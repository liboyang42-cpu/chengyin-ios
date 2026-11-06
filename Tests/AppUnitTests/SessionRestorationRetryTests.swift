import Foundation
import Security
import XCTest
@testable import Questify

/// Isolated new doubles exercise the real AppSession and scoped HTTP adapter.
/// No Keychain, SMS, provider, live backend or existing fixture is touched.
private final class RetrySavedSessionVault: AppTokenStorage {
    var value: String? = "synthetic-saved"
    var error: Error?
    var reads = 0, writes = 0, clears = 0
    func read() throws -> String? {
        reads += 1
        if let error { throw error }
        return value
    }
    func write(_ token: String) throws { writes += 1; value = token }
    func clear() throws { clears += 1; value = nil }
}

private final class RetrySavedSessionWire: HTTPTransport {
    var requests: [URLRequest] = []
    var status = 503, accountID = 7
    var malformed = false, suspendNextRead = false
    var pending: CheckedContinuation<(Data, Int), Error>?
    func accountReply(id: Int? = nil) -> (Data, Int) {
        (Data("{\"code\":200,\"appUser\":{\"id\":\(id ?? accountID),\"role\":\"player\",\"nickname\":\"Read back\"}}".utf8), 200)
    }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        guard let path = request.url?.path else { throw APIError.invalidRequest }
        if path.hasSuffix("/api/userInfo") {
            if suspendNextRead {
                suspendNextRead = false
                return try await withCheckedThrowingContinuation { pending = $0 }
            }
            if status != 200 { return (Data(), status) }
            return malformed ? (Data("{\"code\":200,\"appUser\":{\"id\":7}}".utf8), 200) : accountReply()
        }
        if path.hasSuffix("/api/login/phone") {
            return (Data("{\"code\":200,\"token\":\"synthetic-new-\(accountID)\",\"data\":{\"id\":\(accountID),\"role\":\"player\"}}".utf8), 200)
        }
        if path.hasSuffix("/api/logout") { return (Data("{\"code\":200}".utf8), 200) }
        XCTFail("Recovery must never send SMS or use another route: \(path)")
        throw APIError.invalidRequest
    }
}

@MainActor final class SessionRestorationRetryAppTests: XCTestCase {
    private struct Harness {
        let root: AppCompositionRoot
        let session: AppSession
        let deployment: ReviewedAppDeployment
        let defaults: UserDefaults
        let vault: RetrySavedSessionVault
        let wire: RetrySavedSessionWire
    }
    private func harness() throws -> Harness {
        let suite = "saved-session-retry-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let deployment = try ReviewedAppDeployment(market: .china,
            baseURL: "https://example.test/restore", approvedBaseURLs: [.china: ["https://example.test/restore"]],
            verifiedCapabilities: [.domesticChinaPhone], bundleIdentifier: "test.restore.retry", realm: "offline")
        let vault = RetrySavedSessionVault(), wire = RetrySavedSessionWire()
        let root = AppCompositionRoot(deployment: .reviewed(deployment),
            storage: AppScopedStorageFactory(defaults: defaults, tokenStore: { _ in vault }), makeTransport: { wire })
        return Harness(root: root, session: root.makeSession(), deployment: deployment,
                       defaults: defaults, vault: vault, wire: wire)
    }
    private func waitForPending(_ wire: RetrySavedSessionWire) async throws -> CheckedContinuation<(Data, Int), Error> {
        for _ in 0..<1_000 { if wire.pending != nil { break }; await Task.yield() }
        return try XCTUnwrap(wire.pending)
    }
    private func seedUnknown(_ h: Harness) throws -> (OperationDefaultsJournal, OperationPendingRecord) {
        let owner = "registration|\(h.deployment.storageScope.service)|CN|https://example.test/restore|7"
        let record = OperationPendingRecord(ownerKey: owner, targetKey: "create|10|20")
        let journal = OperationDefaultsJournal(defaults: h.defaults)
        try journal.write(record)
        return (journal, record)
    }
    private func assertOnlyRestorationReads(_ h: Harness, count: Int, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(h.wire.requests.count, count, file: file, line: line)
        for request in h.wire.requests {
            XCTAssertEqual(request.url?.path, "/restore/api/userInfo", file: file, line: line)
            XCTAssertEqual(request.httpMethod, "POST", file: file, line: line)
            XCTAssertNil(request.httpBody, file: file, line: line)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic-saved", file: file, line: line)
        }
        XCTAssertEqual(h.vault.writes, 0, file: file, line: line)
    }

    func testTransientColdRestoreOffersOnlyExplicitReadAndPreservesUnknown() async throws {
        let h = try harness()
        let (journal, unknown) = try seedUnknown(h)
        await h.session.bootstrap()
        XCTAssertTrue(h.session.canRetrySessionRestoration); XCTAssertNil(h.session.account)
        XCTAssertEqual(h.session.errorKey, "auth.networkError"); XCTAssertEqual(h.vault.value, "synthetic-saved")
        await h.session.bootstrap()
        XCTAssertEqual(h.wire.requests.count, 1, "bootstrap remains one-shot; there is no automatic retry")
        h.wire.status = 200
        let attempt = try XCTUnwrap(h.session.prepareSessionRestorationRetry())
        XCTAssertTrue(h.session.isWorking); XCTAssertFalse(h.session.canRetrySessionRestoration)
        await h.session.retrySessionRestoration(attempt)
        XCTAssertEqual(h.session.account?.id, 7); XCTAssertEqual(h.session.account?.nickname, "Read back")
        XCTAssertNil(h.session.errorKey); XCTAssertFalse(h.session.isWorking)
        XCTAssertFalse(h.session.canRetrySessionRestoration)
        assertOnlyRestorationReads(h, count: 2)
        XCTAssertEqual(h.vault.clears, 0)
        XCTAssertEqual(try journal.pending(ownerKey: unknown.ownerKey, targetKey: unknown.targetKey), unknown)
    }

    func testKeychainTemporarilyLockedRetriesReadWithoutChangingAccessOrCredential() async throws {
        let h = try harness()
        h.vault.error = KeychainTokenStore.StoreError.status(errSecInteractionNotAllowed)
        await h.session.bootstrap()
        XCTAssertTrue(h.session.canRetrySessionRestoration); XCTAssertTrue(h.wire.requests.isEmpty)
        XCTAssertEqual(h.session.errorKey, "auth.storageError"); XCTAssertEqual(h.vault.clears, 0)
        h.vault.error = nil; h.wire.status = 200
        await h.session.retrySessionRestoration(try XCTUnwrap(h.session.prepareSessionRestorationRetry()))
        XCTAssertEqual(h.vault.reads, 2); XCTAssertEqual(h.session.account?.id, 7)
        assertOnlyRestorationReads(h, count: 1); XCTAssertEqual(h.vault.clears, 0)
    }

    func testAbsentInvalidUnauthorizedUpgradeOrMalformedCredentialDoesNotOfferRetry() async throws {
        for kind in 0..<5 {
            let h = try harness()
            switch kind {
            case 0: h.vault.value = nil
            case 1: h.vault.error = KeychainTokenStore.StoreError.invalidToken
            case 2: h.wire.status = 401
            case 3: h.wire.status = 426
            default: h.wire.status = 200; h.wire.malformed = true
            }
            await h.session.bootstrap()
            XCTAssertFalse(h.session.canRetrySessionRestoration)
            XCTAssertNil(h.session.prepareSessionRestorationRetry())
            XCTAssertNil(h.session.account); XCTAssertEqual(h.vault.writes, 0)
            XCTAssertEqual(h.vault.clears, kind == 2 ? 1 : 0)
            XCTAssertEqual(h.defaults.bool(forKey: h.deployment.storageScope.restoreBlockedKey), kind == 2)
        }
        let unconfigured = AppSession()
        await unconfigured.bootstrap()
        XCTAssertNil(unconfigured.prepareSessionRestorationRetry())
    }

    func testDuplicatePreparationAndTaskExecutionReadOnlyOnce() async throws {
        let h = try harness(); await h.session.bootstrap()
        h.wire.status = 200; h.wire.suspendNextRead = true
        let attempt = try XCTUnwrap(h.session.prepareSessionRestorationRetry())
        XCTAssertNil(h.session.prepareSessionRestorationRetry())
        let first = Task { await h.session.retrySessionRestoration(attempt) }
        let pending = try await waitForPending(h.wire)
        await h.session.retrySessionRestoration(attempt)
        assertOnlyRestorationReads(h, count: 2)
        XCTAssertTrue(h.session.isWorking)
        pending.resume(returning: h.wire.accountReply()); h.wire.pending = nil
        await first.value
        await h.session.retrySessionRestoration(attempt)
        assertOnlyRestorationReads(h, count: 2); XCTAssertEqual(h.session.account?.id, 7)
    }

    func testCloseBeforeQueuedReadDispatchAndExplicitReentry() async throws {
        let h = try harness(); await h.session.bootstrap()
        let old = try XCTUnwrap(h.session.prepareSessionRestorationRetry())
        h.session.cancelPendingLogin()
        await h.session.retrySessionRestoration(old)
        assertOnlyRestorationReads(h, count: 1)
        XCTAssertTrue(h.session.canRetrySessionRestoration)
        h.wire.status = 200
        let fresh = try XCTUnwrap(h.session.prepareSessionRestorationRetry())
        XCTAssertNotEqual(old, fresh)
        h.session.cancelSessionRestorationRetry(old)
        XCTAssertTrue(h.session.isWorking, "Old view departure cannot cancel the new attempt")
        await h.session.retrySessionRestoration(fresh)
        XCTAssertEqual(h.session.account?.id, 7); assertOnlyRestorationReads(h, count: 2)
    }

    func testTaskCancellationBeforeReadPreservesCredentialAndOffersExplicitRetry() async throws {
        let h = try harness(); await h.session.bootstrap()
        let attempt = try XCTUnwrap(h.session.prepareSessionRestorationRetry())
        let task = Task { await h.session.retrySessionRestoration(attempt) }
        task.cancel(); await task.value
        assertOnlyRestorationReads(h, count: 1)
        XCTAssertTrue(h.session.canRetrySessionRestoration); XCTAssertFalse(h.session.isWorking)
        XCTAssertEqual(h.vault.value, "synthetic-saved"); XCTAssertEqual(h.vault.clears, 0)
    }

    func testCancelledColdBootstrapCanRecoverWithoutAutomaticRerun() async throws {
        let h = try harness(); h.wire.suspendNextRead = true
        let task = Task { await h.session.bootstrap() }
        let pending = try await waitForPending(h.wire)
        task.cancel(); pending.resume(returning: h.wire.accountReply()); h.wire.pending = nil
        await task.value
        XCTAssertNil(h.session.account); XCTAssertTrue(h.session.canRetrySessionRestoration)
        XCTAssertEqual(h.vault.clears, 0)
        h.wire.status = 200
        await h.session.retrySessionRestoration(try XCTUnwrap(h.session.prepareSessionRestorationRetry()))
        XCTAssertEqual(h.session.account?.id, 7); assertOnlyRestorationReads(h, count: 2)
    }

    func testLateRetrySuccessOr401CannotReplaceNewPhoneLogin() async throws {
        for unauthorized in [false, true] {
            let h = try harness(); await h.session.bootstrap()
            h.wire.suspendNextRead = true
            let old = try XCTUnwrap(h.session.prepareSessionRestorationRetry())
            let task = Task { await h.session.retrySessionRestoration(old) }
            let pending = try await waitForPending(h.wire)
            h.session.cancelSessionRestorationRetry(old)
            h.wire.accountID = 8; h.wire.status = 200
            await h.session.authChannels.loginWithPhone(phone: "10000000000", code: "123456")
            XCTAssertEqual(h.session.account?.id, 8)
            let result: (Data, Int) = unauthorized ? (Data(), 401) : h.wire.accountReply(id: 7)
            pending.resume(returning: result); h.wire.pending = nil
            await task.value
            XCTAssertEqual(h.session.account?.id, 8); XCTAssertEqual(h.vault.value, "synthetic-new-8")
            XCTAssertEqual(h.vault.writes, 1); XCTAssertEqual(h.vault.clears, 0)
            XCTAssertFalse(h.session.canRetrySessionRestoration); XCTAssertNil(h.session.errorKey)
            XCTAssertFalse(h.defaults.bool(forKey: h.deployment.storageScope.restoreBlockedKey))
        }
    }

    func testLogoutDuringRetryWinsAgainstLateSuccessAndColdRestart() async throws {
        let h = try harness(); await h.session.bootstrap(); h.wire.suspendNextRead = true
        let attempt = try XCTUnwrap(h.session.prepareSessionRestorationRetry())
        let task = Task { await h.session.retrySessionRestoration(attempt) }
        let pending = try await waitForPending(h.wire)
        await h.session.logout()
        pending.resume(returning: h.wire.accountReply()); h.wire.pending = nil
        await task.value
        XCTAssertNil(h.session.account); XCTAssertNil(h.vault.value)
        XCTAssertFalse(h.session.canRetrySessionRestoration)
        XCTAssertTrue(h.defaults.bool(forKey: h.deployment.storageScope.restoreBlockedKey))
        let count = h.wire.requests.count
        await h.root.makeSession().bootstrap()
        XCTAssertEqual(h.wire.requests.count, count)
    }

    func testRetry401ClearsOnlyScopedTokenAndPreservesOriginalUnknown() async throws {
        let h = try harness()
        let (journal, unknown) = try seedUnknown(h)
        await h.session.bootstrap(); h.wire.status = 401
        await h.session.retrySessionRestoration(try XCTUnwrap(h.session.prepareSessionRestorationRetry()))
        XCTAssertEqual(h.session.errorKey, "auth.expired"); XCTAssertNil(h.vault.value)
        XCTAssertEqual(h.vault.clears, 1); XCTAssertFalse(h.session.canRetrySessionRestoration)
        XCTAssertTrue(h.defaults.bool(forKey: h.deployment.storageScope.restoreBlockedKey))
        XCTAssertEqual(try journal.pending(ownerKey: unknown.ownerKey, targetKey: unknown.targetKey), unknown)
        assertOnlyRestorationReads(h, count: 2)
    }

    func testSecondTransientFailureRetainsCredentialBut426StopsOfferingRetry() async throws {
        let h = try harness(); await h.session.bootstrap()
        await h.session.retrySessionRestoration(try XCTUnwrap(h.session.prepareSessionRestorationRetry()))
        XCTAssertTrue(h.session.canRetrySessionRestoration)
        XCTAssertEqual(h.vault.value, "synthetic-saved"); XCTAssertEqual(h.vault.clears, 0)
        h.wire.status = 426
        await h.session.retrySessionRestoration(try XCTUnwrap(h.session.prepareSessionRestorationRetry()))
        XCTAssertFalse(h.session.canRetrySessionRestoration)
        XCTAssertEqual(h.session.errorKey, "auth.channels.upgradeRequired")
        XCTAssertEqual(h.vault.value, "synthetic-saved"); assertOnlyRestorationReads(h, count: 3)
    }

    func testPolicyDoesNotTurnMalformedOrAuthorizationFailuresIntoRefresh() {
        XCTAssertTrue(SessionRestorationRetryPolicy.permits(URLError(.notConnectedToInternet)))
        XCTAssertTrue(SessionRestorationRetryPolicy.permits(CancellationError()))
        XCTAssertTrue(SessionRestorationRetryPolicy.permits(APIError.httpStatus(503)))
        XCTAssertTrue(SessionRestorationRetryPolicy.permits(KeychainTokenStore.StoreError.status(errSecInteractionNotAllowed)))
        for error in [APIError.unauthorized, .notConfigured, .invalidRequest, .malformedResponse, .httpStatus(426), .businessCode(503)] {
            XCTAssertFalse(SessionRestorationRetryPolicy.permits(error))
        }
        XCTAssertFalse(SessionRestorationRetryPolicy.permits(KeychainTokenStore.StoreError.invalidToken))
        XCTAssertFalse(SessionRestorationRetryPolicy.permits(KeychainTokenStore.StoreError.unconfigured))
    }
}

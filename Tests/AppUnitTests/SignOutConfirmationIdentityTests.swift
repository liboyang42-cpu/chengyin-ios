import Foundation
import XCTest
@testable import Questify

/// Real AppSession, scoped auth transport and synthetic vault. No live logout is sent.
private final class ConfirmedSignOutVault: AppTokenStorage {
    var value: String? = "synthetic-7"
    var failClear = false
    var clears = 0, writes = 0
    func read() throws -> String? { value }
    func write(_ token: String) throws { value = token; writes += 1 }
    func clear() throws {
        clears += 1
        if failClear { throw CocoaError(.fileWriteUnknown) }
        value = nil
    }
}
private final class ConfirmedSignOutWire: HTTPTransport {
    var accountID = 7
    var requests: [URLRequest] = []
    var suspendNextLogout = false
    var pending: CheckedContinuation<(Data, Int), Error>?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        guard let path = request.url?.path else { throw APIError.invalidRequest }
        if path.hasSuffix("/api/userInfo") {
            return (Data("{\"code\":200,\"appUser\":{\"id\":\(accountID),\"role\":\"player\"}}".utf8), 200)
        }
        if path.hasSuffix("/api/login/phone") {
            return (Data("{\"code\":200,\"token\":\"synthetic-\(accountID)\",\"data\":{\"id\":\(accountID),\"role\":\"player\"}}".utf8), 200)
        }
        guard path.hasSuffix("/api/logout") else {
            XCTFail("Unexpected route: \(path)"); throw APIError.invalidRequest
        }
        if suspendNextLogout {
            suspendNextLogout = false
            return try await withCheckedThrowingContinuation { pending = $0 }
        }
        return (Data("{\"code\":200}".utf8), 200)
    }
}

@MainActor final class SignOutConfirmationIdentityTests: XCTestCase {
    private struct Harness {
        let root: AppCompositionRoot
        let session: AppSession
        let defaults: UserDefaults
        let deployment: ReviewedAppDeployment
        let vault: ConfirmedSignOutVault
        let wire: ConfirmedSignOutWire
    }
    private func harness() async throws -> Harness {
        let suite = "signout-confirmation-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let endpoint = "https://example.test/signout"
        let deployment = try ReviewedAppDeployment(market: .china, baseURL: endpoint,
            approvedBaseURLs: [.china: [endpoint]], verifiedCapabilities: [.domesticChinaPhone],
            bundleIdentifier: "test.signout.confirmation", realm: "synthetic")
        let wire = ConfirmedSignOutWire(), vault = ConfirmedSignOutVault()
        let root = AppCompositionRoot(deployment: .reviewed(deployment),
            storage: .init(defaults: defaults, tokenStore: { _ in vault }), makeTransport: { wire })
        let session = root.makeSession(); await session.bootstrap()
        XCTAssertEqual(session.account?.id, 7)
        return Harness(root: root, session: session, defaults: defaults, deployment: deployment, vault: vault, wire: wire)
    }
    private func pending(_ h: Harness) async throws -> CheckedContinuation<(Data, Int), Error> {
        for _ in 0..<1_000 { if h.wire.pending != nil { break }; await Task.yield() }
        return try XCTUnwrap(h.wire.pending)
    }
    private func login(_ h: Harness, accountID: Int) async {
        h.wire.accountID = accountID
        await h.session.authChannels.loginWithPhone(phone: "10000000000", code: "123456")
        XCTAssertEqual(h.session.account?.id, accountID)
    }
    private func logoutCount(_ h: Harness) -> Int {
        h.wire.requests.filter { $0.url?.lastPathComponent == "logout" }.count
    }

    func testOnlyRenderedCurrentAccountCanPrepareAConfirmation() async throws {
        let h = try await harness()
        XCTAssertNil(h.session.signOutConfirmation(accountID: 8))
        XCTAssertNil(h.session.signOutConfirmation(accountID: 0))
        XCTAssertEqual(h.session.signOutConfirmation(accountID: 7), h.session.authChannelSnapshot)
        await h.session.logout()
        XCTAssertNil(h.session.signOutConfirmation(accountID: 7))
    }

    func testMatchingConfirmationClosesLocallyBeforeBestEffortRemoteFailure() async throws {
        let h = try await harness()
        let expected = try XCTUnwrap(h.session.signOutConfirmation(accountID: 7))
        h.wire.suspendNextLogout = true
        let task = Task { await h.session.logout(matching: expected) }
        let remote = try await pending(h)
        XCTAssertNil(h.session.account); XCTAssertNil(h.vault.value)
        XCTAssertTrue(h.defaults.bool(forKey: h.deployment.storageScope.restoreBlockedKey))
        XCTAssertEqual(h.wire.requests.last?.value(forHTTPHeaderField: "Authorization"), "synthetic-7")
        XCTAssertEqual(h.wire.requests.last?.httpMethod, "POST")
        remote.resume(returning: (Data(), 503)); h.wire.pending = nil
        let canDismiss = await task.value
        XCTAssertTrue(canDismiss, "Remote failure cannot undo the existing local-first logout")
        XCTAssertEqual(logoutCount(h), 1); XCTAssertEqual(h.vault.clears, 1)
    }

    func testOldConfirmationCannotSignOutReplacementOrSameAccountRelogin() async throws {
        for nextID in [7, 8] {
            let h = try await harness()
            let expected = try XCTUnwrap(h.session.signOutConfirmation(accountID: 7))
            await h.session.logout(); await login(h, accountID: nextID)
            let requests = h.wire.requests.count, clears = h.vault.clears
            let canDismiss = await h.session.logout(matching: expected)
            XCTAssertFalse(canDismiss); XCTAssertEqual(h.wire.requests.count, requests)
            XCTAssertEqual(h.vault.clears, clears); XCTAssertEqual(h.session.account?.id, nextID)
            XCTAssertEqual(h.vault.value, "synthetic-\(nextID)")
            XCTAssertFalse(h.defaults.bool(forKey: h.deployment.storageScope.restoreBlockedKey))
        }
    }

    func testQueuedConfirmationTaskCannotActAfterAnotherLogout() async throws {
        let h = try await harness()
        let expected = try XCTUnwrap(h.session.signOutConfirmation(accountID: 7))
        let queued = Task { await h.session.logout(matching: expected) }
        // The direct logout closes the original session synchronously before its network await.
        await h.session.logout()
        let canDismiss = await queued.value
        XCTAssertFalse(canDismiss); XCTAssertEqual(logoutCount(h), 1)
        XCTAssertEqual(h.vault.clears, 1)
    }

    func testDuplicateConfirmationCannotDuplicateRemoteRevocation() async throws {
        let h = try await harness()
        let expected = try XCTUnwrap(h.session.signOutConfirmation(accountID: 7))
        h.wire.suspendNextLogout = true
        let first = Task { await h.session.logout(matching: expected) }
        let remote = try await pending(h)
        let duplicate = await h.session.logout(matching: expected)
        XCTAssertFalse(duplicate); XCTAssertEqual(logoutCount(h), 1)
        remote.resume(returning: (Data("{\"code\":200}".utf8), 200)); h.wire.pending = nil
        let canDismiss = await first.value; XCTAssertTrue(canDismiss)
    }

    func testLateRemoteCompletionCannotDismissReplacementAccountPresentation() async throws {
        for nextID in [7, 8] {
            let h = try await harness()
            let expected = try XCTUnwrap(h.session.signOutConfirmation(accountID: 7))
            h.wire.suspendNextLogout = true
            var dismissals = 0
            let first = Task {
                if await h.session.logout(matching: expected) { dismissals += 1 }
            }
            let remote = try await pending(h)
            await login(h, accountID: nextID)
            remote.resume(returning: (Data(), 401)); h.wire.pending = nil
            await first.value
            XCTAssertEqual(dismissals, 0); XCTAssertEqual(h.session.account?.id, nextID)
            XCTAssertEqual(h.vault.value, "synthetic-\(nextID)")
            XCTAssertNil(h.session.errorKey); XCTAssertEqual(logoutCount(h), 1)
            let revoked = h.wire.requests.first { $0.url?.lastPathComponent == "logout" }
            XCTAssertEqual(revoked?.value(forHTTPHeaderField: "Authorization"), "synthetic-7")
        }
    }

    func testGuestEpochABAAlsoSuppressesOldPresentationCallback() async throws {
        let h = try await harness()
        let expected = try XCTUnwrap(h.session.signOutConfirmation(accountID: 7))
        h.wire.suspendNextLogout = true
        let first = Task { await h.session.logout(matching: expected) }
        let remote = try await pending(h)
        await login(h, accountID: 8); await h.session.logout()
        XCTAssertNil(h.session.account)
        remote.resume(returning: (Data("{\"code\":200}".utf8), 200)); h.wire.pending = nil
        let canDismiss = await first.value
        XCTAssertFalse(canDismiss, "A later guest session is not the original logout result")
        XCTAssertEqual(logoutCount(h), 2)
    }

    func testCancelledQueuedConfirmationDoesNotMutateLocalOrRemoteSession() async throws {
        let h = try await harness()
        let expected = try XCTUnwrap(h.session.signOutConfirmation(accountID: 7))
        let task = Task { await h.session.logout(matching: expected) }
        task.cancel()
        let canDismiss = await task.value
        XCTAssertFalse(canDismiss); XCTAssertEqual(h.session.account?.id, 7)
        XCTAssertEqual(h.vault.value, "synthetic-7"); XCTAssertEqual(h.vault.clears, 0)
        XCTAssertEqual(logoutCount(h), 0)
    }

    func testKeychainClearFailureStillClosesLocallyAndTombstonesColdRestore() async throws {
        let h = try await harness()
        let expected = try XCTUnwrap(h.session.signOutConfirmation(accountID: 7))
        h.vault.failClear = true
        let canDismiss = await h.session.logout(matching: expected)
        XCTAssertTrue(canDismiss); XCTAssertNil(h.session.account)
        XCTAssertEqual(h.vault.value, "synthetic-7"); XCTAssertEqual(h.session.errorKey, "auth.storageError")
        XCTAssertTrue(h.defaults.bool(forKey: h.deployment.storageScope.restoreBlockedKey))
        let count = h.wire.requests.count
        await h.root.makeSession().bootstrap()
        XCTAssertEqual(h.wire.requests.count, count)
    }

    func testConfirmedLogoutPreservesOriginalUnknownBusinessRecord() async throws {
        let h = try await harness()
        let owner = "registration|\(h.deployment.storageScope.service)|CN|https://example.test/signout|7"
        let record = OperationPendingRecord(ownerKey: owner, targetKey: "create|10|20")
        let journal = OperationDefaultsJournal(defaults: h.defaults); try journal.write(record)
        let expected = try XCTUnwrap(h.session.signOutConfirmation(accountID: 7))
        _ = await h.session.logout(matching: expected)
        XCTAssertEqual(try journal.pending(ownerKey: owner, targetKey: record.targetKey), record)
        XCTAssertEqual(logoutCount(h), 1)
    }
}

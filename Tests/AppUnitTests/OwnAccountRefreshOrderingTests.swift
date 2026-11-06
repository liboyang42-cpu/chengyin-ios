import Foundation
import XCTest
@testable import Questify

/// Real host/composition/account reader with new synthetic, continuation-controlled HTTP.
/// The existing profile save and its fixtures are not changed or invoked against a backend.
private final class OrderedAccountVault: AppTokenStorage {
    var value: String? = "synthetic-7"
    var writes = 0, clears = 0
    func read() throws -> String? { value }
    func write(_ token: String) throws { value = token; writes += 1 }
    func clear() throws { value = nil; clears += 1 }
}

private final class OrderedAccountWire: HTTPTransport {
    var accountID = 7
    var requests: [URLRequest] = []
    var readCount = 0
    var deferred = false
    var pending: [Int: CheckedContinuation<(Data, Int), Error>] = [:]
    func reply(id: Int = 7, role: String = "player", nickname: String = "Initial") -> (Data, Int) {
        (Data("{\"code\":200,\"appUser\":{\"id\":\(id),\"role\":\"\(role)\",\"nickname\":\"\(nickname)\"}}".utf8), 200)
    }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        guard let path = request.url?.path else { throw APIError.invalidRequest }
        if path.hasSuffix("/api/userInfo") {
            let index = readCount; readCount += 1
            if deferred { return try await withCheckedThrowingContinuation { pending[index] = $0 } }
            return reply(id: accountID)
        }
        if path.hasSuffix("/api/login/phone") {
            return (Data("{\"code\":200,\"token\":\"synthetic-\(accountID)\",\"data\":{\"id\":\(accountID),\"role\":\"player\"}}".utf8), 200)
        }
        if path.hasSuffix("/api/logout") { return (Data("{\"code\":200}".utf8), 200) }
        XCTFail("Unexpected operation: \(path)"); throw APIError.invalidRequest
    }
}

@MainActor final class OwnAccountRefreshOrderingTests: XCTestCase {
    private struct Harness {
        let session: AppSession
        let defaults: UserDefaults
        let deployment: ReviewedAppDeployment
        let vault: OrderedAccountVault
        let wire: OrderedAccountWire
    }
    private func harness() async throws -> Harness {
        let suite = "own-account-refresh-order-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let endpoint = "https://example.test/refresh-order"
        let deployment = try ReviewedAppDeployment(market: .china, baseURL: endpoint,
            approvedBaseURLs: [.china: [endpoint]], verifiedCapabilities: [.domesticChinaPhone],
            bundleIdentifier: "test.own-account-refresh", realm: "synthetic")
        let wire = OrderedAccountWire(), vault = OrderedAccountVault()
        let session = AppCompositionRoot(deployment: .reviewed(deployment),
            storage: .init(defaults: defaults, tokenStore: { _ in vault }), makeTransport: { wire }).makeSession()
        await session.bootstrap()
        XCTAssertEqual(session.account?.id, 7); XCTAssertEqual(wire.readCount, 1)
        return Harness(session: session, defaults: defaults, deployment: deployment, vault: vault, wire: wire)
    }
    private func waiting(_ index: Int, in wire: OrderedAccountWire) async throws {
        for _ in 0..<1_000 { if wire.pending[index] != nil { return }; await Task.yield() }
        XCTFail("Expected suspended account read \(index)")
        throw APIError.malformedResponse
    }
    private func finish(_ index: Int, in wire: OrderedAccountWire, result: (Data, Int)) throws {
        try XCTUnwrap(wire.pending.removeValue(forKey: index)).resume(returning: result)
    }

    func testQueuedSaveReadCannotFollowLogoutOrSameAccountRelogin() async throws {
        for nextID in [7, 8] {
            let h = try await harness()
            let original = try XCTUnwrap(h.session.prepareOwnAccountRefresh())
            await h.session.logout()
            h.wire.accountID = nextID
            await h.session.authChannels.loginWithPhone(phone: "10000000000", code: "123456")
            XCTAssertEqual(h.session.account?.id, nextID)
            let count = h.wire.requests.count
            await original()
            XCTAssertEqual(h.wire.requests.count, count, "Original save cannot read a replacement account, including epoch ABA")
            XCTAssertEqual(h.session.account?.id, nextID)
            XCTAssertEqual(h.vault.value, "synthetic-\(nextID)")
        }
    }

    func testNewerQueuedIntentRetiresOldBeforeEitherTaskDispatches() async throws {
        let h = try await harness()
        let old = try XCTUnwrap(h.session.prepareOwnAccountRefresh())
        let fresh = try XCTUnwrap(h.session.prepareOwnAccountRefresh())
        await old(); XCTAssertEqual(h.wire.readCount, 1)
        await fresh(); XCTAssertEqual(h.wire.readCount, 2)
        await fresh(); XCTAssertEqual(h.wire.readCount, 2, "The captured read is one-shot")
        XCTAssertEqual(h.vault.writes, 0); XCTAssertEqual(h.vault.clears, 0)
    }

    func testDuplicateExecutionWhileOriginalReadIsPendingCannotDispatchAgain() async throws {
        let h = try await harness(); h.wire.deferred = true
        let refresh = try XCTUnwrap(h.session.prepareOwnAccountRefresh())
        let first = Task { await refresh() }
        try await waiting(1, in: h.wire)
        await refresh(); XCTAssertEqual(h.wire.readCount, 2)
        try finish(1, in: h.wire, result: h.wire.reply(nickname: "Updated")); await first.value
        XCTAssertEqual(h.session.account?.nickname, "Updated")
    }

    func testOlderSameRoleResponseCannotOverwriteNewerNickname() async throws {
        let h = try await harness(); h.wire.deferred = true
        let old = Task { await h.session.refreshOwnAccount() }
        try await waiting(1, in: h.wire)
        let fresh = Task { await h.session.refreshOwnAccount() }
        try await waiting(2, in: h.wire)
        try finish(2, in: h.wire, result: h.wire.reply(nickname: "Newest")); await fresh.value
        try finish(1, in: h.wire, result: h.wire.reply(nickname: "Stale")); await old.value
        XCTAssertEqual(h.session.account?.nickname, "Newest")
        XCTAssertEqual(h.session.account?.role, "player")
        XCTAssertEqual(h.vault.writes, 0); XCTAssertEqual(h.vault.clears, 0)
    }

    func testOlderRoleResponseReturningFirstCannotInvalidateNewerRoleRead() async throws {
        let h = try await harness(); h.wire.deferred = true
        let old = Task { await h.session.refreshOwnAccount() }
        try await waiting(1, in: h.wire)
        let fresh = Task { await h.session.refreshOwnAccount() }
        try await waiting(2, in: h.wire)
        try finish(1, in: h.wire, result: h.wire.reply(role: "merchant", nickname: "Stale role")); await old.value
        XCTAssertEqual(h.session.account?.role, "player", "Old read cannot alter the viewer captured by the newer request")
        try finish(2, in: h.wire, result: h.wire.reply(role: "club", nickname: "Current role")); await fresh.value
        XCTAssertEqual(h.session.account?.role, "club")
        XCTAssertEqual(h.session.currentRuntimeDependencyContext?.role, "club")
        XCTAssertEqual(h.session.currentRuntimeDependencyContext?.session.role, "club")
    }

    func testSuperseded401CannotExpireAccountWhileNewerReadIsPending() async throws {
        let h = try await harness(); h.wire.deferred = true
        let old = Task { await h.session.refreshOwnAccount() }
        try await waiting(1, in: h.wire)
        let fresh = Task { await h.session.refreshOwnAccount() }
        try await waiting(2, in: h.wire)
        try finish(1, in: h.wire, result: (Data(), 401)); await old.value
        XCTAssertEqual(h.session.account?.id, 7); XCTAssertEqual(h.vault.clears, 0)
        XCTAssertFalse(h.defaults.bool(forKey: h.deployment.storageScope.restoreBlockedKey))
        try finish(2, in: h.wire, result: h.wire.reply(nickname: "Current")); await fresh.value
        XCTAssertEqual(h.session.account?.nickname, "Current"); XCTAssertNil(h.session.errorKey)
    }

    func testNewest401StillExpiresMatchingSessionAndPreservesUnknownJournal() async throws {
        let h = try await harness()
        let owner = "registration|\(h.deployment.storageScope.service)|CN|https://example.test/refresh-order|7"
        let record = OperationPendingRecord(ownerKey: owner, targetKey: "create|10|20")
        let journal = OperationDefaultsJournal(defaults: h.defaults); try journal.write(record)
        h.wire.deferred = true
        let task = Task { await h.session.refreshOwnAccount() }
        try await waiting(1, in: h.wire)
        try finish(1, in: h.wire, result: (Data(), 401)); await task.value
        XCTAssertNil(h.session.account); XCTAssertNil(h.vault.value)
        XCTAssertEqual(h.vault.clears, 1); XCTAssertEqual(h.session.errorKey, "auth.expired")
        XCTAssertTrue(h.defaults.bool(forKey: h.deployment.storageScope.restoreBlockedKey))
        XCTAssertEqual(try journal.pending(ownerKey: owner, targetKey: record.targetKey), record)
    }

    func testOldReadCannotBecomeFallbackAfterNewerTransientFailure() async throws {
        let h = try await harness(); h.wire.deferred = true
        let old = Task { await h.session.refreshOwnAccount() }
        try await waiting(1, in: h.wire)
        let fresh = Task { await h.session.refreshOwnAccount() }
        try await waiting(2, in: h.wire)
        try finish(2, in: h.wire, result: (Data(), 503)); await fresh.value
        try finish(1, in: h.wire, result: h.wire.reply(role: "merchant", nickname: "Stale")); await old.value
        XCTAssertEqual(h.session.account?.nickname, "Initial"); XCTAssertEqual(h.session.account?.role, "player")
        XCTAssertEqual(h.vault.value, "synthetic-7"); XCTAssertEqual(h.vault.clears, 0)
    }

    func testLateFailureAfterLogoutAndNewPhoneLoginCannotClearNewCredential() async throws {
        let h = try await harness(); h.wire.deferred = true
        let task = Task { await h.session.refreshOwnAccount() }
        try await waiting(1, in: h.wire)
        await h.session.logout()
        h.wire.deferred = false; h.wire.accountID = 8
        await h.session.authChannels.loginWithPhone(phone: "10000000000", code: "123456")
        let clears = h.vault.clears
        try finish(1, in: h.wire, result: (Data(), 401)); await task.value
        XCTAssertEqual(h.session.account?.id, 8); XCTAssertEqual(h.vault.value, "synthetic-8")
        XCTAssertEqual(h.vault.clears, clears); XCTAssertNil(h.session.errorKey)
    }

    func testCancelledQueuedOrRunningReadNeverExpiresTheAccount() async throws {
        for running in [false, true] {
            let h = try await harness(); h.wire.deferred = true
            let refresh = try XCTUnwrap(h.session.prepareOwnAccountRefresh())
            let task = Task { await refresh() }
            if running { try await waiting(1, in: h.wire) }
            task.cancel()
            if running { try finish(1, in: h.wire, result: (Data(), 401)) }
            await task.value
            XCTAssertEqual(h.session.account?.id, 7); XCTAssertEqual(h.vault.clears, 0)
            XCTAssertEqual(h.wire.readCount, running ? 2 : 1)
        }
    }

    func testMismatchedOrUnknownRoleProjectionCannotReplaceCurrentAccount() async throws {
        for mismatched in [false, true] {
            let h = try await harness(); h.wire.deferred = true
            let task = Task { await h.session.refreshOwnAccount() }
            try await waiting(1, in: h.wire)
            try finish(1, in: h.wire, result: h.wire.reply(id: mismatched ? 8 : 7,
                role: mismatched ? "player" : "unknown", nickname: "Rejected"))
            await task.value
            XCTAssertEqual(h.session.account?.id, 7); XCTAssertEqual(h.session.account?.nickname, "Initial")
            XCTAssertEqual(h.session.account?.role, "player"); XCTAssertEqual(h.vault.clears, 0)
        }
    }

    func testGuestCannotPrepareARefreshAndNoNewEndpointIsUsed() async throws {
        let h = try await harness(); await h.session.logout()
        let count = h.wire.requests.count
        XCTAssertNil(h.session.prepareOwnAccountRefresh()); await h.session.refreshOwnAccount()
        XCTAssertEqual(h.wire.requests.count, count)
        for request in h.wire.requests where request.url?.lastPathComponent == "userInfo" {
            XCTAssertEqual(request.httpMethod, "POST"); XCTAssertNil(request.httpBody)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic-7")
        }
    }
}

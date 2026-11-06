import Foundation
import XCTest
@testable import Questify

/// Actual App model/coordinator/service/composition with isolated storage and HTTP doubles.
/// No existing fixture is changed and no request leaves this process.
private final class QueuedAuthVault: AppTokenStorage {
    var value: String?
    var writes = 0, clears = 0
    func read() throws -> String? { value }
    func write(_ token: String) throws { value = token; writes += 1 }
    func clear() throws { value = nil; clears += 1 }
}

private final class QueuedAuthTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var accountID = 7
    var userInfoStatus = 200
    var suspendPhone = false
    var pending: CheckedContinuation<(Data, Int), Error>?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        guard let path = request.url?.path else { throw APIError.invalidRequest }
        if path.hasSuffix("/api/login/phone") {
            if suspendPhone { return try await withCheckedThrowingContinuation { pending = $0 } }
            return loginReply()
        }
        if path.hasSuffix("/api/userInfo") {
            if userInfoStatus != 200 { return (Data(), userInfoStatus) }
            return (Data("{\"code\":200,\"appUser\":{\"id\":\(accountID),\"role\":\"player\",\"nickname\":\"Verified\"}}".utf8), 200)
        }
        guard path.hasSuffix("/api/sms/send") || path.hasSuffix("/api/logout") else {
            XCTFail("Unexpected operation: \(path)"); throw APIError.invalidRequest
        }
        return (Data("{\"code\":200}".utf8), 200)
    }
    func loginReply() -> (Data, Int) {
        (Data("{\"code\":200,\"token\":\"synthetic-token-\(accountID)\",\"data\":{\"id\":\(accountID),\"role\":\"player\"}}".utf8), 200)
    }
}

@MainActor final class AuthChannelQueuedIntentAppTests: XCTestCase {
    private func harness() throws -> (AppCompositionRoot, ReviewedAppDeployment, UserDefaults, QueuedAuthVault, QueuedAuthTransport) {
        let suite = "auth-queued-intent-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let deployment = try ReviewedAppDeployment(market: .china,
            baseURL: "https://example.test/queued", approvedBaseURLs: [.china: ["https://example.test/queued"]],
            verifiedCapabilities: [.domesticChinaPhone], bundleIdentifier: "test.auth.queued", realm: "offline")
        let vault = QueuedAuthVault(), transport = QueuedAuthTransport()
        let root = AppCompositionRoot(deployment: .reviewed(deployment),
            storage: AppScopedStorageFactory(defaults: defaults, tokenStore: { _ in vault }),
            makeTransport: { transport })
        return (root, deployment, defaults, vault, transport)
    }
    private func form(_ session: AppSession) -> AuthChannelModel {
        let model = AuthChannelModel(coordinator: session.authChannels)
        model.phone = "10000000000"; model.code = "123456"
        return model
    }
    private func settled(_ model: AuthChannelModel) async {
        for _ in 0..<1_000 {
            if !model.isScheduled { return }
            await Task.yield()
        }
        XCTFail("Queued form operation did not settle")
    }
    private func drainQueuedWork() async {
        // Allow already-enqueued main-actor tasks to enter their cancellation fences.
        for _ in 0..<30 { await Task.yield() }
    }

    func testDuplicateTapThenCloseBeforeTaskStartsNeverDispatches() async throws {
        for sms in [false, true] {
            let (root, _, _, vault, transport) = try harness()
            let session = root.makeSession(), model = form(session)
            if sms { model.sendCode(); model.sendCode() }
            else { model.signIn(); model.code = "654321"; model.signIn() }
            XCTAssertTrue(model.isScheduled); XCTAssertFalse(model.canStart)
            model.clear()
            await drainQueuedWork()
            XCTAssertTrue(transport.requests.isEmpty)
            XCTAssertNil(session.account); XCTAssertEqual(vault.writes, 0)
            XCTAssertNil(vault.value); XCTAssertEqual(session.authChannels.smsCooldownRemaining, 0)
            XCTAssertEqual(model.phone, ""); XCTAssertEqual(model.code, "")
        }
    }

    func testOuterLoginCloseInvalidatesQueuedIntentBeforeChildDisappears() async throws {
        for sms in [false, true] {
            let (root, _, _, vault, transport) = try harness()
            let session = root.makeSession(), model = form(session)
            if sms { model.sendCode() } else { model.signIn() }
            session.cancelPendingLogin() // Existing LoginView Close hook; child clear has not run.
            await settled(model)
            XCTAssertTrue(transport.requests.isEmpty); XCTAssertNil(session.account)
            XCTAssertEqual(vault.writes, 0); XCTAssertNil(model.state.issue)
        }
    }

    func testDuplicateTapCommitsOnceThenColdRestoreUsesOnlyOriginalUserInfo() async throws {
        let (root, deployment, defaults, vault, transport) = try harness()
        let session = root.makeSession(), model = form(session)
        model.signIn(); model.code = "654321"; model.signIn()
        await settled(model)
        XCTAssertEqual(session.account?.id, 7); XCTAssertEqual(session.account?.nickname, "Verified")
        XCTAssertEqual(vault.writes, 1); XCTAssertEqual(vault.value, "synthetic-token-7")
        XCTAssertEqual(transport.requests.map { $0.url?.lastPathComponent }, ["phone", "userInfo"])
        XCTAssertFalse(defaults.bool(forKey: deployment.storageScope.restoreBlockedKey))
        let restored = root.makeSession()
        await restored.bootstrap()
        XCTAssertEqual(restored.account?.id, 7); XCTAssertEqual(vault.writes, 1)
        XCTAssertEqual(transport.requests.map { $0.url?.lastPathComponent }, ["phone", "userInfo", "userInfo"])
        XCTAssertEqual(transport.requests.last?.value(forHTTPHeaderField: "Authorization"), "synthetic-token-7")
    }

    func testQueuedLoginCannotUndoLogoutAndNewExplicitLoginCanSwitchAccount() async throws {
        let (root, deployment, defaults, vault, transport) = try harness()
        let session = root.makeSession(), old = form(session)
        old.signIn()
        await session.logout()
        await settled(old)
        XCTAssertTrue(transport.requests.isEmpty); XCTAssertEqual(vault.writes, 0)
        XCTAssertTrue(defaults.bool(forKey: deployment.storageScope.restoreBlockedKey))
        transport.accountID = 8
        let fresh = form(session); fresh.signIn()
        await settled(fresh)
        XCTAssertEqual(session.account?.id, 8); XCTAssertEqual(vault.value, "synthetic-token-8")
        XCTAssertEqual(vault.writes, 1)
        XCTAssertFalse(defaults.bool(forKey: deployment.storageScope.restoreBlockedKey))
        await session.logout()
        XCTAssertNil(session.account); XCTAssertNil(vault.value)
        XCTAssertEqual(transport.requests.last?.url?.lastPathComponent, "logout")
        XCTAssertEqual(transport.requests.last?.value(forHTTPHeaderField: "Authorization"), "synthetic-token-8")
        let count = transport.requests.count
        await root.makeSession().bootstrap()
        XCTAssertEqual(transport.requests.count, count, "Logout tombstone prevents cold restoration")
    }

    func testCloseDuringOriginalLoginThenReopenRejectsLateOldResponse() async throws {
        let (root, _, _, vault, transport) = try harness()
        let session = root.makeSession(), old = form(session)
        transport.suspendPhone = true; old.signIn()
        for _ in 0..<1_000 { if transport.pending != nil { break }; await Task.yield() }
        let pending = try XCTUnwrap(transport.pending)
        old.clear(); transport.suspendPhone = false; transport.accountID = 8
        let fresh = form(session); fresh.signIn()
        await settled(fresh)
        let count = transport.requests.count
        pending.resume(returning: (Data("{\"code\":200,\"token\":\"synthetic-old\",\"data\":{\"id\":7,\"role\":\"player\"}}".utf8), 200))
        transport.pending = nil
        await drainQueuedWork()
        XCTAssertEqual(session.account?.id, 8); XCTAssertEqual(vault.writes, 1)
        XCTAssertEqual(vault.value, "synthetic-token-8")
        XCTAssertEqual(transport.requests.count, count, "Old token cannot start a userInfo readback")
        XCTAssertNil(session.errorKey); XCTAssertFalse(fresh.isScheduled)
    }

    func testReadbackRevocationNeverPersistsAndExplicitReentryCanRecover() async throws {
        let (root, _, _, vault, transport) = try harness()
        let session = root.makeSession(), model = form(session)
        transport.userInfoStatus = 401; model.signIn()
        await settled(model)
        XCTAssertNil(session.account); XCTAssertNil(vault.value); XCTAssertEqual(vault.writes, 0)
        XCTAssertEqual(model.state.issue, .unauthorized)
        model.clear(); transport.userInfoStatus = 200
        model.phone = "10000000000"; model.code = "654321"; model.signIn()
        await settled(model)
        XCTAssertEqual(session.account?.id, 7); XCTAssertEqual(vault.writes, 1)
    }
}

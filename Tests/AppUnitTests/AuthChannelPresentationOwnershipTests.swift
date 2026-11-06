import Foundation
import XCTest
@testable import Questify

/// Independent doubles exercise the real form/coordinator/composition. No SDK or network work.
private final class PresentationFormVault: AppTokenStorage {
    var value: String?
    var writes = 0
    func read() throws -> String? { value }
    func write(_ token: String) throws { value = token; writes += 1 }
    func clear() throws { value = nil }
}
private final class PresentationFormTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var accountID = 7, currentStatus = 200
    var holdPhone = false
    var pending: CheckedContinuation<(Data, Int), Error>?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        guard let path = request.url?.path else { throw APIError.invalidRequest }
        if path.hasSuffix("/api/login/phone") {
            if holdPhone { return try await withCheckedThrowingContinuation { pending = $0 } }
            return loginReply()
        }
        if path.hasSuffix("/api/userInfo") {
            if currentStatus != 200 { return (Data(), currentStatus) }
            return (Data("{\"code\":200,\"appUser\":{\"id\":\(accountID),\"role\":\"player\",\"nickname\":\"Verified\"}}".utf8), 200)
        }
        guard path.hasSuffix("/api/sms/send") || path.hasSuffix("/api/logout") else {
            XCTFail("Unexpected route: \(path)"); throw APIError.invalidRequest
        }
        return (Data("{\"code\":200}".utf8), 200)
    }
    func loginReply() -> (Data, Int) {
        (Data("{\"code\":200,\"token\":\"synthetic-token-\(accountID)\",\"data\":{\"id\":\(accountID),\"role\":\"player\"}}".utf8), 200)
    }
}
@MainActor private final class PresentationAppleService: AuthChannelServing {
    var exchanges = 0
    func sendSMSCode(phone: String) async throws { XCTFail("Unexpected SMS") }
    func loginWithPhone(phone: String, code: String) async throws -> LoginResult { throw APIError.notConfigured }
    func loginWithApple(identityToken: String) async throws -> LoginResult {
        exchanges += 1
        return LoginResult(token: "synthetic-apple", account: try await currentAccount(token: "synthetic-apple"))
    }
    func currentAccount(token: String) async throws -> Account {
        try JSONDecoder().decode(Account.self, from: Data("{\"id\":7,\"role\":\"player\"}".utf8))
    }
}

@MainActor final class AuthChannelPresentationOwnershipAppTests: XCTestCase {
    private func harness() throws -> (AppSession, PresentationFormVault, PresentationFormTransport) {
        let suite = "auth-form-owner-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let deployment = try ReviewedAppDeployment(market: .china,
            baseURL: "https://example.test/form-owner", approvedBaseURLs: [.china: ["https://example.test/form-owner"]],
            verifiedCapabilities: [.domesticChinaPhone], bundleIdentifier: "test.auth.form-owner", realm: "offline")
        let vault = PresentationFormVault(), transport = PresentationFormTransport()
        let root = AppCompositionRoot(deployment: .reviewed(deployment),
            storage: AppScopedStorageFactory(defaults: defaults, tokenStore: { _ in vault }),
            makeTransport: { transport })
        return (root.makeSession(), vault, transport)
    }
    private func form(_ session: AppSession) -> AuthChannelModel {
        let model = AuthChannelModel(coordinator: session.authChannels)
        model.phone = "10000000000"; model.code = "123456"
        return model
    }
    private func settled(_ model: AuthChannelModel) async {
        for _ in 0..<1_000 { if !model.isScheduled { return }; await Task.yield() }
        XCTFail("Form work did not settle")
    }
    private func drain() async { for _ in 0..<30 { await Task.yield() } }

    func testDelayedOldDisappearCannotCancelFreshQueuedLogin() async throws {
        let (session, vault, transport) = try harness()
        let old = form(session), fresh = form(session)
        fresh.signIn(); old.clear(); old.clear()
        await settled(fresh)
        XCTAssertEqual(session.account?.id, 7); XCTAssertEqual(vault.writes, 1)
        XCTAssertEqual(transport.requests.map { $0.url?.lastPathComponent }, ["phone", "userInfo"])
        XCTAssertEqual(old.phone, ""); XCTAssertEqual(old.code, "")
        XCTAssertTrue(fresh.state.signedIn)
    }

    func testDelayedOldDisappearCannotCancelFreshInFlightLogin() async throws {
        let (session, vault, transport) = try harness()
        let old = form(session), fresh = form(session)
        transport.holdPhone = true; fresh.signIn()
        for _ in 0..<1_000 { if transport.pending != nil { break }; await Task.yield() }
        let pending = try XCTUnwrap(transport.pending)
        old.clear()
        XCTAssertEqual(fresh.state.work, .phoneLogin)
        pending.resume(returning: transport.loginReply()); await settled(fresh)
        XCTAssertEqual(session.account?.id, 7); XCTAssertEqual(vault.writes, 1)
        XCTAssertEqual(transport.requests.count, 2)
    }

    func testReplacementRetiresQueuedOldWorkAndOldModelCannotStartAgain() async throws {
        for sms in [false, true] {
            let (session, vault, transport) = try harness()
            let old = form(session)
            if sms { old.sendCode() } else { old.signIn() }
            let fresh = form(session)
            XCTAssertFalse(old.canStart); XCTAssertTrue(fresh.canStart)
            await settled(old)
            XCTAssertFalse(old.isScheduled, "A retired queued task must still release local scheduling state")
            old.phone = "10000000001"; old.code = "654321"
            old.sendCode(); old.signIn()
            await drain()
            XCTAssertTrue(transport.requests.isEmpty); XCTAssertEqual(vault.writes, 0)
            XCTAssertNil(session.account); XCTAssertEqual(session.authChannels.smsCooldownRemaining, 0)
            fresh.signIn(); await settled(fresh)
            XCTAssertEqual(session.account?.id, 7); XCTAssertEqual(vault.writes, 1)
        }
    }

    func testOldPhoneChangeAndCleanupCannotEraseFreshReadbackFailure() async throws {
        let (session, vault, transport) = try harness()
        let old = form(session), fresh = form(session)
        transport.currentStatus = 401; fresh.signIn(); await settled(fresh)
        XCTAssertEqual(fresh.state.issue, .unauthorized)
        old.phoneChanged(); old.clear()
        XCTAssertEqual(fresh.state.issue, .unauthorized)
        XCTAssertEqual(session.authChannels.state.issue, .unauthorized)
        XCTAssertNil(session.account); XCTAssertEqual(vault.writes, 0)
        transport.currentStatus = 200; fresh.code = "654321"; fresh.signIn(); await settled(fresh)
        XCTAssertEqual(session.account?.id, 7); XCTAssertEqual(vault.writes, 1)
    }

    func testOldCleanupCannotClearFreshSMSSuccessOrBypassCooldown() async throws {
        let (session, _, transport) = try harness()
        let old = form(session), fresh = form(session)
        fresh.sendCode(); await settled(fresh)
        old.clear(); old.phoneChanged()
        XCTAssertTrue(fresh.state.smsSent); XCTAssertTrue(session.authChannels.state.smsSent)
        let next = form(session); next.phone = "10000000001"; next.sendCode(); await settled(next)
        XCTAssertEqual(next.state.issue, .rateLimited)
        fresh.clear(); old.clear()
        XCTAssertEqual(next.state.issue, .rateLimited)
        XCTAssertGreaterThan(session.authChannels.smsCooldownRemaining, 0)
        XCTAssertEqual(transport.requests.map { $0.url?.lastPathComponent }, ["send"])
    }

    func testLateReplacedLoginCannotClearFreshStateOrStartOldReadback() async throws {
        let (session, vault, transport) = try harness()
        let old = form(session); transport.holdPhone = true; old.signIn()
        for _ in 0..<1_000 { if transport.pending != nil { break }; await Task.yield() }
        let pending = try XCTUnwrap(transport.pending), oldReply = transport.loginReply()
        transport.holdPhone = false; transport.accountID = 8
        let fresh = form(session); fresh.signIn(); await settled(fresh)
        pending.resume(returning: oldReply); await settled(old)
        old.clear(); old.phoneChanged()
        XCTAssertEqual(session.account?.id, 8); XCTAssertEqual(vault.value, "synthetic-token-8")
        XCTAssertEqual(vault.writes, 1); XCTAssertTrue(fresh.state.signedIn)
        XCTAssertEqual(transport.requests.map { $0.url?.lastPathComponent }, ["phone", "phone", "userInfo"])
    }

    func testGlobalCloseStillCancelsFreshQueueAndSameModelCanExplicitlyRetry() async throws {
        let (session, vault, transport) = try harness()
        let old = form(session), fresh = form(session)
        fresh.signIn(); session.cancelPendingLogin(); old.clear()
        await settled(fresh)
        XCTAssertTrue(transport.requests.isEmpty); XCTAssertEqual(vault.writes, 0)
        fresh.clear(); fresh.phone = "10000000001"; fresh.code = "654321"
        XCTAssertTrue(fresh.canStart)
        fresh.signIn(); await settled(fresh)
        XCTAssertEqual(session.account?.id, 7); XCTAssertEqual(vault.writes, 1)
    }

    func testNewFormDoesNotPermitSigningInOverAnAuthenticatedAccount() async throws {
        let (session, vault, transport) = try harness()
        let initial = form(session); initial.signIn(); await settled(initial)
        let requestCount = transport.requests.count
        let fresh = form(session); fresh.signIn(); fresh.sendCode(); initial.clear()
        await drain()
        XCTAssertFalse(fresh.canStart); XCTAssertEqual(transport.requests.count, requestCount)
        XCTAssertEqual(session.account?.id, 7); XCTAssertEqual(vault.writes, 1)
    }

    func testObsoleteModelCannotExchangeEvenWithCurrentAppleAttempt() async throws {
        let service = PresentationAppleService()
        var commits = 0
        let coordinator = AuthChannelCoordinator(service: service, appleConfigurationVerified: true,
            currentSession: { .init(epoch: 1, accountID: nil) }, commitLogin: { _, _ in commits += 1; return true })
        let old = AuthChannelModel(coordinator: coordinator), fresh = AuthChannelModel(coordinator: coordinator)
        let attempt = try XCTUnwrap(coordinator.beginAppleAuthorization())
        old.exchangeApple(attempt, identityToken: "synthetic-old"); await drain()
        XCTAssertEqual(service.exchanges, 0); XCTAssertTrue(coordinator.canCompleteAppleAuthorization(attempt))
        fresh.exchangeApple(attempt, identityToken: "synthetic-current"); old.clear()
        await settled(fresh)
        XCTAssertEqual(service.exchanges, 1); XCTAssertEqual(commits, 1)
    }
}

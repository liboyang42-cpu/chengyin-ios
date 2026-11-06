import Foundation
import XCTest
@testable import Questify

private final class ExpiryPresentationVault: AppTokenStorage {
    var value: String? = "synthetic-7"
    var writes = 0, clears = 0
    func read() throws -> String? { value }
    func write(_ token: String) throws { value = token; writes += 1 }
    func clear() throws { value = nil; clears += 1 }
}
private final class ExpiryPresentationWire: HTTPTransport {
    var requests: [URLRequest] = []
    var accountID = 7, currentStatus = 200
    var holdPhone = false
    var pendingPhone: CheckedContinuation<(Data, Int), Error>?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        guard let path = request.url?.path else { throw APIError.invalidRequest }
        if path.hasSuffix("/api/userInfo") {
            if currentStatus != 200 { return (Data(), currentStatus) }
            return (Data("{\"code\":200,\"appUser\":{\"id\":\(accountID),\"role\":\"player\"}}".utf8), 200)
        }
        if path.hasSuffix("/api/login/phone") {
            if holdPhone { return try await withCheckedThrowingContinuation { pendingPhone = $0 } }
            return (Data("{\"code\":200,\"token\":\"synthetic-\(accountID)\",\"data\":{\"id\":\(accountID),\"role\":\"player\"}}".utf8), 200)
        }
        guard path.hasSuffix("/api/logout") else { XCTFail("Unexpected operation: \(path)"); throw APIError.invalidRequest }
        return (Data("{\"code\":200}".utf8), 200)
    }
}

@MainActor final class SessionExpiryPresentationAppTests: XCTestCase {
    private struct Harness {
        let root: AppCompositionRoot
        let session: AppSession
        let vault: ExpiryPresentationVault
        let wire: ExpiryPresentationWire
        let defaults: UserDefaults
        let deployment: ReviewedAppDeployment
    }
    private func harness(restore: Bool = true) async throws -> Harness {
        let suite = "expiry-presentation-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let endpoint = "https://example.test/expiry-presentation"
        let deployment = try ReviewedAppDeployment(market: .china, baseURL: endpoint,
            approvedBaseURLs: [.china: [endpoint]], verifiedCapabilities: [.domesticChinaPhone],
            bundleIdentifier: "test.expiry.presentation", realm: "synthetic")
        let vault = ExpiryPresentationVault(), wire = ExpiryPresentationWire()
        let root = AppCompositionRoot(deployment: .reviewed(deployment),
            storage: .init(defaults: defaults, tokenStore: { _ in vault }), makeTransport: { wire })
        let session = root.makeSession()
        if restore { await session.bootstrap(); XCTAssertEqual(session.account?.id, 7) }
        return .init(root: root, session: session, vault: vault, wire: wire, defaults: defaults, deployment: deployment)
    }
    private func expired(_ h: Harness) async throws -> SessionExpiryPresentationState {
        var state = SessionExpiryPresentationState()
        state.observe(.init(session: h.session))
        h.wire.currentStatus = 401
        await h.session.refreshOwnAccount()
        XCTAssertNil(h.session.account); XCTAssertEqual(h.session.errorKey, "auth.expired")
        XCTAssertTrue(state.observe(.init(session: h.session)))
        XCTAssertNotNil(state.prompt)
        return state
    }
    private func login(_ h: Harness, id: Int) async {
        h.wire.accountID = id; h.wire.currentStatus = 200
        h.session.authChannels.cancel()
        await h.session.authChannels.loginWithPhone(phone: "10000000000", code: "123456")
        XCTAssertEqual(h.session.account?.id, id)
    }

    func testReal401ProducesOneNoticeAndPresentationActionsDoNotDispatch() async throws {
        let h = try await harness()
        var state = try await expired(h)
        let prompt = try XCTUnwrap(state.prompt), count = h.wire.requests.count
        XCTAssertTrue(h.defaults.bool(forKey: h.deployment.storageScope.restoreBlockedKey))
        XCTAssertNil(h.vault.value); XCTAssertEqual(h.vault.clears, 1)
        XCTAssertFalse(state.observe(.init(session: h.session)))
        XCTAssertTrue(state.beginSignIn(prompt, current: .init(session: h.session)))
        XCTAssertEqual(h.wire.requests.count, count, "Opening the existing login form is not a login/SMS request")
        XCTAssertEqual(h.vault.writes, 0); XCTAssertNil(h.session.account)
    }

    func testOldPromptActionCannotOpenLoginAfterSameOrDifferentAccountReauthentication() async throws {
        for nextID in [7, 8] {
            let h = try await harness()
            var state = try await expired(h); let old = try XCTUnwrap(state.prompt)
            await login(h, id: nextID)
            let count = h.wire.requests.count
            // Recheck the real host before its SwiftUI observer has delivered the change.
            XCTAssertFalse(state.beginSignIn(old, current: .init(session: h.session)))
            XCTAssertNil(state.signIn)
            XCTAssertFalse(state.observe(.init(session: h.session)))
            XCTAssertNil(state.active); XCTAssertEqual(h.session.account?.id, nextID)
            XCTAssertEqual(h.vault.value, "synthetic-\(nextID)"); XCTAssertEqual(h.wire.requests.count, count)
        }
    }

    func testOldPromptCannotFollowAnUnrelatedLaterGuestEpoch() async throws {
        let h = try await harness()
        var state = try await expired(h); let old = try XCTUnwrap(state.prompt)
        await h.session.logout()
        let count = h.wire.requests.count
        XCTAssertFalse(state.beginSignIn(old, current: .init(session: h.session)))
        state.observe(.init(session: h.session)); XCTAssertNil(state.active)
        XCTAssertEqual(h.wire.requests.count, count); XCTAssertNil(h.session.account)
    }

    func testDeliberateLogoutAndColdUnauthorizedRestoreHaveNoTransitionNotice() async throws {
        let signedIn = try await harness()
        var deliberate = SessionExpiryPresentationState(); deliberate.observe(.init(session: signedIn.session))
        await signedIn.session.logout()
        XCTAssertFalse(deliberate.observe(.init(session: signedIn.session))); XCTAssertNil(deliberate.active)
        let cold = try await harness(restore: false)
        var initial = SessionExpiryPresentationState(); initial.observe(.init(session: cold.session))
        cold.wire.currentStatus = 401; await cold.session.bootstrap()
        XCTAssertEqual(cold.session.errorKey, "auth.expired")
        XCTAssertFalse(initial.observe(.init(session: cold.session))); XCTAssertNil(initial.active)
    }

    func testStartedPhoneLoginSurvivesInFlightAndFailureThenClosesAfterSuccessfulRetry() async throws {
        let h = try await harness()
        var state = try await expired(h); let original = try XCTUnwrap(state.prompt)
        XCTAssertTrue(state.beginSignIn(original, current: .init(session: h.session)))
        h.wire.holdPhone = true
        let task = Task { await h.session.authChannels.loginWithPhone(phone: "10000000000", code: "123456") }
        for _ in 0..<1_000 { if h.wire.pendingPhone != nil { break }; await Task.yield() }
        let pending = try XCTUnwrap(h.wire.pendingPhone)
        XCTAssertTrue(h.session.authChannels.state.isWorking)
        state.observe(.init(session: h.session)); XCTAssertEqual(state.signIn, original)
        pending.resume(returning: (Data(), 503)); await task.value
        state.observe(.init(session: h.session)); XCTAssertEqual(state.signIn, original)
        XCTAssertEqual(h.session.authChannels.state.issue, .network)
        h.wire.holdPhone = false; await login(h, id: 8)
        state.observe(.init(session: h.session)); XCTAssertNil(state.active)
        XCTAssertEqual(h.vault.value, "synthetic-8"); XCTAssertEqual(h.vault.writes, 1)
    }

    func testOldAlertAndLoginDismissalCannotClearSecondRealExpiryRecovery() async throws {
        let h = try await harness()
        var state = try await expired(h); let old = try XCTUnwrap(state.prompt)
        state.beginSignIn(old, current: .init(session: h.session))
        await login(h, id: 8); state.observe(.init(session: h.session))
        h.wire.currentStatus = 401; await h.session.refreshOwnAccount()
        XCTAssertTrue(state.observe(.init(session: h.session))); let fresh = try XCTUnwrap(state.prompt)
        state.dismissPrompt(old); state.dismissSignIn(old)
        XCTAssertEqual(state.prompt, fresh)
        XCTAssertTrue(state.beginSignIn(fresh, current: .init(session: h.session)))
        state.dismissSignIn(old); XCTAssertEqual(state.signIn, fresh)
    }

    func testBrowseLeavesOriginalUnknownJournalAndGuestSessionUntouched() async throws {
        let h = try await harness()
        let owner = "registration|\(h.deployment.storageScope.service)|CN|https://example.test/expiry-presentation|7"
        let record = OperationPendingRecord(ownerKey: owner, targetKey: "create|10|20")
        let journal = OperationDefaultsJournal(defaults: h.defaults); try journal.write(record)
        var state = try await expired(h); let prompt = try XCTUnwrap(state.prompt)
        let context = SessionExpiryNoticeContext(session: h.session), count = h.wire.requests.count
        state.dismissPrompt(prompt); state.observe(context)
        XCTAssertNil(state.active); XCTAssertEqual(SessionExpiryNoticeContext(session: h.session), context)
        XCTAssertEqual(h.wire.requests.count, count); XCTAssertEqual(try journal.pending(ownerKey: owner, targetKey: record.targetKey), record)
    }
}

import Foundation
import XCTest
@testable import QuestifyCore

@MainActor
private final class WeChatDriverFixture: WeChatSDKAuthDriving {
    var isLinked = true
    var isInstalledAndSupported = true
    var registrationResult = true
    var registrations: [WeChatSDKConfiguration] = []
    var requests: [WeChatAppAuthorizationRequest] = []
    var launches: [(Bool) -> Void] = []
    var responses: [(WeChatSDKAuthResponse) -> Void] = []
    var detaches = 0
    func register(_ configuration: WeChatSDKConfiguration) -> Bool {
        registrations.append(configuration); return registrationResult
    }
    func send(_ request: WeChatAppAuthorizationRequest, launched: @escaping (Bool) -> Void,
              response: @escaping (WeChatSDKAuthResponse) -> Void) {
        requests.append(request); launches.append(launched); responses.append(response)
    }
    func detach() { detaches += 1 }
}

@MainActor
private final class WeChatSDKExchangeFixture: WeChatAppExchanging {
    var codes: [String] = []
    var accountReads = 0
    func exchange(code: String) async throws -> LoginResult {
        codes.append(code)
        return LoginResult(token: "fixture-token", account: try JSONDecoder().decode(Account.self, from: Data(#"{"id":7}"#.utf8)))
    }
    func currentAccount(token: String) async throws -> Account {
        accountReads += 1
        return try JSONDecoder().decode(Account.self, from: Data(#"{"id":7}"#.utf8))
    }
}

@MainActor
final class WeChatSDKAuthAdapterTests: XCTestCase {
    private func approved() -> WeChatAppAuthGate {
        var gate = WeChatAppAuthGate()
        gate.sdkVerified = true; gate.providerVerified = true; gate.legalVerified = true
        gate.appleAlternativeVerified = true; gate.liveExchangeApproved = true
        return gate
    }
    private func context(epoch: UInt64 = 1, account: Int? = nil, busy: Bool = false,
                         namespace: String = "fixture.cn", market: RegionalMarket = .china) -> WeChatAppAuthContext {
        .init(session: .init(epoch: epoch, accountID: account, isBusy: busy), market: market, namespace: namespace)
    }
    /// These are synthetic routing fixtures, not claims about Tencent's live URL shape.
    private func configuration() throws -> WeChatSDKConfiguration {
        try .init(appID: "wxFixture", universalLink: URL(string: "https://fixture.example/wechat/")!,
                  urlCallbacks: [.init(host: "fixture-auth", path: "/reply")],
                  universalLinkCallbacks: [.init(host: "fixture.example", path: "/wechat/reply")])
    }
    private func request(_ state: String = UUID().uuidString) -> WeChatAppAuthorizationRequest {
        .init(attemptID: UUID(), state: state)
    }
    private func label(_ outcome: WeChatAppAuthorizationOutcome) -> String {
        switch outcome {
        case .code(let code): return "code:\(code)"
        case .cancelled: return "cancelled"
        case .denied: return "denied"
        case .unavailable: return "unavailable"
        case .launchFailed: return "launchFailed"
        }
    }
    func testConfigurationRejectsUnreviewedRoutesAndUnsafeURLs() throws {
        let valid = try configuration()
        XCTAssertFalse(valid.pasteboardReadApproved)
        for appID in ["", "not-wechat", "wx", "wx/a", "wx A"] {
            XCTAssertThrowsError(try WeChatSDKConfiguration(appID: appID, universalLink: valid.universalLink,
                urlCallbacks: valid.urlCallbacks, universalLinkCallbacks: valid.universalLinkCallbacks))
        }
        for link in ["http://fixture.example/wechat/", "https://user@fixture.example/wechat/", "https://fixture.example/wechat/?q=x", "https://fixture.example/wechat", "https://fixture.example/wechat/%2f"] {
            XCTAssertThrowsError(try WeChatSDKConfiguration(appID: valid.appID, universalLink: URL(string: link)!,
                urlCallbacks: valid.urlCallbacks, universalLinkCallbacks: valid.universalLinkCallbacks))
        }
        XCTAssertThrowsError(try WeChatSDKConfiguration(appID: valid.appID, universalLink: valid.universalLink,
            urlCallbacks: [], universalLinkCallbacks: valid.universalLinkCallbacks))
        XCTAssertThrowsError(try WeChatSDKConfiguration(appID: valid.appID, universalLink: valid.universalLink,
            urlCallbacks: valid.urlCallbacks, universalLinkCallbacks: [.init(host: "other.example", path: "/wechat/reply")]))
    }
    func testExactCallbackRoutesRejectNearbyAndEncodedPaths() throws {
        let config = try configuration()
        XCTAssertTrue(config.acceptsURL(URL(string: "wxfixture://fixture-auth/reply?opaque=payload")!))
        XCTAssertTrue(config.acceptsUniversalLink(URL(string: "https://fixture.example/wechat/reply?opaque=payload")!))
        for raw in ["wxother://fixture-auth/reply", "wxfixture://other/reply", "wxfixture://fixture-auth/reply/extra", "wxfixture://fixture-auth/%72eply", "wxfixture://fixture-auth/reply#fragment", "wxfixture://user@fixture-auth/reply", "wxfixture://fixture-auth:80/reply"] {
            XCTAssertFalse(config.acceptsURL(URL(string: raw)!))
        }
        for raw in ["http://fixture.example/wechat/reply", "https://fixture.example.evil/wechat/reply", "https://fixture.example/wechat/reply/", "https://fixture.example:443/wechat/reply", "https://fixture.example/wechat/../reply", "https://fixture.example/wechat/%2e%2e/reply"] {
            XCTAssertFalse(config.acceptsUniversalLink(URL(string: raw)!))
        }
    }
    func testEveryOffGatePreventsRegistrationAndSend() throws {
        var gates = [WeChatAppAuthGate()]
        for field in [\WeChatAppAuthGate.sdkVerified, \.providerVerified, \.legalVerified, \.appleAlternativeVerified, \.liveExchangeApproved] {
            var gate = approved(); gate[keyPath: field] = false; gates.append(gate)
        }
        for gate in gates {
            let driver = WeChatDriverFixture()
            let adapter = WeChatSDKAuthAdapter(driver: driver, configuration: try configuration(), gate: { gate }, context: { self.context() })
            var outcomes: [String] = []
            adapter.start(request()) { _, result in outcomes.append(self.label(result)) }
            XCTAssertEqual(outcomes, ["unavailable"]); XCTAssertTrue(driver.registrations.isEmpty); XCTAssertTrue(driver.requests.isEmpty)
        }
    }
    func testAbsentConfigSDKAndDisallowedSessionNeverRegister() throws {
        let config = try configuration()
        for state in [context(account: 7), context(busy: true), context(namespace: ""), context(market: .unitedStates)] {
            let driver = WeChatDriverFixture()
            let adapter = WeChatSDKAuthAdapter(driver: driver, configuration: config, gate: { self.approved() }, context: { state })
            adapter.start(request()) { _, _ in }
            XCTAssertTrue(driver.registrations.isEmpty)
        }
        let driver = WeChatDriverFixture()
        let unconfigured = WeChatSDKAuthAdapter(driver: driver, gate: { self.approved() }, context: { self.context() })
        unconfigured.start(request()) { _, _ in }; XCTAssertTrue(driver.registrations.isEmpty)
        driver.isLinked = false
        let unlinked = WeChatSDKAuthAdapter(driver: driver, configuration: config, gate: { self.approved() }, context: { self.context() })
        unlinked.start(request()) { _, _ in }; XCTAssertTrue(driver.registrations.isEmpty)
    }
    func testRegistrationInstallationAndLaunchFailures() throws {
        for failure in ["registration", "installation", "launch"] {
            let driver = WeChatDriverFixture(); var outcomes: [String] = []
            driver.registrationResult = failure != "registration"
            driver.isInstalledAndSupported = failure != "installation"
            let adapter = WeChatSDKAuthAdapter(driver: driver, configuration: try configuration(), gate: { self.approved() }, context: { self.context() })
            adapter.start(request()) { _, result in outcomes.append(self.label(result)) }
            if failure == "launch" { driver.launches[0](false) }
            XCTAssertEqual(outcomes, [failure == "installation" ? "unavailable" : "launchFailed"])
            XCTAssertEqual(driver.requests.count, failure == "launch" ? 1 : 0)
            XCTAssertEqual(driver.detaches, 1)
        }
    }
    func testOnlyMatchingStateCanCompleteIncludingCancelAndDeny() throws {
        for errorCode in [Int32(0), -2, -4, -5, -1, -3, -99] {
            let driver = WeChatDriverFixture(), attempt = request(); var outcomes: [String] = []; var returnedState: String?
            let adapter = WeChatSDKAuthAdapter(driver: driver, configuration: try configuration(), gate: { self.approved() }, context: { self.context() })
            adapter.start(attempt) { state, outcome in returnedState = state; outcomes.append(self.label(outcome)) }
            driver.responses[0](.init(state: nil, code: "synthetic", errorCode: errorCode))
            driver.responses[0](.init(state: "different", code: "synthetic", errorCode: errorCode))
            XCTAssertTrue(outcomes.isEmpty); XCTAssertEqual(driver.detaches, 0)
            driver.responses[0](.init(state: attempt.state, code: "synthetic", errorCode: errorCode))
            driver.responses[0](.init(state: attempt.state, code: "duplicate", errorCode: errorCode))
            let expected = [Int32(0): "code:synthetic", -2: "cancelled", -4: "denied", -5: "unavailable"][errorCode] ?? "launchFailed"
            XCTAssertEqual(outcomes, [expected]); XCTAssertEqual(returnedState, attempt.state); XCTAssertEqual(driver.detaches, 1)
        }
    }
    func testInvalidSuccessCodesNeverEscape() throws {
        for code in [nil, "", "two words", "x\n", "中文", String(repeating: "a", count: 4097)] as [String?] {
            let driver = WeChatDriverFixture(), attempt = request(); var outcomes: [String] = []
            let adapter = WeChatSDKAuthAdapter(driver: driver, configuration: try configuration(), gate: { self.approved() }, context: { self.context() })
            adapter.start(attempt) { _, result in outcomes.append(self.label(result)) }
            driver.responses[0](.init(state: attempt.state, code: code, errorCode: 0))
            XCTAssertEqual(outcomes, ["launchFailed"])
        }
    }
    func testCancelDetachesAndLateCallbacksCannotAffectNewAttempt() throws {
        let driver = WeChatDriverFixture(), old = request(), newer = request(); var outcomes: [String] = []
        let adapter = WeChatSDKAuthAdapter(driver: driver, configuration: try configuration(), gate: { self.approved() }, context: { self.context() })
        adapter.start(old) { _, result in outcomes.append(self.label(result)) }
        adapter.cancel(attemptID: old.attemptID)
        adapter.start(newer) { _, result in outcomes.append(self.label(result)) }
        adapter.cancel(attemptID: old.attemptID)
        driver.launches[0](false)
        driver.responses[0](.init(state: old.state, code: "old", errorCode: 0))
        driver.responses[1](.init(state: old.state, code: nil, errorCode: -2))
        XCTAssertTrue(outcomes.isEmpty)
        driver.responses[1](.init(state: newer.state, code: "new", errorCode: 0))
        XCTAssertEqual(outcomes, ["code:new"]); XCTAssertEqual(driver.registrations.count, 1)
    }
    func testNoPendingAttemptAndRevokedContextRejectURLBeforeSDK() throws {
        let driver = WeChatDriverFixture(); var active = context(); let callbackURL = URL(string: "wxfixture://fixture-auth/reply")!
        let adapter = WeChatSDKAuthAdapter(driver: driver, configuration: try configuration(), gate: { self.approved() }, context: { active })
        XCTAssertFalse(adapter.acceptsURL(callbackURL))
        let attempt = request(); adapter.start(attempt) { _, _ in }
        XCTAssertTrue(adapter.acceptsURL(callbackURL))
        active = context(epoch: 2)
        XCTAssertFalse(adapter.acceptsURL(callbackURL)); XCTAssertEqual(driver.detaches, 1)
    }
    func testGateAndContextChangesPreventResponseDelivery() throws {
        for changed in [context(epoch: 2), context(account: 8), context(namespace: "different"), context(busy: true), context(market: .unitedStates)] {
            var active = context(); let driver = WeChatDriverFixture(), attempt = request(); var results: [String] = []
            let adapter = WeChatSDKAuthAdapter(driver: driver, configuration: try configuration(), gate: { self.approved() }, context: { active })
            adapter.start(attempt) { _, result in results.append(self.label(result)) }
            active = changed; driver.responses[0](.init(state: attempt.state, code: "stale", errorCode: 0))
            XCTAssertEqual(results, ["launchFailed"])
        }
        var gate = approved(); let driver = WeChatDriverFixture(), attempt = request(); var results: [String] = []
        let adapter = WeChatSDKAuthAdapter(driver: driver, configuration: try configuration(), gate: { gate }, context: { self.context() })
        adapter.start(attempt) { _, result in results.append(self.label(result)) }
        gate.legalVerified = false; driver.responses[0](.init(state: attempt.state, code: "stale", errorCode: 0))
        XCTAssertEqual(results, ["launchFailed"])
    }
    func testMalformedRequestStateAndDuplicateStartDoNotReplaceActiveAttempt() throws {
        let driver = WeChatDriverFixture()
        let adapter = WeChatSDKAuthAdapter(driver: driver, configuration: try configuration(), gate: { self.approved() }, context: { self.context() })
        for state in ["", "two words", String(repeating: "a", count: 1025), "中文"] {
            adapter.start(request(state)) { _, _ in }
        }
        XCTAssertTrue(driver.registrations.isEmpty)
        let first = request(); var outcomes: [String] = []
        adapter.start(first) { _, result in outcomes.append(self.label(result)) }
        adapter.start(request()) { _, result in outcomes.append("second:" + self.label(result)) }
        XCTAssertEqual(driver.requests.count, 1)
        driver.responses[0](.init(state: first.state, code: "first", errorCode: 0))
        XCTAssertEqual(outcomes, ["second:launchFailed", "code:first"])
    }
    func testAdapterCoordinatorExchangeAndCommitEndToEndWithSyntheticDriver() async throws {
        let driver = WeChatDriverFixture(), service = WeChatSDKExchangeFixture(); var commits = 0
        let adapter = WeChatSDKAuthAdapter(driver: driver, configuration: try configuration(), gate: { self.approved() }, context: { self.context() })
        let coordinator = WeChatAppAuthCoordinator(adapter: adapter, service: service,
            gate: { self.approved() }, context: { self.context() }, commit: { _, _ in commits += 1; return true })
        coordinator.start()
        driver.responses[0](.init(state: "unrelated", code: "wrong", errorCode: 0))
        XCTAssertTrue(service.codes.isEmpty); XCTAssertEqual(coordinator.phase, .authorizing)
        let state = driver.requests[0].state
        driver.responses[0](.init(state: state, code: "synthetic", errorCode: 0))
        driver.responses[0](.init(state: state, code: "duplicate", errorCode: 0))
        for _ in 0..<30 { await Task.yield() }
        XCTAssertEqual(service.codes, ["synthetic"]); XCTAssertEqual(service.accountReads, 1)
        XCTAssertEqual(commits, 1); XCTAssertEqual(coordinator.phase, .signedIn)
    }
    func testAdapterEpochRevocationBecomesCoordinatorStaleSessionWithoutExchange() async throws {
        var active = context(); let driver = WeChatDriverFixture(), service = WeChatSDKExchangeFixture()
        let adapter = WeChatSDKAuthAdapter(driver: driver, configuration: try configuration(), gate: { self.approved() }, context: { active })
        let coordinator = WeChatAppAuthCoordinator(adapter: adapter, service: service,
            gate: { self.approved() }, context: { active }, commit: { _, _ in XCTFail(); return false })
        coordinator.start(); let state = driver.requests[0].state
        active = context(epoch: 2)
        driver.responses[0](.init(state: state, code: "stale", errorCode: 0))
        for _ in 0..<30 { await Task.yield() }
        XCTAssertTrue(service.codes.isEmpty); XCTAssertEqual(coordinator.issue, .staleSession)
        XCTAssertEqual(coordinator.phase, .idle)
    }

}

import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class WeChatUpgradeTransport: HTTPTransport {
    var replies: [(String, Int)]
    var requests: [URLRequest] = []
    init(_ replies: [(String, Int)]) { self.replies = replies }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        guard !replies.isEmpty else { throw URLError(.badServerResponse) }
        let reply = replies.removeFirst()
        return (Data(reply.0.utf8), reply.1)
    }
}
@MainActor private final class WeChatUpgradeAuthorizer: WeChatAppAuthorizing {
    var request: WeChatAppAuthorizationRequest?
    var callback: ((String?, WeChatAppAuthorizationOutcome) -> Void)?
    var starts = 0
    func start(_ request: WeChatAppAuthorizationRequest,
               callback: @escaping (String?, WeChatAppAuthorizationOutcome) -> Void) {
        self.request = request; self.callback = callback; starts += 1
    }
    func cancel(attemptID: UUID) {}
    func syntheticCode() { callback?(request?.state, .code("synthetic-code")) }
}
@MainActor final class WeChatUpgradeRequiredTests: XCTestCase {
    private func service(_ transport: WeChatUpgradeTransport) throws -> WeChatAppAuthService {
        try WeChatAppAuthService(configuration: APIConfiguration(
            baseURL: URL(string: "https://api.example.com/prefix")!), transport: transport)
    }
    private func offlineGate() -> WeChatAppAuthGate {
        var gate = WeChatAppAuthGate()
        gate.sdkVerified = true; gate.providerVerified = true; gate.legalVerified = true
        gate.appleAlternativeVerified = true; gate.liveExchangeApproved = true
        return gate
    }
    private func context() -> WeChatAppAuthContext {
        .init(session: .init(epoch: 1, accountID: nil), market: .china, namespace: "offline.wechat")
    }
    private func complete(_ replies: [(String, Int)], expected: WeChatAppAuthError,
                          expectedPaths: [String]) async throws {
        let transport = WeChatUpgradeTransport(replies), adapter = WeChatUpgradeAuthorizer()
        var commits = 0
        let coordinator = WeChatAppAuthCoordinator(adapter: adapter, service: try service(transport),
            gate: { self.offlineGate() }, context: { self.context() },
            commit: { _, _ in commits += 1; return true })
        let finished = expectation(description: "Original exchange has a terminal presentation")
        coordinator.start()
        coordinator.onChange = { if !coordinator.isWorking { finished.fulfill() } }
        adapter.syntheticCode()
        await fulfillment(of: [finished], timeout: 2)
        coordinator.onChange = nil
        XCTAssertEqual(coordinator.issue, expected)
        XCTAssertEqual(coordinator.phase, .idle)
        XCTAssertEqual(commits, 0)
        XCTAssertEqual(transport.requests.map { $0.url!.path }, expectedPaths)
        adapter.syntheticCode()
        XCTAssertEqual(transport.requests.count, expectedPaths.count, "Old callback cannot replay an exchange")
        coordinator.cancel()
    }
    func testExchange426DisplaysUpgradeWithoutRetryOrIdentityCommit() async throws {
        try await complete([("not JSON", 426)], expected: .upgradeRequired,
                           expectedPaths: ["/prefix/api/login/wechat/app"])
        XCTAssertEqual(WeChatAppAuthError.upgradeRequired.localizationKey, "auth.channels.upgradeRequired")
    }
    func testAccountVerification426DoesNotCommitCandidateToken() async throws {
        try await complete([(#"{"code":200,"token":"synthetic-token","data":{"id":7}}"#, 200),
                            ("not JSON", 426)], expected: .upgradeRequired,
                           expectedPaths: ["/prefix/api/login/wechat/app", "/prefix/api/userInfo"])
    }
    func testOtherHTTPAndBusinessErrorsKeepTheirOriginalMeaning() async throws {
        for (body, status, issue) in [("", 503, WeChatAppAuthError.network),
                                     ("", 401, .unauthorized),
                                     (#"{"code":426}"#, 200, .rejected)] {
            try await complete([(body, status)], expected: issue,
                               expectedPaths: ["/prefix/api/login/wechat/app"])
        }
    }
    func testDefaultGateCannotStartSDKOrDispatch() throws {
        let transport = WeChatUpgradeTransport([]), adapter = WeChatUpgradeAuthorizer()
        let coordinator = WeChatAppAuthCoordinator(adapter: adapter, service: try service(transport),
            context: { self.context() }, commit: { _, _ in XCTFail(); return false })
        coordinator.start()
        XCTAssertEqual(coordinator.issue, .notConfigured)
        XCTAssertEqual(adapter.starts, 0)
        XCTAssertTrue(transport.requests.isEmpty)
    }
    func testCancelledOriginalCallbackCannotTriggerNewExchange() throws {
        let transport = WeChatUpgradeTransport([]), adapter = WeChatUpgradeAuthorizer()
        let coordinator = WeChatAppAuthCoordinator(adapter: adapter, service: try service(transport),
            gate: { self.offlineGate() }, context: { self.context() }, commit: { _, _ in XCTFail(); return false })
        coordinator.start(); coordinator.cancel(); adapter.syntheticCode()
        XCTAssertNil(coordinator.issue)
        XCTAssertEqual(coordinator.phase, .idle)
        XCTAssertTrue(transport.requests.isEmpty)
    }
}

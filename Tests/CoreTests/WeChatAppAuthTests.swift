import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class WeChatHTTPFixture: HTTPTransport {
    var requests: [URLRequest] = []
    var replies: [(String, Int)]
    init(_ replies: [(String, Int)]) { self.replies = replies }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        let reply = replies.removeFirst()
        return (Data(reply.0.utf8), reply.1)
    }
}
@MainActor
private final class WeChatSDKFixture: WeChatAppAuthorizing {
    var requests: [WeChatAppAuthorizationRequest] = []
    var callbacks: [(String?, WeChatAppAuthorizationOutcome) -> Void] = []
    var cancelled: [UUID] = []
    func start(_ request: WeChatAppAuthorizationRequest, callback: @escaping (String?, WeChatAppAuthorizationOutcome) -> Void) {
        requests.append(request); callbacks.append(callback)
    }
    func cancel(attemptID: UUID) { cancelled.append(attemptID) }
    func respond(_ outcome: WeChatAppAuthorizationOutcome, index: Int = 0, state: String? = nil) {
        callbacks[index](state ?? requests[index].state, outcome)
    }
}
@MainActor
private final class WeChatSuspendedExchange: WeChatAppExchanging {
    var continuation: CheckedContinuation<LoginResult, Error>?
    var reads = 0
    func exchange(code: String) async throws -> LoginResult {
        try await withCheckedThrowingContinuation { continuation = $0 }
    }
    func currentAccount(token: String) async throws -> Account {
        reads += 1
        return try JSONDecoder().decode(Account.self, from: Data(#"{"id":7}"#.utf8))
    }
    func resume() throws {
        let account = try JSONDecoder().decode(Account.self, from: Data(#"{"id":7}"#.utf8))
        let pending = continuation; continuation = nil
        pending?.resume(returning: LoginResult(token: "fixture-token", account: account))
    }
}
@MainActor
final class WeChatAppAuthTests: XCTestCase {
    private let login = #"{"code":200,"token":"fixture-token","data":{"id":7}}"#
    private let account = #"{"code":200,"appUser":{"id":7}}"#
    private func service(_ http: WeChatHTTPFixture) throws -> WeChatAppAuthService {
        try WeChatAppAuthService(configuration: APIConfiguration(baseURL: URL(string: "https://api.example.com/prefix")!), transport: http)
    }
    private func enabled() -> WeChatAppAuthGate {
        var gate = WeChatAppAuthGate()
        gate.sdkVerified = true; gate.providerVerified = true; gate.legalVerified = true
        gate.appleAlternativeVerified = true; gate.liveExchangeApproved = true
        return gate
    }
    private func context(epoch: UInt64 = 1, market: RegionalMarket = .china, namespace: String = "fixture.cn", account: Int? = nil) -> WeChatAppAuthContext {
        .init(session: .init(epoch: epoch, accountID: account), market: market, namespace: namespace)
    }
    private func drain() async { for _ in 0..<30 { await Task.yield() } }
    func testExactAppMultipartAndUserInfo() async throws {
        let http = WeChatHTTPFixture([(login, 200), (account, 200)])
        let service = try service(http)
        let result = try await service.exchange(code: "synthetic-app-code")
        _ = try await service.currentAccount(token: result.token)
        XCTAssertEqual(http.requests.map { $0.url!.path }, ["/prefix/api/login/wechat/app", "/prefix/api/userInfo"])
        let request = http.requests[0]
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")!.hasPrefix("multipart/form-data; boundary="))
        let body = String(decoding: request.httpBody!, as: UTF8.self)
        XCTAssertTrue(body.contains("name=\"code\"\r\n\r\nsynthetic-app-code\r\n"))
        XCTAssertEqual(body.components(separatedBy: "Content-Disposition:").count, 2)
        XCTAssertEqual(http.requests[1].value(forHTTPHeaderField: "Authorization"), "fixture-token")
        XCTAssertNil(http.requests[1].httpBody)
    }
    func testInvalidCodesNeverDispatch() async throws {
        let http = WeChatHTTPFixture([]), service = try service(http)
        for code in ["", " ", "x\n", "中文", String(repeating: "a", count: 4097)] {
            do { _ = try await service.exchange(code: code); XCTFail() }
            catch { XCTAssertEqual(error as? WeChatAppAuthError, .invalidCode) }
        }
        XCTAssertTrue(http.requests.isEmpty)
    }
    func testErrorCasesDoNotRetry() async throws {
        let cases: [(String, Int, WeChatAppAuthError)] = [
            ("{}", 401, .unauthorized), ("{}", 429, .rateLimited), ("{}", 503, .network),
            (#"{"code":401}"#, 200, .unauthorized), (#"{"code":429}"#, 200, .rateLimited),
            (#"{"code":500,"msg":"private details"}"#, 200, .rejected),
            ("garbage", 200, .invalidResponse), (#"{"code":200}"#, 200, .invalidResponse),
            (#"{"code":200,"token":"x","data":{"id":0}}"#, 200, .invalidResponse)]
        for (json, status, expected) in cases {
            let http = WeChatHTTPFixture([(json, status)])
            do { _ = try await service(http).exchange(code: "fixture"); XCTFail() }
            catch { XCTAssertEqual(error as? WeChatAppAuthError, expected) }
            XCTAssertEqual(http.requests.count, 1)
        }
    }
    func testDefaultAndEachIndependentGateDenySDKAndHTTP() throws {
        var gates = [WeChatAppAuthGate()]
        for key in [\WeChatAppAuthGate.sdkVerified, \.providerVerified, \.legalVerified, \.appleAlternativeVerified, \.liveExchangeApproved] {
            var gate = enabled(); gate[keyPath: key] = false; gates.append(gate)
        }
        for gate in gates {
            let sdk = WeChatSDKFixture(), http = WeChatHTTPFixture([])
            let coordinator = WeChatAppAuthCoordinator(adapter: sdk, service: try service(http), gate: { gate }, context: { self.context() }, commit: { _, _ in XCTFail(); return false })
            coordinator.start(); XCTAssertEqual(coordinator.issue, .notConfigured)
            XCTAssertTrue(sdk.requests.isEmpty); XCTAssertTrue(http.requests.isEmpty)
        }
    }
    func testWrongRegionAccountAndStorageDeny() throws {
        for context in [context(market: .unitedStates), context(namespace: ""), context(account: 7)] {
            let sdk = WeChatSDKFixture(), http = WeChatHTTPFixture([])
            let coordinator = WeChatAppAuthCoordinator(adapter: sdk, service: try service(http), gate: { self.enabled() }, context: { context }, commit: { _, _ in false })
            coordinator.start(); XCTAssertTrue(sdk.requests.isEmpty)
        }
    }
    func testDuplicateCallbackCommitsExactlyOnceAfterAccountVerification() async throws {
        let sdk = WeChatSDKFixture(), http = WeChatHTTPFixture([(login, 200), (account, 200)])
        var commits = 0
        let coordinator = WeChatAppAuthCoordinator(adapter: sdk, service: try service(http), gate: { self.enabled() }, context: { self.context() }, commit: { _, _ in commits += 1; return true })
        coordinator.start(); coordinator.start()
        XCTAssertEqual(sdk.requests.count, 1)
        XCTAssertEqual(sdk.requests[0].scope, "snsapi_userinfo")
        sdk.respond(.code("fixture")); sdk.respond(.code("duplicate"))
        await drain()
        XCTAssertEqual(http.requests.count, 2); XCTAssertEqual(commits, 1); XCTAssertEqual(coordinator.phase, .signedIn)
    }
    func testStateMismatchCancelLateCallbackAndFreshNonce() async throws {
        let sdk = WeChatSDKFixture(), http = WeChatHTTPFixture([])
        let coordinator = WeChatAppAuthCoordinator(adapter: sdk, service: try service(http), gate: { self.enabled() }, context: { self.context() }, commit: { _, _ in XCTFail(); return false })
        coordinator.start(); sdk.respond(.code("fixture"), state: "wrong")
        XCTAssertEqual(coordinator.issue, .invalidState)
        coordinator.start(); XCTAssertNotEqual(sdk.requests[0].state, sdk.requests[1].state)
        coordinator.cancel(); sdk.respond(.code("late"), index: 1)
        await drain(); XCTAssertTrue(http.requests.isEmpty); XCTAssertEqual(coordinator.phase, .idle)
    }
    func testEpochNamespaceAndGateChangesRejectCallback() async throws {
        for changed in [context(epoch: 2), context(namespace: "different"), context(market: .unitedStates), context(account: 8)] {
            var active = context()
            let sdk = WeChatSDKFixture(), http = WeChatHTTPFixture([])
            let coordinator = WeChatAppAuthCoordinator(adapter: sdk, service: try service(http), gate: { self.enabled() }, context: { active }, commit: { _, _ in XCTFail(); return false })
            coordinator.start(); active = changed; sdk.respond(.code("fixture"))
            await drain(); XCTAssertEqual(coordinator.issue, .staleSession); XCTAssertTrue(http.requests.isEmpty)
        }
    }
    func testAccountMismatchAndStorageFailureNeverSignIn() async throws {
        for storageFails in [false, true] {
            let sdk = WeChatSDKFixture()
            let http = WeChatHTTPFixture([(login, 200), (storageFails ? account : #"{"code":200,"appUser":{"id":8}}"#, 200)])
            let coordinator = WeChatAppAuthCoordinator(adapter: sdk, service: try service(http), gate: { self.enabled() }, context: { self.context() }, commit: { _, _ in throw WeChatAppAuthError.storage })
            coordinator.start(); sdk.respond(.code("fixture")); await drain()
            XCTAssertEqual(coordinator.issue, storageFails ? .storage : .invalidResponse)
            XCTAssertEqual(coordinator.phase, .idle)
        }
    }
    func testLateExchangeAfterCancelDoesNotStopNewAttempt() async throws {
        let sdk = WeChatSDKFixture(), service = WeChatSuspendedExchange()
        let coordinator = WeChatAppAuthCoordinator(adapter: sdk, service: service, gate: { self.enabled() }, context: { self.context() }, commit: { _, _ in XCTFail(); return false })
        coordinator.start(); sdk.respond(.code("old")); await drain()
        XCTAssertNotNil(service.continuation)
        coordinator.cancel(); coordinator.start()
        try service.resume(); await drain()
        XCTAssertEqual(coordinator.phase, .authorizing)
        XCTAssertEqual(service.reads, 0)
        coordinator.cancel()
    }
    func testEpochChangeDuringExchangePreventsUserInfoAndCommit() async throws {
        var active = context()
        let sdk = WeChatSDKFixture(), service = WeChatSuspendedExchange()
        let coordinator = WeChatAppAuthCoordinator(adapter: sdk, service: service, gate: { self.enabled() }, context: { active }, commit: { _, _ in XCTFail(); return false })
        coordinator.start(); sdk.respond(.code("fixture")); await drain()
        active = context(epoch: 2); try service.resume(); await drain()
        XCTAssertEqual(coordinator.issue, .staleSession); XCTAssertEqual(service.reads, 0)
    }
    func testProviderFailuresAndCancellationWithoutStateDoNotExchange() throws {
        let cases: [(WeChatAppAuthorizationOutcome, WeChatAppAuthError?)] = [
            (.cancelled, nil), (.denied, .denied), (.unavailable, .unavailable), (.launchFailed, .launchFailed)]
        for (outcome, expected) in cases {
            let sdk = WeChatSDKFixture(), http = WeChatHTTPFixture([])
            let coordinator = WeChatAppAuthCoordinator(adapter: sdk, service: try service(http), gate: { self.enabled() }, context: { self.context() }, commit: { _, _ in false })
            coordinator.start(); sdk.callbacks[0](nil, outcome)
            XCTAssertEqual(coordinator.issue, expected); XCTAssertEqual(coordinator.phase, .idle)
            XCTAssertTrue(http.requests.isEmpty)
        }
    }
    func testRevokingGateBeforeCallbackRejects() throws {
        var gate = enabled()
        let sdk = WeChatSDKFixture(), http = WeChatHTTPFixture([])
        let coordinator = WeChatAppAuthCoordinator(adapter: sdk, service: try service(http), gate: { gate }, context: { self.context() }, commit: { _, _ in false })
        coordinator.start(); gate.legalVerified = false; sdk.respond(.code("fixture"))
        XCTAssertEqual(coordinator.issue, .staleSession); XCTAssertTrue(http.requests.isEmpty)
    }
    func testTimeoutCancelsAndLateCallbackCannotExchange() async throws {
        let sdk = WeChatSDKFixture(), http = WeChatHTTPFixture([])
        let coordinator = WeChatAppAuthCoordinator(adapter: sdk, service: try service(http), gate: { self.enabled() }, context: { self.context() }, commit: { _, _ in false }, timeoutNanoseconds: 1)
        coordinator.start(); try await Task.sleep(nanoseconds: 10_000_000)
        XCTAssertEqual(coordinator.issue, .timedOut); sdk.respond(.code("late")); await drain()
        XCTAssertTrue(http.requests.isEmpty)
    }
}

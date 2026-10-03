import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

final class PlayReadRouteTests: XCTestCase {
    private let base = URL(string: "https://example.test/native")!
    private func request(_ suffix: String, method: String = "GET") -> URLRequest {
        var request = URLRequest(url: URL(string: base.absoluteString + "/" + suffix)!)
        request.httpMethod = method; request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
    func testOnlyCanonicalNodesAndRouteStateWithOnePositiveScope() throws {
        for endpoint in PlayReadRoute.Endpoint.allCases {
            for (key, scope) in [("activityId", PlaySessionScope.activity(41)), ("topicId", .topic(41))] {
                let route = try XCTUnwrap(PlayReadRoute(request: request(endpoint.rawValue + "?\(key)=41"), baseURL: base))
                XCTAssertEqual(route.endpoint, endpoint); XCTAssertEqual(route.scope, scope)
            }
        }
    }
    func testRejectsAmbiguousQueriesPathAliasesAndOtherPlayReads() {
        let suffixes = ["", "?", "?activityId=0", "?activityId=-1", "?activityId=01", "?activityId=+1",
            "?activityId=1.0", "?activityId=9223372036854775808", "?activityId", "?activityId=", "?actId=1",
            "?activityId=1&topicId=2", "?activityId=1&activityId=1", "?activityId=1&", "?activityId=1&nodeId=2",
            "?activity%49d=1", "?activityId=%31", "?activityId=1#fragment"]
        for suffix in suffixes { XCTAssertNil(PlayReadRoute(request: request("api/play/nodes" + suffix), baseURL: base), suffix) }
        for path in ["api/play/nodes/", "api/play//nodes", "api/play/%6Eodes", "api/play/ending", "api/play/leaderboard",
                     "api/play/run-session", "api/play/run-session/list", "api/play/answer", "api/play/os/1", "api/club/lead/team-progress"] {
            XCTAssertNil(PlayReadRoute(request: request(path + "?activityId=1"), baseURL: base), path)
        }
    }
    func testRejectsWrongMethodBodyStreamAndAuthority() {
        for method in ["POST", "PUT", "DELETE", "HEAD"] {
            XCTAssertNil(PlayReadRoute(request: request("api/play/nodes?activityId=1", method: method), baseURL: base))
        }
        var body = request("api/play/nodes?activityId=1"); body.httpBody = Data()
        XCTAssertNil(PlayReadRoute(request: body, baseURL: base))
        var stream = request("api/play/nodes?activityId=1"); stream.httpBodyStream = InputStream(data: Data("x".utf8))
        XCTAssertNil(PlayReadRoute(request: stream, baseURL: base))
        for origin in ["https://other.test/native", "https://user@example.test/native", "https://example.test:443/native", "http://example.test/native"] {
            var foreign = request("api/play/nodes?activityId=1")
            foreign.url = URL(string: origin + "/api/play/nodes?activityId=1")
            XCTAssertNil(PlayReadRoute(request: foreign, baseURL: base))
        }
    }
    func testMethodNormalizationCannotChangeTheActualGETOnlyFence() {
        let candidate = request("api/play/nodes?activityId=1", method: "get")
        // Foundation implementations may normalize known method spellings at assignment.
        // The matcher governs the actual request; pre-normalization spelling is unavailable.
        XCTAssertEqual(PlayReadRoute(request: candidate, baseURL: base) != nil, candidate.httpMethod == "GET")
    }
    func testRuntimeReadFeatureAndExactApprovedEndpointAreIndependent() throws {
        let route = try XCTUnwrap(PlayReadRoute(request: request("api/play/nodes?topicId=41"), baseURL: base))
        let context = RuntimeDependencyContext(market: .china, baseURL: base, role: "player",
            session: try .init(accountID: 7, epoch: 1, namespace: "synthetic", token: "synthetic"))
        for (market, account, namespace, paths, enabled, expected) in [
            (RegionalMarket.china, 7, "synthetic", ["api/play/nodes"], true, true),
            (.china, 7, "synthetic", ["api/play/route-state"], true, false),
            (.china, 7, "synthetic", ["api/play/nodes"], false, false),
            (.china, 8, "synthetic", ["api/play/nodes"], true, false),
            (.china, 7, "other", ["api/play/nodes"], true, false),
            (.unitedStates, 7, "synthetic", ["api/play/nodes"], true, false)] {
            let approval = try OperationEndpointApproval(baseURL: base, namespace: namespace, accountID: account, paths: Set(paths))
            XCTAssertEqual(route.isApproved(configuration: .init(market: market, endpoints: approval, play: enabled ? [.reads] : [], playReadApprovalID: UUID()), context: context), expected)
        }
        XCTAssertFalse(route.isApproved(configuration: nil, context: context))
    }
}

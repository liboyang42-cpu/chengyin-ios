import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class ShopNPCHostTests: XCTestCase {
    final class HTTP: HTTPTransport {
        var requests: [URLRequest] = []
        var status = 200
        var body = Data(#"{"code":200,"data":{"text":"answer"}}"#.utf8)
        var beforeReturn: (() -> Void)?
        var failure: Error?
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request); beforeReturn?()
            if let failure { throw failure }
            return (body, status)
        }
    }
    func scope(role: String = "player", revision: UInt64 = 1) -> ShopNPCScope {
        .init(sessionID: "test:4:activity:8", accountID: "3", roleID: role, accessRevision: revision, nodeID: ShopNPCNodeID(17)!)
    }
    func grants() -> ShopNPCGrants {
        var value = ShopNPCGrants(); value.server = true; value.provider = true; value.legal = true; value.access = true
        return value
    }
    func request(scope: ShopNPCScope) -> ShopNPCHTTPRequest {
        .init(path: "/api/ai/npc/shop-chat", method: "POST", contentType: "application/json",
              body: Data("{\"requestId\":\"\(UUID().uuidString)\",\"nodeId\":17,\"message\":\"hello\"}".utf8), scope: scope)
    }
    func configuration() throws -> APIConfiguration { try .init(baseURL: URL(string: "https://example.test")!) }
    func testOnlyActualNamedNodeNPCIsDecoded() throws {
        let decoder = JSONDecoder()
        for raw in [#"{"nodeId":17,"merchantId":900}"#, #"{"nodeId":17,"npc":null}"#,
                    #"{"nodeId":17,"npc":7}"#, #"{"nodeId":17,"npc":{"name":"  "}}"#,
                    #"{"nodeId":17,"npc":{"name":7}}"#] {
            XCTAssertNil(try decoder.decode(PlayNode.self, from: Data(raw.utf8)).npc)
        }
        let node = try decoder.decode(PlayNode.self, from: Data(#"{"nodeId":17,"merchantId":900,"npc":{"name":"Guide","greeting":"Hello"}}"#.utf8))
        XCTAssertEqual(node.id, 17); XCTAssertEqual(node.npc?.name, "Guide"); XCTAssertEqual(node.npc?.greeting, "Hello")
    }
    func testProductionGateDefaultsOffWithNoHTTP() async throws {
        let http = HTTP(); let binding = try ShopNPCHostSession(scope: scope(), token: "test-token")
        let adapter = ShopNPCAuthenticatedHTTPTransport(configuration: try configuration(), transport: http, currentSession: { binding }, currentGrants: grants)
        do { _ = try await adapter.perform(request(scope: scope())); XCTFail("Expected disabled") }
        catch { XCTAssertEqual(error as? ShopNPCFailure, .disabled) }
        XCTAssertTrue(http.requests.isEmpty)
    }
    func testPolicyGrantsDefaultOffWithNoHTTP() async throws {
        let http = HTTP(); let binding = try ShopNPCHostSession(scope: scope(), token: "test-token")
        let adapter = ShopNPCAuthenticatedHTTPTransport(configuration: try configuration(), transport: http, productionWritesEnabled: true, currentSession: { binding })
        do { _ = try await adapter.perform(request(scope: scope())); XCTFail("Expected disabled") }
        catch { XCTAssertEqual(error as? ShopNPCFailure, .disabled) }
        XCTAssertTrue(http.requests.isEmpty)
    }
    func testExactAuthenticatedNodeDispatch() async throws {
        let http = HTTP(); let binding = try ShopNPCHostSession(scope: scope(), token: "test-token")
        let adapter = ShopNPCAuthenticatedHTTPTransport(configuration: try configuration(), transport: http, productionWritesEnabled: true, currentSession: { binding }, currentGrants: grants)
        _ = try await adapter.perform(request(scope: scope()))
        let sent = try XCTUnwrap(http.requests.first)
        XCTAssertEqual(sent.url?.absoluteString, "https://example.test/api/ai/npc/shop-chat")
        XCTAssertEqual(sent.value(forHTTPHeaderField: "Authorization"), "test-token")
        XCTAssertEqual(sent.httpMethod, "POST"); XCTAssertEqual(sent.cachePolicy, .reloadIgnoringLocalCacheData)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(sent.httpBody)) as? [String: Any])
        XCTAssertEqual(body["nodeId"] as? Int, 17); XCTAssertNil(body["bizId"]); XCTAssertNil(body["merchantId"])
    }
    func testWrongRoleOrAccessRevisionNeverDispatches() async throws {
        let http = HTTP(); let binding = try ShopNPCHostSession(scope: scope(), token: "test-token")
        let adapter = ShopNPCAuthenticatedHTTPTransport(configuration: try configuration(), transport: http, productionWritesEnabled: true, currentSession: { binding }, currentGrants: grants)
        for stale in [scope(role: "merchant"), scope(revision: 2)] {
            do { _ = try await adapter.perform(request(scope: stale)); XCTFail("Expected stale") }
            catch { XCTAssertEqual(error as? ShopNPCFailure, .stale) }
        }
        XCTAssertTrue(http.requests.isEmpty)
    }
    func testMissingNodeAuthorityNeverDispatches() async throws {
        let http = HTTP()
        let adapter = ShopNPCAuthenticatedHTTPTransport(configuration: try configuration(), transport: http, productionWritesEnabled: true, currentSession: { nil }, currentGrants: grants)
        do { _ = try await adapter.perform(request(scope: scope())); XCTFail("Expected stale") }
        catch { XCTAssertEqual(error as? ShopNPCFailure, .stale) }
        XCTAssertTrue(http.requests.isEmpty)
    }
    func testRevalidationImmediatelyBeforeDispatch() async throws {
        let http = HTTP(); let binding = try ShopNPCHostSession(scope: scope(), token: "test-token"); var reads = 0
        let adapter = ShopNPCAuthenticatedHTTPTransport(configuration: try configuration(), transport: http, productionWritesEnabled: true,
            currentSession: { reads += 1; return reads == 1 ? binding : nil }, currentGrants: grants)
        do { _ = try await adapter.perform(request(scope: scope())); XCTFail("Expected stale") }
        catch { XCTAssertEqual(error as? ShopNPCFailure, .stale) }
        XCTAssertTrue(http.requests.isEmpty)
    }
    func testLateReplyAfterAuthorityRevokedIsRejected() async throws {
        let http = HTTP(); var binding: ShopNPCHostSession? = try .init(scope: scope(), token: "test-token")
        http.beforeReturn = { binding = nil }
        let adapter = ShopNPCAuthenticatedHTTPTransport(configuration: try configuration(), transport: http, productionWritesEnabled: true, currentSession: { binding }, currentGrants: grants)
        do { _ = try await adapter.perform(request(scope: scope())); XCTFail("Expected unknown") }
        catch { XCTAssertEqual(error as? ShopNPCFailure, .unknownOutcome) }
        XCTAssertEqual(http.requests.count, 1)
    }
    func testNetworkFailureRemainsUnknownOutcome() async throws {
        let http = HTTP(); http.failure = ShopNPCFailure.disabled
        let binding = try ShopNPCHostSession(scope: scope(), token: "test-token")
        let adapter = ShopNPCAuthenticatedHTTPTransport(configuration: try configuration(), transport: http, productionWritesEnabled: true, currentSession: { binding }, currentGrants: grants)
        do { _ = try await adapter.perform(request(scope: scope())); XCTFail("Expected unknown") }
        catch { XCTAssertEqual(error as? ShopNPCFailure, .unknownOutcome) }
        XCTAssertEqual(http.requests.count, 1)
    }
    func testMatchingUnauthorizedExpiresCapturedBinding() async throws {
        let http = HTTP(); http.status = 401
        let binding = try ShopNPCHostSession(scope: scope(), token: "test-token"); var expired: ShopNPCHostSession?
        let adapter = ShopNPCAuthenticatedHTTPTransport(configuration: try configuration(), transport: http, productionWritesEnabled: true,
            currentSession: { binding }, currentGrants: grants, onUnauthorized: { expired = $0 })
        do { _ = try await adapter.perform(request(scope: scope())); XCTFail("Expected unknown") }
        catch { XCTAssertEqual(error as? ShopNPCFailure, .unknownOutcome) }
        XCTAssertEqual(expired, binding)
    }
}

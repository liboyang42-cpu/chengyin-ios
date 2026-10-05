import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class MerchantNPCAuthenticatedTransportTests: XCTestCase {
    final class HTTP: HTTPTransport {
        var requests: [URLRequest] = []
        var beforeReturn: (() -> Void)?
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request); beforeReturn?()
            return (Data(#"{"code":200,"data":{"outcomeStatus":"SUCCEEDED"}}"#.utf8), 200)
        }
    }
    func binding() -> MerchantNPCScope { .init(accountID: 4, namespace: "test:cn", epoch: UUID(), merchantRowID: PublicMerchantRowID(71)!, accessRevision: UUID()) }
    func configuration() throws -> APIConfiguration { try .init(baseURL: URL(string: "https://example.test")!) }
    func request(_ scope: MerchantNPCScope, row: Int = 71, path: String = "/api/ai/npc/merchant-chat") -> MerchantNPCHTTPRequest {
        .init(path: path, method: "POST", body: Data("{\"requestId\":\"\(UUID().uuidString)\",\"bizId\":\(row),\"message\":\"hello\"}".utf8), scope: scope)
    }
    func granted() -> MerchantNPCGrants { var result = MerchantNPCGrants(); result.server = true; result.provider = true; result.legal = true; return result }
    func testProductionDefaultOff() async throws {
        let scope = binding(), http = HTTP()
        let adapter = MerchantNPCAuthenticatedTransport(configuration: try configuration(), transport: http, currentScope: { _ in scope }, token: { "token" }, grants: granted)
        do { _ = try await adapter.perform(request(scope)); XCTFail() } catch { XCTAssertEqual(error as? MerchantNPCFailure, .disabled) }
        XCTAssertTrue(http.requests.isEmpty)
    }
    func testPolicyDefaultOff() async throws {
        let scope = binding(), http = HTTP()
        let adapter = MerchantNPCAuthenticatedTransport(configuration: try configuration(), transport: http, enabled: true, currentScope: { _ in scope }, token: { "token" })
        do { _ = try await adapter.perform(request(scope)); XCTFail() } catch { XCTAssertEqual(error as? MerchantNPCFailure, .disabled) }
        XCTAssertTrue(http.requests.isEmpty)
    }
    func testMerchantRowNeverOwnerOrPlayNode() async throws {
        let scope = binding(), http = HTTP()
        let adapter = MerchantNPCAuthenticatedTransport(configuration: try configuration(), transport: http, enabled: true, currentScope: { _ in scope }, token: { "token" }, grants: granted)
        do { _ = try await adapter.perform(request(scope, row: scope.accountID)); XCTFail() } catch { XCTAssertEqual(error as? MerchantNPCFailure, .disabled) }
        do { _ = try await adapter.perform(request(scope, path: "/api/ai/npc/shop-chat")); XCTFail() } catch { XCTAssertEqual(error as? MerchantNPCFailure, .invalid) }
        XCTAssertTrue(http.requests.isEmpty)
    }
    func testExactMerchantJSONAndRawAuthorization() async throws {
        let scope = binding(), http = HTTP()
        let adapter = MerchantNPCAuthenticatedTransport(configuration: try configuration(), transport: http, enabled: true, currentScope: { _ in scope }, token: { "raw-token" }, grants: granted)
        _ = try await adapter.perform(request(scope))
        XCTAssertEqual(http.requests.count, 1)
        XCTAssertEqual(http.requests[0].url?.path, "/api/ai/npc/merchant-chat")
        XCTAssertEqual(http.requests[0].value(forHTTPHeaderField: "Authorization"), "raw-token")
        XCTAssertFalse(http.requests[0].httpShouldHandleCookies)
    }
    func testPostDispatchScopeChangeIsUnknown() async throws {
        let scope = binding(), http = HTTP(); var active: MerchantNPCScope? = scope
        http.beforeReturn = { active = nil }
        let adapter = MerchantNPCAuthenticatedTransport(configuration: try configuration(), transport: http, enabled: true, currentScope: { _ in active }, token: { "token" }, grants: granted)
        do { _ = try await adapter.perform(request(scope)); XCTFail() } catch { XCTAssertEqual(error as? MerchantNPCFailure, .unknownOutcome) }
        XCTAssertEqual(http.requests.count, 1)
    }
}

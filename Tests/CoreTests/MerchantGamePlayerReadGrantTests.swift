import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import QuestifyCore

final class MerchantGamePlayerReadGrantTests: XCTestCase {
    private let base = URL(string: "https://synthetic.example.test/native")!
    private func grant(_ paths: Set<String> = MerchantGamePlayerReadGrant.playerPaths) throws -> MerchantGamePlayerReadGrant {
        .init(market: .china, endpoints: try OperationEndpointApproval(baseURL: base, namespace: "fixture", accountID: 10, paths: paths))
    }
    func testOnlyOriginalPlayerReadPathsAreAccepted() throws {
        let grant = try grant(), api = try APIConfiguration(baseURL: base)
        let uuid = UUID().uuidString
        for path in ["api/merchant/authoring/player/20/game", "api/merchant/authoring/player/20/requests/\(uuid)"] {
            XCTAssertTrue(grant.allows(configuration: api, namespace: "fixture", accountID: 10, path: path))
        }
        for path in ["api/ai/npc/merchant-chat", "api/merchant/authoring/releases", "api/merchant/authoring/player/020/game",
                     "api/merchant/authoring/player/0/game", "api/merchant/authoring/player/20/game?grant=true",
                     "api/merchant/authoring/player/20/requests/not-a-uuid", "api/merchant/authoring/player/20/game/extra"] {
            XCTAssertFalse(grant.allows(configuration: api, namespace: "fixture", accountID: 10, path: path))
        }
    }
    func testPublicationApprovalDoesNotAuthorizeOriginalResultRead() throws {
        let grant = try grant(["api/merchant/authoring/player/{merchantId}/game"])
        XCTAssertFalse(grant.allows(configuration: try APIConfiguration(baseURL: base), namespace: "fixture", accountID: 10,
                                    path: "api/merchant/authoring/player/20/requests/\(UUID().uuidString)"))
    }
    func testAccountNamespaceAndDeploymentRemainIndependentFences() throws {
        let grant = try grant(), path = "api/merchant/authoring/player/20/game", api = try APIConfiguration(baseURL: base)
        XCTAssertFalse(grant.allows(configuration: api, namespace: "another", accountID: 10, path: path))
        XCTAssertFalse(grant.allows(configuration: api, namespace: "fixture", accountID: 11, path: path))
        XCTAssertFalse(grant.allows(configuration: try APIConfiguration(baseURL: URL(string: "https://another.example.test/native")!),
                                    namespace: "fixture", accountID: 10, path: path))
    }
    func testWireRouteRejectsWritesCookiesBodiesQueriesAndWrongOrigin() {
        let path = "api/merchant/authoring/player/20/requests/" + UUID().uuidString
        var valid = URLRequest(url: base.appendingPathComponent(path))
        valid.httpMethod = "GET"; valid.httpShouldHandleCookies = false
        XCTAssertEqual(MerchantGamePlayerReadRoute(request: valid, baseURL: base)?.path, path)
        for mode in 0..<8 {
            var request = valid
            switch mode {
            case 0: request.httpMethod = "POST"
            case 1: request.httpBody = Data()
            case 2: request.httpShouldHandleCookies = true
            case 3: request.setValue("sid=synthetic", forHTTPHeaderField: "Cookie")
            case 4: request.setValue("synthetic", forHTTPHeaderField: "Proxy-Authorization")
            case 5: request.url = URL(string: valid.url!.absoluteString + "?read=true")!
            case 6: request.url = URL(string: valid.url!.absoluteString + "#fragment")!
            default: request.url = URL(string: "https://another.example.test/native/" + path)!
            }
            XCTAssertNil(MerchantGamePlayerReadRoute(request: request, baseURL: base))
        }
    }

}

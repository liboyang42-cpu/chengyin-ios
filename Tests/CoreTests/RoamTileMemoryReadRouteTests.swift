import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor final class RoamTileMemoryReadRouteTests: XCTestCase {
    private let base = URL(string: "https://tiles.example/native")!
    private func request(_ query: String = "afterId=0&limit=1000") -> URLRequest {
        var r = URLRequest(url: URL(string: base.absoluteString + "/api/roam/tiles/page?" + query)!)
        r.httpMethod = "GET"; r.setValue("application/json", forHTTPHeaderField: "Accept"); return r
    }
    private func context(epoch: UInt64 = 1, account: Int = 81, role: String = "player", token: String = "synthetic-tiles") throws -> RuntimeDependencyContext {
        .init(market: .china, baseURL: base, role: role,
              session: try .init(accountID: account, epoch: epoch, namespace: "synthetic", token: token))
    }
    func testExactServiceQueryAndBounds() throws {
        for cursor in [0, 1, Int.max] { for limit in [1,1000,2000] {
            let route = try XCTUnwrap(RoamTileMemoryReadRoute(request: request("afterId=\(cursor)&limit=\(limit)"), baseURL: base))
            XCTAssertEqual(route.afterID, cursor); XCTAssertEqual(route.limit, limit)
        } }
    }
    func testNoncanonicalExtraDuplicateMissingAndOutOfRangeQueryRejects() {
        for q in ["", "afterId=0", "limit=1000", "afterId=0&limit=0", "afterId=-1&limit=10", "afterId=0&limit=2001", "afterId=00&limit=10", "afterId=%30&limit=10", "limit=10&afterId=0", "afterId=0&limit=10&memberId=81", "afterId=0&limit=10&limit=10", "afterId=9999999999999999999999&limit=10", "afterId=0&limit=10#x"] {
            XCTAssertNil(RoamTileMemoryReadRoute(request: request(q), baseURL: base), q)
        }
    }
    func testWrongMethodOriginPathBodyAndStreamReject() {
        var wrong: [URLRequest] = []
        for method in ["POST","PUT","DELETE"] { var r=request();r.httpMethod=method;wrong.append(r) }
        for path in ["/api/roam/tiles", "/api/roam/reveal", "/api/roam/session", "/api/roam/tiles/page/"] {
            var r=request();r.url=URL(string:base.absoluteString+path+"?afterId=0&limit=1000");wrong.append(r)
        }
        var r=request();r.url=URL(string:"https://other.example/native/api/roam/tiles/page?afterId=0&limit=1000");wrong.append(r)
        r=request();r.httpBody=Data();wrong.append(r)
        r=request();r.httpBodyStream=InputStream(data:Data());wrong.append(r)
        r=request();r.setValue(nil,forHTTPHeaderField:"Accept");wrong.append(r)
        for r in wrong { XCTAssertNil(RoamTileMemoryReadRoute(request:r,baseURL:base)) }
    }
    func testAccessUsesOnlyIndependentExactPathAndIdentity() throws {
        let current=try context()
        let approved=try OperationEndpointApproval(baseURL:base,namespace:"synthetic",accountID:81,paths:[RoamTileMemoryReadRoute.path])
        let access=try RoamTileMemoryReadAccess(context:current,approval:approved)
        XCTAssertTrue(access.matches(current))
        for changed in [try context(epoch:2),try context(account:82),try context(role:"merchant"),try context(token:"new-token")] { XCTAssertFalse(access.matches(changed)) }
        for paths in [Set<String>(),["api/roam/reveal"],[RoamTileMemoryReadRoute.path,"api/roam/session"]] {
            let other=try OperationEndpointApproval(baseURL:base,namespace:"synthetic",accountID:81,paths:paths)
            XCTAssertThrowsError(try RoamTileMemoryReadAccess(context:current,approval:other))
        }
        access.revoke();XCTAssertFalse(access.matches(current));access.revoke();XCTAssertFalse(access.matches(current))
    }
    func testStrictSuccessPageAndCursorNoInventedEmpty() throws {
        let route=try XCTUnwrap(RoamTileMemoryReadRoute(request:request("afterId=5&limit=2"),baseURL:base))
        for body in [#"{"code":200,"data":{"tiles":[],"nextAfterId":5,"hasMore":false}}"#,
                     #"{"code":200,"data":{"tiles":["wx4g0ec"],"nextAfterId":6,"hasMore":true}}"#] {
            XCTAssertNoThrow(try route.validateResponse((Data(body.utf8),200)))
        }
        for body in [#"{"code":200}"#, #"{"code":200,"data":{"nextAfterId":5,"hasMore":false}}"#,
                     #"{"code":200,"data":{"tiles":null,"nextAfterId":5,"hasMore":false}}"#,
                     #"{"code":200,"data":{"tiles":[],"nextAfterId":4,"hasMore":false}}"#,
                     #"{"code":200,"data":{"tiles":[],"nextAfterId":5,"hasMore":true}}"#,
                     #"{"code":200,"data":{"tiles":["bad"],"nextAfterId":6,"hasMore":false}}"#,
                     #"{"code":200,"data":{"tiles":[],"nextAfterId":true,"hasMore":false}}"#] {
            XCTAssertThrowsError(try route.validateResponse((Data(body.utf8),200)))
        }
    }
    func testExistingHTTPAndBusinessFailuresStayServiceErrors() throws {
        let route=try XCTUnwrap(RoamTileMemoryReadRoute(request:request(),baseURL:base))
        for status in [401,403,503] { XCTAssertNoThrow(try route.validateResponse((Data(),status))) }
        for code in [401,500] { XCTAssertNoThrow(try route.validateResponse((Data("{\"code\":\(code)}".utf8),200))) }
        XCTAssertThrowsError(try route.validateResponse((Data(),200)))
    }
}

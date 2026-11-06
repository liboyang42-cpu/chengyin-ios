import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor final class RoamSessionFactReadRouteTests: XCTestCase {
    private let base = URL(string: "https://session-facts.example/native")!
    private func request(_ query: String = "sessionId=17") -> URLRequest {
        var r = URLRequest(url: URL(string: base.absoluteString + "/api/roam/session?" + query)!)
        r.httpMethod = "GET"; r.setValue("application/json", forHTTPHeaderField: "Accept"); return r
    }
    private func context(epoch: UInt64 = 1, account: Int = 81, role: String = "player", token: String = "synthetic-facts") throws -> RuntimeDependencyContext {
        .init(market: .china, baseURL: base, role: role,
              session: try .init(accountID: account, epoch: epoch, namespace: "synthetic", token: token))
    }
    func testExactSessionIDQueryAndSignedLongBounds() throws {
        for id in [1,17,Int.max] {
            let route = try XCTUnwrap(RoamSessionFactReadRoute(request: request("sessionId=\(id)"), baseURL: base))
            XCTAssertEqual(route.sessionID, id)
        }
    }
    func testInvalidMissingExtraOrClientKeyQueriesAreNotRoutes() {
        for q in ["", "sessionId=0", "sessionId=-1", "sessionId=01", "sessionId=+1", "sessionId=1.0", "sessionId=%31", "sessionId=9223372036854775808", "sessionId=17&sessionId=17", "sessionId=17&memberId=81", "sessionId=17&clientSessionKey=abc", "clientSessionKey=abc", "SessionId=17", "sessionId=17#fragment"] {
            XCTAssertNil(RoamSessionFactReadRoute(request:request(q),baseURL:base),q)
        }
    }
    func testMethodsPathOriginBodyAndStreamAreExact() {
        var rows:[URLRequest]=[]
        for method in ["POST","PUT","DELETE"] {var r=request();r.httpMethod=method;rows.append(r)}
        for path in ["api/roam/session/","api/roam/session/17","api/roam/finish","api/roam/reveal","api/roam/tiles/page"] {
            var r=request();r.url=URL(string:base.absoluteString+"/"+path+"?sessionId=17");rows.append(r)
        }
        var r=request();r.url=URL(string:"https://other.example/native/api/roam/session?sessionId=17");rows.append(r)
        r=request();r.httpBody=Data();rows.append(r)
        r=request();r.httpBodyStream=InputStream(data:Data());rows.append(r)
        r=request();r.setValue(nil,forHTTPHeaderField:"Accept");rows.append(r)
        for r in rows {XCTAssertNil(RoamSessionFactReadRoute(request:r,baseURL:base))}
    }
    func testIndependentApprovalCannotBorrowOtherEndpointOrOwner() throws {
        let c=try context(), approval=try OperationEndpointApproval(baseURL:base,namespace:"synthetic",accountID:81,paths:[RoamSessionFactReadRoute.path])
        let access=try RoamSessionFactReadAccess(context:c,approval:approval);XCTAssertTrue(access.matches(c))
        for other in [try context(epoch:2),try context(account:82),try context(role:"merchant"),try context(token:"other")] {XCTAssertFalse(access.matches(other))}
        for paths in [Set<String>(),["api/roam/tiles/page"],["api/roam/reveal"],[RoamSessionFactReadRoute.path,"api/roam/finish"]] {
            let wrong=try OperationEndpointApproval(baseURL:base,namespace:"synthetic",accountID:81,paths:paths)
            XCTAssertThrowsError(try RoamSessionFactReadAccess(context:c,approval:wrong))
        }
        access.revoke();XCTAssertFalse(access.matches(c));access.revoke();XCTAssertFalse(access.matches(c))
    }
    func testApprovalBaseNamespaceAndAccountMustAllMatch() throws {
        let current=try context()
        for approval in [
            try OperationEndpointApproval(baseURL:URL(string:"https://other.example/native")!,namespace:"synthetic",accountID:81,paths:[RoamSessionFactReadRoute.path]),
            try OperationEndpointApproval(baseURL:base,namespace:"other",accountID:81,paths:[RoamSessionFactReadRoute.path]),
            try OperationEndpointApproval(baseURL:base,namespace:"synthetic",accountID:82,paths:[RoamSessionFactReadRoute.path])
        ] {XCTAssertThrowsError(try RoamSessionFactReadAccess(context:current,approval:approval))}
    }
    func testOriginalActiveNotFoundAndIncompleteShapesRemainValidFacts() throws {
        let route=try XCTUnwrap(RoamSessionFactReadRoute(request:request(),baseURL:base))
        for data in [#"{"state":"ACTIVE","sessionId":"17"}"#,
                     #"{"state":"NOT_FOUND"}"#,
                     #"{"state":"FINISHED","sessionId":"17","resultComplete":false,"result":{"totalXp":3}}"#,
                     #"{"state":"FINISHED","sessionId":17,"resultComplete":true,"result":{"totalXp":3}}"#] {
            XCTAssertNoThrow(try route.validateResponse((Data(("{\"code\":200,\"data\":"+data+"}").utf8),200)))
        }
    }
    func testUnknownStateWrongSessionMalformedAndNegativeFactsReject() throws {
        let route=try XCTUnwrap(RoamSessionFactReadRoute(request:request(),baseURL:base))
        for data in ["null","[]","{}",#"{"state":"UNKNOWN"}"#,#"{"state":"ACTIVE","sessionId":18}"#,
                     #"{"state":"ACTIVE","sessionId":0}"#,#"{"state":"FINISHED","sessionId":17,"result":{"totalXp":-1}}"#] {
            XCTAssertThrowsError(try route.validateResponse((Data(("{\"code\":200,\"data\":"+data+"}").utf8),200)))
        }
    }
    func testOriginalSettlementCompletenessIsNotInventedByReadAccess() throws {
        let full=#"{"tileXp":0,"poiXp":0,"totalXp":0,"newTiles":0,"newPois":0,"tilesEver":0,"sessionShops":0}"#
        let complete=try JSONDecoder().decode(RoamSessionFact.self,from:Data(("{\"state\":\"FINISHED\",\"sessionId\":17,\"resultComplete\":true,\"result\":"+full+"}").utf8))
        XCTAssertTrue(complete.hasCompleteSettlement)
        for flag in ["false","null","1"] {
            let fact=try JSONDecoder().decode(RoamSessionFact.self,from:Data(("{\"state\":\"FINISHED\",\"sessionId\":17,\"resultComplete\":"+flag+",\"result\":"+full+"}").utf8))
            XCTAssertFalse(fact.hasCompleteSettlement)
        }
        let partial=try JSONDecoder().decode(RoamSessionFact.self,from:Data(#"{"state":"FINISHED","sessionId":17,"resultComplete":true,"result":{"totalXp":0}}"#.utf8))
        XCTAssertFalse(partial.hasCompleteSettlement)
    }
    func testHTTPAndBusinessFailuresRemainOriginalServiceErrors() throws {
        let route=try XCTUnwrap(RoamSessionFactReadRoute(request:request(),baseURL:base))
        for status in [401,403,503] {XCTAssertNoThrow(try route.validateResponse((Data(),status)))}
        for code in [401,500] {XCTAssertNoThrow(try route.validateResponse((Data("{\"code\":\(code)}".utf8),200)))}
        XCTAssertThrowsError(try route.validateResponse((Data(),200)))
    }
}

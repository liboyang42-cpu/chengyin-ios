import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor final class RoamNearbyEventsReadRouteTests: XCTestCase {
    private let base=URL(string:"https://nearby-events.example/native")!
    private var area:RoamSearchArea { .init(coordinate:RoamCoordinate(latitude:30,longitude:120)!,label:"Selected area") }
    private func request(_ radius:String="3000",extra:[String:String]=[:])->URLRequest {
        var fields=["lat":"30.0","lng":"120.0","radius":radius];fields.merge(extra){_,new in new}
        var parts=URLComponents(url:base.appendingPathComponent(RoamNearbyEventsReadRoute.path),resolvingAgainstBaseURL:false)!
        parts.queryItems=fields.keys.sorted().map{URLQueryItem(name:$0,value:fields[$0])}
        var r=URLRequest(url:parts.url!);r.httpMethod="GET";r.setValue("application/json",forHTTPHeaderField:"Accept");return r
    }
    func testExactOriginalQueryAndTwentyKilometerBound() throws {
        for radius in [1,1000,3000,10000,20000] {
            let value=try XCTUnwrap(RoamNearbyEventsReadRoute(request:request(String(radius)),baseURL:base,area:area))
            XCTAssertEqual(value.radius,radius)
        }
        for value in ["0","-1","20001","03000","3e3","3000.0","+3000"] {
            XCTAssertNil(RoamNearbyEventsReadRoute(request:request(value),baseURL:base,area:area))
        }
    }
    func testCoordinateUnknownDuplicateAndNoncanonicalQueryFailClosed() {
        for extra in [["lat":"31.0"],["lng":"121.0"],["memberId":"81"],["sessionId":"17"],["lat":"nan"],["lat":"30"]] {
            XCTAssertNil(RoamNearbyEventsReadRoute(request:request(extra:extra),baseURL:base,area:area))
        }
        for query in ["lat=30.0&lng=120.0","lat=30.0&lng=120.0&radius=3000&radius=3000","lng=120.0&lat=30.0&radius=3000","lat=%33%30.0&lng=120.0&radius=3000","lat=30.0&lng=120.0&radius"] {
            var r=request();r.url=URL(string:base.appendingPathComponent(RoamNearbyEventsReadRoute.path).absoluteString+"?"+query)
            XCTAssertNil(RoamNearbyEventsReadRoute(request:r,baseURL:base,area:area))
        }
    }
    func testOtherMethodsPathsOriginsBodiesAndHeadersAreNotGranted() {
        var requests:[URLRequest]=[]
        for method in ["POST","PUT","DELETE"] {var r=request();r.httpMethod=method;requests.append(r)}
        for path in ["api/roam/entry/nearby","api/roam/hangout/create","api/roam/hangout/join","api/roam/hangout/nearby/","api/roam/nearby-runners","api/map/nearby"] {
            var r=request();r.url=base.appendingPathComponent(path);requests.append(r)
        }
        var r=request();r.url=URL(string:r.url!.absoluteString+"#fragment");requests.append(r)
        r=request();r.url=URL(string:r.url!.absoluteString.replacingOccurrences(of:"nearby-events.example",with:"other.example"));requests.append(r)
        r=request();r.setValue(nil,forHTTPHeaderField:"Accept");requests.append(r)
        r=request();r.setValue("application/json",forHTTPHeaderField:"Content-Type");requests.append(r)
        r=request();r.httpBody=Data("{}".utf8);requests.append(r)
        r=request();r.httpBodyStream=InputStream(data:Data());requests.append(r)
        for r in requests {XCTAssertNil(RoamNearbyEventsReadRoute(request:r,baseURL:base,area:area))}
    }
    func testIndependentApprovalCannotBorrowPlayersManualOrExpandedPaths() throws {
        let c=RuntimeDependencyContext(market:.china,baseURL:base,role:"player",session:try .init(accountID:81,epoch:1,namespace:"synthetic",token:"synthetic-events"))
        let good=try OperationEndpointApproval(baseURL:base,namespace:"synthetic",accountID:81,paths:[RoamNearbyEventsReadRoute.path])
        let access=try RoamNearbyEventsReadAccess(context:c,approval:good);XCTAssertTrue(access.matches(c))
        for paths in [Set<String>(),["api/roam/nearby-runners"],["api/roam/pois"],[RoamNearbyEventsReadRoute.path,"api/roam/hangout/join"]] {
            let wrong=try OperationEndpointApproval(baseURL:base,namespace:"synthetic",accountID:81,paths:paths)
            XCTAssertThrowsError(try RoamNearbyEventsReadAccess(context:c,approval:wrong))
        }
        access.revoke();XCTAssertFalse(access.matches(c))
    }
    func testEmptyObjectIsDistinctFromMissingOrInvalidResponse() throws {
        let route=try XCTUnwrap(RoamNearbyEventsReadRoute(request:request(),baseURL:base,area:area))
        XCTAssertNoThrow(try route.validateResponse((Data(#"{"code":200,"data":{"items":[],"radius":3000}}"#.utf8),200)))
        for raw in [#"{"code":200}"#,#"{"code":200,"data":null}"#,#"{"code":200,"data":[]}"#,#"{"code":200,"data":{}}"#,#"{"code":200,"data":{"items":null,"radius":3000}}"#,#"{"code":200,"data":{"items":[],"radius":20000}}"#,#"{"code":200,"data":{"items":[],"radius":"3000"}}"#,#"{"code":true,"data":{"items":[],"radius":3000}}"#] {
            XCTAssertThrowsError(try route.validateResponse((Data(raw.utf8),200)))
        }
        for status in [401,403,503] {XCTAssertNoThrow(try route.validateResponse((Data(),status)))}
    }
    func testActivityAndTopicWithSameNumericIDRemainSeparateAndRetiredKindsStayFiltered() throws {
        let route=try XCTUnwrap(RoamNearbyEventsReadRoute(request:request(),baseURL:base,area:area))
        let raw=#"{"items":[{"id":7,"kind":"activity","name":"Activity"},{"id":7,"kind":"topic","name":"Topic"},{"id":7,"kind":"hangout","name":"Retired"}],"radius":3000}"#
        try route.validateResponse((Data(("{\"code\":200,\"data\":"+raw+"}").utf8),200))
        let value=try JSONDecoder().decode(RoamEvents.self,from:Data(raw.utf8))
        XCTAssertEqual(value.items.map(\.id),["activity-7","topic-7"])
        XCTAssertEqual(RoamEventDestination(event:value.items[0]),.activity(7));XCTAssertEqual(RoamEventDestination(event:value.items[1]),.topic(7))
    }
    func testDuplicatesInvalidCurrentIDsAndOversizedListAreRejected() throws {
        let route=try XCTUnwrap(RoamNearbyEventsReadRoute(request:request(),baseURL:base,area:area))
        let row:[String:Any] = ["id":7,"kind":"activity","name":"Activity"]
        let invalid:[Any] = [[row,row],[["id":0,"kind":"activity"]],[["id":-1,"kind":"topic"]],(1...201).map{["id":$0,"kind":"activity"] as [String:Any]}]
        for rows in invalid {XCTAssertThrowsError(try route.validateResponse((JSONSerialization.data(withJSONObject:["code":200,"data":["items":rows,"radius":3000]]),200)))}
    }
    func testPurposeRevisionIsOptionalAndCannotInheritPlayerOrManualAuthority() {
        let old=RoamReadIdentity(accountID:81,epoch:1)
        XCTAssertEqual(old,RoamReadIdentity(accountID:81,epoch:1,nearbyEventsApprovalRevision:nil))
        let fresh=RoamReadIdentity(accountID:81,epoch:1,nearbyEventsApprovalRevision:UUID())
        XCTAssertNotEqual(old,fresh);XCTAssertNil(fresh.manualMapApprovalRevision);XCTAssertNil(fresh.nearbyPlayersApprovalRevision)
    }
}

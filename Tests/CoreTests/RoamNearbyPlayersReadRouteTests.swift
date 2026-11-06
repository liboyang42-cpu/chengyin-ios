import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor final class RoamNearbyPlayersReadRouteTests: XCTestCase {
    private let base=URL(string:"https://nearby-players.example/native")!
    private var area:RoamSearchArea { .init(coordinate:RoamCoordinate(latitude:30,longitude:120)!,label:"Selected area") }
    private func request(_ radius:String="3000", extra:[String:String]=[:]) throws -> URLRequest {
        var fields=["lat":"30.0","lng":"120.0","radius":radius];fields.merge(extra){_,new in new}
        return try AuthRequestBuilder.makeFormRequest(url:base.appendingPathComponent(RoamNearbyPlayersReadRoute.path),fields:fields,token:"synthetic-players",boundary:"synthetic")
    }
    func testExactOriginalMultipartAndServerRadiusBound() throws {
        for radius in [1,1000,3000] {
            let value=try XCTUnwrap(RoamNearbyPlayersReadRoute(request:request(String(radius)),baseURL:base,area:area))
            XCTAssertEqual(value.radius,radius)
        }
        for value in ["0","-1","3001","20000","03000","3e3","3000.0"] {
            XCTAssertNil(RoamNearbyPlayersReadRoute(request:try request(value),baseURL:base,area:area))
        }
    }
    func testCoordinateExtraDuplicateWrongOrderAndBodyShapeAreRejected() throws {
        for extra in [["lat":"31.0"],["lng":"121.0"],["memberId":"81"],["sessionId":"17"],["lat":"nan"],["lat":"30"]] {
            XCTAssertNil(RoamNearbyPlayersReadRoute(request:try request(extra:extra),baseURL:base,area:area))
        }
        var r=try request();let original=String(data:r.httpBody!,encoding:.utf8)!
        r.httpBody=Data(original.replacingOccurrences(of:"--synthetic--\r\n",with:"--synthetic\r\nContent-Disposition: form-data; name=\"radius\"\r\n\r\n3000\r\n--synthetic--\r\n").utf8)
        XCTAssertNil(RoamNearbyPlayersReadRoute(request:r,baseURL:base,area:area))
        r=try request();r.httpBody=Data("{}".utf8);XCTAssertNil(RoamNearbyPlayersReadRoute(request:r,baseURL:base,area:area))
        r=try request();r.httpBodyStream=InputStream(data:Data());XCTAssertNil(RoamNearbyPlayersReadRoute(request:r,baseURL:base,area:area))
    }
    func testMethodURLQueryOriginAndPresenceAreNotReadRoutes() throws {
        var requests:[URLRequest]=[]
        for method in ["GET","PUT","DELETE"] {var r=try request();r.httpMethod=method;requests.append(r)}
        for path in ["api/roam/presence","api/roam/reveal","api/roam/finish","api/roam/nearby-runners/","api/map/nearby"] {
            var r=try request();r.url=base.appendingPathComponent(path);requests.append(r)
        }
        var r=try request();r.url=URL(string:r.url!.absoluteString+"?memberId=81");requests.append(r)
        r=try request();r.url=URL(string:"https://other.example/native/api/roam/nearby-runners");requests.append(r)
        r=try request();r.setValue(nil,forHTTPHeaderField:"Accept");requests.append(r)
        for r in requests {XCTAssertNil(RoamNearbyPlayersReadRoute(request:r,baseURL:base,area:area))}
    }
    func testIndependentApprovalIdentityAndRevocation() throws {
        let c=RuntimeDependencyContext(market:.china,baseURL:base,role:"player",session:try .init(accountID:81,epoch:1,namespace:"synthetic",token:"synthetic-players"))
        let good=try OperationEndpointApproval(baseURL:base,namespace:"synthetic",accountID:81,paths:[RoamNearbyPlayersReadRoute.path])
        let access=try RoamNearbyPlayersReadAccess(context:c,approval:good);XCTAssertTrue(access.matches(c))
        for paths in [Set<String>(),["api/roam/presence"],["api/roam/pois"],[RoamNearbyPlayersReadRoute.path,"api/map/nearby"]] {
            let wrong=try OperationEndpointApproval(baseURL:base,namespace:"synthetic",accountID:81,paths:paths)
            XCTAssertThrowsError(try RoamNearbyPlayersReadAccess(context:c,approval:wrong))
        }
        access.revoke();XCTAssertFalse(access.matches(c))
    }
    func testEmptyIsValidButMissingInvalidDuplicateAndOverLimitRowsFail() throws {
        let route=try XCTUnwrap(RoamNearbyPlayersReadRoute(request:request(),baseURL:base,area:area))
        XCTAssertNoThrow(try route.validateResponse((Data(#"{"code":200,"data":[]}"#.utf8),200)))
        let row:[String:Any] = ["memberId":7,"lat":30.123,"lng":120.456]
        let invalid:[Any] = [NSNull(),[:],[row,row],[["memberId":0,"lat":30,"lng":120]],[["memberId":7,"lat":91,"lng":120]],(1...21).map{["memberId":$0,"lat":30,"lng":120]}]
        for data in invalid {
            XCTAssertThrowsError(try route.validateResponse((JSONSerialization.data(withJSONObject:["code":200,"data":data]),200)))
        }
        XCTAssertThrowsError(try route.validateResponse((Data(#"{"code":200}"#.utf8),200)))
    }
    func testProjectionRemainsCoarseAndHasNoLocationPublicationFields() throws {
        let row=try JSONDecoder().decode(RoamPlayer.self,from:Data(#"{"memberId":7,"nickname":"Runner","lat":30.123456,"lng":120.456789,"explorePct":105,"shops":2,"elapsedSec":5,"avatar":"https://unapproved.example/image"}"#.utf8))
        XCTAssertEqual(row.approximateCoordinate?.latitude,30.123);XCTAssertEqual(row.approximateCoordinate?.longitude,120.456)
        XCTAssertEqual(row.explorePct,99);XCTAssertEqual(row.shops,2);XCTAssertEqual(row.elapsedSec,5)
    }
    func testDedicatedApprovalRevisionRetiresExistingReadAndCameraIdentities() throws {
        let a=RoamReadIdentity(accountID:81,epoch:1,nearbyPlayersApprovalRevision:UUID())
        let b=RoamReadIdentity(accountID:81,epoch:1,nearbyPlayersApprovalRevision:UUID())
        XCTAssertNotEqual(a,b);XCTAssertNil(a.manualMapApprovalRevision)
        let old=RoamReadIdentity(accountID:81,epoch:1);XCTAssertNil(old.nearbyPlayersApprovalRevision)
        XCTAssertEqual(old,RoamReadIdentity(accountID:81,epoch:1,nearbyPlayersApprovalRevision:nil))
    }
}

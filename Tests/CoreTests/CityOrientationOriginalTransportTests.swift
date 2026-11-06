import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@available(macOS 14.0, *) @MainActor final class CityOrientationOriginalTransportTests: XCTestCase {
    let base=URL(string:"https://example.test/city")!
    final class Wire:HTTPTransport {
        var count=0;var reply:()->(Data,Int) = {(Data(),200)}
        func send(_ request:URLRequest) async throws -> (Data,Int) {count+=1;return reply()}
    }
    func grant() throws -> CityOrientationTaskApproval {
        let session=try PlayExperienceSession(accountID:7,epoch:1,namespace:"synthetic-city",token:"synthetic-token",role:"player")
        return try .init(context:.init(market:.china,baseURL:base,role:"player",session:session),scope:.activity(41),sessionID:91,
            capability:.receiptRead,expiresAt:Date().addingTimeInterval(3600))
    }
    func request() -> URLRequest {
        var r=URLRequest(url:URL(string:base.appendingPathComponent("api/play/city-orientation/receipt").absoluteString+"?sessionId=91&nodeId=701&requestId=123E4567-E89B-12D3-A456-426614174000")!)
        r.httpMethod="GET";r.httpShouldHandleCookies=false;r.setValue("application/json",forHTTPHeaderField:"Accept")
        r.setValue("synthetic-token",forHTTPHeaderField:"Authorization");return r
    }
    func testDefaultRegistryContainsNoPermission() throws {
        let read=try grant(),registry=CityOrientationTaskApprovalRegistry()
        XCTAssertNil(registry.approval(context:read.context,sessionID:91,capability:.receiptRead))
        let route=try XCTUnwrap(CityOrientationTaskRoute(request:request(),baseURL:base))
        XCTAssertFalse(route.approved(request:request(),context:read.context,receipt:nil,answer:nil))
    }
    func testReadRouteRejectsDuplicateQueryCookiesAndDifferentRun() throws {
        let read=try grant();var r=request()
        r.url=URL(string:r.url!.absoluteString+"&nodeId=701");XCTAssertNil(CityOrientationTaskRoute(request:r,baseURL:base))
        r=request();r.httpShouldHandleCookies=true;XCTAssertNil(CityOrientationTaskRoute(request:r,baseURL:base))
        r=request();r.url=URL(string:r.url!.absoluteString.replacingOccurrences(of:"sessionId=91",with:"sessionId=92"))
        let route=try XCTUnwrap(CityOrientationTaskRoute(request:r,baseURL:base))
        XCTAssertFalse(route.approved(request:r,context:read.context,receipt:read,answer:nil))
    }
    func testRevokedAndRestoredIssuanceCannotReviveOldPort() async throws {
        let read=try grant(),registry=CityOrientationTaskApprovalRegistry(),wire=Wire();registry.issue(read);let revision=registry.revision
        let port=CityOrientationTaskApprovedTransport(context:read.context,scope:read.scope,sessionID:91,receipt:read,answer:nil,
            underlying:wire,current:{read.context},selected:{registry.approval(context:read.context,sessionID:91,capability:$0)},
            approvalRevision:revision,currentApprovalRevision:{registry.revision})
        registry.revoke(context:read.context,sessionID:91,capability:.receiptRead);registry.issue(read)
        do {_ = try await port.send(request());XCTFail("revoked issuance revived")}catch{}
        XCTAssertEqual(wire.count,0)
    }
    func testInFlightRevocationHidesProjection() async throws {
        let read=try grant(),wire=Wire();var revision:UInt64=1
        let port=CityOrientationTaskApprovedTransport(context:read.context,scope:read.scope,sessionID:91,receipt:read,answer:nil,
            underlying:wire,current:{read.context},selected:{$0 == .receiptRead ? read : nil},approvalRevision:1,currentApprovalRevision:{revision})
        wire.reply={revision=2;return (Data(),200)}
        do {_ = try await port.send(request());XCTFail("stale response projected")}catch{}
        XCTAssertEqual(wire.count,1)
    }
    func testAuthenticationFailureRetiresOnlyCapturedPort() async throws {
        let read=try grant(),wire=Wire();var failures=0;wire.reply={(Data(),401)}
        let port=CityOrientationTaskApprovedTransport(context:read.context,scope:read.scope,sessionID:91,receipt:read,answer:nil,
            underlying:wire,current:{read.context},selected:{$0 == .receiptRead ? read : nil},approvalRevision:0,currentApprovalRevision:{0},
            onUnauthorized:{_ in failures+=1})
        for _ in 0..<2 {do {_ = try await port.send(request());XCTFail("retired auth port dispatched")}catch{}}
        XCTAssertEqual(wire.count,1);XCTAssertEqual(failures,1)
    }
}

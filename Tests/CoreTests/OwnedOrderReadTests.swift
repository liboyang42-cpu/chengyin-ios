import XCTest
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor final class OwnedOrderReadTests: XCTestCase {
    private let base = URL(string: "https://example.test/native")!
    private func form(_ path: String, _ fields: [String:String]) throws -> URLRequest {
        try AuthRequestBuilder.makeFormRequest(url: base.appendingPathComponent("api/registration/" + path), fields: fields, token: "synthetic-7", boundary: "Orders")
    }
    private func context(account: Int = 7, epoch: UInt64 = 1, role: String = "player", token: String = "synthetic-7", realm: String = "fixture", market: RegionalMarket = .china) throws -> RuntimeDependencyContext {
        .init(market: market, baseURL: base, role: role, session: try .init(accountID: account, epoch: epoch, namespace: realm, token: token))
    }
    func testExactUnpaginatedRoutesRejectAllExtraScopeAndMalformedShapes() throws {
        XCTAssertEqual(OwnedOrderReadRoute(request: try form("list", ["owner_type":"3"]), baseURL: base), .list)
        XCTAssertEqual(OwnedOrderReadRoute(request: try form("info", ["id":"41"]), baseURL: base), .detail(41))
        for fields in [[:], ["owner_type":"1"], ["owner_type":"03"], ["owner_type":"3", "memberId":"7"], ["owner_type":"3", "status":"0"], ["owner_type":"3", "is_online":"0"], ["owner_type":"3", "pageNum":"1"], ["owner_type":"3", "pageSize":"10"], ["owner_type":"3", "cursor":"next"]] { XCTAssertNil(OwnedOrderReadRoute(request: try form("list", fields), baseURL: base)) }
        for fields in [["id":"0"], ["id":"-1"], ["id":"041"], ["id":"1.5"], ["id":"41", "memberId":"7"]] { XCTAssertNil(OwnedOrderReadRoute(request: try form("info", fields), baseURL: base)) }
        let exact = try form("info", ["id":"41"])
        var variants:[URLRequest] = []
        for method in ["GET","PUT","PATCH","DELETE"] { var v=exact; v.httpMethod=method; variants.append(v) }
        for url in [exact.url!.absoluteString+"?id=41",exact.url!.absoluteString+"#x",exact.url!.absoluteString+"/","https://other.test/native/api/registration/info"] { var v=exact; v.url=URL(string:url); variants.append(v) }
        let raw=String(data:exact.httpBody!,encoding:.utf8)!
        for body in [raw+"\r\n",raw.replacingOccurrences(of:"\r\n",with:"\n"),raw.replacingOccurrences(of:"--Orders--\r\n",with:"--Orders\r\nContent-Disposition: form-data; name=\"id\"\r\n\r\n42\r\n--Orders--\r\n")] { var v=exact;v.httpBody=Data(body.utf8);variants.append(v) }
        var v=exact;v.httpBody=nil;variants.append(v)
        v=exact;v.httpBodyStream=InputStream(data:Data());variants.append(v)
        for type in ["application/json","multipart/form-data; boundary=wrong","multipart/form-data; boundary=Orders; x=1"] { v=exact;v.setValue(type,forHTTPHeaderField:"Content-Type");variants.append(v) }
        for request in variants { XCTAssertNil(OwnedOrderReadRoute(request:request,baseURL:base)) }
        for path in ["create","pay","pay/app","cancel","cancel-refund","quote","join_info","scan_qr_code"] { XCTAssertNil(OwnedOrderReadRoute(request:try form(path,["id":"41"]),baseURL:base)) }
    }
    func testOwnerCorrelationUniqueIDsAndCompleteTableAreRequired() async throws {
        let wire=Wire(),service=ProfileService(configuration:try APIConfiguration(baseURL:base),transport:wire)
        for body in [#"{"rows":[{"id":41,"memberId":8}],"total":1}"#,#"{"rows":[{"id":41,"memberId":7},{"id":42,"memberId":8}],"total":2}"#,#"{"rows":[{"id":41,"memberId":7},{"id":41,"memberId":7}],"total":2}"#,#"{"rows":[{"id":41}],"total":1}"#,#"{"rows":[],"total":2}"#,#"{"rows":[]}"#,"null",#"[{"id":41,"memberId":7}]"#] {
            wire.json="{\"code\":200,\"data\":\(body)}"
            do { _=try await service.orders(token:"synthetic-7",expectedAccountID:7);XCTFail(body) } catch { XCTAssertEqual(error as? APIError,.malformedResponse) }
        }
        wire.json = #"{"code":200,"data":{"rows":[],"total":0}}"#
        let empty=try await service.orders(token:"synthetic-7",expectedAccountID:7);XCTAssertTrue(empty.isEmpty)
        for body in [#"{"id":42,"memberId":7}"#,#"{"id":41,"memberId":8}"#,#"{"id":41}"#] {
            wire.json="{\"code\":200,\"data\":\(body)}"
            do {_=try await service.order(id:41,token:"synthetic-7",expectedAccountID:7);XCTFail()} catch {XCTAssertEqual(error as? APIError,.malformedResponse)}
        }
    }
    func testDecimalDisplayHasExactPrecisionAndNoStatusOrPointsInference() throws {
        let source = #"{"id":41,"memberId":7,"registrationStatus":2,"paymentStatus":0,"payableAmount":123456789012345678.1234567890123456789,"pointUsed":120,"pointPaymentAmount":1.2,"pointsReturned":0,"refundApplication":{"status":1,"payoutStatus":0,"refundAmount":3.21}}"#
        let order=try JSONDecoder().decode(ProfileOrder.self,from:Data(source.utf8))
        let amount=try XCTUnwrap(order.payableAmount)
        XCTAssertEqual(OwnedOrderMoneyText.string(amount),"123456789012345678.1234567890123456789")
        XCTAssertEqual(order.registrationState,.registered);XCTAssertEqual(order.paymentStatus,0)
        XCTAssertEqual(order.pointUsed,120);XCTAssertEqual(order.pointPaymentAmount,Decimal(string:"1.2"));XCTAssertEqual(order.pointsReturned,0);XCTAssertEqual(order.refundPayoutStatus,0)
        for value in ["0.00000000000000000000000001","12.3456","9007199254740993.01"] {
            XCTAssertEqual(OwnedOrderMoneyText.string(try XCTUnwrap(Decimal(string:value))),value)
        }
        for body in [#"{"id":41,"payableAmount":"12.34"}"#,#"{"id":41,"pointPaymentAmount":-1}"#,#"{"id":41,"refundApplication":{"payoutStatus":1.5}}"#] {XCTAssertThrowsError(try JSONDecoder().decode(ProfileOrder.self,from:Data(body.utf8)))}
    }
    func testApprovalEveryAuthorityDimensionExpiryAndIrreversibleRevocation() throws {
        let original=try context(),approval=try OwnedOrderReadApproval(context:original,expiresAt:Date().addingTimeInterval(600))
        for other in [try context(account:8),try context(epoch:2),try context(role:"merchant"),try context(token:"other"),try context(realm:"other"),try context(market:.unitedStates)] {XCTAssertFalse(approval.matches(other))}
        XCTAssertTrue(approval.matches(original));XCTAssertFalse(approval.matches(original,now:approval.expiresAt))
        let invalidated=expectation(description:"observable authority retired")
        withObservationTracking { _=approval.matches(original) } onChange: {invalidated.fulfill()}
        approval.expireIfNeeded(now:approval.expiresAt)
        XCTAssertTrue(approval.isRevoked);XCTAssertFalse(approval.matches(original,now:Date.distantPast))
        XCTAssertEqual(XCTWaiter.wait(for:[invalidated],timeout:1),.completed)
        XCTAssertThrowsError(try OwnedOrderReadApproval(context:original,expiresAt:Date().addingTimeInterval(-1)))
        XCTAssertThrowsError(try OwnedOrderReadApproval(context:original,expiresAt:Date().addingTimeInterval(90_000)))
    }
    func testExpiryDelayUsesTheTaskStartTimeAndNeverRestartsAnElapsedLease() {
        let deadline = Date(timeIntervalSince1970: 1_000)
        XCTAssertEqual(OwnedOrderReadApproval.expiryDelay(until: deadline, now: deadline.addingTimeInterval(-10)), 10)
        XCTAssertEqual(OwnedOrderReadApproval.expiryDelay(until: deadline, now: deadline), 0)
        XCTAssertEqual(OwnedOrderReadApproval.expiryDelay(until: deadline, now: deadline.addingTimeInterval(10)), 0)
        XCTAssertEqual(OwnedOrderReadApproval.expiryDelay(until: deadline, now: deadline.addingTimeInterval(-90_000)), 86_400)
    }
    private final class Wire:HTTPTransport {
        var json="{}"
        func send(_ request:URLRequest) async throws ->(Data,Int) {(Data(json.utf8),200)}
    }
}

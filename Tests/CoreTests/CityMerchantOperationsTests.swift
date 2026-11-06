import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Synthetic transport unit tests; not an App or production validation claim.
@available(macOS 14.0, *) @MainActor final class CityMerchantOperationsTests: XCTestCase {
    private let base = URL(string: "https://example.test/native")!
    private func approval(writes: Bool = true) throws -> CityMerchantOperationsApproval {
        try .init(context: .init(market: .china, baseURL: base, role: "merchant", session: .init(accountID: 7, epoch: 1, namespace: "city-merchant", token: "synthetic-token")), regionID: "city-1", allowsIntent: writes, expiresAt: Date().addingTimeInterval(600))
    }
    private func snapshot(status: String = "NONE", requestID: String? = nil, available: Bool = true) throws -> (Data, Int) {
        var value: [String: Any] = ["merchantId":"41","version": status == "NONE" ? 0 : 1,"status":status,"effectiveState":"INHERIT","runtimeApplied":false,"approvalHash":String(repeating:"a",count:64)]
        if let requestID { value["requestId"] = requestID; value["originalRequestId"] = requestID }
        value["availability"] = available ? "AVAILABLE" : "PUBLISHED_MERCHANT_RELATION_UNAVAILABLE"
        if available { value["relation"] = ["regionId":"city-1","boardId":"board-1","seasonId":"season-1","rulesReleaseId":"release-1","pointIds":["point-1"]] }
        return (try JSONSerialization.data(withJSONObject:["code":200,"data":value]),200)
    }
    private func service(_ grant: CityMerchantOperationsApproval, _ wire: Wire, current: (() -> RuntimeDependencyContext?)? = nil) -> CityMerchantOperationsService {
        .init(approval:grant,transport:.init(approval:grant,underlying:wire,current:current ?? { grant.context },selected:{ _ in grant }))
    }
    func testDefaultDisabledDispatchesNothing() async {
        let controller = CityMerchantOperationsController(service:nil,journal:Journal())
        await controller.load(); controller.prepare(.pause,reason:"close own shop")
        XCTAssertNil(controller.confirmation); XCTAssertFalse(controller.canPrepare)
        XCTAssertEqual(controller.messageKey, "cityMerchant.status.checkInput")
    }
    func testLoadOnlyReadsAndRequiresExplicitConfirmationBeforeOnePostAndReceipt() async throws {
        let grant = try approval(), wire = Wire(), journal = Journal()
        var submittedRequestID: String?
        wire.respond = { request in
            if request.httpMethod == "POST" {
                let body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String:Any]
                submittedRequestID = body["requestId"] as? String
                return try self.snapshot(status:"IN_REVIEW",requestID:submittedRequestID)
            }
            if request.url!.path.contains("/request/") { return try self.snapshot(status:"IN_REVIEW",requestID:request.url!.lastPathComponent) }
            return try self.snapshot(status:submittedRequestID == nil ? "NONE":"IN_REVIEW",requestID:submittedRequestID)
        }
        let controller = CityMerchantOperationsController(service:service(grant,wire),journal:journal)
        await controller.load(); XCTAssertEqual(wire.requests.map(\.httpMethod),["GET"])
        controller.prepare(.pause,reason:"close own shop"); XCTAssertEqual(wire.requests.count,1)
        await controller.confirm(try XCTUnwrap(controller.confirmation))
        XCTAssertEqual(wire.requests.filter { $0.httpMethod == "POST" }.count,1)
        XCTAssertNotNil(controller.receipt); XCTAssertNil(controller.pendingRequestID); XCTAssertNil(journal.record)
    }
    func testUnknownPersistsAndRecoveryNeverPostsAgain() async throws {
        let grant = try approval(), wire = Wire(), journal = Journal()
        wire.respond = { request in
            if request.url!.path.hasSuffix("availability") { return try self.snapshot() }
            if request.httpMethod == "POST" { throw URLError(.timedOut) }
            return (Data("{\"code\":409,\"errorCode\":\"UNKNOWN\"}".utf8),409)
        }
        let first = CityMerchantOperationsController(service:service(grant,wire),journal:journal)
        await first.load(); first.prepare(.pause,reason:"close own shop"); await first.confirm(try XCTUnwrap(first.confirmation))
        XCTAssertNotNil(journal.record); XCTAssertFalse(first.canPrepare)
        let reopened = CityMerchantOperationsController(service:service(grant,wire),journal:journal)
        await reopened.load(); await reopened.recover()
        XCTAssertEqual(wire.requests.filter { $0.httpMethod == "POST" }.count,1); XCTAssertNotNil(journal.record)
    }
    func testAccountSwitchAndRevocationBlockBeforeDispatch() async throws {
        let grant = try approval(), wire = Wire(); var live: RuntimeDependencyContext? = grant.context
        let client = service(grant,wire,current:{live})
        live = nil
        do { _ = try await client.availability(); XCTFail("old account allowed") } catch { }
        XCTAssertTrue(wire.requests.isEmpty)
        live = grant.context; grant.revoke()
        do { _ = try await client.availability(); XCTFail("revoked lease allowed") } catch { }
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testRevokedDuringFlightCannotPublishResponse() async throws {
        let grant = try approval(), wire = Wire()
        wire.respond = { _ in grant.revoke(); return try self.snapshot() }
        let controller = CityMerchantOperationsController(service:service(grant,wire),journal:Journal())
        await controller.load(); XCTAssertNil(controller.snapshot)
    }
    func testReadOnlyLeaseCannotSubmitAndUnavailableRelationCannotPrepare() async throws {
        let grant = try approval(writes:false), wire = Wire(); wire.respond = { _ in try self.snapshot(available:false) }
        let controller = CityMerchantOperationsController(service:service(grant,wire),journal:Journal())
        await controller.load();controller.prepare(.pause,reason:"close own shop");XCTAssertNil(controller.confirmation)
        do { _ = try await service(grant,wire).submit(id:UUID(),version:0,kind:.pause,reason:"close",approvalHash:String(repeating:"a",count:64));XCTFail("read lease wrote") } catch { }
        XCTAssertEqual(wire.requests.count,1)
    }
    func testRouteRejectsForeignOriginStaffAPIAndProtectedFields() throws {
        var request=URLRequest(url:base.appendingPathComponent("api/city-game/merchant/operations/intent"));request.httpMethod="POST"
        request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        var body:[String:Any]=["requestId":UUID().uuidString,"expectedVersion":0,"regionId":"city-1","kind":"PAUSE_MERCHANT","reason":"own shop","approvalHash":String(repeating:"a",count:64)]
        request.httpBody=try JSONSerialization.data(withJSONObject:body);XCTAssertNotNil(CityMerchantRoute(request:request,baseURL:base))
        body["merchantId"]="other-shop"; request.httpBody=try JSONSerialization.data(withJSONObject:body);XCTAssertNil(CityMerchantRoute(request:request,baseURL:base))
        request.url=URL(string:"https://foreign.test/api/city-game/merchant/operations/intent");XCTAssertNil(CityMerchantRoute(request:request,baseURL:base))
    }
    @MainActor private final class Wire: HTTPTransport {
        var requests:[URLRequest]=[]
        var respond:((URLRequest)throws->(Data,Int))?
        func send(_ request:URLRequest) async throws -> (Data,Int) { requests.append(request);return try respond?(request) ?? (Data(),500) }
    }
    @MainActor private final class Journal: OperationPendingJournal {
        var record:OperationPendingRecord?
        func pending(ownerKey:String,targetKey:String)throws->OperationPendingRecord? { guard let record,record.ownerKey==ownerKey,record.targetKey==targetKey else{return nil};return record }
        func write(_ value:OperationPendingRecord)throws { guard record==nil||record==value else{throw APIError.invalidRequest};record=value }
        func clear(_ value:OperationPendingRecord)throws { guard record==value else{throw APIError.invalidRequest};record=nil }
    }
}

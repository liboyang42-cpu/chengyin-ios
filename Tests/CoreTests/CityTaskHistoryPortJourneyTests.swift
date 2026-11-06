import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Authored synthetic transport cases; not evidence of execution without a Swift toolchain.
@available(macOS 14.0, *) @MainActor final class CityTaskHistoryPortJourneyTests: XCTestCase {
    let base = URL(string: "https://example.test/native")!
    let instance = "44444444-4444-4444-4444-444444444444", evidence = "33333333-3333-3333-3333-333333333333"
    let accept = "66666666-6666-6666-6666-666666666666", submit = "77777777-7777-7777-7777-777777777777"
    func grant() throws -> CityTaskHistoryApproval {
        try .init(context: .init(market: .china, baseURL: base, role: "player", session: .init(accountID: 7, epoch: 1, namespace: "city-history", token: "synthetic-token")), regionID: "city-1", expiresAt: Date().addingTimeInterval(600))
    }
    func service(_ approval: CityTaskHistoryApproval, _ wire: Wire, current: (() -> RuntimeDependencyContext?)? = nil) -> CityTaskHistoryService {
        .init(approval: approval, transport: .init(approval: approval, underlying: wire, current: current ?? { approval.context }, selected: { _ in approval }))
    }
    func item(_ id: String? = nil, passed: Bool = false) -> [String: Any] {
        ["instanceId":id ?? instance,"regionId":"city-1","boardId":"old-board","seasonId":"old-season","roundId":"round-a","teamId":"11111111-1111-1111-1111-111111111111","sessionId":"22222222-2222-2222-2222-222222222222","taskId":"task-1","pointId":"point-1","rulesReleaseId":"rules-1","contentHash":String(repeating:"a",count:64),"taskHash":String(repeating:"b",count:64),"status":passed ? "PASSED":"ACTIVE","acceptRequestId":accept,"acceptedAt":"2026-10-21T00:00:00Z","evidenceId":evidence,"arrivalAssurance":"MERCHANT_ATTESTED","effectsStatus":"NOT_EXECUTED","memberId":7,"releaseId":1,"version":passed ? 2:1,"attempts":passed ? 1:0,"maxAttempts":2,"title":"Original frozen title"]
    }
    func result() -> [String:Any] {
        var value=item(passed:true)
        for key in ["title","version","attempts","maxAttempts","acceptedAt","status"] { value.removeValue(forKey:key) }
        value.merge(["resultId":"55555555-5555-5555-5555-555555555555","requestId":submit,"outcome":"PASSED","createdAt":"2026-10-21T00:01:00Z","evidenceCheckedAt":"2026-10-21T00:01:00Z","evidenceExpiresAt":"2026-10-21T00:03:00Z","evidencePolicyHash":String(repeating:"c",count:64),"verifier":"NATIVE_OBJECTIVE_QA_PICK_V1","merchantId":41,"placeId":61,"attemptNumber":1]) { _, new in new };return value
    }
    func baseData() -> [String:Any] { ["contract":"CITY_PERSONAL_TASK_HISTORY_V1","scope":"OWN_ONSITE_TASKS_ONLY","regionId":"city-1","readAt":"2026-10-21T01:00:00Z","currentQualification":"NOT_EVALUATED","memberId":7,"readOnly":true] }
    func response(_ data: [String:Any], status: Int = 200) throws -> (Data,Int) { (try JSONSerialization.data(withJSONObject:["code":status,"data":data]),status) }
    func page(_ values: [[String:Any]], next: String? = nil) throws -> (Data,Int) { var data=baseData();data["items"]=values;data["pageSize"]=20;if let next {data["nextBeforeInstanceId"]=next};return try response(data) }
    func detail() throws -> (Data,Int) {
        var data=baseData();data["instance"]=item(passed:true);data["result"]=result();data["attempts"]=[["attemptId":"88888888-8888-8888-8888-888888888888","requestId":submit,"optionId":"yes","createdAt":"2026-10-21T00:01:00Z","evidenceCheckedAt":"2026-10-21T00:01:00Z","attemptNumber":1,"passed":true]];return try response(data)
    }
    func testDefaultDisabledHasNoReadOrWrite() async { let c=CityTaskHistoryController(service:nil);await c.load();XCTAssertFalse(c.loaded);XCTAssertTrue(c.items.isEmpty);XCTAssertNil(c.detail) }
    func testNormalOwnOldSeasonHistoryDetailAndOriginalReceiptUsesGetOnly() async throws {
        let approval=try grant(),wire=Wire();wire.respond={request in
            if request.url!.path.contains("/request/") { return try self.response(["requestId":self.submit,"requestStatus":"COMPLETE","result":self.result()]) }
            if request.url!.path.contains("/instance/") { return try self.detail() }
            return try self.page([self.item(passed:true)])
        }
        let c=CityTaskHistoryController(service:service(approval,wire));await c.load();XCTAssertEqual(c.items.first?.seasonId,"old-season");await c.select(try XCTUnwrap(c.items.first));XCTAssertEqual(c.detail?.result?.outcome,"PASSED");await c.readReceipt(submit);XCTAssertEqual(c.receipt?.requestID,submit);XCTAssertEqual(c.receipt?.result?.instanceId,instance);c.closeDetail();XCTAssertNil(c.detail);XCTAssertEqual(c.items.count,1);XCTAssertTrue(wire.requests.allSatisfy{$0.httpMethod=="GET"})
    }
    func testBoundedPageAndMoreNeverReadsArbitraryID() async throws {
        let approval=try grant(),wire=Wire();let ids=(1...20).map{String(format:"99999999-9999-9999-9999-%012d",$0)}
        wire.respond={request in if URLComponents(url:request.url!,resolvingAgainstBaseURL:false)?.queryItems?.count==2 {return try self.page([self.item()])};return try self.page(ids.map{self.item($0)},next:ids.last)}
        let c=CityTaskHistoryController(service:service(approval,wire));await c.load();XCTAssertEqual(c.items.count,20);await c.load(more:true);XCTAssertEqual(c.items.count,21);XCTAssertNil(c.nextBeforeID);await c.readReceipt(UUID().uuidString);XCTAssertEqual(wire.requests.count,2)
    }
    func testAccountSwitchAndRevocationClearAllPersonalFacts() async throws {
        let approval=try grant(),wire=Wire();var live:RuntimeDependencyContext?=approval.context;wire.respond={_ in try self.page([self.item()])}
        let c=CityTaskHistoryController(service:service(approval,wire,current:{live}));await c.load();XCTAssertEqual(c.items.count,1);live=nil;await c.load();XCTAssertTrue(c.items.isEmpty);XCTAssertFalse(c.loaded);XCTAssertEqual(wire.requests.count,1)
        live=approval.context;wire.respond={_ in approval.revoke();return try self.page([self.item()])};await c.load();XCTAssertTrue(c.items.isEmpty);XCTAssertNil(c.detail)
    }
    func testReadRouteRejectsPostForeignActorQueryAndWrongRegion() async throws {
        let approval=try grant(),wire=Wire(),client=service(approval,wire)
        var req=URLRequest(url:URL(string:base.absoluteString+"/api/city-game/task-history?regionId=city-1")!);req.httpMethod="GET";req.httpShouldHandleCookies=false;req.setValue(approval.context.session.token,forHTTPHeaderField:"Authorization");XCTAssertNotNil(CityTaskHistoryRoute(request:req,baseURL:base))
        req.httpMethod="POST";XCTAssertNil(CityTaskHistoryRoute(request:req,baseURL:base));req.httpMethod="GET";req.url=URL(string:base.absoluteString+"/api/city-game/task-history?regionId=city-1&memberId=8")!;XCTAssertNil(CityTaskHistoryRoute(request:req,baseURL:base));req.url=URL(string:base.absoluteString+"/api/city-game/task-history?regionId=other")!
        do {_ = try await client.transport.send(req);XCTFail("wrong region")}catch{};XCTAssertTrue(wire.requests.isEmpty)
    }
    func testFailureOrWrongSubjectIsNeverPresentedAsEmptyHistory() async throws {
        let approval=try grant(),wire=Wire(),c=CityTaskHistoryController(service:nil);await c.load();XCTAssertFalse(c.loaded)
        let client=CityTaskHistoryController(service:service(approval,wire));wire.respond={_ in throw URLError(.timedOut)};await client.load();XCTAssertFalse(client.loaded);XCTAssertEqual(client.messageKey,"cityHistory.status.failed")
        var foreign=item();foreign["memberId"]=8;wire.respond={_ in try self.page([foreign])};await client.load();XCTAssertFalse(client.loaded);XCTAssertTrue(client.items.isEmpty)
        wire.respond={_ in try self.page([])};await client.load();XCTAssertTrue(client.loaded);XCTAssertEqual(client.messageKey,"cityHistory.status.empty")
    }
    func testForeignResultOrDuplicatePageCannotReplaceOriginalFacts() async throws {
        let approval=try grant(),wire=Wire(),client=service(approval,wire)
        var foreign=result();foreign["evidenceId"]="00000000-0000-0000-0000-000000000000"
        var envelope=try JSONSerialization.jsonObject(with:detail().0) as! [String:Any];var value=envelope["data"] as! [String:Any];value["result"]=foreign;envelope["data"]=value;let data=try JSONSerialization.data(withJSONObject:envelope);wire.respond={_ in(data,200)}
        do {_ = try await client.detail(instance);XCTFail("wrong evidence binding")}catch{}
        wire.respond={_ in try self.page([self.item(),self.item()])};do {_ = try await client.page();XCTFail("duplicate records")}catch{}
    }
    func testRetiredReadDoesNotReenterAfterInvalidate() async throws {
        let approval = try grant(), wire = Wire(), c = CityTaskHistoryController(service: service(try grant(), Wire()))
        let controller = CityTaskHistoryController(service: service(approval, wire))
        let review = try XCTUnwrap(controller.captureRead(.refresh))
        XCTAssertEqual(String(describing: review), "CityTaskHistoryReadReview[redacted]")
        controller.invalidate(); await controller.perform(review)
        XCTAssertTrue(wire.requests.isEmpty); XCTAssertFalse(controller.loaded)
        // Review is also bound to its original controller, not a replacement with equal owner facts.
        await c.perform(review); XCTAssertFalse(c.loaded)
    }
    func testOldMoreDoesNotSelectRefreshedCursor() async throws {
        let approval = try grant(), wire = Wire(), controller = CityTaskHistoryController(service: service(approval, wire))
        wire.respond = { _ in try self.page([self.item()], next: self.instance) }
        await controller.load(); let more = try XCTUnwrap(controller.captureRead(.more))
        wire.respond = { _ in try self.page([]) }; await controller.load()
        let before = wire.requests.count; await controller.perform(more)
        XCTAssertEqual(wire.requests.count, before); XCTAssertNil(controller.nextBeforeID)
    }
    func testReceiptReviewCannotCrossDetailVisit() async throws {
        let approval = try grant(), wire = Wire(), controller = CityTaskHistoryController(service: service(approval, wire))
        wire.respond = { request in
            if request.url!.path.contains("/instance/") { return try self.detail() }
            return try self.page([self.item(passed: true)])
        }
        await controller.load(); await controller.select(try XCTUnwrap(controller.items.first))
        let old = try XCTUnwrap(controller.captureRead(.receipt(submit)))
        controller.closeDetail(); await controller.select(try XCTUnwrap(controller.items.first))
        let before = wire.requests.count; await controller.perform(old)
        XCTAssertEqual(wire.requests.count, before); XCTAssertNil(controller.receipt)
    }
    func testReturnReadsCurrentOwnHistoryWithoutReplayingWriter() async throws {
        let approval = try grant(), wire = Wire(), controller = CityTaskHistoryController(service: service(approval, wire))
        wire.respond = { request in
            if request.url!.path.contains("/instance/") { return try self.detail() }
            return try self.page([self.item(passed: true)])
        }
        await controller.load(); await controller.select(try XCTUnwrap(controller.items.first))
        let back = try XCTUnwrap(controller.captureRead(.returnToList)); await controller.perform(back)
        XCTAssertNil(controller.detail); XCTAssertTrue(controller.loaded)
        XCTAssertEqual(wire.requests.count, 3); XCTAssertTrue(wire.requests.allSatisfy { $0.httpMethod == "GET" })
        XCTAssertFalse(wire.requests.last!.url!.path.contains("/instance/"))
    }
    func testCapturedReadCannotCrossGrantRevocation() async throws {
        let approval = try grant(), wire = Wire(), controller = CityTaskHistoryController(service: service(approval, wire))
        let review = try XCTUnwrap(controller.captureRead(.refresh))
        approval.revoke(); await controller.perform(review)
        XCTAssertTrue(wire.requests.isEmpty); XCTAssertFalse(controller.loaded)
    }
    func testChangedCredentialCannotReuseHistoryApproval() throws {
        let approval = try grant(), c = approval.context
        let changed = RuntimeDependencyContext(market: c.market, baseURL: c.baseURL, role: c.role,
            session: try .init(accountID: 7, epoch: 1, namespace: "city-history", token: "different-token", role: "player"))
        XCTAssertFalse(approval.matches(changed))
    }
    func testHistoryTransportRejectsCookiesAndOwnReaderDisablesThem() async throws {
        let approval = try grant(), wire = Wire(), client = service(approval, wire)
        wire.respond = { _ in try self.page([]) }
        var request = URLRequest(url: URL(string: base.absoluteString + "/api/city-game/task-history?regionId=city-1")!)
        request.httpMethod = "GET"; request.setValue(approval.context.session.token, forHTTPHeaderField: "Authorization")
        do { _ = try await client.transport.send(request); XCTFail("Automatic cookies must be denied") } catch {}
        request.httpShouldHandleCookies = false; request.setValue("synthetic-cookie", forHTTPHeaderField: "Cookie")
        do { _ = try await client.transport.send(request); XCTFail("Explicit cookies must be denied") } catch {}
        XCTAssertTrue(wire.requests.isEmpty)
        _ = try await client.page(); XCTAssertEqual(wire.requests.count, 1)
        XCTAssertFalse(try XCTUnwrap(wire.requests.first).httpShouldHandleCookies)
    }
    @MainActor final class Wire:HTTPTransport {
        var requests:[URLRequest]=[];var respond:((URLRequest)throws->(Data,Int))?
        func send(_ request:URLRequest)async throws->(Data,Int){requests.append(request);return try respond?(request) ?? (Data(),500)}
    }
}

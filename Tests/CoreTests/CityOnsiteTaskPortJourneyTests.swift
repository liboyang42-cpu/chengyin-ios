import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Authored synthetic transport tests. Execution requires a real supported Swift toolchain.
@available(macOS 14.0, *) @MainActor final class CityOnsiteTaskPortJourneyTests: XCTestCase {
    let base = URL(string: "https://example.test/native")!
    var board: CityReadBoard { .init(gameId: "game-1", boardId: "board-1", regionId: "city-1", seasonId: "season-1", rulesReleaseId: "release-1", rulesHash: String(repeating: "a", count: 64), lifecycle: "FROZEN", title: "Synthetic CITY", revision: 1) }
    func approval(writes: Bool = true) throws -> CityOnsiteTaskApproval {
        try .init(context: .init(market: .china, baseURL: base, role: "player", session: .init(accountID: 7, epoch: 1, namespace: "city-onsite", token: "synthetic-token")), regionID: "city-1", allowsWrite: writes, expiresAt: Date().addingTimeInterval(600))
    }
    let evidenceID = "33333333-3333-3333-3333-333333333333", instanceID = "44444444-4444-4444-4444-444444444444", resultID = "55555555-5555-5555-5555-555555555555"
    func originalResult(_ accept: String, _ submit: String) -> [String: Any] {
        ["resultId":resultID,"instanceId":instanceID,"taskId":"qa-1","requestId":submit,"acceptRequestId":accept,"outcome":"PASSED","createdAt":"2026-10-21T00:00:00Z","evidenceCheckedAt":"2026-10-21T00:00:00Z","evidenceExpiresAt":"2099-01-01T00:00:00Z","evidenceId":evidenceID,"evidencePolicyHash":String(repeating:"b",count:64),"pointId":"point-1","teamId":"11111111-1111-1111-1111-111111111111","sessionId":"22222222-2222-2222-2222-222222222222","regionId":"city-1","boardId":"board-1","seasonId":"season-1","roundId":"round-a","rulesReleaseId":"release-1","contentHash":String(repeating:"a",count:64),"taskHash":String(repeating:"c",count:64),"verifier":"NATIVE_OBJECTIVE_QA_PICK_V1","arrivalAssurance":"MERCHANT_ATTESTED","effectsStatus":"NOT_EXECUTED","memberId":7,"merchantId":41,"placeId":61,"releaseId":1,"attemptNumber":1]
    }
    func response(_ accept: String? = nil, _ submit: String? = nil) throws -> (Data, Int) {
        let rules: [String:Any] = ["mode":"CITY_TEAM","joinPolicy":"INVITE_CODE","rosterPolicy":"CAPTAIN_LOCK_THEN_EACH_MEMBER_CONFIRM","replacementPolicy":"FORBIDDEN_AFTER_LOCK","reentryPolicy":"RESUME_ORIGINAL_SESSION","roundPolicy":"FIXED_PUBLISHED_ROUND","roundId":"round-a","minMembers":2,"maxMembers":3]
        let binding: [String:Any] = ["releaseId":1,"revision":1,"regionId":"city-1","boardId":"board-1","seasonId":"season-1","rulesReleaseId":"release-1","contentHash":String(repeating:"a",count:64),"title":"Synthetic CITY","rules":rules]
        let definition: [String:Any] = ["taskId":"qa-1","pointId":"point-1","title":"Synthetic question","type":"QA_PICK","access":"ONSITE_ZERO_EFFECT","arrivalRequirement":"MERCHANT_ATTESTED","scope":"MEMBER_POINT_TEAM_ROUND","acceptanceReason":"Synthetic approved human source rationale","evidencePolicy":"SAME_EVIDENCE_VALID_ON_ACCEPT_AND_EACH_SUBMIT","evidenceUse":"SINGLE_TASK_INSTANCE","reviewerPolicy":"CURRENT_STORE_PERMISSION_AND_REVIEWER_VERIFY","effectsPolicy":"NO_AUTOMATIC_EFFECTS","question":"Choose","options":[["id":"a","label":"Alpha"],["id":"b","label":"Beta"]],"maxAttempts":2,"pointCost":0,"pointReward":0,"actionCost":0]
        let evidence: [String:Any] = ["evidenceId":evidenceID,"pointId":"point-1","teamId":"11111111-1111-1111-1111-111111111111","sessionId":"22222222-2222-2222-2222-222222222222","contentHash":String(repeating:"a",count:64),"policyHash":String(repeating:"b",count:64),"roundId":"round-a","expiresAt":"2099-01-01T00:00:00Z","assurance":"MERCHANT_ATTESTED","memberId":7,"merchantId":41,"placeId":61,"releaseId":1]
        var task: [String:Any] = ["definition":definition,"status":submit != nil ? "PASSED" : accept != nil ? "ACTIVE" : "NOT_ACCEPTED","version":submit != nil ? 2 : accept != nil ? 1 : 0,"attempts":submit != nil ? 1 : 0,"eligibility":"ELIGIBLE","canAct":submit == nil,"evidence":evidence]
        if let accept { task["instanceId"]=instanceID; task["evidenceId"]=evidenceID; task["acceptRequestId"]=accept; task["acceptedAt"]="2026-10-21T00:00:00Z"; if let submit { task["result"]=originalResult(accept, submit) } }
        let value: [String:Any] = ["contract":"CITY_ONSITE_TASK_V1","scope":"CITY","status":"AVAILABLE","writeApproved":true,"binding":binding,"teamId":"11111111-1111-1111-1111-111111111111","teamVersion":4,"sessionId":"22222222-2222-2222-2222-222222222222","tasks":[task],"memberId":7,"arrivalProof":"MERCHANT_ATTESTED_ONLY","ownershipEffect":"NONE","pointsEffect":"NONE","effectsStatus":"NOT_EXECUTED"]
        return (try JSONSerialization.data(withJSONObject:["code":200,"data":value]),200)
    }
    func service(_ grant: CityOnsiteTaskApproval, _ wire: Wire, current: (() -> RuntimeDependencyContext?)? = nil) -> CityOnsiteTaskService {
        .init(approval:grant,transport:.init(approval:grant,underlying:wire,current:current ?? {grant.context},selected:{_ in grant}),board:board)
    }
    func testDisabledFactoryCannotPrepareOrSend() async {
        let c=CityOnsiteTaskController(service:nil,journal:Journal());await c.load();if let task=c.snapshot?.tasks.first {c.prepare(task)}
        XCTAssertNil(c.confirmation);XCTAssertFalse(c.canWrite)
    }
    func testAcceptThenAnswerReadsOwnUniqueResultAndOriginalReceipts() async throws {
        let grant=try approval(),wire=Wire(),journal=Journal();var accepted:String?,submitted:String?
        wire.respond={ request in
            if request.httpMethod=="POST" { let body=try JSONSerialization.jsonObject(with:request.httpBody!) as! [String:Any];if body["kind"] as? String == "ACCEPT" { accepted=body["requestId"] as? String } else { submitted=body["requestId"] as? String };return try self.response(accepted,submitted) }
            if request.url!.path.contains("/result/") { return (try JSONSerialization.data(withJSONObject:["code":200,"data":["contract":"CITY_ONSITE_TASK_V1","effectsStatus":"NOT_EXECUTED","result":self.originalResult(try XCTUnwrap(accepted),try XCTUnwrap(submitted))]]),200) }
            if request.url!.path.contains("/request/") { var value:[String:Any]=["requestId":request.url!.lastPathComponent,"requestStatus":"COMPLETE"];if let accepted,let submitted {value["result"]=self.originalResult(accepted,submitted)};return (try JSONSerialization.data(withJSONObject:["code":200,"data":value]),200) }
            return try self.response(accepted,submitted)
        }
        let c=CityOnsiteTaskController(service:service(grant,wire),journal:journal);await c.load();c.prepare(try XCTUnwrap(c.snapshot?.tasks.first));XCTAssertEqual(wire.requests.count,1)
        await c.confirm(try XCTUnwrap(c.confirmation));XCTAssertEqual(c.snapshot?.tasks.first?.status,"ACTIVE")
        c.prepare(try XCTUnwrap(c.snapshot?.tasks.first),optionID:"a");await c.confirm(try XCTUnwrap(c.confirmation));XCTAssertEqual(c.selectedResult?.resultId,resultID);XCTAssertEqual(c.selectedResult?.evidenceId,evidenceID);XCTAssertEqual(c.snapshot?.tasks.first?.status,"PASSED");XCTAssertEqual(wire.requests.filter{$0.httpMethod=="POST"}.count,2);XCTAssertEqual(journal.record?.acknowledgedSteps,1)
    }
    func testTimeoutRestartNeverResubmits() async throws {
        let grant=try approval(), wire=Wire(), journal=Journal()
        wire.respond={ request in
            if request.url!.path.hasSuffix("/state") {return try self.response()}
            if request.httpMethod=="POST" {throw URLError(.timedOut)}
            return (Data("{\"code\":202,\"errorCode\":\"OUTCOME_UNKNOWN\",\"data\":{\"requestId\":\"\(request.url!.lastPathComponent)\",\"requestStatus\":\"UNKNOWN\"}}".utf8),202)
        }
        let first=CityOnsiteTaskController(service:service(grant,wire),journal:journal)
        await first.load();first.prepare(try XCTUnwrap(first.snapshot?.tasks.first));await first.confirm(try XCTUnwrap(first.confirmation))
        let reopened=CityOnsiteTaskController(service:service(grant,wire),journal:journal)
        await reopened.load();await reopened.recover();XCTAssertNotNil(journal.record);XCTAssertFalse(reopened.canWrite)
        XCTAssertEqual(wire.requests.filter{$0.httpMethod=="POST"}.count,1)
    }
    func testAccountSwitchAndRevocationBeforeAndAfterFlight() async throws {
        let grant=try approval(), wire=Wire();var current:RuntimeDependencyContext?=grant.context
        let client=service(grant,wire,current:{current});current=nil
        do {_ = try await client.state();XCTFail("stale account")} catch {}
        XCTAssertTrue(wire.requests.isEmpty);current=grant.context
        wire.respond={_ in grant.revoke();return try self.response()}
        let c=CityOnsiteTaskController(service:client,journal:Journal());await c.load();XCTAssertNil(c.snapshot)
    }
    func testReadOnlyLeaseAndProtectedRouteReject() async throws {
        let grant=try approval(writes:false),wire=Wire();wire.respond={_ in try self.response()}
        let c=CityOnsiteTaskController(service:service(grant,wire),journal:Journal());await c.load();if let task=c.snapshot?.tasks.first {c.prepare(task)};XCTAssertNil(c.confirmation)
        var request=URLRequest(url:base.appendingPathComponent("api/city-game/onsite-tasks/command"));request.httpMethod="POST";request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        var body:[String:Any]=["requestId":UUID().uuidString,"regionId":"city-1","kind":"ACCEPT","releaseId":1,"contentHash":String(repeating:"a",count:64),"expectedVersion":0,"teamId":"11111111-1111-1111-1111-111111111111","expectedTeamVersion":4,"taskId":"qa-1","evidenceId":evidenceID]
        request.httpBody=try JSONSerialization.data(withJSONObject:body);XCTAssertNotNil(CityOnsiteTaskRoute(request:request,baseURL:base))
        body["memberId"]=99;request.httpBody=try JSONSerialization.data(withJSONObject:body);XCTAssertNil(CityOnsiteTaskRoute(request:request,baseURL:base))
        request.url=URL(string:"https://foreign.test/api/city-game/onsite-tasks/command")!;XCTAssertNil(CityOnsiteTaskRoute(request:request,baseURL:base))
    }
    func testHumanAcceptancePolicyAndZeroEffectsCannotBeInferred() async throws {
        let grant=try approval(),wire=Wire(),client=service(grant,wire)
        for field in ["access", "arrivalRequirement", "acceptanceReason", "evidencePolicy", "pointCost"] {
            var envelope=try JSONSerialization.jsonObject(with:response().0) as! [String:Any]
            var value=envelope["data"] as! [String:Any];var tasks=value["tasks"] as! [[String:Any]];var definition=tasks[0]["definition"] as! [String:Any]
            definition.removeValue(forKey:field);tasks[0]["definition"]=definition;value["tasks"]=tasks;envelope["data"]=value
            let data=try JSONSerialization.data(withJSONObject:envelope);wire.respond={_ in (data,200)}
            do {_ = try await client.state();XCTFail("missing explicit field must fail")}catch {}
        }
    }
    func testExpiredEvidenceAndOtherSubjectCannotPrepare() async throws {
        let grant=try approval(),wire=Wire()
        for field in ["expiresAt", "memberId"] {
            var envelope=try JSONSerialization.jsonObject(with:response().0) as! [String:Any];var value=envelope["data"] as! [String:Any];var tasks=value["tasks"] as! [[String:Any]];var evidence=tasks[0]["evidence"] as! [String:Any]
            if field == "memberId" { evidence[field] = 8 } else { evidence[field] = "2020-01-01T00:00:00Z" };tasks[0]["evidence"]=evidence;value["tasks"]=tasks;envelope["data"]=value;let data=try JSONSerialization.data(withJSONObject:envelope);wire.respond={_ in (data,200)}
            let c=CityOnsiteTaskController(service:service(grant,wire),journal:Journal());await c.load();if let task=c.snapshot?.tasks.first{c.prepare(task)};XCTAssertNil(c.confirmation)
        }
    }
    func testHistoricalResultSurvivesCurrentSourceReadFailureWithoutWritableSnapshot() async throws {
        let grant=try approval(),wire=Wire(),journal=Journal(),accept=UUID().uuidString,submit=UUID()
        journal.record = .init(operationID:submit,ownerKey:"city-onsite:city-onsite:\(base.absoluteString):7",targetKey:"city-1:board-1:season-1")
        wire.respond={request in
            if request.url!.path.contains("/request/"){return (try JSONSerialization.data(withJSONObject:["code":200,"data":["requestId":submit.uuidString,"requestStatus":"COMPLETE","result":self.originalResult(accept,submit.uuidString)]]),200)}
            if request.url!.path.contains("/result/"){return (try JSONSerialization.data(withJSONObject:["code":200,"data":["contract":"CITY_ONSITE_TASK_V1","effectsStatus":"NOT_EXECUTED","result":self.originalResult(accept,submit.uuidString)]]),200)}
            return (Data("{\"code\":503,\"errorCode\":\"SOURCE_UNAVAILABLE\"}".utf8),503)
        }
        let c=CityOnsiteTaskController(service:service(grant,wire),journal:journal);await c.load();await c.recover();XCTAssertEqual(c.selectedResult?.resultId,resultID);XCTAssertNil(c.snapshot);XCTAssertFalse(c.canWrite);XCTAssertEqual(journal.record?.acknowledgedSteps,1);XCTAssertTrue(wire.requests.allSatisfy{$0.httpMethod=="GET"})
    }
    func testSameAccountChangedCredentialCannotReuseOnsiteGrant() throws {
        let grant = try approval()
        let changed = RuntimeDependencyContext(market: .china, baseURL: base, role: "player", session: try .init(accountID: 7, epoch: 1, namespace: "city-onsite", token: "replacement-token"))
        XCTAssertFalse(grant.matches(changed))
    }
    func testCookiesRejectedAndNormalStateUsesExplicitTokenOnly() async throws {
        let grant = try approval(), wire = Wire(), client = service(grant, wire)
        var parts = URLComponents(url: base.appendingPathComponent("api/city-game/onsite-tasks/state"), resolvingAgainstBaseURL: false)!
        parts.queryItems = [.init(name: "regionId", value: "city-1")]
        var request = URLRequest(url: parts.url!); request.httpMethod = "GET"; request.setValue(grant.context.session.token, forHTTPHeaderField: "Authorization")
        request.httpShouldHandleCookies = true
        do { _ = try await client.transport.send(request); XCTFail("automatic cookies") } catch {}
        request.httpShouldHandleCookies = false; request.setValue("fake=1", forHTTPHeaderField: "Cookie")
        do { _ = try await client.transport.send(request); XCTFail("explicit cookies") } catch {}
        XCTAssertTrue(wire.requests.isEmpty)
        wire.respond = { request in
            XCTAssertFalse(request.httpShouldHandleCookies); XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
            return try self.response()
        }
        _ = try await client.state(); XCTAssertEqual(wire.requests.count, 1)
    }
    @MainActor final class Wire:HTTPTransport {
        var requests:[URLRequest]=[];var respond:((URLRequest)throws->(Data,Int))?
        func send(_ request:URLRequest)async throws->(Data,Int){requests.append(request);return try respond?(request) ?? (Data(),500)}
    }
    @MainActor final class Journal:OperationPendingReplacing {
        var record:OperationPendingRecord?
        func pending(ownerKey:String,targetKey:String)throws->OperationPendingRecord?{guard let record,record.ownerKey==ownerKey,record.targetKey==targetKey else{return nil};return record}
        func write(_ value:OperationPendingRecord)throws{guard record==nil||record?.operationID==value.operationID else{throw APIError.invalidRequest};record=value}
        func replace(_ previous:OperationPendingRecord,with next:OperationPendingRecord)throws{guard record==previous,previous.ownerKey==next.ownerKey,previous.targetKey==next.targetKey else{throw APIError.invalidRequest};record=next}
        func clear(_ value:OperationPendingRecord)throws{guard record==value else{throw APIError.invalidRequest};record=nil}
    }
}

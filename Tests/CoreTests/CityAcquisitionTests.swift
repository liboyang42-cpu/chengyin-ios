import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Authored synthetic transport cases. Not executed without a supported Swift toolchain.
@available(macOS 14.0, *) @MainActor final class CityAcquisitionTests: XCTestCase {
    let base = URL(string: "https://example.test/native")!
    let instance = "44444444-4444-4444-4444-444444444444", quoteID = "66666666-6666-6666-6666-666666666666", confirmID = "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"
    func approval(writes: Bool = true) throws -> CityAcquisitionApproval {
        try .init(context: .init(market: .china, baseURL: base, role: "player", session: .init(accountID: 7, epoch: 1, namespace: "city-acquire", token: "synthetic-token")), regionID: "city-1", allowsWrite: writes, expiresAt: Date().addingTimeInterval(600))
    }
    func quote() -> [String:Any] {
        ["quoteId":quoteID,"confirmRequestId":confirmID,"quoteHash":String(repeating:"a",count:64),"payerMemberId":7,"beneficiaryTeamId":"11111111-1111-1111-1111-111111111111","sessionId":"22222222-2222-2222-2222-222222222222","regionId":"city-1","boardId":"board-1","seasonId":"season-1","roundId":"round-a","pointId":"point-1","releaseId":1,"contentHash":String(repeating:"a",count:64),"policyHash":String(repeating:"b",count:64),"taskInstanceId":instance,"taskResultId":"55555555-5555-5555-5555-555555555555","evidenceId":"33333333-3333-3333-3333-333333333333","evidenceAssurance":"MERCHANT_ATTESTED","evidenceAcceptanceReason":"Synthetic reviewed reason","merchantId":41,"placeId":61,"pointCost":30,"actionCost":2,"maxHoldingsPerTeam":1,"termSeconds":600,"teamVersion":4,"budgetVersion":0,"pointVersion":0,"merchantVersion":0,"platformVersion":0,"pointsBalanceAtQuote":100,"actionsRemainingAtQuote":8,"createdAt":"2026-10-21T00:00:00Z","expiresAt":"2099-01-01T00:00:00Z","mode":"TASK_ACTOR_SELF_PAY_FOR_ORIGINAL_TEAM_UNOWNED_ONLY","releasePolicy":"CURRENT_FROZEN_RELEASE_ONLY","termPolicy":"RETAIN_TITLE_PENDING_REVIEW","pausePolicy":"FREEZE_TERM_REVIEW_BEFORE_RESUME","rewardPolicy":"NONE","writeApproved":true,"expired":false]
    }
    func title() -> [String:Any] {
        ["titleId":"77777777-7777-7777-7777-777777777777","regionId":"city-1","boardId":"board-1","seasonId":"season-1","pointId":"point-1","ownerTeamId":"11111111-1111-1111-1111-111111111111","pointVersion":1,"releaseId":1,"contentHash":String(repeating:"a",count:64),"acquiredAt":"2026-10-21T00:00:00Z","status":"ACTIVE_TERM","titleRetained":true,"transferAllowed":false,"serviceFeesAvailable":false,"payerMemberId":7,"sessionId":"22222222-2222-2222-2222-222222222222","roundId":"round-a","requestId":confirmID,"quoteId":quoteID,"taskResultId":"55555555-5555-5555-5555-555555555555","evidenceId":"33333333-3333-3333-3333-333333333333","pointCost":30,"pointsBefore":100,"pointsAfter":70,"pointsBusinessKey":"CITY:ACQUIRE:77777777-7777-7777-7777-777777777777","actionCost":2,"actionsBefore":8,"actionsAfter":6,"budgetVersion":1,"termSeconds":600,"policyHash":String(repeating:"b",count:64)]
    }
    func state() -> [String:Any] {
        let rules:[String:Any] = ["mode":"CITY_TEAM","joinPolicy":"INVITE_CODE","rosterPolicy":"CAPTAIN_LOCK_THEN_EACH_MEMBER_CONFIRM","replacementPolicy":"FORBIDDEN_AFTER_LOCK","reentryPolicy":"RESUME_ORIGINAL_SESSION","roundPolicy":"FIXED_PUBLISHED_ROUND","roundId":"round-a","minMembers":2,"maxMembers":3]
        let binding:[String:Any] = ["releaseId":1,"revision":1,"regionId":"city-1","boardId":"board-1","seasonId":"season-1","rulesReleaseId":"rules-1","contentHash":String(repeating:"a",count:64),"title":"Synthetic CITY","rules":rules]
        return ["contract":"CITY_ACQUISITION_V1","memberId":7,"regionId":"city-1","writeApproved":true,"status":"AVAILABLE","teamId":"11111111-1111-1111-1111-111111111111","binding":binding,"candidates":[["instanceId":instance,"taskId":"qa-1","pointId":"point-1","eligibility":"QUOTE_AVAILABLE","pointCost":30,"actionCost":2,"maxHoldingsPerTeam":1,"termSeconds":600,"evidenceAcceptance":"MERCHANT_ATTESTED"]],"ownership":[],"ownTitles":[]]
    }
    func response(_ data: [String:Any], status: Int = 200) throws -> (Data,Int) { (try JSONSerialization.data(withJSONObject:["code":status,"data":data]),status) }
    func service(_ grant: CityAcquisitionApproval, _ wire: Wire, current: (() -> RuntimeDependencyContext?)? = nil) -> CityAcquisitionService { .init(approval:grant,transport:.init(approval:grant,underlying:wire,current:current ?? {grant.context},selected:{_ in grant})) }
    func testDisabledFactoryAndReadOnlyGrantCannotQuote() async throws {
        let empty=CityAcquisitionController(service:nil,journal:Journal());await empty.load();XCTAssertFalse(empty.canWrite)
        let grant=try approval(writes:false),wire=Wire();wire.respond={ request in try self.response(request.url!.path.hasSuffix("/titles") ? ["contract":"CITY_ACQUISITION_V1","memberId":7,"regionId":"city-1","titles":[]] : self.state()) }
        let c=CityAcquisitionController(service:service(grant,wire),journal:Journal());await c.load();await c.requestQuote(try XCTUnwrap(c.snapshot?.candidates.first));XCTAssertTrue(wire.requests.allSatisfy{$0.httpMethod=="GET"})
    }
    func testActualQuoteThenSeparateConsentUsesServerKeyAndReadsOriginalTitle() async throws {
        let grant=try approval(),wire=Wire(),journal=Journal();var committed=false;var quotedID:String?
        wire.respond={ request in
            if request.httpMethod=="POST" { let body=try JSONSerialization.jsonObject(with:request.httpBody!) as! [String:Any];if body["kind"] as? String == "QUOTE" {quotedID=body["requestId"] as? String} else {XCTAssertEqual(body["requestId"] as? String,self.confirmID);XCTAssertEqual(body["confirmed"] as? Bool,true);committed=true};return try self.response([:]) }
            if request.url!.path.contains("/request/") { var data:[String:Any]=["contract":"CITY_ACQUISITION_V1","requestId":request.url!.lastPathComponent,"requestStatus":"COMPLETE"];if request.url!.lastPathComponent == self.confirmID { data["title"]=self.title();data["effectsStatus"]="COMMITTED" }else{XCTAssertEqual(request.url!.lastPathComponent,quotedID);data["quote"]=self.quote();data["effectsStatus"]="NOT_EXECUTED"};return try self.response(data) }
            if request.url!.path.contains("/quote/") {return try self.response(["contract":"CITY_ACQUISITION_V1","quote":self.quote()])}
            if request.url!.path.hasSuffix("/titles") {return try self.response(["contract":"CITY_ACQUISITION_V1","memberId":7,"regionId":"city-1","titles":committed ? [self.title()] : []])}
            return try self.response(self.state())
        }
        let c=CityAcquisitionController(service:service(grant,wire),journal:journal);await c.load();await c.requestQuote(try XCTUnwrap(c.snapshot?.candidates.first));XCTAssertFalse(committed);XCTAssertNil(c.confirmation);XCTAssertNotNil(c.selectedQuote)
        c.prepareConfirmation();let captured=try XCTUnwrap(c.confirmation);c.cancelConfirmation();await c.confirm(captured);XCTAssertFalse(committed)
        c.prepareConfirmation();await c.confirm(try XCTUnwrap(c.confirmation));XCTAssertTrue(committed);XCTAssertEqual(c.titles.first?.pointsAfter,70);XCTAssertNil(journal.record);XCTAssertEqual(wire.requests.filter{$0.httpMethod=="POST"}.count,2)
    }
    func testTimeoutRestartNeverChangesKeyOrReplays() async throws {
        let grant=try approval(),wire=Wire(),journal=Journal()
        wire.respond={ request in
            if request.httpMethod=="POST" {throw URLError(.timedOut)}
            if request.url!.path.contains("/request/") {return try self.response(["requestId":request.url!.lastPathComponent,"requestStatus":"UNKNOWN"],status:202)}
            if request.url!.path.hasSuffix("/titles") {return try self.response(["contract":"CITY_ACQUISITION_V1","memberId":7,"regionId":"city-1","titles":[]])}
            return try self.response(self.state())
        }
        let c=CityAcquisitionController(service:service(grant,wire),journal:journal);await c.load();await c.requestQuote(try XCTUnwrap(c.snapshot?.candidates.first));let key=try XCTUnwrap(journal.record?.operationID)
        let reopened=CityAcquisitionController(service:service(grant,wire),journal:journal);await reopened.load();await reopened.recover();XCTAssertEqual(reopened.pendingRequestID,key);XCTAssertFalse(reopened.canWrite);XCTAssertEqual(wire.requests.filter{$0.httpMethod=="POST"}.count,1)
    }
    func testAccountChangeAndMidflightRevocationFenceResponse() async throws {
        let grant=try approval(),wire=Wire();var live:RuntimeDependencyContext?=grant.context;let client=service(grant,wire,current:{live});live=nil
        do{_ = try await client.state();XCTFail("stale actor")}catch{};XCTAssertTrue(wire.requests.isEmpty);live=grant.context
        wire.respond={_ in grant.revoke();return try self.response(self.state())};do{_ = try await client.state();XCTFail("revoked reply")}catch{}
    }
    func testProtectedPayerCostOtherOriginAndMissingConsentAreRejectedByRoute() throws {
        var request=URLRequest(url:base.appendingPathComponent("api/city-game/acquisition/command"));request.httpMethod="POST";request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        var body:[String:Any]=["requestId":confirmID,"kind":"CONFIRM","regionId":"city-1","quoteId":quoteID,"quoteHash":String(repeating:"a",count:64),"confirmed":true]
        request.httpBody=try JSONSerialization.data(withJSONObject:body);XCTAssertNotNil(CityAcquisitionRoute(request:request,baseURL:base))
        for field in ["payerMemberId","pointCost","teamId"] {var tampered=body;tampered[field]=1;request.httpBody=try JSONSerialization.data(withJSONObject:tampered);XCTAssertNil(CityAcquisitionRoute(request:request,baseURL:base))}
        body["confirmed"]=false;request.httpBody=try JSONSerialization.data(withJSONObject:body);XCTAssertNil(CityAcquisitionRoute(request:request,baseURL:base));request.url=URL(string:"https://foreign.test/native/api/city-game/acquisition/state?regionId=city-1");request.httpMethod="GET";request.httpBody=nil;XCTAssertNil(CityAcquisitionRoute(request:request,baseURL:base))
    }
    func testWrongPayerOrRemoteAssuranceCannotBecomeConfirmableQuote() async throws {
        let grant=try approval(),wire=Wire(),client=service(grant,wire)
        for field in ["payerMemberId","evidenceAssurance","pausePolicy"] {var q=quote();q[field] = field == "payerMemberId" ? 8 : "REMOTE_NEUTRAL";wire.respond={_ in try self.response(["contract":"CITY_ACQUISITION_V1","quote":q])};do{_ = try await client.quote(quoteID);XCTFail("invalid source")}catch{}}
    }
    func testHistoricalTitleReadIsSeparateFromCurrentEligibility() async throws {
        let grant=try approval(),wire=Wire();wire.respond={request in if request.url!.path.hasSuffix("/titles"){var t=self.title();t["status"]="PAUSED_TERM_FROZEN";return try self.response(["contract":"CITY_ACQUISITION_V1","memberId":7,"regionId":"city-1","titles":[t]])};return (Data("{\"code\":503,\"errorCode\":\"SOURCE_UNAVAILABLE\"}".utf8),503)}
        let c=CityAcquisitionController(service:service(grant,wire),journal:Journal());await c.load();XCTAssertEqual(c.titles.first?.status,"PAUSED_TERM_FROZEN");XCTAssertNil(c.snapshot);XCTAssertNil(c.confirmation);XCTAssertTrue(wire.requests.allSatisfy{$0.httpMethod=="GET"})
    }
    func testMixedActionPolicyRequiresExplicitCostAndKeepsLegacyRules() throws {
        let legacy:[String:Any]=["scope":"TEAM_ROUND","unit":"ACTION","totalUnits":8,"rollCost":1,"refillPolicy":"NONE_WITHIN_ROUND","chargeTiming":"COMMITTED_DICE_RESULT","actionKind":"DICE_ROLL","resultPolicy":"RECORD_ONLY_NO_EFFECTS"]
        func decode(_ n:[String:Any])throws->CityActionBudgetRules{try JSONDecoder().decode(CityActionBudgetRules.self,from:JSONSerialization.data(withJSONObject:n))}
        XCTAssertTrue(try decode(legacy).valid);var mixed=legacy;mixed["actionKind"]="DICE_ROLL_AND_ACQUIRE";mixed["chargeTiming"]="COMMITTED_ACTION_EFFECT";mixed["resultPolicy"]="DICE_RECORD_ONLY_ACQUISITION_EXPLICIT_CONFIRM";XCTAssertFalse(try decode(mixed).valid);mixed["acquisitionCost"]=2;XCTAssertTrue(try decode(mixed).valid)
    }
    @MainActor final class Wire:HTTPTransport {var requests:[URLRequest]=[];var respond:((URLRequest)throws->(Data,Int))?;func send(_ request:URLRequest)async throws->(Data,Int){requests.append(request);return try respond?(request) ?? (Data(),500)}}
    @MainActor final class Journal:OperationPendingJournal {var record:OperationPendingRecord?;func pending(ownerKey:String,targetKey:String)throws->OperationPendingRecord?{guard let record,record.ownerKey==ownerKey,record.targetKey==targetKey else{return nil};return record};func write(_ value:OperationPendingRecord)throws{guard record==nil||record==value else{throw APIError.invalidRequest};record=value};func clear(_ value:OperationPendingRecord)throws{guard record==value else{throw APIError.invalidRequest};record=nil}}
}

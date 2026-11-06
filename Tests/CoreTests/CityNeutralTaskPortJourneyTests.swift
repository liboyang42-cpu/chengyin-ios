import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Authored synthetic transport tests. Execution requires a real supported Swift toolchain.
@available(macOS 14.0, *) @MainActor final class CityNeutralTaskPortJourneyTests: XCTestCase {
    let base = URL(string: "https://example.test/native")!
    var board: CityReadBoard { .init(gameId: "game-1", boardId: "board-1", regionId: "city-1", seasonId: "season-1", rulesReleaseId: "release-1", rulesHash: String(repeating: "a", count: 64), lifecycle: "FROZEN", title: "Synthetic CITY", revision: 1) }
    func approval(writes: Bool = true) throws -> CityNeutralTaskApproval {
        try .init(context: .init(market: .china, baseURL: base, role: "player", session: .init(accountID: 7, epoch: 1, namespace: "city-neutral", token: "synthetic-token")), regionID: "city-1", allowsWrite: writes, expiresAt: Date().addingTimeInterval(600))
    }
    func response() throws -> (Data, Int) {
        let rules: [String:Any] = ["mode":"CITY_TEAM","joinPolicy":"INVITE_CODE","rosterPolicy":"CAPTAIN_LOCK_THEN_EACH_MEMBER_CONFIRM","replacementPolicy":"FORBIDDEN_AFTER_LOCK","reentryPolicy":"RESUME_ORIGINAL_SESSION","roundPolicy":"FIXED_PUBLISHED_ROUND","roundId":"round-a","minMembers":2,"maxMembers":3]
        let binding: [String:Any] = ["releaseId":1,"revision":1,"regionId":"city-1","boardId":"board-1","seasonId":"season-1","rulesReleaseId":"release-1","contentHash":String(repeating:"a",count:64),"title":"Synthetic CITY","rules":rules]
        let definition: [String:Any] = ["taskId":"qa-1","title":"Synthetic question","type":"QA_PICK","access":"REMOTE_NEUTRAL","arrivalRequirement":"NONE","scope":"TEAM_ROUND","question":"Choose","options":[["id":"a","label":"Alpha"],["id":"b","label":"Beta"]],"maxAttempts":2,"pointCost":0,"pointReward":0,"actionCost":0]
        let task: [String:Any] = ["definition":definition,"status":"NOT_ACCEPTED","version":0,"attempts":0]
        let value: [String:Any] = ["contract":"CITY_NEUTRAL_TASK_V1","scope":"CITY","status":"AVAILABLE","writeApproved":true,"binding":binding,"teamId":"11111111-1111-1111-1111-111111111111","teamVersion":4,"sessionId":"22222222-2222-2222-2222-222222222222","tasks":[task],"arrivalProof":"NOT_PROVIDED","ownershipEffect":"NONE","pointsEffect":"NONE"]
        return (try JSONSerialization.data(withJSONObject:["code":200,"data":value]),200)
    }
    func service(_ grant: CityNeutralTaskApproval, _ wire: Wire, current: (() -> RuntimeDependencyContext?)? = nil) -> CityNeutralTaskService {
        .init(approval:grant,transport:.init(approval:grant,underlying:wire,current:current ?? {grant.context},selected:{_ in grant}),board:board)
    }
    func testDisabledFactoryCannotPrepareOrSend() async {
        let c=CityNeutralTaskController(service:nil,journal:Journal());await c.load();if let task=c.snapshot?.tasks.first {c.prepare(task)}
        XCTAssertNil(c.confirmation);XCTAssertFalse(c.canWrite)
    }
    func testReadPrepareExplicitConfirmOnePostAndOriginalReceipt() async throws {
        let grant=try approval(), wire=Wire(), journal=Journal()
        wire.respond={request in
            if request.url!.path.contains("/request/") {
                let source = try JSONSerialization.jsonObject(with: self.response().0) as! [String: Any]
                let state = source["data"] as! [String: Any]
                var task = (state["tasks"] as! [[String: Any]])[0]
                task["status"] = "ACTIVE"; task["version"] = 1
                task["instanceId"] = "33333333-3333-3333-3333-333333333333"
                task["acceptedAt"] = "2026-10-23T00:00:00Z"
                return (try JSONSerialization.data(withJSONObject:["code":200,"data":["requestId":request.url!.lastPathComponent,"requestStatus":"COMPLETE","contract":"CITY_NEUTRAL_TASK_V1","scope":"CITY","task":task]]),200)
            }
            return try self.response()
        }
        let c=CityNeutralTaskController(service:service(grant,wire),journal:journal)
        await c.load();if let task=c.snapshot?.tasks.first {c.prepare(task)};XCTAssertEqual(wire.requests.count,1)
        await c.confirm(try XCTUnwrap(c.confirmation));XCTAssertEqual(wire.requests.filter{$0.httpMethod=="POST"}.count,1)
        XCTAssertTrue(c.receipt?.succeeded == true);XCTAssertNil(journal.record)
    }
    func testTimeoutRestartNeverResubmits() async throws {
        let grant=try approval(), wire=Wire(), journal=Journal()
        wire.respond={ request in
            if request.url!.path.hasSuffix("/state") {return try self.response()}
            if request.httpMethod=="POST" {throw URLError(.timedOut)}
            return (Data("{\"code\":202,\"errorCode\":\"OUTCOME_UNKNOWN\",\"data\":{\"requestId\":\"\(request.url!.lastPathComponent)\",\"requestStatus\":\"UNKNOWN\"}}".utf8),202)
        }
        let first=CityNeutralTaskController(service:service(grant,wire),journal:journal)
        await first.load();first.prepare(try XCTUnwrap(first.snapshot?.tasks.first));await first.confirm(try XCTUnwrap(first.confirmation))
        let reopened=CityNeutralTaskController(service:service(grant,wire),journal:journal)
        await reopened.load();await reopened.recover();XCTAssertNotNil(journal.record);XCTAssertFalse(reopened.canWrite)
        XCTAssertEqual(wire.requests.filter{$0.httpMethod=="POST"}.count,1)
    }
    func testAccountSwitchAndRevocationBeforeAndAfterFlight() async throws {
        let grant=try approval(), wire=Wire();var current:RuntimeDependencyContext?=grant.context
        let client=service(grant,wire,current:{current});current=nil
        do {_ = try await client.state();XCTFail("stale account")} catch {}
        XCTAssertTrue(wire.requests.isEmpty);current=grant.context
        wire.respond={_ in grant.revoke();return try self.response()}
        let c=CityNeutralTaskController(service:client,journal:Journal());await c.load();XCTAssertNil(c.snapshot)
    }
    func testReadOnlyLeaseAndProtectedRouteReject() async throws {
        let grant=try approval(writes:false),wire=Wire();wire.respond={_ in try self.response()}
        let c=CityNeutralTaskController(service:service(grant,wire),journal:Journal());await c.load();if let task=c.snapshot?.tasks.first {c.prepare(task)};XCTAssertNil(c.confirmation)
        var request=URLRequest(url:base.appendingPathComponent("api/city-game/neutral-tasks/command"));request.httpMethod="POST";request.setValue("application/json",forHTTPHeaderField:"Content-Type")
        var body:[String:Any]=["requestId":UUID().uuidString,"regionId":"city-1","kind":"ACCEPT","releaseId":1,"contentHash":String(repeating:"a",count:64),"expectedVersion":0,"teamId":"11111111-1111-1111-1111-111111111111","expectedTeamVersion":4,"taskId":"qa-1"]
        request.httpBody=try JSONSerialization.data(withJSONObject:body);XCTAssertNotNil(CityNeutralTaskRoute(request:request,baseURL:base))
        body["memberId"]=99;request.httpBody=try JSONSerialization.data(withJSONObject:body);XCTAssertNil(CityNeutralTaskRoute(request:request,baseURL:base))
        request.url=URL(string:"https://foreign.test/api/city-game/neutral-tasks/command")!;XCTAssertNil(CityNeutralTaskRoute(request:request,baseURL:base))
    }
    func testRemoteScopeAndZeroEffectsCannotBeInferred() async throws {
        let grant=try approval(),wire=Wire(),client=service(grant,wire)
        for field in ["access", "arrivalRequirement", "pointCost"] {
            var envelope=try JSONSerialization.jsonObject(with:response().0) as! [String:Any]
            var value=envelope["data"] as! [String:Any];var tasks=value["tasks"] as! [[String:Any]];var definition=tasks[0]["definition"] as! [String:Any]
            definition.removeValue(forKey:field);tasks[0]["definition"]=definition;value["tasks"]=tasks;envelope["data"]=value
            let data=try JSONSerialization.data(withJSONObject:envelope);wire.respond={_ in (data,200)}
            do {_ = try await client.state();XCTFail("missing explicit field must fail")}catch {}
        }
    }
    func testPortRejectsSameAccountChangedCredentialBeforeDispatch() async throws {
        let grant = try approval(), wire = Wire()
        let different = RuntimeDependencyContext(market: .china, baseURL: base, role: "player",
            session: try .init(accountID: 7, epoch: 1, namespace: "city-neutral", token: "changed-token", role: "player"))
        XCTAssertFalse(grant.matches(different))
        let client = service(grant, wire, current: { different })
        do { _ = try await client.state(); XCTFail("Expected original credential fence") } catch {}
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testPortRejectsImplicitAndExplicitCookiesWithoutDispatch() async throws {
        let grant = try approval(), wire = Wire(), client = service(grant, wire)
        var parts = URLComponents(url: base.appendingPathComponent("api/city-game/neutral-tasks/state"), resolvingAgainstBaseURL: false)!
        parts.queryItems = [.init(name: "regionId", value: "city-1")]
        var request = URLRequest(url: parts.url!); request.httpMethod = "GET"
        request.setValue(grant.context.session.token, forHTTPHeaderField: "Authorization")
        do { _ = try await client.transport.send(request); XCTFail("Expected cookie rejection") } catch {}
        request.httpShouldHandleCookies = false; request.setValue("fake=1", forHTTPHeaderField: "Cookie")
        do { _ = try await client.transport.send(request); XCTFail("Expected cookie rejection") } catch {}
        XCTAssertTrue(wire.requests.isEmpty)
    }
    @MainActor final class Wire:HTTPTransport {
        var requests:[URLRequest]=[];var respond:((URLRequest)throws->(Data,Int))?
        func send(_ request:URLRequest)async throws->(Data,Int){requests.append(request);return try respond?(request) ?? (Data(),500)}
    }
    @MainActor final class Journal:OperationPendingJournal {
        var record:OperationPendingRecord?
        func pending(ownerKey:String,targetKey:String)throws->OperationPendingRecord?{guard let record,record.ownerKey==ownerKey,record.targetKey==targetKey else{return nil};return record}
        func write(_ value:OperationPendingRecord)throws{guard record==nil||record==value else{throw APIError.invalidRequest};record=value}
        func clear(_ value:OperationPendingRecord)throws{guard record==value else{throw APIError.invalidRequest};record=nil}
    }
}

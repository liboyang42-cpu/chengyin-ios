import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Synthetic GET-only executable regressions. Swift/XCTest execution is separately reported.
@available(macOS 14.0, *) @MainActor final class CityPlayerRulesFlowTests: XCTestCase {
    private let base = URL(string: "https://example.test/native")!
    private var board: CityReadBoard { .init(gameId: "game-1", boardId: "board-1", regionId: "city-1", seasonId: "season-1", rulesReleaseId: "release-1", rulesHash: String(repeating: "a", count: 64), lifecycle: "FROZEN", title: "Synthetic CITY", revision: 1) }
    private var read: CityReadSnapshot { .init(board: board, membership: .notJoined, participation: nil, points: nil) }
    private func approval() throws -> CityPlayerRulesApproval {
        try .init(context: .init(market: .china, baseURL: base, role: "player", session: .init(accountID: 7, epoch: 1, namespace: "city-rules", token: "synthetic-token")), regionID: "city-1", expiresAt: Date().addingTimeInterval(600))
    }
    private func payload(text: String = "Complete public rules") -> [String: Any] {
        func section(_ id: String, _ fields: [(String,String)]) -> [String: Any] { ["id":id, "status":"PUBLISHED", "rows":fields.map { ["key":$0.0, "value":$0.1] }] }
        let sections: [[String:Any]] = [
            section("rules", [("rulesId","rules-1"),("text",text)]), section("protection", [("challengeId","protect-1"),("text","Stay on the path")]),
            section("safety", [("statement","Use safe places")]), section("dice", [("diceId","dice-1"),("faces","[1,2]")]),
            section("pointCost", [("unit","POINT"),("amount","0")]), section("serviceFee", [("amountMinor","100"),("currency","CNY")]),
            ["id":"participation","status":"NOT_CONFIGURED","rows":[]], ["id":"actionBudget","status":"NOT_CONFIGURED","rows":[]],
            ["id":"acquisition","status":"NOT_CONFIGURED","rows":[]], section("season",[("seasonId","season-1")]),
            ["id":"effectiveInterval","status":"NOT_PUBLISHED","rows":[]], ["id":"settlement","status":"INTERNAL_BUDGET_ONLY","rows":[]],
            ["id":"taskDetails","status":"CONTEXTUAL_READ_ONLY","rows":[]], ["id":"locationDetails","status":"CONTEXTUAL_READ_ONLY","rows":[]]
        ]
        return ["contract":"CITY_PLAYER_RULES_V1","scope":"CITY","status":"AVAILABLE", "releaseId":11,
                "board":["gameId":"game-1","regionId":"city-1","boardId":"board-1","seasonId":"season-1","rulesReleaseId":"release-1","rulesHash":String(repeating:"a",count:64),"revision":1,"title":"Synthetic CITY","lifecycle":"FROZEN"],
                "sections":sections,"eligibility":["status":"NOT_CONFIGURED"],"grantsAction":false,"grantsParticipation":false]
    }
    private func response(_ payload: [String:Any]? = nil) throws -> (Data, Int) { (try JSONSerialization.data(withJSONObject:["code":200,"data":payload ?? self.payload()]),200) }
    private func client(_ grant: CityPlayerRulesApproval, _ wire: Wire, current: (() -> RuntimeDependencyContext?)? = nil) -> CityPlayerRulesClient {
        .init(approval:grant,transport:.init(approval:grant,underlying:wire,current:current ?? {grant.context},selected:{_ in grant}),read:read)
    }
    func testRulesReadUsesOnlyExactGETAndPreservesFullText() async throws {
        let grant = try approval(), wire = Wire(); let full = String(repeating:"全",count:4000)
        wire.answer = { _ in try self.response(self.payload(text:full)) }
        let flow = CityPlayerRulesFlow(client:client(grant,wire)); flow.bindSelection {true}; await flow.load()
        XCTAssertEqual(flow.phase,.ready); XCTAssertEqual(flow.snapshot?.sections.first?.rows.last?.value,full)
        let request = try XCTUnwrap(wire.requests.first)
        XCTAssertEqual(request.httpMethod,"GET"); XCTAssertNil(request.httpBody); XCTAssertFalse(request.httpShouldHandleCookies)
        XCTAssertEqual(request.cachePolicy,.reloadIgnoringLocalCacheData); XCTAssertNotNil(CityPlayerRulesRoute(request:request,baseURL:base))
        let query = URLComponents(url:request.url!,resolvingAgainstBaseURL:false)!.queryItems!
        XCTAssertEqual(Set(query.map(\.name)),["gameId","regionId","boardId","seasonId","rulesReleaseId","rulesHash","revision","membership"])
        flow.cancel(); XCTAssertNil(flow.snapshot); await flow.load(); XCTAssertEqual(wire.requests.count,2); XCTAssertEqual(flow.phase,.ready)
    }
    func testPolicyCodeCollisionsPreservePublishedTextAndIdentifiers() async throws {
        let grant = try approval(), wire = Wire()
        var value = payload(text: "CITY_TEAM"), sections = value["sections"] as! [[String: Any]]
        sections[0]["rows"] = [["key": "rulesId", "value": "ACTION"], ["key": "text", "value": "CITY_TEAM"]]
        sections[1]["rows"] = [["key": "challengeId", "value": "POINT"], ["key": "text", "value": "POINT"]]
        sections[2]["rows"] = [["key": "statement", "value": "INVITE_CODE"]]
        value["sections"] = sections
        wire.answer = { _ in try self.response(value) }
        let flow = CityPlayerRulesFlow(client: client(grant, wire)); flow.bindSelection { true }; await flow.load()
        let snapshot = try XCTUnwrap(flow.snapshot)
        XCTAssertEqual(snapshot.sections[0].rows.last?.value, "CITY_TEAM")
        XCTAssertEqual(snapshot.sections[1].rows.last?.value, "POINT")
        for section in snapshot.sections.prefix(3) {
            for row in section.rows { XCTAssertNil(row.localizationKey(sectionID: section.id)) }
        }
        for (section, field, text) in [
            ("rules", "rulesId", "ACTION"), ("season", "seasonId", "ACTION"),
            ("dice", "diceId", "POINT"), ("participation", "roundId", "CITY_TEAM"),
            ("acquisition", "evidenceAcceptanceReason", "MERCHANT_ATTESTED"),
            ("rules", "mode", "CITY_TEAM"), ("participation", "mode", "ACTION"),
            ("actionBudget", "unit", "POINT")
        ] {
            XCTAssertNil(CityPlayerRulesRow(key: field, value: text).localizationKey(sectionID: section))
        }
        for (section, field, text) in [
            ("participation", "mode", "CITY_TEAM"), ("pointCost", "unit", "POINT"),
            ("actionBudget", "unit", "ACTION"), ("acquisition", "evidenceAcceptance", "MERCHANT_ATTESTED")
        ] {
            XCTAssertEqual(CityPlayerRulesRow(key: field, value: text).localizationKey(sectionID: section), "cityRules.value." + text)
        }
    }
    func testRefreshFailureClearsOldRulesForEveryServerOutcome() async throws {
        for (status, phase) in [(403,CityPlayerRulesFlow.Phase.accessWithdrawn),(404,.notPublished),(409,.changed),(503,.unavailable)] {
            let grant = try approval(), wire = Wire(); wire.answer = {_ in try self.response()}
            let flow = CityPlayerRulesFlow(client:client(grant,wire)); flow.bindSelection {true}; await flow.load(); XCTAssertNotNil(flow.snapshot)
            wire.answer = {_ in (Data("{\"code\":\(status),\"errorCode\":\"UNAVAILABLE\"}".utf8),status)}
            await flow.load(); XCTAssertNil(flow.snapshot); XCTAssertEqual(flow.phase,phase)
        }
        let grant = try approval(), wire = Wire(); wire.answer = {_ in throw URLError(.notConnectedToInternet)}
        let flow = CityPlayerRulesFlow(client:client(grant,wire)); flow.bindSelection {true}; await flow.load(); XCTAssertEqual(flow.phase,.unavailable)
    }
    func testSelectionChangeRevocationAndNilClientNeverShowOldFacts() async throws {
        let unavailable = CityPlayerRulesFlow(client:nil); unavailable.bindSelection {true}; await unavailable.load(); XCTAssertNil(unavailable.snapshot)
        let grant = try approval(), wire = Wire(); var selected = true
        wire.answer = {_ in try self.response()}; let flow = CityPlayerRulesFlow(client:client(grant,wire)); flow.bindSelection {selected}
        await flow.load(); XCTAssertNotNil(flow.snapshot); selected = false; XCTAssertNil(flow.snapshot); await flow.load(); XCTAssertEqual(wire.requests.count,1)
        selected = true; await flow.load(); grant.revoke(); XCTAssertNil(flow.snapshot); await flow.load(); XCTAssertEqual(wire.requests.count,2)
    }
    func testAccountAndLeaseChangeBeforeAndDuringReadAreRejected() async throws {
        let grant = try approval(), wire = Wire(); var live: RuntimeDependencyContext? = nil
        let c = client(grant,wire,current:{live}); let flow = CityPlayerRulesFlow(client:c); flow.bindSelection {true}
        await flow.load(); XCTAssertTrue(wire.requests.isEmpty)
        live = grant.context; wire.answer = {_ in live = nil; return try self.response()}
        await flow.load(); XCTAssertNil(flow.snapshot); XCTAssertEqual(flow.phase,.unavailable)
    }
    func testLateAndSupersededResponsesCannotRestoreOldRules() async throws {
        let grant = try approval(), wire = Wire(); wire.suspended = true
        let flow = CityPlayerRulesFlow(client:client(grant,wire)); flow.bindSelection {true}
        let first = Task { await flow.load() }; while wire.pending.isEmpty { await Task.yield() }
        XCTAssertEqual(flow.phase,.loading); XCTAssertNil(flow.snapshot)
        flow.cancel(); wire.suspended = false; wire.answer = {_ in try self.response(self.payload(text:"New read"))}
        await flow.load(); XCTAssertEqual(flow.snapshot?.sections.first?.rows.last?.value,"New read")
        wire.pending.removeFirst().resume(returning:try response(payload(text:"Obsolete read"))); await first.value
        XCTAssertEqual(flow.snapshot?.sections.first?.rows.last?.value,"New read")
        wire.suspended = true; let closing = Task { await flow.load() }; while wire.pending.isEmpty { await Task.yield() }
        closing.cancel(); flow.cancel(); wire.pending.removeFirst().resume(returning:try response()); await closing.value
        XCTAssertNil(flow.snapshot)
    }
    func testHTTP200BusinessErrorCodesAreHandled() async throws {
        for code in [401,403,404,409] {
            let grant = try approval(), wire = Wire(); var signedOut = false
            wire.answer = {_ in (Data("{\"code\":\(code),\"errorCode\":\"UNAVAILABLE\"}".utf8),200)}
            let flow = CityPlayerRulesFlow(client:client(grant,wire),unauthorized:{signedOut = true}); flow.bindSelection {true}; await flow.load()
            XCTAssertNil(flow.snapshot); XCTAssertEqual(signedOut,code == 401)
            XCTAssertEqual(flow.phase,code == 409 ? .changed : code == 404 ? .notPublished : .accessWithdrawn)
        }
    }
    func testForeignVersionAndSensitiveFieldsCannotBeDisplayed() async throws {
        let grant = try approval()
        for mode in ["hash","foreignField","missingRules","wrongPolicy","grantsAction"] {
            let wire = Wire(); var value = payload()
            if mode == "hash" { var b = value["board"] as! [String:Any]; b["rulesHash"] = String(repeating:"b",count:64); value["board"] = b }
            else if mode == "grantsAction" { value["grantsAction"] = true }
            else {
                var sections = value["sections"] as! [[String:Any]]
                if mode == "missingRules" { sections.removeFirst() }
                else if mode == "wrongPolicy" { sections[4]["rows"] = [["key":"unit","value":"FAKE_CURRENCY"],["key":"amount","value":"0"]] }
                else { sections[0]["rows"] = [["key":"rulesId","value":"rules-1"],["key":"text","value":"Public"],["key":"correctOptionId","value":"secret"]] }
                value["sections"] = sections
            }
            wire.answer = {_ in try self.response(value)}
            let flow = CityPlayerRulesFlow(client:client(grant,wire)); flow.bindSelection {true}; await flow.load(); XCTAssertNil(flow.snapshot,mode)
        }
    }
    func testJoinedFactsMatchOriginalSessionAndPublishedParticipationPolicy() async throws {
        let grant = try approval(), wire = Wire()
        let selected = CityReadSnapshot(board:board,membership:.joined,participation:.init(participationId:"session-1",membershipVersion:4),points:nil)
        let transport = CityPlayerRulesTransport(approval:grant,underlying:wire,current:{grant.context},selected:{_ in grant})
        let c = CityPlayerRulesClient(approval:grant,transport:transport,read:selected)
        var value = payload(); var sections = value["sections"] as! [[String:Any]]
        let policy = ["mode":"CITY_TEAM","minMembers":"1","maxMembers":"3","joinPolicy":"INVITE_CODE","rosterPolicy":"CAPTAIN_LOCK_THEN_EACH_MEMBER_CONFIRM","replacementPolicy":"FORBIDDEN_AFTER_LOCK","reentryPolicy":"RESUME_ORIGINAL_SESSION","roundPolicy":"FIXED_PUBLISHED_ROUND","roundId":"round-1"]
        sections[6] = ["id":"participation","status":"PUBLISHED","rows":policy.keys.sorted().map {["key":$0,"value":policy[$0]!]}]
        value["sections"] = sections
        value["eligibility"] = ["status":"MEMBERSHIP_CONFIRMED","teamId":"team-1","teamVersion":4,"sessionId":"session-1","sessionVersion":1,"present":true,"confirmed":true,"memberCount":1,"presentCount":1,"confirmedCount":1]
        wire.answer = {_ in try self.response(value)}
        let flow = CityPlayerRulesFlow(client:c); flow.bindSelection {true}; await flow.load(); XCTAssertEqual(flow.phase,.ready)
        let query = URLComponents(url:wire.requests.last!.url!,resolvingAgainstBaseURL:false)!.queryItems!
        XCTAssertEqual(query.first{$0.name == "membershipVersion"}?.value,"4")
        XCTAssertEqual(query.first{$0.name == "participationId"}?.value,"session-1")
        var facts = value["eligibility"] as! [String:Any]; facts["teamVersion"] = 5; value["eligibility"] = facts
        await flow.load(); XCTAssertNil(flow.snapshot)
        facts["teamVersion"] = 4; value["eligibility"] = facts; sections[6] = ["id":"participation","status":"NOT_CONFIGURED","rows":[]]; value["sections"] = sections
        await flow.load(); XCTAssertNil(flow.snapshot)
    }
    func testRouteRejectsWritesForeignOriginsCookiesExtraFieldsAndMissingIdentity() throws {
        let valid = try CityPlayerRulesRoute(read:read).request(baseURL:base,token:"synthetic-token")
        for mode in ["POST","cookie","proxy","cookieJar","foreign","extra","missing"] {
            var request = valid
            switch mode {
            case "POST": request.httpMethod = "POST"
            case "cookie": request.setValue("a=b",forHTTPHeaderField:"Cookie")
            case "proxy": request.setValue("secret",forHTTPHeaderField:"Proxy-Authorization")
            case "cookieJar": request.httpShouldHandleCookies = true
            default:
                var parts = URLComponents(url:request.url!,resolvingAgainstBaseURL:false)!
                if mode == "foreign" {parts.host = "foreign.test"}
                else if mode == "extra" {parts.queryItems!.append(.init(name:"memberId",value:"8"))}
                else {parts.queryItems!.removeAll{$0.name == "rulesHash"}}
                request.url = parts.url
            }
            XCTAssertNil(CityPlayerRulesRoute(request:request,baseURL:base),mode)
        }
    }
    @MainActor final class Wire: HTTPTransport {
        var requests: [URLRequest] = []
        var answer: ((URLRequest) throws -> (Data,Int))?
        var suspended = false
        var pending: [CheckedContinuation<(Data,Int), Error>] = []
        func send(_ request: URLRequest) async throws -> (Data,Int) {
            requests.append(request)
            if suspended {return try await withCheckedThrowingContinuation {pending.append($0)}}
            return try answer?(request) ?? (Data(),500)
        }
    }
}

import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class CityActionBudgetScopedTransportTests: XCTestCase {
    private static let invite = "00000000-0000-0000-0000-000000000001"
    private static let team = "00000000-0000-0000-0000-000000000001", session = "00000000-0000-0000-0000-000000000002"
    private static let binding: [String: Any] = ["releaseId": 1, "regionId": "region", "boardId": "board", "seasonId": "season", "rulesReleaseId": "rules",
        "contentHash": String(repeating: "a", count: 64), "revision": 1, "title": "Fake original board",
        "rules": ["mode": "CITY_TEAM", "minMembers": 1, "maxMembers": 3, "joinPolicy": "INVITE_CODE", "rosterPolicy": "CAPTAIN_LOCK_THEN_EACH_MEMBER_CONFIRM",
            "replacementPolicy": "FORBIDDEN_AFTER_LOCK", "reentryPolicy": "RESUME_ORIGINAL_SESSION", "roundPolicy": "FIXED_PUBLISHED_ROUND", "roundId": "round"]]
    private static func stateFixture() -> [String: Any] {
        ["contract": "CITY_ACTION_BUDGET_V1", "scope": "CITY", "status": "AVAILABLE", "writeApproved": true, "binding": binding,
         "teamId": team, "sessionId": session, "teamVersion": 3, "version": 0, "usedUnits": 0, "remainingUnits": 2, "rollCount": 0,
         "movementStatus": "UNAVAILABLE", "arrivalProof": "NOT_PROVIDED", "ownershipEffect": "NONE", "pointsEffect": "NONE", "effectsStatus": "NOT_EXECUTED", "recentResults": [],
         "rules": ["scope": "TEAM_ROUND", "unit": "ACTION", "totalUnits": 2, "rollCost": 1, "refillPolicy": "NONE_WITHIN_ROUND", "chargeTiming": "COMMITTED_DICE_RESULT", "actionKind": "DICE_ROLL", "resultPolicy": "RECORD_ONLY_NO_EFFECTS"],
         "dice": ["diceId": "dice", "faces": [1, 9], "weights": [1, 3]]]
    }
    @MainActor private final class Wire: HTTPTransport {
        var requests: [URLRequest] = []
        var status = 200
        var body = Data(#"{"code":200}"#.utf8)
        var beforeReply: (() -> Void)?
        func send(_ request: URLRequest) async throws -> (Data,Int) {
            requests.append(request); beforeReply?(); return (body,status)
        }
    }
    @MainActor private final class Harness {
        let context: RuntimeDependencyContext
        let api: APIConfiguration
        let scope: CityActionBudgetScope
        let prepared: CityActionBudgetPrepared
        var command: CityActionBudgetCommand { prepared.command }
        var current: RuntimeDependencyContext?
        var revision: UInt64 = 1
        var bundle: CityActionBudgetRuntimeGrants?
        var state: CityActionBudgetReadGrant?
        var write: CityActionBudgetCommandGrant?
        var receipt: CityOriginalReceiptReadGrant?
        var unauthorizedCount = 0
        let wire = Wire()
        init() throws {
            api = try .init(baseURL:URL(string:"https://city.example.test/native/")!)
            let session = try PlayExperienceSession(accountID:7,epoch:2,namespace:"city-test",token:"fake-token",role:"player")
            context = .init(market:.china,baseURL:api.baseURL,role:"player",session:session); current = context
            scope = try .init(market:.china,baseURL:api.baseURL,namespace:"city-test",accountID:7,epoch:2,token:"fake-token")
            let data = try JSONSerialization.data(withJSONObject: CityActionBudgetScopedTransportTests.stateFixture())
            let state = try JSONDecoder().decode(CityActionBudgetState.self, from: data)
            prepared = try .init(state: state, region: "region", requestID: CityActionBudgetScopedTransportTests.invite)
            bundle = try makeBundle()
        }
        func makeBundle() throws -> CityActionBudgetRuntimeGrants {
            try .init(context:context,revision:1,regionID:"region",expiresAt:Date().addingTimeInterval(600),
                state:{_ in self.state},command:{_ in self.write},receipt:{_ in self.receipt})
        }
        func approveAll() throws {
            state = .init(scope:scope, region:"region")
            write = try .init(scope:scope,prepared:prepared)
            receipt = .init(reference:try .init(session:scope.session,domain:.actionBudget,requestID:command.requestId))
        }
        func transport() throws -> CityActionBudgetScopedTransport {
            .init(configuration:api,grants:try XCTUnwrap(bundle),underlying:wire,currentContext:{self.current},
                  currentRevision:{self.revision},currentGrants:{self.bundle},unauthorized:{self.unauthorizedCount += 1})
        }
        func request(_ suffix: String, query: String? = nil, method: String = "GET", body: Data? = nil) throws -> URLRequest {
            var parts = try XCTUnwrap(URLComponents(url:api.baseURL.appendingPathComponent("api/city-game/action-budget/"+suffix),resolvingAgainstBaseURL:false))
            parts.percentEncodedQuery = query
            var request = URLRequest(url:try XCTUnwrap(parts.url));request.httpMethod=method;request.httpBody=body;request.httpShouldHandleCookies=false
            request.setValue("fake-token",forHTTPHeaderField:"Authorization")
            if method == "POST" { request.setValue("application/json",forHTTPHeaderField:"Content-Type") }
            return request
        }
    }
    private func denied(_ transport: CityActionBudgetScopedTransport,_ request: URLRequest) async {
        do { _ = try await transport.send(request);XCTFail("Expected exact-scope denial") } catch {}
    }
    func testEmptyProviderBundleDoesNotGrantAnyRoute() async throws {
        let h = try Harness(), transport = try h.transport()
        await denied(transport,try h.request("state",query:"regionId=region"))
        await denied(transport,try h.request("command",method:"POST",body:h.command.bytes()))
        XCTAssertTrue(h.wire.requests.isEmpty)
    }
    func testAllThreeExactRoutesPreserveOriginalRequestBytes() async throws {
        let h = try Harness();try h.approveAll();let transport = try h.transport()
        let requests = [try h.request("state",query:"regionId=region"),
                        try h.request("request/"+Self.invite),try h.request("command",method:"POST",body:h.command.bytes())]
        for request in requests { _ = try await transport.send(request) }
        XCTAssertEqual(h.wire.requests.count,3);XCTAssertEqual(h.wire.requests.last?.httpBody,try h.command.bytes())
        XCTAssertEqual(h.wire.requests.map(\.url),requests.map(\.url))
    }
    func testDuplicateOrExtraQueryAndWrongMethodNeverDispatch() async throws {
        let h = try Harness();try h.approveAll();let transport = try h.transport()
        for request in [try h.request("state",query:"regionId=region&regionId=region"),try h.request("state",query:"regionId=region&x=1"),
                        try h.request("state",query:"regionId"),try h.request("request/"+Self.invite,query:"regionId=region"),
                        try h.request("command",query:"",method:"POST",body:h.command.bytes()),try h.request("state",method:"DELETE")] {
            await denied(transport,request)
        }
        XCTAssertTrue(h.wire.requests.isEmpty)
    }
    func testAlteredBodyOtherReferenceAndCrossOriginDoNotReuseGrant() async throws {
        let h = try Harness();try h.approveAll();let transport = try h.transport()
        var bytes = try h.command.bytes();bytes.append(32)
        await denied(transport,try h.request("command",method:"POST",body:bytes))
        await denied(transport,try h.request("request/another-original"))
        await denied(transport,try h.request("request/original%2Fother"))
        var foreign = try h.request("state",query:"regionId=region");foreign.url=URL(string:"https://other.example.test/native/api/city-game/action-budget/state?regionId=region")!
        await denied(transport,foreign)
        var token = try h.request("state",query:"regionId=region");token.setValue("other-token",forHTTPHeaderField:"Authorization")
        await denied(transport,token)
        XCTAssertTrue(h.wire.requests.isEmpty)
    }
    func testCookieAndGETBodyCannotReachUnderlyingTransport() async throws {
        let h = try Harness();try h.approveAll();let transport = try h.transport()
        var cookie = try h.request("state",query:"regionId=region");cookie.setValue("unapproved=1",forHTTPHeaderField:"Cookie")
        await denied(transport,cookie)
        var automatic = try h.request("state",query:"regionId=region");automatic.httpShouldHandleCookies=true
        await denied(transport,automatic)
        await denied(transport,try h.request("state",query:"regionId=region",body:Data()))
        XCTAssertTrue(h.wire.requests.isEmpty)
    }
    func testRevokedGrantDropsLateReplyWithoutRetry() async throws {
        let h = try Harness();try h.approveAll();let transport = try h.transport();h.wire.beforeReply={h.state?.revoke()}
        await denied(transport,try h.request("state",query:"regionId=region"));XCTAssertEqual(h.wire.requests.count,1)
        await denied(transport,try h.request("state",query:"regionId=region"));XCTAssertEqual(h.wire.requests.count,1)
    }
    func testBundleReplacementAndRevisionChangeCannotReuseOldTransport() async throws {
        let h = try Harness();try h.approveAll();let transport = try h.transport()
        h.bundle = try h.makeBundle();await denied(transport,try h.request("state",query:"regionId=region"))
        let fresh = try h.transport();h.revision=2;await denied(fresh,try h.request("state",query:"regionId=region"))
        XCTAssertTrue(h.wire.requests.isEmpty)
    }
    func testOnlyCurrent401MayNotifySessionOwner() async throws {
        let h = try Harness();try h.approveAll();let transport = try h.transport();h.wire.status=401
        _ = try await transport.send(h.request("state",query:"regionId=region"));XCTAssertEqual(h.unauthorizedCount,1)
        h.wire.beforeReply={h.current=nil}
        await denied(transport,try h.request("state",query:"regionId=region"));XCTAssertEqual(h.unauthorizedCount,1)
    }
    func testExpiryAndRevocationDoNotCreateAuthority() throws {
        let h = try Harness(), bundle = try XCTUnwrap(h.bundle)
        XCTAssertFalse(bundle.matches(h.context,revision:1,now:bundle.expiresAt))
        bundle.revoke();XCTAssertFalse(bundle.matches(h.context,revision:1));XCTAssertNil(bundle.state(h.scope))
    }
    func testRoleChangeWithSameAccountCannotUseCapturedTransport() async throws {
        let h = try Harness(); try h.approveAll(); let transport = try h.transport()
        let session = try PlayExperienceSession(accountID:7,epoch:2,namespace:"city-test",token:"fake-token",role:"merchant")
        h.current = .init(market:.china,baseURL:h.api.baseURL,role:"merchant",session:session)
        await denied(transport,try h.request("state",query:"regionId=region"))
        XCTAssertTrue(h.wire.requests.isEmpty)
    }
    func testLateCommandGrantLossDoesNotReplayOrReportUnauthorized() async throws {
        let h = try Harness(); try h.approveAll(); let transport = try h.transport()
        h.wire.status = 401; h.wire.beforeReply = { h.write?.revoke() }
        let request = try h.request("command",method:"POST",body:h.command.bytes())
        await denied(transport,request); XCTAssertEqual(h.wire.requests.count,1)
        await denied(transport,request); XCTAssertEqual(h.wire.requests.count,1)
        XCTAssertEqual(h.unauthorizedCount,0)
    }
    func testStateGrantReplacementAndWrongRegionRemainDenied() async throws {
        let h = try Harness(); try h.approveAll(); let transport = try h.transport()
        await denied(transport,try h.request("state",query:"regionId=other"))
        h.wire.beforeReply = { h.state = .init(scope:h.scope,region:"region") }
        await denied(transport,try h.request("state",query:"regionId=region"))
        XCTAssertEqual(h.wire.requests.count,1)
    }

}

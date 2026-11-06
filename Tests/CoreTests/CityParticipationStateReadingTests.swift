import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class CityParticipationStateReadingTests: XCTestCase {
    private static let teamID = "11111111-1111-1111-1111-111111111111"
    private static let sessionID = "22222222-2222-2222-2222-222222222222"
    @MainActor private final class Wire: HTTPTransport {
        var requests: [URLRequest] = []
        var httpStatus = 200
        var body: [String: Any] = [:]
        var beforeReply: (() -> Void)?
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request); beforeReply?()
            return (try JSONSerialization.data(withJSONObject: body), httpStatus)
        }
    }
    @MainActor private final class Harness {
        let api: APIConfiguration
        let wire = Wire()
        let original: CityParticipationReadScope
        var current: CityParticipationReadScope?
        var issued: CityParticipationReadGrant?
        init() throws {
            api = try .init(baseURL: URL(string: "https://city.example.test/native/")!)
            original = try .init(market: .china, baseURL: api.baseURL, namespace: "test-city", accountID: 7, epoch: 1, token: "synthetic-token", regionID: "region-1")
            current = original; issued = .init(scope: original)
        }
        func reader() -> CityParticipationStateReader {
            .init(configuration: api, transport: wire, currentScope: { self.current }, grant: { self.issued })
        }
    }
    private func fixture(status: String = "NOT_JOINED", team: [String: Any]? = nil) -> [String: Any] {
        var state: [String: Any] = ["contract": "CITY_TEAM_PARTICIPATION_V1", "scope": "CITY", "status": status,
            "writeApproved": false, "pointsStatus": "UNAVAILABLE", "taskExecutionStatus": "UNAVAILABLE", "actionBudgetStatus": "UNAVAILABLE",
            "binding": ["releaseId": 12, "regionId": "region-1", "boardId": "board-original", "seasonId": "season-original", "rulesReleaseId": "rules-original",
                        "contentHash": String(repeating: "a", count: 64), "revision": 2, "title": "Original frozen board",
                        "rules": ["mode": "CITY_TEAM", "minMembers": 1, "maxMembers": 6, "joinPolicy": "INVITE_CODE",
                                  "rosterPolicy": "CAPTAIN_LOCK_THEN_EACH_MEMBER_CONFIRM", "replacementPolicy": "FORBIDDEN_AFTER_LOCK",
                                  "reentryPolicy": "RESUME_ORIGINAL_SESSION", "roundPolicy": "FIXED_PUBLISHED_ROUND", "roundId": "round-original"]]]
        if let team { state["team"] = team }
        return ["code": 200, "data": state]
    }
    private func team(present: Bool, confirmed: Bool, locked: Bool = true) -> [String: Any] {
        var result: [String: Any] = ["teamId": Self.teamID, "version": 3, "state": locked ? "LOCKED" : "FORMING", "captain": false,
            "memberCount": 2, "presentCount": present ? 2 : 1, "confirmedCount": confirmed ? 2 : 0, "present": present, "confirmed": confirmed]
        if locked { result["session"] = ["sessionId": Self.sessionID, "version": 4, "state": "AWAITING_CONFIRMATION"] }
        return result
    }
    private func rejects(_ expected: CityParticipationReadFailure, _ operation: () async throws -> CityParticipationState) async {
        do { _ = try await operation(); XCTFail("Expected closed read") }
        catch { XCTAssertEqual(error as? CityParticipationReadFailure, expected) }
    }
    func testDefaultNilGrantAndWrongRegionNeverDispatch() async throws {
        let h = try Harness()
        let reader = CityParticipationStateReader(configuration: h.api, transport: h.wire, currentScope: { h.current })
        await rejects(.disabled) { try await reader.read(h.original) }
        let other = try CityParticipationReadScope(market: .china, baseURL: h.api.baseURL, namespace: "test-city", accountID: 7, epoch: 1, token: "synthetic-token", regionID: "other")
        h.issued = .init(scope: other)
        await rejects(.disabled) { try await h.reader().read(h.original) }
        XCTAssertTrue(h.wire.requests.isEmpty)
    }
    func testExactStateGETAndNotJoinedAreReadOnlyObservations() async throws {
        let h = try Harness(); h.wire.body = fixture()
        let result = try await h.reader().read(h.original)
        XCTAssertEqual(result.status, "NOT_JOINED"); XCTAssertNil(result.team); XCTAssertFalse(result.writeApproved)
        let request = try XCTUnwrap(h.wire.requests.first)
        XCTAssertEqual(request.url?.path, "/native/api/city-game/team-participation/state")
        XCTAssertEqual(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems, [.init(name: "regionId", value: "region-1")])
        XCTAssertEqual(request.httpMethod, "GET"); XCTAssertNil(request.httpBody); XCTAssertFalse(request.httpShouldHandleCookies)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic-token")
        XCTAssertEqual(h.wire.requests.count, 1)
    }
    func testOriginalFrozenBindingAndExitedConfirmedSessionArePreserved() async throws {
        let h = try Harness(); h.wire.body = fixture(status: "PENDING", team: team(present: false, confirmed: true))
        let result = try await h.reader().read(h.original)
        XCTAssertEqual(result.binding.releaseId, 12); XCTAssertEqual(result.binding.boardId, "board-original")
        XCTAssertEqual(result.binding.rules.roundId, "round-original"); XCTAssertEqual(result.binding.revision, 2)
        XCTAssertEqual(result.team?.present, false); XCTAssertEqual(result.team?.confirmed, true)
        XCTAssertEqual(result.team?.session?.sessionId, Self.sessionID)
        XCTAssertEqual(result.team?.session?.state, "AWAITING_CONFIRMATION")
        XCTAssertEqual(h.wire.requests.count, 1)
    }
    func testJoinedAndFormingPreserveSourceWithoutInferringGameplay() async throws {
        let h = try Harness()
        h.wire.body = fixture(status: "JOINED", team: team(present: true, confirmed: true))
        let joined = try await h.reader().read(h.original)
        XCTAssertEqual(joined.status, "JOINED"); XCTAssertEqual(joined.actionBudgetStatus, "UNAVAILABLE")
        XCTAssertEqual(joined.team?.session?.state, "AWAITING_CONFIRMATION")
        h.wire.body = fixture(status: "PENDING", team: team(present: true, confirmed: false, locked: false))
        let forming = try await h.reader().read(h.original)
        XCTAssertNil(forming.team?.session); XCTAssertEqual(forming.team?.state, "FORMING")
    }
    func testHTTPAndEnvelopeFailuresNeverBecomeNotJoinedOrRetry() async throws {
        for status in [202, 401, 403, 404, 409, 503] {
            let h = try Harness(); h.wire.body = fixture(); h.wire.httpStatus = status
            await rejects(.unavailable(status: status)) { try await h.reader().read(h.original) }
            h.wire.httpStatus = 200; h.wire.body = ["code": status]
            await rejects(.unavailable(status: status)) { try await h.reader().read(h.original) }
            XCTAssertEqual(h.wire.requests.count, 2)
        }
    }
    func testFutureContractWrongRegionAndContradictoryStateAreRejected() async throws {
        let mutations: [(inout [String: Any]) -> Void] = [
            { $0["contract"] = "FUTURE" }, { $0["scope"] = "GAME" }, { $0["status"] = "JOINED" },
            { var b = $0["binding"] as! [String: Any]; b["regionId"] = "other"; $0["binding"] = b },
            { var b = $0["binding"] as! [String: Any]; var r = b["rules"] as! [String: Any]; r["reentryPolicy"] = "NEW_SESSION"; b["rules"] = r; $0["binding"] = b },
            { $0["team"] = self.team(present: true, confirmed: true) }, { $0["pointsStatus"] = "AVAILABLE" }
        ]
        for mutate in mutations {
            let h = try Harness(); h.wire.body = fixture()
            var data = try XCTUnwrap(h.wire.body["data"] as? [String: Any]); mutate(&data); h.wire.body["data"] = data
            await rejects(.unverified) { try await h.reader().read(h.original) }
        }
    }
    func testMalformedCountsAndUnauthorizedInviteProjectionFailClosed() async throws {
        for field in ["memberCount", "presentCount", "confirmedCount", "inviteCode"] {
            let h = try Harness()
            var value = team(present: true, confirmed: true)
            if field == "inviteCode" { value[field] = Self.teamID }
            else { value[field] = field == "memberCount" ? -1 : 999 }
            h.wire.body = fixture(status: "JOINED", team: value)
            await rejects(.unverified) { try await h.reader().read(h.original) }
        }
    }
    func testAccountEpochTokenAndRegionChangeDiscardLateResponse() async throws {
        for kind in 0..<4 {
            let h = try Harness(); h.wire.body = fixture()
            let replacement = try CityParticipationReadScope(market: .china, baseURL: h.api.baseURL, namespace: "test-city", accountID: kind == 0 ? 8 : 7, epoch: kind == 1 ? 2 : 1, token: kind == 2 ? "replacement-token" : "synthetic-token", regionID: kind == 3 ? "other" : "region-1")
            h.wire.beforeReply = { h.current = replacement }
            await rejects(.staleSession) { try await h.reader().read(h.original) }
            XCTAssertEqual(h.wire.requests.count, 1)
        }
    }
    func testRevokedOrReissuedGrantDiscardsLateResponse() async throws {
        for revoke in [true, false] {
            let h = try Harness(); h.wire.body = fixture()
            h.wire.beforeReply = { if revoke { h.issued?.revoke() } else { h.issued = .init(scope: h.original) } }
            await rejects(.disabled) { try await h.reader().read(h.original) }
            XCTAssertEqual(h.wire.requests.count, 1)
        }
    }
    func testRegionInjectionAndMissingLockedSessionFailClosed() async throws {
        let h = try Harness()
        for region in ["", "../other", "region?actor=8", String(repeating: "x", count: 97), "城市"] {
            XCTAssertThrowsError(try CityParticipationReadScope(market: .china, baseURL: h.api.baseURL, namespace: "test-city", accountID: 7, epoch: 1, token: "synthetic-token", regionID: region))
        }
        var locked = team(present: true, confirmed: true); locked.removeValue(forKey: "session")
        h.wire.body = fixture(status: "JOINED", team: locked)
        await rejects(.unverified) { try await h.reader().read(h.original) }
    }
}

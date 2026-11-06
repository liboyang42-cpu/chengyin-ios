import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class CityCurrentSnapshotReadingTests: XCTestCase {
    @MainActor private final class Wire: HTTPTransport {
        var requests: [URLRequest] = []
        var body: [String: Any] = [:]
        var status = 200
        var beforeReply: (() -> Void)?
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request); beforeReply?()
            return (try JSONSerialization.data(withJSONObject: body), status)
        }
    }
    private func query(south: String = "30", north: String = "30.1", layers: [String] = ["POI"], revision: Int64 = 2) throws -> CityCurrentSnapshotQuery {
        try .init(regionID: "region-1", boardID: "board-1", seasonID: "season-1", rulesReleaseID: "rules-1", revision: revision,
                  south: south, west: "120", north: north, east: "120.1", datum: "WGS84", zoom: 12, layers: layers, limit: 50)
    }
    private func scope(_ q: CityCurrentSnapshotQuery, account: Int = 7, epoch: UInt64 = 1, token: String = "synthetic-token") throws -> CityCurrentSnapshotScope {
        try .init(market: .china, baseURL: URL(string: "https://city.example.test/native/")!, namespace: "test-city", accountID: account, epoch: epoch, token: token, query: q)
    }
    private func fixture() -> [String: Any] {
        let bounds: [String: Any] = ["south": 30, "west": 120, "north": 30.1, "east": 120.1]
        return ["code": 200, "candidate": true, "data": [
            "contract": "CITY_CURRENT_SNAPSHOT_V1", "scope": "CITY", "mode": "CURRENT_SNAPSHOT", "deltaStatus": "DELTAS_UNAVAILABLE", "deltaReason": "AUTHORIZATION_LIFETIME_UNAVAILABLE",
            "board": ["gameId": "game-1", "boardId": "board-1", "regionId": "region-1", "seasonId": "season-1", "rulesReleaseId": "rules-1", "rulesHash": String(repeating: "a", count: 64), "lifecycle": "FROZEN", "title": "Frozen board", "revision": 2],
            "boardVersion": 2, "membership": "NOT_JOINED", "participation": NSNull(), "points": [point()],
            "mapRead": ["contract": "CITY_BOUNDED_MAP_V1", "datum": "WGS84", "initialViewport": bounds, "initialZoom": 12, "maxViewportSpanDegrees": 0.5, "minZoom": 0, "maxZoom": 22, "pageSize": 50, "maxPages": 4],
            "viewport": bounds, "datum": "WGS84", "zoom": 12, "layers": ["POI"], "complete": true, "capturedAtMillis": 1_700_000_000_000 as Int64,
            "validUntilMillis": 1_700_000_010_000 as Int64, "grantsNavigation": false, "grantsAction": false]]
    }
    private func point(_ id: String = "point-1") -> [String: Any] {
        ["pointId": id, "title": "Public point", "latitude": 30.05, "longitude": 120.05, "domain": "POI", "datum": "WGS84",
         "collectedAt": "2023-01-01T00:00:00Z", "coordinateAssurance": "PLATFORM_REVIEWED_METADATA", "availability": "AVAILABLE",
         "merchantVersion": 0, "platformVersion": 0, "mine": false, "ownership": "UNOWNED", "grantsNavigation": false, "grantsAction": false]
    }
    private func mutate(_ wire: Wire, _ body: (inout [String: Any]) -> Void) throws {
        var data = try XCTUnwrap(wire.body["data"] as? [String: Any]); body(&data); wire.body["data"] = data
    }
    private func reader(_ wire: Wire, current: @escaping () -> CityCurrentSnapshotScope?, grant: @escaping () -> CityCurrentSnapshotReadGrant?, now: @escaping () -> Int64 = { 1_700_000_000_001 }) throws -> CityCurrentSnapshotReader {
        .init(configuration: try .init(baseURL: URL(string: "https://city.example.test/native/")!), transport: wire, currentScope: current, grant: grant, now: now)
    }
    private func rejects(_ expected: CityCurrentSnapshotFailure, _ operation: () async throws -> CityCurrentSnapshot) async {
        do { _ = try await operation(); XCTFail("Expected closed current read") }
        catch { XCTAssertEqual(error as? CityCurrentSnapshotFailure, expected) }
    }
    func testDefaultGrantAndWrongQueryNeverDispatch() async throws {
        let s = try scope(query()), wire = Wire()
        let closed = CityCurrentSnapshotReader(configuration: try .init(baseURL: s.session.baseURL), transport: wire, currentScope: { s })
        await rejects(.disabled) { try await closed.read(s) }
        let other = CityCurrentSnapshotReadGrant(scope: try scope(query(revision: 3)))
        let r = try reader(wire, current: { s }, grant: { other })
        await rejects(.disabled) { try await r.read(s) }
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testExactBoundedGETPreservesFullCurrentProjectionWithoutDeltaOrAction() async throws {
        let s = try scope(query()), grant = CityCurrentSnapshotReadGrant(scope: s), wire = Wire(); wire.body = fixture()
        let result = try await reader(wire, current: { s }, grant: { grant }).read(s)
        XCTAssertEqual(result.points.map(\.pointId), ["point-1"]); XCTAssertEqual(result.boardVersion, 2)
        XCTAssertEqual(result.deltaStatus, "DELTAS_UNAVAILABLE"); XCTAssertFalse(result.grantsAction); XCTAssertFalse(result.grantsNavigation)
        XCTAssertEqual(result.membership, "NOT_JOINED"); XCTAssertNil(result.participation)
        let request = try XCTUnwrap(wire.requests.first), url = try XCTUnwrap(request.url)
        XCTAssertEqual(url.path, "/native/api/city-game/state/snapshot")
        let pairs = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        XCTAssertEqual(Set(pairs.map(\.name)), Set(["regionId", "boardId", "seasonId", "rulesReleaseId", "revision", "south", "west", "north", "east", "datum", "zoom", "layers", "limit"]))
        XCTAssertEqual(pairs.count, 13); XCTAssertEqual(pairs.first(where: { $0.name == "north" })?.value, "30.1")
        XCTAssertNil(request.httpBody); XCTAssertEqual(request.httpMethod, "GET"); XCTAssertFalse(request.httpShouldHandleCookies)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic-token")
    }
    func testSourceQueryBoundariesRejectRoundingInjectionAndBroadViewport() throws {
        for south in ["30\n", "30e0", "030", "30.0000000000001", "nan", "30&actor=8"] { XCTAssertThrowsError(try query(south: south)) }
        XCTAssertThrowsError(try query(north: "30")); XCTAssertThrowsError(try query(north: "30.500000000001"))
        XCTAssertThrowsError(try query(layers: [])); XCTAssertThrowsError(try query(layers: ["POI", "MERCHANT"]))
        XCTAssertThrowsError(try query(layers: ["POI", "POI"])); XCTAssertThrowsError(try query(revision: 9_007_199_254_740_992))
        XCTAssertNoThrow(try query(north: "30.5", layers: ["MERCHANT", "POI"]))
    }
    func testExpiredPermitFailsButNilDeadlineDoesNotInventAnExpiryOrGrant() async throws {
        let s = try scope(query()), grant = CityCurrentSnapshotReadGrant(scope: s), wire = Wire(); wire.body = fixture()
        let r = try reader(wire, current: { s }, grant: { grant }, now: { 1_700_000_010_000 })
        await rejects(.expired) { try await r.read(s) }
        try mutate(wire) { $0["validUntilMillis"] = NSNull(); $0["points"] = [] }
        let result = try await r.read(s)
        XCTAssertNil(result.validUntilMillis); XCTAssertFalse(result.grantsNavigation)
    }
    func testFailuresNeverFabricateEmptySnapshotOrRetry() async throws {
        let s = try scope(query()), grant = CityCurrentSnapshotReadGrant(scope: s), wire = Wire()
        let r = try reader(wire, current: { s }, grant: { grant })
        for status in [401, 403, 404, 409, 422, 503] {
            wire.body = fixture(); wire.status = status
            await rejects(.unavailable(status: status)) { try await r.read(s) }
            wire.status = 200; wire.body = ["code": status]
            await rejects(.unavailable(status: status)) { try await r.read(s) }
        }
        XCTAssertEqual(wire.requests.count, 12)
    }
    func testMismatchedBoardViewportAndFutureModeFailClosed() async throws {
        let changes: [(inout [String: Any]) -> Void] = [
            { $0["boardVersion"] = 3 }, { $0["mode"] = "ORDERED" }, { $0["complete"] = false }, { $0["grantsAction"] = true },
            { $0["deltaStatus"] = "AVAILABLE" }, { $0["membership"] = "JOINED" },
            { $0["viewport"] = ["south": 30, "west": 120, "north": 30.2, "east": 120.1] }
        ]
        for change in changes {
            let s = try scope(query()), grant = CityCurrentSnapshotReadGrant(scope: s), wire = Wire(); wire.body = fixture(); try mutate(wire, change)
            let r = try reader(wire, current: { s }, grant: { grant })
            await rejects(.unverified) { try await r.read(s) }
        }
    }
    func testDuplicateUnsortedOrOutOfBoundsPointsNeverReturnPartialPrefix() async throws {
        for points in [[point(), point()], [point("z"), point("a")], [point(), point("outside").merging(["latitude": 31]) { _, new in new }]] {
            let s = try scope(query()), grant = CityCurrentSnapshotReadGrant(scope: s), wire = Wire(); wire.body = fixture()
            try mutate(wire) { $0["points"] = points }
            let r = try reader(wire, current: { s }, grant: { grant })
            await rejects(.unverified) { try await r.read(s) }
        }
    }
    func testMembershipAndRetainedTitleRemainReadFacts() async throws {
        let s = try scope(query()), grant = CityCurrentSnapshotReadGrant(scope: s), wire = Wire(); wire.body = fixture()
        try mutate(wire) {
            $0["membership"] = "JOINED"; $0["participation"] = ["participationId": "original-session", "membershipVersion": 9]
            $0["points"] = [self.point().merging(["ownership": "RETAINED_REVIEW", "mine": true]) { _, new in new }]
        }
        let result = try await reader(wire, current: { s }, grant: { grant }).read(s)
        XCTAssertEqual(result.participation?.participationId, "original-session"); XCTAssertEqual(result.points.first?.ownership, "RETAINED_REVIEW")
        XCTAssertEqual(result.points.first?.mine, true); XCTAssertFalse(result.grantsAction)
    }
    func testLateAccountTokenEpochOrQueryChangeDiscardsWholeSnapshot() async throws {
        let s = try scope(query())
        let replacements = [try scope(query(), account: 8), try scope(query(), epoch: 2), try scope(query(), token: "other-token"), try scope(query(revision: 3))]
        for replacement in replacements {
            var current = s
            let grant = CityCurrentSnapshotReadGrant(scope: s), wire = Wire(); wire.body = fixture(); wire.beforeReply = { current = replacement }
            let r = try reader(wire, current: { current }, grant: { grant })
            await rejects(.staleSession) { try await r.read(s) }
            XCTAssertEqual(wire.requests.count, 1)
        }
    }
    func testLateGrantRevocationOrReplacementDiscardsWholeSnapshot() async throws {
        for revoke in [true, false] {
            let s = try scope(query()), wire = Wire(); wire.body = fixture()
            var grant = CityCurrentSnapshotReadGrant(scope: s)
            wire.beforeReply = { if revoke { grant.revoke() } else { grant = .init(scope: s) } }
            let r = try reader(wire, current: { s }, grant: { grant })
            await rejects(.disabled) { try await r.read(s) }
        }
    }
}

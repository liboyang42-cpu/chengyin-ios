import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class CityCurrentSnapshotPresentationTests: XCTestCase {
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

    @MainActor private final class Lifetime {
        let original: RuntimeDependencyContext
        var current: RuntimeDependencyContext?
        var revision: UInt64 = 1
        var now: Int64 = 1_700_000_000_001
        var issued: CityCurrentSnapshotReadGrant?
        init() throws {
            let session = try PlayExperienceSession(accountID: 7, epoch: 1, namespace: "test-city", token: "synthetic-token", role: "player")
            original = .init(market: .china, baseURL: URL(string: "https://city.example.test/native/")!, role: "player", session: session)
            current = original
        }
    }
    private func model(_ life: Lifetime, _ wire: Wire, enabled: Bool = true) throws -> CityCurrentSnapshotPresentation {
        let q = try query()
        if enabled { life.issued = CityCurrentSnapshotReadGrant(scope: try scope(q)) }
        return try .init(context: life.original, revision: 1, query: q, transport: wire,
            currentContext: { life.current }, currentRevision: { life.revision }, grant: { life.issued }, now: { life.now })
    }
    func testRealReaderDisplaysExactPointAndNeverDispatchesAction() async throws {
        let life = try Lifetime(), wire = Wire(); wire.body = fixture()
        let m = try model(life, wire); await m.open()
        XCTAssertEqual(m.phase, .ready); XCTAssertEqual(m.snapshot?.points.map(\.pointId), ["point-1"])
        m.selectPoint("point-1"); XCTAssertEqual(m.selectedPoint?.title, "Public point")
        XCTAssertEqual(m.selectedPoint?.grantsAction, false); XCTAssertEqual(m.selectedPoint?.grantsNavigation, false)
        m.selectPoint("not-in-snapshot"); XCTAssertNil(m.selectedPoint)
        XCTAssertEqual(wire.requests.count, 1); XCTAssertEqual(wire.requests.first?.httpMethod, "GET")
        XCTAssertNil(wire.requests.first?.httpBody)
    }
    func testDefaultMissingGrantCannotRead() async throws {
        let life = try Lifetime(), wire = Wire(); wire.body = fixture()
        let m = try model(life, wire, enabled: false); await m.open()
        XCTAssertEqual(m.phase, .unavailable); XCTAssertNil(m.snapshot); XCTAssertTrue(wire.requests.isEmpty)
    }
    func testExpiryImmediatelyHidesDetailsAndRequiresFreshRead() async throws {
        let life = try Lifetime(), wire = Wire(); wire.body = fixture()
        let m = try model(life, wire); await m.open(); m.selectPoint("point-1")
        life.now = 1_700_000_010_000
        XCTAssertNil(m.snapshot); XCTAssertNil(m.selectedPoint)
        m.synchronize(); XCTAssertEqual(m.phase, .expired); XCTAssertNil(m.selectedPointID)
        XCTAssertEqual(wire.requests.count, 1)
        await m.refresh(); XCTAssertEqual(m.phase, .expired); XCTAssertEqual(wire.requests.count, 2)
    }
    func testAccountOrRevisionChangeRetiresInsteadOfRestoringOldCache() async throws {
        for changedRevision in [false, true] {
            let life = try Lifetime(), wire = Wire(); wire.body = fixture()
            let m = try model(life, wire); await m.open()
            if changedRevision { life.revision += 1 } else { life.current = nil }
            XCTAssertNil(m.snapshot); m.synchronize(); XCTAssertTrue(m.isRetired)
            life.current = life.original; life.revision = 1
            await m.open(); XCTAssertNil(m.snapshot); XCTAssertEqual(wire.requests.count, 1)
        }
    }
    func testBackgroundDuringReplyCannotRepopulateClosedVisit() async throws {
        let life = try Lifetime(), wire = Wire(); wire.body = fixture()
        let m = try model(life, wire); wire.beforeReply = { m.close() }
        await m.open(); XCTAssertNil(m.snapshot); XCTAssertEqual(m.phase, .hidden)
        wire.beforeReply = nil; await m.open(); XCTAssertEqual(m.phase, .ready)
        XCTAssertEqual(wire.requests.count, 2)
    }
    func testRevokedOrReplacedGrantHidesOldProjectionWithoutAutomaticRetry() async throws {
        for replace in [false, true] {
            let life = try Lifetime(), wire = Wire(); wire.body = fixture()
            let m = try model(life, wire); await m.open(); m.selectPoint("point-1")
            if replace { life.issued = CityCurrentSnapshotReadGrant(scope: try scope(query())) }
            else { life.issued?.revoke() }
            XCTAssertNil(m.snapshot); m.synchronize(); XCTAssertNil(m.selectedPoint); XCTAssertEqual(m.phase, .unavailable)
            XCTAssertEqual(wire.requests.count, 1)
        }
    }
    func testFailedRefreshDoesNotShowPreviouslyReadyPointAsCurrent() async throws {
        let life = try Lifetime(), wire = Wire(); wire.body = fixture()
        let m = try model(life, wire); await m.open(); m.selectPoint("point-1")
        wire.status = 503; await m.refresh()
        XCTAssertEqual(m.phase, .unavailable); XCTAssertNil(m.snapshot); XCTAssertNil(m.selectedPointID)
        XCTAssertEqual(wire.requests.count, 2)
    }
}

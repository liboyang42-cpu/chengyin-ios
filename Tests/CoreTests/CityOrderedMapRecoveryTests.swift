import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class CityOrderedMapRecoveryTests: XCTestCase {
    final class Wire: HTTPTransport {
        var replies: [(Data, Int)] = []
        var requests: [URLRequest] = []
        var beforeReply: (() -> Void)?
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request); beforeReply?()
            guard !replies.isEmpty else { throw CityOrderedMapFailure.unavailable }
            return replies.removeFirst()
        }
    }
    func fixture() -> [String: Any] {
        let bounds: [String: Any] = ["south": 30, "west": 120, "north": 30.1, "east": 120.1]
        return ["code": 200, "candidate": true, "data": [
            "contract": "CITY_CURRENT_SNAPSHOT_V1", "scope": "CITY", "mode": "CURRENT_SNAPSHOT", "deltaStatus": "DELTAS_UNAVAILABLE", "deltaReason": "AUTHORIZATION_LIFETIME_UNAVAILABLE",
            "board": ["gameId": "game-1", "boardId": "board-1", "regionId": "region-1", "seasonId": "season-1", "rulesReleaseId": "rules-1", "rulesHash": String(repeating: "a", count: 64), "lifecycle": "FROZEN", "title": "Frozen board", "revision": 2],
            "boardVersion": 2, "membership": "NOT_JOINED", "participation": NSNull(), "points": [point()],
            "mapRead": ["contract": "CITY_BOUNDED_MAP_V1", "datum": "WGS84", "initialViewport": bounds, "initialZoom": 12, "maxViewportSpanDegrees": 0.5, "minZoom": 0, "maxZoom": 22, "pageSize": 50, "maxPages": 4],
            "viewport": bounds, "datum": "WGS84", "zoom": 12, "layers": ["POI"], "complete": true, "capturedAtMillis": Int64(Date().timeIntervalSince1970 * 1000) as Int64,
            "validUntilMillis": 1_700_000_010_000 as Int64, "grantsNavigation": false, "grantsAction": false]]
    }
    func point(_ id: String = "point-1") -> [String: Any] {
        ["pointId": id, "title": "Public point", "latitude": 30.05, "longitude": 120.05, "domain": "POI", "datum": "WGS84",
         "collectedAt": "2023-01-01T00:00:00Z", "coordinateAssurance": "PLATFORM_REVIEWED_METADATA", "availability": "AVAILABLE",
         "merchantVersion": 0, "platformVersion": 0, "mine": false, "ownership": "UNOWNED", "grantsNavigation": false, "grantsAction": false]
    }

    func setup(_ wire: Wire) throws -> (CityOrderedMapRuntimeSelection, CityOrderedMapReadGrant) {
        let session = try PlayExperienceSession(accountID: 7, epoch: 1, namespace: "test-city", token: "synthetic-token", role: "player")
        let context = RuntimeDependencyContext(market: .china, baseURL: URL(string: "https://city.example.test/native/")!, role: "player", session: session)
        let q = try CityCurrentSnapshotQuery(regionID: "region-1", boardID: "board-1", seasonID: "season-1", rulesReleaseID: "rules-1", revision: 2,
            south: "30", west: "120", north: "30.1", east: "120.1", datum: "WGS84", zoom: 12, layers: ["POI"], limit: 50)
        let scope = try CityCurrentSnapshotScope(market: .china, baseURL: context.baseURL, namespace: session.namespace, accountID: 7, epoch: 1, token: session.token, query: q)
        let grant = CityOrderedMapReadGrant(scope: scope)
        return (try .init(context: context, revision: 1, query: q, expiresAt: Date().addingTimeInterval(60), grant: { grant }), grant)
    }
    func reply(kind: String = "SNAPSHOT", sequence: Int = 0) throws -> (Data, Int) {
        let snapshot = try XCTUnwrap(fixture()["data"] as? [String: Any])
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        var value: [String: Any] = ["contract": "CITY_TRANSACTIONAL_MAP_V1", "scope": "CITY", "mode": "TRANSACTIONAL_EVENTS_V1", "kind": kind,
            "streamId": "00000000-0000-0000-0000-000000000001", "scopeHash": String(repeating: "a", count: 64), "sequence": sequence,
            "cursor": "00000000-0000-0000-0000-000000000001.\(sequence)", "boardVersion": 2, "capturedAtMillis": now,
            "validUntilMillis": now + 30000, "grantsAction": false, "grantsNavigation": false]
        if kind == "SNAPSHOT" {
            var current = snapshot; current["capturedAtMillis"] = now; current["validUntilMillis"] = now + 60000
            value["snapshot"] = current; value["versions"] = ["point-1": ["SLOT": 0, "MERCHANT": 0, "PLATFORM": 0]]
        } else { value["afterSequence"] = 0; value["batches"] = [] }
        return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": value]), 200)
    }
    func reset() -> (Data, Int) { (Data(#"{"code":409,"errorCode":"CITY_ORDERED_RESET_REQUIRED"}"#.utf8), 409) }
    func testDefaultCurrentProviderDoesNotSend() async throws {
        let w = Wire(); let (s, _) = try setup(w); let r = CityOrderedMapReader(selection: s, transport: w)
        do { _ = try await r.load(); XCTFail("Expected disabled") } catch { XCTAssertEqual(error as? CityOrderedMapFailure, .disabled) }
        XCTAssertTrue(w.requests.isEmpty)
    }
    func testRestartStartsWithSnapshotAndNeverRestoresCursor() async throws {
        let w = Wire(); let (s, _) = try setup(w); w.replies = [try reply(), try reply()]
        _ = try await CityOrderedMapReader(selection: s, transport: w, current: { true }).load()
        _ = try await CityOrderedMapReader(selection: s, transport: w, current: { true }).load()
        XCTAssertEqual(w.requests.count, 2); XCTAssertTrue(w.requests.allSatisfy { $0.url?.path.hasSuffix("/snapshot") == true && $0.url?.query?.contains("cursor=") == false })
    }
    func testExactResetFetchesOneSnapshotWithoutBusinessReplay() async throws {
        let w = Wire(); let (s, _) = try setup(w); let r = CityOrderedMapReader(selection: s, transport: w, current: { true })
        w.replies = [try reply(), reset(), try reply()]; _ = try await r.load(); _ = try await r.load()
        XCTAssertEqual(w.requests.map { $0.url!.lastPathComponent }, ["snapshot", "deltas", "snapshot"])
        XCTAssertTrue(w.requests.allSatisfy { $0.httpMethod == "GET" && $0.httpBody == nil })
    }
    func testMissingSequenceFetchesOneSnapshot() async throws {
        let w = Wire(); let (s, _) = try setup(w); let r = CityOrderedMapReader(selection: s, transport: w, current: { true })
        w.replies = [try reply(), try reply(kind: "DELTAS", sequence: 1), try reply()]; _ = try await r.load(); _ = try await r.load()
        XCTAssertEqual(w.requests.count, 3)
    }
    func testSecondResetDoesNotLoop() async throws {
        let w = Wire(); let (s, _) = try setup(w); let r = CityOrderedMapReader(selection: s, transport: w, current: { true })
        w.replies = [try reply(), reset(), reset()]; _ = try await r.load()
        do { _ = try await r.load(); XCTFail("Expected failure") } catch {}
        XCTAssertEqual(w.requests.count, 3)
    }
    func testRevocationDuringReplyDoesNotRecoverOrExposeMap() async throws {
        let w = Wire(); let (s, grant) = try setup(w); let r = CityOrderedMapReader(selection: s, transport: w, current: { true })
        w.replies = [try reply()]; w.beforeReply = { grant.revoke() }
        do { _ = try await r.load(); XCTFail("Expected revoked") } catch {}
        XCTAssertEqual(w.requests.count, 1)
    }
    func testCompleteCommittedBatchStagesOriginalPointReplacement() throws {
        let wire = Wire(); let (selection, _) = try setup(wire)
        let raw = try reply().0
        let initialObject = try XCTUnwrap(JSONSerialization.jsonObject(with: raw) as? [String: Any])
        var initial = try XCTUnwrap(initialObject["data"] as? [String: Any])
        let first = try JSONDecoder().decode(CityOrderedMapReply.self, from: JSONSerialization.data(withJSONObject: initial))
        var state = try CityOrderedMapState(first, query: selection.scope.query)
        var replacement = point(); replacement["availability"] = "PAUSED"; replacement["merchantVersion"] = 1
        let event: [String: Any] = ["eventId": String(repeating: "b", count: 64), "aggregate": "point-1", "component": "MERCHANT",
            "type": "POINT_REPLACED", "sequence": 1, "aggregateVersion": 1, "point": replacement]
        initial["kind"] = "DELTAS"; initial["sequence"] = 1; initial["cursor"] = "00000000-0000-0000-0000-000000000001.1"
        initial["snapshot"] = nil; initial["versions"] = nil; initial["afterSequence"] = 0
        initial["batches"] = [["batchId": String(repeating: "c", count: 64), "firstSequence": 1, "lastSequence": 1, "events": [event]]]
        let delta = try JSONDecoder().decode(CityOrderedMapReply.self, from: JSONSerialization.data(withJSONObject: initial))
        try state.ingest(delta, requestedSequence: 0, query: selection.scope.query)
        XCTAssertEqual(state.sequence, 1); XCTAssertEqual(state.snapshot.points.first?.availability, "PAUSED")
        XCTAssertFalse(state.snapshot.grantsAction); XCTAssertFalse(state.snapshot.grantsNavigation)
    }

}

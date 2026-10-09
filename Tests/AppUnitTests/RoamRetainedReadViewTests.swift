import XCTest
@testable import Questify

private actor RetainedRoamWire: HTTPTransport {
    private var mode = "success"
    private(set) var calls = 0
    func setMode(_ value: String) { mode = value }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        calls += 1
        switch mode {
        case "offline": throw URLError(.notConnectedToInternet)
        case "forbidden": return (Data(#"{"code":403}"#.utf8), 403)
        case "businessForbidden": return (Data(#"{"code":403}"#.utf8), 200)
        case "unauthorized": return (Data(#"{"code":401}"#.utf8), 401)
        case "empty": return (Data(#"{"code":200,"data":[]}"#.utf8), 200)
        default: return (Data(#"{"code":200,"data":[{"id":1,"name":"Synthetic place","type":1,"lat":1,"lng":2}]}"#.utf8), 200)
        }
    }
}

@MainActor final class RoamRetainedReadViewTests: XCTestCase {
    private let readAt = Date(timeIntervalSince1970: 1_800_000_000)
    private var area: RoamSearchArea { .init(coordinate: .init(latitude: 1, longitude: 2)!, label: "Manual") }
    private func scope(_ reader: any RoamReading) throws -> RoamRetainedRead.Scope {
        try XCTUnwrap(.init(readerID: ObjectIdentifier(reader), identity: reader.identity, area: reader.searchArea,
            layer: .places, radius: 3000, query: "", placeFilter: .all, eventFilter: .all, isConfigured: reader.isConfigured))
    }
    private func reader(_ wire: RetainedRoamWire) throws -> RoamSessionReader {
        let session = try RoamReadSession(accountID: 7, epoch: 1, token: "synthetic", manualMapApprovalRevision: UUID())
        let service = RoamService(configuration: try APIConfiguration(baseURL: URL(string: "https://example.test/")!), transport: wire)
        return RoamSessionReader(service: service, currentSession: { session }, searchArea: { self.area })
    }
    func testActualReadThenOfflineRetryRetainsSameScopedStaticRowsWithoutAdvancingTime() async throws {
        let wire = RetainedRoamWire(), reader = try reader(wire), scope = try scope(reader)
        var state = RoamRetainedRead(); let first = try XCTUnwrap(state.begin(scope: scope))
        let rows = try await reader.roamPlaces(radiusM: 3000).map(RoamMapItem.place)
        XCTAssertTrue(state.finish(first, items: rows, readAt: readAt))
        await wire.setMode("offline")
        let refresh = try XCTUnwrap(state.begin(scope: scope))
        XCTAssertEqual(state.snapshot(in: scope)?.isRetained, true)
        do { _ = try await reader.roamPlaces(radiusM: 3000); XCTFail("Expected offline failure") }
        catch { state.fail(refresh, error: error) }
        let value = try XCTUnwrap(state.snapshot(in: try self.scope(reader)))
        XCTAssertEqual(value.items.map(\.id), ["place-1"]); XCTAssertTrue(value.isRetained); XCTAssertEqual(value.readAt, readAt)
        let calls = await wire.calls; XCTAssertEqual(calls, 2)
    }
    func testActual401AndBoth403FormsClearReadOnlyFallback() async throws {
        for mode in ["forbidden", "businessForbidden", "unauthorized"] {
            let wire = RetainedRoamWire(), reader = try reader(wire), scope = try scope(reader)
            var state = RoamRetainedRead(); let first = try XCTUnwrap(state.begin(scope: scope))
            let rows = try await reader.roamPlaces(radiusM: 3000).map(RoamMapItem.place)
            XCTAssertTrue(state.finish(first, items: rows, readAt: readAt))
            await wire.setMode(mode); let refresh = try XCTUnwrap(state.begin(scope: scope))
            do { _ = try await reader.roamPlaces(radiusM: 3000); XCTFail(mode) }
            catch { state.fail(refresh, error: error) }
            XCTAssertNil(state.snapshot(in: scope), mode)
        }
    }
    func testRealSuccessfulEmptyResponseReplacesPreviousRowsAndReadTime() async throws {
        let wire = RetainedRoamWire(), reader = try reader(wire), scope = try scope(reader)
        var state = RoamRetainedRead(); let first = try XCTUnwrap(state.begin(scope: scope))
        let rows = try await reader.roamPlaces(radiusM: 3000).map(RoamMapItem.place)
        XCTAssertTrue(state.finish(first, items: rows, readAt: readAt))
        await wire.setMode("empty"); let refresh = try XCTUnwrap(state.begin(scope: scope))
        let empty = try await reader.roamPlaces(radiusM: 3000).map(RoamMapItem.place)
        XCTAssertTrue(state.finish(refresh, items: empty, readAt: readAt.addingTimeInterval(20)))
        let value = try XCTUnwrap(state.snapshot(in: scope)); XCTAssertEqual(value.items, [])
        XCTAssertFalse(value.isRetained); XCTAssertEqual(value.readAt, readAt.addingTimeInterval(20))
    }
    func testReaderScopeRevocationImmediatelyHidesAndRetiresPreviousRead() async throws {
        let wire = RetainedRoamWire(), grant = UUID()
        var session = try RoamReadSession(accountID: 7, epoch: 1, token: "synthetic", manualMapApprovalRevision: grant)
        let service = RoamService(configuration: try APIConfiguration(baseURL: URL(string: "https://example.test/")!), transport: wire)
        let reader = RoamSessionReader(service: service, currentSession: { session }, searchArea: { self.area })
        let original = try scope(reader)
        var state = RoamRetainedRead(); let first = try XCTUnwrap(state.begin(scope: original))
        let rows = try await reader.roamPlaces(radiusM: 3000).map(RoamMapItem.place)
        XCTAssertTrue(state.finish(first, items: rows, readAt: readAt))
        session = try RoamReadSession(accountID: 7, epoch: 1, token: "synthetic", manualMapApprovalRevision: nil)
        let revoked = try scope(reader)
        XCTAssertNil(state.snapshot(in: revoked)); state.retainOnly(scope: revoked)
        XCTAssertNil(state.snapshot(in: original))
        let calls = await wire.calls; XCTAssertEqual(calls, 1)
    }
}

import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@available(macOS 14.0, *)
@MainActor final class NearbyMerchantCoordinatorTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_700_000_000)
    private func fix(_ longitude: Double = 116.397128, _ latitude: Double = 39.916527, accuracy: Double = 5, age: Double = 0, datum: RoamDeviceFix.Datum = .wgs84) throws -> RoamDeviceFix {
        try .init(coordinate: XCTUnwrap(.init(latitude: latitude, longitude: longitude)), accuracyMeters: accuracy, measuredAt: date.addingTimeInterval(-age), datum: datum)
    }
    func testSourceConversionIsExplicitAndOutsideChinaIsUnchanged() throws {
        let converted = try RuntimeLocationProjection.gcj02(fix(), now: date)
        XCTAssertEqual(converted.coordinate.longitude, 116.40337249402477, accuracy: 0.000000001)
        XCTAssertEqual(converted.coordinate.latitude, 39.91793074924595, accuracy: 0.000000001)
        XCTAssertEqual(converted.datum, .gcj02)
        let outside = try fix(-122.4, 37.7)
        XCTAssertEqual(try RuntimeLocationProjection.gcj02(outside, now: date).coordinate, outside.coordinate)
        XCTAssertThrowsError(try RuntimeLocationProjection.gcj02(fix(age: 31), now: date))
        XCTAssertThrowsError(try RuntimeLocationProjection.gcj02(fix(accuracy: 101), now: date))
        let gcj = try fix(datum: .gcj02)
        XCTAssertEqual(try RuntimeLocationProjection.gcj02(gcj, now: date), gcj)
    }
    func testConstructionAndConsentDenialAreInert() async throws {
        let reader = try NearbyTestReader(), location = NearbyTestLocation(try fix())
        let model = NearbyMerchantCoordinator(reader: reader, location: location, approved: { true }, now: { self.date })
        XCTAssertEqual(reader.reads.count, 0); XCTAssertEqual(location.calls, 0)
        await model.search(purposeAccepted: false)
        XCTAssertEqual(model.phase, .consentRequired); XCTAssertEqual(location.calls, 0); XCTAssertTrue(reader.reads.isEmpty)
    }
    func testUnavailableAndSignedOutNeverRequestLocation() async throws {
        let reader = try NearbyTestReader(), location = NearbyTestLocation(try fix())
        let model = NearbyMerchantCoordinator(reader: reader, location: location, approved: { false }, now: { self.date })
        await model.search(purposeAccepted: true); XCTAssertEqual(model.phase, .unavailable)
        reader.session = nil
        let guest = NearbyMerchantCoordinator(reader: reader, location: location, approved: { true }, now: { self.date })
        await guest.search(purposeAccepted: true)
        XCTAssertEqual(location.calls, 0); XCTAssertTrue(reader.reads.isEmpty)
    }
    func testLocationToActualNearbyContractAndMemberDomain() async throws {
        let reader = try NearbyTestReader(), location = NearbyTestLocation(try fix())
        let model = NearbyMerchantCoordinator(reader: reader, location: location, approved: { true }, now: { self.date })
        await model.search(purposeAccepted: true)
        XCTAssertEqual(model.phase, .ready); XCTAssertEqual(location.calls, 1); XCTAssertEqual(reader.reads.count, 1)
        guard case .nearby(let lng, let lat) = reader.reads[0] else { return XCTFail() }
        XCTAssertEqual(lng, 116.40337249402477, accuracy: 0.000000001); XCTAssertEqual(lat, 39.91793074924595, accuracy: 0.000000001)
        XCTAssertEqual(model.rows[0].id, 91); XCTAssertEqual(model.rows[0].memberID, 801)
        XCTAssertEqual(model.rows[0].distance, 125); XCTAssertEqual(model.rows[1].memberID, nil)
        let body = try reader.reads[0].body(); XCTAssertEqual(body["radius"].text, "5000"); XCTAssertEqual(body["limit"].text, "30")
    }
    func testStaleLocationCannotReachReaderAndBusyResets() async throws {
        let reader = try NearbyTestReader(), location = NearbyTestLocation(try fix())
        location.beforeReply = { reader.session = nil }
        let model = NearbyMerchantCoordinator(reader: reader, location: location, approved: { true }, now: { self.date })
        await model.search(purposeAccepted: true)
        XCTAssertTrue(reader.reads.isEmpty); XCTAssertTrue(model.rows.isEmpty); XCTAssertFalse(model.isBusy)
    }
    func testStaleResponseAndCancelNeverDisplayPriorAccountRows() async throws {
        let reader = try NearbyTestReader(), location = NearbyTestLocation(try fix())
        reader.beforeReply = { reader.session = nil }
        let model = NearbyMerchantCoordinator(reader: reader, location: location, approved: { true }, now: { self.date })
        await model.search(purposeAccepted: true)
        XCTAssertEqual(reader.reads.count, 1); XCTAssertTrue(model.rows.isEmpty); XCTAssertFalse(model.isBusy)
        model.cancel(); XCTAssertEqual(model.phase, .idle); XCTAssertTrue(model.rows.isEmpty)
    }
    func testInvalidFixIsLocationErrorNotAnEmptySearch() async throws {
        let reader = try NearbyTestReader(), location = NearbyTestLocation(try fix(age: 31))
        let model = NearbyMerchantCoordinator(reader: reader, location: location, approved: { true }, now: { self.date })
        await model.search(purposeAccepted: true)
        XCTAssertEqual(model.phase, .locationFailed); XCTAssertTrue(reader.reads.isEmpty)
    }
    func testRepeatedSearchUsesFreshFixAndRead() async throws {
        let reader = try NearbyTestReader(), location = NearbyTestLocation(try fix())
        let model = NearbyMerchantCoordinator(reader: reader, location: location, approved: { true }, now: { self.date })
        await model.search(purposeAccepted: true); await model.search(purposeAccepted: true)
        XCTAssertEqual(location.calls, 2); XCTAssertEqual(reader.reads.count, 2)
        reader.session = nil; XCTAssertTrue(model.rows.isEmpty)
    }
    func testDoubleTapAndCancelDiscardLateLocation() async throws {
        let reader = try NearbyTestReader(), location = NearbySuspendedLocation()
        let model = NearbyMerchantCoordinator(reader: reader, location: location, approved: { true }, now: { self.date })
        let task = Task { await model.search(purposeAccepted: true) }
        while location.pending == nil { await Task.yield() }
        await model.search(purposeAccepted: true)
        XCTAssertEqual(location.calls, 1)
        model.cancel(); location.pending?.resume(returning: try fix()); location.pending = nil
        await task.value
        XCTAssertEqual(model.phase, .idle); XCTAssertTrue(reader.reads.isEmpty); XCTAssertTrue(model.rows.isEmpty)
    }
    func testDuplicateMerchantRowsFailClosed() async throws {
        let reader = try NearbyTestReader(), location = NearbyTestLocation(try fix())
        reader.result = .array([.object(["id": .id(91), "name": .string("Synthetic")]), .object(["id": .id(91), "name": .string("Synthetic")])])
        let model = NearbyMerchantCoordinator(reader: reader, location: location, approved: { true }, now: { self.date })
        await model.search(purposeAccepted: true)
        XCTAssertEqual(model.phase, .failed); XCTAssertTrue(model.rows.isEmpty)
    }
}

@MainActor private final class NearbyTestLocation: RoamDeviceLocationProviding {
    let fix: RoamDeviceFix; var calls = 0; var stops = 0; var beforeReply: (() -> Void)?
    init(_ fix: RoamDeviceFix) { self.fix = fix }
    func currentFix() async throws -> RoamDeviceFix { calls += 1; beforeReply?(); return fix }
    func stop() { stops += 1 }
}
@MainActor private final class NearbyTestReader: CoopFlowReading {
    var session: CoopFlowSession?
    var reads: [CoopFlowRead] = []; var beforeReply: (() -> Void)?
    var result: CoopFlowJSON = .array([
        .object(["id": .id(91), "memberId": .id(801), "name": .string("Synthetic shop"), "distance": .number(125)]),
        .object(["id": .id(92), "name": .string("Synthetic lead")])])
    init() throws { session = try .init(accountID: 7, epoch: 1, token: "synthetic") }
    func read(_ resource: CoopFlowRead) async throws -> CoopFlowJSON { reads.append(resource); beforeReply?(); return result }
    func settlement(source: CoopFlowSettlement.Source, id: Int) async throws -> CoopFlowSettlement { throw CoopFlowFailure.unavailable }
}

@MainActor private final class NearbySuspendedLocation: RoamDeviceLocationProviding {
    var calls = 0
    var pending: CheckedContinuation<RoamDeviceFix, Error>?
    func currentFix() async throws -> RoamDeviceFix {
        calls += 1
        return try await withCheckedThrowingContinuation { pending = $0 }
    }
    // Intentionally late external completion exercises the coordinator's generation fence.
    func stop() {}
}

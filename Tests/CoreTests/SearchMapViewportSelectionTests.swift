import XCTest
@testable import QuestifyCore

final class SearchMapViewportSelectionTests: XCTestCase {
    private let context = SearchMapViewportSelection.Context(readerScope: UUID(), manualAreaRevision: 1, presentationID: UUID())
    private func viewport(_ latitude: Double = 31.2, _ longitude: Double = 121.4) throws -> SearchMapViewport {
        try XCTUnwrap(.init(latitude: latitude, longitude: longitude, latitudeSpan: 0.04, longitudeSpan: 0.04, datum: .wgs84))
    }
    func testCameraDraftDoesNotConvertOrChangeTheManualAreaUntilConsumed() throws {
        var gate = SearchMapViewportSelection(); let observed = try viewport()
        gate.observe(observed, context: context)
        let ticket = try XCTUnwrap(gate.current(in: context))
        XCTAssertEqual(ticket.viewport.center, observed.center); XCTAssertEqual(ticket.viewport.datum, .wgs84)
        let result = try XCTUnwrap(gate.consume(ticket, context: context, readerConfigured: true, active: true))
        XCTAssertEqual(result.datum, .gcj02); XCTAssertNotEqual(result.coordinate, observed.center)
        XCTAssertNil(gate.consume(ticket, context: context, readerConfigured: true, active: true))
    }
    func testCameraMovementRetiresOldTicketAndSameCenterReopenIsNewIdentity() throws {
        var gate = SearchMapViewportSelection(); let observed = try viewport()
        gate.observe(observed, context: context); let first = try XCTUnwrap(gate.draft)
        gate.observe(nil, context: context)
        XCTAssertNil(gate.current(in: context)); XCTAssertNil(gate.consume(first, context: context, readerConfigured: true, active: true))
        gate.observe(observed, context: context); let second = try XCTUnwrap(gate.draft)
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertNil(gate.consume(first, context: context, readerConfigured: true, active: true))
        XCTAssertNotNil(gate.consume(second, context: context, readerConfigured: true, active: true))
    }
    func testReaderLeaseAreaAndPresentationChangesRejectRetainedAction() throws {
        let changed = [SearchMapViewportSelection.Context(readerScope: UUID(), manualAreaRevision: 1, presentationID: context.presentationID),
                       .init(readerScope: context.readerScope, manualAreaRevision: 2, presentationID: context.presentationID),
                       .init(readerScope: context.readerScope, manualAreaRevision: 1, presentationID: UUID())]
        for current in changed {
            var gate = SearchMapViewportSelection(); gate.observe(try viewport(), context: context)
            let ticket = try XCTUnwrap(gate.draft)
            XCTAssertNil(gate.current(in: current))
            XCTAssertNil(gate.consume(ticket, context: current, readerConfigured: true, active: true))
        }
    }
    func testUnavailableBackgroundAndDepartureCannotConsume() throws {
        var gate = SearchMapViewportSelection(); gate.observe(try viewport(), context: context)
        let ticket = try XCTUnwrap(gate.draft)
        XCTAssertNil(gate.consume(ticket, context: context, readerConfigured: false, active: true))
        XCTAssertNil(gate.consume(ticket, context: context, readerConfigured: true, active: false))
        gate.invalidate()
        XCTAssertNil(gate.consume(ticket, context: context, readerConfigured: true, active: true))
    }
    func testInvalidPoleDatelineAndWorldSizedRegionsDoNotProduceDrafts() {
        for (lat, lon, height, width) in [(Double.nan, 121.0, 1.0, 1.0), (31, Double.infinity, 1, 1),
            (31, 121, 0, 1), (31, 121, -1, 1), (31, 121, 1, Double.nan), (84.9, 0, 1, 1),
            (0, 179.9, 1, 1), (0, -179.9, 1, 1), (0, 0, 180, 360)] {
            XCTAssertNil(SearchMapViewport(latitude: lat, longitude: lon, latitudeSpan: height, longitudeSpan: width, datum: .wgs84))
        }
    }
    func testTypedManualProjectionRejectsDoubleConversionAndReturnsNoDeviceEvidence() throws {
        let input = RuntimeLocationProjection.MapCenter(coordinate: try viewport().center, datum: .wgs84)
        let output: RuntimeLocationProjection.MapCenter = try RuntimeLocationProjection.gcj02MapCenter(input)
        XCTAssertEqual(output.datum, .gcj02)
        XCTAssertThrowsError(try RuntimeLocationProjection.gcj02MapCenter(output))
        var gate = SearchMapViewportSelection()
        gate.observe(.init(latitude: 31, longitude: 121, latitudeSpan: 0.01, longitudeSpan: 0.01, datum: .gcj02), context: context)
        let ticket = try XCTUnwrap(gate.draft)
        XCTAssertFalse(gate.canSearch(ticket, context: context, readerConfigured: true, active: true))
    }
    func testManualAndDeviceProjectionShareUnchangedSourceVectorsAndBoundary() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        for (lat, lon) in [(31.2, 121.4), (39.9, 116.4), (0.8293, 72.004), (55.8271, 137.8347),
                          (0.8292, 72.004), (1.0, 1.0), (-33.9, 151.2)] {
            let point = try XCTUnwrap(RoamCoordinate(latitude: lat, longitude: lon))
            let fix = try RoamDeviceFix(coordinate: point, accuracyMeters: 7, measuredAt: now, datum: .wgs84)
            let device = try RuntimeLocationProjection.gcj02(fix, now: now)
            let manual = try RuntimeLocationProjection.gcj02MapCenter(.init(coordinate: point, datum: .wgs84))
            XCTAssertEqual(manual.coordinate, device.coordinate); XCTAssertEqual(device.accuracyMeters, 7); XCTAssertEqual(device.measuredAt, now)
            if lon < 72.004 || lon > 137.8347 || lat < 0.8293 || lat > 55.8271 { XCTAssertEqual(manual.coordinate, point) }
        }
        let beijing = try RuntimeLocationProjection.gcj02MapCenter(.init(coordinate: try viewport(39.916527, 116.397128).center, datum: .wgs84))
        XCTAssertEqual(beijing.coordinate.latitude, 39.91793074924595, accuracy: 0.000000001)
        XCTAssertEqual(beijing.coordinate.longitude, 116.40337249402477, accuracy: 0.000000001)
    }
    func testDeviceFreshnessAndAccuracyGuardsRemainBeforeAlreadyProjectedEarlyReturn() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000), point = try viewport().center
        for datum in [RoamDeviceFix.Datum.wgs84, .gcj02] {
            for (accuracy, age) in [(101.0, 0.0), (1, 31), (1, -31)] {
                let fix = try RoamDeviceFix(coordinate: point, accuracyMeters: accuracy, measuredAt: now.addingTimeInterval(-age), datum: datum)
                XCTAssertThrowsError(try RuntimeLocationProjection.gcj02(fix, now: now))
            }
        }
        let alreadyProjected = try RoamDeviceFix(coordinate: point, accuracyMeters: 5, measuredAt: now, datum: .gcj02)
        XCTAssertEqual(try RuntimeLocationProjection.gcj02(alreadyProjected, now: now), alreadyProjected)
    }
}

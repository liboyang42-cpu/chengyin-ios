import XCTest
@testable import QuestifyCore

final class MapCoordinateObservationTests: XCTestCase {
    private let shanghaiWGS = (lat: 31.2304, lng: 121.4737)
    func testMissingOrUnknownDatumFailsClosed() {
        for datum in [nil, "", "bd09", "wgs"] as [String?] {
            XCTAssertThrowsError(try MapCoordinateObservation.normalize(latitude: 31.2, longitude: 121.4, datum: datum, source: .backend)) {
                XCTAssertEqual($0 as? MapCoordinateFailure, .missingDatum)
            }
        }
        XCTAssertEqual(try MapCoordinateObservation.normalize(latitude: "31.2", longitude: "121.4", datum: "GCJ-02", source: .backend).datum, .gcj02)
    }
    func testSwappedOrderIsReportedNotSilentlyFixed() {
        XCTAssertThrowsError(try MapCoordinateObservation(latitude: 121.47, longitude: 31.23, datum: .wgs84, source: .backend)) {
            XCTAssertEqual($0 as? MapCoordinateFailure, .likelySwappedOrder)
        }
        XCTAssertThrowsError(try MapCoordinateObservation(latitude: 120, longitude: 200, datum: .wgs84, source: .backend)) {
            XCTAssertEqual($0 as? MapCoordinateFailure, .outOfRange)
        }
    }
    func testNonNumericBooleanAndNaNInputsRejected() {
        for value in [true, "abc", "", Double.nan] as [Any] {
            XCTAssertThrowsError(try MapCoordinateObservation.normalize(latitude: value, longitude: 121.0, datum: "wgs84", source: .backend))
        }
        XCTAssertThrowsError(try MapCoordinateObservation(latitude: 31, longitude: 121, datum: .wgs84, source: .deviceLocation, accuracyMeters: -1))
    }
    func testConversionHappensExactlyOnce() throws {
        let wgs = try MapCoordinateObservation(latitude: shanghaiWGS.lat, longitude: shanghaiWGS.lng, datum: .wgs84, source: .deviceLocation, accuracyMeters: 8)
        let gcj = try wgs.projected(to: .gcj02)
        XCTAssertEqual(gcj.datum, .gcj02)
        XCTAssertNotNil(gcj.conversion)
        XCTAssertEqual(gcj.accuracyMeters, 8)
        XCTAssertNotEqual(gcj.latitude, wgs.latitude)
        XCTAssertEqual(try gcj.projected(to: .gcj02), gcj)
        XCTAssertThrowsError(try gcj.projected(to: .wgs84)) { XCTAssertEqual($0 as? MapCoordinateFailure, .doubleConversion) }
        let backendGCJ = try MapCoordinateObservation(latitude: 31.2, longitude: 121.4, datum: .gcj02, source: .backend)
        XCTAssertThrowsError(try backendGCJ.projected(to: .wgs84)) { XCTAssertEqual($0 as? MapCoordinateFailure, .unsupportedConversion) }
    }
    func testDistanceRequiresTheSameDatum() throws {
        let a = try MapCoordinateObservation(latitude: 31.23, longitude: 121.47, datum: .wgs84, source: .deviceLocation)
        let b = try MapCoordinateObservation(latitude: 31.24, longitude: 121.47, datum: .wgs84, source: .backend)
        XCTAssertEqual(try MapCoordinateObservation.distanceMeters(a, b), 1112, accuracy: 15)
        XCTAssertThrowsError(try MapCoordinateObservation.distanceMeters(a, b.projected(to: .gcj02))) {
            XCTAssertEqual($0 as? MapCoordinateFailure, .datumMismatch)
        }
    }
    func testStaleAndFutureFixesAreNotLive() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        func fix(_ offset: TimeInterval?) throws -> MapCoordinateObservation {
            try .init(latitude: 31, longitude: 121, datum: .wgs84, source: .deviceLocation, observedAt: offset.map { now.addingTimeInterval($0) })
        }
        XCTAssertFalse(try fix(-10).isStale(now: now, maxAge: 30))
        XCTAssertTrue(try fix(-31).isStale(now: now, maxAge: 30))
        XCTAssertTrue(try fix(120).isStale(now: now, maxAge: 30))
        XCTAssertTrue(try fix(nil).isStale(now: now, maxAge: 30))
    }
}

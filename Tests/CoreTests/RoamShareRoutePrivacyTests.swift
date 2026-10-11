import XCTest
@testable import QuestifyCore

final class RoamShareRoutePrivacyTests: XCTestCase {
    private func point(_ longitude: Double, latitude: Double = 0) -> RoamHistoryPoint {
        RoamHistoryPoint(coordinate: RoamCoordinate(latitude: latitude, longitude: longitude)!)
    }
    func testEmptyAndSinglePointAreHidden() {
        XCTAssertTrue(RoamShareRoutePrivacy.clippedTrack([]).isEmpty)
        XCTAssertTrue(RoamShareRoutePrivacy.clippedTrack([point(1)]).isEmpty)
    }
    func testTwoPointTrackClipsBothEndsByLength() {
        let result = RoamShareRoutePrivacy.clippedTrack([point(0), point(10)])
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].lng, 1, accuracy: 0.000001)
        XCTAssertEqual(result[1].lng, 9, accuracy: 0.000001)
    }
    func testUnevenSamplingUsesDistanceNotPointCount() {
        let result = RoamShareRoutePrivacy.clippedTrack([point(0), point(0.1), point(0.2), point(10)])
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].lng, 1, accuracy: 0.000001)
        XCTAssertEqual(result[1].lng, 9, accuracy: 0.000001)
    }
    func testInteriorVerticesAreRetained() {
        let result = RoamShareRoutePrivacy.clippedTrack([point(0), point(5), point(10)])
        XCTAssertEqual(result.count, 3)
        for (point, expected) in zip(result, [1.0, 5.0, 9.0]) { XCTAssertEqual(point.lng, expected, accuracy: 0.000001) }
    }
    func testDuplicatePointsDoNotDivideByZero() {
        let result = RoamShareRoutePrivacy.clippedTrack([point(0), point(0), point(5), point(5), point(10)])
        XCTAssertEqual(result.count, 3)
        for (point, expected) in zip(result, [1.0, 5.0, 9.0]) { XCTAssertEqual(point.lng, expected, accuracy: 0.000001) }
    }
    func testStationaryTrackFailsClosed() {
        XCTAssertTrue(RoamShareRoutePrivacy.clippedTrack([point(1), point(1), point(1)]).isEmpty)
    }
    func testDateLineCrossingFailsClosed() {
        XCTAssertTrue(RoamShareRoutePrivacy.clippedTrack([point(179), point(-179)]).isEmpty)
    }
    func testOriginalInputRemainsUnchanged() {
        let input = [point(0), point(5), point(10)]
        let before = input
        _ = RoamShareRoutePrivacy.clippedTrack(input)
        XCTAssertEqual(input, before)
    }
    func testReversedRouteRemovesBothEnds() {
        let result = RoamShareRoutePrivacy.clippedTrack([point(10), point(0)])
        XCTAssertEqual(result[0].lng, 9, accuracy: 0.000001)
        XCTAssertEqual(result[1].lng, 1, accuracy: 0.000001)
    }
    func testVeryShortTrackDoesNotFallBackToOriginal() {
        let input = [point(0), point(0.000001)]
        let result = RoamShareRoutePrivacy.clippedTrack(input)
        XCTAssertEqual(result.count, 2)
        XCTAssertGreaterThan(result[0].lng, input[0].lng)
        XCTAssertLessThan(result[1].lng, input[1].lng)
    }
    func testSketchNeverIncludesOriginalPOIsAndRecordIsUnchanged() throws {
        let bytes = Data(#"{"ts":1,"track":[{"lat":0,"lng":0},{"lat":0,"lng":10}],"pois":[{"lat":0,"lng":0,"name":"Private endpoint"}]}"#.utf8)
        let record = try JSONDecoder().decode(RoamHistoryRecord.self, from: bytes)
        let before = record
        let sketch = RoamShareRoutePrivacy.sketch(for: record)
        XCTAssertEqual(sketch.track.count, 2)
        XCTAssertTrue(sketch.places.isEmpty)
        XCTAssertEqual(record, before)
        XCTAssertEqual(record.pois.count, 1)
        XCTAssertEqual(record.track.first?.lng, 0)
    }
    func testAdjacentDoubleEndpointsCannotExportUnclippedRoute() {
        let input = [point(100), point(100.0.nextUp)]
        XCTAssertTrue(RoamShareRoutePrivacy.clippedTrack(input).isEmpty)
    }
    func testRepeatedAdjacentDoubleEndpointsFailClosed() {
        let input = [point(100), point(100), point(100.0.nextUp), point(100.0.nextUp)]
        XCTAssertTrue(RoamShareRoutePrivacy.clippedTrack(input).isEmpty)
    }
    func testTwoULPTrackWithInteriorPointCannotRoundToOriginalEndpoints() {
        let input = [point(100), point(100.0.nextUp), point(100.0.nextUp.nextUp)]
        XCTAssertTrue(RoamShareRoutePrivacy.clippedTrack(input).isEmpty)
    }
    func testSmallRepresentableInsetsRemainAvailable() {
        let input = [point(100), point(100.000001)]
        let result = RoamShareRoutePrivacy.clippedTrack(input)
        XCTAssertEqual(result.count, 2)
        XCTAssertGreaterThan(result[0].lng, input[0].lng)
        XCTAssertLessThan(result[1].lng, input[1].lng)
        XCTAssertGreaterThan(RoamExperienceMath.distanceMeters(result[0].coordinate, result[1].coordinate), 0)
    }

    func testReversedAdjacentDoubleEndpointsFailClosed() {
        XCTAssertTrue(RoamShareRoutePrivacy.clippedTrack([point(100.0.nextUp), point(100)]).isEmpty)
    }
    func testAdjacentLatitudeEndpointsFailClosed() {
        let input = [point(0, latitude: 50), point(0, latitude: 50.0.nextUp)]
        XCTAssertTrue(RoamShareRoutePrivacy.clippedTrack(input).isEmpty)
    }

}

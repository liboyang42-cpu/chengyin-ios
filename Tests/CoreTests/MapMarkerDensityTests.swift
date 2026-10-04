import XCTest
@testable import QuestifyCore

final class MapMarkerDensityTests: XCTestCase {
    func testScreenSpaceMergeSplitAndStableIdentity() {
        let a = MapMarkerDensity.Point(id: "nearby-7", x: 10, y: 10)
        let b = MapMarkerDensity.Point(id: "city-7", x: 15, y: 15)
        XCTAssertEqual(MapMarkerDensity.groups([a,b], diameter: 60), [["city-7", "nearby-7"]])
        XCTAssertEqual(MapMarkerDensity.groups([b,a], diameter: 60), [["city-7", "nearby-7"]])
        XCTAssertEqual(MapMarkerDensity.groups([a,.init(id: b.id, x: 100, y: 100)], diameter: 60), [["city-7"], ["nearby-7"]])
    }
    func testFreshMembershipDuplicateAndInvalidFailClosed() {
        let a = MapMarkerDensity.Point(id: "a", x: 0, y: 0)
        XCTAssertEqual(MapMarkerDensity.groups([a], diameter: 60), [["a"]])
        XCTAssertEqual(MapMarkerDensity.groups([], diameter: 60), [])
        XCTAssertEqual(MapMarkerDensity.groups([a,a,.init(id: "b", x: .nan, y: 0)], diameter: 60), [])
        XCTAssertEqual(MapMarkerDensity.groups([a], diameter: .infinity), [])
    }
    func testCoincidentAndTransitiveMarkersKeepAllIDs() {
        let points = [MapMarkerDensity.Point(id: "a", x: 0, y: 0), .init(id: "b", x: 0, y: 0), .init(id: "c", x: 50, y: 0), .init(id: "d", x: 100, y: 0)]
        XCTAssertEqual(MapMarkerDensity.groups(points, diameter: 60), [["a","b","c","d"]])
    }
    func testRotationPreservesDistancesAndDynamicTypeCanMerge() {
        let points = [MapMarkerDensity.Point(id: "a", x: 0, y: 0), .init(id: "b", x: 0, y: 80)]
        XCTAssertEqual(MapMarkerDensity.groups(points, diameter: 60).count, 2)
        XCTAssertEqual(MapMarkerDensity.groups(points, diameter: 100).count, 1)
        let rotated = points.map { MapMarkerDensity.Point(id: $0.id, x: -$0.y, y: $0.x) }
        XCTAssertEqual(MapMarkerDensity.groups(points, diameter: 100), MapMarkerDensity.groups(rotated, diameter: 100))
    }
    func testWorldPolarDateLineAndCoincidentCameraBounds() {
        let world = MapMarkerDensity.fit([.init(latitude: -85, longitude: -90), .init(latitude: 85, longitude: 90)])
        XCTAssertEqual(world?.latitudeSpan, 170)
        XCTAssertEqual(world?.longitudeSpan, 270)
        XCTAssertNil(MapMarkerDensity.fit([.init(latitude: 86, longitude: 0)]))
        XCTAssertNil(MapMarkerDensity.fit([.init(latitude: 0, longitude: -179), .init(latitude: 0, longitude: 179)]))
        XCTAssertNil(MapMarkerDensity.fit([.init(latitude: .nan, longitude: 0)]))
        XCTAssertNil(MapMarkerDensity.fit([]))
        let same = MapMarkerDensity.fit([.init(latitude: 85, longitude: 180), .init(latitude: 85, longitude: 180)])
        XCTAssertNotNil(same)
        XCTAssertLessThanOrEqual(same!.latitude + same!.latitudeSpan / 2, 85)
        XCTAssertGreaterThan(same!.latitudeSpan, 0)
        XCTAssertEqual(same?.longitudeSpan, 0.001)
    }

    func testRoamOverlappingKindsRetainExplicitMemberIdentities() {
        // Domain-prefixed IDs survive clustering even when numeric IDs coincide.
        let points = ["place-7", "route-7", "event-7", "player-7"].map {
            MapMarkerDensity.Point(id: $0, x: 100, y: 100)
        }
        XCTAssertEqual(MapMarkerDensity.groups(points, diameter: 72),
                       [["event-7", "place-7", "player-7", "route-7"]])
        // A refreshed/filtered snapshot never inherits absent members.
        XCTAssertEqual(MapMarkerDensity.groups(Array(points.prefix(1)), diameter: 72), [["place-7"]])
    }
    func testRoamAccessibleMarkerFootprintAndBoundary() {
        let points = [MapMarkerDensity.Point(id: "place-1", x: 0, y: 0),
                      .init(id: "place-2", x: 72, y: 0)]
        XCTAssertEqual(MapMarkerDensity.groups(points, diameter: 72), [["place-1"], ["place-2"]])
        XCTAssertEqual(MapMarkerDensity.groups(points, diameter: 100), [["place-1", "place-2"]])
    }

}

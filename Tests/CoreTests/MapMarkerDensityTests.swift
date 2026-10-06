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

    func testExplicitFocusUsesExactSelectedIdentity() throws {
        let targets = [MapMarkerDensity.Target(id: "city-7", coordinate: .init(latitude: 31, longitude: 121)),
                       .init(id: "nearby-7", coordinate: .init(latitude: 32, longitude: 120))]
        var gate = MapMarkerDensity.FocusGate()
        let request = try XCTUnwrap(gate.request(selectedID: "nearby-7", targets: targets))
        let fit = try XCTUnwrap(gate.consume(request))
        XCTAssertEqual(fit.latitude, 32)
        XCTAssertEqual(fit.longitude, 120)
        XCTAssertEqual(fit.latitudeSpan, 0.001)
        XCTAssertEqual(fit.longitudeSpan, 0.001)
    }

    func testFocusMissingEmptyAndAmbiguousIdentityFailClosed() {
        let target = MapMarkerDensity.Target(id: "city-7", coordinate: .init(latitude: 31, longitude: 121))
        let gate = MapMarkerDensity.FocusGate()
        XCTAssertNil(gate.request(selectedID: nil, targets: [target]))
        XCTAssertNil(gate.request(selectedID: "", targets: [.init(id: "", coordinate: target.coordinate)]))
        XCTAssertNil(gate.request(selectedID: "city-8", targets: [target]))
        XCTAssertNil(gate.request(selectedID: target.id, targets: []))
        XCTAssertNil(gate.request(selectedID: target.id, targets: [target, target]))
    }

    func testFocusUnsafeGeometryDoesNotProduceARequest() {
        let gate = MapMarkerDensity.FocusGate()
        for coordinate in [MapMarkerDensity.Coordinate(latitude: 86, longitude: 121),
                           .init(latitude: 31, longitude: 181),
                           .init(latitude: .nan, longitude: 121),
                           .init(latitude: 31, longitude: .infinity)] {
            XCTAssertNil(gate.request(selectedID: "selected", targets: [.init(id: "selected", coordinate: coordinate)]))
        }
    }

    func testFocusConsumptionRejectsDuplicateTapAndAllowsFreshExplicitTap() throws {
        let targets = [MapMarkerDensity.Target(id: "selected", coordinate: .init(latitude: 31, longitude: 121))]
        var gate = MapMarkerDensity.FocusGate()
        let request = try XCTUnwrap(gate.request(selectedID: "selected", targets: targets))
        XCTAssertNotNil(gate.consume(request))
        XCTAssertNil(gate.consume(request))
        let fresh = try XCTUnwrap(gate.request(selectedID: "selected", targets: targets))
        XCTAssertNotNil(gate.consume(fresh))
    }

    func testFocusInvalidationRejectsRefreshRemovalAndSameSelectionReopening() throws {
        let targets = [MapMarkerDensity.Target(id: "selected", coordinate: .init(latitude: 31, longitude: 121))]
        var gate = MapMarkerDensity.FocusGate()
        let old = try XCTUnwrap(gate.request(selectedID: "selected", targets: targets))
        // The view invalidates on every input snapshot/selection change and exit.
        gate.invalidate()
        XCTAssertNil(gate.request(selectedID: nil, targets: []))
        XCTAssertNil(gate.consume(old))
        let reopened = try XCTUnwrap(gate.request(selectedID: "selected", targets: targets))
        XCTAssertNil(gate.consume(old))
        XCTAssertNotNil(gate.consume(reopened))
    }

    func testFocusRequestCannotCrossPresentationInstances() throws {
        let targets = [MapMarkerDensity.Target(id: "selected", coordinate: .init(latitude: 31, longitude: 121))]
        let first = MapMarkerDensity.FocusGate()
        var second = MapMarkerDensity.FocusGate()
        let foreign = try XCTUnwrap(first.request(selectedID: "selected", targets: targets))
        XCTAssertNil(second.consume(foreign))
        let own = try XCTUnwrap(second.request(selectedID: "selected", targets: targets))
        XCTAssertNotNil(second.consume(own))
    }

    func testListSelectionUsesExactBusinessIDDespiteCoincidentTitlesAndCoordinates() throws {
        var gate = MapMarkerDensity.SelectionGate()
        let request = try XCTUnwrap(gate.request(id: "route-7", suppliedIDs: ["place-7", "route-7"]))
        XCTAssertEqual(gate.consume(request), "route-7")
    }

    func testListSelectionRejectsEmptyMissingAndEveryAmbiguousDuplicate() {
        let gate = MapMarkerDensity.SelectionGate()
        XCTAssertNil(gate.request(id: "", suppliedIDs: [""]))
        XCTAssertNil(gate.request(id: "removed", suppliedIDs: []))
        XCTAssertNil(gate.request(id: "a", suppliedIDs: ["a", "a", "b"]))
        XCTAssertNotNil(gate.request(id: "b", suppliedIDs: ["a", "a", "b"]))
    }

    func testListSelectionConsumesOnceAndRejectsAnotherOldRowAction() throws {
        var gate = MapMarkerDensity.SelectionGate()
        let first = try XCTUnwrap(gate.request(id: "a", suppliedIDs: ["a", "b"]))
        let second = try XCTUnwrap(gate.request(id: "b", suppliedIDs: ["a", "b"]))
        XCTAssertEqual(gate.consume(first), "a")
        XCTAssertNil(gate.consume(first))
        XCTAssertNil(gate.consume(second))
        let fresh = try XCTUnwrap(gate.request(id: "b", suppliedIDs: ["a", "b"]))
        XCTAssertEqual(gate.consume(fresh), "b")
    }

    func testListCloseRefreshRemovalAndSameIDReplacementInvalidateOldActions() throws {
        for _ in ["close", "refresh", "removal", "same-ID replacement", "scope", "disappear"] {
            var gate = MapMarkerDensity.SelectionGate()
            let old = try XCTUnwrap(gate.request(id: "a", suppliedIDs: ["a"]))
            gate.invalidate()
            XCTAssertNil(gate.consume(old))
            let reopened = try XCTUnwrap(gate.request(id: "a", suppliedIDs: ["a"]))
            XCTAssertNil(gate.consume(old))
            XCTAssertEqual(gate.consume(reopened), "a")
        }
    }

    func testListSelectionRequestCannotCrossViewInstances() throws {
        let first = MapMarkerDensity.SelectionGate()
        var second = MapMarkerDensity.SelectionGate()
        let foreign = try XCTUnwrap(first.request(id: "a", suppliedIDs: ["a"]))
        XCTAssertNil(second.consume(foreign))
        let own = try XCTUnwrap(second.request(id: "a", suppliedIDs: ["a"]))
        XCTAssertEqual(second.consume(own), "a")
    }

    func testPresentationToggleRequiresAppearanceAndCannotIssueOffscreenRequests() throws {
        var gate = MapMarkerDensity.PresentationGate()
        XCTAssertNil(gate.request())
        gate.appear()
        let active = try XCTUnwrap(gate.request())
        gate.disappear()
        XCTAssertNil(gate.request())
        // Explicit negative control: the retained toggle must not reopen offscreen.
        XCTAssertFalse(gate.consume(active))
        gate.invalidate()
        XCTAssertNil(gate.request())
    }

    func testPresentationToggleRejectsOldLifetimeAfterReturnButFreshToggleWorks() throws {
        var gate = MapMarkerDensity.PresentationGate()
        gate.appear()
        let departed = try XCTUnwrap(gate.request())
        gate.disappear()
        gate.appear()
        let returned = try XCTUnwrap(gate.request())
        XCTAssertFalse(gate.consume(departed))
        XCTAssertTrue(gate.consume(returned))
        XCTAssertFalse(gate.consume(returned))
        let freshClose = try XCTUnwrap(gate.request())
        XCTAssertTrue(gate.consume(freshClose))
    }

    func testPresentationToggleRejectsChangedInputAndForeignInstanceRequests() throws {
        var first = MapMarkerDensity.PresentationGate()
        var second = MapMarkerDensity.PresentationGate()
        first.appear(); second.appear()
        let old = try XCTUnwrap(first.request())
        first.invalidate()
        XCTAssertFalse(first.consume(old))
        let current = try XCTUnwrap(first.request())
        XCTAssertFalse(second.consume(current))
        XCTAssertTrue(first.consume(current))
    }
}

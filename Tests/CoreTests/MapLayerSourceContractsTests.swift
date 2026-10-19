import XCTest
@testable import QuestifyCore

final class MapLayerSourceContractsTests: XCTestCase {
    private func point(_ lat: Double = 31.23, _ lng: Double = 121.47) throws -> MapCoordinateObservation {
        try .init(latitude: lat, longitude: lng, datum: .gcj02, source: .backend)
    }
    private func item(_ type: MapSourceType, _ id: String, place: String? = nil, version: Int = 1,
                      state: MapMarkerVisualState = .standard, sort: String = "a", title: String = "Stop") throws -> MapLayerItem {
        try .init(key: .init(type: type, id: id), placeID: place, visibilityVersion: version, state: state,
                  coordinate: point(), capabilities: [.viewDetail], sortKey: sort, title: title)
    }
    func testAggregatedQueryStaysDisabled() {
        XCTAssertFalse(MapLayerFeature.aggregatedQueryEnabled)
        XCTAssertFalse(MapCoreEntry.preciseSharingDefaultEnabled)
    }
    func testEqualNumericIDsFromDifferentSourcesStayDistinct() throws {
        let merged = MapLayerMerge.merge([], [try item(.store, "7"), try item(.roamPOI, "7"), try item(.sideQuest, "7")])
        XCTAssertEqual(merged.count, 3)
        XCTAssertEqual(Set(merged.map(\.key.type)), [.store, .roamPOI, .sideQuest])
    }
    func testOlderVisibilityVersionCannotResurrect() throws {
        let newer = try item(.themeNode, "1", version: 5, state: .locked)
        let older = try item(.themeNode, "1", version: 4, state: .interactive)
        XCTAssertEqual(MapLayerMerge.merge([newer], [older]).first?.state, .locked)
        XCTAssertEqual(MapLayerMerge.merge([older], [newer]).first?.state, .locked)
    }
    func testMergeOrderIsStableByServerSortKey() throws {
        let merged = MapLayerMerge.merge([try item(.store, "2", sort: "b")], [try item(.store, "1", sort: "c"), try item(.roamPOI, "3", sort: "a")])
        XCTAssertEqual(merged.map(\.key.id), ["3", "2", "1"])
    }
    func testOnlyCanonicalPlaceGroupsNeverNamesOrCoordinates() throws {
        let a = try item(.store, "1", place: "p1", title: "Same name")
        let b = try item(.sideQuest, "9", place: "p1", title: "Other")
        let c = try item(.store, "2", place: nil, title: "Same name")
        let d = try item(.store, "3", place: nil, title: "Same name")
        let groups = MapLayerMerge.placeGroups([a, b, c, d])
        XCTAssertEqual(groups.count, 3)
        XCTAssertEqual(groups.first?.count, 2)
    }
    func testHiddenLayerRemovesItsItems() throws {
        let items = [try item(.store, "1"), try item(.sideQuest, "2")]
        XCTAssertEqual(MapLayerMerge.visible(items, layers: [.store]).map(\.key.type), [.store])
    }
    func testLockedItemsCannotAdvertiseAccept() throws {
        XCTAssertThrowsError(try MapLayerItem(key: .init(type: .sideQuest, id: "1"), placeID: nil, visibilityVersion: 1, state: .locked,
                                              coordinate: point(), capabilities: [.accept], sortKey: "a", title: "Locked"))
        XCTAssertThrowsError(try MapSourceKey(type: .store, id: "../1"))
        XCTAssertThrowsError(try MapSourceKey(type: .store, id: ""))
    }
    func testQueryBoundsLimitsAndCursorBinding() throws {
        let viewport = try MapLayerQuery.Viewport(south: 31.2, west: 121.4, north: 31.3, east: 121.5)
        let query = try MapLayerQuery(viewport: viewport, datum: .gcj02, zoom: 15, layers: [.store, .sideQuest], limit: 50)
        XCTAssertEqual(query.layers, [.sideQuest, .store])
        let next = try query.next(cursor: "c1", issuedFor: query.parameterFingerprint)
        XCTAssertEqual(next.cursor, "c1")
        let moved = try MapLayerQuery(viewport: .init(south: 31.21, west: 121.4, north: 31.3, east: 121.5), datum: .gcj02, zoom: 15, layers: [.store, .sideQuest], limit: 50)
        XCTAssertThrowsError(try moved.next(cursor: "c1", issuedFor: query.parameterFingerprint)) {
            XCTAssertEqual($0 as? MapLayerContractFailure, .cursorMismatch)
        }
        let huge = try MapLayerQuery.Viewport(south: 30, west: 120, north: 32, east: 122)
        XCTAssertThrowsError(try MapLayerQuery(viewport: huge, datum: .gcj02, zoom: 10, layers: [.store], limit: 50))
        XCTAssertThrowsError(try MapLayerQuery(viewport: viewport, datum: .gcj02, zoom: 15, layers: [], limit: 50))
        XCTAssertThrowsError(try MapLayerQuery(viewport: viewport, datum: .gcj02, zoom: 15, layers: [.store], limit: 500))
        XCTAssertThrowsError(try MapLayerQuery.Viewport(south: 31.3, west: 121.4, north: 31.2, east: 121.5))
    }
    func testEntranceShownOnlyWhenSourcedAndReviewed() throws {
        func entrance(reviewer: String?, closed: Bool = false) throws -> PlaceNavigationEntrance {
            .init(label: "North gate", floor: "1F", approachNote: nil, coordinate: try point(), source: "merchant-console",
                  reviewedBy: reviewer, updatedAt: Date(), temporarilyClosed: closed, accessibleAlternative: "Lift at east gate")
        }
        XCTAssertFalse(try entrance(reviewer: nil).isDisplayable)
        XCTAssertTrue(try entrance(reviewer: "ops").isNavigable)
        let closed = try entrance(reviewer: "ops", closed: true)
        XCTAssertTrue(closed.isDisplayable); XCTAssertFalse(closed.isNavigable)
    }
    func testCoreEntryAvailabilityIsExplicit() {
        XCTAssertEqual(MapCoreEntry.cityOrienteering.availability, .existing)
        XCTAssertEqual(MapCoreEntry.merchantSideQuests.availability, .pendingBackend)
        XCTAssertEqual(MapCoreEntry.sharedLocation.availability, .pendingDecision)
        XCTAssertEqual(MapCoreEntry.cityOperation.availability, .pendingDecision)
        XCTAssertEqual(Set(MapCoreEntry.allCases.map(\.symbolName)).count, MapCoreEntry.allCases.count)
    }
}

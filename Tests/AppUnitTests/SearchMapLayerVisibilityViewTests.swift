import XCTest
@testable import Questify

@MainActor final class SearchMapLayerVisibilityViewTests: XCTestCase {
    private final class ReaderMarker {}
    private let reader = ReaderMarker()
    private let scope = UUID()
    private let presentation = UUID()
    private let area = RoamSearchArea(coordinate: RoamCoordinate(latitude: 1, longitude: 2)!, label: "Manual")
    private func pin(_ id: String, title: String = "Same title", latitude: Double = 1) -> SearchMapPin {
        .init(id: id, title: title, coordinate: .init(latitude: latitude, longitude: 2)!, symbol: "mappin")
    }
    private func context(_ pins: [SearchMapPin], visibility: UUID, scope: UUID? = nil,
                         areaRevision: UInt64 = 1, area: RoamSearchArea? = nil, readerID: ObjectIdentifier? = nil, presentationID: UUID? = nil) -> SearchMapLayerSelection {
        .init(readerID: readerID ?? ObjectIdentifier(reader), scope: scope ?? self.scope, manualAreaRevision: areaRevision,
              area: area ?? self.area, visibilityRevision: visibility, pins: pins, presentationID: presentationID ?? presentation)
    }
    func testSameNumericSourceIDTitleAndCoordinateRemainIndependentChoices() {
        let value = context([pin("activity-7"), pin("city-7")], visibility: UUID())
        XCTAssertTrue(value.accepts("activity-7", current: value, isConfigured: true))
        XCTAssertTrue(value.accepts("city-7", current: value, isConfigured: true))
        XCTAssertFalse(value.accepts("7", current: value, isConfigured: true))
        XCTAssertFalse(value.accepts("Same title", current: value, isConfigured: true))
    }
    func testHiddenThenRestoredLayerNeverRestoresCapturedMapOrListAction() {
        var visibility = SearchMapLayerVisibility()
        let supplied = [pin("activity-7"), pin("city-7")]
        let original = context(supplied, visibility: visibility.revision)
        visibility.set(.activities, visible: false)
        let hidden = context([supplied[1]], visibility: visibility.revision)
        XCTAssertFalse(original.accepts("activity-7", current: hidden, isConfigured: true))
        visibility.set(.activities, visible: true)
        let restored = context(supplied, visibility: visibility.revision)
        XCTAssertFalse(original.accepts("activity-7", current: restored, isConfigured: true))
        XCTAssertTrue(restored.accepts("activity-7", current: restored, isConfigured: true))
        XCTAssertEqual(supplied.map(\.id), ["activity-7", "city-7"])
    }
    func testRemovedReplacedOrAmbiguousPinsCannotSelect() {
        let visibility = UUID(), original = context([pin("activity-7")], visibility: visibility)
        for pins in [[], [pin("city-7")], [pin("activity-7", title: "Replacement")],
                     [pin("activity-7", latitude: 2)], [pin("activity-7"), pin("activity-7")]] {
            XCTAssertFalse(original.accepts("activity-7", current: context(pins, visibility: visibility), isConfigured: true))
        }
        let duplicate = context([pin("activity-7"), pin("activity-7")], visibility: visibility)
        XCTAssertFalse(duplicate.accepts("activity-7", current: duplicate, isConfigured: true))
    }
    func testReaderLeaseManualAreaAndConfigurationAreRecheckedAtActionTime() {
        let otherReader = ReaderMarker(), visibility = UUID(), pins = [pin("city-7")]
        let original = context(pins, visibility: visibility)
        let changes = [context(pins, visibility: visibility, scope: UUID()),
            context(pins, visibility: visibility, areaRevision: 2),
            context(pins, visibility: visibility, presentationID: UUID()),
            context(pins, visibility: visibility, area: .init(coordinate: .init(latitude: 2, longitude: 3)!, label: "Elsewhere")),
            context(pins, visibility: visibility, readerID: ObjectIdentifier(otherReader))]
        for changed in changes { XCTAssertFalse(original.accepts("city-7", current: changed, isConfigured: true)) }
        XCTAssertFalse(original.accepts("city-7", current: original, isConfigured: false))
    }
    func testAllLayersHiddenHasNoSelectionAndResetCannotReuseOldAction() {
        var visibility = SearchMapLayerVisibility()
        let original = context([pin("activity-7"), pin("city-7")], visibility: visibility.revision)
        visibility.set(.activities, visible: false); visibility.set(.cityPlaces, visible: false)
        let hidden = context([], visibility: visibility.revision)
        XCTAssertTrue(visibility.isEmpty)
        XCTAssertFalse(original.accepts("activity-7", current: hidden, isConfigured: true))
        visibility.showAll()
        let restored = context(original.pins, visibility: visibility.revision)
        XCTAssertFalse(original.accepts("city-7", current: restored, isConfigured: true))
    }
    func testListOnlyActivityWithoutCoordinatesCanOpenButCannotReviveAfterHideShow() throws {
        let row = try JSONDecoder().decode(ActivitySummary.self, from: Data(#"{"id":7,"name":"List-only activity"}"#.utf8))
        var original = context([], visibility: UUID()); original.activities = [row]
        XCTAssertTrue(original.acceptsActivity(row, current: original, isConfigured: true))
        XCTAssertFalse(original.accepts("activity-7", current: original, isConfigured: true))
        var hidden = context([], visibility: UUID()); hidden.activities = []
        XCTAssertFalse(original.acceptsActivity(row, current: hidden, isConfigured: true))
        var restored = context([], visibility: UUID()); restored.activities = [row]
        XCTAssertFalse(original.acceptsActivity(row, current: restored, isConfigured: true))
        XCTAssertTrue(restored.acceptsActivity(row, current: restored, isConfigured: true))
    }
    func testNavigationRowsUseExactSourceSnapshotAndRejectSameIDReplacement() throws {
        let activity = try JSONDecoder().decode(ActivitySummary.self, from: Data(#"{"id":7,"name":"Original","topicId":8}"#.utf8))
        let replacement = try JSONDecoder().decode(ActivitySummary.self, from: Data(#"{"id":7,"name":"Changed","topicId":9}"#.utf8))
        let place = try JSONDecoder().decode(SearchMapCityNode.self, from: Data(#"{"poiId":7,"name":"City place"}"#.utf8))
        var original = context([], visibility: UUID()); original.activities = [activity]; original.cityPlaces = [place]
        XCTAssertTrue(original.acceptsActivity(activity, current: original, isConfigured: true))
        XCTAssertTrue(original.acceptsCityPlace(place, current: original, isConfigured: true))
        var changed = original; changed.activities = [replacement]
        XCTAssertFalse(original.acceptsActivity(activity, current: changed, isConfigured: true))
        XCTAssertFalse(original.acceptsCityPlace(place, current: changed, isConfigured: true))
        XCTAssertFalse(changed.acceptsActivity(activity, current: changed, isConfigured: true))
        XCTAssertFalse(original.acceptsCityPlace(place, current: original, isConfigured: false))
    }

    func testAcceptedNavigationKeepsImmutableTargetAcrossParentPresentationRetirement() throws {
        let row = try JSONDecoder().decode(ActivitySummary.self, from: Data(#"{"id":7,"name":"Original"}"#.utf8))
        var rendered = context([], visibility: UUID()); rendered.activities = [row]
        XCTAssertTrue(rendered.acceptsActivity(row, current: rendered, isConfigured: true))
        let route = SearchMapLayerNavigation(target: .activity(row), readerID: rendered.readerID, scope: rendered.scope, origin: rendered.area?.coordinate)
        var retired = context([], visibility: rendered.visibilityRevision, presentationID: UUID()); retired.activities = [row]
        XCTAssertFalse(rendered.acceptsActivity(row, current: retired, isConfigured: true))
        XCTAssertEqual(route.readerID, ObjectIdentifier(reader)); XCTAssertEqual(route.scope, scope)
        if case .activity(let accepted) = route.target { XCTAssertEqual(accepted, row) } else { XCTFail() }
        let another = SearchMapLayerNavigation(target: .activity(row), readerID: rendered.readerID, scope: rendered.scope, origin: rendered.area?.coordinate)
        XCTAssertNotEqual(route.id, another.id)
    }

}

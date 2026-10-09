import XCTest
@testable import QuestifyCore

final class SearchMapLayerVisibilityTests: XCTestCase {
    func testDefaultShowsBothExistingReadSources() {
        let value = SearchMapLayerVisibility()
        XCTAssertTrue(value.shows(.activities)); XCTAssertTrue(value.shows(.cityPlaces)); XCTAssertFalse(value.isEmpty)
    }
    func testEachLayerCanBeHiddenIndependently() {
        for layer in SearchMapLayerVisibility.Layer.allCases {
            var value = SearchMapLayerVisibility(); let before = value.revision
            value.set(layer, visible: false)
            XCTAssertFalse(value.shows(layer)); XCTAssertNotEqual(value.revision, before)
            for other in SearchMapLayerVisibility.Layer.allCases where other != layer { XCTAssertTrue(value.shows(other)) }
            XCTAssertFalse(value.isEmpty)
        }
    }
    func testAllHiddenIsDistinctAndShowAllRestoresVisibilityWithNewRevision() {
        var value = SearchMapLayerVisibility()
        value.set(.activities, visible: false); value.set(.cityPlaces, visible: false)
        XCTAssertTrue(value.isEmpty); let hidden = value.revision
        value.showAll()
        XCTAssertFalse(value.isEmpty); XCTAssertTrue(value.shows(.activities)); XCTAssertTrue(value.shows(.cityPlaces))
        XCTAssertNotEqual(value.revision, hidden)
    }
    func testHideShowABAHasIdenticalFlagsButCannotReviveOldActions() {
        var value = SearchMapLayerVisibility(); let first = value.revision
        value.set(.activities, visible: false); let hidden = value.revision
        value.set(.activities, visible: true)
        XCTAssertTrue(value.shows(.activities)); XCTAssertTrue(value.shows(.cityPlaces))
        XCTAssertNotEqual(value.revision, first); XCTAssertNotEqual(value.revision, hidden)
    }
    func testNoopKeepsGenerationWhileExplicitResetRetiresIt() {
        var value = SearchMapLayerVisibility(); let first = value.revision
        value.set(.activities, visible: true); XCTAssertEqual(value.revision, first)
        value.showAll(); XCTAssertNotEqual(value.revision, first)
    }
}

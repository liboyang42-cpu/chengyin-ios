import XCTest
@testable import QuestifyCore

final class TemplateHotspotPlacementTests: XCTestCase {
    private func fixture() -> TemplateAdvancedDraft {
        var draft = TemplateAdvancedDraft(); draft.setCreatorEnabled(.hiddenObject, true)
        draft.set("hiddenObject", "title", .string("Find the cats")); draft.set("hiddenObject", "imageUrl", .string("https://images.example.com/scene.jpg"))
        for index in 0..<3 { draft.setRow("hiddenObject", "hotspots", index: index, key: "label", text: "Cat \(index + 1)") }
        return draft
    }
    private func edited(_ draft: TemplateAdvancedDraft, _ edit: TemplateHotspotPlacement.Edit) throws -> TemplateAdvancedDraft { try XCTUnwrap(TemplateHotspotPlacement(draft).applying(edit, to: draft)) }
    func testOpeningIsReadOnlyAndProjectsExistingTargetPositions() {
        let draft = fixture(), before = draft, editor = TemplateHotspotPlacement(draft)
        XCTAssertTrue(editor.canEdit); XCTAssertEqual(editor.targets.count, 3); XCTAssertEqual(editor.targets[0].id, "spot_1")
        XCTAssertEqual(editor.targets[0].point?.x, 0.25); XCTAssertEqual(editor.targets[0].point?.y, 0.3); XCTAssertEqual(draft, before)
    }
    func testMeasuredCoordinatesClampAndRoundToFourDecimals() throws {
        let point = try XCTUnwrap(TemplateHotspotPlacement.point(x: 100, y: 50, width: 300, height: 200))
        XCTAssertEqual(point.x, 0.3333); XCTAssertEqual(point.y, 0.25)
        let edges = try XCTUnwrap(TemplateHotspotPlacement.point(x: -3, y: 205, width: 300, height: 200))
        XCTAssertEqual(edges.x, 0); XCTAssertEqual(edges.y, 1)
    }
    func testInvalidOrUnmeasuredGeometryDoesNotProduceCoordinates() {
        for values in [(0.0, 1.0, 0.0, 10.0), (0, 1, 10, -1), (.nan, 0, 10, 10), (0, .infinity, 10, 10), (1, 2, .infinity, 3)] {
            XCTAssertNil(TemplateHotspotPlacement.point(x: values.0, y: values.1, width: values.2, height: values.3))
        }
    }
    func testPlaceWritesOnlyChosenXYAndKeepsRadiusAndUnknownFields() throws {
        var draft = fixture(); draft.setCreatorValue(.hiddenObject, path: [.field("hotspots"), .index(1), .field("future")], entry: .string("keep"))
        draft.setCreatorValue(.hiddenObject, path: [.field("hotspots"), .index(1), .field("r")], entry: .number(0.12))
        let before = draft.rows("hiddenObject", "hotspots"), changed = try edited(draft, .place("spot_2", x: 3, y: 4, width: 10, height: 10))
        let after = changed.rows("hiddenObject", "hotspots")
        XCTAssertEqual(after[0], before[0]); XCTAssertEqual(after[2], before[2])
        XCTAssertEqual(after[1].object?["x"], .number(0.3)); XCTAssertEqual(after[1].object?["y"], .number(0.4))
        XCTAssertEqual(after[1].object?["r"], .number(0.12)); XCTAssertEqual(after[1].object?["future"], .string("keep"))
        XCTAssertEqual(after[1].object?["label"], before[1].object?["label"])
    }
    func testAddNameAndRemoveRespectThreeToFiveContract() throws {
        var draft = fixture(); XCTAssertFalse(TemplateHotspotPlacement(draft).canRemove)
        XCTAssertNil(TemplateHotspotPlacement(draft).applying(.remove("spot_1"), to: draft))
        draft = try edited(draft, .add("spot_new")); draft = try edited(draft, .label("spot_new", "Window cat"))
        XCTAssertEqual(draft.rows("hiddenObject", "hotspots")[3].object?["r"], .number(0.08))
        XCTAssertEqual(TemplateHotspotPlacement(draft).targets[3].point?.x, 0.5)
        draft = try edited(draft, .add("spot_last")); XCTAssertFalse(TemplateHotspotPlacement(draft).canAdd)
        XCTAssertNil(TemplateHotspotPlacement(draft).applying(.add("spot_six"), to: draft))
        draft = try edited(draft, .remove("spot_new")); XCTAssertFalse(TemplateHotspotPlacement(draft).targets.contains { $0.id == "spot_new" })
    }
    func testMovePreservesExistingWholeRowOrderingCapability() throws {
        let draft = fixture(), before = draft.rows("hiddenObject", "hotspots")
        let moved = try edited(draft, .move("spot_1", 2)).rows("hiddenObject", "hotspots")
        XCTAssertEqual(moved, [before[1], before[2], before[0]])
        XCTAssertNil(TemplateHotspotPlacement(draft).applying(.move("spot_1", -1), to: draft))
    }
    func testDuplicateMissingAndInvalidIDsNeverTargetAnotherRow() throws {
        let draft = fixture(), editor = TemplateHotspotPlacement(draft)
        for edit in [TemplateHotspotPlacement.Edit.add("spot_1"), .add(""), .add("bad.id"), .label("missing", "Wrong"), .place("missing", x: 0, y: 0, width: 1, height: 1)] { XCTAssertNil(editor.applying(edit, to: draft)) }
        var duplicate = draft; duplicate.setRow("hiddenObject", "hotspots", index: 1, key: "id", text: "spot_1")
        XCTAssertFalse(TemplateHotspotPlacement(duplicate).isSupported)
    }
    func testMalformedListsUseFallbackAndDisabledFamilyCannotEdit() {
        var draft = fixture(); draft.set("hiddenObject", "hotspots", .string("legacy")); XCTAssertFalse(TemplateHotspotPlacement(draft).isSupported)
        draft = fixture(); draft.setCreatorValue(.hiddenObject, path: [.field("hotspots"), .index(0), .field("r")], entry: .number(0.99)); XCTAssertFalse(TemplateHotspotPlacement(draft).isSupported)
        draft = fixture(); draft.setCreatorEnabled(.hiddenObject, false); XCTAssertFalse(TemplateHotspotPlacement(draft).canEdit)
    }
    func testUnplacedCoordinatesCanBeRepairedWithoutChangingOtherFields() throws {
        var draft = fixture(); draft.setCreatorValue(.hiddenObject, path: [.field("hotspots"), .index(0), .field("x")], entry: nil)
        XCTAssertTrue(TemplateHotspotPlacement(draft).isSupported); XCTAssertNil(TemplateHotspotPlacement(draft).targets[0].point)
        draft = try edited(draft, .place("spot_1", x: 1, y: 2, width: 4, height: 4))
        XCTAssertEqual(TemplateHotspotPlacement(draft).targets[0].point?.y, 0.5)
    }
    func testStaleSectionSnapshotCannotOverwriteNewSceneOrTargetOrder() {
        let original = fixture(), snapshot = TemplateHotspotPlacement(original)
        var draft = original; draft.set("hiddenObject", "imageUrl", .string("https://images.example.com/new.jpg"))
        XCTAssertNil(snapshot.applying(.place("spot_1", x: 1, y: 1, width: 2, height: 2), to: draft))
        draft = original; draft.moveRow("hiddenObject", "hotspots", from: 0, to: 1)
        XCTAssertNil(snapshot.applying(.label("spot_1", "Stale"), to: draft))
    }
    func testSceneURLRequiresExplicitSafeHTTPSReference() {
        var draft = fixture(); XCTAssertNotNil(TemplateHotspotPlacement(draft).sceneURL)
        for reference in ["", "http://images.example.com/x", "/relative/x", "https://user:password@example.com/x", "https://example.com/x#fragment", "https://example.com/a b", "file:///tmp/a", "https://example.com/" + String(repeating: "x", count: 513)] {
            draft.set("hiddenObject", "imageUrl", .string(reference)); XCTAssertNil(TemplateHotspotPlacement(draft).sceneURL, reference)
        }
    }
    func testPlacementSerializesAndLocalDraftRoundTrips() throws {
        var draft = try edited(fixture(), .place("spot_1", x: 1, y: 1, width: 3, height: 10))
        XCTAssertTrue(draft.creatorIssues(.hiddenObject).isEmpty)
        let normalized = try TemplateAdvancedDraft(raw: draft.serialize())
        XCTAssertEqual(TemplateHotspotPlacement(normalized).targets[0].point?.x, 0.3333)
        draft.set("timer", "enabled", .bool(true)); var local = TemplateAuthoringDraft(title: "Targets"); local.advanced = draft
        XCTAssertEqual(try JSONDecoder().decode(TemplateAuthoringDraft.self, from: JSONEncoder().encode(local)), local)
    }
}

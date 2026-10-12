import XCTest
@testable import QuestifyCore

final class TemplateLocalCategoryRemovalTests: XCTestCase {
    private func draft(_ raw: String?) -> TemplateAuthoringDraft {
        var draft = TemplateAuthoringDraft(title: "Saved categories")
        draft.activityCategoryids = raw; draft.categoryId = 88
        draft.advanced.value["future"] = .string("keep")
        return draft
    }
    func testReadingNilEmptyAndWhitespaceFormattingNeverNormalizes() {
        let values: [String?] = [nil, "", " 7, 3 ,9 "]
        for raw in values {
            let item = draft(raw), before = item, projection = TemplateLocalCategoryRemoval(item)
            XCTAssertEqual(projection.original, raw); XCTAssertTrue(projection.isCurrent(item)); XCTAssertEqual(item, before)
        }
    }
    func testRemoveOneSelectedIDPreservesOrderAndAllOtherFields() throws {
        let item = draft("7,3,9"), projection = TemplateLocalCategoryRemoval(item)
        var expected = item; expected.activityCategoryids = "7,9"
        XCTAssertEqual(try XCTUnwrap(projection.removing(3, from: item)), expected)
    }
    func testRemovingLastIDUsesExistingExplicitEmptySerialization() throws {
        let item = draft("7"), next = try XCTUnwrap(TemplateLocalCategoryRemoval(item).removing(7, from: item))
        XCTAssertEqual(next.activityCategoryids, ""); XCTAssertEqual(next.categoryId, 88)
    }
    func testUnknownAndInvalidIDsCannotAddOrChangeAnything() {
        let item = draft("7,3"), projection = TemplateLocalCategoryRemoval(item)
        for id in [0, -1, 4, Int.max] { XCTAssertNil(projection.removing(id, from: item)) }
        XCTAssertEqual(projection.selectedIDs, [7,3])
    }
    func testMalformedHistoricalValuesAreReadOnlyAndPreserved() {
        for raw in ["7,7", "07", "7,", "7,unknown", "-3", "0", " ", "7.0"] {
            let item = draft(raw), projection = TemplateLocalCategoryRemoval(item)
            XCTAssertFalse(projection.isSupported); XCTAssertEqual(projection.original, raw)
            XCTAssertTrue(projection.selectedIDs.isEmpty); XCTAssertNil(projection.removing(7, from: item))
        }
    }
    func testExplicitRemovalUsesExistingStrictSelectionSerializer() throws {
        let item = draft(" 7, 3 ,9 ")
        var expected = TemplateMetadataCategorySelection(raw: item.activityCategoryids); expected.toggle(3)
        let next = try XCTUnwrap(TemplateLocalCategoryRemoval(item).removing(3, from: item))
        XCTAssertEqual(next.activityCategoryids, expected.savedValue); XCTAssertEqual(next.activityCategoryids, "7,9")
    }
    func testFullDraftAndUnicodeByteChangesRejectStaleProjection() {
        var item = draft("7,3"); item.title = "\u{00E9}"
        let projection = TemplateLocalCategoryRemoval(item); var changed = item
        changed.title = "e\u{0301}"; XCTAssertFalse(projection.isCurrent(changed)); XCTAssertNil(projection.removing(7, from: changed))
        changed = item; changed.description = "Other"; XCTAssertNil(projection.removing(7, from: changed))
    }
    func testUnencodableSnapshotCannotRemove() {
        var item = draft("7,3"); item.advanced.set("timer", "durationSeconds", .number(.nan))
        let projection = TemplateLocalCategoryRemoval(item)
        XCTAssertFalse(projection.isSupported); XCTAssertNil(projection.removing(7, from: item))
    }
}

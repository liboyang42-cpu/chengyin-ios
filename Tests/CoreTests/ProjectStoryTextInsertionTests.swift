import XCTest
@testable import QuestifyCore

final class ProjectStoryTextInsertionTests: XCTestCase {
    private func draft(count: Int = 3) -> ProjectEditDraft {
        var draft = ProjectEditSyntheticFixtures.draft(); draft.chapters[0].id = "chapter"
        draft.chapters[0].blocks = (0..<count).map { index in
            var block = ProjectEditBlock(kind: index == 1 ? .voice : .text, content: index == 0 ? " e\u{301} " : "é\n")
            block.id = "block-\(index)"; block.sourceFields = ["future": .string(" retained ")]; return block
        }; return draft
    }
    private func snapshot(_ value: ProjectEditDraft, before: String = "block-1") -> ProjectStoryTextInsertion {
        .init(draft: value, chapterID: "chapter", beforeBlockID: before)
    }
    func testFirstMiddleAndLastAnchorInsertionPreserveEveryExistingByteAndOrder() throws {
        for position in 0..<3 {
            let original = draft(), next = try snapshot(original, before: "block-\(position)").inserting(blockID: "new", in: original)
            var expected = original, added = ProjectEditBlock(kind: .text); added.id = "new"
            expected.chapters[0].blocks?.insert(added, at: position)
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(next), ProjectEditPendingMaterials.exactData(expected))
            var remaining = next; remaining.chapters[0].blocks?.remove(at: position)
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(remaining), ProjectEditPendingMaterials.exactData(original))
            XCTAssertEqual(next.chapters[0].blocks?[position].content, ""); XCTAssertNil(next.chapters[0].blocks?[position].sourceFields)
        }
    }
    func testSourceCapAccepts199AndRejects200OrMoreWithoutMutation() throws {
        let allowed = draft(count: 199), next = try snapshot(allowed).inserting(blockID: "new", in: allowed)
        XCTAssertEqual(next.chapters[0].blocks?.count, 200)
        for count in [200, 201] { let value = draft(count: count); XCTAssertEqual(snapshot(value).reason, .limit); XCTAssertThrowsError(try snapshot(value).inserting(blockID: "new", in: value)) }
    }
    func testMissingLegacyEmptyOrUnsupportedChapterIsNotMaterialized() {
        for kind in ["legacy", "empty", "schema", "chapter"] {
            var value = draft()
            switch kind {
            case "legacy": value.chapters[0].blocks = nil
            case "empty": value.chapters[0].blocks = []
            case "schema": value.chapters[0].schemaVersion = 2
            default: value.chapters[0].id = "other"
            }
            XCTAssertNotNil(snapshot(value).reason); XCTAssertThrowsError(try snapshot(value).inserting(blockID: "new", in: value))
        }
    }
    func testDuplicateEmptyAndCanonicalAliasBlockIDsFailClosed() {
        for kind in ["duplicate", "empty", "alias"] {
            var value = draft()
            switch kind {
            case "duplicate": value.chapters[0].blocks?[0].id = "block-1"
            case "empty": value.chapters[0].blocks?[0].id = ""
            default: value.chapters[0].blocks?[0].id = "é"; value.chapters[0].blocks?[2].id = "e\u{301}"
            }
            XCTAssertEqual(snapshot(value).reason, .identity)
        }
    }
    func testExactTargetIdentityRejectsCanonicalOnlyMatchAndCrossChapterDuplicate() {
        var value = draft(); value.chapters[0].blocks?[1].id = "é"
        XCTAssertEqual(snapshot(value, before: "e\u{301}").reason, .identity)
        let duplicate = value.chapters[0]; value.chapters.append(duplicate)
        XCTAssertEqual(snapshot(value, before: "é").reason, .identity)
        value.chapters[1].id = "other"
        XCTAssertEqual(snapshot(value, before: "é").reason, .identity)
    }
    func testFreshKeyMustNotDuplicateExistingExactOrCanonicalBlockID() {
        var value = draft(); value.chapters[0].blocks?[0].id = "é"
        for key in ["", "block-1", "é", "e\u{301}"] { XCTAssertThrowsError(try snapshot(value).inserting(blockID: key, in: value)) }
    }
    func testStaleAnchorReorderDeletionAndOtherChangesReject() {
        let original = draft(), captured = snapshot(original)
        for kind in ["reorder", "delete", "other", "text"] {
            var next = original
            switch kind {
            case "reorder": next.chapters[0].blocks?.swapAt(0, 1)
            case "delete": next.chapters[0].blocks?.remove(at: 1)
            case "other": next.name += "!"
            default: next.chapters[0].blocks?[0].content += "!"
            }
            XCTAssertFalse(captured.isCurrent(in: next)); XCTAssertThrowsError(try captured.inserting(blockID: "new", in: next))
        }
    }
    func testNodeImageAudioAndRichAnchorsRemainUnmodified() throws {
        for kind in ProjectEditBlock.Kind.allCases {
            var original = draft(); original.chapters[0].blocks?[1].kind = kind
            original.chapters[0].blocks?[1].nodeID = "raw-node"; original.chapters[0].blocks?[1].url = "raw-reference"
            let next = try snapshot(original).inserting(blockID: "new", in: original)
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(next.chapters[0].blocks?[2]), ProjectEditPendingMaterials.exactData(original.chapters[0].blocks?[1]))
        }
    }
}

import XCTest
@testable import QuestifyCore

final class ProjectRichStoryInsertionTests: XCTestCase {
    private func draft(count: Int = 3) -> ProjectEditDraft {
        var draft = ProjectEditSyntheticFixtures.draft(); draft.chapters[0].id = "chapter"
        draft.chapters[0].blocks = (0..<count).map { i in
            var block = ProjectEditBlock(kind: i == 1 ? .voice : .text, content: " e\u{301} \(i)"); block.id = "block-\(i)"
            block.sourceFields = ["future": .object(["raw": .string(" preserved ")])]; return block
        }; return draft
    }
    private func snapshot(_ d: ProjectEditDraft, anchor: String = "block-1") -> ProjectRichStoryInsertion { .init(draft: d, chapterID: "chapter", beforeBlockID: anchor) }
    func testEveryExistingRichKindUsesExactCurrentDefaultAtFirstMiddleAndLastAnchor() throws {
        for kind in ProjectEditRichStoryContract.richKinds { for index in 0..<3 {
            let original = draft(); let next = try snapshot(original, anchor: "block-\(index)").inserting(kind, blockID: "new", in: original)
            var expected = original, block = ProjectEditRichStoryContract.defaultBlock(kind); block.id = "new"
            expected.chapters[0].blocks!.insert(block, at: index)
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(next), ProjectEditPendingMaterials.exactData(expected))
            var inverse = next; inverse.chapters[0].blocks!.remove(at: index)
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(inverse), ProjectEditPendingMaterials.exactData(original))
        } }
    }
    func testNonRichKindsCannotBypassExistingOtherAuthoringPaths() {
        let original = draft()
        for kind in ProjectEditBlock.Kind.allCases where !ProjectEditRichStoryContract.richKinds.contains(kind) {
            XCTAssertThrowsError(try snapshot(original).inserting(kind, blockID: "new", in: original))
        }
    }
    func testCapacity199AllowsExactlyOneAnd200Rejects() throws {
        let allowed = draft(count: 199); XCTAssertEqual(try snapshot(allowed).inserting(.dream, blockID: "new", in: allowed).chapters[0].blocks?.count, 200)
        let full = draft(count: 200); XCTAssertFalse(snapshot(full).isCurrent(in: full)); XCTAssertThrowsError(try snapshot(full).inserting(.voice, blockID: "new", in: full))
    }
    func testLegacyUnsupportedSchemaAndMissingAnchorDoNotMaterializeStory() {
        for kind in ["legacy", "schema", "anchor"] {
            var original = draft()
            switch kind { case "legacy": original.chapters[0].blocks = nil; case "schema": original.chapters[0].schemaVersion = 2; default: original.chapters[0].blocks!.remove(at: 1) }
            XCTAssertFalse(snapshot(original).isCurrent(in: original)); XCTAssertThrowsError(try snapshot(original).inserting(.mood, blockID: "new", in: original))
        }
    }
    func testDuplicateOrCanonicalAliasAnchorAndNewIDFailClosed() {
        var original = draft(); original.chapters[0].blocks![0].id = "é"
        for id in ["", "block-1", "é", "e\u{301}"] { XCTAssertThrowsError(try snapshot(original).inserting(.odd, blockID: id, in: original)) }
        XCTAssertFalse(snapshot(original, anchor: "e\u{301}").isCurrent(in: original))
        original.chapters[0].blocks![2].id = "block-1"; XCTAssertFalse(snapshot(original).isCurrent(in: original))
    }
    func testUnrelatedEditsAnchorReorderAndRemovalRejectOldSnapshot() {
        let original = draft(), captured = snapshot(original)
        for kind in ["other", "reorder", "remove"] {
            var next = original
            switch kind { case "other": next.name += "!"; case "reorder": next.chapters[0].blocks!.swapAt(0, 1); default: next.chapters[0].blocks!.remove(at: 1) }
            XCTAssertFalse(captured.isCurrent(in: next)); XCTAssertThrowsError(try captured.inserting(.reveal, blockID: "new", in: next))
        }
    }
}

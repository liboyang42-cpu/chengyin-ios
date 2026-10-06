import XCTest
@testable import QuestifyCore

final class ProjectEditPendingChapterTests: XCTestCase {
    private func draft(_ product: ProjectEditProduct) -> ProjectEditDraft {
        var draft = ProjectEditSyntheticFixtures.draft(product: product); draft.chapters = []
        var node = ProjectEditNode(); node.name = "Pending node"; node.longitude = "121.5"; node.latitude = "31.2"
        node.description = "  e\u{301}\t\n"; node.imgUrl = "fixture:source-reference"; node.nodeTime = 45; node.templateID = 73
        node.localMetadata = ["future": .object(["kept": .bool(true)]), "hookText": .string("Original hook")]
        draft.pendingMaterials = [.init(node: node, kind: .place)]; return draft
    }
    func testFreeNewChapterAtomicallyContainsExactMaterialAndRemovesOnlyThatPendingRow() throws {
        var original = draft(.freeExplore); let row = try XCTUnwrap(original.pendingMaterials?.first)
        var other = row; other.node.id = "other"; other.node.name = "Other material"; original.pendingMaterials?.append(other)
        let result = try ProjectEditPendingChapter.create(for: row.id, name: "Chapter 1", in: original)
        XCTAssertEqual(result.draft.chapters.count, 1); XCTAssertEqual(result.draft.chapters[0].id, result.chapterID)
        XCTAssertNil(result.draft.chapters[0].blocks); XCTAssertEqual(result.draft.chapters[0].description, "")
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(result.draft.chapters[0].nodes[0]), ProjectEditPendingMaterials.exactData(row.node))
        XCTAssertEqual(result.draft.pendingMaterials, [other]); XCTAssertEqual(original.pendingMaterials?.count, 2)
        XCTAssertNil(try ProjectEditContract.payload(result.draft, topicID: nil, scope: .full)["pendingMaterials"])
    }
    func testCityNewChapterKeepsMaterialAndEmptyStoryUntilExplicitInsertion() throws {
        let original = draft(.city), row = try XCTUnwrap(original.pendingMaterials?.first)
        let result = try ProjectEditPendingChapter.create(for: row.id, name: "Chapter 1", in: original)
        let chapter = result.draft.chapters[0]
        XCTAssertEqual(chapter.blocks, []); XCTAssertTrue(chapter.nodes.isEmpty); XCTAssertEqual(chapter.description, "")
        XCTAssertEqual(chapter.schemaVersion, 1); XCTAssertEqual(chapter.required, 1); XCTAssertEqual(result.draft.pendingMaterials, original.pendingMaterials)
        XCTAssertThrowsError(try ProjectEditPendingMaterials.arranging(row.id, into: chapter.id, expectedBlocks: [], in: result.draft))
        var written = result.draft; written.chapters[0].blocks = [.init(kind: .text, content: "Real story")]
        let placed = try ProjectEditPendingMaterials.arranging(row.id, into: chapter.id, expectedBlocks: written.chapters[0].blocks?.map(\.id), in: written)
        XCTAssertEqual(placed.chapters[0].nodes, [row.node]); XCTAssertEqual(placed.pendingMaterials, [])
    }
    func testMissingInvalidCoordinatesAndMissingMaterialCannotCreateGhostChapter() throws {
        for coordinate in ["", "bad", "181"] {
            var original = draft(.freeExplore); original.pendingMaterials?[0].node.longitude = coordinate
            let before = ProjectEditPendingMaterials.exactData(original), id = try XCTUnwrap(original.pendingMaterials?.first?.id)
            XCTAssertThrowsError(try ProjectEditPendingChapter.create(for: id, name: "Chapter 1", in: original))
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(original), before)
        }
        let original = draft(.city)
        XCTAssertThrowsError(try ProjectEditPendingChapter.create(for: "missing", name: "Chapter 1", in: original))
        XCTAssertThrowsError(try ProjectEditPendingChapter.create(for: XCTUnwrap(original.pendingMaterials?.first?.id), name: " \n", in: original))
    }
    func testExistingChapterOrderBytesAndOpeningRoleRemainUnchanged() throws {
        var original = draft(.city), opening = ProjectEditChapter(), existing = ProjectEditChapter()
        opening.name = "Opening"; opening.preserved["opening"] = .bool(true); opening.blocks = [.init(kind: .text, content: "Opening story")]
        existing.name = "  e\u{301}\n"; existing.description = "Unchanged existing chapter"; original.chapters = [opening, existing]
        let before = ProjectEditPendingMaterials.exactData(original.chapters), id = try XCTUnwrap(original.pendingMaterials?.first?.id)
        let result = try ProjectEditPendingChapter.create(for: id, name: "Chapter 2", in: original)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(Array(result.draft.chapters.prefix(2))), before)
        XCTAssertNil(result.draft.chapters[2].preserved["opening"]); XCTAssertEqual(result.draft.chapters[2].name, "Chapter 2")
    }
    func testDuplicateIdentityRejectsBeforeCreatingOrRemovingAnyMaterial() throws {
        var original = draft(.freeExplore); let row = try XCTUnwrap(original.pendingMaterials?.first)
        original.pendingMaterials?.append(row); let before = ProjectEditPendingMaterials.exactData(original)
        XCTAssertThrowsError(try ProjectEditPendingChapter.create(for: row.id, name: "Chapter 1", in: original))
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(original), before)
    }
}

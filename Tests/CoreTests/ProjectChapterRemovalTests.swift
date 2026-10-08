import XCTest
@testable import QuestifyCore

final class ProjectChapterRemovalTests: XCTestCase {
    private func draft(product: ProjectEditProduct = .city) -> ProjectEditDraft {
        var value = ProjectEditSyntheticFixtures.draft(product: product)
        value.preserved["futureTopic"] = .object(["raw": .string("e\u{301}")])
        value.preserved["routeGraphJson"] = .string("opaque cross-chapter references")
        value.chapters[0].preserved["futureChapter"] = .object(["raw": .string("  untouched  ")])
        value.chapters[0].nodes[0].localMetadata["futureNode"] = .number(7)
        var second = ProjectEditChapter(); second.id = "second"; second.name = "Retained"
        second.preserved["futureChapter"] = .array([.null, .bool(true)])
        value.chapters.append(second)
        var pending = ProjectEditNode(); pending.id = "pending"; pending.name = "Pending"
        value.pendingMaterials = [.init(node: pending, kind: .place)]
        return value
    }
    func testSelectionUsesChapterOrderAndDoesNotMutateDraft() throws {
        let source = draft()
        let before = ProjectEditPendingMaterials.exactData(source)
        let ids = source.chapters.map(\.id)
        let selected = try ProjectChapterRemoval.selecting(Array(ids.reversed()), in: source)
        XCTAssertEqual(selected, source.chapters)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(source), before)
        XCTAssertEqual(source.chapters.count, 2)
    }
    func testDeletingOneChapterRetainsEveryOtherLocalFieldExactly() throws {
        for product in ProjectEditProduct.allCases {
            let source = draft(product: product)
            let next = try ProjectChapterRemoval.removing([source.chapters[0].id], from: source)
            var expected = source; expected.chapters.removeFirst()
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(next), ProjectEditPendingMaterials.exactData(expected))
            XCTAssertEqual(next.preserved["routeGraphJson"], source.preserved["routeGraphJson"])
            XCTAssertEqual(next.pendingMaterials, source.pendingMaterials)
            XCTAssertEqual(next.chapters[0], source.chapters[1])
            XCTAssertEqual(source.chapters.count, 2)
        }
    }
    func testDeletingAllChaptersLeavesDraftAndPendingMaterialsAvailable() throws {
        let source = draft()
        let next = try ProjectChapterRemoval.removing(source.chapters.map(\.id), from: source)
        XCTAssertTrue(next.chapters.isEmpty)
        XCTAssertEqual(next.pendingMaterials, source.pendingMaterials)
        XCTAssertEqual(next.tickets, source.tickets)
        XCTAssertEqual(next.preserved, source.preserved)
    }
    func testMissingEmptyAndRepeatedTargetsRejectWithoutPartialDeletion() throws {
        let source = draft(), target = source.chapters[0].id
        for ids in [[], [""], ["missing"], [target, "missing"], [target, target]] {
            XCTAssertThrowsError(try ProjectChapterRemoval.removing(ids, from: source))
        }
        XCTAssertEqual(source.chapters.count, 2)
    }
    func testDuplicateOrEmptyChapterIdentityRejectsEvenWhenNotSelected() throws {
        var source = draft()
        source.chapters[1].id = source.chapters[0].id
        XCTAssertThrowsError(try ProjectChapterRemoval.removing([source.chapters[0].id], from: source))
        source.chapters[1].id = ""
        XCTAssertThrowsError(try ProjectChapterRemoval.removing([source.chapters[0].id], from: source))
    }
    func testDeletedChapterIncludesItsOpaqueNodeAndStoryDataOnly() throws {
        var source = draft()
        let nodeID = source.chapters[0].nodes[0].id
        source.chapters[0].blocks = [.init(kind: .text, content: "Original"), .init(kind: .node, nodeID: nodeID)]
        let capture = try ProjectChapterRemoval.selecting([source.chapters[0].id], in: source)
        XCTAssertEqual(capture[0].nodes[0].localMetadata["futureNode"], .number(7))
        XCTAssertEqual(capture[0].blocks, source.chapters[0].blocks)
        let next = try ProjectChapterRemoval.removing([source.chapters[0].id], from: source)
        XCTAssertEqual(next.chapters, [source.chapters[1]])
    }
}

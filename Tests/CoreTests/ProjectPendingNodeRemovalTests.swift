import XCTest
@testable import QuestifyCore

final class ProjectPendingNodeRemovalTests: XCTestCase {
    private func draft() -> ProjectEditDraft {
        var value = ProjectEditDraft(product: .freeExplore), chapter = ProjectEditChapter()
        chapter.id = "chapter"
        chapter.nodes = ["a", "b", "c"].map { id in
            var node = ProjectEditNode(); node.id = id; node.name = "  \(id) e\u{301}\n"
            node.description = "  é\n"; node.templateID = 7
            node.localMetadata["future"] = .object(["raw": .string(" e\u{301} ")]); return node
        }
        var pending = ProjectEditNode(); pending.id = "pending"; pending.name = "Existing pending"
        value.chapters = [chapter]; value.pendingMaterials = [.init(node: pending, kind: .place)]
        value.preserved["future"] = .string("untouched")
        return value
    }
    func testMoveKeepsOriginalOrderIdentifiersAllNodeBytesAndExistingPendingKind() throws {
        let original = draft(), receipt = try ProjectPendingNodeRemoval.moving(["c", "a"], chapterID: "chapter", in: original)
        XCTAssertEqual(receipt.after.chapters[0].nodes.map(\.id), ["b"])
        XCTAssertEqual(receipt.after.pendingMaterials?.map(\.id), ["pending", "a", "c"])
        XCTAssertEqual(receipt.after.pendingMaterials?.first?.kind, .place)
        for (offset, index) in [(1, 0), (2, 2)] {
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(receipt.after.pendingMaterials![offset].node),
                           ProjectEditPendingMaterials.exactData(original.chapters[0].nodes[index]))
        }
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(try ProjectPendingNodeRemoval.restoring(receipt, in: receipt.after)),
                       ProjectEditPendingMaterials.exactData(original))
    }
    func testRestoreKeepsNilPendingRepresentationAndRepeatedRestoreIsRejected() throws {
        var original = draft(); original.pendingMaterials = nil
        let receipt = try ProjectPendingNodeRemoval.moving(["a", "b", "c"], chapterID: "chapter", in: original)
        XCTAssertTrue(receipt.after.chapters[0].nodes.isEmpty)
        let restored = try ProjectPendingNodeRemoval.restoring(receipt, in: receipt.after)
        XCTAssertNil(restored.pendingMaterials)
        XCTAssertThrowsError(try ProjectPendingNodeRemoval.restoring(receipt, in: restored))
    }
    func testConsecutiveMovesCombineAndUndoRestoresExactInitialOrder() throws {
        let original = draft(), first = try ProjectPendingNodeRemoval.moving(["b"], chapterID: "chapter", in: original)
        let second = try ProjectPendingNodeRemoval.moving(["a"], chapterID: "chapter", in: first.after)
        let combined = try ProjectPendingNodeRemoval.combining(first, with: second)
        XCTAssertEqual(combined.nodeIDs, ["b", "a"])
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(try ProjectPendingNodeRemoval.restoring(combined, in: second.after)),
                       ProjectEditPendingMaterials.exactData(original))
        XCTAssertThrowsError(try ProjectPendingNodeRemoval.combining(second, with: first))
    }
    func testUnrelatedAndCanonicalEquivalentChangesCannotBeOverwrittenByUndo() throws {
        let receipt = try ProjectPendingNodeRemoval.moving(["a"], chapterID: "chapter", in: draft())
        var current = receipt.after; current.name = "New user edit"
        XCTAssertThrowsError(try ProjectPendingNodeRemoval.restoring(receipt, in: current))
        current = receipt.after; current.pendingMaterials![1].node.description = "  e\u{301}\n"
        XCTAssertEqual(current, receipt.after)
        XCTAssertThrowsError(try ProjectPendingNodeRemoval.restoring(receipt, in: current))
    }
    func testCityStoriesUnknownRoutesOpeningChaptersDuplicatesAndStaleTargetsAreRejected() throws {
        let original = draft()
        for ids in [[], ["missing"], ["a", "a"], ["a", "missing"]] {
            XCTAssertThrowsError(try ProjectPendingNodeRemoval.moving(ids, chapterID: "chapter", in: original))
        }
        var current = original; current.product = .city
        XCTAssertThrowsError(try ProjectPendingNodeRemoval.moving(["a"], chapterID: "chapter", in: current))
        current = original; current.chapters[0].blocks = []
        XCTAssertThrowsError(try ProjectPendingNodeRemoval.moving(["a"], chapterID: "chapter", in: current))
        current = original; current.chapters[0].preserved["opening"] = .bool(true)
        XCTAssertThrowsError(try ProjectPendingNodeRemoval.moving(["a"], chapterID: "chapter", in: current))
        current = original; current.preserved["routeGraphJson"] = .string("opaque")
        XCTAssertThrowsError(try ProjectPendingNodeRemoval.moving(["a"], chapterID: "chapter", in: current))
        current = original; current.pendingMaterials?.append(.init(node: current.chapters[0].nodes[0]))
        XCTAssertThrowsError(try ProjectPendingNodeRemoval.moving(["a"], chapterID: "chapter", in: current))
    }
}

import XCTest
@testable import QuestifyCore

final class ProjectNodeNarrativeTests: XCTestCase {
    func testMergeMatchesCurrentMiniAndKeepsParagraphsAndDistinctUnicodeBytes() throws {
        var node = ProjectEditNode(); node.description = "  First\n\nSecond  "
        node.localMetadata = ["hookText": .string("First\n\nSecond"), "cardHookLong": .string(" e\u{301} "), "fragmentText": .string("é")]
        let before = ProjectEditPendingMaterials.exactData(node)
        let merged = try ProjectNodeNarrative.mergedDescription(in: node)
        XCTAssertEqual(Array(merged.utf8), Array("First\n\nSecond\ne\u{301}\né".utf8))
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(node), before)
    }
    func testMissingNullAndEmptyAreAcceptedWithoutMutationUntilExplicitApply() throws {
        var node = ProjectEditNode(); node.description = "Description"
        node.localMetadata = ["hookText": .null, "cardHookLong": .string(""), "future": .object(["value": .bool(true)])]
        let before = node
        XCTAssertEqual(try ProjectNodeNarrative.mergedDescription(in: node), "Description")
        XCTAssertEqual(node, before)
        let next = try ProjectNodeNarrative.applying("", to: node)
        XCTAssertEqual(next.description, "")
        for field in ProjectNodeNarrative.Field.allCases { XCTAssertEqual(next.localMetadata[field.rawValue], .string("")) }
        XCTAssertEqual(next.localMetadata["future"], before.localMetadata["future"])
        XCTAssertEqual(next.id, before.id); XCTAssertEqual(next.name, before.name)
    }
    func testUnknownLegacyTypesAreNeverFlattenedOrCleared() {
        for field in ProjectNodeNarrative.Field.allCases {
            for value in [ProjectEditJSON.bool(true), .number(1), .array([.string("future")]), .object(["future": .null])] {
                var node = ProjectEditNode(); node.localMetadata[field.rawValue] = value
                let before = ProjectEditPendingMaterials.exactData(node)
                XCTAssertThrowsError(try ProjectNodeNarrative.mergedDescription(in: node))
                XCTAssertThrowsError(try ProjectNodeNarrative.applying("replacement", to: node))
                XCTAssertEqual(ProjectEditPendingMaterials.exactData(node), before)
            }
        }
    }
    func testExistingLongTextRemainsReadableAndNeverSilentlyTruncated() throws {
        var node = ProjectEditNode(); node.description = String(repeating: "🚲", count: 1001)
        XCTAssertEqual(try ProjectNodeNarrative.mergedDescription(in: node), node.description)
        XCTAssertThrowsError(try ProjectNodeNarrative.applying(node.description, to: node))
        let exact = " \n" + String(repeating: "x", count: 1997) + " "
        XCTAssertEqual(exact.utf16.count, 2000)
        XCTAssertEqual(try ProjectNodeNarrative.applying(exact, to: node).description, exact)
    }
    func testPreparedReviewUsesSerializedNodeOrderAndImmutableLegacyValues() throws {
        var draft = ProjectEditSyntheticFixtures.draft(), second = draft.chapters[0].nodes[0]
        let firstID = draft.chapters[0].nodes[0].id
        draft.chapters[0].nodes[0].localMetadata["hookText"] = .string("First legacy hook")
        second.id = "second"; second.localMetadata["hookText"] = .string("Second legacy hook")
        draft.chapters[0].nodes.append(second)
        draft.chapters[0].blocks = [.init(kind: .text, content: "Story"), .init(kind: .node, nodeID: second.id), .init(kind: .node, nodeID: firstID)]
        let captured = try ProjectEditContract.payload(draft, topicID: nil, scope: .full)
        let review = ProjectEditPreparedNodes(payload: captured)
        draft.chapters[0].nodes[0].localMetadata["hookText"] = .string("Later mutable draft")
        XCTAssertEqual(review.chapters?.first?.nodes?.map { $0.raw.object?["hookText"] }, [.string("Second legacy hook"), .string("First legacy hook")])
        XCTAssertEqual(review.raw, captured["chapters"])
    }
}

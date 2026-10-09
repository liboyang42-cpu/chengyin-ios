import XCTest
@testable import QuestifyCore

final class ProjectNodeGameplayRemovalTests: XCTestCase {
    func testOnlyTypedReferenceAndThreeExistingCompanionFieldsChange() throws {
        var draft = ProjectEditSyntheticFixtures.draft()
        draft.chapters[0].nodes[0].localMetadata = ["templateId": .number(41), "templateInfo": .object(["id": .number(41)]),
            "templateName": .string("e\u{301}"), "future": .object(["keep": .string("e\u{301}")])]
        var expected = draft; expected.chapters[0].nodes[0].templateID = nil
        expected.chapters[0].nodes[0].localMetadata["templateId"] = .number(0)
        expected.chapters[0].nodes[0].localMetadata["templateInfo"] = .object([:])
        expected.chapters[0].nodes[0].localMetadata["templateName"] = .string("")
        let next = try ProjectNodeGameplayRemoval.clearing(chapterID: draft.chapters[0].id, nodeID: draft.chapters[0].nodes[0].id, in: draft)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(next), ProjectEditPendingMaterials.exactData(expected))
        let repeatValue = try ProjectNodeGameplayRemoval.clearing(chapterID: next.chapters[0].id, nodeID: next.chapters[0].nodes[0].id, in: next)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(repeatValue), ProjectEditPendingMaterials.exactData(next))
    }
    func testAbsentCompanionsAreNotSynthesizedAndNoTemplateIsNoOp() throws {
        var draft = ProjectEditSyntheticFixtures.draft()
        let cleared = try ProjectNodeGameplayRemoval.clearing(chapterID: draft.chapters[0].id, nodeID: draft.chapters[0].nodes[0].id, in: draft)
        XCTAssertTrue(cleared.chapters[0].nodes[0].localMetadata.isEmpty)
        draft.chapters[0].nodes[0].templateID = nil; draft.chapters[0].nodes[0].localMetadata["templateInfo"] = .object(["future": .bool(true)])
        let next = try ProjectNodeGameplayRemoval.clearing(chapterID: draft.chapters[0].id, nodeID: draft.chapters[0].nodes[0].id, in: draft)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(next), ProjectEditPendingMaterials.exactData(draft))
    }
    func testStoryOnlyNodesOpeningAndBranchGraphsCannotBeUnbound() throws {
        for scope in ["story", "opening", "branch", "opaque", "unknown"] {
            var draft = ProjectEditSyntheticFixtures.draft(), block = ProjectEditBlock(kind: .node)
            block.nodeID = draft.chapters[0].nodes[0].id
            switch scope {
            case "story": block.sourceFields = ["locationRequired": .bool(false)]; draft.chapters[0].blocks = [block]
            case "opening": draft.chapters[0].preserved["opening"] = .bool(true)
            case "branch": draft.preserved["routeMode"] = .string("BRANCH_GRAPH")
            case "opaque": draft.preserved["routeGraphJson"] = .string("legacy-opaque")
            default: block.sourceFields = ["locationRequired": .string("future")]; draft.chapters[0].blocks = [block]
            }
            XCTAssertThrowsError(try ProjectNodeGameplayRemoval.clearing(chapterID: draft.chapters[0].id, nodeID: draft.chapters[0].nodes[0].id, in: draft), scope)
        }
    }
    func testDuplicateAndCanonicalAliasIDsCannotTargetAnotherNode() throws {
        var draft = ProjectEditSyntheticFixtures.draft(); draft.chapters[0].nodes[0].id = "e\u{301}"
        XCTAssertNil(ProjectNodeGameplayRemoval.index(chapterID: draft.chapters[0].id, nodeID: "é", in: draft))
        draft.chapters[0].nodes.append(draft.chapters[0].nodes[0])
        XCTAssertNil(ProjectNodeGameplayRemoval.index(chapterID: draft.chapters[0].id, nodeID: "e\u{301}", in: draft))
    }
}

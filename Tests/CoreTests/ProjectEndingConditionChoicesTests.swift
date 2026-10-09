import XCTest
@testable import QuestifyCore

final class ProjectEndingConditionChoicesTests: XCTestCase {
    private func draft(op: String = "HAS_TAG", value: ProjectEditJSON = .string("unknown")) -> ProjectEditDraft {
        var draft = ProjectEditSyntheticFixtures.draft()
        draft.preserved["journeyRules"] = .string(#"{"schemaVersion":1,"thoughts":[{"key":"first","name":"First","need":120}]}"#)
        draft.chapters[0].nodes[0].localMetadata["id"] = .number(19)
        var ending = ProjectEditChapter(); ending.name = "Ending"
        ending.preserved["ending"] = .object(["fallback": .bool(false), "future": .string("keep"), "when": .array([.object(["op": .string(op), (op == "HAS_TAG" ? "value" : "nodeId"): value, "future": .string("e\u{301}")])])])
        draft.chapters.append(ending); return draft
    }
    func testThoughtAndOnlyActualMatchingTemplateTagAreChoices() throws {
        var draft = draft()
        let config = #"{"schemaVersion":1,"options":[{"label":"Door","effects":[{"op":"ADD_TAG","value":"tag.door"}]}]}"#
        draft.chapters[0].nodes[0].localMetadata["templateInfo"] = .object(["id": .number(999), "advancedConfigJson": .string(config)])
        XCTAssertEqual(ProjectEndingConditionChoices.choices(in: draft, operation: "HAS_TAG").map(\.id), ["thought:first"])
        draft.chapters[0].nodes[0].localMetadata["templateInfo"] = .object(["id": .number(41), "advancedConfigJson": .string(config)])
        let choices = ProjectEndingConditionChoices.choices(in: draft, operation: "HAS_TAG")
        XCTAssertEqual(choices.map(\.id), ["thought:first", "tag:tag.door"])
        XCTAssertEqual(choices[0].value, .string("thought.first.done")); XCTAssertEqual(choices[1].value, .string("tag.door"))
    }
    func testUnsavedDuplicateServerOrLocalNodeIDsAreNeverInferred() throws {
        var draft = draft(op: "NODE_COMPLETED", value: .number(99))
        XCTAssertEqual(ProjectEndingConditionChoices.choices(in: draft, operation: "NODE_COMPLETED").map(\.id), ["node:19"])
        var other = ProjectEditNode(); other.name = "Unsaved"; draft.chapters[0].nodes.append(other)
        XCTAssertEqual(ProjectEndingConditionChoices.choices(in: draft, operation: "NODE_COMPLETED").count, 1)
        other.localMetadata["id"] = .number(19); draft.chapters[0].nodes[1] = other
        XCTAssertTrue(ProjectEndingConditionChoices.choices(in: draft, operation: "NODE_COMPLETED").isEmpty)
        draft.chapters[0].nodes[1].localMetadata["id"] = .number(20); draft.chapters[0].nodes[1].id = draft.chapters[0].nodes[0].id
        XCTAssertTrue(ProjectEndingConditionChoices.choices(in: draft, operation: "NODE_COMPLETED").isEmpty)
    }
    func testApplyChangesOnlyReferenceAndNoOpKeepsExactDraftAndUnknownFields() throws {
        let draft = draft(), chapterID = draft.chapters[1].id
        let target = try ProjectEndingConditionChoices.Target(draft: draft, chapterID: chapterID, index: 0)
        let choice = try XCTUnwrap(ProjectEndingConditionChoices.choices(in: draft, operation: "HAS_TAG").first)
        let next = try ProjectEndingConditionChoices.applying(choice, to: draft, target: target)
        var expected = draft
        expected.chapters[1].preserved["ending"] = .object(["fallback": .bool(false), "future": .string("keep"), "when": .array([.object(["op": .string("HAS_TAG"), "value": .string("thought.first.done"), "future": .string("e\u{301}")])])])
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(next), ProjectEditPendingMaterials.exactData(expected))
        let repeatTarget = try ProjectEndingConditionChoices.Target(draft: next, chapterID: chapterID, index: 0)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(try ProjectEndingConditionChoices.applying(choice, to: next, target: repeatTarget)), ProjectEditPendingMaterials.exactData(next))
    }
    func testRemovedSourceChangedPredicateOrFallbackCannotAcceptOldChoice() throws {
        let original = draft(), target = try ProjectEndingConditionChoices.Target(draft: original, chapterID: original.chapters[1].id, index: 0)
        let choice = try XCTUnwrap(ProjectEndingConditionChoices.choices(in: original, operation: "HAS_TAG").first)
        var noSource = original; noSource.preserved["journeyRules"] = .string("{}")
        XCTAssertThrowsError(try ProjectEndingConditionChoices.applying(choice, to: noSource, target: target))
        var changed = original; changed.chapters[1].preserved["ending"] = .object(["fallback": .bool(true)])
        XCTAssertThrowsError(try ProjectEndingConditionChoices.applying(choice, to: changed, target: target))
        XCTAssertThrowsError(try ProjectEndingConditionChoices.Target(draft: changed, chapterID: original.chapters[1].id, index: 0))
    }
    func testOtherProductOrAmbiguousEndingChapterHasNoTarget() throws {
        var draft = draft(), id = draft.chapters[1].id; draft.product = .freeExplore
        XCTAssertThrowsError(try ProjectEndingConditionChoices.Target(draft: draft, chapterID: id, index: 0))
        draft.product = .city; draft.chapters.append(draft.chapters[1])
        XCTAssertThrowsError(try ProjectEndingConditionChoices.Target(draft: draft, chapterID: id, index: 0))
    }
}

import XCTest
@testable import QuestifyCore

final class ProjectStoryConditionChoiceTests: XCTestCase {
    private func draft() -> ProjectEditDraft {
        var draft = ProjectEditSyntheticFixtures.draft()
        draft.preserved["journeyRules"] = .string(#"{"schemaVersion":1,"thoughts":[{"key":"first","name":"First","need":120}]}"#)
        var voice = ProjectEditBlock(kind: .voice, content: "Keep e\u{301}"); voice.id = "voice"
        voice.sourceFields = ["who": .string("规矩"), "futureBlock": .string("e\u{301}"),
            "when": .object(["op": .string("HAS_TAG"), "value": .string("unknown.old"), "futureCondition": .string("e\u{301}")])]
        draft.chapters[0].blocks = [voice]; return draft
    }
    private func target(_ draft: ProjectEditDraft) throws -> ProjectStoryConditionChoice.Target {
        try .init(draft: draft, chapterID: draft.chapters[0].id, blockID: "voice")
    }
    func testChangesOnlyValuePreservesUnknownFieldsAndExactNoOp() throws {
        let original = draft(), captured = try target(original)
        let choice = try XCTUnwrap(ProjectEndingConditionChoices.choices(in: original, operation: "HAS_TAG").first)
        let next = try ProjectStoryConditionChoice.applying(choice, to: original, target: captured)
        var expected = original; var condition = expected.chapters[0].blocks![0].sourceFields!["when"]!.object!
        condition["value"] = .string("thought.first.done"); expected.chapters[0].blocks![0].setField("when", .object(condition))
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(next), ProjectEditPendingMaterials.exactData(expected))
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(try ProjectStoryConditionChoice.applying(choice, to: next, target: target(next))), ProjectEditPendingMaterials.exactData(next))
    }
    func testOnlyExistingVoiceHAS_TAGPredicateIsEligible() throws {
        for kind in [ProjectEditBlock.Kind.text, .thought, .audio] {
            var value = draft(); value.chapters[0].blocks![0].kind = kind; XCTAssertThrowsError(try target(value))
        }
        for condition in [ProjectEditJSON.null, .string("legacy"), .object(["op": .string("UNKNOWN"), "future": .string("retain")])] {
            var value = draft(); value.chapters[0].blocks![0].setField("when", condition); XCTAssertThrowsError(try target(value))
        }
        var value = draft(); value.chapters[0].blocks![0].setField("when", nil); XCTAssertThrowsError(try target(value))
        value = draft(); value.product = .freeExplore; XCTAssertThrowsError(try target(value))
    }
    func testUniqueExactChapterAndBlockIDsRequired() throws {
        var value = draft(); value.chapters.append(value.chapters[0]); XCTAssertThrowsError(try target(value))
        value = draft(); value.chapters[0].blocks!.append(value.chapters[0].blocks![0]); XCTAssertThrowsError(try target(value))
        value = draft(); value.chapters[0].blocks![0].id = "e\u{301}"
        XCTAssertThrowsError(try ProjectStoryConditionChoice.Target(draft: value, chapterID: value.chapters[0].id, blockID: "é"))
    }
    func testRemovedSourceOrEditedBlockRejectsCapturedChoice() throws {
        let original = draft(), captured = try target(original), choice = try XCTUnwrap(ProjectEndingConditionChoices.choices(in: original, operation: "HAS_TAG").first)
        var changed = original; changed.preserved["journeyRules"] = .string("{}")
        XCTAssertThrowsError(try ProjectStoryConditionChoice.applying(choice, to: changed, target: captured))
        changed = original; changed.chapters[0].blocks![0].content = "changed"
        XCTAssertThrowsError(try ProjectStoryConditionChoice.applying(choice, to: changed, target: captured))
        changed = original; changed.chapters[0].blocks = []
        XCTAssertThrowsError(try ProjectStoryConditionChoice.applying(choice, to: changed, target: captured))
    }
}

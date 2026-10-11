import XCTest
@testable import QuestifyCore

final class TemplateQAAnswerSelectionTests: XCTestCase {
    private func fixture(_ correct: [Bool] = [true, false, false], multiple: Bool = false) -> TemplateAdvancedDraft {
        var draft = TemplateAdvancedDraft()
        draft.setCreatorEnabled(.qa, true); draft.set("qa", "mode", .string("PICK"))
        draft.set("qa", "title", .string("Pick the answer")); draft.set("qa", "multi", .bool(multiple))
        draft.set("qa", "options", .array(correct.enumerated().map { index, selected in
            .object(["id": .string("opt_\(index + 1)"), "label": .string("Option \(index + 1)"),
                     "fb": .string("Feedback \(index + 1)"), "correct": .bool(selected), "effects": .array([])])
        }))
        return draft
    }
    private func flags(_ draft: TemplateAdvancedDraft) -> [Bool] { draft.rows("qa", "options").map { $0.object?["correct"]?.bool ?? false } }
    private func edit(_ action: TemplateQAAnswerSelection.Edit, _ draft: TemplateAdvancedDraft) throws -> TemplateAdvancedDraft {
        try XCTUnwrap(TemplateQAAnswerSelection(draft).applying(action, to: draft))
    }
    func testSingleChoiceSelectsExactlyOneAndCannotUncheckItself() throws {
        let first = fixture(), selected = try edit(.choose(2), first)
        XCTAssertEqual(flags(selected), [false, false, true])
        XCTAssertEqual(try edit(.choose(2), selected), selected)
        XCTAssertEqual(flags(try edit(.choose(1), selected)), [false, true, false])
    }
    func testMultipleChoiceCanSelectAndUnselectIndependently() throws {
        var draft = try edit(.setMultiple(true), fixture())
        XCTAssertEqual(flags(draft), [true, false, false])
        draft = try edit(.choose(2), draft); XCTAssertEqual(flags(draft), [true, false, true])
        draft = try edit(.choose(0), draft); XCTAssertEqual(flags(draft), [false, false, true])
        draft = try edit(.choose(2), draft); XCTAssertEqual(flags(draft), [false, false, false])
        XCTAssertTrue(draft.creatorIssues(.qa).contains { $0.path == "options" && $0.code == "answer" })
    }
    func testTurningMultipleOffKeepsFirstCorrectWithoutInventingOne() throws {
        let reduced = try edit(.setMultiple(false), fixture([false, true, true, true], multiple: true))
        XCTAssertEqual(flags(reduced), [false, true, false, false]); XCTAssertFalse(TemplateQAAnswerSelection(reduced).isMultiple)
        let missing = try edit(.setMultiple(false), fixture([false, false], multiple: true))
        XCTAssertEqual(flags(missing), [false, false])
        XCTAssertTrue(missing.creatorIssues(.qa).contains { $0.code == "answer" })
    }
    func testOnlyAnswerFlagsChangeAndFutureFieldsRemainVerbatim() throws {
        var original = fixture()
        original.setCreatorValue(.qa, path: [.field("options"), .index(1), .field("effects")], entry: .array([
            .object(["op": .string("ADD_TAG"), "var": .string(""), "value": .string("tag.memo")])]))
        original.setCreatorValue(.qa, path: [.field("options"), .index(1), .field("future")], entry: .object(["keep": .string("e\u{301}")]))
        original.set("qa", "future", .string("do not trim \n")); original.set("timer", "enabled", .bool(true))
        let next = try edit(.choose(1), original)
        var expected = original
        for index in 0..<3 { expected.setCreatorValue(.qa, path: [.field("options"), .index(index), .field("correct")], entry: .bool(index == 1)) }
        XCTAssertEqual(next, expected)
        XCTAssertThrowsError(try next.serialize(), "Unknown fields still obey existing network validation")
    }
    func testOpeningDoesNotNormalizeMultipleCorrectLegacyData() {
        let draft = fixture([true, true, false]), before = draft
        let selection = TemplateQAAnswerSelection(draft)
        XCTAssertTrue(selection.canEdit); XCTAssertEqual(selection.options.map(\.correct), [true, true, false])
        XCTAssertEqual(draft, before)
    }
    func testChangedOrReorderedSnapshotsAndInvalidIndexesReject() {
        let original = fixture(), captured = TemplateQAAnswerSelection(original)
        var changed = original; var rows = changed.rows("qa", "options"); rows.swapAt(0, 1); changed.set("qa", "options", .array(rows))
        XCTAssertNil(captured.applying(.choose(0), to: changed))
        changed = original; changed.setCreatorValue(.qa, path: [.field("options"), .index(0), .field("label")], entry: .string("Renamed"))
        XCTAssertNil(captured.applying(.choose(0), to: changed))
        XCTAssertNil(captured.applying(.choose(-1), to: original)); XCTAssertNil(captured.applying(.choose(3), to: original))
    }
    func testCanonicallyEquivalentButByteDifferentLabelsRetireSnapshots() {
        var draft = fixture(); draft.setCreatorValue(.qa, path: [.field("options"), .index(0), .field("label")], entry: .string("é"))
        let captured = TemplateQAAnswerSelection(draft)
        draft.setCreatorValue(.qa, path: [.field("options"), .index(0), .field("label")], entry: .string("e\u{301}"))
        XCTAssertNil(captured.applying(.choose(1), to: draft))
    }
    func testDisabledOrOtherModesCannotChangeAnswers() {
        for mode in ["TYPE", "SHOT", "UNKNOWN"] {
            var draft = fixture(); draft.set("qa", "mode", .string(mode))
            XCTAssertNil(TemplateQAAnswerSelection(draft).applying(.setMultiple(true), to: draft))
        }
        var draft = fixture(); draft.setCreatorEnabled(.qa, false)
        XCTAssertNil(TemplateQAAnswerSelection(draft).applying(.choose(1), to: draft))
    }
    func testUnsupportedShapesRemainUnchanged() {
        let invalid: [TemplateAuthoringJSON] = [.string("legacy"), .array([.string("row")]), .array(Array(repeating: .object([:]), count: 5))]
        for value in invalid {
            var draft = fixture(); draft.set("qa", "options", value)
            let selection = TemplateQAAnswerSelection(draft)
            XCTAssertFalse(selection.isSupported); XCTAssertNil(selection.applying(.choose(0), to: draft))
        }
        var draft = fixture(); draft.setCreatorValue(.qa, path: [.field("options"), .index(0), .field("correct")], entry: .string("true"))
        XCTAssertFalse(TemplateQAAnswerSelection(draft).isSupported)
        draft = fixture(); draft.set("qa", "multi", .number(1)); XCTAssertFalse(TemplateQAAnswerSelection(draft).isSupported)
    }
    func testMissingCorrectFlagsAreFalseAndEmptyListsNeverCreateAnAnswer() throws {
        var draft = fixture([false, false]); draft.setCreatorValue(.qa, path: [.field("options"), .index(0), .field("correct")], entry: nil)
        XCTAssertEqual(TemplateQAAnswerSelection(draft).options.map(\.correct), [false, false])
        XCTAssertEqual(flags(try edit(.choose(1), draft)), [false, true])
        draft.set("qa", "options", .array([]))
        XCTAssertNil(TemplateQAAnswerSelection(draft).applying(.choose(0), to: draft))
        XCTAssertEqual(flags(try edit(.setMultiple(false), draft)), [])
    }
    func testExistingSerializationRestoreAndRehearsalUseConfiguredAnswers() throws {
        var draft = try edit(.setMultiple(true), fixture())
        draft = try edit(.choose(2), draft)
        XCTAssertTrue(draft.creatorIssues(.qa).isEmpty)
        let restored = try TemplateAdvancedDraft(raw: draft.serialize())
        XCTAssertEqual(flags(restored), [true, false, true]); XCTAssertTrue(TemplateQAAnswerSelection(restored).isMultiple)
        var rehearsal = TemplateCreatorRehearsal()
        rehearsal.evaluate(.qa, draft: restored, selected: ["opt_1", "opt_3"]); XCTAssertEqual(rehearsal.result, .matched)
        rehearsal.evaluate(.qa, draft: restored, selected: ["opt_1"]); XCTAssertEqual(rehearsal.result, .missed)
        let local = try JSONDecoder().decode(TemplateAdvancedDraft.self, from: JSONEncoder().encode(draft))
        XCTAssertEqual(local, draft)
    }
}

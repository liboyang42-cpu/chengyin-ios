import XCTest
@testable import QuestifyCore

final class TemplateBlindOptionsTests: XCTestCase {
    private func fixture(_ keys: [String] = ["A", "B"], answer: String = "A") -> TemplateAdvancedDraft {
        var draft = TemplateAdvancedDraft(); draft.setCreatorEnabled(.blindTaste, true)
        draft.set("blindTaste", "title", .string("Which tea?")); draft.set("blindTaste", "answerKey", .string(answer))
        draft.set("blindTaste", "options", .array(keys.map { .object(["key": .string($0), "label": .string("Tea " + $0)]) }))
        return draft
    }
    private func edit(_ edit: TemplateBlindOptions.Edit, _ draft: TemplateAdvancedDraft) throws -> TemplateAdvancedDraft {
        try XCTUnwrap(TemplateBlindOptions(draft).applying(edit, to: draft))
    }
    func testAddUsesFirstFreeLetterAndDoesNotChangeAnswer() throws {
        let original = fixture(["A", "C"], answer: "C"), next = try edit(.add, original)
        XCTAssertEqual(TemplateBlindOptions(next).rows.map(\.key), ["A", "C", "B"])
        XCTAssertEqual(next.text("blindTaste", "answerKey"), "C"); XCTAssertEqual(TemplateBlindOptions(next).rows.last?.label, "")
        let empty = try edit(.add, fixture([], answer: ""))
        XCTAssertEqual(TemplateBlindOptions(empty).rows.map(\.key), ["A"]); XCTAssertEqual(empty.text("blindTaste", "answerKey"), "")
    }
    func testMaximumSixOptionsAndCustomKeysDoNotCollide() throws {
        let full = fixture(["A", "B", "C", "D", "E", "F"])
        XCTAssertFalse(TemplateBlindOptions(full).canAdd); XCTAssertNil(TemplateBlindOptions(full).applying(.add, to: full))
        let custom = try edit(.add, fixture(["tea_1", "A", "C"]))
        XCTAssertEqual(TemplateBlindOptions(custom).rows.last?.key, "B")
    }
    func testSelectedKeyFollowsRenameWhileOtherKeyAndLabelDoNotChangeAnswer() throws {
        let original = fixture(), renamed = try edit(.updateKey(0, "green_tea"), original)
        XCTAssertEqual(renamed.text("blindTaste", "answerKey"), "green_tea")
        let other = try edit(.updateKey(1, "black_tea"), renamed)
        XCTAssertEqual(other.text("blindTaste", "answerKey"), "green_tea")
        let label = try edit(.updateLabel(0, "Spring harvest"), other)
        XCTAssertEqual(label.text("blindTaste", "answerKey"), "green_tea"); XCTAssertEqual(TemplateBlindOptions(label).rows[0].label, "Spring harvest")
    }
    func testChooseUsesAnExistingUniqueValidKey() throws {
        let selected = try edit(.choose(1), fixture())
        XCTAssertEqual(selected.text("blindTaste", "answerKey"), "B")
        XCTAssertEqual(TemplateBlindOptions(selected).rows.map(\.isAnswer), [false, true])
        for keys in [["A", "A"], ["A", ""], ["A", "not a key"], ["A", "B\n"]] {
            let draft = fixture(keys)
            XCTAssertFalse(TemplateBlindOptions(draft).canChoose(1)); XCTAssertNil(TemplateBlindOptions(draft).applying(.choose(1), to: draft))
        }
    }
    func testDeleteSelectedFallsBackToFirstRemainingAndLastRemovalClearsAnswer() throws {
        let selected = fixture(["A", "B", "C"], answer: "C"), next = try edit(.remove(2), selected)
        XCTAssertEqual(next.text("blindTaste", "answerKey"), "A")
        let another = try edit(.remove(0), fixture(["A", "B", "C"], answer: "C"))
        XCTAssertEqual(another.text("blindTaste", "answerKey"), "C")
        let empty = try edit(.remove(0), fixture(["A"]))
        XCTAssertTrue(TemplateBlindOptions(empty).rows.isEmpty); XCTAssertEqual(empty.text("blindTaste", "answerKey"), "")
        XCTAssertFalse(empty.creatorIssues(.blindTaste).isEmpty)
    }
    func testMovingPreservesRowsAndSelectedIdentityWithoutChangingTheAnswerKey() throws {
        let original = fixture(["A", "B", "C"], answer: "C"), next = try edit(.move(2, 0), original)
        XCTAssertEqual(TemplateBlindOptions(next).rows.map(\.key), ["C", "A", "B"])
        XCTAssertEqual(next.text("blindTaste", "answerKey"), "C")
        XCTAssertEqual(TemplateBlindOptions(next).rows.map(\.isAnswer), [true, false, false])
        XCTAssertNil(TemplateBlindOptions(original).applying(.move(0, -1), to: original))
        XCTAssertNil(TemplateBlindOptions(original).applying(.move(2, 3), to: original))
    }
    func testExplicitEditsPreserveEveryUnrelatedFieldIncludingUnknowns() throws {
        var original = fixture()
        original.setCreatorValue(.blindTaste, path: [.field("options"), .index(0), .field("future")], entry: .object(["keep": .string("e\u{301}")]))
        original.set("blindTaste", "future", .number(9)); original.set("timer", "enabled", .bool(true))
        let next = try edit(.updateLabel(0, "New label"), original)
        var expected = original; expected.setCreatorValue(.blindTaste, path: [.field("options"), .index(0), .field("label")], entry: .string("New label"))
        XCTAssertEqual(next, expected); XCTAssertThrowsError(try next.serialize())
    }
    func testOpeningAndMissingAnswerNeverInventOrNormalizeData() {
        var draft = fixture(["A", "A"], answer: "missing")
        draft.setCreatorValue(.blindTaste, path: [.field("options"), .index(0), .field("label")], entry: .string("  old label \n"))
        let before = draft, projection = TemplateBlindOptions(draft)
        XCTAssertTrue(projection.canEdit); XCTAssertEqual(draft, before)
        XCTAssertFalse(projection.rows.contains(where: \.isAnswer)); XCTAssertEqual(projection.rows[0].label, "  old label \n")
    }
    func testMalformedShapesAndDisabledFamilyRefuseChanges() {
        let malformed: [TemplateAuthoringJSON] = [.string("legacy"), .array([.string("row")]), .array(Array(repeating: .object([:]), count: 7))]
        for value in malformed {
            var draft = fixture(); draft.set("blindTaste", "options", value)
            XCTAssertFalse(TemplateBlindOptions(draft).isSupported); XCTAssertNil(TemplateBlindOptions(draft).applying(.add, to: draft))
        }
        var draft = fixture(); draft.set("blindTaste", "answerKey", .number(1)); XCTAssertFalse(TemplateBlindOptions(draft).isSupported)
        draft = fixture(); draft.setCreatorEnabled(.blindTaste, false)
        XCTAssertNil(TemplateBlindOptions(draft).applying(.choose(1), to: draft))
    }
    func testStaleSnapshotsAndOutOfBoundsIndexesAreNoOps() {
        let draft = fixture(), snapshot = TemplateBlindOptions(draft)
        let invalid: [TemplateBlindOptions.Edit] = [.remove(-1), .choose(2), .updateKey(2, "C"), .updateLabel(-1, "bad")]
        for action in invalid {
            XCTAssertNil(snapshot.applying(action, to: draft))
        }
        var changed = draft; var rows = changed.rows("blindTaste", "options"); rows.swapAt(0, 1); changed.set("blindTaste", "options", .array(rows))
        XCTAssertNil(snapshot.applying(.remove(0), to: changed))
        changed = draft; changed.set("blindTaste", "title", .string("Changed question"))
        XCTAssertNil(snapshot.applying(.choose(1), to: changed))
    }
    func testMissingKeysCanBeEditedAndDuplicateKeysCanBeRepairedExplicitly() throws {
        var draft = fixture(["A", "A"])
        draft = try edit(.updateKey(1, "B"), draft)
        XCTAssertEqual(TemplateBlindOptions(draft).rows.map(\.key), ["A", "B"])
        XCTAssertTrue(TemplateBlindOptions(draft).canChoose(1))
        draft.setCreatorValue(.blindTaste, path: [.field("options"), .index(0), .field("key")], entry: nil)
        XCTAssertTrue(TemplateBlindOptions(draft).isSupported)
        draft = try edit(.updateKey(0, "C"), draft); XCTAssertEqual(TemplateBlindOptions(draft).rows[0].key, "C")
    }
    func testSerializationLocalRestoreAndExistingRehearsalShareTheChosenKey() throws {
        var draft = try edit(.updateKey(1, "oolong"), fixture())
        draft = try edit(.choose(1), draft)
        XCTAssertTrue(draft.creatorIssues(.blindTaste).isEmpty)
        let restored = try TemplateAdvancedDraft(raw: draft.serialize())
        XCTAssertEqual(restored.text("blindTaste", "answerKey"), "oolong")
        var rehearsal = TemplateCreatorRehearsal()
        rehearsal.evaluate(.blindTaste, draft: restored, selected: ["oolong"]); XCTAssertEqual(rehearsal.result, .matched)
        rehearsal.evaluate(.blindTaste, draft: restored, selected: ["A"]); XCTAssertEqual(rehearsal.result, .missed)
        let local = try JSONDecoder().decode(TemplateAdvancedDraft.self, from: JSONEncoder().encode(draft))
        XCTAssertEqual(local, draft)
    }
}

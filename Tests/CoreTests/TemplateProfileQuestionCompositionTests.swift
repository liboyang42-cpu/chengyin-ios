import XCTest
@testable import QuestifyCore

final class TemplateProfileQuestionCompositionTests: XCTestCase {
    private func fixture() -> TemplateAdvancedDraft {
        var draft = TemplateAdvancedDraft(); draft.setCreatorEnabled(.profile, true)
        draft.setCreatorValue(.profile, path: [.field("questions"), .index(0), .field("label")], entry: .string("Your name")); return draft
    }
    private func key(_ draft: TemplateAdvancedDraft, _ index: Int = 0) -> String { TemplateProfileQuestionComposition(draft).questions[index].key }
    private func edit(_ draft: TemplateAdvancedDraft, _ edit: TemplateProfileQuestionComposition.Edit) throws -> TemplateAdvancedDraft { try XCTUnwrap(TemplateProfileQuestionComposition(draft).applying(edit, to: draft)) }
    private func question(_ draft: TemplateAdvancedDraft, _ index: Int = 0) -> [String: TemplateAuthoringJSON] { draft.rows("profile", "questions")[index].object! }
    private func set(_ draft: inout TemplateAdvancedDraft, _ field: String, _ value: TemplateAuthoringJSON, index: Int = 0) { draft.setCreatorValue(.profile, path: [.field("questions"), .index(index), .field(field)], entry: value) }

    func testNewQuestionUsesSourceDefaultsAndFirstUnusedQNumber() throws {
        var draft = fixture(); set(&draft, "key", .string("q2")); draft = try edit(draft, .addQuestion)
        XCTAssertEqual(question(draft, 1), ["key": .string("q3"), "label": .string(""), "kind": .string("text"), "maxLength": .number(12), "required": .bool(true)])
    }
    func testQuestionCountsStayBetweenOneAndEight() throws {
        var draft = fixture(); XCTAssertNil(TemplateProfileQuestionComposition(draft).applying(.removeQuestions([0]), to: draft))
        for _ in 1..<8 { draft = try edit(draft, .addQuestion) }
        XCTAssertFalse(TemplateProfileQuestionComposition(draft).canAddQuestion); XCTAssertNil(TemplateProfileQuestionComposition(draft).applying(.addQuestion, to: draft))
        draft = try edit(draft, .removeQuestions([1, 2, 3, 4, 5, 6, 7])); XCTAssertEqual(TemplateProfileQuestionComposition(draft).questions.count, 1)
    }
    func testPickTransitionSeedsTwoChoicesAndMarksRequired() throws {
        var draft = fixture(); set(&draft, "required", .bool(false)); let changed = try edit(draft, .kind(key(draft), "pick"))
        XCTAssertEqual(question(changed)["kind"], .string("pick")); XCTAssertEqual(question(changed)["required"], .bool(true))
        XCTAssertEqual(question(changed)["options"], .array(["A", "B"].map { .object(["key": .string($0), "label": .string(""), "effects": .array([])]) }))
    }
    func testGlobalKeyAllocationIncludesRetainedTextQuestionOptions() throws {
        var draft = try edit(fixture(), .kind(key(fixture()), "pick")); let firstKey = key(draft)
        draft = try edit(draft, .kind(firstKey, "text")); draft = try edit(draft, .addQuestion)
        draft = try edit(draft, .kind(key(draft, 1), "pick"))
        XCTAssertEqual(TemplateProfileQuestionComposition(draft).questions[1].options.map(\.key), ["C", "D"])
        draft = try edit(draft, .addOption(key(draft, 1))); XCTAssertEqual(TemplateProfileQuestionComposition(draft).questions[1].options.last?.key, "E")
        XCTAssertEqual(TemplateProfileQuestionComposition(draft).questions[0].options.map(\.key), ["A", "B"])
    }
    func testKeyAllocatorContinuesAfterAlphabetAndFillsHoles() {
        let keys = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init) + ["opt1", "opt2", "opt3", "opt4"]
        var draft = fixture()
        let questions: [TemplateAuthoringJSON] = (0..<5).map { index in
            .object(["key": .string("q\(index + 1)"), "label": .string("Question"), "kind": .string("text"), "options": .array(keys[(index * 6)..<(index * 6 + 6)].map { .object(["key": .string($0), "label": .string("Choice")]) })])
        }
        draft.set("profile", "questions", .array(questions)); XCTAssertEqual(TemplateProfileQuestionComposition(draft).nextOptionKeys(2), ["opt5", "opt6"])
        draft.setCreatorValue(.profile, path: [.field("questions"), .index(0), .field("options"), .index(0), .field("key")], entry: .string("custom"))
        XCTAssertEqual(TemplateProfileQuestionComposition(draft).nextOptionKeys(2), ["A", "opt5"])
    }
    func testPickWithOneOldChoiceReplacesItUsingGloballyUnoccupiedKeys() throws {
        var draft = fixture(); set(&draft, "options", .array([.object(["key": .string("A"), "label": .string("Old one"), "effects": .array([])])]))
        draft = try edit(draft, .kind(key(draft), "pick"))
        XCTAssertEqual(TemplateProfileQuestionComposition(draft).questions[0].options.map(\.key), ["B", "C"])
    }
    func testRoundTripKindSwitchPreservesTwoOrMoreWholeOptionsAndEffects() throws {
        var draft = try edit(fixture(), .kind(key(fixture()), "pick"))
        draft.setCreatorValue(.profile, path: [.field("questions"), .index(0), .field("options"), .index(0), .field("effects")], entry: .array([.object(["op": .string("ADD_TAG"), "value": .string("tag.brave")])]))
        let options = question(draft)["options"]; draft = try edit(draft, .kind(key(draft), "text")); draft = try edit(draft, .kind(key(draft), "pick"))
        XCTAssertEqual(question(draft)["options"], options)
    }
    func testOptionCountLimitsAndBatchRemovalPreserveMinimumTwo() throws {
        var draft = try edit(fixture(), .kind(key(fixture()), "pick"))
        XCTAssertNil(TemplateProfileQuestionComposition(draft).applying(.removeOptions(key(draft), [0]), to: draft))
        for _ in 2..<6 { draft = try edit(draft, .addOption(key(draft))) }
        XCTAssertNil(TemplateProfileQuestionComposition(draft).applying(.addOption(key(draft)), to: draft))
        XCTAssertNil(TemplateProfileQuestionComposition(draft).applying(.removeOptions(key(draft), [0, 1, 2, 3, 4]), to: draft))
        draft = try edit(draft, .removeOptions(key(draft), [1, 2, 3, 4])); XCTAssertEqual(TemplateProfileQuestionComposition(draft).questions[0].options.map(\.key), ["A", "F"])
    }
    func testMovePreservesWholeQuestionAndOptionRows() throws {
        var draft = try edit(fixture(), .kind(key(fixture()), "pick")); draft = try edit(draft, .addOption(key(draft)))
        let options = question(draft)["options"]!.array!
        draft = try edit(draft, .moveOptions(key(draft), [0, 1], 3)); XCTAssertEqual(question(draft)["options"], .array([options[2], options[0], options[1]]))
        draft = try edit(draft, .addQuestion); let before = draft.rows("profile", "questions")
        draft = try edit(draft, .moveQuestions([0], 2)); XCTAssertEqual(draft.rows("profile", "questions"), [before[1], before[0]])
    }
    func testUnknownFieldsAndOverrideReferencesArePreservedWithoutRepair() throws {
        var draft = try edit(fixture(), .kind(key(fixture()), "pick")); draft = try edit(draft, .addOption(key(draft)))
        set(&draft, "future", .string("keep")); set(&draft, "override", .object(["option": .string("C"), "voice": .string("Keep"), "requires": .array([])]))
        let before = question(draft); draft = try edit(draft, .removeOptions(key(draft), [2]))
        XCTAssertEqual(question(draft)["future"], before["future"]); XCTAssertEqual(question(draft)["override"], before["override"])
        XCTAssertFalse(draft.creatorIssues(.profile).isEmpty)
    }
    func testMalformedInactiveAndStaleScopesDoNotWrite() throws {
        let draft = fixture(), snapshot = TemplateProfileQuestionComposition(draft)
        var changed = draft; changed.set("profile", "title", .string("Changed")); XCTAssertNil(snapshot.applying(.addQuestion, to: changed))
        changed = draft; changed.setCreatorEnabled(.profile, false); XCTAssertFalse(TemplateProfileQuestionComposition(changed).canEdit)
        changed = draft; changed.set("profile", "questions", .array([.string("legacy")])); XCTAssertFalse(TemplateProfileQuestionComposition(changed).isSupported)
        XCTAssertNil(snapshot.applying(.removeQuestions([-1]), to: draft)); XCTAssertNil(snapshot.applying(.moveQuestions([0, 0], 1), to: draft))
    }
    func testValidConfiguredQuestionsSerializeAndLocalDraftRestores() throws {
        var draft = try edit(fixture(), .kind(key(fixture()), "pick"))
        for index in 0..<2 { draft.setCreatorValue(.profile, path: [.field("questions"), .index(0), .field("options"), .index(index), .field("label")], entry: .string("Choice \(index)")) }
        XCTAssertTrue(draft.creatorIssues(.profile).isEmpty)
        let normalized = try TemplateAdvancedDraft(raw: draft.serialize()); XCTAssertEqual(TemplateProfileQuestionComposition(normalized).questions[0].options.map(\.key), ["A", "B"])
        var local = TemplateAuthoringDraft(title: "Questions"); local.advanced = draft
        XCTAssertEqual(try JSONDecoder().decode(TemplateAuthoringDraft.self, from: JSONEncoder().encode(local)), local)
    }
}

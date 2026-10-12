import XCTest
@testable import QuestifyCore

final class TemplateLegacyQuestionRehearsalTests: XCTestCase {
    private func text(_ answer: String = "Orange、柑橘, citrus；tangerine") -> TemplateAuthoringDraft {
        var draft = TemplateAuthoringDraft(title: "Question"); draft.validationMethod = .text; draft.questionName = "What fruit?"; draft.questionAnswer = answer; draft.hint1 = "It is orange"; draft.answerReveal = "An orange"; draft.legacyHintsEnabled = true; return draft
    }
    private func choice() -> TemplateAuthoringDraft {
        var draft = text(); draft.validationMethod = .choice; draft.questionA = "Apple"; draft.questionB = "Orange"; draft.correctAnswer = "B"; return draft
    }
    func testTextAliasesUseSourcePunctuationTrimAndCase() {
        for answer in [" orange ", "柑橘", "CITRUS", "tangerine"] { var value = TemplateLegacyQuestionRehearsal(text()); value.setAnswer(answer); XCTAssertTrue(value.submit(), answer); XCTAssertEqual(value.state, .completed) }
    }
    func testWrongRetryClearsErrorButKeepsShownHint() {
        var value = TemplateLegacyQuestionRehearsal(text()); value.setAnswer("apple"); XCTAssertFalse(value.submit()); XCTAssertEqual(value.state, .wrong)
        value.revealHint(); XCTAssertTrue(value.hintRevealed); XCTAssertEqual(value.state, .wrong)
        value.setAnswer("orange"); XCTAssertEqual(value.state, .ready); XCTAssertTrue(value.hintRevealed); XCTAssertTrue(value.submit())
    }
    func testCanonicalUnicodeFormsRemainDistinctLikeJavaScriptIncludes() {
        var value = TemplateLegacyQuestionRehearsal(text("\u{00E9}")); value.setAnswer("e\u{0301}"); XCTAssertFalse(value.submit())
        value.setAnswer("\u{00C9}"); XCTAssertTrue(value.submit())
    }
    func testECMAScriptWhitespaceIncludesBOMButNotNELOrZeroWidthSpace() {
        var value = TemplateLegacyQuestionRehearsal(text("one\u{FEFF}two\u{3000}three")); value.setAnswer("\u{FEFF} TWO \u{FEFF}"); XCTAssertTrue(value.submit())
        value = .init(text("one\u{0085}two")); value.setAnswer("two"); XCTAssertFalse(value.submit()); value.setAnswer("one\u{0085}two"); XCTAssertTrue(value.submit())
        value = .init(text("orange")); value.setAnswer("\u{200B}orange"); XCTAssertFalse(value.submit())
    }
    func testEmptyConfigurationBlockedButDelimiterOnlyFollowsSourceAnyNonemptyRule() {
        var value = TemplateLegacyQuestionRehearsal(text("")); XCTAssertFalse(value.isConfigured); value.setAnswer("anything"); XCTAssertFalse(value.submit())
        value = .init(text("； 、, ")); XCTAssertTrue(value.isConfigured); XCTAssertTrue(value.acceptsAnyNonemptyAnswer)
        value.setAnswer("  "); XCTAssertFalse(value.submit()); value.setAnswer("anything"); XCTAssertTrue(value.submit())
    }
    func testChoiceRequiresSelectionAndExactCorrectLetterWithoutToggleOff() {
        var value = TemplateLegacyQuestionRehearsal(choice()); XCTAssertFalse(value.submit()); value.select(.a); XCTAssertEqual(value.state, .ready); XCTAssertFalse(value.submit())
        value.select(.b); value.select(.b); XCTAssertEqual(value.selected, .b); XCTAssertTrue(value.submit()); XCTAssertEqual(value.state, .completed)
    }
    func testNativeTwoToFourRowsKeepLetterIdentityWithDuplicateLabels() {
        var draft = choice(); draft.questionC = "Orange"; draft.questionD = "Orange"; draft.correctAnswer = "D"
        var value = TemplateLegacyQuestionRehearsal(draft); XCTAssertEqual(value.options.map(\.letter), [.a, .b, .c, .d]); value.select(.b); XCTAssertFalse(value.submit()); value.select(.d); XCTAssertTrue(value.submit())
        value = .init(choice()); value.select(.d); XCTAssertNil(value.selected)
    }
    func testMissingQuestionChoicesAnswerAndMalformedMediaCannotComplete() {
        var drafts = [text(), choice(), choice(), choice(), choice()]
        drafts[0].questionName = ""; drafts[1].questionB = ""; drafts[2].correctAnswer = "C"; drafts[3].correctAnswer = "unknown"; drafts[4].questionOptionMediaJson = "[]"
        for draft in drafts { var value = TemplateLegacyQuestionRehearsal(draft); XCTAssertFalse(value.isConfigured); value.setAnswer("Orange"); value.select(.b); XCTAssertFalse(value.submit()); XCTAssertNotEqual(value.state, .completed) }
    }
    func testAdvancedPrimaryAndOtherMethodsExcludedButTimerDoesNotReplaceLegacyQuestion() {
        var draft = text(); draft.advanced.setCreatorEnabled(.qa, true); XCTAssertFalse(TemplateLegacyQuestionRehearsal(draft).isAvailable)
        draft = text(); draft.advanced.set("timer", "enabled", .bool(true)); XCTAssertTrue(TemplateLegacyQuestionRehearsal(draft).isAvailable)
        for method in [TemplateAuthoringMethod.manual, .photo, .gps, .scan, .preference, .sensor] { draft = text(); draft.validationMethod = method; XCTAssertFalse(TemplateLegacyQuestionRehearsal(draft).isAvailable) }
        draft = text(); draft.finishEnabled = false; XCTAssertFalse(TemplateLegacyQuestionRehearsal(draft).isAvailable)
    }
    func testHintUsesFirstThenRevealAndHonorsExplicitDisable() {
        var draft = text(), value = TemplateLegacyQuestionRehearsal(draft); XCTAssertEqual(value.hint, "It is orange"); value.revealHint(); XCTAssertTrue(value.hintRevealed)
        draft.hint1 = ""; value = .init(draft); XCTAssertEqual(value.hint, "An orange")
        draft.legacyHintsEnabled = false; value = .init(draft); XCTAssertNil(value.hint); XCTAssertFalse(value.canRevealHint)
    }
    func testHintTwoAloneIsNotExposedAndWhitespaceHintUsesSourceTruthiness() {
        var draft = text(); draft.hint1 = ""; draft.answerReveal = ""; draft.hint2 = "Second only"; draft.legacyHintsEnabled = nil
        XCTAssertNil(TemplateLegacyQuestionRehearsal(draft).hint)
        draft.hint1 = " "; XCTAssertEqual(TemplateLegacyQuestionRehearsal(draft).hint, " ")
    }
    func testRestartResetsAllEphemeralStateAndCompletionStopsFurtherInput() {
        var value = TemplateLegacyQuestionRehearsal(text()); value.revealHint(); value.setAnswer("orange"); XCTAssertTrue(value.submit()); value.setAnswer("wrong"); XCTAssertEqual(value.answer, ""); XCTAssertFalse(value.hintRevealed)
        value.restart(); XCTAssertEqual(value.state, .ready); XCTAssertEqual(value.answer, ""); XCTAssertNil(value.selected); XCTAssertFalse(value.hintRevealed); XCTAssertTrue(value.canAttempt)
    }
    func testExactSnapshotRejectsUnrelatedAndCanonicalSourceChanges() {
        var draft = text(); draft.title = "\u{00E9}"; let value = TemplateLegacyQuestionRehearsal(draft)
        draft.title = "e\u{0301}"; XCTAssertFalse(value.isCurrent(draft)); draft = text(); XCTAssertFalse(value.isCurrent(draft))
    }
    func testOpeningAndRehearsalNeverAlterStoredDraftOrLocalJSON() throws {
        let draft = choice(), encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let before = try encoder.encode(draft); var value = TemplateLegacyQuestionRehearsal(draft)
        value.select(.a); value.revealHint(); value.submit(); value.select(.b); value.submit(); value.restart()
        XCTAssertEqual(try encoder.encode(draft), before); XCTAssertEqual(try JSONDecoder().decode(TemplateAuthoringDraft.self, from: before), draft); XCTAssertTrue(value.isCurrent(draft))
    }
}

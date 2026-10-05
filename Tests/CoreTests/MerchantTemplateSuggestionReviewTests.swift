import XCTest
@testable import QuestifyCore

final class MerchantTemplateSuggestionReviewTests: XCTestCase {
    private func result() throws -> MerchantTemplateAssistResult {
        try .init(.object(["trace": .string("wrapper-preserved"), "template": .object([
            "title": .string("Generated"), "description": .string("Generated description"),
            "questionName": .string("Which sign?"), "optionA": .string("Lantern"), "optionB": .string("Clock"),
            "correctAnswer": .string("a"), "validationMethod": .number(3),
            "futureField": .object(["keep": .bool(true)]), "medalName": .string("No destination")])]))
    }
    private func action(_ review: MerchantTemplateSuggestionReview, _ field: MerchantTemplateAssistField) throws -> MerchantTemplateSuggestionReview.Action {
        review.action(for: try XCTUnwrap(review.suggestions.first { $0.field == field }))
    }
    private func commit(_ field: MerchantTemplateAssistField, _ change: MerchantTemplateSuggestionReview.Change = .accept,
                        review: inout MerchantTemplateSuggestionReview, draft: inout MerchantNodeTemplate,
                        edits: inout MerchantTemplateAssistEdits) throws {
        let action = try action(review, field)
        let next = try XCTUnwrap(review.proposedDraft(action, change: change, current: draft, edits: edits))
        edits.record(from: draft, to: next); draft = next; review.recordCommit(action, change: change, edits: edits)
    }
    func testFullDecodedWrapperAndUnsupportedFieldsArePreserved() throws {
        let value = try result()
        XCTAssertEqual(value.response.object?["trace"], .string("wrapper-preserved"))
        XCTAssertEqual(value.raw["futureField"], .object(["keep": .bool(true)]))
        XCTAssertTrue(value.unsupportedKeys.contains("futureField")); XCTAssertTrue(value.unsupportedKeys.contains("medalName"))
        let review = MerchantTemplateSuggestionReview(result: value, captured: .init(), edits: .init())
        XCTAssertEqual(review.result.response, value.response)
        XCTAssertFalse(review.suggestions.contains { $0.field.rawValue == "medalName" })
    }
    func testExplicitAcceptanceChangesOnlyOneFieldAndPreservesUnrelatedData() throws {
        var draft = MerchantNodeTemplate(); draft.feedbackText = "  Preserve\n"; draft.couponID = 19
        var edits = MerchantTemplateAssistEdits(), review = MerchantTemplateSuggestionReview(result: try result(), captured: draft, edits: edits)
        try commit(.title, review: &review, draft: &draft, edits: &edits)
        XCTAssertEqual(draft.title, "Generated"); XCTAssertEqual(draft.questionName, ""); XCTAssertNil(draft.method)
        XCTAssertEqual(Array(draft.feedbackText.utf8), Array("  Preserve\n".utf8)); XCTAssertEqual(draft.couponID, 19)
        XCTAssertNil(draft.fields["medalName"]); XCTAssertNil(draft.fields["futureField"])
    }
    func testOriginalWhitespaceIsRestoredExactlyByUndoAndReacceptIsExplicit() throws {
        var draft = MerchantNodeTemplate(); draft.title = " \r\n\t"
        var edits = MerchantTemplateAssistEdits(), review = MerchantTemplateSuggestionReview(result: try result(), captured: draft, edits: edits)
        let action = try action(review, .title)
        XCTAssertEqual(review.suggestion(for: action)?.original, " \r\n\t")
        try commit(.title, review: &review, draft: &draft, edits: &edits)
        XCTAssertEqual(review.suggestions.first { $0.field == .title }?.state, .applied)
        try commit(.title, .undo, review: &review, draft: &draft, edits: &edits)
        XCTAssertEqual(Array(draft.title.utf8), Array(" \r\n\t".utf8)); XCTAssertEqual(review.suggestions.first { $0.field == .title }?.state, .undone)
        try commit(.title, review: &review, draft: &draft, edits: &edits)
        XCTAssertEqual(draft.title, "Generated")
    }
    func testRejectIsTerminalAndCannotTriggerAcceptance() throws {
        let draft = MerchantNodeTemplate(); var review = MerchantTemplateSuggestionReview(result: try result(), captured: draft, edits: .init())
        let action = try action(review, .title)
        XCTAssertTrue(review.reject(action)); XCTAssertEqual(review.suggestions.first { $0.field == .title }?.state, .rejected)
        XCTAssertFalse(review.reject(action)); XCTAssertNil(review.proposedDraft(action, change: .accept, current: draft, edits: .init()))
        XCTAssertEqual(draft.title, "")
    }
    func testExistingNonemptyOriginalCannotBeReplaced() throws {
        var draft = MerchantNodeTemplate(); draft.title = "My title"
        let review = MerchantTemplateSuggestionReview(result: try result(), captured: draft, edits: .init())
        XCTAssertEqual(review.suggestions.first { $0.field == .title }?.original, "My title")
        XCTAssertNil(review.proposedDraft(try action(review, .title), change: .accept, current: draft, edits: .init()))
    }
    func testIntentionalClearAndABAEditsRemainProtected() throws {
        var draft = MerchantNodeTemplate(), edits = MerchantTemplateAssistEdits()
        let captured = draft, review = MerchantTemplateSuggestionReview(result: try result(), captured: draft, edits: edits)
        draft.title = "Manual"; edits.record(from: captured, to: draft)
        let manual = draft; draft.title = ""; edits.record(from: manual, to: draft)
        XCTAssertNil(review.proposedDraft(try action(review, .title), change: .accept, current: draft, edits: edits))
        XCTAssertNotNil(review.proposedDraft(try action(review, .description), change: .accept, current: draft, edits: edits))
    }
    func testCanonicalUnicodeEditStillChangesRevisionAndBlocksUndo() throws {
        let response = try MerchantTemplateAssistResult(.object(["title": .string("é"), "questionName": .string("Question")]))
        var draft = MerchantNodeTemplate(), edits = MerchantTemplateAssistEdits()
        var review = MerchantTemplateSuggestionReview(result: response, captured: draft, edits: edits)
        try commit(.title, review: &review, draft: &draft, edits: &edits)
        let before = draft; draft.title = "e\u{301}"; edits.record(from: before, to: draft)
        XCTAssertNil(review.proposedDraft(try action(review, .title), change: .undo, current: draft, edits: edits))
        XCTAssertEqual(Array(draft.title.utf8), [101, 204, 129])
    }
    func testUndoCannotOverwriteManualChangesAfterAcceptance() throws {
        var draft = MerchantNodeTemplate(), edits = MerchantTemplateAssistEdits()
        var review = MerchantTemplateSuggestionReview(result: try result(), captured: draft, edits: edits)
        try commit(.title, review: &review, draft: &draft, edits: &edits)
        let before = draft; draft.title = "Mine now"; edits.record(from: before, to: draft)
        XCTAssertNil(review.proposedDraft(try action(review, .title), change: .undo, current: draft, edits: edits))
    }
    func testAnswerRequiresExplicitQuestionOptionsAndMethodAcceptances() throws {
        var draft = MerchantNodeTemplate(), edits = MerchantTemplateAssistEdits()
        var review = MerchantTemplateSuggestionReview(result: try result(), captured: draft, edits: edits)
        let answer = try action(review, .correctAnswer)
        for field: MerchantTemplateAssistField in [.questionName, .optionA, .optionB, .validationMethod] {
            XCTAssertNil(review.proposedDraft(answer, change: .accept, current: draft, edits: edits))
            try commit(field, review: &review, draft: &draft, edits: &edits)
        }
        try commit(.correctAnswer, review: &review, draft: &draft, edits: &edits)
        XCTAssertEqual(draft.correctAnswer, "A")
    }
    func testChangedUnselectedOptionAlsoBlocksGeneratedAnswer() throws {
        var draft = MerchantNodeTemplate(), edits = MerchantTemplateAssistEdits()
        var review = MerchantTemplateSuggestionReview(result: try result(), captured: draft, edits: edits)
        for field: MerchantTemplateAssistField in [.questionName, .optionA, .optionB, .validationMethod] { try commit(field, review: &review, draft: &draft, edits: &edits) }
        let before = draft; draft.optionB = "Manual non-answer"; edits.record(from: before, to: draft)
        XCTAssertNil(review.proposedDraft(try action(review, .correctAnswer), change: .accept, current: draft, edits: edits))
    }
    func testUndoAnswerBeforeUndoingItsQuestionDependencies() throws {
        var draft = MerchantNodeTemplate(), edits = MerchantTemplateAssistEdits()
        var review = MerchantTemplateSuggestionReview(result: try result(), captured: draft, edits: edits)
        for field: MerchantTemplateAssistField in [.questionName, .optionA, .optionB, .validationMethod, .correctAnswer] { try commit(field, review: &review, draft: &draft, edits: &edits) }
        XCTAssertNil(review.proposedDraft(try action(review, .optionA), change: .undo, current: draft, edits: edits))
        try commit(.correctAnswer, .undo, review: &review, draft: &draft, edits: &edits)
        try commit(.optionA, .undo, review: &review, draft: &draft, edits: &edits)
        XCTAssertEqual(draft.correctAnswer, ""); XCTAssertEqual(draft.optionA, "")
    }
    func testOldReviewActionCannotMutateOrRejectReplacementReview() throws {
        let draft = MerchantNodeTemplate(), result = try result()
        let old = MerchantTemplateSuggestionReview(result: result, captured: draft, edits: .init())
        var next = MerchantTemplateSuggestionReview(result: result, captured: draft, edits: .init())
        let action = try action(old, .title)
        XCTAssertFalse(next.reject(action)); XCTAssertNil(next.proposedDraft(action, change: .accept, current: draft, edits: .init()))
    }
    func testAcceptUndoReacceptNeverReviveAnOldRenderedAction() throws {
        var draft = MerchantNodeTemplate(), edits = MerchantTemplateAssistEdits()
        var review = MerchantTemplateSuggestionReview(result: try result(), captured: draft, edits: edits)
        let oldAccept = try action(review, .title)
        try commit(.title, review: &review, draft: &draft, edits: &edits)
        let oldUndo = try action(review, .title)
        try commit(.title, .undo, review: &review, draft: &draft, edits: &edits)
        XCTAssertNil(review.proposedDraft(oldAccept, change: .accept, current: draft, edits: edits))
        try commit(.title, review: &review, draft: &draft, edits: &edits)
        XCTAssertNil(review.proposedDraft(oldUndo, change: .undo, current: draft, edits: edits))
        XCTAssertEqual(draft.title, "Generated")
    }
    func testReplacementTemplateIdentityAndUnknownMethodAreNeverGuessed() throws {
        let draft = MerchantNodeTemplate(), result = try MerchantTemplateAssistResult(.object(["questionName": .string("Question"), "validationMethod": .number(99)]))
        let review = MerchantTemplateSuggestionReview(result: result, captured: draft, edits: .init())
        XCTAssertFalse(review.suggestions.contains { $0.field == .validationMethod })
        var replacement = draft; replacement.id = 99
        XCTAssertNil(review.proposedDraft(try action(review, .questionName), change: .accept, current: replacement, edits: .init()))
        XCTAssertTrue(result.unsupportedKeys.contains("validationMethod"))
    }
}

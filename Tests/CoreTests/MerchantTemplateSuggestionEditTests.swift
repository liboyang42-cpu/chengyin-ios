import XCTest
@testable import QuestifyCore

final class MerchantTemplateSuggestionEditTests: XCTestCase {
    private func result() throws -> MerchantTemplateAssistResult {
        try .init(.object(["template": .object(["title": .string("AI title"), "description": .string("AI description"),
            "feedbackText": .string("AI feedback"), "questionName": .string("Original question"),
            "optionA": .string("A"), "optionB": .string("B"), "correctAnswer": .string("A"), "validationMethod": .number(3)])]))
    }
    private func action(_ review: MerchantTemplateSuggestionReview, _ field: MerchantTemplateAssistField) throws -> MerchantTemplateSuggestionReview.Action {
        review.action(for: try XCTUnwrap(review.suggestions.first(where: { $0.field == field })))
    }
    func testOnlyThreeCopyFieldsAreEditable() throws {
        let draft = MerchantNodeTemplate(), edits = MerchantTemplateAssistEdits()
        let review = MerchantTemplateSuggestionReview(result: try result(), captured: draft, edits: edits)
        for suggestion in review.suggestions {
            let allowed = [MerchantTemplateAssistField.title, .description, .feedbackText].contains(suggestion.field)
            XCTAssertEqual(review.prepareCopyEdit(review.action(for: suggestion), current: draft, edits: edits) != nil, allowed)
        }
    }
    func testSavingEditedCopyPreservesAIOriginalAndNeverChangesTheDraftOrResponse() throws {
        let draft = MerchantNodeTemplate(), edits = MerchantTemplateAssistEdits(), result = try result()
        var review = MerchantTemplateSuggestionReview(result: result, captured: draft, edits: edits)
        let oldAction = try action(review, .title)
        var edit = try XCTUnwrap(review.prepareCopyEdit(oldAction, current: draft, edits: edits))
        edit.text = "My reviewed title"
        XCTAssertTrue(review.saveCopyEdit(edit, current: draft, edits: edits))
        let suggestion = try XCTUnwrap(review.suggestions.first(where: { $0.field == .title }))
        XCTAssertEqual(suggestion.generated, "AI title"); XCTAssertEqual(suggestion.proposed, "My reviewed title"); XCTAssertTrue(suggestion.isEdited)
        XCTAssertEqual(review.result.response, result.response); XCTAssertEqual(draft.title, "")
        XCTAssertNil(review.suggestion(for: oldAction)); XCTAssertFalse(review.reject(oldAction))
        XCTAssertFalse(review.saveCopyEdit(edit, current: draft, edits: edits))
    }
    func testNoOpWhitespaceOnlyAndInvalidTextDoNotRotateSuggestion() throws {
        let draft = MerchantNodeTemplate(), edits = MerchantTemplateAssistEdits()
        var review = MerchantTemplateSuggestionReview(result: try result(), captured: draft, edits: edits)
        let original = try action(review, .title)
        var edit = try XCTUnwrap(review.prepareCopyEdit(original, current: draft, edits: edits))
        for text in ["AI title", "  AI title\n", " ", "Bad\u{0000}text", String(repeating: "x", count: 16_385)] {
            edit.text = text; XCTAssertFalse(review.saveCopyEdit(edit, current: draft, edits: edits))
            XCTAssertNotNil(review.suggestion(for: original))
        }
    }
    func testMultilineTextAndUTF8CapacityAreExplicitLocalLimits() throws {
        let draft = MerchantNodeTemplate(), edits = MerchantTemplateAssistEdits()
        let review = MerchantTemplateSuggestionReview(result: try result(), captured: draft, edits: edits)
        var edit = try XCTUnwrap(review.prepareCopyEdit(try action(review, .description), current: draft, edits: edits))
        edit.text = "First paragraph\nSecond paragraph\tDetail"; XCTAssertNil(edit.issue)
        edit.text = String(repeating: "茶", count: 5_462); XCTAssertEqual(edit.issue, .tooLarge)
        edit.text = "A\u{0085}B"; XCTAssertEqual(edit.issue, .controls)
    }
    func testManualEditAndIntentionalClearProtectOriginalField() throws {
        var draft = MerchantNodeTemplate(), edits = MerchantTemplateAssistEdits()
        var review = MerchantTemplateSuggestionReview(result: try result(), captured: draft, edits: edits)
        var edit = try XCTUnwrap(review.prepareCopyEdit(try action(review, .title), current: draft, edits: edits)); edit.text = "Edited"
        let empty = draft; draft.title = "Manual"; edits.record(from: empty, to: draft)
        XCTAssertFalse(review.saveCopyEdit(edit, current: draft, edits: edits))
        let manual = draft; draft.title = ""; edits.record(from: manual, to: draft)
        XCTAssertFalse(review.saveCopyEdit(edit, current: draft, edits: edits))
        XCTAssertEqual(review.suggestions.first(where: { $0.field == .title })?.proposed, "AI title")
    }
    func testSeparateAcceptAndUndoUseHumanVersionWithoutOverwritingLaterEdits() throws {
        var draft = MerchantNodeTemplate(), edits = MerchantTemplateAssistEdits()
        var review = MerchantTemplateSuggestionReview(result: try result(), captured: draft, edits: edits)
        var edit = try XCTUnwrap(review.prepareCopyEdit(try action(review, .title), current: draft, edits: edits)); edit.text = "Human version"
        XCTAssertTrue(review.saveCopyEdit(edit, current: draft, edits: edits))
        let accept = try action(review, .title)
        let accepted = try XCTUnwrap(review.proposedDraft(accept, change: .accept, current: draft, edits: edits))
        edits.record(from: draft, to: accepted); draft = accepted; review.recordCommit(accept, change: .accept, edits: edits)
        XCTAssertEqual(draft.title, "Human version"); XCTAssertFalse(review.saveCopyEdit(edit, current: draft, edits: edits))
        let undo = try action(review, .title)
        let original = try XCTUnwrap(review.proposedDraft(undo, change: .undo, current: draft, edits: edits))
        edits.record(from: draft, to: original); draft = original; review.recordCommit(undo, change: .undo, edits: edits)
        XCTAssertEqual(draft.title, "")
        var revision = try XCTUnwrap(review.prepareCopyEdit(try action(review, .title), current: draft, edits: edits)); revision.text = "A second human version"
        XCTAssertTrue(review.saveCopyEdit(revision, current: draft, edits: edits))
        XCTAssertEqual(review.suggestions.first(where: { $0.field == .title })?.generated, "AI title")
    }
    func testOldEditorCannotChangeRejectedOrReplacementReview() throws {
        let draft = MerchantNodeTemplate(), edits = MerchantTemplateAssistEdits()
        var review = MerchantTemplateSuggestionReview(result: try result(), captured: draft, edits: edits)
        let captured = try action(review, .title)
        var edit = try XCTUnwrap(review.prepareCopyEdit(captured, current: draft, edits: edits)); edit.text = "Edited"
        XCTAssertTrue(review.reject(captured)); XCTAssertFalse(review.saveCopyEdit(edit, current: draft, edits: edits))
        var replacement = MerchantTemplateSuggestionReview(result: try result(), captured: draft, edits: edits)
        XCTAssertFalse(replacement.saveCopyEdit(edit, current: draft, edits: edits))
    }
    func testExistingNonemptyDraftCannotBeReplacedThroughSuggestionEditing() throws {
        var draft = MerchantNodeTemplate(); draft.title = "Original human title"
        let review = MerchantTemplateSuggestionReview(result: try result(), captured: draft, edits: .init())
        XCTAssertNil(review.prepareCopyEdit(try action(review, .title), current: draft, edits: .init()))
    }
}

@MainActor private final class EditableSuggestionClient: MerchantTemplateAssistServing {
    var session: PublishingSession? = .init(namespace: "synthetic", accountID: 901, epoch: UUID(), role: "merchant", region: .china)
    var canGenerate = true
    var calls = 0
    func generate(_ input: MerchantTemplateAssistInput) async throws -> MerchantTemplateAssistResult {
        calls += 1
        return try .init(.object(["title": .string("AI title"), "description": .string("AI description"), "feedbackText": .string("AI feedback"), "questionName": .string("Source question")]))
    }
    func cancel() {}
}
@MainActor final class MerchantTemplateSuggestionEditFlowTests: XCTestCase {
    private func setup() async -> (MerchantOperationsFixtureReader, MerchantOperationsCoordinator, EditableSuggestionClient, MerchantTemplateAssistFlow) {
        let reader = MerchantOperationsFixtureReader(), client = EditableSuggestionClient()
        let coordinator = MerchantOperationsCoordinator(reader: reader, destination: .template(nil)); await coordinator.load()
        let flow = MerchantTemplateAssistFlow(coordinator: coordinator, client: client)
        flow.shopName = "Synthetic shop"; flow.prompt = "A simple game"; await flow.generate()
        return (reader, coordinator, client, flow)
    }
    private func edit(_ flow: MerchantTemplateAssistFlow) throws -> MerchantTemplateSuggestionEdit {
        let review = try XCTUnwrap(flow.visibleReview), suggestion = try XCTUnwrap(flow.visibleReview?.suggestions.first(where: { $0.field == .title }))
        var value = try XCTUnwrap(flow.prepareSuggestionEdit(review.action(for: suggestion))); value.text = "Human title"; return value
    }
    func testSaveOnlyUpdatesSuggestionAndSeparateAcceptStillRefreshesPermission() async throws {
        let (reader, coordinator, client, flow) = await setup()
        let before = coordinator.draft, reads = reader.accessCount
        XCTAssertTrue(flow.saveSuggestionEdit(try edit(flow)))
        XCTAssertEqual(coordinator.draft, before); XCTAssertEqual(reader.accessCount, reads); XCTAssertEqual(reader.saveCount, 0); XCTAssertEqual(client.calls, 1)
        let review = try XCTUnwrap(flow.visibleReview), suggestion = try XCTUnwrap(flow.visibleReview?.suggestions.first(where: { $0.field == .title }))
        let accepted = await flow.change(review.action(for: suggestion), .accept)
        XCTAssertTrue(accepted); XCTAssertEqual(reader.accessCount, reads + 1); XCTAssertEqual(reader.saveCount, 0)
        guard case .template(let draft) = coordinator.draft else { return XCTFail() }; XCTAssertEqual(draft.title, "Human title")
    }
    func testPermissionRevocationBeforeAcceptPreservesOriginalDraft() async throws {
        let (reader, coordinator, _, flow) = await setup(); let before = coordinator.draft
        XCTAssertTrue(flow.saveSuggestionEdit(try edit(flow))); reader.denied = true
        let review = try XCTUnwrap(flow.visibleReview), suggestion = try XCTUnwrap(flow.visibleReview?.suggestions.first(where: { $0.field == .title }))
        let accepted = await flow.change(review.action(for: suggestion), .accept)
        XCTAssertFalse(accepted); XCTAssertEqual(coordinator.draft, before); XCTAssertEqual(flow.failure, .permission); XCTAssertEqual(reader.saveCount, 0)
    }
    func testCancelCloseSessionReplacementAndReloadRetireTheEditor() async throws {
        for variant in 0..<4 {
            let (reader, coordinator, client, flow) = await setup(); let edit = try edit(flow), before = coordinator.draft
            if variant == 0 { flow.cancel() }
            else if variant == 1 { flow.close() }
            else if variant == 2 { client.session = nil }
            else { await coordinator.load() }
            XCTAssertFalse(flow.saveSuggestionEdit(edit)); XCTAssertEqual(coordinator.draft, before); XCTAssertEqual(reader.saveCount, 0)
        }
    }
    func testGenerationCannotReplaceAHumanEditedCurrentResult() async throws {
        let (_, _, client, flow) = await setup()
        XCTAssertTrue(flow.saveSuggestionEdit(try edit(flow))); XCTAssertFalse(flow.canGenerate)
        await flow.generate()
        XCTAssertEqual(client.calls, 1); XCTAssertEqual(flow.visibleReview?.suggestions.first(where: { $0.field == .title })?.proposed, "Human title")
    }
}

import XCTest
@testable import Questify

@MainActor final class TemplateLegacyQuestionRehearsalViewTests: XCTestCase {
    private final class Owner { var session: TemplateAuthoringSession?; init(_ value: TemplateAuthoringSession) { session = value } }
    private func setup(choice: Bool = false, store: TemplateAuthoringLocalStore? = nil) throws -> (TemplateAuthoringModel, TemplateLegacyQuestionRehearsalController, Owner) {
        let owner = Owner(try .init(accountID: 991, namespace: "legacy-question", epoch: 1, authorizationRevision: "member"))
        let model = TemplateAuthoringModel(coordinator: .init(store: store ?? .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { owner.session }))
        model.load(); model.draft.title = "Question"; model.draft.validationMethod = choice ? .choice : .text; model.draft.questionName = "Which fruit?"; model.draft.questionAnswer = "Orange、柑橘"
        if choice { model.draft.questionA = "Apple"; model.draft.questionB = "Orange"; model.draft.correctAnswer = "B" }
        model.draft.hint1 = "An orange fruit"; model.draft.answerReveal = "Orange"; model.draft.legacyHintsEnabled = true; model.changed()
        return (model, .init(model: model), owner)
    }
    func testTextWrongHintRetryCompleteAndRestartDoesNotWriteDraft() throws {
        let (model, editor, _) = try setup(), before = model.draft, revision = model.revision
        editor.answerInput().wrappedValue = "apple"; editor.submitAction()(); XCTAssertEqual(editor.state, .wrong)
        editor.hintAction()(); XCTAssertEqual(editor.visibleHint, "An orange fruit"); editor.answerInput().wrappedValue = " ORANGE "; XCTAssertEqual(editor.state, .ready)
        editor.submitAction()(); XCTAssertEqual(editor.state, .completed); editor.restartAction()(); XCTAssertEqual(editor.answerInput().wrappedValue, ""); XCTAssertNil(editor.visibleHint)
        XCTAssertEqual(model.draft, before); XCTAssertEqual(model.coordinator.draft, before); XCTAssertEqual(model.revision, revision)
    }
    func testChoiceSelectionStaysSelectedAndMatchesCorrectLetter() throws {
        let (model, editor, _) = try setup(choice: true), before = model.draft
        editor.submitAction()(); XCTAssertEqual(editor.state, .wrong); editor.selectAction(.a)(); XCTAssertEqual(editor.state, .ready); editor.submitAction()(); XCTAssertEqual(editor.state, .wrong)
        editor.selectAction(.b)(); editor.selectAction(.b)(); XCTAssertEqual(editor.selected, .b); editor.submitAction()(); XCTAssertEqual(editor.state, .completed); XCTAssertEqual(model.draft, before)
    }
    func testIncompleteLegacyQuestionCannotProduceCompletion() throws {
        let (model, editor, _) = try setup(); model.draft.questionAnswer = ""; model.changed(); editor.reload(); let before = model.draft
        XCTAssertFalse(editor.isConfigured); XCTAssertFalse(editor.canAttempt); editor.answerInput().wrappedValue = "Orange"; editor.submitAction()(); XCTAssertNotEqual(editor.state, .completed); XCTAssertEqual(model.draft, before)
    }
    func testCapturedSubmitAndHintCannotActAfterAnotherInput() throws {
        let (_, editor, _) = try setup(); let submit = editor.submitAction(), hint = editor.hintAction(); editor.answerInput().wrappedValue = "Orange"
        submit(); hint(); XCTAssertEqual(editor.state, .ready); XCTAssertNil(editor.visibleHint); editor.submitAction()(); XCTAssertEqual(editor.state, .completed)
    }
    func testRestartFencesOldInputSelectionAndDuplicateCallbacks() throws {
        let (_, editor, _) = try setup(), input = editor.answerInput(); input.wrappedValue = "Orange"; let submit = editor.submitAction(); editor.submitAction()(); let reset = editor.restartAction()
        reset(); input.wrappedValue = "stale"; submit(); reset(); XCTAssertEqual(editor.answerInput().wrappedValue, ""); XCTAssertEqual(editor.state, .ready)
        let (_, choice, _) = try setup(choice: true), oldSelect = choice.selectAction(.b); choice.restartAction()(); oldSelect(); XCTAssertNil(choice.selected)
    }
    func testParentReviewOnlyRefreshPreservesAttemptButRetiresOldAction() throws {
        let (model, editor, _) = try setup(), input = editor.answerInput(); input.wrappedValue = "Orange"; let submit = editor.submitAction(); model.changed()
        XCTAssertEqual(input.wrappedValue, "Orange"); XCTAssertFalse(editor.needsReload); submit(); XCTAssertEqual(editor.state, .ready); editor.submitAction()(); XCTAssertEqual(editor.state, .completed)
    }
    func testExternalDraftABARetiresAttemptAndRequiresExplicitReload() throws {
        let (model, editor, _) = try setup(), original = model.draft; editor.answerInput().wrappedValue = "Orange"; let submit = editor.submitAction()
        model.draft.questionAnswer = "Apple"; model.draft = original; submit(); XCTAssertTrue(editor.needsReload); XCTAssertFalse(editor.canRead); XCTAssertEqual(editor.question, ""); XCTAssertNil(editor.visibleHint)
        editor.reload(); XCTAssertTrue(editor.canAttempt); XCTAssertEqual(editor.answerInput().wrappedValue, ""); XCTAssertEqual(editor.state, .ready)
    }
    func testReloadUsesCurrentQuestionAndAnswerRatherThanDemoData() throws {
        let (model, editor, _) = try setup(); model.draft.questionName = "New question"; model.draft.questionAnswer = "blue"; model.changed(); editor.reload()
        XCTAssertEqual(editor.question, "New question"); editor.answerInput().wrappedValue = "Orange"; editor.submitAction()(); XCTAssertEqual(editor.state, .wrong)
        editor.answerInput().wrappedValue = "blue"; editor.submitAction()(); XCTAssertEqual(editor.state, .completed)
    }
    func testOwnerLoadRestoreDiscardLeaveAndBackgroundFencePrivatePreview() throws {
        for operation in ["load", "restore", "discard", "owner", "leave", "dismiss", "background"] {
            let (model, editor, owner) = try setup(); editor.hintAction()(); let input = editor.answerInput(), submit = editor.submitAction(), restart = editor.restartAction()
            switch operation {
            case "load": model.load()
            case "restore": model.restore()
            case "discard": model.discard()
            case "owner": owner.session = try .init(accountID: 992, namespace: "legacy-question", epoch: 2, authorizationRevision: "member")
            case "leave": model.leave()
            case "background": editor.suspend()
            default: editor.retire()
            }
            let before = model.draft; input.wrappedValue = "Orange"; submit(); restart(); XCTAssertEqual(model.draft, before, operation); XCTAssertFalse(editor.canRead, operation); XCTAssertEqual(editor.question, "", operation); XCTAssertNil(editor.visibleHint, operation)
        }
    }
    func testBusyABARetiresAttemptInsteadOfResumingOldCompletion() throws {
        let (model, editor, _) = try setup(); editor.answerInput().wrappedValue = "Orange"; let submit = editor.submitAction()
        model.busy = true; model.busy = false; submit(); XCTAssertTrue(editor.needsReload); XCTAssertFalse(editor.canAttempt); editor.reload(); XCTAssertEqual(editor.state, .ready); XCTAssertEqual(editor.answerInput().wrappedValue, "")
    }
    func testAdvancedQuestionContractIsNotOverriddenByLegacyRehearsal() throws {
        let (model, editor, _) = try setup(); model.draft.advanced.setCreatorEnabled(.qa, true); model.changed(); editor.reload(); let before = model.draft
        XCTAssertFalse(editor.canInteract); editor.answerInput().wrappedValue = "Orange"; editor.submitAction()(); XCTAssertNotEqual(editor.state, .completed); XCTAssertEqual(model.draft, before)
    }
    func testHintsRespectIntentAndSecondHintDoesNotBecomeFirst() throws {
        let (model, editor, _) = try setup(); model.draft.hint1 = ""; model.draft.answerReveal = ""; model.draft.hint2 = "Second"; model.changed(); editor.reload()
        XCTAssertFalse(editor.canRevealHint); editor.hintAction()(); XCTAssertNil(editor.visibleHint)
        model.draft.answerReveal = "Reveal"; model.draft.legacyHintsEnabled = false; model.changed(); editor.reload(); XCTAssertFalse(editor.canRevealHint)
    }
    func testExistingLocalRestoreSuppliesActualConfigurationWithoutStoringAttempt() throws {
        let store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage()), (model, editor, owner) = try setup(store: store), expected = model.draft
        model.save(); editor.answerInput().wrappedValue = "Orange"; editor.submitAction()(); editor.retire(); model.leave()
        let reopened = TemplateAuthoringModel(coordinator: .init(store: store, currentSession: { owner.session })); reopened.load(); reopened.restore(); let fresh = TemplateLegacyQuestionRehearsalController(model: reopened)
        XCTAssertEqual(reopened.draft, expected); XCTAssertEqual(fresh.question, expected.questionName); XCTAssertEqual(fresh.state, .ready); XCTAssertEqual(fresh.answerInput().wrappedValue, ""); XCTAssertFalse(reopened.coordinator.canSubmit)
    }
    func testPendingWriteLockPreventsRehearsalActions() throws {
        let (seedModel, _, owner) = try setup(), session = try XCTUnwrap(owner.session)
        let store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage()), identity = TemplateAuthoringIdentity(), seed = seedModel.draft
        try store.save(seed, session: session, identity: identity); try store.savePending(.init(operationID: UUID(), ownerKey: session.ownerKey, identity: identity, request: TemplateAuthoringContract.request(seed, intent: .saveDraft), createdAt: Date()), session: session)
        let model = TemplateAuthoringModel(coordinator: .init(store: store, currentSession: { session })); model.load(); model.draft = seed
        let editor = TemplateLegacyQuestionRehearsalController(model: model); editor.answerInput().wrappedValue = "Orange"; editor.submitAction()(); XCTAssertFalse(editor.canInteract); XCTAssertNotEqual(editor.state, .completed); XCTAssertEqual(model.draft, seed)
    }
}

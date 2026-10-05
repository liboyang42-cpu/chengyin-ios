import XCTest
@testable import Questify

/// Cross-feature lifecycle coverage for the integrated rule, story, and legacy-hint editors.
/// Authored here; execution requires the Apple app-unit test host.
@MainActor final class TemplateEditorIntegrationTests: XCTestCase {
    private func owner(_ epoch: UInt64 = 1) throws -> TemplateAuthoringSession {
        try .init(accountID: 908, namespace: "template-editor-integration", epoch: epoch, authorizationRevision: "member")
    }
    private func seed() -> TemplateAuthoringDraft {
        var draft = TemplateAuthoringDraft(title: "Combined local editors")
        draft.validationMethod = .text; draft.ruleInstructions = " First \n Second "
        draft.hint1 = "first hint"; draft.hint2 = "second hint"; draft.answerReveal = "answer"
        draft.storyEnabled = true; draft.storyText = "independent historical summary"
        draft.storyJson = " [ {\"text\":\"  original scene  \", \"tag\":\"\", \"imgs\":[]} ]\n"
        return draft
    }
    func testSameOwnerReloadPreservesAllEditsAndInvalidatesAllRetainedBindings() throws {
        let session = try owner(), store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage())
        let coordinator = TemplateAuthoringCoordinator(store: store, currentSession: { session })
        coordinator.open(seed: seed()); let model = TemplateAuthoringModel(coordinator: coordinator); model.load()
        let editor = TemplateStoryEditor(model: model)
        let rule = model.ruleStep(try XCTUnwrap(model.ruleSteps.rows.first?.id))
        let story = editor.text(try XCTUnwrap(editor.beats.first?.id), \.text)
        model.legacyHintToggle().wrappedValue = true
        let hint = model.legacyHint(.hint1)
        rule.wrappedValue = "Changed rule"; story.wrappedValue = "  Changed scene  "; hint.wrappedValue = "Changed hint"
        let expected = model.draft
        XCTAssertEqual(coordinator.draft, expected)
        XCTAssertEqual(expected.ruleInstructions, "Changed rule\nSecond")
        XCTAssertEqual(try expected.preparedStoryText(), "Changed scene")
        XCTAssertEqual(expected.storyText, "independent historical summary")
        XCTAssertEqual(expected.storyTimelineEdited, true); XCTAssertEqual(expected.legacyHintsEnabled, true)
        model.leave(); model.load()
        rule.wrappedValue = "stale rule"; story.wrappedValue = "stale scene"; hint.wrappedValue = "stale hint"
        XCTAssertEqual(model.draft, expected); XCTAssertEqual(coordinator.draft, expected)
        XCTAssertFalse(editor.canEdit); model.save()
        let reopened = TemplateAuthoringCoordinator(store: store, currentSession: { session })
        reopened.open(); reopened.restoreDraft(); XCTAssertEqual(reopened.draft, expected)
        XCTAssertFalse(coordinator.canSubmit); XCTAssertNil(try store.pending(session: session, identity: coordinator.identity))
    }
    func testRestorePreservesRawHistoryAndMissingMarkersAcrossAllThreeEditors() throws {
        let session = try owner(), store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage())
        let saved = TemplateAuthoringCoordinator(store: store, currentSession: { session })
        let historical = seed(); saved.open(seed: historical); saved.saveLocal()
        let coordinator = TemplateAuthoringCoordinator(store: store, currentSession: { session })
        let model = TemplateAuthoringModel(coordinator: coordinator); model.load()
        let editor = TemplateStoryEditor(model: model)
        let rule = model.ruleStep(try XCTUnwrap(model.ruleSteps.rows.first?.id))
        let story = editor.text(try XCTUnwrap(editor.beats.first?.id), \.text), hint = model.legacyHint(.hint1)
        XCTAssertFalse(model.canEdit); model.restore()
        rule.wrappedValue = "stale rule"; story.wrappedValue = "stale scene"; hint.wrappedValue = "stale hint"
        XCTAssertEqual(model.draft, historical); XCTAssertEqual(coordinator.draft, historical)
        XCTAssertNil(model.draft.storyTimelineEdited); XCTAssertNil(model.draft.legacyHintsEnabled)
        editor.load(); XCTAssertTrue(editor.canEdit); XCTAssertEqual(model.draft, historical)
        model.save(); XCTAssertEqual(model.draft, historical)
    }
    func testDiscardFencesEveryEditorWithoutRelyingOnIdentityChange() throws {
        let session = try owner()
        let coordinator = TemplateAuthoringCoordinator(store: .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { session })
        coordinator.open(seed: seed()); let model = TemplateAuthoringModel(coordinator: coordinator); model.load()
        let editor = TemplateStoryEditor(model: model)
        let rule = model.ruleStep(try XCTUnwrap(model.ruleSteps.rows.first?.id))
        let story = editor.text(try XCTUnwrap(editor.beats.first?.id), \.text), hint = model.legacyHint(.hint1)
        let identity = coordinator.identity; model.discard()
        XCTAssertEqual(coordinator.identity, identity)
        let expected = model.draft
        rule.wrappedValue = "stale rule"; story.wrappedValue = "stale scene"; hint.wrappedValue = "stale hint"
        XCTAssertEqual(model.draft, expected); XCTAssertEqual(coordinator.draft, expected)
        XCTAssertNil(expected.ruleInstructions); XCTAssertNil(expected.storyJson); XCTAssertNil(expected.hint1)
        XCTAssertNil(expected.storyTimelineEdited); XCTAssertNil(expected.legacyHintsEnabled)
    }
    func testEpochReplacementRejectsEveryRetainedEditorBeforeAndAfterReload() throws {
        var session: TemplateAuthoringSession? = try owner()
        let coordinator = TemplateAuthoringCoordinator(store: .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { session })
        coordinator.open(seed: seed()); let model = TemplateAuthoringModel(coordinator: coordinator); model.load()
        let editor = TemplateStoryEditor(model: model)
        let rule = model.ruleStep(try XCTUnwrap(model.ruleSteps.rows.first?.id))
        let story = editor.text(try XCTUnwrap(editor.beats.first?.id), \.text), hint = model.legacyHint(.hint1)
        let original = model.draft; session = try owner(2)
        rule.wrappedValue = "wrong owner"; story.wrappedValue = "wrong owner"; hint.wrappedValue = "wrong owner"
        XCTAssertEqual(model.draft, original)
        model.load(); let replacement = model.draft
        rule.wrappedValue = "stale rule"; story.wrappedValue = "stale scene"; hint.wrappedValue = "stale hint"
        XCTAssertEqual(model.draft, replacement); XCTAssertEqual(coordinator.draft, replacement)
        XCTAssertNil(replacement.ruleInstructions); XCTAssertNil(replacement.storyJson); XCTAssertNil(replacement.hint1)
    }
}

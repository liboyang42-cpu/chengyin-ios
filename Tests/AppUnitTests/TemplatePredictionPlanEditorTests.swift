import XCTest
@testable import Questify

@MainActor final class TemplatePredictionPlanEditorTests: XCTestCase {
    private final class Owner { var session: TemplateAuthoringSession?; init(_ value: TemplateAuthoringSession) { session = value } }
    private func setup(store: TemplateAuthoringLocalStore? = nil) throws -> (TemplateAuthoringModel, TemplatePredictionPlanController, Owner) {
        let owner = Owner(try .init(accountID: 991, namespace: "prediction-plan", epoch: 1, authorizationRevision: "member"))
        let model = TemplateAuthoringModel(coordinator: .init(store: store ?? .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { owner.session }))
        model.load(); model.draft.title = "Predict"; model.draft.advanced.setCreatorEnabled(.predict, true)
        model.draft.advanced.set("predict", "question", .string("Which drink?")); model.draft.advanced.set("predict", "options", .array([.object(["key": .string("A"), "label": .string("Tea")]), .object(["key": .string("B"), "label": .string("Coffee")])]))
        model.draft.advanced.set("predict", "closeAtHour", .number(20)); model.draft.advanced.set("predict", "revealDays", .number(1)); model.draft.advanced.set("predict", "revealHour", .number(20)); model.changed(); return (model, .init(model: model), owner)
    }
    func testCompleteQuestionOptionsScheduleAndLocalSaveFlow() throws {
        let (model, editor, _) = try setup(); editor.textInput(.question).wrappedValue = "Today's top drink?"; editor.textInput(.hint).wrappedValue = "Come back tomorrow"
        editor.addAction()(); XCTAssertEqual(editor.rows.count, 3); editor.labelInput(2).wrappedValue = "Milk"; editor.removeAction(0)(); XCTAssertEqual(editor.rows.map(\.label), ["Coffee", "Milk"])
        editor.timingInput(.closeAtHour).wrappedValue = 23; editor.timingInput(.revealDays).wrappedValue = 1; editor.timingInput(.revealHour).wrappedValue = 9
        XCTAssertTrue(editor.issues.isEmpty); editor.saveAction()(); XCTAssertEqual(model.coordinator.draft, model.draft); XCTAssertFalse(model.coordinator.canSubmit)
    }
    func testContinuousRawInputsAndParentRefreshKeepEditorLive() throws {
        let (model, editor, _) = try setup(), question = editor.textInput(.question), label = editor.labelInput(0), timing = editor.timingInput(.revealDays)
        question.wrappedValue = " raw\n"; question.wrappedValue = " raw\nquestion"; label.wrappedValue = "Tea "; label.wrappedValue = "Tea 2"; model.changed(); timing.wrappedValue = 2; timing.wrappedValue = 30
        XCTAssertEqual(question.wrappedValue, " raw\nquestion"); XCTAssertEqual(label.wrappedValue, "Tea 2"); XCTAssertEqual(editor.timing(.revealDays), 30); XCTAssertFalse(editor.needsReload)
    }
    func testRemoveAndAddCannotRetargetOldRowInputsOrButtons() throws {
        let (model, editor, _) = try setup(), oldInput = editor.labelInput(1), oldRemove = editor.removeAction(1), oldAdd = editor.addAction()
        editor.removeAction(0)(); editor.addAction()(); let before = model.draft; oldInput.wrappedValue = "stale"; oldRemove(); oldAdd(); XCTAssertEqual(model.draft, before); XCTAssertEqual(editor.rows.count, 2)
        editor.labelInput(1).wrappedValue = "New"; XCTAssertEqual(editor.rows.map(\.label), ["Coffee", "New"])
    }
    func testEmptyRowsRemainRepairableAndCapUsesExistingContract() throws {
        let (_, editor, _) = try setup(); editor.removeAction(1)(); editor.removeAction(0)(); XCTAssertTrue(editor.isSupported); XCTAssertTrue(editor.issues.contains { $0.path == "options" && $0.code == "count" })
        for _ in 0..<4 { editor.addAction()() }; XCTAssertEqual(editor.rows.count, 4); XCTAssertFalse(editor.canAdd); editor.addAction()(); XCTAssertEqual(editor.rows.count, 4)
    }
    func testSameDayConflictCanBeCorrectedWithoutAutomaticRescheduling() throws {
        let (_, editor, _) = try setup(); editor.timingInput(.revealDays).wrappedValue = 0; editor.timingInput(.revealHour).wrappedValue = 19; XCTAssertTrue(editor.sameDayConflict); XCTAssertEqual(editor.timing(.closeAtHour), 20)
        editor.timingInput(.revealHour).wrappedValue = 20; XCTAssertFalse(editor.sameDayConflict); XCTAssertTrue(editor.issues.isEmpty)
    }
    func testStaleActionsAfterMetadataChangeCannotMutate() throws {
        let (model, editor, _) = try setup(), remove = editor.removeAction(0); model.changed(); let before = model.draft; remove(); XCTAssertEqual(model.draft, before); XCTAssertTrue(editor.canEdit)
    }
    func testExternalDraftABARequiresReload() throws {
        let (model, editor, _) = try setup(), input = editor.textInput(.question), add = editor.addAction(), before = model.draft
        model.draft.title = "Other"; model.draft = before; input.wrappedValue = "stale"; add(); XCTAssertEqual(model.draft, before); XCTAssertTrue(editor.needsReload); editor.reload(); XCTAssertTrue(editor.canEdit)
    }
    func testOwnerLifecycleAndBackgroundFenceInputsAndActions() throws {
        for operation in ["load", "restore", "discard", "owner", "leave", "dismiss", "background"] {
            let (model, editor, owner) = try setup(), input = editor.textInput(.question), timing = editor.timingInput(.revealDays), add = editor.addAction()
            switch operation { case "load": model.load(); case "restore": model.restore(); case "discard": model.discard(); case "owner": owner.session = try .init(accountID: 992, namespace: "prediction-plan", epoch: 2, authorizationRevision: "member"); case "leave": model.leave(); case "background": editor.suspend(); default: editor.retire() }
            let before = model.draft; input.wrappedValue = "stale"; timing.wrappedValue = 30; add(); XCTAssertEqual(model.draft, before, operation); XCTAssertFalse(editor.canEdit, operation)
        }
    }
    func testBusyABARequiresExplicitReload() throws {
        let (model, editor, _) = try setup(), input = editor.labelInput(0); model.busy = true; model.busy = false; let before = model.draft; input.wrappedValue = "stale"; XCTAssertEqual(model.draft, before); XCTAssertTrue(editor.needsReload); editor.reload(); XCTAssertTrue(editor.canEdit)
    }
    func testMediaScopeChangeRetiresOldCallbacks() throws {
        let (model, editor, _) = try setup(), input = editor.textInput(.hint), add = editor.addAction(); model.restore(); let before = model.draft; input.wrappedValue = "stale"; add(); XCTAssertEqual(model.draft, before); XCTAssertFalse(editor.canEdit)
    }
    func testMalformedDraftRemainsUntouchedAndDisabled() throws {
        let (model, editor, _) = try setup(); model.draft.advanced.set("predict", "revealHour", .string("bad")); editor.reload(); let before = model.draft; editor.timingInput(.revealHour).wrappedValue = 9; editor.addAction()(); XCTAssertEqual(model.draft, before); XCTAssertFalse(editor.isSupported)
    }
    func testLocalSaveRestoreRetainsCurrentKeysLabelsAndRelativeDays() throws {
        let store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage()), (model, editor, owner) = try setup(store: store)
        editor.addAction()(); editor.labelInput(2).wrappedValue = "Milk"; editor.removeAction(1)(); editor.timingInput(.revealDays).wrappedValue = 30; let expected = model.draft; editor.saveAction()(); editor.retire(); model.leave()
        let reopened = TemplateAuthoringModel(coordinator: .init(store: store, currentSession: { owner.session })); reopened.load(); reopened.restore(); let fresh = TemplatePredictionPlanController(model: reopened)
        XCTAssertEqual(reopened.draft, expected); XCTAssertEqual(fresh.rows.map(\.label), ["Tea", "Milk"]); XCTAssertEqual(fresh.timing(.revealDays), 30); XCTAssertFalse(reopened.coordinator.canSubmit)
    }
    func testPendingWriteLockBlocksPlanMutation() throws {
        let (seedModel, _, owner) = try setup(), session = try XCTUnwrap(owner.session), seed = seedModel.draft, identity = TemplateAuthoringIdentity(), store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage())
        try store.save(seed, session: session, identity: identity); try store.savePending(.init(operationID: UUID(), ownerKey: session.ownerKey, identity: identity, request: TemplateAuthoringContract.request(seed, intent: .saveDraft), createdAt: Date()), session: session)
        let model = TemplateAuthoringModel(coordinator: .init(store: store, currentSession: { session })); model.load(); model.draft = seed; let editor = TemplatePredictionPlanController(model: model)
        editor.textInput(.question).wrappedValue = "stale"; editor.addAction()(); XCTAssertEqual(model.draft, seed); XCTAssertFalse(editor.canEdit)
    }
}

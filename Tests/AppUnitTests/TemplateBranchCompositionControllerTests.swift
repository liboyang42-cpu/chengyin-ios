import XCTest
@testable import Questify

@MainActor final class TemplateBranchCompositionControllerTests: XCTestCase {
    private final class Owner { var session: TemplateAuthoringSession?; init(_ session: TemplateAuthoringSession) { self.session = session } }
    private func setup(store: TemplateAuthoringLocalStore? = nil) throws -> (TemplateAuthoringModel, Owner) {
        let owner = Owner(try .init(accountID: 941, namespace: "branch-composition", epoch: 1, authorizationRevision: "member"))
        let model = TemplateAuthoringModel(coordinator: .init(store: store ?? .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { owner.session }))
        model.load(); model.draft.title = "Branches"; model.draft.advanced.setCreatorEnabled(.branch, true); model.changed(); return (model, owner)
    }
    func testNewStepContinueWithChoiceEditThenTerminalCompleteFlow() throws {
        let (model, _) = try setup(), root = TemplateBranchCompositionController(model: model)
        root.addAction()(); XCTAssertEqual(model.draft.advanced.rows("branch", "steps").count, 2)
        let terminal = TemplateBranchCompositionController(model: model, stepIndex: 0)
        XCTAssertTrue(terminal.terminal); terminal.addAction()(); XCTAssertFalse(terminal.terminal)
        let path: [TemplateCreatorPath] = [.field("steps"), .index(0), .field("options"), .index(0)]
        model.draft.advanced.setCreatorValue(.branch, path: path + [.field("label")], entry: .string("Continue"))
        let endID = model.draft.advanced.rows("branch", "steps")[1].object?["id"]?.string ?? ""
        model.draft.advanced.setCreatorValue(.branch, path: path + [.field("nextStepId")], entry: .string(endID)); model.changed()
        XCTAssertTrue(model.draft.advanced.creatorIssues(.branch).isEmpty)
        terminal.terminalBinding().wrappedValue = true
        XCTAssertTrue(terminal.terminal); XCTAssertEqual(model.draft.advanced.rows("branch", "steps")[0].object?["options"], .array([]))
        XCTAssertEqual(model.coordinator.draft, model.draft)
    }
    func testTurningOffAloneDoesNotInventAnOption() throws {
        let (model, _) = try setup(), editor = TemplateBranchCompositionController(model: model, stepIndex: 0)
        editor.terminalBinding().wrappedValue = false
        XCTAssertFalse(editor.terminal); XCTAssertEqual(model.draft.advanced.rows("branch", "steps")[0].object?["options"], .array([]))
        editor.addAction()(); XCTAssertEqual(model.draft.advanced.rows("branch", "steps")[0].object?["options"]?.array?.count, 1)
    }
    func testRetainedToggleAndAddActionCannotReplayAfterTransition() throws {
        let (model, _) = try setup(), editor = TemplateBranchCompositionController(model: model, stepIndex: 0)
        let binding = editor.terminalBinding(), add = editor.addAction(); add(); let before = model.draft
        add(); binding.wrappedValue = true; XCTAssertEqual(model.draft, before)
        editor.terminalBinding().wrappedValue = true; XCTAssertTrue(editor.terminal)
    }
    func testExternalTextChangeAndSameValueABARetireActions() throws {
        let (model, _) = try setup(), editor = TemplateBranchCompositionController(model: model, stepIndex: 0)
        let add = editor.addAction(), toggle = editor.terminalBinding(), original = model.draft
        model.draft.advanced.setRow("branch", "steps", index: 0, key: "title", text: "Changed"); model.draft = original
        add(); toggle.wrappedValue = false; XCTAssertEqual(model.draft, original)
        editor.addAction()(); XCTAssertFalse(editor.terminal)
    }
    func testStepIdentityAndReorderCannotRetargetCapturedControllerAfterReload() throws {
        let (model, _) = try setup(), root = TemplateBranchCompositionController(model: model); root.addAction()()
        let editor = TemplateBranchCompositionController(model: model, stepIndex: 0), add = editorAdd(model)
        model.draft.advanced.moveRow("branch", "steps", from: 0, to: 1); editor.reload(); let before = model.draft
        XCTAssertFalse(editor.canEdit); editor.addAction()(); add(); XCTAssertEqual(model.draft, before)
    }
    private func editorAdd(_ model: TemplateAuthoringModel) -> () -> Void {
        // Keep this controller alive through the returned closure for a genuine retained callback.
        let editor = TemplateBranchCompositionController(model: model, stepIndex: 0), action = editor.addAction()
        return { _ = editor; action() }
    }
    func testStepRenameRequiresNewIdentityControllerAndOldCallbackStaysRetired() throws {
        let (model, _) = try setup(), old = TemplateBranchCompositionController(model: model, stepIndex: 0), action = old.addAction()
        model.draft.advanced.setRow("branch", "steps", index: 0, key: "id", text: "renamed"); let before = model.draft
        action(); XCTAssertFalse(old.canEdit); XCTAssertEqual(model.draft, before)
        let fresh = TemplateBranchCompositionController(model: model, stepIndex: 0); fresh.addAction()()
        XCTAssertFalse(fresh.terminal)
    }
    func testLoadRestoreDiscardOwnerLeaveAndDismissFenceControls() throws {
        for operation in ["load", "restore", "discard", "owner", "leave", "dismiss"] {
            let (model, owner) = try setup(), editor = TemplateBranchCompositionController(model: model, stepIndex: 0)
            let add = editor.addAction(), toggle = editor.terminalBinding()
            switch operation {
            case "load": model.load()
            case "restore": model.restore()
            case "discard": model.discard()
            case "owner": owner.session = try .init(accountID: 942, namespace: "branch-composition", epoch: 2, authorizationRevision: "member")
            case "leave": model.leave()
            default: editor.retire()
            }
            let before = model.draft; add(); toggle.wrappedValue = false; XCTAssertEqual(model.draft, before, operation)
        }
    }
    func testReappearanceRetiresEarlierBindingButAllowsFreshAction() throws {
        let (model, _) = try setup(), editor = TemplateBranchCompositionController(model: model, stepIndex: 0), old = editor.addAction()
        editor.retire(); editor.reload(); let before = model.draft; old(); XCTAssertEqual(model.draft, before)
        editor.addAction()(); XCTAssertFalse(editor.terminal)
    }
    func testLocalSaveAndRestoreKeepTerminalOutcomeAndClearedChoices() throws {
        let store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage()), (model, owner) = try setup(store: store)
        let editor = TemplateBranchCompositionController(model: model, stepIndex: 0); editor.addAction()(); editor.terminalAction(true)()
        let expected = model.draft; model.save(); model.leave()
        let reopened = TemplateAuthoringModel(coordinator: .init(store: store, currentSession: { owner.session })); reopened.load(); reopened.restore()
        XCTAssertEqual(reopened.draft, expected); XCTAssertTrue(TemplateBranchCompositionController(model: reopened, stepIndex: 0).terminal)
        XCTAssertFalse(reopened.coordinator.canSubmit)
    }
    func testPendingLockDeniesRootAndStepChanges() throws {
        let (seedModel, owner) = try setup(), session = try XCTUnwrap(owner.session)
        let store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage()), identity = TemplateAuthoringIdentity(), seed = seedModel.draft
        try store.save(seed, session: session, identity: identity)
        try store.savePending(.init(operationID: UUID(), ownerKey: session.ownerKey, identity: identity,
            request: TemplateAuthoringContract.request(seed, intent: .saveDraft), createdAt: Date()), session: session)
        let model = TemplateAuthoringModel(coordinator: .init(store: store, currentSession: { session })); model.load(); model.draft = seed
        let root = TemplateBranchCompositionController(model: model), step = TemplateBranchCompositionController(model: model, stepIndex: 0)
        root.addAction()(); step.addAction()(); step.terminalAction(false)(); XCTAssertEqual(model.draft, seed)
        XCTAssertFalse(root.canEdit); XCTAssertFalse(step.canEdit)
    }
}

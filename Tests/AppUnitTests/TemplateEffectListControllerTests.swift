import XCTest
@testable import Questify

@MainActor final class TemplateEffectListControllerTests: XCTestCase {
    private let path: [TemplateCreatorPath] = [.field("options"), .index(0), .field("effects")]
    private final class Owner { var session: TemplateAuthoringSession?; init(_ value: TemplateAuthoringSession) { session = value } }
    private func setup(store: TemplateAuthoringLocalStore? = nil) throws -> (TemplateAuthoringModel, TemplateEffectListController, Owner) {
        let owner = Owner(try .init(accountID: 921, namespace: "effect-editor", epoch: 1, authorizationRevision: "member"))
        let model = TemplateAuthoringModel(coordinator: .init(store: store ?? .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { owner.session }))
        model.load(); model.draft.title = "Effect authoring"; model.draft.advanced.setCreatorEnabled(.qa, true)
        model.draft.advanced.set("qa", "mode", .string("PICK")); model.draft.advanced.set("qa", "title", .string("Choose"))
        for index in 0..<2 { model.draft.advanced.setCreatorValue(.qa, path: [.field("options"), .index(index), .field("label")], entry: .string("Option \(index)")) }
        model.draft.advanced.setCreatorValue(.qa, path: [.field("options"), .index(0), .field("correct")], entry: .bool(true))
        model.changed(); return (model, .init(model: model, family: .qa, path: path), owner)
    }
    func testFullAddTypeSwitchInputMoveAndRemoveFlow() throws {
        let (model, editor, _) = try setup(); editor.addAction()()
        editor.input(0, .variable).wrappedValue = "counter.visits"; editor.input(0, .value).wrappedValue = "2"
        editor.operation(0).wrappedValue = "ADD_TAG"; XCTAssertEqual(editor.rows[0].input, "")
        editor.input(0, .value).wrappedValue = "tag.brave"; editor.operation(0).wrappedValue = "INC"
        XCTAssertEqual(editor.rows[0].input, "1"); XCTAssertEqual(editor.rows[0].variable, "counter.visits")
        editor.addAction()(); editor.moveAction(0, 1)(); XCTAssertEqual(editor.rows[1].variable, "counter.visits")
        editor.removeAction(0)(); XCTAssertEqual(editor.rows.count, 1)
        XCTAssertEqual(model.coordinator.draft, model.draft); XCTAssertTrue(model.draft.advanced.creatorIssues(.qa).isEmpty)
    }
    func testRepeatedTypingAndInvalidIntermediateValueStayEditable() throws {
        let (_, editor, _) = try setup(); editor.addAction()()
        let variable = editor.input(0, .variable), value = editor.input(0, .value)
        variable.wrappedValue = "counter.v"; variable.wrappedValue = "counter.visits"
        value.wrappedValue = "-"; XCTAssertFalse(editor.issues.isEmpty)
        value.wrappedValue = "-3"; XCTAssertEqual(editor.rows[0].input, "-3"); XCTAssertTrue(editor.issues.isEmpty)
    }
    func testOperationChangeRetiresHiddenInputAndOldOperationBindings() throws {
        let (model, editor, _) = try setup(); editor.addAction()()
        let oldVariable = editor.input(0, .variable), oldValue = editor.input(0, .value), oldOperation = editor.operation(0)
        editor.operation(0).wrappedValue = "ADD_TAG"; let expected = model.draft
        oldVariable.wrappedValue = "counter.stale"; oldValue.wrappedValue = "99"; oldOperation.wrappedValue = "SET"
        XCTAssertEqual(model.draft, expected)
        editor.input(0, .value).wrappedValue = "tag.current"; XCTAssertEqual(editor.rows[0].input, "tag.current")
    }
    func testReorderingAndRemovingRetiresOldRowIndexControls() throws {
        let (model, editor, _) = try setup(); editor.addAction()(); editor.addAction()()
        let old = editor.input(0, .variable), remove = editor.removeAction(1)
        editor.moveAction(0, 1)(); let expected = model.draft
        old.wrappedValue = "counter.wrong"; remove(); XCTAssertEqual(model.draft, expected)
        editor.removeAction(0)(); XCTAssertEqual(editor.rows.count, 1)
    }
    func testEnclosingOptionChangeCannotSilentlyRetargetEvenAfterReload() throws {
        let (model, editor, _) = try setup(); editor.addAction()()
        let old = editor.input(0, .value), add = editor.addAction()
        var rows = model.draft.advanced.rows("qa", "options"); rows.swapAt(0, 1); model.draft.advanced.set("qa", "options", .array(rows))
        editor.reload(); let expected = model.draft
        XCTAssertTrue(editor.needsReopen); XCTAssertFalse(editor.canEdit)
        old.wrappedValue = "99"; add(); XCTAssertEqual(model.draft, expected)
    }
    func testSameValueParentABARejectsRetainedCallbacksBeforeOnChange() throws {
        let (model, editor, _) = try setup(); editor.addAction()()
        let old = editor.input(0, .value), operation = editor.operation(0), before = model.draft
        model.draft.advanced.set("qa", "mode", .string("TYPE")); model.draft = before
        old.wrappedValue = "99"; operation.wrappedValue = "SET"
        XCTAssertEqual(model.draft, before)
        editor.input(0, .value).wrappedValue = "3"; XCTAssertEqual(editor.rows[0].input, "3")
    }
    func testLocalSaveAndFreshRestoreRetainTypedEffectConfiguration() throws {
        let store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage())
        let (model, editor, owner) = try setup(store: store); editor.addAction()()
        editor.operation(0).wrappedValue = "ADD_TAG"; editor.input(0, .value).wrappedValue = "tag.brave"
        let expected = model.draft; model.save(); editor.retire(); model.leave()
        let reopened = TemplateAuthoringModel(coordinator: .init(store: store, currentSession: { owner.session })); reopened.load(); reopened.restore()
        let fresh = TemplateEffectListController(model: reopened, family: .qa, path: path)
        XCTAssertEqual(reopened.draft, expected); XCTAssertEqual(fresh.rows[0].input, "tag.brave"); XCTAssertTrue(fresh.canEdit)
        XCTAssertFalse(reopened.coordinator.canSubmit)
    }
    func testLoadRestoreDiscardOwnerAndDismissFenceOldControls() throws {
        for operation in ["load", "restore", "discard", "owner", "dismiss", "leave"] {
            let (model, editor, owner) = try setup(); editor.addAction()()
            let input = editor.input(0, .value), add = editor.addAction()
            switch operation {
            case "load": model.load()
            case "restore": model.restore()
            case "discard": model.discard()
            case "owner": owner.session = try .init(accountID: 922, namespace: "effect-editor", epoch: 2, authorizationRevision: "member")
            case "leave": model.leave()
            default: editor.retire()
            }
            let expected = model.draft; input.wrappedValue = "99"; add(); XCTAssertEqual(model.draft, expected, operation)
        }
    }
    func testSameParentReappearancePreservesContentButDoesNotReviveBindings() throws {
        let (model, editor, _) = try setup(); editor.addAction()()
        let old = editor.input(0, .value); editor.retire(); editor.reload(); let before = model.draft
        old.wrappedValue = "99"; XCTAssertEqual(model.draft, before)
        editor.input(0, .value).wrappedValue = "4"; XCTAssertEqual(editor.rows[0].input, "4")
    }
    func testPendingWriteLockDeniesAllEffectChanges() throws {
        let (seedModel, _, owner) = try setup(), session = try XCTUnwrap(owner.session)
        let store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage()), identity = TemplateAuthoringIdentity(), seed = seedModel.draft
        try store.save(seed, session: session, identity: identity)
        try store.savePending(.init(operationID: UUID(), ownerKey: session.ownerKey, identity: identity,
            request: TemplateAuthoringContract.request(seed, intent: .saveDraft), createdAt: Date()), session: session)
        let model = TemplateAuthoringModel(coordinator: .init(store: store, currentSession: { session })); model.load(); model.draft = seed
        let editor = TemplateEffectListController(model: model, family: .qa, path: path); editor.addAction()()
        XCTAssertFalse(editor.canEdit); XCTAssertEqual(model.draft, seed)
    }
}

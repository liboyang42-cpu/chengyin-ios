import XCTest
@testable import Questify

@MainActor final class TemplateBlindOptionEditorTests: XCTestCase {
    private final class Owner {
        var session: TemplateAuthoringSession?
        init(_ session: TemplateAuthoringSession) { self.session = session }
    }
    private func setup(store: TemplateAuthoringLocalStore? = nil) throws -> (TemplateAuthoringModel, TemplateBlindOptionEditor, Owner) {
        let owner = Owner(try .init(accountID: 917, namespace: "blind-option-flow", epoch: 1, authorizationRevision: "member"))
        let model = TemplateAuthoringModel(coordinator: .init(store: store ?? .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { owner.session }))
        model.load(); model.draft.title = "Blind tasting"
        model.draft.advanced.setCreatorEnabled(.blindTaste, true); model.draft.advanced.set("blindTaste", "title", .string("Which tea?"))
        for index in 0..<2 { model.draft.advanced.setCreatorValue(.blindTaste, path: [.field("options"), .index(index), .field("label")], entry: .string("Tea \(index + 1)")) }
        model.changed(); return (model, .init(model: model), owner)
    }
    func testAddEditChooseRenameDeleteCompleteFlow() throws {
        let (model, editor, _) = try setup()
        editor.addAction()(); XCTAssertEqual(editor.rows.map(\.key), ["A", "B", "C"])
        editor.text(2, .label).wrappedValue = "Oolong"; editor.chooseAction(2)()
        XCTAssertEqual(model.draft.advanced.text("blindTaste", "answerKey"), "C")
        editor.text(2, .key).wrappedValue = "oolong"
        XCTAssertEqual(model.draft.advanced.text("blindTaste", "answerKey"), "oolong")
        editor.removeAction(2)(); XCTAssertEqual(editor.rows.map(\.key), ["A", "B"])
        XCTAssertEqual(model.draft.advanced.text("blindTaste", "answerKey"), "A")
        XCTAssertEqual(model.coordinator.draft, model.draft); XCTAssertTrue(model.draft.advanced.creatorIssues(.blindTaste).isEmpty)
    }
    func testRepeatedKeyAndLabelTypingKeepsCurrentRowsStable() throws {
        let (model, editor, _) = try setup(), key = editor.text(0, .key), label = editor.text(0, .label)
        key.wrappedValue = "t"; key.wrappedValue = "tea"; key.wrappedValue = "tea_1"
        label.wrappedValue = "G"; label.wrappedValue = "Green tea"
        XCTAssertEqual(editor.rows[0].key, "tea_1"); XCTAssertEqual(editor.rows[0].label, "Green tea")
        XCTAssertEqual(model.draft.advanced.text("blindTaste", "answerKey"), "tea_1")
    }
    func testNativeSaveFreshRestoreAndLocalRehearsalUseResultingAnswer() throws {
        let store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage())
        let (model, editor, owner) = try setup(store: store)
        editor.text(1, .key).wrappedValue = "oolong"; editor.chooseAction(1)()
        let expected = model.draft; model.save(); editor.retire(); model.leave()
        let reopened = TemplateAuthoringModel(coordinator: .init(store: store, currentSession: { owner.session }))
        reopened.load(); reopened.restore(); let fresh = TemplateBlindOptionEditor(model: reopened)
        XCTAssertEqual(reopened.draft, expected); XCTAssertEqual(fresh.rows.map(\.isAnswer), [false, true])
        var rehearsal = TemplateCreatorRehearsal()
        rehearsal.evaluate(.blindTaste, draft: reopened.draft.advanced, selected: ["oolong"])
        XCTAssertEqual(rehearsal.result, .matched); XCTAssertFalse(reopened.coordinator.canSubmit)
    }
    func testDeletingARowRetiresTextAndActionCallbacksForOldIndexes() throws {
        let (model, editor, _) = try setup(), oldKey = editor.text(1, .key), oldLabel = editor.text(1, .label)
        let oldChoose = editor.chooseAction(1), oldDelete = editor.removeAction(1)
        editor.removeAction(0)(); let expected = model.draft
        oldKey.wrappedValue = "wrong"; oldLabel.wrappedValue = "wrong"; oldChoose(); oldDelete()
        XCTAssertEqual(model.draft, expected)
        editor.text(0, .label).wrappedValue = "Current row"; XCTAssertEqual(editor.rows[0].label, "Current row")
    }
    func testMovingRetainsSelectedIdentityAndRetiresOldRowFields() throws {
        let (model, editor, _) = try setup(), old = editor.text(0, .label)
        editor.moveAction(0, 1)(); let expected = model.draft
        XCTAssertEqual(editor.rows.map(\.key), ["B", "A"]); XCTAssertTrue(editor.rows[1].isAnswer)
        old.wrappedValue = "stale"; XCTAssertEqual(model.draft, expected)
        editor.text(0, .label).wrappedValue = "Current first"; XCTAssertEqual(editor.rows[0].label, "Current first")
    }
    func testExternalReorderAndSameValueABAInvalidateFieldsBeforeParentOnChange() throws {
        for mutation in ["reorder", "aba"] {
            let (model, editor, _) = try setup(), field = editor.text(0, .label), choose = editor.chooseAction(1), add = editor.addAction()
            let before = model.draft
            if mutation == "reorder" {
                var rows = model.draft.advanced.rows("blindTaste", "options"); rows.swapAt(0, 1)
                model.draft.advanced.set("blindTaste", "options", .array(rows))
            } else {
                model.draft.advanced.setCreatorEnabled(.blindTaste, false); model.draft = before
            }
            let expected = model.draft; field.wrappedValue = "stale"; choose(); add()
            XCTAssertEqual(model.draft, expected, mutation)
        }
    }
    func testOwnTypingRetiresOldButtonsWithoutInterruptingTextBinding() throws {
        let (model, editor, _) = try setup(), field = editor.text(1, .label), choose = editor.chooseAction(1), remove = editor.removeAction(0)
        field.wrappedValue = "Black"; choose(); remove(); field.wrappedValue = "Black tea"
        XCTAssertEqual(editor.rows.count, 2); XCTAssertEqual(editor.rows[1].label, "Black tea")
        XCTAssertEqual(model.draft.advanced.text("blindTaste", "answerKey"), "A")
    }
    func testLoadRestoreDiscardLeaveAndOwnerChangeRejectRetainedControls() throws {
        for operation in ["load", "restore", "discard", "leave", "owner"] {
            let (model, editor, owner) = try setup(), field = editor.text(0, .key), add = editor.addAction(), remove = editor.removeAction(1)
            switch operation {
            case "load": model.load()
            case "restore": model.restore()
            case "discard": model.discard()
            case "leave": model.leave()
            default: owner.session = try .init(accountID: 918, namespace: "blind-option-flow", epoch: 2, authorizationRevision: "member")
            }
            let expected = model.draft; field.wrappedValue = "stale"; add(); remove()
            XCTAssertEqual(model.draft, expected, operation)
        }
    }
    func testReappearanceReacquiresBindingsWithoutRevivingOldControls() throws {
        let (model, editor, _) = try setup(), old = editor.text(0, .label)
        editor.retire(); XCTAssertFalse(editor.canEdit); editor.reload()
        let before = model.draft; old.wrappedValue = "stale"; XCTAssertEqual(model.draft, before)
        editor.text(0, .label).wrappedValue = "New label"; XCTAssertEqual(editor.rows[0].label, "New label")
        model.load(); editor.reload(); editor.chooseAction(1)(); XCTAssertTrue(editor.rows[1].isAnswer)
    }
    func testOpeningPreservesUnsupportedDraftAndDisabledFamilyCannotEdit() throws {
        let (model, editor, _) = try setup()
        model.draft.advanced.set("blindTaste", "options", .string("legacy")); let legacy = model.draft
        editor.reload(); editor.addAction()(); editor.text(0, .key).wrappedValue = "A"
        XCTAssertFalse(editor.isSupported); XCTAssertEqual(model.draft, legacy)
        model.draft.advanced.setCreatorEnabled(.blindTaste, false); let disabled = model.draft
        editor.chooseAction(0)(); XCTAssertEqual(model.draft, disabled)
    }
    func testDurablePendingWriteLockRejectsOptionMutation() throws {
        let (seedModel, _, owner) = try setup(), session = try XCTUnwrap(owner.session)
        let store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage()), identity = TemplateAuthoringIdentity(), seed = seedModel.draft
        try store.save(seed, session: session, identity: identity)
        try store.savePending(.init(operationID: UUID(), ownerKey: session.ownerKey, identity: identity,
            request: TemplateAuthoringContract.request(seed, intent: .saveDraft), createdAt: Date()), session: session)
        let model = TemplateAuthoringModel(coordinator: .init(store: store, currentSession: { session })); model.load(); model.draft = seed
        let editor = TemplateBlindOptionEditor(model: model)
        editor.addAction()(); editor.removeAction(0)(); editor.text(0, .label).wrappedValue = "Changed"
        XCTAssertFalse(editor.canEdit); XCTAssertEqual(model.draft, seed)
    }
}

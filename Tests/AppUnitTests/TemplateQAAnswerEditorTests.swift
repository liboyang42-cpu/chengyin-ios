import XCTest
@testable import Questify

@MainActor final class TemplateQAAnswerEditorTests: XCTestCase {
    private final class Owner {
        var session: TemplateAuthoringSession?
        init(_ value: TemplateAuthoringSession) { session = value }
    }
    private func setup(store: TemplateAuthoringLocalStore? = nil) throws -> (TemplateAuthoringModel, TemplateQAAnswerEditor, Owner) {
        let owner = Owner(try .init(accountID: 915, namespace: "qa-answer-flow", epoch: 1, authorizationRevision: "member"))
        let model = TemplateAuthoringModel(coordinator: .init(store: store ?? .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { owner.session }))
        model.load(); model.draft.title = "QA answers"
        model.draft.advanced.setCreatorEnabled(.qa, true); model.draft.advanced.set("qa", "mode", .string("PICK"))
        model.draft.advanced.set("qa", "title", .string("Which choices?"))
        for index in 0..<2 { model.draft.advanced.setCreatorValue(.qa, path: [.field("options"), .index(index), .field("label")], entry: .string("Option \(index + 1)")) }
        model.changed()
        return (model, .init(model: model), owner)
    }
    private func flags(_ model: TemplateAuthoringModel) -> [Bool] { TemplateQAAnswerSelection(model.draft.advanced).options.map(\.correct) }
    func testSingleMultiAndBackToSingleFollowCompleteAnswerFlow() throws {
        let (model, editor, _) = try setup()
        editor.chooseAction(1)(); XCTAssertEqual(flags(model), [false, true])
        editor.multiple().wrappedValue = true
        editor.chooseAction(0)(); XCTAssertEqual(flags(model), [true, true])
        editor.chooseAction(0)(); XCTAssertEqual(flags(model), [false, true])
        editor.chooseAction(0)(); editor.multiple().wrappedValue = false
        XCTAssertEqual(flags(model), [true, false]); XCTAssertEqual(model.coordinator.draft, model.draft)
        XCTAssertTrue(model.draft.advanced.creatorIssues(.qa).isEmpty)
    }
    func testLocalSaveAndFreshRestoreKeepChoicesForExistingRehearsal() throws {
        let store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage())
        let (model, editor, owner) = try setup(store: store)
        editor.multiple().wrappedValue = true; editor.chooseAction(1)()
        let expected = model.draft; model.save(); editor.retire(); model.leave()
        let reopened = TemplateAuthoringModel(coordinator: .init(store: store, currentSession: { owner.session }))
        reopened.load(); reopened.restore()
        let fresh = TemplateQAAnswerEditor(model: reopened)
        XCTAssertEqual(reopened.draft, expected); XCTAssertEqual(fresh.options.map(\.correct), [true, true]); XCTAssertTrue(fresh.isMultiple)
        var rehearsal = TemplateCreatorRehearsal()
        rehearsal.evaluate(.qa, draft: reopened.draft.advanced, selected: ["opt_1", "opt_2"])
        XCTAssertEqual(rehearsal.result, .matched); XCTAssertFalse(reopened.coordinator.canSubmit)
    }
    func testEditingAddingReorderingAndRemovingExistingOptionsRefreshesOverview() throws {
        let (model, editor, _) = try setup()
        model.draft.advanced.setCreatorValue(.qa, path: [.field("options"), .index(1), .field("label")], entry: .string("Renamed"))
        XCTAssertEqual(editor.options[1].label, "Renamed")
        let field = try XCTUnwrap(TemplateCreatorSchema.fields(.qa).first { $0.id == "options" })
        model.draft.advanced.addCreatorRow(.qa, path: [.field("options")], field: field)
        XCTAssertEqual(editor.options.count, 3)
        editor.chooseAction(2)(); XCTAssertEqual(flags(model), [false, false, true])
        var rows = model.draft.advanced.rows("qa", "options"); rows.swapAt(0, 2)
        model.draft.advanced.set("qa", "options", .array(rows)); XCTAssertEqual(flags(model), [true, false, false])
        rows.removeFirst(); model.draft.advanced.set("qa", "options", .array(rows))
        XCTAssertEqual(flags(model), [false, false]); editor.chooseAction(1)(); XCTAssertEqual(flags(model), [false, true])
    }
    func testStaleChoicesAndModeBindingsRejectImmediatelyBeforeOnChangeRuns() throws {
        let (model, editor, _) = try setup(), choose = editor.chooseAction(1), multiple = editor.multiple()
        let original = model.draft
        model.draft.advanced.set("qa", "mode", .string("TYPE"))
        model.draft = original // ABA: same bytes, but a newer publication; no model.changed() call yet.
        choose(); multiple.wrappedValue = true
        XCTAssertEqual(model.draft, original)
        editor.chooseAction(1)(); XCTAssertEqual(flags(model), [false, true])
    }
    func testRetainedChoicesCannotTargetNewRowsAfterReorderOrRemoval() throws {
        for operation in ["reorder", "remove", "rename"] {
            let (model, editor, _) = try setup(), choose = editor.chooseAction(1)
            var rows = model.draft.advanced.rows("qa", "options")
            if operation == "reorder" { rows.swapAt(0, 1) }
            else if operation == "remove" { rows.removeFirst() }
            else { var row = rows[1].object!; row["label"] = .string("Renamed"); rows[1] = .object(row) }
            model.draft.advanced.set("qa", "options", .array(rows))
            let expected = model.draft; choose(); XCTAssertEqual(model.draft, expected, operation)
        }
    }
    func testLoadRestoreDiscardOwnerAndDismissalFenceRetainedCallbacks() throws {
        for operation in ["load", "restore", "discard", "owner", "dismiss", "leave"] {
            let (model, editor, owner) = try setup(), choose = editor.chooseAction(1), multiple = editor.multiple()
            switch operation {
            case "load": model.load()
            case "restore": model.restore()
            case "discard": model.discard()
            case "owner": owner.session = try .init(accountID: 916, namespace: "qa-answer-flow", epoch: 2, authorizationRevision: "member")
            case "leave": model.leave()
            default: editor.retire()
            }
            let expected = model.draft; choose(); multiple.wrappedValue = true
            XCTAssertEqual(model.draft, expected, operation)
        }
    }
    func testReappearanceAcquiresNewControlsWithoutRevivingOldOnes() throws {
        let (model, editor, _) = try setup(), old = editor.chooseAction(1)
        editor.retire(); XCTAssertFalse(editor.canEdit); editor.reload()
        old(); XCTAssertEqual(flags(model), [true, false])
        editor.chooseAction(1)(); XCTAssertEqual(flags(model), [false, true])
        model.load(); editor.reload(); XCTAssertTrue(editor.canEdit)
        editor.chooseAction(0)(); XCTAssertEqual(flags(model), [true, false])
    }
    func testOpeningAndRepeatedSingleSelectionDoNotMutateHistory() throws {
        let (model, editor, _) = try setup(), before = model.draft
        editor.reload(); editor.chooseAction(0)()
        XCTAssertEqual(model.draft, before)
        model.draft.advanced.setCreatorValue(.qa, path: [.field("options"), .index(1), .field("correct")], entry: .bool(true))
        let legacy = model.draft; editor.reload()
        XCTAssertEqual(editor.options.map(\.correct), [true, true]); XCTAssertEqual(model.draft, legacy)
        editor.chooseAction(1)(); XCTAssertEqual(flags(model), [false, true])
    }
    func testDisabledFamilyAndOtherModeRejectControls() throws {
        let (model, editor, _) = try setup()
        model.draft.advanced.setCreatorEnabled(.qa, false)
        let disabled = model.draft; editor.chooseAction(1)(); editor.multiple().wrappedValue = true
        XCTAssertEqual(model.draft, disabled)
        model.draft.advanced.setCreatorEnabled(.qa, true); model.draft.advanced.set("qa", "mode", .string("SHOT"))
        let shot = model.draft; editor.chooseAction(1)(); XCTAssertEqual(model.draft, shot)
    }
    func testDurablePendingWriteLockRejectsAnswerChanges() throws {
        let (seedModel, _, owner) = try setup(), session = try XCTUnwrap(owner.session)
        let store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage()), identity = TemplateAuthoringIdentity(), seed = seedModel.draft
        try store.save(seed, session: session, identity: identity)
        try store.savePending(.init(operationID: UUID(), ownerKey: session.ownerKey, identity: identity,
            request: TemplateAuthoringContract.request(seed, intent: .saveDraft), createdAt: Date()), session: session)
        let model = TemplateAuthoringModel(coordinator: .init(store: store, currentSession: { session })); model.load(); model.draft = seed
        let editor = TemplateQAAnswerEditor(model: model)
        editor.chooseAction(1)(); editor.multiple().wrappedValue = true
        XCTAssertFalse(editor.canEdit); XCTAssertEqual(model.draft, seed)
    }
}

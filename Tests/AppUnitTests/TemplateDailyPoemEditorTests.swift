import XCTest
@testable import Questify

@MainActor final class TemplateDailyPoemEditorTests: XCTestCase {
    private final class Owner { var session: TemplateAuthoringSession?; init(_ value: TemplateAuthoringSession) { session = value } }
    private func setup(store: TemplateAuthoringLocalStore? = nil) throws -> (TemplateAuthoringModel, TemplateDailyPoemController, Owner) {
        let owner = Owner(try .init(accountID: 963, namespace: "daily-poems", epoch: 1, authorizationRevision: "member"))
        let model = TemplateAuthoringModel(coordinator: .init(store: store ?? .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { owner.session }))
        model.load(); model.draft.title = "Poem pool"; model.draft.advanced.setCreatorEnabled(.dailySign, true); model.changed()
        return (model, .init(model: model), owner)
    }
    func testCompleteAddPasteRepeatedEditPreviewAndDeleteFlow() throws {
        let (model, editor, _) = try setup(); editor.addAction()(); let id = try XCTUnwrap(editor.rows.first?.id), binding = editor.text(id)
        binding.wrappedValue = " First \n"; binding.wrappedValue = " First \n\nSecond\n"
        XCTAssertEqual(editor.rows[0].text, " First \n\nSecond\n"); XCTAssertEqual(TemplateDailyPoemPool.lines(editor.rows[0].text), ["First", "Second"])
        XCTAssertTrue(editor.issues.isEmpty); XCTAssertEqual(model.coordinator.draft, model.draft)
        editor.removeAction(id)(); XCTAssertTrue(editor.rows.isEmpty); XCTAssertFalse(editor.issues.isEmpty)
    }
    func testRawOnlyTypingKeepsInputAndRetiresEarlierButtons() throws {
        let (model, editor, _) = try setup(); editor.addAction()(); let id = try XCTUnwrap(editor.rows.first?.id), input = editor.text(id)
        input.wrappedValue = "Line"; let before = model.draft, remove = editor.removeAction(id), add = editor.addAction()
        input.wrappedValue = "Line\n\n"; XCTAssertEqual(model.draft, before); XCTAssertEqual(input.wrappedValue, "Line\n\n")
        remove(); add(); XCTAssertEqual(editor.rows.count, 1); XCTAssertEqual(editor.rows[0].text, "Line\n\n")
    }
    func testParentChangedRefreshDoesNotDiscardRawInputOrInterruptTyping() throws {
        let (model, editor, _) = try setup(); editor.addAction()(); let id = try XCTUnwrap(editor.rows.first?.id), input = editor.text(id)
        input.wrappedValue = " First \n"; let oldRemove = editor.removeAction(id)
        model.changed() // The existing parent onChange(draft) performs this after the editor's own write.
        XCTAssertFalse(editor.needsReload); XCTAssertEqual(input.wrappedValue, " First \n")
        input.wrappedValue = " First \nSecond\n"; XCTAssertEqual(editor.rows.first?.text, " First \nSecond\n")
        oldRemove(); XCTAssertEqual(editor.rows.count, 1)
    }
    func testCanonicallyEquivalentUnicodeEditWritesExactBytesAndKeepsLease() throws {
        let (model, editor, _) = try setup(); editor.addAction()(); let id = try XCTUnwrap(editor.rows.first?.id), input = editor.text(id)
        input.wrappedValue = "\u{00E9}"; input.wrappedValue = "e\u{0301}"
        let stored = model.draft.advanced.value["dailySign"]?.object?["poems"]?.array?.first?.array?.first?.string
        XCTAssertEqual(stored.map { Data($0.utf8) }, Data("e\u{0301}".utf8)); XCTAssertTrue(editor.canEdit)
        XCTAssertEqual(Data(editor.rows[0].text.utf8), Data("e\u{0301}".utf8))
    }
    func testNewRowRetiresOldTextBindingButDoesNotNormalizeVisibleInput() throws {
        let (_, editor, _) = try setup(); editor.addAction()(); let first = try XCTUnwrap(editor.rows.first?.id), old = editor.text(first)
        old.wrappedValue = " First \n"; editor.addAction()(); old.wrappedValue = "Stale"
        XCTAssertEqual(editor.rows[0].text, " First \n"); XCTAssertEqual(editor.rows.count, 2)
        editor.text(first).wrappedValue = "Fresh\n"; XCTAssertEqual(editor.rows[0].text, "Fresh\n")
    }
    func testDeleteInvalidatesRemovedAndNeighborBindingsWithoutRetargeting() throws {
        let (model, editor, _) = try setup(); editor.addAction()(); editor.addAction()()
        let first = editor.rows[0].id, second = editor.rows[1].id, oldFirst = editor.text(first), oldSecond = editor.text(second)
        editor.removeAction(first)(); let before = model.draft
        oldFirst.wrappedValue = "Resurrect"; oldSecond.wrappedValue = "Wrong occurrence"
        XCTAssertEqual(model.draft, before); XCTAssertEqual(editor.rows.map(\.id), [second])
    }
    func testExternalPublicationNeedsExplicitReloadAndRejectsOldRawDraft() throws {
        let (model, editor, _) = try setup(); editor.addAction()(); let id = try XCTUnwrap(editor.rows.first?.id), old = editor.text(id), remove = editor.removeAction(id)
        old.wrappedValue = "Line\n"; model.draft.advanced.set("dailySign", "signer", .string("Other")); let before = model.draft
        XCTAssertTrue(editor.needsReload); XCTAssertTrue(editor.rows.isEmpty); old.wrappedValue = "Stale"; remove(); XCTAssertEqual(model.draft, before)
        editor.reload(); XCTAssertFalse(editor.needsReload); XCTAssertEqual(editor.rows.first?.text, "Line"); XCTAssertTrue(editor.canEdit)
    }
    func testSameValueABACannotReviveRetainedActionsOrInput() throws {
        let (model, editor, _) = try setup(); editor.addAction()(); let id = try XCTUnwrap(editor.rows.first?.id), input = editor.text(id), add = editor.addAction(), before = model.draft
        model.draft.advanced.set("dailySign", "signer", .string("Other")); model.draft = before
        input.wrappedValue = "Stale"; add(); XCTAssertEqual(model.draft, before); XCTAssertTrue(editor.needsReload)
        editor.reload(); XCTAssertEqual(editor.rows.count, 1)
    }
    func testMalformedExternalDataRemainsPreservedAfterReload() throws {
        let (model, editor, _) = try setup(); model.draft.advanced.set("dailySign", "poems", .string("legacy")); let before = model.draft
        editor.reload(); editor.addAction()(); XCTAssertFalse(editor.isSupported); XCTAssertFalse(editor.canEdit); XCTAssertEqual(model.draft, before)
    }
    func testLoadRestoreDiscardOwnerLeaveAndDismissFenceAllControls() throws {
        for operation in ["load", "restore", "discard", "owner", "leave", "dismiss"] {
            let (model, editor, owner) = try setup(); editor.addAction()(); let id = try XCTUnwrap(editor.rows.first?.id), input = editor.text(id), add = editor.addAction()
            switch operation {
            case "load": model.load()
            case "restore": model.restore()
            case "discard": model.discard()
            case "owner": owner.session = try .init(accountID: 964, namespace: "daily-poems", epoch: 2, authorizationRevision: "member")
            case "leave": model.leave()
            default: editor.retire()
            }
            let before = model.draft; input.wrappedValue = "Stale"; add(); XCTAssertEqual(model.draft, before, operation)
            if operation == "leave" {
                XCTAssertFalse(editor.canEdit); model.load()
                input.wrappedValue = "Revived"; add(); XCTAssertEqual(model.draft, before)
                let fresh = TemplateDailyPoemController(model: model)
                XCTAssertTrue(fresh.canEdit); let freshID = try XCTUnwrap(fresh.rows.first?.id)
                fresh.text(freshID).wrappedValue = "Fresh after return"
                XCTAssertEqual(fresh.rows.first?.text, "Fresh after return")
            }
        }
    }
    func testDismissalAndReopenUsesCanonicalTextAndFreshBindings() throws {
        let (model, editor, _) = try setup(); editor.addAction()(); let id = try XCTUnwrap(editor.rows.first?.id), old = editor.text(id)
        old.wrappedValue = " Line \n\n"; editor.retire(); editor.reload(); let before = model.draft
        old.wrappedValue = "Stale"; XCTAssertEqual(model.draft, before); XCTAssertEqual(editor.rows.first?.text, "Line")
        let newID = try XCTUnwrap(editor.rows.first?.id); XCTAssertNotEqual(newID, id); editor.text(newID).wrappedValue = "Fresh\n"
        XCTAssertEqual(editor.rows.first?.text, "Fresh\n")
    }
    func testLocalSaveRestorePersistsOnlyCanonicalPoems() throws {
        let store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage()), (model, editor, owner) = try setup(store: store)
        editor.addAction()(); let id = try XCTUnwrap(editor.rows.first?.id); editor.text(id).wrappedValue = " First \n\nSecond\n"
        let expected = model.draft; model.save(); editor.retire(); model.leave()
        let reopened = TemplateAuthoringModel(coordinator: .init(store: store, currentSession: { owner.session })); reopened.load(); reopened.restore()
        let fresh = TemplateDailyPoemController(model: reopened)
        XCTAssertEqual(reopened.draft, expected); XCTAssertEqual(fresh.rows.first?.text, "First\nSecond"); XCTAssertFalse(reopened.coordinator.canSubmit)
    }
    func testPendingLockDeniesPoemWrites() throws {
        let (seedModel, seedEditor, owner) = try setup(), session = try XCTUnwrap(owner.session)
        seedEditor.addAction()(); let seedID = try XCTUnwrap(seedEditor.rows.first?.id)
        seedEditor.text(seedID).wrappedValue = "A valid pending poem"
        XCTAssertTrue(seedModel.draft.advanced.enabled("dailySign")); XCTAssertTrue(seedModel.draft.advanced.issues.isEmpty)
        let store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage()), identity = TemplateAuthoringIdentity(), seed = seedModel.draft
        try store.save(seed, session: session, identity: identity)
        try store.savePending(.init(operationID: UUID(), ownerKey: session.ownerKey, identity: identity,
            request: TemplateAuthoringContract.request(seed, intent: .saveDraft), createdAt: Date()), session: session)
        let model = TemplateAuthoringModel(coordinator: .init(store: store, currentSession: { session })); model.load(); model.draft = seed
        XCTAssertNotNil(model.coordinator.pending); XCTAssertTrue(model.coordinator.locked)
        let editor = TemplateDailyPoemController(model: model); editor.addAction()(); XCTAssertFalse(editor.canEdit); XCTAssertEqual(model.draft, seed)
    }
}

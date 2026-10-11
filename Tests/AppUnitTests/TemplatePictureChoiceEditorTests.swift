import XCTest
@testable import Questify

@MainActor final class TemplatePictureChoiceEditorTests: XCTestCase {
    private final class Owner { var session: TemplateAuthoringSession?; init(_ value: TemplateAuthoringSession) { session = value } }
    private func setup(store: TemplateAuthoringLocalStore? = nil) throws -> (TemplateAuthoringModel, TemplatePictureChoiceController, Owner) {
        let owner = Owner(try .init(accountID: 972, namespace: "picture-choices", epoch: 1, authorizationRevision: "member"))
        let model = TemplateAuthoringModel(coordinator: .init(store: store ?? .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { owner.session }))
        model.load(); model.draft.title = "Picture choices"; model.draft.advanced.setCreatorEnabled(.pricePair, true); model.draft.advanced.set("pricePair", "title", .string("Pick one"))
        for index in 0..<3 {
            model.draft.advanced.setCreatorValue(.pricePair, path: [.field("items"), .index(index), .field("id")], entry: .string("items_\(index + 1)"))
            model.draft.advanced.setCreatorValue(.pricePair, path: [.field("items"), .index(index), .field("name")], entry: .string("Picture \(index + 1)"))
            model.draft.advanced.setCreatorValue(.pricePair, path: [.field("items"), .index(index), .field("correct")], entry: .bool(false))
        }
        model.changed(); return (model, .init(model: model), owner)
    }
    func testCompleteAddEditSelectMoveRemoveFlowUpdatesCoordinator() throws {
        let (model, editor, _) = try setup(); editor.addAction()(); let row = try XCTUnwrap(editor.rows.last)
        editor.text(row.id, field: .name).wrappedValue = "Tea"; editor.text(row.id, field: .imageURL).wrappedValue = "/media/tea.jpg"
        editor.chooseAction(row.id)(); XCTAssertEqual(editor.correctCount, 1); XCTAssertTrue(editor.issues.isEmpty)
        editor.moveAction(row.id, by: -1)(); XCTAssertEqual(editor.rows[2].id, row.id); XCTAssertTrue(editor.rows[2].isCorrect)
        editor.removeAction(editor.rows[0].id)(); XCTAssertEqual(editor.rows.count, 3); XCTAssertEqual(editor.correctCount, 1)
        XCTAssertEqual(model.coordinator.draft, model.draft)
    }
    func testSelectingCurrentAnswerRemainsSelectedAndInvalidatesOldButtons() throws {
        let (model, editor, _) = try setup(); let id = editor.rows[1].id; editor.chooseAction(id)()
        let before = model.draft, oldRemove = editor.removeAction(id); editor.chooseAction(id)(); oldRemove()
        XCTAssertEqual(model.draft, before); XCTAssertEqual(editor.rows.count, 3); XCTAssertTrue(editor.rows[1].isCorrect)
    }
    func testContinuousTextInputSurvivesParentChangedRefresh() throws {
        let (model, editor, _) = try setup(); let id = editor.rows[0].id, binding = editor.text(id, field: .name)
        binding.wrappedValue = "T"; let oldChoose = editor.chooseAction(id); model.changed()
        XCTAssertFalse(editor.needsReload); binding.wrappedValue = "Tea"; oldChoose()
        XCTAssertEqual(editor.rows[0].name, "Tea"); XCTAssertEqual(editor.correctCount, 0); XCTAssertTrue(editor.canEdit)
    }
    func testUnicodeEquivalentInputWritesExactBytes() throws {
        let (model, editor, _) = try setup(); let binding = editor.text(editor.rows[0].id, field: .name)
        binding.wrappedValue = "\u{00E9}"; binding.wrappedValue = "e\u{0301}"
        XCTAssertEqual(Data(editor.rows[0].name.utf8), Data("e\u{0301}".utf8)); XCTAssertTrue(editor.canEdit)
        let stored = model.draft.advanced.value["pricePair"]?.object?["items"]?.array?.first?.object?["name"]?.string
        XCTAssertEqual(stored.map { Data($0.utf8) }, Data("e\u{0301}".utf8))
    }
    func testRemoveSelectedLeavesExplicitValidationAndNoReplacement() throws {
        let (_, editor, _) = try setup(); let id = editor.rows[0].id; editor.chooseAction(id)(); editor.removeAction(id)()
        XCTAssertEqual(editor.correctCount, 0); XCTAssertFalse(editor.issues.isEmpty); XCTAssertEqual(editor.rows.count, 2)
    }
    func testStructuralActionsRetireBindingsWithoutRetargeting() throws {
        for action in ["add", "choose", "move", "remove"] {
            let (model, editor, _) = try setup(); let id = editor.rows[1].id, binding = editor.text(id, field: .name)
            switch action {
            case "add": editor.addAction()()
            case "choose": editor.chooseAction(id)()
            case "move": editor.moveAction(id, by: -1)()
            default: editor.removeAction(id)()
            }
            let before = model.draft; binding.wrappedValue = "Stale"; XCTAssertEqual(model.draft, before, action)
        }
    }
    func testExternalDraftChangesRequireReloadAndRejectStaleActions() throws {
        let (model, editor, _) = try setup(); let id = editor.rows[0].id, input = editor.text(id, field: .name), choose = editor.chooseAction(id)
        model.draft.advanced.set("pricePair", "title", .string("Other")); let before = model.draft
        XCTAssertTrue(editor.needsReload); XCTAssertTrue(editor.rows.isEmpty); input.wrappedValue = "Stale"; choose(); XCTAssertEqual(model.draft, before)
        editor.reload(); XCTAssertFalse(editor.needsReload); XCTAssertEqual(editor.rows.count, 3); XCTAssertTrue(editor.canEdit)
    }
    func testSameValueABADoesNotReviveRetainedBindingsOrButtons() throws {
        let (model, editor, _) = try setup(); let id = editor.rows[0].id, input = editor.text(id, field: .name), choose = editor.chooseAction(id), before = model.draft
        model.draft.advanced.set("pricePair", "title", .string("Other")); model.draft = before
        input.wrappedValue = "Stale"; choose(); XCTAssertEqual(model.draft, before); XCTAssertTrue(editor.needsReload)
    }
    func testMalformedExternalRowsArePreservedAfterReload() throws {
        let (model, editor, _) = try setup(); model.draft.advanced.set("pricePair", "items", .string("legacy")); let before = model.draft
        editor.reload(); editor.addAction()(); XCTAssertFalse(editor.isSupported); XCTAssertFalse(editor.canEdit); XCTAssertEqual(model.draft, before)
    }
    func testLoadRestoreDiscardOwnerLeaveAndDismissFenceWrites() throws {
        for operation in ["load", "restore", "discard", "owner", "leave", "dismiss"] {
            let (model, editor, owner) = try setup(); let id = editor.rows[0].id, binding = editor.text(id, field: .name), choose = editor.chooseAction(id), add = editor.addAction()
            switch operation {
            case "load": model.load()
            case "restore": model.restore()
            case "discard": model.discard()
            case "owner": owner.session = try .init(accountID: 973, namespace: "picture-choices", epoch: 2, authorizationRevision: "member")
            case "leave": model.leave()
            default: editor.retire()
            }
            let before = model.draft; binding.wrappedValue = "Stale"; choose(); add(); XCTAssertEqual(model.draft, before, operation)
        }
    }
    func testReopenKeepsWireAnswerAndUsesFreshLocalRowIdentities() throws {
        let (model, editor, _) = try setup(); let first = editor.rows[0], old = editor.chooseAction(first.id)
        editor.chooseAction(first.id)(); editor.retire(); editor.reload(); let before = model.draft; old()
        XCTAssertEqual(model.draft, before); XCTAssertNotEqual(editor.rows[0].id, first.id); XCTAssertEqual(editor.rows[0].wireID, first.wireID); XCTAssertTrue(editor.rows[0].isCorrect)
    }
    func testLocalSaveRestoreRetainsSelectedAnswerAndMediaAddress() throws {
        let store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage()), (model, editor, owner) = try setup(store: store)
        let row = editor.rows[2]; editor.text(row.id, field: .imageURL).wrappedValue = "/media/choice.jpg"; editor.chooseAction(row.id)()
        let expected = model.draft; model.save(); editor.retire(); model.leave()
        let reopened = TemplateAuthoringModel(coordinator: .init(store: store, currentSession: { owner.session })); reopened.load(); reopened.restore()
        let fresh = TemplatePictureChoiceController(model: reopened)
        XCTAssertEqual(reopened.draft, expected); XCTAssertEqual(fresh.rows.filter(\.isCorrect).map(\.wireID), [row.wireID]); XCTAssertEqual(fresh.rows[2].imageURL, "/media/choice.jpg"); XCTAssertFalse(reopened.coordinator.canSubmit)
    }
    func testPendingLockDeniesPictureEdits() throws {
        let (seedModel, _, owner) = try setup(), session = try XCTUnwrap(owner.session)
        let store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage()), identity = TemplateAuthoringIdentity(), seed = seedModel.draft
        try store.save(seed, session: session, identity: identity)
        try store.savePending(.init(operationID: UUID(), ownerKey: session.ownerKey, identity: identity,
            request: TemplateAuthoringContract.request(seed, intent: .saveDraft), createdAt: Date()), session: session)
        let model = TemplateAuthoringModel(coordinator: .init(store: store, currentSession: { session })); model.load(); model.draft = seed
        let editor = TemplatePictureChoiceController(model: model); editor.addAction()(); XCTAssertFalse(editor.canEdit); XCTAssertEqual(model.draft, seed)
    }
}

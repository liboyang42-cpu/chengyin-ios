import XCTest
@testable import Questify

@MainActor final class TemplateMultiplayerPlanEditorTests: XCTestCase {
    private final class Owner { var session: TemplateAuthoringSession?; init(_ value: TemplateAuthoringSession) { session = value } }
    private func setup(store: TemplateAuthoringLocalStore? = nil) throws -> (TemplateAuthoringModel, TemplateMultiplayerPlanController, Owner) {
        let owner = Owner(try .init(accountID: 975, namespace: "multiplayer-plan", epoch: 1, authorizationRevision: "member"))
        let model = TemplateAuthoringModel(coordinator: .init(store: store ?? .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { owner.session }))
        model.load(); model.draft.title = "Team plan"; model.draft.advanced.setCreatorEnabled(.multiplayer, true); model.changed()
        return (model, .init(model: model), owner)
    }
    func testCompleteRoleEditBulkOrderReferenceAndRemoveFlow() throws {
        let (model, editor, _) = try setup(); editor.addAction()(); let role = try XCTUnwrap(editor.roles.last)
        editor.text(role.id, field: .identifier).wrappedValue = "scout"; editor.text(role.id, field: .label).wrappedValue = "Scout"
        editor.text(role.id, field: .minimum).wrappedValue = "0"; editor.text(role.id, field: .maximum).wrappedValue = "1"
        editor.orderInput().wrappedValue = " player，scout\nplayer, "
        XCTAssertTrue(editor.issues.isEmpty); XCTAssertEqual(editor.turns.map(\.roleID), ["player", "scout", "player"]); XCTAssertTrue(editor.turns.allSatisfy(\.resolvesUniquely))
        editor.moveAction(role.id, by: -1)(); XCTAssertEqual(editor.roles[0].id, role.id); XCTAssertEqual(editor.turns.map(\.roleID), ["player", "scout", "player"])
        editor.removeAction(role.id)(); XCTAssertFalse(editor.turns[1].resolvesUniquely); editor.orderInput().wrappedValue = "player"
        XCTAssertTrue(editor.issues.isEmpty); XCTAssertEqual(model.coordinator.draft, model.draft)
    }
    func testContinuousOrderAndRoleTypingSurvivesParentChangedRefresh() throws {
        let (model, editor, _) = try setup(); let order = editor.orderInput(), name = editor.text(editor.roles[0].id, field: .label)
        order.wrappedValue = "player, "; name.wrappedValue = "T"; model.changed()
        XCTAssertFalse(editor.needsReload); XCTAssertEqual(order.wrappedValue, "player, ")
        order.wrappedValue = "player, player, "; name.wrappedValue = "Team"
        XCTAssertEqual(editor.turns.count, 2); XCTAssertEqual(editor.roles[0].label, "Team"); XCTAssertEqual(order.wrappedValue, "player, player, ")
    }
    func testRawOnlyOrderChangeRetiresButtonsWithoutWritingDifferentModel() throws {
        let (model, editor, _) = try setup(); let before = model.draft, oldAdd = editor.addAction(), oldRemove = editor.removeAction(editor.roles[0].id)
        editor.orderInput().wrappedValue = "player,\n "; oldAdd(); oldRemove()
        XCTAssertEqual(model.draft, before); XCTAssertEqual(editor.roles.count, 1); XCTAssertEqual(editor.orderInput().wrappedValue, "player,\n ")
    }
    func testNumericTypingRetainsIncompleteAndLeadingZeroText() throws {
        let (model, editor, _) = try setup(); let binding = editor.text(editor.roles[0].id, field: .minimum)
        binding.wrappedValue = "-"; XCTAssertEqual(binding.wrappedValue, "-"); XCTAssertFalse(editor.issues.isEmpty)
        binding.wrappedValue = "01"; model.changed(); XCTAssertEqual(binding.wrappedValue, "01"); XCTAssertTrue(editor.issues.isEmpty)
    }
    func testRenamingRoleDoesNotSilentlyRepairExistingTurnReferences() throws {
        let (model, editor, _) = try setup(); let originalOrder = model.draft.advanced.value["multiplayer"]?.object?["turnOrder"]
        editor.text(editor.roles[0].id, field: .identifier).wrappedValue = "scout"
        XCTAssertEqual(model.draft.advanced.value["multiplayer"]?.object?["turnOrder"], originalOrder); XCTAssertFalse(editor.turns[0].resolvesUniquely)
        editor.orderInput().wrappedValue = "scout"; XCTAssertTrue(editor.turns[0].resolvesUniquely); XCTAssertTrue(editor.issues.isEmpty)
    }
    func testStructuralActionsRetireRoleAndOrderBindings() throws {
        for action in ["add", "remove", "move"] {
            let (model, editor, _) = try setup(); editor.addAction()(); let id = editor.roles[1].id, roleInput = editor.text(id, field: .label), orderInput = editor.orderInput()
            switch action { case "add": editor.addAction()(); case "remove": editor.removeAction(id)(); default: editor.moveAction(id, by: -1)() }
            let before = model.draft; roleInput.wrappedValue = "Stale"; orderInput.wrappedValue = "stale"; XCTAssertEqual(model.draft, before, action)
        }
    }
    func testExternalPublicationRequiresReloadAndRejectsRetainedInputs() throws {
        let (model, editor, _) = try setup(); let roleInput = editor.text(editor.roles[0].id, field: .label), order = editor.orderInput(), add = editor.addAction()
        model.draft.advanced.set("multiplayer", "unitScore", .number(3)); let before = model.draft
        XCTAssertTrue(editor.needsReload); roleInput.wrappedValue = "Stale"; order.wrappedValue = "stale"; add(); XCTAssertEqual(model.draft, before)
        editor.reload(); XCTAssertFalse(editor.needsReload); XCTAssertEqual(editor.roles.count, 1); XCTAssertTrue(editor.canEdit)
    }
    func testEqualValueABACannotReviveOldControls() throws {
        let (model, editor, _) = try setup(); let order = editor.orderInput(), add = editor.addAction(), before = model.draft
        model.draft.advanced.set("multiplayer", "unitScore", .number(3)); model.draft = before
        order.wrappedValue = "stale"; add(); XCTAssertEqual(model.draft, before); XCTAssertTrue(editor.needsReload)
    }
    func testMalformedExternalOrderStaysUntouchedAfterReload() throws {
        let (model, editor, _) = try setup(); model.draft.advanced.set("multiplayer", "turnOrder", .string("legacy")); let before = model.draft
        editor.reload(); editor.orderInput().wrappedValue = "player"; editor.addAction()(); XCTAssertFalse(editor.canEdit); XCTAssertFalse(editor.isSupported); XCTAssertEqual(model.draft, before)
    }
    func testLoadRestoreDiscardOwnerLeaveAndDismissFenceAllInputs() throws {
        for operation in ["load", "restore", "discard", "owner", "leave", "dismiss"] {
            let (model, editor, owner) = try setup(); let role = editor.text(editor.roles[0].id, field: .label), order = editor.orderInput(), add = editor.addAction()
            switch operation {
            case "load": model.load()
            case "restore": model.restore()
            case "discard": model.discard()
            case "owner": owner.session = try .init(accountID: 976, namespace: "multiplayer-plan", epoch: 2, authorizationRevision: "member")
            case "leave": model.leave()
            default: editor.retire()
            }
            let before = model.draft; role.wrappedValue = "Stale"; order.wrappedValue = "stale"; add(); XCTAssertEqual(model.draft, before, operation)
            if operation == "leave" {
                XCTAssertFalse(editor.canEdit); model.load()
                role.wrappedValue = "Revived"; order.wrappedValue = "revived"; add(); XCTAssertEqual(model.draft, before)
                let fresh = TemplateMultiplayerPlanController(model: model)
                XCTAssertTrue(fresh.canEdit); let freshID = try XCTUnwrap(fresh.roles.first?.id)
                fresh.text(freshID, field: .label).wrappedValue = "Fresh after return"
                XCTAssertEqual(fresh.roles.first?.label, "Fresh after return")
            }
        }
    }
    func testReopeningUsesCanonicalOrderAndFreshLocalRoleIdentity() throws {
        let (model, editor, _) = try setup(); let oldID = editor.roles[0].id, input = editor.orderInput()
        input.wrappedValue = "player, player, "; editor.retire(); editor.reload(); let before = model.draft; input.wrappedValue = "stale"
        XCTAssertEqual(model.draft, before); XCTAssertEqual(editor.orderInput().wrappedValue, "player, player"); XCTAssertNotEqual(editor.roles[0].id, oldID)
    }
    func testLocalSaveRestorePersistsWireRolesAndOrderOnly() throws {
        let store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage()), (model, editor, owner) = try setup(store: store)
        editor.orderInput().wrappedValue = "player，player\n"; let expected = model.draft
        model.save(); editor.retire(); model.leave()
        let reopened = TemplateAuthoringModel(coordinator: .init(store: store, currentSession: { owner.session })); reopened.load(); reopened.restore()
        let fresh = TemplateMultiplayerPlanController(model: reopened)
        XCTAssertEqual(reopened.draft, expected); XCTAssertEqual(fresh.turns.map(\.roleID), ["player", "player"]); XCTAssertEqual(fresh.orderInput().wrappedValue, "player, player"); XCTAssertFalse(reopened.coordinator.canSubmit)
    }
    func testPendingLockDeniesRoleAndOrderWrites() throws {
        let (seedModel, _, owner) = try setup(), session = try XCTUnwrap(owner.session)
        let store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage()), identity = TemplateAuthoringIdentity(), seed = seedModel.draft
        try store.save(seed, session: session, identity: identity)
        try store.savePending(.init(operationID: UUID(), ownerKey: session.ownerKey, identity: identity, request: TemplateAuthoringContract.request(seed, intent: .saveDraft), createdAt: Date()), session: session)
        let model = TemplateAuthoringModel(coordinator: .init(store: store, currentSession: { session })); model.load(); model.draft = seed
        let editor = TemplateMultiplayerPlanController(model: model); editor.addAction()(); editor.orderInput().wrappedValue = "stale"
        XCTAssertFalse(editor.canEdit); XCTAssertEqual(model.draft, seed)
    }
}

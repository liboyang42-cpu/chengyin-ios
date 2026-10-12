import XCTest
import Combine
@testable import Questify

@MainActor final class TemplateLocalCategoryRemovalViewTests: XCTestCase {
    private final class Owner {
        var session: TemplateAuthoringSession?
        init(_ session: TemplateAuthoringSession) { self.session = session }
    }
    private func setup(raw: String = "7,3,9", visible: Bool = true, store: TemplateAuthoringLocalStore? = nil) throws -> (TemplateAuthoringModel, TemplateLocalCategoryRemovalController, Owner) {
        let owner = Owner(try .init(accountID: 1015, namespace: "local-categories", epoch: 1, authorizationRevision: "member"))
        let model = TemplateAuthoringModel(coordinator: .init(store: store ?? .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { owner.session }))
        model.load(); model.draft.title = "Saved categories"; model.draft.activityCategoryids = raw; model.draft.categoryId = 88; model.changed()
        let controller = TemplateLocalCategoryRemovalController(model: model)
        if visible { controller.viewAppeared(sceneIsActive: true) }
        return (model, controller, owner)
    }
    func testNilReaderLocalRemovalHasOnePublicationAndNoRequestAuthority() throws {
        let (model, controller, _) = try setup(); var emitted: [TemplateAuthoringDraft] = []
        let observation = model.$draft.dropFirst().sink { emitted.append($0) }; defer { observation.cancel() }
        XCTAssertTrue(controller.canEdit); controller.removeAction(3)()
        XCTAssertEqual(emitted.count, 1); XCTAssertEqual(model.draft.activityCategoryids, "7,9")
        XCTAssertEqual(model.draft.categoryId, 88); XCTAssertFalse(model.coordinator.canSubmit)
    }
    func testRepeatedAndOldRemovalCannotChangeReplacementSelection() throws {
        let (model, controller, _) = try setup(), old = controller.removeAction(3)
        old(); old(); XCTAssertEqual(model.draft.activityCategoryids, "7,9")
        model.draft.activityCategoryids = "3,8"; model.changed(); controller.reload(); old()
        XCTAssertEqual(model.draft.activityCategoryids, "3,8")
        controller.removeAction(3)(); XCTAssertEqual(model.draft.activityCategoryids, "8")
    }
    func testHiddenSceneAndReloadDoNotReactivateOldRemoval() throws {
        let (model, controller, _) = try setup(), before = model.draft, old = controller.removeAction(3)
        controller.viewDisappeared(); controller.sceneChanged(isActive: true); controller.reload()
        XCTAssertFalse(controller.canRead); XCTAssertFalse(controller.canReload)
        old(); controller.removeAction(3)(); XCTAssertEqual(model.draft, before)
        controller.viewAppeared(sceneIsActive: true); old(); XCTAssertEqual(model.draft, before)
        controller.removeAction(3)(); XCTAssertEqual(model.draft.activityCategoryids, "7,9")
    }
    func testInactiveAndRepeatedVisibleAppearancesRespectCurrentLease() throws {
        let (model, controller, _) = try setup(visible: false)
        controller.viewAppeared(sceneIsActive: false); controller.reload(); XCTAssertFalse(controller.canEdit)
        let inactive = controller.removeAction(3); controller.sceneChanged(isActive: true)
        inactive(); XCTAssertEqual(model.draft.activityCategoryids, "7,3,9")
        let current = controller.removeAction(3); controller.viewAppeared(sceneIsActive: true)
        current(); XCTAssertEqual(model.draft.activityCategoryids, "7,9")
    }
    func testBusyABARetiresOldActionButFreshLocalActionWorks() throws {
        let (model, controller, _) = try setup(), old = controller.removeAction(3)
        model.busy = true; XCTAssertFalse(controller.canEdit); model.busy = false
        old(); XCTAssertEqual(model.draft.activityCategoryids, "7,3,9")
        controller.removeAction(3)(); XCTAssertEqual(model.draft.activityCategoryids, "7,9")
    }
    func testDraftABARetiresOldActionWithoutNormalizingRaw() throws {
        let (model, controller, _) = try setup(raw: " 7, 3 ,9 "), before = model.draft, old = controller.removeAction(3)
        model.draft.description = "Other"; model.draft = before; old()
        XCTAssertEqual(model.draft, before)
        controller.removeAction(3)(); XCTAssertEqual(model.draft.activityCategoryids, "7,9")
    }
    func testOwnerChangeCannotReloadOrRemoveAnotherDraft() throws {
        let (model, controller, owner) = try setup(), before = model.draft, old = controller.removeAction(3)
        owner.session = try .init(accountID: 1016, namespace: "local-categories", epoch: 2, authorizationRevision: "member")
        controller.reload(); old(); XCTAssertEqual(model.draft, before); XCTAssertFalse(controller.canReload)
        model.load(); controller.viewAppeared(sceneIsActive: true); XCTAssertFalse(controller.canRead)
    }
    func testMalformedSelectionAndUnknownIDRemainUnchanged() throws {
        let (model, controller, _) = try setup(raw: "7,unknown"), before = model.draft
        XCTAssertTrue(controller.canRead); XCTAssertFalse(controller.isSupported); XCTAssertEqual(controller.visibleRaw, "7,unknown")
        controller.removeAction(7)(); XCTAssertEqual(model.draft, before)
        model.draft.activityCategoryids = "7,3"; model.changed(); controller.reload()
        controller.removeAction(99)(); XCTAssertEqual(model.draft.activityCategoryids, "7,3")
    }
    func testExistingLocalSaveRestoreKeepsOnlyRequestedRemoval() throws {
        let store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage())
        let (model, controller, owner) = try setup(store: store); controller.removeAction(3)(); let expected = model.draft
        model.save(); model.leave()
        let reopened = TemplateAuthoringModel(coordinator: .init(store: store, currentSession: { owner.session }))
        reopened.load(); reopened.restore(); XCTAssertEqual(reopened.draft, expected); XCTAssertFalse(reopened.coordinator.canSubmit)
    }
    func testPendingWriteLockStillBlocksVisibleLocalRemoval() throws {
        let (seedModel, _, owner) = try setup(), session = try XCTUnwrap(owner.session), identity = TemplateAuthoringIdentity()
        let store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage()), seed = seedModel.draft
        try store.save(seed, session: session, identity: identity)
        try store.savePending(.init(operationID: UUID(), ownerKey: session.ownerKey, identity: identity, request: TemplateAuthoringContract.request(seed, intent: .saveDraft), createdAt: Date()), session: session)
        let model = TemplateAuthoringModel(coordinator: .init(store: store, currentSession: { session })); model.load(); model.draft = seed
        let controller = TemplateLocalCategoryRemovalController(model: model); controller.viewAppeared(sceneIsActive: true)
        XCTAssertFalse(controller.canEdit); controller.removeAction(3)(); XCTAssertEqual(model.draft, seed)
    }
}

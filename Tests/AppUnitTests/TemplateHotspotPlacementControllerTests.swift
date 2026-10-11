import XCTest
@testable import Questify

@MainActor final class TemplateHotspotPlacementControllerTests: XCTestCase {
    private final class Owner { var session: TemplateAuthoringSession?; init(_ value: TemplateAuthoringSession) { session = value } }
    private func setup(store: TemplateAuthoringLocalStore? = nil) throws -> (TemplateAuthoringModel, TemplateHotspotPlacementController, Owner) {
        let owner = Owner(try .init(accountID: 930, namespace: "hotspot-placement", epoch: 1, authorizationRevision: "member"))
        let model = TemplateAuthoringModel(coordinator: .init(store: store ?? .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { owner.session }))
        model.load(); model.draft.title = "Target configuration"; model.draft.advanced.setCreatorEnabled(.hiddenObject, true)
        model.draft.advanced.set("hiddenObject", "title", .string("Find cats")); model.draft.advanced.set("hiddenObject", "imageUrl", .string("https://images.example.com/scene.jpg"))
        for index in 0..<3 { model.draft.advanced.setRow("hiddenObject", "hotspots", index: index, key: "label", text: "Cat \(index)") }
        model.changed(); return (model, .init(model: model), owner)
    }
    @discardableResult private func loaded(_ editor: TemplateHotspotPlacementController) throws -> TemplateHotspotPlacementController.SceneRequest {
        editor.loadSceneAction()(); let request = try XCTUnwrap(editor.scene); editor.imageReady(request); return request
    }
    func testCompleteLoadSelectPlaceAddRenameRemoveFlow() throws {
        let (model, editor, _) = try setup(); XCTAssertNil(editor.scene); try loaded(editor)
        editor.armAction("spot_1")(); editor.placementAction()(100, 50, 300, 200)
        XCTAssertEqual(editor.targets[0].point?.x, 0.3333); XCTAssertNil(editor.armedID); XCTAssertTrue(editor.isSceneReady)
        editor.addAction()(); let new = try XCTUnwrap(editor.targets.last?.id); editor.label(new).wrappedValue = "Window cat"
        editor.armAction(new)(); editor.placementAction()(10, 20, 100, 100); XCTAssertEqual(editor.targets.last?.point?.y, 0.2)
        editor.removeAction(new)(); XCTAssertEqual(editor.targets.count, 3); XCTAssertEqual(model.coordinator.draft, model.draft)
    }
    func testParentDraftChangeNotificationPreservesImageAfterPlacementAndRename() throws {
        let (model, editor, _) = try setup(); let request = try loaded(editor)
        editor.armAction("spot_1")(); editor.placementAction()(25, 50, 100, 100)
        model.changed() // The parent Form observes the already-applied child draft.
        XCTAssertEqual(editor.scene?.id, request.id); XCTAssertTrue(editor.isSceneReady)
        XCTAssertEqual(editor.targets[0].point?.x, 0.25)
        editor.label("spot_1").wrappedValue = "Window cat"
        model.changed()
        XCTAssertEqual(editor.scene?.id, request.id); XCTAssertTrue(editor.isSceneReady)
        XCTAssertEqual(editor.targets[0].label, "Window cat")
    }
    func testExternalModuleDisableRetiresLoadedImageAndOldCallback() throws {
        let (model, editor, _) = try setup(); let request = try loaded(editor)
        model.draft.advanced.setCreatorEnabled(.hiddenObject, false); model.changed()
        editor.imageReady(request)
        XCTAssertNil(editor.scene); XCTAssertFalse(editor.isSceneReady)
    }
    func testNoImageNoSelectionOrZeroGeometryCannotPlace() throws {
        let (model, editor, _) = try setup(), before = model.draft
        editor.armAction("spot_1")(); editor.placementAction()(20, 20, 100, 100); XCTAssertEqual(model.draft, before)
        try loaded(editor); editor.placementAction()(20, 20, 100, 100); XCTAssertEqual(model.draft, before)
        editor.armAction("spot_1")(); editor.placementAction()(20, 20, 0, 100)
        XCTAssertEqual(model.draft, before); XCTAssertEqual(editor.armedID, "spot_1")
    }
    func testSelectAgainCancelsAndOldCanvasCallbackCannotMoveNewSelection() throws {
        let (model, editor, _) = try setup(); try loaded(editor)
        editor.armAction("spot_1")(); let stale = editor.placementAction(); editor.armAction("spot_1")(); XCTAssertNil(editor.armedID)
        editor.armAction("spot_2")(); let before = model.draft; stale(10, 10, 100, 100); XCTAssertEqual(model.draft, before)
        editor.placementAction()(10, 10, 100, 100); XCTAssertEqual(editor.targets[1].point?.x, 0.1)
    }
    func testPlacementIsOneShotEvenIfTapCallbackIsRetained() throws {
        let (model, editor, _) = try setup(); try loaded(editor); editor.armAction("spot_1")()
        let tap = editor.placementAction(); tap(10, 10, 100, 100); let before = model.draft
        tap(90, 90, 100, 100); XCTAssertEqual(model.draft, before)
    }
    func testImageFailureRetryAndOldImageCallbackStayFenced() throws {
        let (_, editor, _) = try setup(); let first = try loaded(editor); editor.armAction("spot_1")()
        editor.imageFailed(first); XCTAssertFalse(editor.isSceneReady); XCTAssertNil(editor.armedID)
        editor.loadSceneAction()(); let retry = try XCTUnwrap(editor.scene)
        editor.imageReady(first); XCTAssertFalse(editor.isSceneReady)
        editor.imageReady(retry); XCTAssertTrue(editor.isSceneReady)
    }
    func testSceneChangeAndSameValueABAClearSelectionAndRequest() throws {
        let (model, editor, _) = try setup(); let old = try loaded(editor); editor.armAction("spot_1")(); let tap = editor.placementAction(), before = model.draft
        model.draft.advanced.set("hiddenObject", "imageUrl", .string("https://images.example.com/next.jpg")); model.draft = before
        XCTAssertNil(editor.scene); XCTAssertNil(editor.armedID); editor.imageReady(old); tap(90, 90, 100, 100)
        XCTAssertEqual(model.draft, before); XCTAssertFalse(editor.isSceneReady)
    }
    func testRepeatedLabelTypingKeepsImageButRetiresOldButtonsAndPlacement() throws {
        let (model, editor, _) = try setup(); try loaded(editor); editor.armAction("spot_1")()
        let tap = editor.placementAction(), add = editor.addAction(), label = editor.label("spot_1")
        label.wrappedValue = "Window"; label.wrappedValue = "Window cat"; let before = model.draft
        tap(90, 90, 100, 100); add(); XCTAssertEqual(model.draft, before)
        XCTAssertTrue(editor.isSceneReady); XCTAssertEqual(editor.targets[0].label, "Window cat"); XCTAssertNil(editor.armedID)
    }
    func testOwnReorderPreservesLoadedSceneButDisarmsAndRetiresCallbacks() throws {
        let (model, editor, _) = try setup(); try loaded(editor); editor.armAction("spot_1")()
        let tap = editor.placementAction(), label = editor.label("spot_1")
        editor.moveAction("spot_1", to: 2)(); let before = model.draft
        tap(90, 90, 100, 100); label.wrappedValue = "Wrong"
        XCTAssertEqual(model.draft, before); XCTAssertEqual(editor.targets.last?.id, "spot_1")
        XCTAssertTrue(editor.isSceneReady); XCTAssertNil(editor.armedID)
    }
    func testExternalTargetReorderAndRemovalRetireLabelBindings() throws {
        let (model, editor, _) = try setup(); try loaded(editor)
        let label = editor.label("spot_1"); model.draft.advanced.moveRow("hiddenObject", "hotspots", from: 0, to: 1)
        let before = model.draft; label.wrappedValue = "Stale"; XCTAssertEqual(model.draft, before); XCTAssertNil(editor.scene)
        editor.addAction()(); let new = try XCTUnwrap(editor.targets.last?.id), old = editor.label(new)
        editor.removeAction(new)(); let removed = model.draft; old.wrappedValue = "Resurrect"; XCTAssertEqual(model.draft, removed)
    }
    func testLifecycleOwnerAndMediaChangesDenyRetainedCallbacks() throws {
        for action in ["load", "restore", "discard", "owner", "leave", "dismiss"] {
            let (model, editor, owner) = try setup(); let request = try loaded(editor); editor.armAction("spot_1")()
            let tap = editor.placementAction(), label = editor.label("spot_1")
            switch action {
            case "load": model.load()
            case "restore": model.restore()
            case "discard": model.discard()
            case "owner": owner.session = try .init(accountID: 931, namespace: "hotspot-placement", epoch: 2, authorizationRevision: "member")
            case "leave": model.leave()
            default: editor.retire()
            }
            let before = model.draft; editor.imageReady(request); tap(90, 90, 100, 100); label.wrappedValue = "Stale"
            XCTAssertEqual(model.draft, before, action); XCTAssertFalse(editor.isSceneReady, action)
        }
    }
    func testLocalSaveRestoreRetainsPositionsButNeverRestoresImageOrArming() throws {
        let store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage())
        let (model, editor, owner) = try setup(store: store); try loaded(editor); editor.armAction("spot_1")(); editor.placementAction()(1, 1, 3, 10)
        let expected = model.draft; model.save(); editor.retire(); model.leave()
        let reopened = TemplateAuthoringModel(coordinator: .init(store: store, currentSession: { owner.session })); reopened.load(); reopened.restore()
        let fresh = TemplateHotspotPlacementController(model: reopened)
        XCTAssertEqual(reopened.draft, expected); XCTAssertEqual(fresh.targets[0].point?.x, 0.3333); XCTAssertNil(fresh.scene); XCTAssertNil(fresh.armedID)
        XCTAssertFalse(reopened.coordinator.canSubmit)
    }
    func testPendingWriteLockDeniesSceneAndTargetEdits() throws {
        let (seedModel, _, owner) = try setup(), session = try XCTUnwrap(owner.session)
        let store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage()), identity = TemplateAuthoringIdentity(), seed = seedModel.draft
        try store.save(seed, session: session, identity: identity)
        try store.savePending(.init(operationID: UUID(), ownerKey: session.ownerKey, identity: identity,
            request: TemplateAuthoringContract.request(seed, intent: .saveDraft), createdAt: Date()), session: session)
        let model = TemplateAuthoringModel(coordinator: .init(store: store, currentSession: { session })); model.load(); model.draft = seed
        let editor = TemplateHotspotPlacementController(model: model); editor.loadSceneAction()(); editor.addAction()()
        XCTAssertFalse(editor.canEdit); XCTAssertNil(editor.scene); XCTAssertEqual(model.draft, seed)
    }
}

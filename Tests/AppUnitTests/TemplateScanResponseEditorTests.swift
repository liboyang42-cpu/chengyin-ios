import XCTest
@testable import Questify

/// Image callbacks are explicit simulated inputs, not image networking or AR execution.
@MainActor final class TemplateScanResponseEditorTests: XCTestCase {
    private final class Owner { var session: TemplateAuthoringSession?; init(_ value: TemplateAuthoringSession) { session = value } }
    private func setup(store: TemplateAuthoringLocalStore? = nil) throws -> (TemplateAuthoringModel, TemplateScanResponseController, Owner) {
        let owner = Owner(try .init(accountID: 989, namespace: "scan-response", epoch: 1, authorizationRevision: "member"))
        let model = TemplateAuthoringModel(coordinator: .init(store: store ?? .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { owner.session }))
        model.load(); model.draft.title = "Scan"; model.draft.advanced.setCreatorEnabled(.scan, true)
        for (key, value) in ["kind":"OVERLAY", "reply":"Hello", "imageUrl":"https://example.invalid/image.png", "overlayUrl":"https://example.invalid/overlay.png", "arMode":"MARKER", "markerUrl":"/marker.png", "modelUrl":"/model.glb"] { model.draft.advanced.set("scan", key, .string(value)) }
        model.draft.advanced.set("scan", "overlayScale", .number(60)); model.changed(); return (model, .init(model: model), owner)
    }
    func testOverlayConfigureLoadSizeClearAndSaveFlow() throws {
        let (model, editor, _) = try setup(); XCTAssertNil(editor.scene); editor.loadAction()(); let request = try XCTUnwrap(editor.scene); editor.imageReady(request)
        editor.scaleInput().wrappedValue = 75; XCTAssertEqual(editor.widthPercent, 75); XCTAssertEqual(editor.scene?.id, request.id)
        editor.clearModelAction()(); XCTAssertEqual(model.draft.advanced.text("scan", "modelUrl"), ""); XCTAssertEqual(editor.scene?.id, request.id)
        editor.saveAction()(); XCTAssertEqual(model.coordinator.draft, model.draft); XCTAssertEqual(editor.previewState, .ready)
    }
    func testInitReloadAndAddressEditsNeverAutomaticallyLoad() throws {
        let (_, editor, _) = try setup(); editor.reload(); XCTAssertNil(editor.scene)
        editor.textInput(.overlayUrl).wrappedValue = "/outline.png"; XCTAssertFalse(editor.canLoad); XCTAssertNil(editor.scene); XCTAssertTrue(editor.canEdit)
        editor.textInput(.overlayUrl).wrappedValue = "https://example.invalid/new.png"; XCTAssertTrue(editor.canLoad); XCTAssertNil(editor.scene)
    }
    func testModeSwitchFencesOldInputsAndShowsRetainedARConflicts() throws {
        let (model, editor, _) = try setup(); editor.loadAction()(); let request = try XCTUnwrap(editor.scene), oldInput = editor.textInput(.overlayUrl), oldSlider = editor.scaleInput()
        editor.kindInput().wrappedValue = .text; let before = model.draft; oldInput.wrappedValue = "stale"; oldSlider.wrappedValue = 25; editor.imageReady(request)
        XCTAssertEqual(model.draft, before); XCTAssertNil(editor.scene); XCTAssertTrue(editor.showsRetainedAR); XCTAssertTrue(editor.retainedFields.contains(.modelUrl)); XCTAssertFalse(editor.issues.isEmpty)
        editor.arModeInput().wrappedValue = .none; XCTAssertTrue(editor.retainedFields.contains(.modelUrl)); editor.clearModelAction()(); XCTAssertTrue(editor.issues.isEmpty)
    }
    func testARModePreservesDataAndExplicitClearRetiresOldModelInput() throws {
        let (model, editor, _) = try setup(), old = editor.textInput(.modelUrl); editor.arModeInput().wrappedValue = .plane
        XCTAssertEqual(model.draft.advanced.text("scan", "markerUrl"), "/marker.png"); XCTAssertEqual(model.draft.advanced.text("scan", "modelUrl"), "/model.glb")
        old.wrappedValue = "stale"; XCTAssertEqual(model.draft.advanced.text("scan", "modelUrl"), "/model.glb")
        let beforeClear = editor.textInput(.modelUrl); editor.clearModelAction()(); beforeClear.wrappedValue = "/restore.glb"; XCTAssertEqual(model.draft.advanced.text("scan", "modelUrl"), "")
    }
    func testContinuousRawTypingAndParentRefreshPreserveCurrentPreview() throws {
        let (model, editor, _) = try setup(); editor.loadAction()(); let request = try XCTUnwrap(editor.scene); editor.imageReady(request)
        let input = editor.textInput(.reply), slider = editor.scaleInput(); input.wrappedValue = "Hello\n"; input.wrappedValue = "Hello\nworld"; model.changed(); slider.wrappedValue = 65; slider.wrappedValue = 70
        XCTAssertEqual(input.wrappedValue, "Hello\nworld"); XCTAssertEqual(editor.widthPercent, 70); XCTAssertEqual(editor.scene?.id, request.id); XCTAssertFalse(editor.needsReload)
    }
    func testReferenceChangeFencesLoadedImageAndOldSlider() throws {
        let (model, editor, _) = try setup(); editor.loadAction()(); let request = try XCTUnwrap(editor.scene), oldSlider = editor.scaleInput(), oldLoad = editor.loadAction()
        let input = editor.textInput(.overlayUrl); input.wrappedValue = "https://example.invalid/n"; input.wrappedValue = "https://example.invalid/new.png"; let before = model.draft
        oldSlider.wrappedValue = 25; oldLoad(); editor.imageReady(request); XCTAssertEqual(model.draft, before); XCTAssertNil(editor.scene)
        editor.loadAction()(); XCTAssertNotEqual(editor.scene?.id, request.id)
    }
    func testRetryAndStaleImageCallbacksUseRequestIdentity() throws {
        let (_, editor, _) = try setup(); editor.loadAction()(); let first = try XCTUnwrap(editor.scene); editor.imageFailed(first); XCTAssertEqual(editor.previewState, .failed)
        editor.loadAction()(); let second = try XCTUnwrap(editor.scene); editor.imageReady(first); XCTAssertEqual(editor.previewState, .loading)
        editor.imageReady(second); editor.imageFailed(first); XCTAssertEqual(editor.previewState, .ready)
    }
    func testImageUsesFullWidthAndVoiceDoesNotStartPlayback() throws {
        let (_, editor, _) = try setup(); editor.kindInput().wrappedValue = .image; XCTAssertEqual(editor.widthPercent, 100); editor.loadAction()(); XCTAssertNotNil(editor.scene)
        editor.kindInput().wrappedValue = .voice; editor.textInput(.audioUrl).wrappedValue = "/voice.m4a"; editor.loadAction()(); XCTAssertNil(editor.scene); XCTAssertFalse(editor.canLoad); XCTAssertTrue(editor.currentFields.contains(.audioUrl))
    }
    func testExternalDraftABARequiresReloadAndCannotReviveOldRequest() throws {
        let (model, editor, _) = try setup(); editor.loadAction()(); let request = try XCTUnwrap(editor.scene), before = model.draft, clear = editor.clearModelAction()
        model.draft.title = "Other"; model.draft = before; clear(); editor.imageReady(request); XCTAssertEqual(model.draft, before); XCTAssertNil(editor.scene); XCTAssertTrue(editor.needsReload)
        editor.reload(); XCTAssertTrue(editor.canEdit); XCTAssertNil(editor.scene)
    }
    func testOwnerLoadRestoreDiscardLeaveAndBackgroundFenceEverything() throws {
        for operation in ["load", "restore", "discard", "owner", "leave", "dismiss", "background"] {
            let (model, editor, owner) = try setup(); editor.loadAction()(); let request = try XCTUnwrap(editor.scene), input = editor.textInput(.reply), clear = editor.clearModelAction()
            switch operation {
            case "load": model.load()
            case "restore": model.restore()
            case "discard": model.discard()
            case "owner": owner.session = try .init(accountID: 990, namespace: "scan-response", epoch: 2, authorizationRevision: "member")
            case "leave": model.leave()
            case "background": editor.suspend()
            default: editor.retire()
            }
            let before = model.draft; input.wrappedValue = "stale"; clear(); editor.imageReady(request); XCTAssertEqual(model.draft, before, operation); XCTAssertNil(editor.scene, operation)
        }
    }
    func testBusyABARetiresRequestEvenAfterUnlock() throws {
        let (model, editor, _) = try setup(); editor.loadAction()(); let request = try XCTUnwrap(editor.scene), input = editor.textInput(.reply)
        model.busy = true; model.busy = false; let before = model.draft; input.wrappedValue = "stale"; editor.imageReady(request)
        XCTAssertEqual(model.draft, before); XCTAssertNil(editor.scene); XCTAssertTrue(editor.needsReload); editor.reload(); XCTAssertTrue(editor.canEdit); XCTAssertNil(editor.scene)
    }
    func testUnsupportedExternalShapeNeverDrivesSliderOrMutation() throws {
        let (model, editor, _) = try setup(); model.draft.advanced.set("scan", "overlayScale", .number(1e30)); let before = model.draft; editor.reload()
        XCTAssertFalse(editor.isSupported); XCTAssertEqual(editor.widthPercent, 100); editor.scaleInput().wrappedValue = 60; editor.clearModelAction()(); editor.loadAction()(); XCTAssertEqual(model.draft, before); XCTAssertNil(editor.scene)
    }
    func testLocalSaveRestoreRetainsExactConfigurationWithoutPreview() throws {
        let store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage()), (model, editor, owner) = try setup(store: store)
        editor.textInput(.reply).wrappedValue = "\u{00E9}\ne\u{0301}"; editor.scaleInput().wrappedValue = 85; editor.clearModelAction()(); let expected = model.draft
        editor.saveAction()(); editor.retire(); model.leave()
        let reopened = TemplateAuthoringModel(coordinator: .init(store: store, currentSession: { owner.session })); reopened.load(); reopened.restore()
        let fresh = TemplateScanResponseController(model: reopened); XCTAssertEqual(reopened.draft, expected); XCTAssertEqual(fresh.widthPercent, 85); XCTAssertNil(fresh.scene); XCTAssertFalse(reopened.coordinator.canSubmit)
    }
    func testPendingWriteLockDeniesEditorAndImageLoading() throws {
        let (seedModel, _, owner) = try setup(), session = try XCTUnwrap(owner.session)
        let store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage()), identity = TemplateAuthoringIdentity(), seed = seedModel.draft
        try store.save(seed, session: session, identity: identity)
        try store.savePending(.init(operationID: UUID(), ownerKey: session.ownerKey, identity: identity, request: TemplateAuthoringContract.request(seed, intent: .saveDraft), createdAt: Date()), session: session)
        let model = TemplateAuthoringModel(coordinator: .init(store: store, currentSession: { session })); model.load(); model.draft = seed
        let editor = TemplateScanResponseController(model: model); editor.loadAction()(); editor.clearModelAction()(); XCTAssertFalse(editor.canEdit); XCTAssertNil(editor.scene); XCTAssertEqual(model.draft, seed)
    }
}

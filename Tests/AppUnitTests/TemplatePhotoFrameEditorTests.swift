import XCTest
@testable import Questify

/// Request callbacks below are simulated unit inputs, not image-network or SwiftUI rendering tests.
@MainActor final class TemplatePhotoFrameEditorTests: XCTestCase {
    private final class Owner { var session: TemplateAuthoringSession?; init(_ value: TemplateAuthoringSession) { session = value } }
    private func setup(store: TemplateAuthoringLocalStore? = nil) throws -> (TemplateAuthoringModel, TemplatePhotoFrameController, Owner) {
        let owner = Owner(try .init(accountID: 986, namespace: "photo-frame", epoch: 1, authorizationRevision: "member"))
        let model = TemplateAuthoringModel(coordinator: .init(store: store ?? .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { owner.session }))
        model.load(); model.draft.title = "Frame"; model.draft.advanced.setCreatorEnabled(.photoCheck, true)
        model.draft.advanced.set("photoCheck", "title", .string("Window")); model.draft.advanced.set("photoCheck", "requirement", .string("Window in frame"))
        model.draft.advanced.set("photoCheck", "frameUrl", .string("https://example.invalid/frame.png")); model.draft.advanced.set("photoCheck", "frameOpacity", .number(40)); model.changed()
        return (model, .init(model: model), owner)
    }
    func testExplicitLoadAdjustOpacityAndClearFullFlow() throws {
        let (model, editor, _) = try setup(); XCTAssertNil(editor.scene); editor.loadAction()(); let request = try XCTUnwrap(editor.scene)
        XCTAssertEqual(editor.previewState, .loading); editor.imageReady(request); XCTAssertEqual(editor.previewState, .ready)
        editor.opacityInput().wrappedValue = 65; XCTAssertEqual(editor.opacity, 65); XCTAssertEqual(editor.scene?.id, request.id); XCTAssertEqual(editor.previewState, .ready)
        editor.clearAction()(); XCTAssertEqual(editor.reference, ""); XCTAssertEqual(editor.opacity, 65); XCTAssertNil(editor.scene); XCTAssertEqual(editor.previewState, .idle)
        editor.imageReady(request); XCTAssertEqual(editor.previewState, .idle); XCTAssertEqual(model.coordinator.draft, model.draft)
    }
    func testInitReloadAndAddressEditingNeverAutomaticallyStartPreview() throws {
        let (_, editor, _) = try setup(); XCTAssertNil(editor.scene); editor.reload(); XCTAssertNil(editor.scene)
        editor.referenceInput().wrappedValue = "https://example.invalid/new.png"; XCTAssertTrue(editor.canLoad); XCTAssertNil(editor.scene)
        editor.referenceInput().wrappedValue = "/frames/new.png"; XCTAssertFalse(editor.canLoad); XCTAssertTrue(editor.canEdit); XCTAssertTrue(editor.canClear)
    }
    func testParentChangedRefreshAndContinuousSliderKeepLoadedRequest() throws {
        let (model, editor, _) = try setup(); editor.loadAction()(); let request = try XCTUnwrap(editor.scene); editor.imageReady(request)
        let slider = editor.opacityInput(); slider.wrappedValue = 45; let oldClear = editor.clearAction(); model.changed()
        XCTAssertFalse(editor.needsReload); XCTAssertEqual(editor.scene?.id, request.id); XCTAssertEqual(editor.previewState, .ready)
        slider.wrappedValue = 50; slider.wrappedValue = 55; oldClear(); XCTAssertEqual(editor.opacity, 55); XCTAssertEqual(editor.scene?.id, request.id)
    }
    func testFailureRetryCreatesNewRequestAndRejectsLateOldCallback() throws {
        let (_, editor, _) = try setup(); editor.loadAction()(); let first = try XCTUnwrap(editor.scene); editor.imageFailed(first); XCTAssertEqual(editor.previewState, .failed)
        editor.loadAction()(); let second = try XCTUnwrap(editor.scene); XCTAssertNotEqual(second.id, first.id)
        editor.imageReady(first); XCTAssertEqual(editor.previewState, .loading); editor.imageReady(second); XCTAssertEqual(editor.previewState, .ready)
        editor.imageFailed(first); XCTAssertEqual(editor.previewState, .ready)
    }
    func testURLChangeRetiresImageAndOldSliderButAllowsContinuedAddressTyping() throws {
        let (model, editor, _) = try setup(); editor.loadAction()(); let request = try XCTUnwrap(editor.scene), slider = editor.opacityInput(), input = editor.referenceInput()
        input.wrappedValue = "https://example.invalid/n"; input.wrappedValue = "https://example.invalid/new.png"; model.changed()
        XCTAssertEqual(input.wrappedValue, "https://example.invalid/new.png"); XCTAssertNil(editor.scene); XCTAssertFalse(editor.needsReload)
        let before = model.draft; slider.wrappedValue = 90; editor.imageReady(request); XCTAssertEqual(model.draft, before); XCTAssertEqual(editor.previewState, .idle)
        editor.loadAction()(); XCTAssertNotEqual(editor.scene?.id, request.id)
    }
    func testClearRetiresReferenceInputSliderAndCapturedLoad() throws {
        let (model, editor, _) = try setup(); let input = editor.referenceInput(), slider = editor.opacityInput(), load = editor.loadAction()
        editor.clearAction()(); let before = model.draft; input.wrappedValue = "https://example.invalid/stale.png"; slider.wrappedValue = 90; load()
        XCTAssertEqual(model.draft, before); XCTAssertNil(editor.scene); XCTAssertFalse(editor.canAdjustOpacity)
    }
    func testExternalDraftChangeRequiresReloadBeforeAnyNewPreview() throws {
        let (model, editor, _) = try setup(); editor.loadAction()(); let request = try XCTUnwrap(editor.scene), load = editor.loadAction(), input = editor.referenceInput()
        model.draft.advanced.set("photoCheck", "title", .string("Other")); let before = model.draft
        XCTAssertTrue(editor.needsReload); XCTAssertNil(editor.scene); load(); input.wrappedValue = "stale"; editor.imageReady(request); XCTAssertEqual(model.draft, before)
        editor.reload(); XCTAssertFalse(editor.needsReload); XCTAssertNil(editor.scene); editor.loadAction()(); XCTAssertNotEqual(editor.scene?.id, request.id)
    }
    func testEqualDraftABACannotReviveOldImageOrActions() throws {
        let (model, editor, _) = try setup(); editor.loadAction()(); let request = try XCTUnwrap(editor.scene), before = model.draft, clear = editor.clearAction()
        model.draft.advanced.set("photoCheck", "title", .string("Other")); model.draft = before
        editor.imageReady(request); clear(); XCTAssertEqual(model.draft, before); XCTAssertNil(editor.scene); XCTAssertTrue(editor.needsReload)
    }
    func testLoadRestoreDiscardOwnerLeaveDismissAndBackgroundFenceRequests() throws {
        for operation in ["load", "restore", "discard", "owner", "leave", "dismiss", "background"] {
            let (model, editor, owner) = try setup(); editor.loadAction()(); let request = try XCTUnwrap(editor.scene), clear = editor.clearAction(), input = editor.referenceInput()
            switch operation {
            case "load": model.load()
            case "restore": model.restore()
            case "discard": model.discard()
            case "owner": owner.session = try .init(accountID: 987, namespace: "photo-frame", epoch: 2, authorizationRevision: "member")
            case "leave": model.leave()
            case "background": editor.suspend()
            default: editor.retire()
            }
            let before = model.draft; editor.imageReady(request); clear(); input.wrappedValue = "stale"; XCTAssertEqual(model.draft, before, operation); XCTAssertNil(editor.scene, operation)
        }
    }
    func testUnsupportedExternalOpacityKeepsDataAndDisablesSpecializedControls() throws {
        let (model, editor, _) = try setup(); model.draft.advanced.set("photoCheck", "frameOpacity", .number(1e30)); let before = model.draft
        editor.reload(); editor.clearAction()(); editor.opacityInput().wrappedValue = 50; editor.loadAction()()
        XCTAssertFalse(editor.isSupported); XCTAssertFalse(editor.canEdit); XCTAssertNil(editor.scene); XCTAssertEqual(model.draft, before)
    }
    func testExactUnicodeReferenceEditRetiresRequestAndPersistsBytes() throws {
        let (model, editor, _) = try setup(); let input = editor.referenceInput()
        input.wrappedValue = "https://example.invalid/\u{00E9}.png"; editor.loadAction()(); let request = try XCTUnwrap(editor.scene)
        input.wrappedValue = "https://example.invalid/e\u{0301}.png"
        XCTAssertNil(editor.scene); XCTAssertTrue(editor.canEdit); XCTAssertEqual(Data(editor.reference.utf8), Data("https://example.invalid/e\u{0301}.png".utf8))
        editor.imageReady(request); XCTAssertEqual(editor.previewState, .idle); XCTAssertEqual(model.draft.advanced.text("photoCheck", "frameUrl").utf8.count, editor.reference.utf8.count)
    }
    func testReopenDoesNotAutoloadAndOldCallbacksStayRetired() throws {
        let (_, editor, _) = try setup(); editor.loadAction()(); let old = try XCTUnwrap(editor.scene)
        editor.retire(); editor.reload(); editor.imageReady(old); XCTAssertNil(editor.scene); XCTAssertEqual(editor.previewState, .idle)
        editor.loadAction()(); XCTAssertNotEqual(editor.scene?.id, old.id)
    }
    func testLocalSaveRestoreRetainsFrameFieldsButNotPreviewRequests() throws {
        let store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage()), (model, editor, owner) = try setup(store: store)
        editor.referenceInput().wrappedValue = "/frames/outline.png"; editor.opacityInput().wrappedValue = 75; let expected = model.draft
        model.save(); editor.retire(); model.leave()
        let reopened = TemplateAuthoringModel(coordinator: .init(store: store, currentSession: { owner.session })); reopened.load(); reopened.restore()
        let fresh = TemplatePhotoFrameController(model: reopened); XCTAssertEqual(reopened.draft, expected); XCTAssertEqual(fresh.reference, "/frames/outline.png"); XCTAssertEqual(fresh.opacity, 75); XCTAssertNil(fresh.scene); XCTAssertFalse(reopened.coordinator.canSubmit)
    }
    func testPendingLockDeniesImageLoadingAndFrameWrites() throws {
        let (seedModel, _, owner) = try setup(), session = try XCTUnwrap(owner.session)
        let store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage()), identity = TemplateAuthoringIdentity(), seed = seedModel.draft
        try store.save(seed, session: session, identity: identity)
        try store.savePending(.init(operationID: UUID(), ownerKey: session.ownerKey, identity: identity, request: TemplateAuthoringContract.request(seed, intent: .saveDraft), createdAt: Date()), session: session)
        let model = TemplateAuthoringModel(coordinator: .init(store: store, currentSession: { session })); model.load(); model.draft = seed
        let editor = TemplatePhotoFrameController(model: model); editor.loadAction()(); editor.clearAction()(); XCTAssertFalse(editor.canEdit); XCTAssertNil(editor.scene); XCTAssertEqual(model.draft, seed)
    }
}

import XCTest
@testable import Questify

@MainActor final class TemplateAdditionalSampleBrowserTests: XCTestCase {
    private final class Owner {
        var session: TemplateAuthoringSession?
        init(_ value: TemplateAuthoringSession) { session = value }
    }
    private func setup() throws -> (TemplateAuthoringModel, TemplateAdditionalSampleBrowserController, Owner) {
        let owner = Owner(try .init(accountID: 999, namespace: "sample-coverage", epoch: 1, authorizationRevision: "member"))
        let model = TemplateAuthoringModel(coordinator: .init(store: .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { owner.session }))
        model.load(); model.draft.title = "Keep original"; model.changed()
        let controller = TemplateAdditionalSampleBrowserController(model: model)
        controller.viewAppeared(sceneIsActive: true)
        return (model, controller, owner)
    }
    func testFourChoicesDoNotWriteOriginalOrStoredDraft() throws {
        let (model, controller, _) = try setup(), before = model.draft, stored = model.coordinator.draft
        for choice in TemplateAdditionalSamplePreview.Choice.allCases {
            controller.openAction(choice)(); XCTAssertNotNil(controller.visiblePresentation, choice.rawValue); controller.close()
        }
        XCTAssertEqual(model.draft, before); XCTAssertEqual(model.coordinator.draft, stored)
    }
    func testD20PreviewDoesNotSwitchRealEditorMode() throws {
        let (model, controller, _) = try setup(); controller.openAction(.d20)()
        XCTAssertEqual(controller.visiblePresentation?.sample.draft.diceMode, "d20"); XCTAssertEqual(model.draft.advanced.diceMode, "d6")
    }
    func testCloseAndReopenCreateIndependentIdentity() throws {
        let (_, controller, _) = try setup(); controller.openAction(.dice)(); let first = try XCTUnwrap(controller.presentation?.id)
        controller.close(); controller.openAction(.dice)(); XCTAssertNotEqual(controller.presentation?.id, first)
    }
    func testCapturedOldOpenCannotRunAfterCloseOrDraftABA() throws {
        let (model, controller, _) = try setup(), open = controller.openAction(.predict), before = model.draft
        model.draft.title = "Changed"; model.draft = before; open(); XCTAssertNil(controller.presentation)
        let next = controller.openAction(.predict); next(); controller.close(); next(); XCTAssertNil(controller.presentation)
    }
    func testOldSwipeAndCloseCannotDismissNewSample() throws {
        let (_, controller, _) = try setup(); controller.openAction(.predict)(); let id = try XCTUnwrap(controller.presentation?.id)
        let binding = controller.presentationBinding, close = controller.closeAction(id)
        controller.close(); controller.openAction(.pricePair)(); let newer = try XCTUnwrap(controller.presentation?.id)
        binding.wrappedValue = nil; close(); XCTAssertEqual(controller.presentation?.id, newer)
    }
    func testCurrentSwipeAndModelChangesReleaseSnapshot() throws {
        let (model, controller, _) = try setup(); controller.openAction(.dice)(); controller.presentationBinding.wrappedValue = nil
        XCTAssertNil(controller.presentation); controller.openAction(.d20)(); model.draft.description = "New"; XCTAssertNil(controller.presentation)
    }
    func testBusyReviewAndBackgroundFenceActions() throws {
        let (model, controller, _) = try setup(); controller.openAction(.predict)(); model.busy = true; model.busy = false
        XCTAssertNil(controller.presentation); controller.openAction(.predict)(); model.prepare(.saveDraft); XCTAssertNil(controller.visiblePresentation)
        model.cancel(); controller.reload(); let open = controller.openAction(.dice); controller.retire(); open(); XCTAssertNil(controller.presentation)
    }
    func testOwnerMismatchHidesSampleAndBlocksNewActions() throws {
        let (_, controller, owner) = try setup(); controller.openAction(.pricePair)()
        owner.session = try .init(accountID: 1000, namespace: "sample-coverage", epoch: 2, authorizationRevision: "member")
        XCTAssertNil(controller.visiblePresentation); XCTAssertFalse(controller.canBrowse)
    }
    func testReloadAndLeaveRetireExistingSample() throws {
        for operation in ["load", "leave", "changed"] {
            let (model, controller, _) = try setup(); controller.openAction(.dice)()
            switch operation { case "load": model.load(); case "leave": model.leave(); default: model.changed() }
            XCTAssertNil(controller.visiblePresentation, operation)
        }
    }
    func testInvalidDiceShowsUnavailableWithoutRepairingDraft() throws {
        let (model, controller, _) = try setup(); model.draft.advanced.set("diceRoll", "diceCount", .number(3)); let before = model.draft
        controller.openAction(.dice)(); XCTAssertTrue(controller.unavailable); XCTAssertNil(controller.presentation); XCTAssertEqual(model.draft, before)
    }
    func testHiddenSceneAndMediaCannotReactivateOrReuseOldOpen() throws {
        let (_, controller, _) = try setup(), oldOpen = controller.openAction(.predict)
        controller.viewDisappeared()
        XCTAssertFalse(controller.isVisible); XCTAssertFalse(controller.canBrowse)
        controller.sceneChanged(isActive: false); controller.sceneChanged(isActive: true)
        controller.mediaChanged(sceneIsActive: true); controller.reload(); oldOpen()
        XCTAssertFalse(controller.isVisible); XCTAssertFalse(controller.canBrowse); XCTAssertNil(controller.presentation)
        controller.viewAppeared(sceneIsActive: true); oldOpen()
        XCTAssertTrue(controller.canBrowse); XCTAssertNil(controller.presentation)
        controller.openAction(.predict)(); XCTAssertNotNil(controller.visiblePresentation)
    }
    func testInactiveAppearanceRequiresForegroundAndFencesOldOpen() throws {
        let (_, controller, _) = try setup(), oldOpen = controller.openAction(.predict)
        controller.viewDisappeared(); controller.viewAppeared(sceneIsActive: false)
        XCTAssertTrue(controller.isVisible); XCTAssertFalse(controller.canBrowse)
        controller.mediaChanged(sceneIsActive: false); controller.openAction(.predict)()
        XCTAssertNil(controller.presentation)
        controller.sceneChanged(isActive: true); oldOpen()
        XCTAssertTrue(controller.canBrowse); XCTAssertNil(controller.presentation)
        controller.openAction(.predict)(); XCTAssertNotNil(controller.visiblePresentation)
    }
    func testRepeatedVisibleAppearancePreservesSheetAndOldDismissCannotCrossHiddenReentry() throws {
        let (_, controller, _) = try setup(); controller.openAction(.predict)()
        let first = try XCTUnwrap(controller.presentation?.id), binding = controller.presentationBinding
        let close = controller.closeAction(first)
        controller.viewAppeared(sceneIsActive: true); controller.sceneChanged(isActive: true)
        XCTAssertEqual(controller.presentation?.id, first); XCTAssertNotNil(controller.visiblePresentation)
        controller.viewDisappeared(); XCTAssertNil(controller.presentation)
        controller.sceneChanged(isActive: true); controller.mediaChanged(sceneIsActive: true)
        XCTAssertFalse(controller.canBrowse)
        controller.viewAppeared(sceneIsActive: true); controller.openAction(.pricePair)()
        let fresh = try XCTUnwrap(controller.presentation?.id); XCTAssertNotEqual(fresh, first)
        binding.wrappedValue = nil; close(); controller.close(expected: first)
        XCTAssertEqual(controller.presentation?.id, fresh); XCTAssertNotNil(controller.visiblePresentation)
    }

}

extension TemplateAdditionalSampleBrowserTests {
    func testPresentationBindingReadsOnlyCapturedIdentityIncludingInitialNilAndSameChoiceReopen() throws {
        let (_, controller, _) = try setup()
        let initiallyEmpty = controller.presentationBinding
        XCTAssertNil(initiallyEmpty.wrappedValue)
        controller.openAction(.predict)()
        let first = try XCTUnwrap(controller.visiblePresentation?.id)
        let old = controller.presentationBinding
        XCTAssertEqual(old.wrappedValue?.id, first)
        XCTAssertNil(initiallyEmpty.wrappedValue)
        controller.close(); controller.openAction(.predict)()
        let second = try XCTUnwrap(controller.visiblePresentation?.id)
        XCTAssertNotEqual(second, first)
        XCTAssertNil(old.wrappedValue); XCTAssertNil(initiallyEmpty.wrappedValue)
        let current = controller.presentationBinding
        XCTAssertEqual(current.wrappedValue?.id, second)
        old.wrappedValue = nil; initiallyEmpty.wrappedValue = nil
        XCTAssertEqual(controller.visiblePresentation?.id, second)
        XCTAssertEqual(current.wrappedValue?.id, second)
        current.wrappedValue = nil
        XCTAssertNil(controller.presentation); XCTAssertNil(current.wrappedValue)
    }
    func testPresentationBindingUsesVisibleLeaseAndCannotReadHiddenOwnerReentry() throws {
        let (_, controller, owner) = try setup()
        let originalOwner = owner.session
        controller.openAction(.predict)()
        let first = try XCTUnwrap(controller.visiblePresentation?.id)
        let old = controller.presentationBinding
        XCTAssertEqual(old.wrappedValue?.id, first)
        // This owner change has no parent Published event. The stored item remains,
        // so the getter itself must apply visiblePresentation's exact owner fence.
        owner.session = try .init(accountID: 1000, namespace: "sample-coverage", epoch: 2, authorizationRevision: "member")
        XCTAssertEqual(controller.presentation?.id, first)
        XCTAssertNil(controller.visiblePresentation); XCTAssertNil(old.wrappedValue)
        controller.viewDisappeared()
        controller.sceneChanged(isActive: false); controller.sceneChanged(isActive: true)
        XCTAssertFalse(controller.isVisible); XCTAssertNil(old.wrappedValue)
        owner.session = originalOwner
        controller.viewAppeared(sceneIsActive: true); controller.openAction(.predict)()
        let second = try XCTUnwrap(controller.visiblePresentation?.id)
        XCTAssertNotEqual(second, first); XCTAssertNil(old.wrappedValue)
        XCTAssertEqual(controller.presentationBinding.wrappedValue?.id, second)
        old.wrappedValue = nil
        XCTAssertEqual(controller.visiblePresentation?.id, second)
    }
}

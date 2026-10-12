import XCTest
@testable import Questify

@MainActor final class TemplateSampleBrowserViewTests: XCTestCase {
    private final class Owner {
        var session: TemplateAuthoringSession?
        init(_ value: TemplateAuthoringSession) { session = value }
    }
    private func setup() throws -> (TemplateAuthoringModel, TemplateSampleBrowserController, Owner) {
        let owner = Owner(try .init(accountID: 999, namespace: "sample-browser", epoch: 1, authorizationRevision: "member"))
        let model = TemplateAuthoringModel(coordinator: .init(store: .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { owner.session }))
        model.load(); model.draft.title = "Keep original"; model.changed()
        let controller = TemplateSampleBrowserController(model: model)
        controller.viewAppeared(sceneIsActive: true)
        return (model, controller, owner)
    }
    func testBrowseBeforePublishValidationWithoutSavingExample() throws {
        let (model, controller, _) = try setup(), before = model.draft, stored = model.coordinator.draft
        XCTAssertFalse(model.draft.publishIssues.isEmpty); XCTAssertTrue(controller.canBrowse)
        controller.openAction(.qaPick)(); let item = try XCTUnwrap(controller.visiblePresentation)
        XCTAssertEqual(item.sample.draft.text("qa", "mode"), "PICK")
        XCTAssertEqual(model.draft, before); XCTAssertEqual(model.coordinator.draft, stored); XCTAssertNil(model.review)
    }
    func testAllSevenChoicesReuseFreshValueSnapshots() throws {
        let (model, controller, _) = try setup(), before = model.draft
        var ids = Set<UUID>()
        for choice in TemplateSamplePreview.Choice.allCases {
            controller.openAction(choice)(); let item = try XCTUnwrap(controller.visiblePresentation)
            XCTAssertTrue(ids.insert(item.id).inserted); XCTAssertEqual(item.sample.choice, choice); controller.close()
        }
        XCTAssertEqual(model.draft, before)
    }
    func testRepeatedCapturedOpenDoesNotReopenAfterClose() throws {
        let (_, controller, _) = try setup(), open = controller.openAction(.note)
        open(); let first = try XCTUnwrap(controller.presentation?.id); open(); XCTAssertEqual(controller.presentation?.id, first)
        controller.close(); open(); XCTAssertNil(controller.presentation)
    }
    func testOldDismissalAndCloseCannotCloseNewSample() throws {
        let (_, controller, _) = try setup(); controller.openAction(.qaText)(); let first = try XCTUnwrap(controller.presentation?.id)
        let close = controller.closeAction(first), binding = controller.presentationBinding
        controller.close(); controller.openAction(.random)(); let second = try XCTUnwrap(controller.presentation?.id)
        close(); binding.wrappedValue = nil; controller.close(expected: first); XCTAssertEqual(controller.presentation?.id, second)
    }
    func testCurrentSheetDismissalReleasesSnapshot() throws {
        let (_, controller, _) = try setup(); controller.openAction(.profile)(); controller.presentationBinding.wrappedValue = nil
        XCTAssertNil(controller.presentation)
    }
    func testDraftEditAndABARejectCapturedOpenAndRetireActiveSample() throws {
        let (model, controller, _) = try setup(), open = controller.openAction(.estimate), before = model.draft
        model.draft.title = "Changed"; model.draft = before; open(); XCTAssertNil(controller.presentation)
        controller.openAction(.estimate)(); model.draft.description = "New description"; XCTAssertNil(controller.presentation)
    }
    func testMetadataLoadAndLeaveRetirePresentedSample() throws {
        for operation in ["refresh", "load", "leave"] {
            let (model, controller, _) = try setup(); controller.openAction(.note)()
            switch operation { case "load": model.load(); case "leave": model.leave(); default: model.changed() }
            XCTAssertNil(controller.visiblePresentation, operation)
        }
    }
    func testBusyReviewBackgroundAndDepartureFenceSamples() throws {
        let (model, controller, _) = try setup(); controller.openAction(.typeIn)(); model.busy = true; model.busy = false
        XCTAssertNil(controller.presentation); controller.openAction(.note)(); model.prepare(.saveDraft); XCTAssertNil(controller.visiblePresentation)
        model.cancel(); controller.reload(); let open = controller.openAction(.profile); controller.retire(); open(); XCTAssertNil(controller.presentation)
    }
    func testOwnerChangeHidesSnapshotAndCannotOpenNewSample() throws {
        let (_, controller, owner) = try setup(); controller.openAction(.qaText)()
        owner.session = try .init(accountID: 1000, namespace: "sample-browser", epoch: 2, authorizationRevision: "member")
        XCTAssertNil(controller.visiblePresentation); XCTAssertFalse(controller.canBrowse); controller.close(); controller.openAction(.note)(); XCTAssertNil(controller.presentation)
    }
    func testUnsupportedTargetShowsUnavailableAndKeepsRawDraft() throws {
        let (model, controller, _) = try setup(); model.draft.advanced.value["note"] = .string("Opaque")
        let before = model.draft; controller.openAction(.note)(); XCTAssertTrue(controller.unavailable); XCTAssertNil(controller.presentation); XCTAssertEqual(model.draft, before)
    }
    func testHiddenSceneAndMediaCannotReactivateOrReuseOldOpen() throws {
        let (_, controller, _) = try setup(), oldOpen = controller.openAction(.qaText)
        controller.viewDisappeared()
        XCTAssertFalse(controller.isVisible); XCTAssertFalse(controller.canBrowse)
        controller.sceneChanged(isActive: false); controller.sceneChanged(isActive: true)
        controller.mediaChanged(sceneIsActive: true); controller.reload(); oldOpen()
        XCTAssertFalse(controller.isVisible); XCTAssertFalse(controller.canBrowse); XCTAssertNil(controller.presentation)
        controller.viewAppeared(sceneIsActive: true); oldOpen()
        XCTAssertTrue(controller.canBrowse); XCTAssertNil(controller.presentation)
        controller.openAction(.qaText)(); XCTAssertNotNil(controller.visiblePresentation)
    }
    func testInactiveAppearanceRequiresForegroundAndFencesOldOpen() throws {
        let (_, controller, _) = try setup(), oldOpen = controller.openAction(.qaText)
        controller.viewDisappeared(); controller.viewAppeared(sceneIsActive: false)
        XCTAssertTrue(controller.isVisible); XCTAssertFalse(controller.canBrowse)
        controller.mediaChanged(sceneIsActive: false); controller.openAction(.qaText)()
        XCTAssertNil(controller.presentation)
        controller.sceneChanged(isActive: true); oldOpen()
        XCTAssertTrue(controller.canBrowse); XCTAssertNil(controller.presentation)
        controller.openAction(.qaText)(); XCTAssertNotNil(controller.visiblePresentation)
    }
    func testRepeatedVisibleAppearancePreservesSheetAndOldDismissCannotCrossHiddenReentry() throws {
        let (_, controller, _) = try setup(); controller.openAction(.qaText)()
        let first = try XCTUnwrap(controller.presentation?.id), binding = controller.presentationBinding
        let close = controller.closeAction(first)
        controller.viewAppeared(sceneIsActive: true); controller.sceneChanged(isActive: true)
        XCTAssertEqual(controller.presentation?.id, first); XCTAssertNotNil(controller.visiblePresentation)
        controller.viewDisappeared(); XCTAssertNil(controller.presentation)
        controller.sceneChanged(isActive: true); controller.mediaChanged(sceneIsActive: true)
        XCTAssertFalse(controller.canBrowse)
        controller.viewAppeared(sceneIsActive: true); controller.openAction(.note)()
        let fresh = try XCTUnwrap(controller.presentation?.id); XCTAssertNotEqual(fresh, first)
        binding.wrappedValue = nil; close(); controller.close(expected: first)
        XCTAssertEqual(controller.presentation?.id, fresh); XCTAssertNotNil(controller.visiblePresentation)
    }

}

extension TemplateSampleBrowserViewTests {
    func testPresentationBindingReadsOnlyCapturedIdentityIncludingInitialNilAndSameChoiceReopen() throws {
        let (_, controller, _) = try setup()
        let initiallyEmpty = controller.presentationBinding
        XCTAssertNil(initiallyEmpty.wrappedValue)
        controller.openAction(.qaText)()
        let first = try XCTUnwrap(controller.visiblePresentation?.id)
        let old = controller.presentationBinding
        XCTAssertEqual(old.wrappedValue?.id, first)
        XCTAssertNil(initiallyEmpty.wrappedValue)
        controller.close(); controller.openAction(.qaText)()
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
        controller.openAction(.qaText)()
        let first = try XCTUnwrap(controller.visiblePresentation?.id)
        let old = controller.presentationBinding
        XCTAssertEqual(old.wrappedValue?.id, first)
        // This owner change has no parent Published event. The stored item remains,
        // so the getter itself must apply visiblePresentation's exact owner fence.
        owner.session = try .init(accountID: 1000, namespace: "sample-browser", epoch: 2, authorizationRevision: "member")
        XCTAssertEqual(controller.presentation?.id, first)
        XCTAssertNil(controller.visiblePresentation); XCTAssertNil(old.wrappedValue)
        controller.viewDisappeared()
        controller.sceneChanged(isActive: false); controller.sceneChanged(isActive: true)
        XCTAssertFalse(controller.isVisible); XCTAssertNil(old.wrappedValue)
        owner.session = originalOwner
        controller.viewAppeared(sceneIsActive: true); controller.openAction(.qaText)()
        let second = try XCTUnwrap(controller.visiblePresentation?.id)
        XCTAssertNotEqual(second, first); XCTAssertNil(old.wrappedValue)
        XCTAssertEqual(controller.presentationBinding.wrappedValue?.id, second)
        old.wrappedValue = nil
        XCTAssertEqual(controller.visiblePresentation?.id, second)
    }
}

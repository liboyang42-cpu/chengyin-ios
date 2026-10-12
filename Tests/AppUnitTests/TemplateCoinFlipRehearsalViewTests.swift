import XCTest
@testable import Questify

@MainActor final class TemplateCoinFlipRehearsalViewTests: XCTestCase {
    private final class Owner {
        var session: TemplateAuthoringSession?
        init(_ value: TemplateAuthoringSession) { session = value }
    }
    private func setup(_ mode: TemplateCoinFlipRehearsal.Mode = .sourceExample) throws -> (TemplateAuthoringModel, TemplateCoinFlipRehearsalController, Owner) {
        let owner = Owner(try .init(accountID: 999, namespace: "coin-rehearsal", epoch: 1, authorizationRevision: "member"))
        let model = TemplateAuthoringModel(coordinator: .init(store: .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { owner.session }))
        model.load(); model.draft.title = "Keep original"; model.changed()
        let controller = TemplateCoinFlipRehearsalController(model: model, mode: mode); controller.viewAppeared(sceneIsActive: true)
        return (model, controller, owner)
    }
    func testConfigurationModeReadsActualFieldsWithoutSample() throws {
        let (model, controller, _) = try setup(.currentConfiguration)
        model.draft.advanced.setNested("coinFlip", "heads", "action", "My action"); controller.reload(); controller.showAction()()
        XCTAssertEqual(controller.visibleState?.result?.side.action, "My action"); XCTAssertEqual(controller.visibleState?.filledFields, [])
    }
    func testBothResultsTryAgainAndResetKeepModelAndStoredDraftExact() throws {
        let (model, controller, _) = try setup(), before = model.draft, stored = model.coordinator.draft
        controller.showAction()(); XCTAssertEqual(controller.visibleState?.result?.face, .heads)
        controller.selection.wrappedValue = .tails; controller.showAction()(); XCTAssertEqual(controller.visibleState?.result?.face, .tails)
        let first = controller.visibleState?.result; controller.showAction()(); XCTAssertEqual(controller.visibleState?.result, first)
        controller.resetAction()(); XCTAssertNil(controller.visibleState?.result); XCTAssertEqual(controller.visibleState?.selection, .heads)
        XCTAssertEqual(model.draft, before); XCTAssertEqual(model.coordinator.draft, stored); XCTAssertNil(model.review)
    }
    func testCapturedShowIsSingleUseAndCannotRunAfterChangingFace() throws {
        let (_, controller, _) = try setup(), old = controller.showAction(); old()
        controller.selection.wrappedValue = .tails; old(); XCTAssertNil(controller.visibleState?.result)
        controller.showAction()(); XCTAssertEqual(controller.visibleState?.result?.face, .tails)
    }
    func testOldBindingAndResetCannotAffectReloadedState() throws {
        let (_, controller, _) = try setup(), binding = controller.selection, reset = controller.resetAction()
        controller.retire(); controller.reload(); controller.selection.wrappedValue = .tails; controller.showAction()()
        binding.wrappedValue = .heads; reset(); XCTAssertEqual(controller.visibleState?.selection, .tails)
        XCTAssertEqual(controller.visibleState?.result?.face, .tails); XCTAssertEqual(binding.wrappedValue, .heads)
    }
    func testConfigurationEditRetiresSnapshotAndReloadUsesNewData() throws {
        let (model, controller, _) = try setup(.currentConfiguration), show = controller.showAction()
        model.draft.advanced.setNested("coinFlip", "tails", "action", "Changed"); show(); XCTAssertNil(controller.visibleState)
        controller.reload(); controller.selection.wrappedValue = .tails; controller.showAction()()
        XCTAssertEqual(controller.visibleState?.result?.side.action, "Changed")
    }
    func testDraftABACannotRestoreOldCallback() throws {
        let (model, controller, _) = try setup(), before = model.draft, show = controller.showAction()
        model.draft.title = "New"; model.draft = before; controller.reload(); show(); XCTAssertNil(controller.visibleState?.result)
    }
    func testCurrentCloseRetiresAndOldCloseCannotDismissReopenedView() throws {
        let (_, controller, _) = try setup(); var dismissals = 0
        let close = controller.closeAction { dismissals += 1 }; close(); XCTAssertEqual(dismissals, 1); XCTAssertNil(controller.visibleState)
        controller.reload(); close(); XCTAssertEqual(dismissals, 1); XCTAssertNotNil(controller.visibleState)
        controller.closeAction { dismissals += 1 }(); XCTAssertEqual(dismissals, 2)
    }
    func testBackgroundRetirementDropsResultsAndOldCallbacks() throws {
        let (_, controller, _) = try setup(); controller.showAction()(); let show = controller.showAction()
        controller.retire(); XCTAssertNil(controller.visibleState); controller.reload(); show(); XCTAssertNil(controller.visibleState?.result)
    }
    func testBusyAndReviewRequireFreshReload() throws {
        let (model, controller, _) = try setup(); model.busy = true; XCTAssertFalse(controller.canReload); model.busy = false
        XCTAssertNil(controller.visibleState); controller.reload(); model.prepare(.saveDraft); XCTAssertNil(controller.visibleState)
        XCTAssertFalse(controller.canReload); model.cancel(); controller.reload(); XCTAssertNotNil(controller.visibleState)
    }
    func testOwnerMismatchHidesPrivateConfigurationAndDisablesReload() throws {
        let (_, controller, owner) = try setup(); controller.showAction()()
        owner.session = try .init(accountID: 1000, namespace: "coin-rehearsal", epoch: 2, authorizationRevision: "member")
        XCTAssertNil(controller.visibleState); XCTAssertFalse(controller.canReload)
    }
    func testMetadataLoadAndLeaveRetireOldResults() throws {
        for operation in ["load", "changed", "leave"] {
            let (model, controller, _) = try setup(); controller.showAction()()
            switch operation { case "load": model.load(); case "leave": model.leave(); default: model.changed() }
            XCTAssertNil(controller.visibleState, operation)
        }
    }
    func testMalformedCoinCannotBeSilentlyRebuilt() throws {
        let (model, controller, _) = try setup(); model.draft.advanced.value["coinFlip"] = .string("Opaque"); let before = model.draft
        controller.reload(); XCTAssertNil(controller.visibleState); controller.showAction()(); XCTAssertEqual(model.draft, before)
    }
    func testHiddenForegroundCannotReloadOrRunOldActionAndClose() throws {
        let (model, controller, _) = try setup(), before = model.draft
        let oldAction = controller.showAction(); var dismissals = 0
        let oldClose = controller.closeAction { dismissals += 1 }
        controller.viewDisappeared(); controller.sceneChanged(isActive: false); controller.sceneChanged(isActive: true)
        controller.reload(); oldAction(); oldClose()
        XCTAssertFalse(controller.isVisible); XCTAssertFalse(controller.canReload); XCTAssertNil(controller.visibleState)
        XCTAssertEqual(model.draft, before); XCTAssertEqual(dismissals, 0)
        controller.viewAppeared(sceneIsActive: true); oldAction(); oldClose()
        XCTAssertTrue(controller.canReload); XCTAssertNotNil(controller.visibleState)
        XCTAssertEqual(model.draft, before); XCTAssertEqual(dismissals, 0)
    }
    func testInactiveAppearanceWaitsForForegroundAndRejectsOldAction() throws {
        let (model, controller, _) = try setup(), before = model.draft, oldAction = controller.showAction()
        controller.viewDisappeared(); controller.viewAppeared(sceneIsActive: false)
        controller.reload(); oldAction()
        XCTAssertTrue(controller.isVisible); XCTAssertFalse(controller.canReload); XCTAssertNil(controller.visibleState)
        controller.sceneChanged(isActive: true); oldAction()
        XCTAssertTrue(controller.canReload); XCTAssertNotNil(controller.visibleState); XCTAssertEqual(model.draft, before)
    }
    func testRepeatedVisibleAppearanceKeepsCurrentStateAndGeneration() throws {
        let (model, controller, _) = try setup()
        controller.showAction()()
        let visible = controller.visibleState, draft = model.draft
        XCTAssertNotNil(visible)
        controller.viewAppeared(sceneIsActive: true); controller.sceneChanged(isActive: true)
        XCTAssertEqual(controller.visibleState, visible); XCTAssertEqual(model.draft, draft)
    }

}

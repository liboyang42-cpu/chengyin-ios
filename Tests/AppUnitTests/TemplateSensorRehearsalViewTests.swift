import XCTest
@testable import Questify

@MainActor final class TemplateSensorRehearsalViewTests: XCTestCase {
    private final class Owner {
        var session: TemplateAuthoringSession?
        init(_ session: TemplateAuthoringSession) { self.session = session }
    }
    private func setup() throws -> (TemplateAuthoringModel, TemplateSensorRehearsalController, Owner) {
        let owner = Owner(try .init(accountID: 999, namespace: "sensor-rehearsal", epoch: 1, authorizationRevision: "member"))
        let model = TemplateAuthoringModel(coordinator: .init(store: .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { owner.session }))
        model.load(); model.draft.title = "Current author draft"
        model.draft.advanced.setGameEnabled(.compass, true)
        model.draft.advanced.set("compass", "bearing", .number(0)); model.changed()
        let controller = TemplateSensorRehearsalController(model: model, game: .compass)
        controller.viewAppeared(sceneIsActive: true)
        return (model, controller, owner)
    }
    func testConfigurationToSimulatedResultAndCleanRetry() throws {
        let (model, controller, _) = try setup(), before = model.draft
        for _ in 0..<5 { controller.advanceAction()(0, 0, 0.1) }
        XCTAssertEqual(controller.visibleState?.feedback, .matched)
        let oldForm = controller.formID
        controller.resetAction()()
        XCTAssertEqual(controller.visibleState?.feedback, .ready)
        XCTAssertNotEqual(controller.formID, oldForm); XCTAssertEqual(model.draft, before)
    }
    func testCapturedAdvanceCannotRunTwiceOrAfterReset() throws {
        let (_, controller, _) = try setup(), advance = controller.advanceAction()
        advance(0, 0, 0.1); let first = controller.visibleState
        advance(0, 0, 0.1); XCTAssertEqual(controller.visibleState, first)
        controller.resetAction()(); advance(0, 0, 0.1)
        XCTAssertEqual(controller.visibleState?.feedback, .ready)
    }
    func testDraftEditRetiresInputAndReloadUsesNewTarget() throws {
        let (model, controller, _) = try setup(), old = controller.advanceAction()
        model.draft.advanced.set("compass", "bearing", .number(90)); model.changed()
        XCTAssertNil(controller.visibleState); old(0, 0, 0.1); XCTAssertNil(controller.visibleState)
        controller.reload(); XCTAssertEqual(controller.visibleState?.targetBearing, 90)
    }
    func testBackgroundAndHiddenViewsCannotAdvance() throws {
        let (_, controller, _) = try setup(), old = controller.advanceAction()
        controller.sceneChanged(isActive: false); old(0, 0, 0.1); XCTAssertNil(controller.visibleState)
        controller.viewDisappeared(); controller.sceneChanged(isActive: true); XCTAssertNil(controller.visibleState)
        controller.viewAppeared(sceneIsActive: true); XCTAssertEqual(controller.visibleState?.feedback, .ready)
    }
    func testLogoutHidesResultsAndRejectsRetainedInput() throws {
        let (_, controller, owner) = try setup(), old = controller.advanceAction()
        owner.session = nil; old(0, 0, 0.1); XCTAssertNil(controller.visibleState)
    }
    func testOldResetCannotClearSuccessorResult() throws {
        let (_, controller, _) = try setup(), oldReset = controller.resetAction()
        controller.advanceAction()(0, 0, 0.1); let next = controller.visibleState
        oldReset(); XCTAssertEqual(controller.visibleState, next)
    }
}

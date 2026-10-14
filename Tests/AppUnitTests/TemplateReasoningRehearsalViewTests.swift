import XCTest
@testable import Questify

@MainActor final class TemplateReasoningRehearsalViewTests: XCTestCase {
    private final class Owner {
        var session: TemplateAuthoringSession?
        init(_ session: TemplateAuthoringSession) { self.session = session }
    }
    private func setup(_ game: TemplateAdvancedGame = .sort) throws -> (TemplateAuthoringModel, TemplateReasoningRehearsalController, Owner) {
        let owner = Owner(try .init(accountID: 999, namespace: "reasoning-rehearsal", epoch: 1, authorizationRevision: "member"))
        let model = TemplateAuthoringModel(coordinator: .init(store: .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { owner.session }))
        model.load(); model.draft.title = "Retained draft"
        model.draft.advanced.setGameEnabled(game, true); model.draft.advanced.set(game.section, "prompt", .string("Question"))
        for field in game == .sort ? ["items"] : game == .match ? ["left", "right"] : ["items", "bins"] {
            for index in model.draft.advanced.rows(game.section, field).indices {
                model.draft.advanced.setRow(game.section, field, index: index, key: "label", text: "\(field) \(index)")
            }
        }
        model.changed()
        let controller = TemplateReasoningRehearsalController(model: model, game: game)
        controller.viewAppeared(sceneIsActive: true)
        return (model, controller, owner)
    }
    private let correct: [String: PlayWireValue] = ["order": .array([.string("item_1"), .string("item_2"), .string("item_3")])]
    private let wrong: [String: PlayWireValue] = ["order": .array([.string("item_3"), .string("item_2"), .string("item_1")])]

    func testNormalEntryToResultAndRetryNeverMutatesAuthorDraft() throws {
        let (model, controller, _) = try setup(), before = model.draft, stored = model.coordinator.draft
        controller.submitAction()("SUBMIT_SORT", correct, {})
        XCTAssertEqual(controller.visibleState?.result, .matched)
        let formID = controller.formID; controller.resetAction()()
        XCTAssertEqual(controller.visibleState?.result, .ready); XCTAssertNotEqual(controller.formID, formID)
        XCTAssertEqual(model.draft, before); XCTAssertEqual(model.coordinator.draft, stored); XCTAssertNil(model.review)
    }
    func testAllThreeGamesUseExistingRequestShapesForLocalFeedback() throws {
        for game in [TemplateAdvancedGame.sort, .match, .classify] {
            let (_, controller, _) = try setup(game)
            let payload: [String: PlayWireValue] = game == .sort ? correct : game == .match ? ["pairs": .array([.array([.string("left_1"), .string("right_1")]), .array([.string("left_2"), .string("right_2")])])] : ["placement": .object(["item_1": .string("bin_1"), "item_2": .string("bin_2")])]
            let state = try XCTUnwrap(controller.visibleState)
            controller.submitAction()(state.action, payload, {}); XCTAssertEqual(controller.visibleState?.result, .matched)
        }
    }
    func testWrongAnswerRetainsFeedbackUntilExplicitRetry() throws {
        let (_, controller, _) = try setup()
        controller.submitAction()("SUBMIT_SORT", wrong, {}); XCTAssertEqual(controller.visibleState?.result, .missed)
        controller.viewAppeared(sceneIsActive: true); XCTAssertEqual(controller.visibleState?.result, .missed)
        controller.resetAction()(); XCTAssertEqual(controller.visibleState?.result, .ready)
    }
    func testRuntimeCompletionCallbackIsNeverInvoked() throws {
        let (_, controller, _) = try setup(); var completed = false
        controller.submitAction()("SUBMIT_SORT", correct, { completed = true })
        XCTAssertFalse(completed); XCTAssertEqual(controller.visibleState?.result, .matched)
    }
    func testDuplicateSubmitAndRetainedCallbackCannotReplaceResult() throws {
        let (_, controller, _) = try setup(); let submit = controller.submitAction()
        submit("SUBMIT_SORT", correct, {}); submit("SUBMIT_SORT", wrong, {})
        controller.submitAction()("SUBMIT_SORT", wrong, {})
        XCTAssertEqual(controller.visibleState?.result, .matched)
    }
    func testOldSubmitCannotAnswerFreshResetForm() throws {
        let (_, controller, _) = try setup(); let old = controller.submitAction()
        controller.resetAction()(); old("SUBMIT_SORT", correct, {})
        XCTAssertEqual(controller.visibleState?.result, .ready)
    }
    func testOldResetCannotClearNewResult() throws {
        let (_, controller, _) = try setup(); let old = controller.resetAction()
        controller.submitAction()("SUBMIT_SORT", correct, {}); old()
        XCTAssertEqual(controller.visibleState?.result, .matched)
    }
    func testDraftEditRetiresResultAndReloadUsesNewAnswer() throws {
        let (model, controller, _) = try setup(); controller.submitAction()("SUBMIT_SORT", correct, {})
        model.draft.advanced.moveRow("sort", "items", from: 0, to: 2)
        XCTAssertNil(controller.visibleState); controller.reload()
        XCTAssertEqual(controller.visibleState?.result, .ready)
        controller.submitAction()("SUBMIT_SORT", correct, {}); XCTAssertEqual(controller.visibleState?.result, .missed)
    }
    func testDraftABADoesNotReviveResultOrRetainedSubmit() throws {
        let (model, controller, _) = try setup(), before = model.draft; let old = controller.submitAction()
        model.draft.title = "Changed"; model.draft = before
        XCTAssertNil(controller.visibleState); controller.reload(); old("SUBMIT_SORT", correct, {})
        XCTAssertEqual(controller.visibleState?.result, .ready)
    }
    func testOwnerSwitchWithoutModelNotificationHidesAndRejectsInput() throws {
        let (_, controller, owner) = try setup(); let old = controller.submitAction()
        owner.session = try .init(accountID: 1000, namespace: "reasoning-rehearsal", epoch: 2, authorizationRevision: "member")
        XCTAssertNil(controller.visibleState); old("SUBMIT_SORT", correct, {}); controller.reload()
        XCTAssertNil(controller.visibleState); XCTAssertFalse(controller.canReload)
    }
    func testLogoutImmediatelyHidesAcceptedResult() throws {
        let (_, controller, owner) = try setup(); controller.submitAction()("SUBMIT_SORT", correct, {})
        owner.session = nil; XCTAssertNil(controller.visibleState); XCTAssertFalse(controller.canReload)
    }
    func testBackgroundRetiresAndForegroundStartsCleanVisibleForm() throws {
        let (_, controller, _) = try setup(); let old = controller.submitAction()
        controller.submitAction()("SUBMIT_SORT", correct, {}); let id = controller.formID
        controller.sceneChanged(isActive: false); XCTAssertNil(controller.visibleState)
        controller.sceneChanged(isActive: true); old("SUBMIT_SORT", correct, {})
        XCTAssertEqual(controller.visibleState?.result, .ready); XCTAssertNotEqual(controller.formID, id)
    }
    func testHiddenDestinationCannotReloadOnForeground() throws {
        let (_, controller, _) = try setup(); controller.viewDisappeared()
        controller.sceneChanged(isActive: false); controller.sceneChanged(isActive: true); controller.reload()
        XCTAssertNil(controller.visibleState); XCTAssertFalse(controller.canReload)
        controller.viewAppeared(sceneIsActive: true); XCTAssertEqual(controller.visibleState?.result, .ready)
    }
    func testRepeatedAppearancePreservesCurrentFormAndResult() throws {
        let (_, controller, _) = try setup(); let formID = controller.formID
        controller.submitAction()("SUBMIT_SORT", correct, {}); controller.viewAppeared(sceneIsActive: true)
        XCTAssertEqual(controller.formID, formID); XCTAssertEqual(controller.visibleState?.result, .matched)
    }
    func testInactiveAppearanceCannotCreateLease() throws {
        let (_, controller, _) = try setup(); controller.viewDisappeared(); controller.viewAppeared(sceneIsActive: false)
        XCTAssertNil(controller.visibleState); XCTAssertFalse(controller.canReload)
    }
    func testBusyAuthorCannotUseOrReloadRehearsal() throws {
        let (model, controller, _) = try setup(); let old = controller.submitAction(); model.busy = true
        old("SUBMIT_SORT", correct, {}); controller.reload(); XCTAssertNil(controller.visibleState)
        model.busy = false; controller.reload(); XCTAssertEqual(controller.visibleState?.result, .ready)
    }
    func testChangedOrDisabledQuestionCannotFallbackToSample() throws {
        let (model, controller, _) = try setup(); model.draft.advanced.setGameEnabled(.sort, false)
        controller.reload(); XCTAssertNil(controller.visibleState)
        model.draft.advanced.setGameEnabled(.sort, true); model.draft.advanced.set("sort", "prompt", .string(""))
        controller.reload(); XCTAssertNil(controller.visibleState)
    }
    func testRetainedSubmitAfterDisappearanceCannotAffectReopenedForm() throws {
        let (_, controller, _) = try setup(); let old = controller.submitAction()
        controller.viewDisappeared(); controller.viewAppeared(sceneIsActive: true); old("SUBMIT_SORT", correct, {})
        XCTAssertEqual(controller.visibleState?.result, .ready)
    }
    func testOldReloadEraResetCannotClearNewAcceptedResult() throws {
        let (_, controller, _) = try setup(); let old = controller.resetAction(); controller.reload()
        controller.submitAction()("SUBMIT_SORT", correct, {}); old()
        XCTAssertEqual(controller.visibleState?.result, .matched)
    }
    func testMalformedSubmissionIsExplicitAndRecoverable() throws {
        let (_, controller, _) = try setup(); controller.submitAction()("SUBMIT_SORT", [:], {})
        XCTAssertEqual(controller.visibleState?.result, .invalid); controller.resetAction()()
        controller.submitAction()("SUBMIT_SORT", correct, {}); XCTAssertEqual(controller.visibleState?.result, .matched)
    }
}

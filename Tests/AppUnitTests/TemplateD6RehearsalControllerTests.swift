import XCTest
@testable import Questify

@MainActor final class TemplateD6RehearsalControllerTests: XCTestCase {
    private final class Owner {
        var session: TemplateAuthoringSession?
        init(_ session: TemplateAuthoringSession) { self.session = session }
    }
    private func setup(store: TemplateAuthoringLocalStore? = nil) throws -> (TemplateAuthoringModel, TemplateD6RehearsalController, Owner) {
        let owner = Owner(try .init(accountID: 919, namespace: "d6-authoring-preview", epoch: 1, authorizationRevision: "member"))
        let model = TemplateAuthoringModel(coordinator: .init(store: store ?? .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { owner.session }))
        model.load(); model.draft.title = "Dice authoring"; model.setGameEnabled(.dice, true)
        for index in 0..<6 { model.draft.advanced.setFace(index, "Action \(index + 1)") }
        model.changed()
        let controller = TemplateD6RehearsalController(model: model); controller.reload()
        return (model, controller, owner)
    }
    func testChooseShowAndRepeatSingleDieSamplesWithoutAnyDraftWrite() throws {
        let (model, controller, _) = try setup(), before = model.draft, saved = model.coordinator.draft
        for value in 1...6 {
            controller.pip(0).wrappedValue = value; controller.sampleAction()()
            XCTAssertEqual(controller.visibleSample?.total, value); XCTAssertEqual(controller.visibleSample?.action, "Action \(value)")
        }
        XCTAssertEqual(model.draft, before); XCTAssertEqual(model.coordinator.draft, saved)
        XCTAssertFalse(model.coordinator.canSubmit)
    }
    func testTwoDiceShowSumWithoutFaceActionIncludingTwelve() throws {
        let (model, controller, _) = try setup()
        model.draft.advanced.set("diceRoll", "diceCount", .number(2)); model.changed(); controller.reload()
        controller.pip(0).wrappedValue = 6; controller.pip(1).wrappedValue = 6; controller.sampleAction()()
        XCTAssertEqual(controller.visibleSample?.pips, [6, 6]); XCTAssertEqual(controller.visibleSample?.total, 12)
        XCTAssertNil(controller.visibleSample?.action)
    }
    func testChangingExampleValuesClearsResultAndRejectsOldShowAction() throws {
        let (_, controller, _) = try setup()
        controller.sampleAction()(); XCTAssertNotNil(controller.visibleSample)
        let old = controller.sampleAction(); controller.pip(0).wrappedValue = 5
        XCTAssertNil(controller.visibleSample); old(); XCTAssertNil(controller.visibleSample)
        controller.sampleAction()(); XCTAssertEqual(controller.visibleSample?.action, "Action 5")
    }
    func testResetClearsResultAndRetiresRetainedPipAndShowControls() throws {
        let (_, controller, _) = try setup(); controller.pip(0).wrappedValue = 3; controller.sampleAction()()
        let pip = controller.pip(0), show = controller.sampleAction(), reset = controller.resetAction()
        reset(); XCTAssertNil(controller.visibleSample); XCTAssertEqual(controller.selectedPips, [1])
        pip.wrappedValue = 6; show(); XCTAssertEqual(controller.selectedPips, [1]); XCTAssertNil(controller.visibleSample)
        controller.sampleAction()(); XCTAssertEqual(controller.visibleSample?.action, "Action 1")
    }
    func testDraftEditSynchronouslyRetiresSamplesBeforeParentOnChangeAndReloadsExplicitly() throws {
        let (model, controller, _) = try setup(); controller.sampleAction()()
        let pip = controller.pip(0), show = controller.sampleAction()
        model.draft.advanced.setFace(0, "New action")
        XCTAssertNil(controller.visibleConfiguration); XCTAssertNil(controller.visibleSample)
        pip.wrappedValue = 6; show(); XCTAssertNil(controller.visibleSample)
        controller.reload(); controller.sampleAction()(); XCTAssertEqual(controller.visibleSample?.action, "New action")
    }
    func testSameValueDraftABAAndUnrelatedChangesAlsoRetireLocalSample() throws {
        let (model, controller, _) = try setup(); let original = model.draft
        controller.sampleAction()(); let old = controller.sampleAction()
        model.draft.title = "Changed"; model.draft = original
        old(); XCTAssertNil(controller.visibleSample); XCTAssertNil(controller.visibleConfiguration)
        controller.reload(); XCTAssertEqual(controller.selectedPips, [1]); XCTAssertNil(controller.visibleSample)
    }
    func testLoadRestoreDiscardLeaveDismissAndOwnerChangeFenceEveryControl() throws {
        for operation in ["load", "restore", "discard", "leave", "dismiss", "owner"] {
            let (model, controller, owner) = try setup(); controller.sampleAction()()
            let show = controller.sampleAction(), reset = controller.resetAction(), pip = controller.pip(0)
            switch operation {
            case "load": model.load()
            case "restore": model.restore()
            case "discard": model.discard()
            case "leave": model.leave()
            case "dismiss": controller.retire()
            default: owner.session = try .init(accountID: 920, namespace: "d6-authoring-preview", epoch: 2, authorizationRevision: "member")
            }
            show(); reset(); pip.wrappedValue = 6
            XCTAssertNil(controller.visibleConfiguration, operation); XCTAssertNil(controller.visibleSample, operation)
            XCTAssertEqual(controller.selectedPips, [], operation)
        }
    }
    func testInvalidAndOtherModesCannotReloadWhileCurrentD6Can() throws {
        let (model, controller, _) = try setup()
        model.draft.advanced.setFace(0, ""); controller.reload()
        XCTAssertFalse(controller.canReload); XCTAssertNil(controller.visibleConfiguration)
        model.draft.advanced.setFace(0, "Restored"); model.draft.advanced.setDiceMode("d20"); controller.reload()
        XCTAssertNil(controller.visibleConfiguration)
        model.draft.advanced.setDiceMode("d6"); controller.reload()
        XCTAssertTrue(controller.canReload); XCTAssertEqual(controller.visibleConfiguration?.faces.first, "Restored")
    }
    func testExistingLocalSaveFreshRestoreKeepsConfigWithoutSampleState() throws {
        let store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage())
        let (model, controller, owner) = try setup(store: store)
        controller.pip(0).wrappedValue = 6; controller.sampleAction()(); let expected = model.draft
        model.save(); controller.retire(); model.leave()
        let reopened = TemplateAuthoringModel(coordinator: .init(store: store, currentSession: { owner.session }))
        reopened.load(); reopened.restore(); let fresh = TemplateD6RehearsalController(model: reopened); fresh.reload()
        XCTAssertEqual(reopened.draft, expected); XCTAssertNil(fresh.visibleSample); XCTAssertEqual(fresh.selectedPips, [1])
        fresh.pip(0).wrappedValue = 6; fresh.sampleAction()(); XCTAssertEqual(fresh.visibleSample?.action, "Action 6")
    }
    func testPendingWriteLockDoesNotPermitRehearsalOrAnyDraftMutation() throws {
        let (seedModel, _, owner) = try setup(), session = try XCTUnwrap(owner.session)
        let store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage()), identity = TemplateAuthoringIdentity(), seed = seedModel.draft
        try store.save(seed, session: session, identity: identity)
        try store.savePending(.init(operationID: UUID(), ownerKey: session.ownerKey, identity: identity,
            request: TemplateAuthoringContract.request(seed, intent: .saveDraft), createdAt: Date()), session: session)
        let model = TemplateAuthoringModel(coordinator: .init(store: store, currentSession: { session })); model.load(); model.draft = seed
        let controller = TemplateD6RehearsalController(model: model); controller.reload(); controller.sampleAction()()
        XCTAssertFalse(controller.canReload); XCTAssertNil(controller.visibleSample); XCTAssertEqual(model.draft, seed)
    }
}

import XCTest
@testable import Questify

@MainActor final class TemplateSensorDraftLifecycleTests: XCTestCase {
    func testChildEditSurvivesBackAndRestoreAndRejectsChangedSession() throws {
        var session: TemplateAuthoringSession? = try .init(accountID: 901, namespace: "sensor-lifecycle", epoch: 1, authorizationRevision: "fixture")
        let store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage())
        let coordinator = TemplateAuthoringCoordinator(store: store, currentSession: { session })
        var seed = TemplateAuthoringDraft(title: "Sensor")
        // The coordinated local-only enum patch is a required integration dependency.
        seed.validationMethod = try XCTUnwrap(TemplateAuthoringMethod(rawValue: 7))
        coordinator.open(seed: seed)
        let model = TemplateAuthoringModel(coordinator: coordinator); model.load()
        model.leave(); model.selectSensorKind(.steps)
        model.setSensorInput(.targetSteps, "invalid-current"); model.setSensorInput(.windowSec, "60")
        XCTAssertEqual(coordinator.draft.sensorDraft, model.draft.sensorDraft)
        model.load(); model.save()
        let expected = model.draft
        let reopened = TemplateAuthoringCoordinator(store: store, currentSession: { session })
        reopened.open(); reopened.restoreDraft(); XCTAssertEqual(reopened.draft, expected)
        XCTAssertFalse(try XCTUnwrap(reopened.draft.sensorDraft).isValid)
        session = try .init(accountID: 901, namespace: "sensor-lifecycle", epoch: 2, authorizationRevision: "fixture")
        model.setSensorInput(.targetSteps, "12"); model.selectSensorKind(.still)
        XCTAssertEqual(model.draft, expected); XCTAssertFalse(model.canEdit)
        model.load(); XCTAssertNil(model.draft.sensorDraft)
    }
    func testUnknownConfigurationCannotBeEditedOrReplacedByChild() throws {
        let session = try TemplateAuthoringSession(accountID: 901, namespace: "sensor-unknown", epoch: 1, authorizationRevision: "fixture")
        let coordinator = TemplateAuthoringCoordinator(store: .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { session })
        var seed = TemplateAuthoringDraft(title: "Sensor")
        seed.validationMethod = try XCTUnwrap(TemplateAuthoringMethod(rawValue: 7))
        seed.sensorDraft = .init(type: "future", config: #"{"future":[1,true]}"#)
        coordinator.open(seed: seed)
        let model = TemplateAuthoringModel(coordinator: coordinator); model.load()
        model.selectSensorKind(.still); model.setSensorInput(.durationSec, "3")
        XCTAssertEqual(model.draft, seed); XCTAssertEqual(coordinator.draft, seed)
    }
}

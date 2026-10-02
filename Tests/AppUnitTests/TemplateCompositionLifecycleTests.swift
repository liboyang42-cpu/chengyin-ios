import XCTest
@testable import Questify

@MainActor final class TemplateCompositionLifecycleTests: XCTestCase {
    private func session(_ accountID: Int = 901) throws -> TemplateAuthoringSession {
        try .init(accountID: accountID, namespace: "composition-lifecycle-fixture", epoch: 1, authorizationRevision: "member")
    }
    func testChildToggleSurvivesParentLoadAndLocalReopenWithSiblingsIntact() throws {
        let owner = try session()
        let store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage())
        let coordinator = TemplateAuthoringCoordinator(store: store, currentSession: { owner })
        let seed = TemplateAuthoringSyntheticFixtures.compoundDraft()
        coordinator.open(seed: seed)
        let model = TemplateAuthoringModel(coordinator: coordinator); model.load()
        model.setGameEnabled(.coin, false)
        XCTAssertFalse(coordinator.draft.advanced.enabled("coinFlip"))
        model.leave(); model.load(); model.save()
        let reopened = TemplateAuthoringCoordinator(store: store, currentSession: { owner })
        reopened.open(); reopened.restoreDraft()
        XCTAssertFalse(reopened.draft.advanced.enabled("coinFlip"))
        for (key, value) in seed.advanced.value where key != "coinFlip" {
            XCTAssertEqual(reopened.draft.advanced.value[key], value, key)
        }
        XCTAssertEqual(reopened.draft.advanced.value["coinFlip"]?.object?["heads"], seed.advanced.value["coinFlip"]?.object?["heads"])
    }
    func testChildToggleCannotMutateAfterSessionChange() throws {
        var owner: TemplateAuthoringSession? = try session()
        let coordinator = TemplateAuthoringCoordinator(store: .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { owner })
        coordinator.open(seed: TemplateAuthoringSyntheticFixtures.compoundDraft())
        let model = TemplateAuthoringModel(coordinator: coordinator); model.load()
        let previous = model.draft
        owner = try session(902)
        model.setGameEnabled(.coin, false)
        XCTAssertEqual(model.draft, previous)
        model.load()
        XCTAssertFalse(model.draft.advanced.enabled("coinFlip"))
        XCTAssertFalse(model.draft.advanced.enabled("diceRoll"))
    }
    func testChildToggleCannotMutateLockedSubmission() async throws {
        let owner = try session()
        let coordinator = TemplateAuthoringCoordinator(adapter: .init(transport: TemplateAuthoringSyntheticTransport(scenario: .uncertain)), store: .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { owner })
        coordinator.open(seed: TemplateAuthoringSyntheticFixtures.compoundDraft())
        let model = TemplateAuthoringModel(coordinator: coordinator); model.load(); model.prepare(.publish)
        await model.confirm(try XCTUnwrap(model.review))
        XCTAssertTrue(coordinator.locked)
        let previous = model.draft
        model.setGameEnabled(.coin, false)
        XCTAssertEqual(model.draft, previous)
        XCTAssertEqual(coordinator.draft, previous)
    }
}

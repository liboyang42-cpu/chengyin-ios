import XCTest
@testable import Questify

/// Authored Apple app-unit lifecycle checks. No device or Swift runtime execution claimed.
@MainActor final class TemplatePreferenceDraftLifecycleTests: XCTestCase {
    private func session(_ epoch: UInt64 = 1) throws -> TemplateAuthoringSession {
        try .init(accountID: 901, namespace: "preference-lifecycle", epoch: epoch, authorizationRevision: "member")
    }
    func testPreferenceRawSurvivesParentReappearanceAndProtectedStoreRestore() throws {
        let owner = try session(), store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage())
        let coordinator = TemplateAuthoringCoordinator(store: store, currentSession: { owner })
        let model = TemplateAuthoringModel(coordinator: coordinator); model.load()
        let raw = "\n{\"future\":9007199254740993, unfinished\n"
        model.draft.validationMethod = .preference; model.draft.preferenceJson = raw; model.changed()
        model.leave(); model.load(); model.save()
        XCTAssertEqual(model.draft.preferenceJson, raw)
        let reopened = TemplateAuthoringCoordinator(store: store, currentSession: { owner }); reopened.open(); reopened.restoreDraft()
        XCTAssertEqual(reopened.draft.validationMethod, .preference)
        XCTAssertEqual(reopened.draft.preferenceJson, raw)
    }
    func testEpochChangeDoesNotSavePreviousOwnerRaw() throws {
        var owner: TemplateAuthoringSession? = try session()
        let store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage())
        let coordinator = TemplateAuthoringCoordinator(store: store, currentSession: { owner })
        let model = TemplateAuthoringModel(coordinator: coordinator); model.load()
        model.draft.preferenceJson = "private local text"
        owner = try session(2)
        XCTAssertFalse(model.canEdit); model.save(); model.load()
        XCTAssertNil(model.draft.preferenceJson); XCTAssertNil(coordinator.draft.preferenceJson)
    }
    func testLocalMethodCannotPrepareRemoteReviewOrPendingIntent() throws {
        let owner = try session(), storage = TemplateAuthoringMemoryStorage()
        let store = TemplateAuthoringLocalStore(storage: storage)
        let coordinator = TemplateAuthoringCoordinator(adapter: .init(transport: TemplateAuthoringSyntheticTransport()), store: store, currentSession: { owner })
        let model = TemplateAuthoringModel(coordinator: coordinator); model.load()
        model.draft.title = "Local preference"; model.draft.validationMethod = .preference
        model.draft.preferenceJson = TemplatePreferenceDraftCheck.example; model.changed()
        for intent in TemplateAuthoringIntent.allCases { model.prepare(intent); XCTAssertNil(model.review); XCTAssertNil(coordinator.review) }
        XCTAssertNil(try store.pending(session: owner, identity: coordinator.identity))
    }
}

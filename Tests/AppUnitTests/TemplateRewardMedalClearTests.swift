import XCTest
@testable import Questify

@MainActor final class TemplateRewardMedalClearTests: XCTestCase {
    private func owner(_ epoch: UInt64 = 1) throws -> TemplateAuthoringSession {
        try .init(accountID: 912, namespace: "reward-medal-clear", epoch: epoch, authorizationRevision: "member")
    }
    private func makeModel(_ session: @escaping () -> TemplateAuthoringSession?, store: TemplateAuthoringLocalStore? = nil) -> TemplateAuthoringModel {
        let model = TemplateAuthoringModel(coordinator: .init(store: store ?? .init(storage: TemplateAuthoringMemoryStorage()), currentSession: session))
        model.load(); model.draft.title = "Medal reward"; model.draft.rewardEnabled = true
        model.draft.medalImg = "unknown:medal"; model.draft.medalName = "City medal"; model.draft.medalStyle = "enamel"
        model.draft.couponId = 22; model.draft.feedbackText = "Keep feedback"; model.changed()
        return model
    }
    func testClearIsAtomicAndIdempotentAndSurvivesFreshLocalRestore() throws {
        let session = try owner(), store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage())
        let model = makeModel({ session }, store: store), action = model.clearRewardMedalAction(), revision = model.revision
        var expected = model.draft; expected.medalImg = nil; expected.medalName = nil; expected.medalStyle = "glow"
        action(); action()
        XCTAssertEqual(model.draft, expected); XCTAssertEqual(model.coordinator.draft, expected)
        XCTAssertEqual(model.revision, revision + 1); XCTAssertFalse(model.canClearRewardMedal)
        model.save(); model.leave()
        let reopened = TemplateAuthoringModel(coordinator: .init(store: store, currentSession: { session }))
        reopened.load(); reopened.restore(); XCTAssertEqual(reopened.draft, expected)
        XCTAssertFalse(model.coordinator.canSubmit)
    }
    func testPreparingOrDismissingAnActionDoesNotChangeAnyField() throws {
        let session = try owner(), model = makeModel({ session }), before = model.draft
        let action = model.clearRewardMedalAction()
        XCTAssertEqual(model.draft, before)
        model.leave(); action(); XCTAssertEqual(model.draft, before)
    }
    func testDirectEditsBeforeObservationRejectOldAction() throws {
        for key in [\TemplateAuthoringDraft.medalImg, \.medalName, \.medalStyle] {
            let session = try owner(), model = makeModel({ session }), action = model.clearRewardMedalAction()
            model.draft[keyPath: key] = "new value"
            let before = model.draft; action(); XCTAssertEqual(model.draft, before)
        }
    }
    func testCommittedABAAndRewardToggleRejectOldAction() throws {
        let session = try owner(), model = makeModel({ session }), action = model.clearRewardMedalAction()
        let original = model.draft.medalImg
        model.draft.medalImg = "replacement"; model.changed()
        model.draft.medalImg = original; model.changed()
        let before = model.draft; action(); XCTAssertEqual(model.draft, before)
        let toggled = model.clearRewardMedalAction()
        model.draft.rewardEnabled = false; model.changed(); toggled(); XCTAssertEqual(model.draft.medalImg, original)
        model.draft.rewardEnabled = true; model.changed(); toggled(); XCTAssertEqual(model.draft.medalImg, original)
    }
    func testReloadRestoreDiscardAndReviewCancellationRetireAction() throws {
        for transition in ["load", "restore", "discard", "review"] {
            let session = try owner(), model = makeModel({ session }), action = model.clearRewardMedalAction()
            switch transition {
            case "load": model.load()
            case "restore": model.restore()
            case "discard": model.discard()
            default: model.prepare(.saveDraft); model.cancel()
            }
            let expected = model.draft; action(); XCTAssertEqual(model.draft, expected, transition)
        }
    }
    func testOwnerChangeAndSignoutRejectActionBeforeReload() throws {
        var session: TemplateAuthoringSession? = try owner()
        let model = makeModel({ session }), action = model.clearRewardMedalAction(), before = model.draft
        session = try owner(2); action(); XCTAssertEqual(model.draft, before)
        session = nil; action(); XCTAssertEqual(model.draft, before)
    }
    func testDurablePendingLockPreservesRetainedMedalFields() throws {
        let session = try owner(), seed = makeModel({ session }).draft
        let store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage()), identity = TemplateAuthoringIdentity()
        try store.save(seed, session: session, identity: identity)
        try store.savePending(.init(operationID: UUID(), ownerKey: session.ownerKey, identity: identity,
            request: TemplateAuthoringContract.request(seed, intent: .saveDraft), createdAt: Date()), session: session)
        let model = TemplateAuthoringModel(coordinator: .init(store: store, currentSession: { session })); model.load()
        model.draft = seed; let before = model.draft
        XCTAssertTrue(model.coordinator.locked); XCTAssertFalse(model.canClearRewardMedal)
        model.clearRewardMedalAction()(); XCTAssertEqual(model.draft, before)
    }
}

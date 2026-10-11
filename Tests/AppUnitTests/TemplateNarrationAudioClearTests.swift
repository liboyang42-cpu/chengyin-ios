import XCTest
@testable import Questify

@MainActor final class TemplateNarrationAudioClearTests: XCTestCase {
    private func owner(_ epoch: UInt64 = 1) throws -> TemplateAuthoringSession {
        try .init(accountID: 908, namespace: "narration-clear", epoch: epoch, authorizationRevision: "member")
    }
    private func model(_ session: @escaping () -> TemplateAuthoringSession?, store: TemplateAuthoringLocalStore? = nil) -> TemplateAuthoringModel {
        let coordinator = TemplateAuthoringCoordinator(store: store ?? .init(storage: TemplateAuthoringMemoryStorage()), currentSession: session)
        let model = TemplateAuthoringModel(coordinator: coordinator); model.load()
        model.draft.title = "Narration draft"; model.draft.voiceEnabled = true
        model.draft.audioUrl = " unknown://narration\n"; model.draft.audioDuration = 45
        model.draft.storyJson = #"[{"text":"keep","tag":"tag","imgs":["same","same"]}]"#
        model.draft.questionAudio = "keep-question-audio"; model.changed()
        return model
    }

    func testClearIsAtomicIdempotentAndPersistsThroughLocalRestore() throws {
        let session = try owner(), store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage())
        let model = model({ session }, store: store)
        var expected = model.draft; expected.audioUrl = nil; expected.audioDuration = nil
        let action = model.clearNarrationAudioAction(), revision = model.revision
        action(); action()
        XCTAssertEqual(model.draft, expected); XCTAssertEqual(model.coordinator.draft, expected)
        XCTAssertEqual(model.revision, revision + 1); XCTAssertFalse(model.canClearNarrationAudio)
        XCTAssertFalse(model.coordinator.canSubmit); XCTAssertNil(model.coordinator.review)
        model.save(); model.leave()
        let reopened = TemplateAuthoringModel(coordinator: .init(store: store, currentSession: { session }))
        reopened.load(); reopened.restore()
        XCTAssertEqual(reopened.draft, expected)
    }

    func testPreparingAnActionDoesNotChangeDraftAndLeavingRetiresIt() throws {
        let session = try owner(), model = model({ session }), before = model.draft
        let action = model.clearNarrationAudioAction()
        XCTAssertEqual(model.draft, before)
        model.leave(); action(); XCTAssertEqual(model.draft, before)
    }

    func testReferenceOrDurationEditBeforeObservationRejectsOldAction() throws {
        for field in ["reference", "duration"] {
            let session = try owner(), model = model({ session }), action = model.clearNarrationAudioAction()
            if field == "reference" { model.draft.audioUrl = "replacement" }
            else { model.draft.audioDuration = 60 }
            let expected = model.draft; action(); XCTAssertEqual(model.draft, expected)
        }
    }

    func testCommittedABAEditAndModuleToggleRetireOldAction() throws {
        let session = try owner(), model = model({ session }), action = model.clearNarrationAudioAction()
        let original = model.draft.audioUrl
        model.draft.audioUrl = "replacement"; model.changed()
        model.draft.audioUrl = original; model.changed()
        let expected = model.draft; action(); XCTAssertEqual(model.draft, expected)
        let beforeToggle = model.clearNarrationAudioAction()
        model.draft.voiceEnabled = false; model.changed(); beforeToggle()
        XCTAssertEqual(model.draft.audioUrl, original)
        model.draft.voiceEnabled = true; model.changed(); beforeToggle()
        XCTAssertEqual(model.draft.audioUrl, original)
        model.clearNarrationAudioAction()(); XCTAssertNil(model.draft.audioUrl)
    }

    func testReloadRestoreAndDiscardRetireOldAction() throws {
        for transition in ["load", "restore", "discard"] {
            let session = try owner(), model = model({ session }), action = model.clearNarrationAudioAction()
            switch transition { case "load": model.load(); case "restore": model.restore(); default: model.discard() }
            let expected = model.draft; action(); XCTAssertEqual(model.draft, expected)
        }
    }

    func testPreparingThenCancellingReviewDoesNotReviveOldAction() throws {
        let session = try owner(), model = model({ session }), action = model.clearNarrationAudioAction()
        let before = model.draft
        model.prepare(.saveDraft); XCTAssertNotNil(model.review)
        model.cancel(); action(); XCTAssertEqual(model.draft, before)
    }

    func testOwnerChangeAndSignOutRejectActionBeforeReload() throws {
        var session: TemplateAuthoringSession? = try owner()
        let model = model({ session }), action = model.clearNarrationAudioAction(), before = model.draft
        session = try owner(2); action(); XCTAssertEqual(model.draft, before)
        session = nil; action(); XCTAssertEqual(model.draft, before)
    }

    func testClearCancelsPendingInspectionAndRejectsItsLateCompletion() throws {
        let session = try owner(), model = model({ session })
        let media = TemplateMediaReviewController(model: model, fixtureMode: "generated"); media.reload()
        media.open(try XCTUnwrap(media.rows.first { $0.field == .narration }))
        media.beginSynthetic(try XCTUnwrap(media.review), held: true)
        let pending = try XCTUnwrap(media.review), action = model.clearNarrationAudioAction()
        action(); let expected = model.draft
        XCTAssertNil(media.review); XCTAssertNil(media.presentation(for: pending.id))
        media.completeSynthetic(pending); media.finish(pending)
        XCTAssertNil(media.review); XCTAssertEqual(model.draft, expected)
    }

    func testReadOnlyRestoreStateDoesNotAllowRemoval() throws {
        let session = try owner(), model = model({ session })
        model.save()
        // A newly opened coordinator must wait for the explicit local restore choice.
        let storage = TemplateAuthoringMemoryStorage(), store = TemplateAuthoringLocalStore(storage: storage)
        let identity = TemplateAuthoringIdentity()
        try store.save(model.draft, session: session, identity: identity)
        let reopened = TemplateAuthoringModel(coordinator: .init(store: store, currentSession: { session }))
        reopened.load(); let before = reopened.draft
        XCTAssertFalse(reopened.canClearNarrationAudio)
        reopened.clearNarrationAudioAction()(); XCTAssertEqual(reopened.draft, before)
    }

    func testDurablePendingLockRejectsActionAndLeavesBothFieldsUnchanged() throws {
        let session = try owner(), seed = model({ session }).draft
        let storage = TemplateAuthoringMemoryStorage(), store = TemplateAuthoringLocalStore(storage: storage)
        let identity = TemplateAuthoringIdentity()
        try store.save(seed, session: session, identity: identity)
        try store.savePending(.init(operationID: UUID(), ownerKey: session.ownerKey, identity: identity,
            request: TemplateAuthoringContract.request(seed, intent: .saveDraft), createdAt: Date()), session: session)
        let model = TemplateAuthoringModel(coordinator: .init(store: store, currentSession: { session })); model.load()
        // Keep the same retained fields visible while preserving the durable write lock.
        model.draft = seed; let before = model.draft
        XCTAssertTrue(model.coordinator.locked); XCTAssertFalse(model.canClearNarrationAudio)
        model.clearNarrationAudioAction()(); XCTAssertEqual(model.draft, before)
    }
}

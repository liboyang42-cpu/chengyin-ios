import XCTest
@testable import Questify

@MainActor final class TemplateOptionalModuleManagerTests: XCTestCase {
    private final class Owner { var session: TemplateAuthoringSession?; init(_ value: TemplateAuthoringSession) { session = value } }
    private func setup(store: TemplateAuthoringLocalStore? = nil) throws -> (TemplateAuthoringModel, TemplateOptionalModuleController, Owner) {
        let owner = Owner(try .init(accountID: 987, namespace: "optional-modules", epoch: 1, authorizationRevision: "member"))
        let model = TemplateAuthoringModel(coordinator: .init(store: store ?? .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { owner.session }))
        model.load(); model.draft.title = "Modules"; model.draft.rewardEnabled = true; model.draft.storyEnabled = true; model.draft.voiceEnabled = true
        model.draft.couponId = 25; model.draft.feedbackText = "Done"; model.draft.medalName = "Medal"; model.draft.medalImg = "/medal.png"; model.draft.medalStyle = "enamel"
        model.draft.storyText = "Story"; model.draft.storyJson = "[{\"text\":\"Beat\",\"tag\":\"tag\",\"imgs\":[]}]"; model.draft.storyImg = "/legacy.png"
        model.draft.audioUrl = "/audio.m4a"; model.draft.audioDuration = 12; model.changed()
        return (model, .init(model: model), owner)
    }
    private func request(_ module: TemplateOptionalModules.Module, _ editor: TemplateOptionalModuleController) throws -> TemplateOptionalModuleController.Review {
        editor.removalAction(module)(); return try XCTUnwrap(editor.currentReview)
    }
    func testInspectCancelConfirmReAddWholeFlow() throws {
        for module in TemplateOptionalModules.Module.allCases {
            let (model, editor, _) = try setup(), before = model.draft, first = try request(module, editor)
            XCTAssertEqual(first.fields.map(\.value), TemplateOptionalModules(before).fields(module).map(\.value)); XCTAssertEqual(model.draft, before)
            editor.cancel(first); XCTAssertNil(editor.currentReview); XCTAssertEqual(model.draft, before)
            let next = try request(module, editor); editor.confirm(next); XCTAssertFalse(editor.enabled(module)); XCTAssertNil(editor.currentReview)
            let removed = model.draft; editor.addAction(module)(); XCTAssertTrue(editor.enabled(module)); XCTAssertEqual(TemplateOptionalModules(model.draft).fields(module).map(\.value), TemplateOptionalModules(removed).fields(module).map(\.value)); XCTAssertEqual(model.coordinator.draft, model.draft)
        }
    }
    func testCancelledAndDuplicateConfirmationCannotClearLaterData() throws {
        let (model, editor, _) = try setup(), first = try request(.reward, editor); editor.cancel(first)
        let second = try request(.reward, editor); editor.confirm(first); XCTAssertEqual(editor.currentReview?.id, second.id); editor.confirm(second)
        editor.addAction(.reward)(); let before = model.draft; editor.confirm(second); XCTAssertEqual(model.draft, before)
    }
    func testStaleDismissalCannotDismissNewReview() throws {
        let (_, editor, _) = try setup(), first = try request(.story, editor); editor.cancel(first)
        let second = try request(.voice, editor); editor.dismiss(first); XCTAssertEqual(editor.currentReview?.id, second.id)
    }
    func testExternalDraftChangeAndABAInvalidateReview() throws {
        let (model, editor, _) = try setup(), review = try request(.story, editor), before = model.draft
        model.draft.title = "Other"; model.draft = before; editor.confirm(review)
        XCTAssertEqual(model.draft, before); XCTAssertNil(editor.currentReview); XCTAssertTrue(editor.needsReload)
        editor.reload(); XCTAssertTrue(editor.canEdit); XCTAssertNil(editor.currentReview)
    }
    func testParentReviewRefreshDoesNotLoseCommittedState() throws {
        let (model, editor, _) = try setup(), review = try request(.voice, editor); editor.confirm(review); model.changed()
        XCTAssertTrue(editor.canEdit); XCTAssertFalse(editor.needsReload); XCTAssertFalse(editor.enabled(.voice)); editor.addAction(.voice)(); XCTAssertTrue(model.draft.voiceEnabled); XCTAssertEqual(model.draft.audioUrl, "")
    }
    func testRefreshInvalidatesCapturedActionsAndPendingConfirmation() throws {
        let (model, editor, _) = try setup(), action = editor.removalAction(.reward), review = try request(.voice, editor), before = model.draft
        model.changed(); editor.confirm(review); action(); XCTAssertEqual(model.draft, before); XCTAssertNil(editor.currentReview)
    }
    func testCommitRotatesMediaAndStoryLeasesBeforeRemoval() throws {
        let (model, editor, _) = try setup(), media = model.mediaReviewGeneration, story = model.storyEditorGeneration, timeline = TemplateStoryEditor(model: model)
        let firstBeat = try XCTUnwrap(timeline.beats.first), oldInput = timeline.text(firstBeat.id, \.text), review = try request(.story, editor)
        editor.confirm(review); XCTAssertNotEqual(model.mediaReviewGeneration, media); XCTAssertGreaterThan(model.storyEditorGeneration, story)
        editor.addAction(.story)(); let before = model.draft; oldInput.wrappedValue = "Stale story"; XCTAssertEqual(model.draft, before)
        let fresh = TemplateStoryEditor(model: model); XCTAssertEqual(fresh.beats.count, 1); XCTAssertEqual(fresh.beats.first?.text, "")
    }
    func testOrdinaryDisabledContentIsPreservedWhenAdded() throws {
        let (model, editor, _) = try setup(); model.draft.voiceEnabled = false; model.changed(); editor.reload()
        editor.addAction(.voice)(); XCTAssertEqual(model.draft.audioUrl, "/audio.m4a"); XCTAssertEqual(model.draft.audioDuration, 12); XCTAssertTrue(editor.enabled(.voice))
    }
    func testLoadRestoreDiscardOwnerLeaveAndBackgroundRejectCapturedReview() throws {
        for operation in ["load", "restore", "discard", "owner", "leave", "dismiss", "background"] {
            let (model, editor, owner) = try setup(), review = try request(.reward, editor), oldAction = editor.addAction(.voice)
            switch operation {
            case "load": model.load()
            case "restore": model.restore()
            case "discard": model.discard()
            case "owner": owner.session = try .init(accountID: 988, namespace: "optional-modules", epoch: 2, authorizationRevision: "member")
            case "leave": model.leave()
            case "background": editor.suspend()
            default: editor.retire()
            }
            let before = model.draft; editor.confirm(review); oldAction(); XCTAssertEqual(model.draft, before, operation); XCTAssertNil(editor.currentReview, operation)
        }
    }
    func testReopenCannotReviveOldReviewOrAction() throws {
        let (model, editor, _) = try setup(), review = try request(.reward, editor), action = editor.removalAction(.story)
        editor.retire(); editor.reload(); let before = model.draft; editor.confirm(review); action(); XCTAssertEqual(model.draft, before); XCTAssertNil(editor.currentReview)
    }
    func testBusyStateDeniesNewAndCapturedRemovals() throws {
        let (model, editor, _) = try setup(), review = try request(.reward, editor), before = model.draft
        model.busy = true; editor.confirm(review); XCTAssertFalse(editor.canEdit); editor.removalAction(.story)(); XCTAssertNil(editor.currentReview); XCTAssertEqual(model.draft, before)
    }
    func testNativeSaveRestoreKeepsRemovedAndReAddedState() throws {
        let store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage()), (model, editor, owner) = try setup(store: store)
        for module in TemplateOptionalModules.Module.allCases { editor.confirm(try request(module, editor)); editor.addAction(module)() }
        let expected = model.draft; editor.saveAction()(); editor.retire(); model.leave()
        let reopened = TemplateAuthoringModel(coordinator: .init(store: store, currentSession: { owner.session })); reopened.load(); reopened.restore()
        XCTAssertEqual(reopened.draft, expected); XCTAssertEqual(reopened.draft.storyImg, "/legacy.png"); XCTAssertFalse(reopened.coordinator.canSubmit)
    }
    func testPendingReviewCannotBeSavedOrReplacedByAdd() throws {
        let (model, editor, _) = try setup(), review = try request(.story, editor), before = model.draft
        editor.saveAction()(); editor.addAction(.voice)(); XCTAssertEqual(model.draft, before); XCTAssertEqual(editor.currentReview?.id, review.id)
    }
    func testPendingWriteLockRejectsModuleManager() throws {
        let (seedModel, _, owner) = try setup(), session = try XCTUnwrap(owner.session)
        let store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage()), identity = TemplateAuthoringIdentity(), seed = seedModel.draft
        try store.save(seed, session: session, identity: identity)
        try store.savePending(.init(operationID: UUID(), ownerKey: session.ownerKey, identity: identity, request: TemplateAuthoringContract.request(seed, intent: .saveDraft), createdAt: Date()), session: session)
        let model = TemplateAuthoringModel(coordinator: .init(store: store, currentSession: { session })); model.load(); model.draft = seed
        let editor = TemplateOptionalModuleController(model: model); editor.removalAction(.reward)(); editor.addAction(.voice)(); XCTAssertFalse(editor.canEdit); XCTAssertNil(editor.currentReview); XCTAssertEqual(model.draft, seed)
    }
}

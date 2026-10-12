import XCTest
@testable import Questify

@MainActor final class TemplateAuthoringExitGuardTests: XCTestCase {
    private final class Owner { var session: TemplateAuthoringSession?; init(_ session: TemplateAuthoringSession) { self.session = session } }
    private final class Overlay { var open = false }
    private final class Storage: TemplateAuthoringStorage {
        var values: [String: Data] = [:]
        var failReads = false, failWrites = false
        var writes = 0, removes = 0
        var onRead: (() -> Void)?
        func read(_ key: String) throws -> Data? { let action = onRead; onRead = nil; action?(); if failReads { throw TemplateAuthoringError.storageUnavailable }; return values[key] }
        func write(_ data: Data, key: String) throws { if failWrites { throw TemplateAuthoringError.storageUnavailable }; writes += 1; values[key] = data }
        func remove(_ key: String) throws { removes += 1; values.removeValue(forKey: key) }
    }
    private func setup() throws -> (TemplateAuthoringModel, TemplateAuthoringExitController, Owner, Storage, Overlay) {
        let owner = Owner(try .init(accountID: 999, namespace: "creator-exit", epoch: 1, authorizationRevision: "member")), storage = Storage(), overlay = Overlay()
        let model = TemplateAuthoringModel(coordinator: .init(store: .init(storage: storage), currentSession: { owner.session })); model.load()
        let controller = TemplateAuthoringExitController(model: model, overlaysOpen: { overlay.open }); controller.activate()
        return (model, controller, owner, storage, overlay)
    }
    private func edit(_ model: TemplateAuthoringModel, title: String = "Unsaved") { model.draft.title = title; model.changed() }
    func testCleanEmptyBackExitsOnceWithoutAnyWrite() throws {
        let (_,c,_,storage,_) = try setup(); var exits = 0; let back = c.backAction { exits += 1 }; back(); back()
        XCTAssertEqual(exits,1); XCTAssertNil(c.review); XCTAssertEqual(storage.writes,0); XCTAssertEqual(storage.removes,0)
    }
    func testDirtyBackAndContinuePreserveDraftStorageAndNavigation() throws {
        let (model,c,_,storage,_) = try setup(); edit(model); let before = model.draft; var exits = 0; c.backAction { exits += 1 }()
        let review = try XCTUnwrap(c.review); XCTAssertEqual(review.status,.unsaved); c.cancelAction(review)()
        XCTAssertEqual(exits,0); XCTAssertNil(c.review); XCTAssertEqual(model.draft,before); XCTAssertEqual(storage.writes,0); XCTAssertEqual(storage.removes,0)
    }
    func testConfirmedLeaveRetainsSavedRecordAndUnmodifiedCurrentDraft() throws {
        let (model,c,_,storage,_) = try setup(); edit(model,title:"Saved"); model.save(); let saved = storage.values; edit(model,title:"Changed"); let draft = model.draft; var exits = 0
        c.backAction { exits += 1 }(); let review = try XCTUnwrap(c.review), leave = c.leaveAction(review) { exits += 1 }; leave(); leave()
        XCTAssertEqual(exits,1); XCTAssertEqual(storage.values,saved); XCTAssertEqual(storage.removes,0); XCTAssertEqual(model.draft,draft)
    }
    func testExistingSuccessfulLocalSaveMakesBackClean() throws {
        let (model,c,_,storage,_) = try setup(); edit(model); model.save(); let writes = storage.writes; var exits = 0; c.backAction { exits += 1 }()
        XCTAssertEqual(exits,1); XCTAssertNil(c.review); XCTAssertEqual(storage.writes,writes)
    }
    func testChangesAfterLocalSavePromptAgain() throws {
        let (model,c,_,_,_) = try setup(); edit(model); model.save(); edit(model,title:"Newer"); var exits = 0; c.backAction { exits += 1 }()
        XCTAssertEqual(c.review?.status,.unsaved); XCTAssertEqual(exits,0)
    }
    func testFailedLocalSaveDoesNotMarkDraftClean() throws {
        let (model,c,_,storage,_) = try setup(); edit(model); storage.failWrites = true; model.save(); XCTAssertEqual(model.coordinator.messageKey,"templateAuthor.storageFailed")
        var exits = 0; c.backAction { exits += 1 }(); XCTAssertEqual(c.review?.status,.unsaved); XCTAssertEqual(exits,0); XCTAssertTrue(storage.values.isEmpty)
    }
    func testReadFailureOffersUnverifiedReviewAndRealRecheckCanExitClean() throws {
        let (model,c,_,storage,_) = try setup(); edit(model); model.save(); storage.failReads = true; var exits = 0; c.backAction { exits += 1 }()
        let review = try XCTUnwrap(c.review); XCTAssertEqual(review.status,.unverified); storage.failReads = false; c.retryAction(review) { exits += 1 }()
        XCTAssertEqual(exits,1); XCTAssertNil(c.review); XCTAssertEqual(storage.removes,0)
    }
    func testCorruptCheckpointRequiresExplicitReviewAndIsNeverDeleted() throws {
        let (model,c,_,storage,_) = try setup(); edit(model); model.save()
        let envelopeKeys = storage.values.filter { (try? JSONDecoder().decode(TemplateAuthoringEnvelope.self,from:$0.value)) != nil }.map(\.key)
        for key in envelopeKeys { storage.values[key] = Data("broken".utf8) }
        let saved = storage.values; var exits = 0; c.backAction { exits += 1 }(); let review = try XCTUnwrap(c.review); XCTAssertEqual(review.status,.unverified)
        c.leaveAction(review) { exits += 1 }(); XCTAssertEqual(exits,1); XCTAssertEqual(storage.values,saved); XCTAssertEqual(storage.removes,0)
    }
    func testCheckpointReadDoesNotChangeCoordinatorOrStoreState() throws {
        let (model,_,_,storage,_) = try setup(); edit(model); model.save(); let draft = model.coordinator.draft, identity = model.coordinator.identity, state = model.coordinator.state, message = model.coordinator.messageKey, values = storage.values, writes = storage.writes
        guard case .ready(let value) = model.coordinator.localCheckpointForExit() else { return XCTFail("Expected saved checkpoint") }
        XCTAssertEqual(value.draft,draft); XCTAssertEqual(model.coordinator.draft,draft); XCTAssertEqual(model.coordinator.identity,identity); XCTAssertEqual(model.coordinator.state,state); XCTAssertEqual(model.coordinator.messageKey,message); XCTAssertEqual(storage.values,values); XCTAssertEqual(storage.writes,writes); XCTAssertEqual(storage.removes,0)
    }
    func testOwnerChangeDuringCheckpointReadRejectsTheReturnedRecordAndExit() throws {
        let (model,c,owner,storage,_) = try setup(); edit(model); model.save(); let next = try TemplateAuthoringSession(accountID:1000,namespace:"creator-exit",epoch:2,authorizationRevision:"member")
        storage.onRead = { owner.session = next }; var exits = 0; c.backAction { exits += 1 }(); XCTAssertEqual(exits,0); XCTAssertNil(c.review)
        XCTAssertEqual(model.coordinator.localCheckpointForExit(),.unavailable)
    }
    func testRetainedBackBeforeAnEditCannotExitTheNewDraft() throws {
        let (model,c,_,_,_) = try setup(); var exits = 0; let old = c.backAction { exits += 1 }; edit(model); old(); XCTAssertEqual(exits,0); XCTAssertNil(c.review)
    }
    func testOldConfirmCancelAndPresentationSetterCannotAffectNewReview() throws {
        let (model,c,_,_,_) = try setup(); edit(model); var exits = 0; c.backAction { exits += 1 }(); let first = try XCTUnwrap(c.review), oldBinding = c.presentationBinding(), leave = c.leaveAction(first) { exits += 1 }, cancel = c.cancelAction(first)
        edit(model,title:"Newer"); c.backAction { exits += 1 }(); let second = try XCTUnwrap(c.review); leave(); cancel(); oldBinding.wrappedValue = false
        XCTAssertEqual(c.review?.id,second.id); XCTAssertEqual(exits,0)
    }
    func testWholeDraftABAFencesEarlierLeaveAction() throws {
        let (model,c,_,_,_) = try setup(); edit(model); let before = model.draft; var exits = 0; c.backAction { exits += 1 }(); let leave = c.leaveAction(try XCTUnwrap(c.review)) { exits += 1 }
        model.draft.title = "Changed"; model.draft = before; leave(); XCTAssertEqual(exits,0); XCTAssertNil(c.review)
    }
    func testOwnerSwitchInvalidatesConfirmWithoutTouchingEitherOwnersStorage() throws {
        let (model,c,owner,storage,_) = try setup(); edit(model); var exits = 0; c.backAction { exits += 1 }(); let leave = c.leaveAction(try XCTUnwrap(c.review)) { exits += 1 }, values = storage.values
        owner.session = try .init(accountID:1000,namespace:"creator-exit",epoch:2,authorizationRevision:"member"); leave(); XCTAssertEqual(exits,0); XCTAssertEqual(storage.values,values)
    }
    func testBusyAndPublicationReviewBlockTheEditorBackRoute() throws {
        let (model,c,_,_,_) = try setup(); var exits = 0; model.busy = true; c.backAction { exits += 1 }(); XCTAssertFalse(c.canRequestBack); XCTAssertEqual(exits,0)
        model.busy = false; model.draft = TemplateAuthoringSyntheticFixtures.draft(); model.changed(); model.prepare(.saveDraft); XCTAssertNotNil(model.review)
        c.backAction { exits += 1 }(); XCTAssertFalse(c.canRequestBack); XCTAssertEqual(exits,0)
    }
    func testPreviewMediaAndDiscardOverlaysBlockOldBackWithoutClosingThem() throws {
        let (_,c,_,_,overlay) = try setup(); var exits = 0; let old = c.backAction { exits += 1 }; overlay.open = true; old(); XCTAssertEqual(exits,0); XCTAssertFalse(c.canRequestBack); XCTAssertTrue(overlay.open)
        c.overlayChanged(); overlay.open = false; c.overlayChanged(); old(); XCTAssertEqual(exits,0); c.backAction { exits += 1 }(); XCTAssertEqual(exits,1)
    }
    func testBackgroundCloseAndReentryRetireLeaveAndRetryCallbacks() throws {
        let (model,c,_,storage,_) = try setup(); edit(model); storage.failReads = true; var exits = 0; c.backAction { exits += 1 }(); let old = try XCTUnwrap(c.review), leave = c.leaveAction(old) { exits += 1 }, retry = c.retryAction(old) { exits += 1 }
        c.retire(); c.activate(); leave(); retry(); XCTAssertEqual(exits,0); XCTAssertNil(c.review); XCTAssertEqual(model.draft.title,"Unsaved")
        c.backAction { exits += 1 }(); XCTAssertEqual(c.review?.status,.unverified)
    }
    func testExternalLeaveAndMetadataLifecycleInvalidatePendingConfirmation() throws {
        let (model,c,_,_,_) = try setup(); edit(model); var exits = 0; c.backAction { exits += 1 }(); let leave = c.leaveAction(try XCTUnwrap(c.review)) { exits += 1 }; model.leave(); leave(); XCTAssertEqual(exits,0); XCTAssertNil(c.review)
    }
}

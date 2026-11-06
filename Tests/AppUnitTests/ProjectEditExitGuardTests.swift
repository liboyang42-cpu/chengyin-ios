import XCTest
import SwiftUI
import UIKit
@testable import Questify

@MainActor final class ProjectEditExitGuardTests: XCTestCase {
    @MainActor private final class Account {
        var session: ProjectEditSession?
        init(guest: Bool) throws { session = guest ? nil : try .init(accountID: 901, epoch: 1, storageNamespace: "project-exit-tests") }
    }
    @MainActor private final class Storage: ProjectEditDataStorage {
        var data: [String: Data] = [:]
        var writes = 0, removes = 0
        var fail = false
        var failAt: Int?
        var onWrite: (() -> Void)?
        func read(_ key: String) throws -> Data? { data[key] }
        func write(_ value: Data, key: String) throws {
            writes += 1; onWrite?()
            if fail || writes == failAt { throw ProjectEditError.persistenceUnavailable }
            data[key] = value
        }
        func remove(_ key: String) throws { removes += 1; data[key] = nil }
    }
    @MainActor private final class Harness {
        let account: Account
        let storage: Storage
        let store: ProjectEditLocalStore
        let service: ProjectEditSyntheticService
        let model: ProjectEditModel
        var overlay = false
        var exits = 0
        lazy var owner = ProjectEditExitController(model: model, overlaysOpen: { [weak self] in self?.overlay == true })
        init(guest: Bool = false, scenario: ProjectEditSyntheticService.Scenario = .accepted, existing: Bool = false) throws {
            let account = try Account(guest: guest), storage = Storage()
            let store = ProjectEditLocalStore(storage: storage)
            let baseline = existing ? ProjectEditSyntheticFixtures.snapshot(scope: .whitelist) : ProjectEditSnapshot(draft: ProjectEditSyntheticFixtures.draft(product: .freeExplore))
            let service = ProjectEditSyntheticService(scenario: scenario, snapshot: baseline)
            self.account = account; self.storage = storage; self.store = store; self.service = service
            model = .init(coordinator: .init(initial: baseline, service: service, store: store, currentSession: { account.session }))
        }
        func load() async { await model.load(); owner.appear(active: true) }
        func back() { owner.backAction { self.exits += 1 }() }
        func failure() throws -> ProjectEditExitController.Review { try XCTUnwrap(owner.review) }
    }
    func testNormalBackPersistsFullDraftBeforeExitAndDepartureDoesNotWriteTwice() async throws {
        let h = try Harness(); await h.load(); h.model.draft.name = "  Exact e\u{301} local draft  "
        let bytes = ProjectEditPendingMaterials.exactData(h.model.draft)
        h.back(); XCTAssertEqual(h.exits, 1); XCTAssertNil(h.owner.review); XCTAssertEqual(h.storage.writes, 2)
        let identity = try XCTUnwrap(h.model.coordinator.identity), session = try XCTUnwrap(h.account.session)
        guard case .ready(let stored) = h.store.load(session: session, identity: identity, baseline: h.model.draft) else { return XCTFail("Saved draft missing") }
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(stored.draft), bytes)
        h.model.leave(); XCTAssertEqual(h.storage.writes, 2); XCTAssertTrue(h.service.submissions.isEmpty)
    }
    func testFailedSaveKeepsWholeDraftAndDoesNotExit() async throws {
        let h = try Harness(); await h.load(); h.model.draft.name = "Unsaved change"; h.storage.fail = true
        let bytes = ProjectEditPendingMaterials.exactData(h.model.draft)
        h.back(); XCTAssertEqual(try h.failure().reason, .saveFailed); XCTAssertEqual(h.exits, 0)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(h.model.draft), bytes)
        XCTAssertTrue(h.storage.data.isEmpty); XCTAssertTrue(h.service.submissions.isEmpty)
    }
    func testContinueAfterFailureRetainsInputWithoutAnotherWrite() async throws {
        let h = try Harness(); await h.load(); h.storage.fail = true; h.back()
        let review = try h.failure(), writes = h.storage.writes, draft = h.model.draft
        h.owner.continueAction(review)()
        XCTAssertNil(h.owner.review); XCTAssertEqual(h.exits, 0); XCTAssertEqual(h.storage.writes, writes)
        XCTAssertEqual(h.model.draft, draft); XCTAssertTrue(h.owner.canRequestBack)
    }
    func testExplicitRetryAfterStorageRecoversSavesThenExits() async throws {
        let h = try Harness(); await h.load(); h.storage.fail = true; h.back()
        let review = try h.failure(); h.storage.fail = false
        h.owner.retryAction(review) { h.exits += 1 }()
        XCTAssertNil(h.owner.review); XCTAssertEqual(h.exits, 1); XCTAssertEqual(h.storage.writes, 3)
        XCTAssertFalse(h.storage.data.isEmpty); XCTAssertTrue(h.service.submissions.isEmpty)
    }
    func testRepeatedFailedRetryStaysInEditorWithFreshConfirmation() async throws {
        let h = try Harness(); await h.load(); h.storage.fail = true; h.back()
        let first = try h.failure()
        h.owner.retryAction(first) { h.exits += 1 }(); let second = try h.failure()
        XCTAssertNotEqual(first.id, second.id); XCTAssertEqual(second.reason, .saveFailed)
        XCTAssertEqual(h.exits, 0); XCTAssertEqual(h.storage.writes, 2)
        h.owner.leaveAction(first) { h.exits += 1 }(); XCTAssertEqual(h.exits, 0)
    }
    func testExplicitLeaveAfterFailureDoesNotRetryOrDeleteDraft() async throws {
        let h = try Harness(); await h.load(); h.model.saveLocal(); let saved = h.storage.data
        h.model.draft.name = "New unsaved"; h.storage.fail = true; h.back()
        let review = try h.failure(), writes = h.storage.writes
        h.owner.leaveAction(review) { h.exits += 1 }(); h.model.leave()
        XCTAssertEqual(h.exits, 1); XCTAssertEqual(h.storage.writes, writes); XCTAssertEqual(h.storage.removes, 0)
        XCTAssertEqual(h.storage.data, saved); XCTAssertTrue(h.service.submissions.isEmpty)
    }
    func testPartialPointerFailureNeverClaimsSavedOrExitsAutomatically() async throws {
        let h = try Harness(); await h.load(); h.storage.failAt = 2
        h.back(); XCTAssertEqual(h.exits, 0); XCTAssertEqual(try h.failure().reason, .saveFailed)
        XCTAssertEqual(h.storage.writes, 2); XCTAssertEqual(h.storage.data.count, 1)
        h.owner.retryAction(try h.failure()) { h.exits += 1 }()
        XCTAssertEqual(h.exits, 1); XCTAssertEqual(h.storage.data.count, 2)
    }
    func testUnchangedGuestCanReturnWithoutPersistence() async throws {
        let h = try Harness(guest: true); await h.load(); h.back()
        XCTAssertEqual(h.exits, 1); XCTAssertNil(h.owner.review); XCTAssertEqual(h.storage.writes, 0)
        XCTAssertTrue(h.service.submissions.isEmpty)
    }
    func testEditedGuestMustChooseContinueOrLeaveWithNoPersistence() async throws {
        let h = try Harness(guest: true); await h.load(); h.model.draft.name = "Guest only"
        h.back(); let review = try h.failure(); XCTAssertEqual(review.reason, .memoryOnly); XCTAssertEqual(h.exits, 0)
        h.owner.retryAction(review) { h.exits += 1 }(); XCTAssertEqual(h.exits, 0)
        h.owner.continueAction(review)(); XCTAssertEqual(h.model.draft.name, "Guest only")
        h.back(); h.owner.leaveAction(try h.failure()) { h.exits += 1 }(); h.model.leave()
        XCTAssertEqual(h.exits, 1); XCTAssertEqual(h.storage.writes, 0); XCTAssertTrue(h.service.submissions.isEmpty)
    }
    func testGuestChangedThenExactlyRestoredDoesNotPrompt() async throws {
        let h = try Harness(guest: true); await h.load(); let original = h.model.draft
        h.model.draft.name = "Changed"; h.model.draft = original; h.back()
        XCTAssertEqual(h.exits, 1); XCTAssertNil(h.owner.review)
    }
    func testUnknownSubmissionLeavesOriginalRequestAndMaterialUntouched() async throws {
        let h = try Harness(scenario: .unknown); await h.load(); h.model.review()
        await h.model.submit(try XCTUnwrap(h.model.confirmation))
        XCTAssertTrue(h.model.coordinator.isLocked)
        let request = try XCTUnwrap(h.model.coordinator.pending), data = h.storage.data, writes = h.storage.writes
        h.back(); h.model.leave()
        XCTAssertEqual(h.exits, 1); XCTAssertEqual(h.storage.data, data); XCTAssertEqual(h.storage.writes, writes)
        XCTAssertEqual(h.service.submissions.count, 1)
        let session = try XCTUnwrap(h.account.session)
        XCTAssertEqual(try h.store.pending(session: session, identity: request.identity)?.operationID, request.operationID)
        XCTAssertTrue(h.model.coordinator.isLocked)
    }
    func testTerminalReceiptBackDoesNotSubmitOrRewrite() async throws {
        let h = try Harness(); await h.load(); h.model.review(); await h.model.submit(try XCTUnwrap(h.model.confirmation))
        XCTAssertEqual(h.model.coordinator.state, .simulated)
        let data = h.storage.data, writes = h.storage.writes
        h.back(); h.model.leave()
        XCTAssertEqual(h.exits, 1); XCTAssertEqual(h.storage.data, data); XCTAssertEqual(h.storage.writes, writes)
        XCTAssertEqual(h.service.submissions.count, 1)
    }
    func testUnreviewedRestoreIsNotOverwrittenOnBack() async throws {
        let h = try Harness(); await h.load(); h.model.draft.name = "Saved original"; h.model.saveLocal()
        let data = h.storage.data, writes = h.storage.writes
        let replacement = ProjectEditModel(coordinator: h.model.coordinator)
        await replacement.load(); XCTAssertTrue(replacement.hasRestore)
        let owner = ProjectEditExitController(model: replacement); owner.appear(active: true)
        owner.backAction { h.exits += 1 }(); replacement.leave()
        XCTAssertEqual(h.exits, 1); XCTAssertEqual(h.storage.data, data); XCTAssertEqual(h.storage.writes, writes)
    }
    func testWhitelistBackPreservesAllLockedFieldsAndOnlySavesExistingDraft() async throws {
        let h = try Harness(existing: true); await h.load(); XCTAssertFalse(h.model.fullEdit)
        let before = h.model.draft; h.back()
        XCTAssertEqual(h.exits, 1); XCTAssertEqual(h.model.draft, before); XCTAssertEqual(h.storage.writes, 1)
        XCTAssertTrue(h.service.submissions.isEmpty)
    }
    func testOldBackActionCannotWriteChangedDraftOrSameBytesABA() async throws {
        let h = try Harness(); await h.load(); let back = h.owner.backAction { h.exits += 1 }, original = h.model.draft
        h.model.draft.name = "Other"; h.model.draft = original; back()
        XCTAssertEqual(h.exits, 0); XCTAssertEqual(h.storage.writes, 0)
        h.back(); XCTAssertEqual(h.exits, 1)
    }
    func testAccountChangeRejectsOldFailureLeaveRetryAndContinue() async throws {
        let h = try Harness(); await h.load(); h.storage.fail = true; h.back(); let review = try h.failure()
        let writes = h.storage.writes
        h.account.session = try .init(accountID: 902, epoch: 2, storageNamespace: "project-exit-tests")
        h.owner.leaveAction(review) { h.exits += 1 }(); h.owner.retryAction(review) { h.exits += 1 }(); h.owner.continueAction(review)()
        XCTAssertEqual(h.exits, 0); XCTAssertEqual(h.storage.writes, writes); XCTAssertEqual(h.owner.review?.id, review.id)
    }
    func testReplacementEditorVisitRejectsOldConfirmation() async throws {
        let h = try Harness(); await h.load(); h.storage.fail = true; h.back(); let review = try h.failure()
        let replacement = ProjectEditModel(coordinator: h.model.coordinator); await replacement.load()
        h.owner.leaveAction(review) { h.exits += 1 }(); h.owner.retryAction(review) { h.exits += 1 }()
        XCTAssertEqual(h.exits, 0); XCTAssertFalse(h.model.ownsVisit); XCTAssertTrue(replacement.ownsVisit)
    }
    func testDraftMutationImmediatelyRetiresFailureConfirmation() async throws {
        let h = try Harness(); await h.load(); h.storage.fail = true; h.back(); let review = try h.failure()
        h.model.draft.description = "Updated after failure"
        XCTAssertNil(h.owner.review); h.owner.leaveAction(review) { h.exits += 1 }()
        XCTAssertEqual(h.exits, 0); XCTAssertEqual(h.model.draft.description, "Updated after failure")
    }
    func testHiddenForegroundDoesNotReviveOldBackOrConfirmation() async throws {
        let h = try Harness(); await h.load(); h.storage.fail = true; h.back(); let review = try h.failure()
        h.owner.disappear(); h.owner.sceneChanged(active: true)
        h.owner.leaveAction(review) { h.exits += 1 }(); XCTAssertEqual(h.exits, 0); XCTAssertFalse(h.owner.canRequestBack)
        h.owner.appear(active: true); h.back(); XCTAssertNotEqual(h.owner.review?.id, review.id)
    }
    func testVisibleBackgroundRetiresOldConfirmationButFreshBackCanRetry() async throws {
        let h = try Harness(); await h.load(); h.storage.fail = true; h.back(); let review = try h.failure()
        h.owner.sceneChanged(active: false); h.owner.sceneChanged(active: true)
        h.owner.retryAction(review) { h.exits += 1 }(); XCTAssertEqual(h.storage.writes, 1)
        h.back(); XCTAssertEqual(h.storage.writes, 2); XCTAssertEqual(h.exits, 0)
    }
    func testRepeatedAppearanceDoesNotDropVisibleFailureReview() async throws {
        let h = try Harness(); await h.load(); h.storage.fail = true; h.back(); let review = try h.failure()
        h.owner.appear(active: true); XCTAssertEqual(h.owner.review?.id, review.id)
        h.owner.continueAction(review)(); XCTAssertNil(h.owner.review)
    }
    func testExistingOverlayPreventsCapturedBackUntilClosed() async throws {
        let h = try Harness(); await h.load(); let back = h.owner.backAction { h.exits += 1 }
        h.overlay = true; back(); XCTAssertEqual(h.exits, 0); XCTAssertEqual(h.storage.writes, 0)
        h.owner.overlayChanged(); h.overlay = false; back(); XCTAssertEqual(h.exits, 0)
        h.back(); XCTAssertEqual(h.exits, 1)
    }
    func testExistingSubmitReviewIsNeverCancelledByBackGuard() async throws {
        let h = try Harness(); await h.load(); h.model.review(); let review = try XCTUnwrap(h.model.confirmation)
        let data = h.storage.data, writes = h.storage.writes
        h.back(); XCTAssertEqual(h.exits, 0); XCTAssertEqual(h.model.confirmation?.id, review.id)
        XCTAssertEqual(h.storage.data, data); XCTAssertEqual(h.storage.writes, writes)
    }
    func testNativeContainerRequiredDoesNotPermitBeforeAttachment() async throws {
        let h = try Harness(); await h.load()
        let owner = ProjectEditExitController(model: h.model, requiresNativeRoot: true); owner.appear(active: true)
        owner.backAction { h.exits += 1 }(); XCTAssertFalse(owner.canRequestBack)
        XCTAssertEqual(h.exits, 0); XCTAssertEqual(h.storage.writes, 0)
        let detached = UIViewController(); owner.attach(detached)
        XCTAssertFalse(owner.canRequestBack); owner.detach(detached); XCTAssertFalse(owner.canRequestBack)
    }
    func testOwnerChangeDuringLocalWriteCannotDismissNewContext() async throws {
        let h = try Harness(); await h.load()
        h.storage.onWrite = { h.account.session = nil }; h.back()
        XCTAssertEqual(h.exits, 0); XCTAssertNil(h.owner.review); XCTAssertTrue(h.service.submissions.isEmpty)
    }
    func testConfirmedExitCannotSuppressLaterChangedDraftDepartureSave() async throws {
        let h = try Harness(); await h.load(); h.back(); let writes = h.storage.writes
        h.model.draft.name = "Changed before actual departure"; h.model.leave()
        XCTAssertEqual(h.storage.writes, writes + 2)
        XCTAssertTrue(h.service.submissions.isEmpty)
    }
}

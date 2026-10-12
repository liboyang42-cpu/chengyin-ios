import XCTest
@testable import Questify

@MainActor final class CouponValidityRangeEditorTests: XCTestCase {
    private let owner = NSObject()
    private func session(_ account: Int = 1, epoch: UInt64 = 1, revision: String = "approved-read") throws -> CouponManagementSession {
        try .init(accountID: account, namespace: "synthetic", epoch: epoch, authorizationRevision: revision)
    }
    private func draft() -> CouponManagementDraft {
        var value = CouponManagementDraft(); value.name = "Synthetic"; value.description = "Keep"; value.quantity = "3"; value.couponType = 0
        value.startTime = Date(timeIntervalSince1970: 1_800_000_000); value.endTime = Date(timeIntervalSince1970: 1_800_003_600)
        return value
    }
    private func context(session: CouponManagementSession? = nil) throws -> CouponValidityRangeContext {
        .init(coordinatorID: ObjectIdentifier(owner), session: try session ?? self.session(), draft: draft())
    }
    func testCancelledLocalEditHasNoSourceCallbackAndCannotBeConfirmedLater() throws {
        let source = try context(); var calls = 0
        let model = try XCTUnwrap(CouponValidityRangeEditorModel(current: { source }, apply: { _, _ in calls += 1; return true }))
        model.setEnd(source.draft.endTime!.addingTimeInterval(3600)); model.cancel()
        XCTAssertFalse(model.confirm()); XCTAssertEqual(calls, 0); XCTAssertEqual(source.draft, draft())
    }
    func testValidApplyCommitsPairOnceAndPreservesRestOfSource() throws {
        let source = try context(); var result: CouponManagementDraft?; var calls = 0
        let model = try XCTUnwrap(CouponValidityRangeEditorModel(current: { source }, apply: { expected, value in
            XCTAssertTrue(expected.matches(source)); calls += 1; result = value; return true
        }))
        model.setStart(source.draft.startTime!.addingTimeInterval(60)); model.setEnd(source.draft.endTime!.addingTimeInterval(120))
        XCTAssertTrue(model.confirm()); XCTAssertFalse(model.confirm()); XCTAssertEqual(calls, 1)
        var restored = try XCTUnwrap(result); restored.startTime = source.draft.startTime; restored.endTime = source.draft.endTime
        XCTAssertEqual(restored, source.draft)
    }
    func testInvalidRangeStaysLocalAndCanBeCorrectedBeforeApply() throws {
        let source = try context(); var calls = 0
        let model = try XCTUnwrap(CouponValidityRangeEditorModel(current: { source }, apply: { _, _ in calls += 1; return true }))
        model.setEnd(source.draft.startTime); XCTAssertFalse(model.canApply); XCTAssertFalse(model.confirm())
        XCTAssertTrue(model.active); XCTAssertEqual(calls, 0)
        model.setEnd(source.draft.endTime); XCTAssertTrue(model.confirm()); XCTAssertEqual(calls, 1)
    }
    func testIdentityEpochAndAuthorizationChangeRejectOldSheet() throws {
        for changed in [try session(2), try session(epoch: 2), try session(revision: "new-approval")] {
            var current: CouponValidityRangeContext? = try context(); var calls = 0
            let model = try XCTUnwrap(CouponValidityRangeEditorModel(current: { current }, apply: { _, _ in calls += 1; return true }))
            current = try context(session: changed)
            XCTAssertFalse(model.confirm()); XCTAssertEqual(calls, 0); XCTAssertFalse(model.active)
        }
    }
    func testLogoutCoordinatorReplacementAndOtherFieldChangesCannotBeOverwritten() throws {
        let replacement = NSObject()
        for mode in 0..<3 {
            let original = try context(); var current: CouponValidityRangeContext? = original; var calls = 0
            let model = try XCTUnwrap(CouponValidityRangeEditorModel(current: { current }, apply: { _, _ in calls += 1; return true }))
            if mode == 0 { current = nil }
            if mode == 1 { current = .init(coordinatorID: ObjectIdentifier(replacement), session: original.session, draft: original.draft) }
            if mode == 2 { var changed = original.draft; changed.name = "Newer draft"; current = .init(coordinatorID: original.coordinatorID, session: original.session, draft: changed) }
            XCTAssertFalse(model.confirm()); current = original
            XCTAssertFalse(model.confirm()); XCTAssertEqual(calls, 0)
        }
    }
    func testFailedFinalApplyConsumesWithoutReplay() throws {
        let source = try context(); var calls = 0
        let model = try XCTUnwrap(CouponValidityRangeEditorModel(current: { source }, apply: { _, _ in calls += 1; return false }))
        XCTAssertFalse(model.confirm()); XCTAssertFalse(model.confirm()); XCTAssertEqual(calls, 1)
        XCTAssertEqual(model.issue, "couponManagement.changed")
    }
    func testNormalEditorFactoryUsesExistingLocalChangeWithoutReadingOrWriting() throws {
        let session = try session(), locks = LocalRangeLocks(), source = draft()
        let core = CouponManagementCoordinator(adapter: .init(), authorizer: CouponPublisherUnavailable(), locks: locks, currentSession: { session })
        core.change(source)
        let screen = CouponManagementScreenModel(core)
        let editor = try XCTUnwrap(CouponValidityRangeEditorModel.make(screen: screen))
        editor.setEnd(source.endTime!.addingTimeInterval(3600)); XCTAssertTrue(editor.confirm())
        XCTAssertEqual(core.draft.endTime, source.endTime!.addingTimeInterval(3600))
        XCTAssertEqual(core.draft.name, source.name); XCTAssertEqual(screen.revision, 1)
        XCTAssertFalse(core.canSubmit); XCTAssertNil(core.review); XCTAssertEqual(locks.calls, 0)
    }
    func testNormalEditorFactoryRejectsBusyOrUnownedSource() throws {
        var current: CouponManagementSession? = try session()
        let core = CouponManagementCoordinator(adapter: .init(), authorizer: CouponPublisherUnavailable(), locks: LocalRangeLocks(), currentSession: { current })
        core.change(draft()); let screen = CouponManagementScreenModel(core)
        screen.working = true; XCTAssertNil(CouponValidityRangeEditorModel.make(screen: screen))
        screen.working = false; current = nil; XCTAssertNil(CouponValidityRangeEditorModel.make(screen: screen))
    }
}

@MainActor private final class LocalRangeLocks: CouponManagementLocking {
    var calls = 0
    func pending(ownerKey: String, resource: String) throws -> CouponManagementPending? { calls += 1; return nil }
    func acquire(_ pending: CouponManagementPending) throws { calls += 1 }
    func release(_ pending: CouponManagementPending) throws { calls += 1 }
}

extension CouponValidityRangeEditorTests {
    func testExistingPublishReviewSurvivesCancelAndIsClearedOnlyByApply() async throws {
        let owner = try session(), locks = LocalRangeLocks(), permission = LocalRangePublisher()
        let core = CouponManagementCoordinator(adapter: .init(), authorizer: permission, locks: locks, currentSession: { owner })
        core.change(draft()); await core.preparePublish()
        let review = try XCTUnwrap(core.review), screen = CouponManagementScreenModel(core)
        let cancelled = try XCTUnwrap(CouponValidityRangeEditorModel.make(screen: screen))
        cancelled.setEnd(core.draft.endTime!.addingTimeInterval(3600)); cancelled.cancel()
        XCTAssertEqual(core.review, review)
        let applied = try XCTUnwrap(CouponValidityRangeEditorModel.make(screen: screen))
        applied.setEnd(core.draft.endTime!.addingTimeInterval(3600)); XCTAssertTrue(applied.confirm())
        XCTAssertNil(core.review); XCTAssertEqual(permission.calls, 1); XCTAssertEqual(locks.calls, 1)
        XCTAssertFalse(core.canSubmit)
    }
}
@MainActor private final class LocalRangePublisher: CouponPublisherAuthorizing {
    var calls = 0
    func freshPermission(session: CouponManagementSession) async throws -> CouponPublisherPermission {
        calls += 1; return .init(revision: "synthetic-local-preview", mayPublish: true)
    }
}


extension CouponValidityRangeEditorTests {
    func testNormalFactoryRejectsUnobservedDraftABAUsingSourceRevision() throws {
        let owner = try session(), locks = LocalRangeLocks(), source = draft()
        let core = CouponManagementCoordinator(adapter: .init(), authorizer: CouponPublisherUnavailable(), locks: locks, currentSession: { owner })
        core.change(source)
        let screen = CouponManagementScreenModel(core)
        let editor = try XCTUnwrap(CouponValidityRangeEditorModel.make(screen: screen))
        editor.setEnd(source.endTime!.addingTimeInterval(3600))
        var interim = source; interim.name = "Interim draft"
        screen.update(interim)
        screen.update(source) // No old-editor call occurs between the two source changes.
        XCTAssertEqual(core.draft, source); XCTAssertEqual(screen.revision, 2)
        XCTAssertFalse(editor.confirm()); XCTAssertFalse(editor.active)
        XCTAssertEqual(core.draft, source); XCTAssertEqual(screen.revision, 2)
        XCTAssertEqual(locks.calls, 0); XCTAssertNil(core.review); XCTAssertFalse(core.canSubmit)
    }

    func testNormalFactorySynchronizesNewPrincipalBeforeCapturingOldDraft() throws {
        let original = try session(), replacement = try session(2), locks = LocalRangeLocks(), source = draft()
        var current: CouponManagementSession? = original
        let core = CouponManagementCoordinator(adapter: .init(), authorizer: CouponPublisherUnavailable(), locks: locks, currentSession: { current })
        core.change(source)
        let screen = CouponManagementScreenModel(core)
        current = replacement // The parent task and screen.synchronize() have not run.
        XCTAssertEqual(core.draft, source); XCTAssertEqual(screen.revision, 0)
        let editor = try XCTUnwrap(CouponValidityRangeEditorModel.make(screen: screen))
        XCTAssertEqual(core.session, replacement); XCTAssertEqual(core.draft, CouponManagementDraft())
        XCTAssertNil(editor.selection.startTime); XCTAssertNil(editor.selection.endTime)
        let start = Date(timeIntervalSince1970: 1_900_000_000), end = start.addingTimeInterval(3600)
        editor.setStart(start); editor.setEnd(end); XCTAssertTrue(editor.confirm())
        var expected = CouponManagementDraft(); expected.startTime = start; expected.endTime = end
        XCTAssertEqual(core.draft, expected); XCTAssertEqual(core.session, replacement)
        XCTAssertEqual(screen.revision, 1); XCTAssertEqual(locks.calls, 0)
        XCTAssertNil(core.review); XCTAssertFalse(core.canSubmit)
    }
}

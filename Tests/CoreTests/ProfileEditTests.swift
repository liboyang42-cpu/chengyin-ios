import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class ProfileEditTests: XCTestCase {
    private func snapshot(_ changes: [String: Any] = [:]) throws -> ProfileEditSnapshot {
        var object: [String: Any] = ["id": 901, "nickname": "Trail Friend", "introduction": "Weekend walks", "avatar": " raw-avatar ", "wechat": " contact-qr ", "casePics": "one;;two;", "tagIds": "7,4"]
        object.merge(changes) { _, new in new }
        return try JSONDecoder().decode(ProfileEditSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
    }
    func testPayloadTrimsOnlyEditedFieldsAndPreservesReplacementValues() throws {
        let source = try snapshot()
        let payload = try ProfileEditPayload(draft: .init(name: " New Name\n", introduction: " New bio "), preserving: source)
        XCTAssertEqual(payload.name, "New Name"); XCTAssertEqual(payload.introduction, "New bio")
        XCTAssertEqual(payload.avatar, " raw-avatar "); XCTAssertEqual(payload.wechat, " contact-qr ")
        XCTAssertEqual(payload.casePics, "one;;two;"); XCTAssertEqual(payload.tagIds, "7,4")
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: String])
        XCTAssertEqual(Set(json.keys), Set(["name", "introduction", "avatar", "wechat", "casePics", "tagIds"]))
        XCTAssertThrowsError(try ProfileEditPayload(draft: .init(name: " \n"), preserving: source))
    }
    func testMissingPreservationFailsClosed() throws {
        let json = Data(#"{"id":901,"nickname":"A","introduction":"","avatar":"","wechat":"","tagIds":""}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(ProfileEditSnapshot.self, from: json))
    }
    @MainActor func testConfirmationIsImmutableAndReadbackVerifiesSuccess() async throws {
        let service = ProfileEditSyntheticService()
        let session = try ProfileEditSession(accountID: 901, epoch: 1, token: "fixture")
        let coordinator = ProfileEditCoordinator(service: service, currentSession: { session })
        await coordinator.load()
        var draft = ProfileEditDraft(name: "Confirmed Name", introduction: "Confirmed bio")
        await coordinator.prepare(draft)
        let confirmation = try XCTUnwrap(coordinator.confirmation)
        draft.name = "Later typing"
        await coordinator.save(confirmation)
        XCTAssertEqual(coordinator.snapshot?.nickname, "Confirmed Name")
        XCTAssertEqual(coordinator.messageKey, "profile.edit.saved")
        XCTAssertFalse(coordinator.isLocked)
        await coordinator.save(confirmation)
        XCTAssertEqual(coordinator.snapshot?.nickname, "Confirmed Name")
    }
    @MainActor func testUnknownOutcomeRemainsLockedAcrossNavigationAndSameAccountEpoch() async throws {
        var session: ProfileEditSession? = try .init(accountID: 901, epoch: 1, token: "fixture")
        let coordinator = ProfileEditCoordinator(service: ProfileEditSyntheticService(scenario: .unknown), currentSession: { session })
        await coordinator.load(); await coordinator.prepare(.init(name: "New"))
        let confirmation = try XCTUnwrap(coordinator.confirmation)
        await coordinator.save(confirmation)
        XCTAssertTrue(coordinator.isLocked)
        coordinator.leaveScreen(); await coordinator.load()
        XCTAssertTrue(coordinator.isLocked)
        session = nil; coordinator.synchronizeSession()
        session = try .init(accountID: 901, epoch: 2, token: "new-fixture")
        coordinator.synchronizeSession(); await coordinator.load()
        XCTAssertTrue(coordinator.isLocked)
        await coordinator.prepare(.init(name: "Another"))
        XCTAssertNil(coordinator.confirmation)
    }
    @MainActor func testRejectedWriteUnlocksButDoesNotClaimSaved() async throws {
        let session = try ProfileEditSession(accountID: 901, epoch: 1, token: "fixture")
        let coordinator = ProfileEditCoordinator(service: ProfileEditSyntheticService(scenario: .rejected), currentSession: { session })
        await coordinator.load(); await coordinator.prepare(.init(name: "New"))
        await coordinator.save(try XCTUnwrap(coordinator.confirmation))
        XCTAssertFalse(coordinator.isLocked)
        XCTAssertEqual(coordinator.messageKey, "profile.edit.rejected")
    }
    @MainActor func testOldConfirmationCannotWriteAfterTokenChange() async throws {
        var session: ProfileEditSession? = try .init(accountID: 901, epoch: 1, token: "fixture")
        let coordinator = ProfileEditCoordinator(service: ProfileEditSyntheticService(), currentSession: { session })
        await coordinator.load(); await coordinator.prepare(.init(name: "New"))
        let old = try XCTUnwrap(coordinator.confirmation)
        session = try .init(accountID: 901, epoch: 1, token: "replacement")
        await coordinator.save(old)
        XCTAssertNil(coordinator.snapshot); XCTAssertNil(coordinator.confirmation)
        await coordinator.load()
        XCTAssertEqual(coordinator.snapshot?.nickname, "Trail Friend")
    }
}

/// Source-backed read-error presentation only. All services are in-memory; no live writes.
@MainActor final class ProfileReadFailureRecoveryTests: XCTestCase {
    private func session(_ epoch: UInt64 = 1, token: String = "synthetic-read-failure") throws -> ProfileEditSession {
        try .init(accountID: 901, epoch: epoch, token: token)
    }
    private let explanation = " 资料正在维护，请稍后重试。 "
    private func failure(_ message: String?) -> ProfileReadFailure { .init(code: 503, message: message) }

    func testInitialReadFailureShowsExactServerMessageAndRetryClearsItWithoutWriting() async throws {
        let current = try session(), service = ProfileReadFailureRecoveryService()
        service.readError = failure(explanation)
        let subject = ProfileEditCoordinator(service: service, currentSession: { current })
        let failed = await subject.load()
        XCTAssertFalse(failed); XCTAssertNil(subject.snapshot)
        XCTAssertEqual(subject.messageKey, "profile.edit.loadFailed")
        XCTAssertEqual(subject.remoteMessage, explanation)
        XCTAssertFalse(subject.isBusy); XCTAssertFalse(subject.isLocked)
        service.readError = nil
        let retried = await subject.load()
        XCTAssertTrue(retried); XCTAssertNotNil(subject.snapshot)
        XCTAssertNil(subject.messageKey); XCTAssertNil(subject.remoteMessage)
        XCTAssertEqual(service.saveCount, 0)
    }
    func testFailedRefreshRetainsSnapshotAndShowsExplanation() async throws {
        let current = try session(), service = ProfileReadFailureRecoveryService()
        let subject = ProfileEditCoordinator(service: service, currentSession: { current })
        await subject.load(); let original = subject.snapshot
        service.readError = failure(explanation)
        let loaded = await subject.load()
        XCTAssertFalse(loaded); XCTAssertEqual(subject.snapshot, original)
        XCTAssertEqual(subject.messageKey, "profile.edit.refreshFailed")
        XCTAssertEqual(subject.remoteMessage, explanation)
        XCTAssertNil(subject.confirmation); XCTAssertEqual(service.saveCount, 0)
    }
    func testPrepareFailureKeepsSnapshotAndRequiresANewReview() async throws {
        let current = try session(), service = ProfileReadFailureRecoveryService()
        let subject = ProfileEditCoordinator(service: service, currentSession: { current })
        await subject.load(); let original = subject.snapshot
        let draft = ProfileEditDraft(name: "Local draft", introduction: "Untouched", routePreferenceIDs: [7])
        service.readError = failure(explanation)
        await subject.prepare(draft)
        XCTAssertEqual(subject.snapshot, original); XCTAssertNil(subject.confirmation)
        XCTAssertEqual(subject.messageKey, "profile.edit.loadFailed")
        XCTAssertEqual(subject.remoteMessage, explanation); XCTAssertEqual(service.saveCount, 0)
        service.readError = nil
        await subject.prepare(draft)
        XCTAssertEqual(subject.confirmation?.payload.name, draft.name)
        XCTAssertEqual(subject.confirmation?.payload.tagIds, "7")
        XCTAssertNil(subject.remoteMessage); XCTAssertEqual(service.saveCount, 0)
    }
    func testFinalPreWriteReadFailureDoesNotDispatchOrReuseConfirmation() async throws {
        let current = try session(), service = ProfileReadFailureRecoveryService()
        let subject = ProfileEditCoordinator(service: service, currentSession: { current })
        await subject.load(); let original = subject.snapshot
        await subject.prepare(.init(name: "Reviewed"))
        let review = try XCTUnwrap(subject.confirmation)
        service.readError = failure(explanation)
        await subject.save(review)
        XCTAssertEqual(subject.remoteMessage, explanation)
        XCTAssertEqual(subject.messageKey, "profile.edit.loadFailed")
        XCTAssertEqual(subject.snapshot, original); XCTAssertFalse(subject.isLocked)
        XCTAssertNil(subject.confirmation); XCTAssertEqual(service.saveCount, 0)
        service.readError = nil
        await subject.save(review)
        XCTAssertEqual(service.saveCount, 0)
    }
    func testAcknowledgedWriteReadbackFailureKeepsLockUntilReadOnlyRetry() async throws {
        let current = try session(), service = ProfileReadFailureRecoveryService()
        let subject = ProfileEditCoordinator(service: service, currentSession: { current })
        await subject.load(); await subject.prepare(.init(name: "Confirmed"))
        let review = try XCTUnwrap(subject.confirmation)
        service.afterSaveReadError = failure(explanation)
        await subject.save(review)
        XCTAssertTrue(subject.isLocked); XCTAssertEqual(subject.messageKey, "profile.edit.unknown")
        XCTAssertEqual(subject.remoteMessage, explanation); XCTAssertEqual(service.saveCount, 1)
        service.readError = nil
        await subject.load()
        XCTAssertFalse(subject.isLocked); XCTAssertEqual(subject.messageKey, "profile.edit.saved")
        XCTAssertNil(subject.remoteMessage); XCTAssertEqual(service.saveCount, 1)
    }
    func testUnknownWriteReadbackFailureAndMatchingRetryNeverUnlockOrResend() async throws {
        let current = try session(), service = ProfileReadFailureRecoveryService()
        service.unknownWrite = true
        let subject = ProfileEditCoordinator(service: service, currentSession: { current })
        await subject.load(); await subject.prepare(.init(name: "Possibly stored"))
        let review = try XCTUnwrap(subject.confirmation)
        service.afterSaveReadError = failure(explanation)
        await subject.save(review)
        XCTAssertTrue(subject.isLocked); XCTAssertEqual(subject.remoteMessage, explanation)
        XCTAssertEqual(subject.messageKey, "profile.edit.unknown")
        await subject.load()
        XCTAssertTrue(subject.isLocked); XCTAssertEqual(subject.remoteMessage, explanation)
        service.readError = nil
        await subject.load()
        XCTAssertTrue(subject.isLocked); XCTAssertNil(subject.remoteMessage)
        XCTAssertEqual(subject.messageKey, "profile.edit.readbackUnconfirmed")
        await subject.save(review)
        XCTAssertEqual(service.saveCount, 1)
    }
    func testWhitespaceAndNonServerErrorsNeverBecomeUserText() async throws {
        let current = try session(), service = ProfileReadFailureRecoveryService()
        let subject = ProfileEditCoordinator(service: service, currentSession: { current })
        let errors: [Error] = [failure(" \n\t"), failure(nil), APIError.malformedResponse,
                              NSError(domain: "synthetic-internal-only", code: 1,
                                      userInfo: [NSLocalizedDescriptionKey: "INTERNAL_SENTINEL_DO_NOT_DISPLAY"])]
        for error in errors {
            service.readError = error
            await subject.load()
            XCTAssertNil(subject.remoteMessage)
            XCTAssertEqual(subject.messageKey, "profile.edit.loadFailed")
        }
    }
    func testNewReadClearsPriorExplanationBeforeResponse() async throws {
        let current = try session(), service = ProfileReadFailureRecoveryService()
        let subject = ProfileEditCoordinator(service: service, currentSession: { current })
        service.readError = failure(explanation); await subject.load()
        XCTAssertNotNil(subject.remoteMessage)
        service.readError = nil
        service.beforeRead = { XCTAssertNil(subject.remoteMessage); XCTAssertNil(subject.messageKey) }
        await subject.load()
        XCTAssertNil(subject.remoteMessage)
    }
    func testLateFailureCannotPublishAfterSameAccountTokenReplacement() async throws {
        var current = try session()
        let replacement = try session(token: "synthetic-replacement"), service = ProfileReadFailureRecoveryService()
        let subject = ProfileEditCoordinator(service: service, currentSession: { current })
        service.beforeRead = { current = replacement; subject.synchronizeSession() }
        service.readError = failure(explanation)
        await subject.load()
        XCTAssertNil(subject.remoteMessage); XCTAssertNil(subject.messageKey)
        XCTAssertNil(subject.snapshot); XCTAssertFalse(subject.isBusy)
    }
    func testCancelledReadDoesNotPublishLateServerExplanation() async throws {
        let current = try session(), service = ProfileReadFailureRecoveryService()
        let subject = ProfileEditCoordinator(service: service, currentSession: { current })
        service.beforeRead = { withUnsafeCurrentTask { $0?.cancel() } }
        service.readError = failure(explanation)
        let task = Task { await subject.load() }
        let loaded = await task.value
        XCTAssertFalse(loaded); XCTAssertNil(subject.remoteMessage); XCTAssertNil(subject.messageKey)
        XCTAssertFalse(subject.isBusy); XCTAssertEqual(service.saveCount, 0)
    }
    func testSessionResetClearsPreviouslyDisplayedExplanation() async throws {
        var current: ProfileEditSession? = try session()
        let service = ProfileReadFailureRecoveryService()
        let subject = ProfileEditCoordinator(service: service, currentSession: { current })
        service.readError = failure(explanation); await subject.load()
        XCTAssertNotNil(subject.remoteMessage)
        current = nil; subject.synchronizeSession()
        XCTAssertNil(subject.remoteMessage); XCTAssertNil(subject.messageKey)
        XCTAssertNil(subject.snapshot); XCTAssertNil(subject.confirmation)
    }
    func testUnauthorizedCallbackInvalidatesFailureBeforePresentation() async throws {
        var current: ProfileEditSession? = try session()
        let service = ProfileReadFailureRecoveryService()
        service.readError = ProfileReadFailure(httpStatus: 401, message: explanation)
        var unauthorizedCount = 0
        let subject = ProfileEditCoordinator(service: service, currentSession: { current },
            onUnauthorized: { _ in unauthorizedCount += 1; current = nil })
        await subject.load()
        XCTAssertEqual(unauthorizedCount, 1); XCTAssertNil(subject.remoteMessage)
        XCTAssertNil(subject.messageKey); XCTAssertEqual(service.saveCount, 0)
    }
}

@MainActor private final class ProfileReadFailureRecoveryService: ProfileEditServing {
    var readError: Error?
    var afterSaveReadError: Error?
    var beforeRead: (() -> Void)?
    var unknownWrite = false
    private(set) var saveCount = 0
    private var name = "Trail Friend"
    private var introduction = "Weekend walks"
    private var tagIds = "7,4"
    func read(token: String) async throws -> ProfileEditSnapshot {
        beforeRead?()
        if let readError { throw readError }
        let object: [String: Any] = ["id": 901, "nickname": name, "introduction": introduction,
            "avatar": " raw-avatar ", "wechat": " contact-qr ", "casePics": "one;;two;", "tagIds": tagIds]
        return try JSONDecoder().decode(ProfileEditSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
    }
    func save(_ payload: ProfileEditPayload, token: String) async throws {
        saveCount += 1
        name = payload.name; introduction = payload.introduction; tagIds = payload.tagIds
        readError = afterSaveReadError
        if unknownWrite { throw ProfileEditWriteError.outcomeUnknown }
    }
}

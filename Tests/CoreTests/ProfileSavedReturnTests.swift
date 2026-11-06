import XCTest
@testable import QuestifyCore

@MainActor final class ProfileSavedReturnTests: XCTestCase {
    private func session(_ revision: UInt64 = 1, account: Int = 901) throws -> ProfileEditSession {
        try .init(accountID: account, epoch: 1, token: "synthetic-return", viewerRevision: revision)
    }
    private func reviewed(_ coordinator: ProfileEditCoordinator) async throws -> ProfileEditConfirmation {
        await coordinator.load()
        await coordinator.prepare(.init(name: "Confirmed name", introduction: "Confirmed introduction"))
        return try XCTUnwrap(coordinator.confirmation)
    }
    func testAcknowledgedMatchingReadbackIssuesOneConsumableReceipt() async throws {
        let current = try session(), service = SavedReturnService()
        let subject = ProfileEditCoordinator(service: service, currentSession: { current })
        let review = try await reviewed(subject)
        let result = await subject.save(review)
        let receipt = try XCTUnwrap(result)
        XCTAssertEqual(receipt.reviewID, review.id)
        XCTAssertEqual(subject.snapshot?.nickname, "Confirmed name")
        XCTAssertEqual(service.writes, 1)
        XCTAssertTrue(subject.consumeSavedReturn(receipt))
        XCTAssertFalse(subject.consumeSavedReturn(receipt))
        let repeated = await subject.save(review)
        XCTAssertNil(repeated); XCTAssertEqual(service.writes, 1)
    }
    func testUnknownMatchingReadbackStaysLockedWithoutReceiptOrResend() async throws {
        let current = try session(), service = SavedReturnService(); service.unknown = true
        let subject = ProfileEditCoordinator(service: service, currentSession: { current })
        let review = try await reviewed(subject), receipt = await subject.save(review)
        XCTAssertNil(receipt); XCTAssertTrue(subject.isLocked)
        XCTAssertEqual(subject.messageKey, "profile.edit.readbackUnconfirmed")
        await subject.load()
        XCTAssertTrue(subject.isLocked)
        let repeated = await subject.save(review)
        XCTAssertNil(repeated); XCTAssertEqual(service.writes, 1)
    }
    func testRejectionCannotIssueReceipt() async throws {
        let current = try session(), service = SavedReturnService(); service.reject = true
        let subject = ProfileEditCoordinator(service: service, currentSession: { current })
        let review = try await reviewed(subject), receipt = await subject.save(review)
        XCTAssertNil(receipt); XCTAssertFalse(subject.isLocked)
        XCTAssertEqual(subject.messageKey, "profile.edit.rejected"); XCTAssertEqual(service.writes, 1)
    }
    func testReadbackFailureThenSuccessfulRefreshDoesNotCreateNavigationReceipt() async throws {
        let current = try session(), service = SavedReturnService(); service.failReadback = true
        let subject = ProfileEditCoordinator(service: service, currentSession: { current })
        let review = try await reviewed(subject), receipt = await subject.save(review)
        XCTAssertNil(receipt); XCTAssertTrue(subject.isLocked)
        service.failReadback = false; await subject.load()
        XCTAssertFalse(subject.isLocked); XCTAssertEqual(subject.messageKey, "profile.edit.saved")
        let repeated = await subject.save(review)
        XCTAssertNil(repeated); XCTAssertEqual(service.writes, 1)
    }
    func testRefreshRetiresPreviouslyIssuedReceipt() async throws {
        let current = try session(), subject = ProfileEditCoordinator(service: SavedReturnService(), currentSession: { current })
        let review = try await reviewed(subject), result = await subject.save(review)
        let receipt = try XCTUnwrap(result); await subject.load()
        XCTAssertFalse(subject.consumeSavedReturn(receipt))
    }
    func testNewReviewAndCancellationCannotReusePreviouslySuccessfulReceipt() async throws {
        let current = try session(), subject = ProfileEditCoordinator(service: SavedReturnService(), currentSession: { current })
        let review = try await reviewed(subject), result = await subject.save(review)
        let receipt = try XCTUnwrap(result)
        await subject.prepare(.init(name: "Next edit", introduction: "Another introduction"))
        let next = try XCTUnwrap(subject.confirmation); subject.cancel(next)
        XCTAssertFalse(subject.consumeSavedReturn(receipt))
        let cancelled = await subject.save(next); XCTAssertNil(cancelled)
    }
    func testChangedOwnerBeforeConsumptionRejectsReceipt() async throws {
        var current = try session()
        let subject = ProfileEditCoordinator(service: SavedReturnService(), currentSession: { current })
        let review = try await reviewed(subject), result = await subject.save(review)
        let receipt = try XCTUnwrap(result)
        current = try session(2, account: 902)
        XCTAssertFalse(subject.consumeSavedReturn(receipt))
    }
    func testSameAccountRevisionABADoesNotReviveReceipt() async throws {
        var current = try session()
        let subject = ProfileEditCoordinator(service: SavedReturnService(), currentSession: { current })
        let review = try await reviewed(subject), result = await subject.save(review)
        let receipt = try XCTUnwrap(result)
        current = try session(2); subject.synchronizeSession()
        current = try session(3)
        XCTAssertFalse(subject.consumeSavedReturn(receipt))
    }
    func testLateSaveAfterOwnerChangeDoesNotIssueReceipt() async throws {
        var current = try session(); let replacement = try session(2), service = SavedReturnService()
        let subject = ProfileEditCoordinator(service: service, currentSession: { current })
        let review = try await reviewed(subject)
        service.afterWrite = { current = replacement }
        let receipt = await subject.save(review)
        XCTAssertNil(receipt); XCTAssertTrue(subject.isLocked); XCTAssertEqual(service.writes, 1)
    }
    func testCancelledReadbackDoesNotIssueReceipt() async throws {
        let current = try session(), service = SavedReturnService()
        let subject = ProfileEditCoordinator(service: service, currentSession: { current })
        let review = try await reviewed(subject)
        service.afterWrite = { withUnsafeCurrentTask { $0?.cancel() } }
        let task = Task { await subject.save(review) }; let receipt = await task.value
        XCTAssertNil(receipt); XCTAssertTrue(subject.isLocked)
    }
    func testLeavingScreenRetiresReceiptAndOtherCoordinatorCannotConsumeIt() async throws {
        let current = try session(), subject = ProfileEditCoordinator(service: SavedReturnService(), currentSession: { current })
        let other = ProfileEditCoordinator(service: SavedReturnService(), currentSession: { current })
        let review = try await reviewed(subject), result = await subject.save(review)
        let receipt = try XCTUnwrap(result)
        XCTAssertFalse(other.consumeSavedReturn(receipt))
        subject.leaveScreen(); XCTAssertFalse(subject.consumeSavedReturn(receipt))
    }
}

@MainActor private final class SavedReturnService: ProfileEditServing {
    var unknown = false, reject = false, failReadback = false
    var afterWrite: (() -> Void)?
    private(set) var writes = 0
    private var name = "Original", introduction = "Original introduction"
    func read(token: String) async throws -> ProfileEditSnapshot {
        if writes > 0 && failReadback { throw APIError.httpStatus(503) }
        return try JSONDecoder().decode(ProfileEditSnapshot.self, from: JSONSerialization.data(withJSONObject:
            ["id": 901, "nickname": name, "introduction": introduction, "avatar": "", "wechat": "", "casePics": "", "tagIds": ""]))
    }
    func save(_ payload: ProfileEditPayload, token: String) async throws {
        writes += 1
        if reject { throw ProfileEditWriteError.rejected(.init(code: 422)) }
        name = payload.name; introduction = payload.introduction
        afterWrite?()
        if unknown { throw ProfileEditWriteError.outcomeUnknown }
    }
}

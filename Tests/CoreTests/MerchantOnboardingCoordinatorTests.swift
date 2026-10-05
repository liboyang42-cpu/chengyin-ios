import XCTest
@testable import QuestifyCore

@MainActor
final class MerchantOnboardingCoordinatorTests: XCTestCase {
    private func ready(_ server: MerchantOnboardingFakeServer) async -> MerchantOnboardingCoordinator {
        let coordinator = MerchantOnboardingCoordinator(server: server)
        await coordinator.load(); await coordinator.checkIdentity()
        return coordinator
    }
    func testInitialReadFailureNeverOpensApplicationForm() async throws {
        let server = MerchantOnboardingFakeServer(); server.readError = APIError.malformedResponse
        let coordinator = await ready(server)
        XCTAssertEqual(coordinator.loadState, .unavailable)
        XCTAssertThrowsError(try coordinator.prepare(makeMerchantOnboardingDraft()))
        XCTAssertTrue(server.submissions.isEmpty)
    }
    func testIdentityRequirementGatesUploadsAndSubmissionWithoutCollectingIdentity() async throws {
        let server = MerchantOnboardingFakeServer(); server.registered = false
        let coordinator = await ready(server)
        XCTAssertEqual(coordinator.identityGate, .required)
        XCTAssertThrowsError(try coordinator.prepare(makeMerchantOnboardingDraft())) { XCTAssertEqual($0 as? MerchantOnboardingBlock, .identityRequired) }
        do {
            _ = try await coordinator.uploadLicense(.init(jpegData: Data([0xff, 0xd8, 0xff])), expectedIdentity: server.identity!)
            XCTFail()
        } catch { XCTAssertEqual(error as? MerchantOnboardingBlock, .identityRequired) }
        XCTAssertEqual(server.uploads, 0); XCTAssertTrue(server.submissions.isEmpty)
    }
    func testIdentityFailureRemainsUnknownAndCanBeRechecked() async throws {
        let server = MerchantOnboardingFakeServer(); server.identityError = APIError.malformedResponse
        let coordinator = await ready(server)
        XCTAssertEqual(coordinator.identityGate, .unavailable)
        server.identityError = nil
        await coordinator.checkIdentity()
        XCTAssertEqual(coordinator.identityGate, .registered)
    }
    func testApplicationStatePreventsNewOrWrongIDRequests() async throws {
        for application in [try makeMerchantOnboardingApplication(status: 0), try makeMerchantOnboardingApplication(status: 1),
                            try makeMerchantOnboardingApplication(status: 2, accountStatus: 2)] {
            let server = MerchantOnboardingFakeServer(); server.snapshot = .application(application)
            let coordinator = await ready(server)
            XCTAssertThrowsError(try coordinator.prepare(makeMerchantOnboardingDraft()))
        }
        let server = MerchantOnboardingFakeServer(); server.snapshot = .application(try makeMerchantOnboardingApplication(status: 2))
        let coordinator = await ready(server)
        XCTAssertThrowsError(try coordinator.prepare(makeMerchantOnboardingDraft()))
        let draft = try MerchantOnboardingDraft(reapplying: makeMerchantOnboardingApplication(status: 2))
        let confirmation = try coordinator.prepare(draft)
        XCTAssertEqual(confirmation.draft.id, 17)
    }
    func testPrepareFreezesDraftAndCancelSendsNothing() async throws {
        let server = MerchantOnboardingFakeServer(); let coordinator = await ready(server)
        var draft = try makeMerchantOnboardingDraft()
        let confirmation = try coordinator.prepare(draft)
        draft.name = "Later edit"
        XCTAssertEqual(confirmation.draft.name, " Example Store ")
        coordinator.cancel(confirmation)
        await coordinator.confirm(confirmation)
        XCTAssertEqual(coordinator.submission, .idle); XCTAssertTrue(server.submissions.isEmpty)
    }
    func testConfirmedSubmitReadsEligibilityThenStatusAndNeverApprovesLocally() async throws {
        let server = MerchantOnboardingFakeServer(); let coordinator = await ready(server)
        let confirmation = try coordinator.prepare(makeMerchantOnboardingDraft())
        XCTAssertTrue(server.submissions.isEmpty)
        server.afterSubmit = .application(try makeMerchantOnboardingApplication(status: 0))
        await coordinator.confirm(confirmation)
        XCTAssertEqual(server.submissions, [confirmation.draft])
        XCTAssertEqual(server.applicationReads, 3) // Entry, preflight, one readback.
        XCTAssertEqual(server.identityReads, 2) // Gate and final preflight.
        XCTAssertEqual(coordinator.submission, .acknowledged)
        guard case .loaded(.application(let application)) = coordinator.loadState else { return XCTFail() }
        XCTAssertEqual(application.status, 0); XCTAssertEqual(application.accountStatus, 0)
        XCTAssertThrowsError(try coordinator.prepare(makeMerchantOnboardingDraft()))
    }
    func testLaterRejectionAfterConfirmedPendingReadbackCanBeReapplied() async throws {
        let server = MerchantOnboardingFakeServer(); let coordinator = await ready(server)
        let confirmation = try coordinator.prepare(makeMerchantOnboardingDraft())
        server.afterSubmit = .application(try makeMerchantOnboardingApplication(status: 0))
        await coordinator.confirm(confirmation)
        XCTAssertEqual(coordinator.submission, .acknowledged)
        let rejection = try makeMerchantOnboardingApplication(status: 2)
        server.snapshot = .application(rejection)
        await coordinator.load()
        XCTAssertEqual(coordinator.submission, .idle)
        XCTAssertNoThrow(try coordinator.prepare(MerchantOnboardingDraft(reapplying: rejection)))
        XCTAssertEqual(server.submissions.count, 1)
    }
    func testChangedApplicationOrIdentityStopsBeforeSubmit() async throws {
        let server = MerchantOnboardingFakeServer(); let coordinator = await ready(server)
        let confirmation = try coordinator.prepare(makeMerchantOnboardingDraft())
        server.snapshot = .application(try makeMerchantOnboardingApplication(status: 0))
        await coordinator.confirm(confirmation)
        XCTAssertEqual(coordinator.submission, .notSent); XCTAssertTrue(server.submissions.isEmpty)
        let other = MerchantOnboardingFakeServer(); let second = await ready(other)
        let otherConfirmation = try second.prepare(makeMerchantOnboardingDraft()); other.registered = false
        await second.confirm(otherConfirmation)
        XCTAssertEqual(second.identityGate, .required); XCTAssertTrue(other.submissions.isEmpty)
    }
    func testReadbackFailureDoesNotUndoAcknowledgementOrUnlockResend() async throws {
        let server = MerchantOnboardingFakeServer(); let coordinator = await ready(server)
        let confirmation = try coordinator.prepare(makeMerchantOnboardingDraft())
        server.onSubmit = { server.readError = APIError.malformedResponse }
        await coordinator.confirm(confirmation)
        XCTAssertEqual(coordinator.submission, .acknowledged)
        XCTAssertEqual(coordinator.loadState, .unavailable)
        server.readError = nil
        await coordinator.load()
        XCTAssertEqual(coordinator.loadState, .loaded(.none))
        XCTAssertThrowsError(try coordinator.prepare(makeMerchantOnboardingDraft()))
        XCTAssertEqual(server.submissions.count, 1)
    }
    func testTimeoutRequiresExplicitReadbackAndNoneDoesNotAllowRetry() async throws {
        let server = MerchantOnboardingFakeServer(); server.submitError = MerchantOnboardingWriteError.outcomeUnknown
        let coordinator = await ready(server); let confirmation = try coordinator.prepare(makeMerchantOnboardingDraft())
        await coordinator.confirm(confirmation)
        XCTAssertEqual(coordinator.submission, .outcomeUnknown)
        XCTAssertEqual(server.applicationReads, 2) // No implicit retry or read after uncertain failure.
        await coordinator.load()
        XCTAssertEqual(coordinator.loadState, .loaded(.none))
        XCTAssertThrowsError(try coordinator.prepare(makeMerchantOnboardingDraft()))
        coordinator.leaveScreen(); await coordinator.load(); await coordinator.checkIdentity()
        XCTAssertEqual(coordinator.submission, .outcomeUnknown)
        XCTAssertThrowsError(try coordinator.prepare(makeMerchantOnboardingDraft()))
        XCTAssertEqual(server.submissions.count, 1)
    }
    func testBusinessRejectionIsDisplayedWithoutInventedRoleRule() async throws {
        let server = MerchantOnboardingFakeServer()
        let failure = MerchantOnboardingFailure(code: 409, message: "Server eligibility conflict")
        server.submitError = MerchantOnboardingWriteError.rejected(failure)
        let coordinator = await ready(server); let confirmation = try coordinator.prepare(makeMerchantOnboardingDraft())
        await coordinator.confirm(confirmation)
        XCTAssertEqual(coordinator.submission, .rejected(failure))
        // An explicit rejection permits another user-confirmed attempt after a fresh preflight.
        XCTAssertNoThrow(try coordinator.prepare(makeMerchantOnboardingDraft()))
        XCTAssertEqual(server.submissions.count, 1)
    }
    func testRepeatedConfirmationOnlyDispatchesOnceAndDismissalKeepsUnknownLock() async throws {
        let server = MerchantOnboardingFakeServer(); server.suspendSubmit = true
        let dispatched = expectation(description: "dispatched")
        server.onSubmit = { dispatched.fulfill() }
        let coordinator = await ready(server); let confirmation = try coordinator.prepare(makeMerchantOnboardingDraft())
        let first = Task { await coordinator.confirm(confirmation) }
        await fulfillment(of: [dispatched], timeout: 1)
        await coordinator.confirm(confirmation)
        XCTAssertEqual(server.submissions.count, 1)
        coordinator.leaveScreen()
        XCTAssertEqual(coordinator.submission, .outcomeUnknown)
        server.resumeSubmit()
        await first.value
        XCTAssertTrue(coordinator.submission.isLocked)
        XCTAssertEqual(coordinator.loadState, .idle)
    }
    func testAccountReplacementClearsSnapshotsAndCannotSendOldConfirmation() async throws {
        let server = MerchantOnboardingFakeServer(); let coordinator = await ready(server)
        let confirmation = try coordinator.prepare(makeMerchantOnboardingDraft())
        server.identity = .init(accountID: 2, epoch: 2); coordinator.synchronizeSession()
        XCTAssertEqual(coordinator.loadState, .idle); XCTAssertEqual(coordinator.identityGate, .unchecked)
        await coordinator.confirm(confirmation)
        XCTAssertTrue(server.submissions.isEmpty)
    }
    func testSameAccountNewEpochKeepsOnlyUncertainOperationLock() async throws {
        let server = MerchantOnboardingFakeServer(); server.submitError = MerchantOnboardingWriteError.outcomeUnknown
        let coordinator = await ready(server); let confirmation = try coordinator.prepare(makeMerchantOnboardingDraft())
        await coordinator.confirm(confirmation)
        server.identity = nil; coordinator.synchronizeSession()
        XCTAssertEqual(coordinator.submission, .idle); XCTAssertEqual(coordinator.loadState, .idle)
        server.identity = .init(accountID: 1, epoch: 3); coordinator.synchronizeSession()
        XCTAssertEqual(coordinator.submission, .outcomeUnknown); XCTAssertEqual(coordinator.loadState, .idle)
        await coordinator.load(); await coordinator.checkIdentity()
        XCTAssertThrowsError(try coordinator.prepare(makeMerchantOnboardingDraft()))
    }
    func testCancellationBeforeConfirmationDispatchSendsNothing() async throws {
        let server = MerchantOnboardingFakeServer(); let coordinator = await ready(server)
        let confirmation = try coordinator.prepare(makeMerchantOnboardingDraft())
        let task = Task { await coordinator.confirm(confirmation) }
        task.cancel(); await task.value
        XCTAssertTrue(server.submissions.isEmpty); XCTAssertEqual(coordinator.submission, .notSent)
    }
}

@MainActor
final class MerchantOnboardingFakeServer: MerchantOnboardingServing {
    var isConfigured = true
    var identity: ProfileReadIdentity? = .init(accountID: 1, epoch: 1)
    var snapshot: MerchantOnboardingSnapshot = .none
    var registered = true
    var readError: Error?
    var identityError: Error?
    var submitError: Error?
    var afterSubmit: MerchantOnboardingSnapshot?
    var applicationReads = 0, identityReads = 0, uploads = 0
    var submissions: [MerchantOnboardingDraft] = []
    var onSubmit: (() -> Void)?
    var suspendSubmit = false
    var submitContinuation: CheckedContinuation<Void, Error>?
    func application(expectedIdentity: ProfileReadIdentity) async throws -> MerchantOnboardingSnapshot {
        guard identity == expectedIdentity else { throw APIError.unauthorized }
        applicationReads += 1
        if let readError { throw readError }
        return snapshot
    }
    func identityRegistered(expectedIdentity: ProfileReadIdentity) async throws -> Bool {
        guard identity == expectedIdentity else { throw APIError.unauthorized }
        identityReads += 1
        if let identityError { throw identityError }
        return registered
    }
    func uploadLicense(_ image: MerchantOnboardingImage, expectedIdentity: ProfileReadIdentity) async throws -> MerchantOnboardingLicense {
        guard identity == expectedIdentity else { throw APIError.unauthorized }
        uploads += 1; return try .init(serverURL: "https://fixtures.example/upload.jpg")
    }
    func submit(_ draft: MerchantOnboardingDraft, expectedIdentity: ProfileReadIdentity) async throws {
        guard identity == expectedIdentity else { throw MerchantOnboardingWriteError.notSent }
        submissions.append(draft); onSubmit?()
        if suspendSubmit { try await withCheckedThrowingContinuation { submitContinuation = $0 } }
        if let submitError { throw submitError }
        if let afterSubmit { snapshot = afterSubmit }
    }
    func resumeSubmit() { submitContinuation?.resume(); submitContinuation = nil }
}

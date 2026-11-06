import Foundation
import XCTest
@testable import Questify

@MainActor final class ParticipantRecoveryFeedbackTests: XCTestCase {
    private func model(_ io: FeedbackIO, _ journal: FeedbackJournal) -> ParticipantFormModel {
        ParticipantFormModel(id: nil, reader: io, coordinator: ParticipantMutationCoordinator(
            writer: io, reader: io, pendingJournal: journal, pendingOwner: { "fixture-owner" }))
    }
    private func fill(_ model: ParticipantFormModel) {
        model.draft.fullName = "Name"; model.draft.mobilePhone = "13900000000"
    }
    func testStorageBlockedReadbackShowsSafetyFailureAndSendsNothing() async {
        let io = FeedbackIO(), journal = FeedbackJournal(); journal.failRead = true
        let model = self.model(io, journal); await model.load()
        XCTAssertTrue(model.showsOwnedUnknown)
        await model.readBack()
        XCTAssertEqual(model.issue?.key, "participant.recovery.safetyUnavailable")
        XCTAssertEqual(model.issue?.tableName, "ProfileParticipantRecovery")
        XCTAssertEqual(io.reads, 0); XCTAssertEqual(io.writes, 0)
        XCTAssertTrue(model.showsOwnedUnknown); XCTAssertFalse(model.canMutate)
    }
    func testExplicitRecheckAfterStorageRecoveryClearsFeedbackButNeverUnlocks() async {
        let io = FeedbackIO(), journal = FeedbackJournal()
        journal.marker = .init(operationID: UUID(), ownerKey: "fixture-owner", targetKey: "profile.participants")
        journal.failRead = true
        let model = self.model(io, journal); await model.load(); await model.readBack()
        XCTAssertNotNil(model.issue)
        journal.failRead = false
        await model.readBack()
        XCTAssertNil(model.issue); XCTAssertEqual(io.reads, 1); XCTAssertEqual(io.writes, 0)
        XCTAssertEqual(model.readback, .received(.list([])))
        XCTAssertTrue(model.showsOwnedUnknown); XCTAssertFalse(model.canMutate)
        XCTAssertNotNil(journal.marker)
    }
    func testPreDispatchJournalFailureIsNotMisreportedAsAccountChange() async {
        let io = FeedbackIO(), journal = FeedbackJournal(), model = self.model(io, journal)
        await model.load(); fill(model); model.prepareSave(); journal.failWrite = true
        let saved = await model.confirmMutation()
        XCTAssertFalse(saved); XCTAssertEqual(io.writes, 0)
        XCTAssertEqual(model.issue?.key, "participant.recovery.safetyUnavailable")
        XCTAssertNotEqual(model.issue?.key, "participant.form.sessionChanged")
        XCTAssertEqual(model.operation, .notSent)
    }
    func testOriginalRetryStorageFailureKeepsOriginalUUIDAndExplainsBlock() async throws {
        let io = FeedbackIO(), journal = FeedbackJournal(), model = self.model(io, journal)
        await model.load(); fill(model); model.prepareSave(); _ = await model.confirmMutation()
        let original = try XCTUnwrap(model.originalCreateRetry)
        XCTAssertEqual(io.writes, 1)
        journal.failWrite = true
        let saved = await model.retryOriginalCreate()
        XCTAssertFalse(saved); XCTAssertEqual(io.writes, 1)
        XCTAssertEqual(model.issue?.key, "participant.recovery.safetyUnavailable")
        XCTAssertEqual(model.originalCreateRetry, original)
        XCTAssertTrue(model.showsOwnedUnknown)
        XCTAssertEqual(journal.marker?.operationID, original.requestID)
    }
    func testKnownBlockKindsKeepSpecificMeaningAndLocalizeInOwnedCatalog() {
        let cases: [(ParticipantCoordinatorBlock, String)] = [
            (.unavailable,"safetyUnavailable"), (.invalidForm,"invalidForm"),
            (.pendingOperation,"pendingOperation"), (.confirmationNoLongerValid,"confirmationExpired"),
            (.cancelledBeforeDispatch,"cancelledBeforeDispatch"), (.noUncertainOutcome,"noUncertainOutcome"),
            (.readbackInProgress,"readInProgress")]
        for (reason, key) in cases {
            let issue = ParticipantScreenIssue(reason)
            XCTAssertEqual(issue.key, "participant.recovery." + key)
            XCTAssertEqual(issue.tableName, "ProfileParticipantRecovery"); XCTAssertNil(issue.message)
        }
        XCTAssertEqual(ParticipantScreenIssue(ParticipantCoordinatorBlock.accountChanged).key, "participant.form.sessionChanged")
        XCTAssertEqual(ParticipantScreenIssue(ParticipantCoordinatorBlock.signedOut).key, "auth.expired")
    }
    func testDuplicateReadAndStaleCompletionDoNotProduceMisleadingErrors() {
        XCTAssertNil(ParticipantScreenIssue.feedback(for: .blocked(.readbackInProgress)))
        XCTAssertNil(ParticipantScreenIssue.feedback(for: .ignoredStale))
        XCTAssertNil(ParticipantScreenIssue.feedback(for: .applied))
        XCTAssertEqual(ParticipantScreenIssue.feedback(for: .blocked(.unavailable))?.key, "participant.recovery.safetyUnavailable")
    }
    func testDepartureClearsFeedbackAndPreventsQueuedRecheck() async {
        let io = FeedbackIO(), journal = FeedbackJournal(); journal.failRead = true
        let model = self.model(io, journal); await model.load(); await model.readBack()
        XCTAssertNotNil(model.issue)
        model.disappear(); await model.readBack()
        XCTAssertNil(model.issue); XCTAssertEqual(io.reads, 0); XCTAssertEqual(io.writes, 0)
    }
}
@MainActor private final class FeedbackJournal: OperationPendingJournal {
    var marker: OperationPendingRecord?
    var failRead = false, failWrite = false
    func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? {
        if failRead { throw APIError.notConfigured }; return marker
    }
    func write(_ record: OperationPendingRecord) throws {
        if failWrite { throw APIError.notConfigured }
        if let marker, marker.operationID != record.operationID { throw APIError.invalidRequest }
        marker = record
    }
    func clear(_ record: OperationPendingRecord) throws { XCTFail("Inspection must never clear UNKNOWN") }
}
@MainActor private final class FeedbackIO: ProfileReading, ParticipantWriting {
    var identity: ProfileReadIdentity? = .init(accountID: 1, epoch: 1)
    var isConfigured = true
    var reads = 0, writes = 0
    func perform(_ mutation: ParticipantMutation, expectedIdentity: ProfileReadIdentity) async throws {
        writes += 1; throw ParticipantWriteError.outcomeUnknown(.transport)
    }
    func profileParticipants() async throws -> [ProfileParticipant] { reads += 1; return [] }
    func profileParticipant(id: Int) async throws -> ProfileParticipant { throw APIError.notConfigured }
    func profileOrders() async throws -> [ProfileOrder] { throw APIError.notConfigured }
    func profileOrder(id: Int) async throws -> ProfileOrder { throw APIError.notConfigured }
    func profileBadges() async throws -> ProfileBadgeWall { throw APIError.notConfigured }
}

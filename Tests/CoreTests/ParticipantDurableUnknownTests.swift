import Foundation
import XCTest
@testable import QuestifyCore

@MainActor final class ParticipantDurableUnknownTests: XCTestCase {
    private func draft() -> ParticipantFormDraft {
        var d = ParticipantFormDraft(); d.fullName = "Name"; d.mobilePhone = "13900000000"; return d
    }
    private func flow(_ io: DurableParticipantIO, _ journal: any OperationPendingJournal,
                      owner: @escaping () -> String? = { "scope-a" }) -> ParticipantMutationCoordinator {
        ParticipantMutationCoordinator(writer: io, reader: io, pendingJournal: journal, pendingOwner: owner)
    }
    private func submit(_ c: ParticipantMutationCoordinator, _ io: DurableParticipantIO) async throws -> ParticipantConfirmation {
        let review = try c.prepare(.save(draft()), expectedIdentity: io.identity!)
        _ = await c.confirm(review); return review
    }
    func testDefaultsReconstructionRestoresOriginalIDWithoutPIIOrReplay() async throws {
        let suite = "participant-durable-test-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let io = DurableParticipantIO(), journal = OperationDefaultsJournal(defaults: defaults)
        let first = flow(io, journal)
        let review = try await submit(first, io)
        let stored = try XCTUnwrap(journal.pending(ownerKey: "scope-a", targetKey: "profile.participants"))
        XCTAssertEqual(stored.operationID, review.id)
        let bytes = try JSONEncoder().encode(stored), text = String(decoding: bytes, as: UTF8.self)
        XCTAssertFalse(text.contains("13900000000")); XCTAssertFalse(text.contains("fullName"))
        XCTAssertFalse(text.contains("token")); XCTAssertFalse(text.contains("mutation"))
        io.identity = .init(accountID: 7, epoch: 42, approvalRevision: UUID())
        let reopenedDefaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let restarted = flow(io, OperationDefaultsJournal(defaults: reopenedDefaults))
        XCTAssertEqual(restarted.state, .outcomeUnknown(.transport))
        XCTAssertFalse(restarted.canPrepare); XCTAssertNil(restarted.savedParticipant)
        XCTAssertEqual(restarted.readbackState, .idle); XCTAssertEqual(io.ids, [review.id])
        _ = await restarted.readBackUncertainOutcome()
        XCTAssertEqual(restarted.readbackState, .received(.list([])))
        XCTAssertFalse(restarted.canPrepare); XCTAssertEqual(io.ids, [review.id])
        XCTAssertEqual(try journal.pending(ownerKey: "scope-a", targetKey: "profile.participants")?.operationID, review.id)
    }
    func testOtherDeploymentSameAccountCannotSeeOrClearOriginalLock() async throws {
        let io = DurableParticipantIO(), journal = DurableParticipantJournal()
        var owner = "scope-a"
        let c = flow(io, journal, owner: { owner })
        let review = try await submit(c, io)
        owner = "scope-b"
        XCTAssertEqual(c.state, .idle); XCTAssertTrue(c.canPrepare)
        XCTAssertNil(c.savedParticipant); XCTAssertEqual(c.readbackState, .idle)
        owner = "scope-a"
        XCTAssertFalse(c.canPrepare)
        XCTAssertEqual(try journal.pending(ownerKey: owner, targetKey: "profile.participants")?.operationID, review.id)
        XCTAssertEqual(io.ids, [review.id])
    }
    func testJournalFailureBeforeWriteDispatchesNothing() async throws {
        let io = DurableParticipantIO(), journal = DurableParticipantJournal()
        journal.failWrite = true
        let c = flow(io, journal), review = try c.prepare(.save(draft()), expectedIdentity: io.identity!)
        let result = await c.confirm(review)
        XCTAssertEqual(result, .blocked(.unavailable)); XCTAssertTrue(io.ids.isEmpty)
    }
    func testUncertainJournalWriteRestoresMarkerAndStillDispatchesNothing() async throws {
        let io = DurableParticipantIO(), journal = DurableParticipantJournal()
        journal.failAfterWrite = true
        let c = flow(io, journal), review = try c.prepare(.save(draft()), expectedIdentity: io.identity!)
        _ = await c.confirm(review)
        XCTAssertEqual(c.state, .outcomeUnknown(.transport)); XCTAssertFalse(c.canPrepare)
        XCTAssertTrue(io.ids.isEmpty)
        XCTAssertEqual(try journal.pending(ownerKey: "scope-a", targetKey: "profile.participants")?.operationID, review.id)
    }
    func testUnreadableJournalFailsClosedWithoutInventingRequestID() throws {
        let io = DurableParticipantIO(), journal = DurableParticipantJournal()
        journal.failRead = true
        let c = flow(io, journal)
        XCTAssertEqual(c.state, .outcomeUnknown(.transport)); XCTAssertFalse(c.canPrepare)
        XCTAssertThrowsError(try c.prepare(.save(draft()), expectedIdentity: io.identity!))
        XCTAssertTrue(io.ids.isEmpty); XCTAssertTrue(journal.records.isEmpty)
    }
    func testAcknowledgedSuccessClearsOnlyOriginalMarker() async throws {
        let io = DurableParticipantIO(), journal = DurableParticipantJournal(); io.mode = .success
        let c = flow(io, journal), review = try await submit(c, io)
        XCTAssertEqual(c.state, .succeeded); XCTAssertNotNil(c.savedParticipant)
        XCTAssertNil(try journal.pending(ownerKey: "scope-a", targetKey: "profile.participants"))
        XCTAssertEqual(io.ids, [review.id]); XCTAssertEqual(flow(io, journal).state, .idle)
    }
    func testSuccessWithFailedMarkerClearRemainsUnknownWithoutPublishedRow() async throws {
        let io = DurableParticipantIO(), journal = DurableParticipantJournal(); io.mode = .success; journal.failClear = true
        let c = flow(io, journal); _ = try await submit(c, io)
        XCTAssertEqual(c.state, .outcomeUnknown(.transport)); XCTAssertNil(c.savedParticipant)
        XCTAssertFalse(flow(io, journal).canPrepare); XCTAssertEqual(io.ids.count, 1)
    }
    func testKnownNotSentClearsMarkerButMissingCreateACKDoesNot() async throws {
        for mode in [DurableParticipantIO.Mode.notSent, .nilRow] {
            let io = DurableParticipantIO(), journal = DurableParticipantJournal(); io.mode = mode
            let c = flow(io, journal); _ = try await submit(c, io)
            if mode == .notSent {
                XCTAssertEqual(c.state, .notSent)
                XCTAssertNil(try journal.pending(ownerKey: "scope-a", targetKey: "profile.participants"))
            } else {
                XCTAssertEqual(c.state, .outcomeUnknown(.malformedResponse))
                XCTAssertNotNil(try journal.pending(ownerKey: "scope-a", targetKey: "profile.participants"))
            }
        }
    }
    func testSamePageRetryRetainsUUIDAndRestartCannotReusePayload() async throws {
        let io = DurableParticipantIO(), journal = DurableParticipantJournal()
        let c = flow(io, journal), review = try await submit(c, io)
        let original = try XCTUnwrap(ParticipantOriginalCreateRetry(confirmation: review))
        let restarted = flow(io, journal)
        XCTAssertFalse(restarted.canRetryOriginalCreate(original))
        io.mode = .success
        XCTAssertTrue(c.canRetryOriginalCreate(original))
        _ = await c.retryOriginalCreate(original)
        XCTAssertEqual(io.ids, [review.id, review.id]); XCTAssertEqual(c.state, .succeeded)
        XCTAssertNil(try journal.pending(ownerKey: "scope-a", targetKey: "profile.participants"))
    }
    func testCancelUnsubmittedConfirmationNeverCreatesMarker() throws {
        let io = DurableParticipantIO(), journal = DurableParticipantJournal(), c = flow(io, journal)
        let review = try c.prepare(.save(draft()), expectedIdentity: io.identity!)
        c.cancelConfirmation(review)
        XCTAssertTrue(journal.records.isEmpty); XCTAssertTrue(io.ids.isEmpty)
    }
}

@MainActor private final class DurableParticipantJournal: OperationPendingJournal {
    var records: [String: OperationPendingRecord] = [:]
    var failRead = false, failWrite = false, failAfterWrite = false, failClear = false
    func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? {
        if failRead { throw APIError.malformedResponse }; return records[ownerKey + targetKey]
    }
    func write(_ record: OperationPendingRecord) throws {
        if failWrite { throw APIError.notConfigured }
        let key = record.ownerKey + record.targetKey
        if let held = records[key], held.operationID != record.operationID { throw APIError.invalidRequest }
        records[key] = record
        if failAfterWrite { throw APIError.notConfigured }
    }
    func clear(_ record: OperationPendingRecord) throws {
        if failClear { throw APIError.notConfigured }
        let key = record.ownerKey + record.targetKey
        guard records[key] == record else { throw APIError.invalidRequest }
        records[key] = nil
    }
}
@MainActor private final class DurableParticipantIO: ProfileReading, ParticipantWriting {
    enum Mode { case unknown, success, notSent, nilRow }
    var mode: Mode = .unknown
    var identity: ProfileReadIdentity? = .init(accountID: 7, epoch: 1)
    var isConfigured = true
    var ids: [UUID] = []
    func perform(_ mutation: ParticipantMutation, expectedIdentity: ProfileReadIdentity) async throws { XCTFail("Original UUID required") }
    func performReturningParticipant(_ mutation: ParticipantMutation, requestID: UUID, expectedIdentity: ProfileReadIdentity) async throws -> ProfileParticipant? {
        ids.append(requestID)
        switch mode {
        case .unknown: throw ParticipantWriteError.outcomeUnknown(.transport)
        case .notSent: throw ParticipantWriteError.notSent(.notConfigured)
        case .nilRow: return nil
        case .success: return try JSONDecoder().decode(ProfileParticipant.self, from: Data(#"{"id":9,"fullName":"Name","mobilePhone":"13900000000"}"#.utf8))
        }
    }
    func profileParticipants() async throws -> [ProfileParticipant] { [] }
    func profileParticipant(id: Int) async throws -> ProfileParticipant { throw APIError.notConfigured }
    func profileOrders() async throws -> [ProfileOrder] { throw APIError.notConfigured }
    func profileOrder(id: Int) async throws -> ProfileOrder { throw APIError.notConfigured }
    func profileBadges() async throws -> ProfileBadgeWall { throw APIError.notConfigured }
}

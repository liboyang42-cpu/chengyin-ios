import XCTest
@testable import QuestifyCore

/// New faithful specimens; the three conflicting legacy perform-only fakes stay untouched.
@MainActor final class ProfileParticipantOriginalRecoveryTests: XCTestCase {
    func testOriginalCreateUUIDFrozenPayloadAndSuccessfulRow() async throws {
        let io = ParticipantRecoverySpecimen()
        let flow = ParticipantMutationCoordinator(writer: io, reader: io)
        var draft = ParticipantFormDraft(); draft.fullName = "Name"; draft.mobilePhone = "13900000000"
        let review = try flow.prepare(.save(draft), expectedIdentity: io.identity!)
        draft.fullName = "Later edit"
        let result = await flow.confirm(review)
        XCTAssertEqual(result, .applied); XCTAssertEqual(flow.state, .succeeded)
        XCTAssertEqual(io.ids, [review.id]); XCTAssertEqual(io.mutations, [review.mutation])
        XCTAssertEqual(flow.savedParticipant?.fullName, "Name")
        _ = await flow.confirm(review); XCTAssertEqual(io.ids.count, 1)
    }
    func testUnknownCurrentNeverUnlocksAndRetryKeepsOriginalUUID() async throws {
        let io = ParticipantRecoverySpecimen()
        let coordinator = ParticipantMutationCoordinator(writer: io, reader: io)
        io.fail = true
        var draft = ParticipantFormDraft(); draft.fullName = "Name"; draft.mobilePhone = "13900000000"
        let review = try coordinator.prepare(.save(draft), expectedIdentity: io.identity!)
        let original = try XCTUnwrap(ParticipantOriginalCreateRetry(confirmation: review))
        _ = await coordinator.confirm(review)
        _ = await coordinator.readBackUncertainOutcome()
        XCTAssertEqual(coordinator.state, .outcomeUnknown(.transport)); XCTAssertFalse(coordinator.canPrepare)
        XCTAssertEqual(io.ids, [review.id]); XCTAssertEqual(io.reads, 1)
        io.fail = false
        _ = await coordinator.retryOriginalCreate(original)
        XCTAssertEqual(io.ids, [review.id, review.id]); XCTAssertEqual(io.mutations, [review.mutation, review.mutation])
        XCTAssertEqual(coordinator.state, .succeeded)
    }
    func testNilCreateRowStaysUnknownButEditDeleteACKDoNotRequireEcho() async throws {
        for mutation in [ParticipantMutation.delete(id: 9), .save(ParticipantFormDraft(detail: try ParticipantRecoverySpecimen.row()))] {
            let io = ParticipantRecoverySpecimen(); io.returnRow = false
            let flow = ParticipantMutationCoordinator(writer: io, reader: io)
            let review = try flow.prepare(mutation, expectedIdentity: io.identity!)
            _ = await flow.confirm(review); XCTAssertEqual(flow.state, .succeeded)
        }
        let io = ParticipantRecoverySpecimen(); io.returnRow = false
        let flow = ParticipantMutationCoordinator(writer: io, reader: io)
        var draft = ParticipantFormDraft(); draft.fullName = "Name"; draft.mobilePhone = "13900000000"
        let review = try flow.prepare(.save(draft), expectedIdentity: io.identity!)
        _ = await flow.confirm(review); XCTAssertEqual(flow.state, .outcomeUnknown(.malformedResponse))
    }
    func testGrantRevisionRetiresOriginalRetryWithoutDroppingAccountLock() async throws {
        let io = ParticipantRecoverySpecimen(); io.fail = true
        let flow = ParticipantMutationCoordinator(writer: io, reader: io)
        var draft = ParticipantFormDraft(); draft.fullName = "Name"; draft.mobilePhone = "13900000000"
        let review = try flow.prepare(.save(draft), expectedIdentity: io.identity!)
        let original = try XCTUnwrap(ParticipantOriginalCreateRetry(confirmation: review))
        _ = await flow.confirm(review)
        io.identity = .init(accountID: 7, epoch: 1, viewerRevision: 1, approvalRevision: UUID())
        flow.synchronizeSession(); XCTAssertFalse(flow.canRetryOriginalCreate(original)); XCTAssertFalse(flow.canPrepare)
        _ = await flow.readBackUncertainOutcome(); XCTAssertFalse(flow.canPrepare)
        io.identity = .init(accountID: 8, epoch: 2)
        flow.synchronizeSession(); XCTAssertEqual(flow.state, .idle); XCTAssertEqual(flow.readbackState, .idle)
        io.identity = .init(accountID: 7, epoch: 3)
        flow.synchronizeSession(); XCTAssertFalse(flow.canPrepare)
        let restarted = ParticipantMutationCoordinator(writer: io, reader: io)
        XCTAssertEqual(restarted.state, .idle) // Existing memory-only boundary, not durable recovery.
        XCTAssertEqual(io.ids.count, 1)
    }
    func testRetryRejectionDoesNotProveOriginalFailure() async throws {
        let io = ParticipantRecoverySpecimen(); io.fail = true
        let flow = ParticipantMutationCoordinator(writer: io, reader: io)
        var draft = ParticipantFormDraft(); draft.fullName = "Name"; draft.mobilePhone = "13900000000"
        let review = try flow.prepare(.save(draft), expectedIdentity: io.identity!)
        let original = try XCTUnwrap(ParticipantOriginalCreateRetry(confirmation: review))
        _ = await flow.confirm(review); io.fail = false; io.reject = true
        _ = await flow.retryOriginalCreate(original)
        if case .outcomeUnknown = flow.state {} else { XCTFail() }
        XCTAssertFalse(flow.canPrepare); XCTAssertEqual(io.ids, [review.id, review.id])
    }
}
@MainActor private final class ParticipantRecoverySpecimen: ProfileReading, ParticipantWriting {
    var identity: ProfileReadIdentity? = .init(accountID: 7, epoch: 1, viewerRevision: 1, approvalRevision: UUID())
    var isConfigured = true, fail = false, reject = false, returnRow = true
    var ids: [UUID] = [], mutations: [ParticipantMutation] = [], reads = 0
    static func row() throws -> ProfileParticipant {
        try JSONDecoder().decode(ProfileParticipant.self, from: Data(#"{"id":9,"fullName":"Name","mobilePhone":"13900000000"}"#.utf8))
    }
    func perform(_ mutation: ParticipantMutation, expectedIdentity: ProfileReadIdentity) async throws { XCTFail("Normal create must retain the original UUID") }
    func performReturningParticipant(_ mutation: ParticipantMutation, requestID: UUID, expectedIdentity: ProfileReadIdentity) async throws -> ProfileParticipant? {
        ids.append(requestID); mutations.append(mutation)
        if fail { throw ParticipantWriteError.outcomeUnknown(.transport) }
        if reject { throw ParticipantWriteError.rejected(.init(code: 401)) }
        if returnRow { return try Self.row() }; return nil
    }
    func profileParticipants() async throws -> [ProfileParticipant] { reads += 1; return [] }
    func profileParticipant(id: Int) async throws -> ProfileParticipant { reads += 1; return try Self.row() }
    func profileOrders() async throws -> [ProfileOrder] { throw APIError.notConfigured }
    func profileOrder(id: Int) async throws -> ProfileOrder { throw APIError.notConfigured }
    func profileBadges() async throws -> ProfileBadgeWall { throw APIError.notConfigured }
}

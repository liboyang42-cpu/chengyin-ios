import XCTest
@testable import QuestifyCore

@MainActor
final class ParticipantCoordinatorTests: XCTestCase {
    private func fixture() -> (ParticipantMutationCoordinator, ParticipantFakeWriter, ParticipantFakeReader) {
        let writer = ParticipantFakeWriter()
        let reader = ParticipantFakeReader()
        return (ParticipantMutationCoordinator(writer: writer, reader: reader), writer, reader)
    }
    func testCurrentMiniPhoneRuleCannotCreateConfirmationOrWrite() throws {
        let (coordinator, writer, _) = fixture()
        for initial in [ParticipantFormDraft(), ParticipantFormDraft(detail: try participantFixture())] {
            for phone in ["10000000000", "11000000000", "12000000000"] {
                var draft = initial
                draft.fullName = "Fixture"; draft.mobilePhone = phone
                XCTAssertThrowsError(try coordinator.prepare(.save(draft), expectedIdentity: writer.identity!)) {
                    XCTAssertEqual($0 as? ParticipantCoordinatorBlock, .invalidForm)
                }
                XCTAssertEqual(coordinator.state, .idle)
            }
        }
        XCTAssertTrue(writer.mutations.isEmpty)
        XCTAssertTrue(coordinator.canPrepare)
    }
    func testPrepareRequiresValidFormCurrentIdentityAndConfiguration() throws {
        let (coordinator, writer, reader) = fixture()
        let identity = try XCTUnwrap(writer.identity)
        XCTAssertThrowsError(try coordinator.prepare(.save(ParticipantFormDraft()), expectedIdentity: identity))
        XCTAssertThrowsError(try coordinator.prepare(.delete(id: 0), expectedIdentity: identity))
        XCTAssertThrowsError(try coordinator.prepare(.delete(id: 7), expectedIdentity: .init(accountID: 2, epoch: 1)))
        writer.isConfigured = false
        XCTAssertThrowsError(try coordinator.prepare(.delete(id: 7), expectedIdentity: identity))
        writer.isConfigured = true; writer.identity = nil; reader.identity = nil
        XCTAssertThrowsError(try coordinator.prepare(.delete(id: 7), expectedIdentity: identity))
        XCTAssertTrue(writer.mutations.isEmpty)
    }
    func testPreparingAndCancellingConfirmationNeverSends() throws {
        let (coordinator, writer, _) = fixture()
        let confirmation = try coordinator.prepare(.save(participantDraftFixture()), expectedIdentity: writer.identity!)
        XCTAssertEqual(coordinator.state, .awaitingConfirmation)
        XCTAssertFalse(coordinator.canPrepare)
        XCTAssertTrue(writer.mutations.isEmpty)
        coordinator.cancelConfirmation(confirmation)
        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertTrue(coordinator.canPrepare)
    }
    func testOnlyFrozenConfirmedValuesAreSubmittedAndCompletedIntentCannotReplay() async throws {
        let (coordinator, writer, _) = fixture()
        var draft = participantDraftFixture()
        let confirmation = try coordinator.prepare(.save(draft), expectedIdentity: writer.identity!)
        draft.fullName = "Changed after confirmation"
        let first = await coordinator.confirm(confirmation)
        let duplicate = await coordinator.confirm(confirmation)
        XCTAssertEqual(first, .applied)
        XCTAssertEqual(duplicate, .blocked(.confirmationNoLongerValid))
        XCTAssertEqual(writer.mutations, [.save(participantDraftFixture())])
        XCTAssertEqual(coordinator.state, .succeeded)
    }
    func testRepeatedConfirmDuringSuspendedWriteIsBlocked() async throws {
        let (coordinator, writer, _) = fixture()
        var resume: CheckedContinuation<Void, Error>?
        writer.operation = { _ in try await withCheckedThrowingContinuation { resume = $0 } }
        let confirmation = try coordinator.prepare(.delete(id: 7), expectedIdentity: writer.identity!)
        let task = Task { await coordinator.confirm(confirmation) }
        while resume == nil { await Task.yield() }
        XCTAssertEqual(coordinator.state, .submitting)
        let duplicate = await coordinator.confirm(confirmation)
        XCTAssertEqual(duplicate, .blocked(.confirmationNoLongerValid))
        XCTAssertThrowsError(try coordinator.prepare(.delete(id: 7), expectedIdentity: writer.identity!))
        resume?.resume(returning: ())
        _ = await task.value
        XCTAssertEqual(writer.mutations.count, 1)
    }
    func testUnknownCreateReadbackDoesNotResubmitUnlockOrClaimSuccess() async throws {
        let (coordinator, writer, reader) = fixture()
        writer.operation = { _ in throw ParticipantWriteError.outcomeUnknown(.transport) }
        reader.rows = [try participantFixture()]
        let confirmation = try coordinator.prepare(.save(participantDraftFixture()), expectedIdentity: writer.identity!)
        _ = await coordinator.confirm(confirmation)
        XCTAssertEqual(coordinator.state, .outcomeUnknown(.transport))
        XCTAssertFalse(coordinator.canPrepare)
        let read = await coordinator.readBackUncertainOutcome()
        XCTAssertEqual(read, .applied)
        XCTAssertEqual(reader.listCalls, 1)
        XCTAssertEqual(coordinator.readbackState, .received(.list(reader.rows)))
        XCTAssertFalse(coordinator.canPrepare)
        XCTAssertThrowsError(try coordinator.prepare(.save(participantDraftFixture()), expectedIdentity: writer.identity!))
        let duplicate = await coordinator.confirm(confirmation)
        XCTAssertEqual(duplicate, .blocked(.confirmationNoLongerValid))
        XCTAssertEqual(writer.mutations.count, 1)
    }
    func testUnknownEditAndDefaultReadExactlyKnownDetail() async throws {
        for mutation in [ParticipantMutation.save(ParticipantFormDraft(detail: try participantFixture())), .setDefault(id: 7)] {
            let (coordinator, writer, reader) = fixture()
            writer.operation = { _ in throw ParticipantWriteError.outcomeUnknown(.malformedResponse) }
            let confirmation = try coordinator.prepare(mutation, expectedIdentity: writer.identity!)
            _ = await coordinator.confirm(confirmation)
            _ = await coordinator.readBackUncertainOutcome()
            XCTAssertEqual(reader.detailIDs, [7])
            XCTAssertEqual(reader.listCalls, 0)
            XCTAssertEqual(writer.mutations.count, 1)
            XCTAssertFalse(coordinator.canPrepare)
        }
    }
    func testUnknownDeleteEmptyListAndFailedReadbackRemainUncertain() async throws {
        let (coordinator, writer, reader) = fixture()
        writer.operation = { _ in throw ParticipantWriteError.outcomeUnknown(.transport) }
        let confirmation = try coordinator.prepare(.delete(id: 7), expectedIdentity: writer.identity!)
        _ = await coordinator.confirm(confirmation)
        _ = await coordinator.readBackUncertainOutcome()
        XCTAssertEqual(coordinator.readbackState, .received(.list([])))
        XCTAssertFalse(coordinator.canPrepare)
        reader.readError = APIError.malformedResponse
        _ = await coordinator.readBackUncertainOutcome()
        XCTAssertEqual(coordinator.readbackState, .unavailable)
        XCTAssertFalse(coordinator.canPrepare)
        XCTAssertEqual(writer.mutations.count, 1)
        XCTAssertEqual(reader.listCalls, 2)
    }
    func testExplicitRejectionAllowsNewConfirmationButNeverImplicitRetry() async throws {
        let (coordinator, writer, _) = fixture()
        let failure = ParticipantResponseFailure(code: 403, message: "Unavailable")
        writer.operation = { _ in throw ParticipantWriteError.rejected(failure) }
        let confirmation = try coordinator.prepare(.delete(id: 7), expectedIdentity: writer.identity!)
        _ = await coordinator.confirm(confirmation)
        XCTAssertEqual(coordinator.state, .rejected(failure))
        XCTAssertTrue(coordinator.canPrepare)
        let replacement = try coordinator.prepare(.delete(id: 7), expectedIdentity: writer.identity!)
        XCTAssertNotEqual(replacement.id, confirmation.id)
        XCTAssertEqual(writer.mutations.count, 1)
        coordinator.cancelConfirmation(replacement)
    }
    func testAccountChangeBeforeConfirmationSendsNothing() async throws {
        let (coordinator, writer, reader) = fixture()
        let confirmation = try coordinator.prepare(.delete(id: 7), expectedIdentity: writer.identity!)
        writer.identity = .init(accountID: 1, epoch: 2); reader.identity = writer.identity
        let result = await coordinator.confirm(confirmation)
        XCTAssertEqual(result, .blocked(.accountChanged))
        XCTAssertTrue(writer.mutations.isEmpty)
        XCTAssertEqual(coordinator.state, .idle)
    }
    func testAccountChangeDuringWriteHidesOldOutcomeAndRetainsLockForOriginalAccount() async throws {
        let (coordinator, writer, reader) = fixture()
        let original = writer.identity!
        writer.operation = { _ in
            writer.identity = .init(accountID: 2, epoch: 2); reader.identity = writer.identity
        }
        let confirmation = try coordinator.prepare(.delete(id: 7), expectedIdentity: original)
        let result = await coordinator.confirm(confirmation)
        XCTAssertEqual(result, .ignoredStale)
        XCTAssertEqual(coordinator.state, .idle)
        XCTAssertEqual(coordinator.readbackState, .idle)
        writer.identity = .init(accountID: 1, epoch: 3); reader.identity = writer.identity
        XCTAssertEqual(coordinator.state, .outcomeUnknown(.accountChanged))
        XCTAssertFalse(coordinator.canPrepare)
        _ = await coordinator.readBackUncertainOutcome()
        XCTAssertEqual(reader.listCalls, 1)
        XCTAssertFalse(coordinator.canPrepare)
    }
    func testDismissedInFlightWriteCannotBecomeSuccessOrReplayOnLateCompletion() async throws {
        let writer = ParticipantFakeWriter(); let reader = ParticipantFakeReader()
        var changes = 0
        let coordinator = ParticipantMutationCoordinator(writer: writer, reader: reader, onParticipantsChanged: { changes += 1 })
        var resume: CheckedContinuation<Void, Error>?
        writer.operation = { _ in try await withCheckedThrowingContinuation { resume = $0 } }
        let confirmation = try coordinator.prepare(.delete(id: 7), expectedIdentity: writer.identity!)
        let task = Task { await coordinator.confirm(confirmation) }
        while resume == nil { await Task.yield() }
        coordinator.leaveScreen(confirmation: confirmation)
        XCTAssertEqual(coordinator.state, .outcomeUnknown(.cancelled))
        resume?.resume(returning: ())
        let result = await task.value
        XCTAssertEqual(result, .ignoredStale)
        XCTAssertEqual(coordinator.state, .outcomeUnknown(.cancelled))
        XCTAssertEqual(changes, 0)
        XCTAssertFalse(coordinator.canPrepare)
    }
    func testSuccessfulMutationInvalidatesSharedRowsExactlyOnce() async throws {
        let writer = ParticipantFakeWriter(); let reader = ParticipantFakeReader()
        var changes = 0
        let coordinator = ParticipantMutationCoordinator(writer: writer, reader: reader, onParticipantsChanged: { changes += 1 })
        let confirmation = try coordinator.prepare(.delete(id: 7), expectedIdentity: writer.identity!)
        _ = await coordinator.confirm(confirmation)
        _ = await coordinator.confirm(confirmation)
        XCTAssertEqual(changes, 1)
        XCTAssertEqual(writer.mutations.count, 1)
    }
    func testReadbackRaceCannotLeakOldRowsIntoReplacementAccount() async throws {
        let (coordinator, writer, reader) = fixture()
        writer.operation = { _ in throw ParticipantWriteError.outcomeUnknown(.transport) }
        let confirmation = try coordinator.prepare(.delete(id: 7), expectedIdentity: writer.identity!)
        _ = await coordinator.confirm(confirmation)
        reader.beforeRead = {
            writer.identity = .init(accountID: 2, epoch: 2); reader.identity = writer.identity
        }
        reader.rows = [try participantFixture()]
        let result = await coordinator.readBackUncertainOutcome()
        XCTAssertEqual(result, .ignoredStale)
        XCTAssertEqual(coordinator.readbackState, .idle)
        XCTAssertEqual(coordinator.state, .idle)
    }
    func testCancellationAfterDispatchRemainsUnknownEvenWhenWriterIgnoresCancellation() async throws {
        let (coordinator, writer, _) = fixture()
        var resume: CheckedContinuation<Void, Error>?
        writer.operation = { _ in try await withCheckedThrowingContinuation { resume = $0 } }
        let confirmation = try coordinator.prepare(.save(participantDraftFixture()), expectedIdentity: writer.identity!)
        let task = Task { await coordinator.confirm(confirmation) }
        while resume == nil { await Task.yield() }
        task.cancel()
        resume?.resume(returning: ())
        _ = await task.value
        XCTAssertEqual(coordinator.state, .outcomeUnknown(.cancelled))
        XCTAssertFalse(coordinator.canPrepare)
        XCTAssertEqual(writer.mutations.count, 1)
    }
    func testReadbackMismatchedDetailIsUnavailableAndStaysLocked() async throws {
        let (coordinator, writer, reader) = fixture()
        writer.operation = { _ in throw ParticipantWriteError.outcomeUnknown(.transport) }
        reader.detail = try participantFixture(#"{"id":99}"#)
        let confirmation = try coordinator.prepare(.setDefault(id: 7), expectedIdentity: writer.identity!)
        _ = await coordinator.confirm(confirmation)
        _ = await coordinator.readBackUncertainOutcome()
        XCTAssertEqual(coordinator.readbackState, .unavailable)
        XCTAssertFalse(coordinator.canPrepare)
    }
    func testRepeatedReadbackIsBlockedAndDismissalDiscardsLateSnapshot() async throws {
        let (coordinator, writer, reader) = fixture()
        writer.operation = { _ in throw ParticipantWriteError.outcomeUnknown(.transport) }
        let identity = writer.identity!
        let confirmation = try coordinator.prepare(.delete(id: 7), expectedIdentity: identity)
        _ = await coordinator.confirm(confirmation)
        var resume: CheckedContinuation<Void, Never>?
        reader.waitForRead = { await withCheckedContinuation { resume = $0 } }
        reader.rows = [try participantFixture()]
        let task = Task { await coordinator.readBackUncertainOutcome() }
        while resume == nil { await Task.yield() }
        let duplicate = await coordinator.readBackUncertainOutcome()
        XCTAssertEqual(duplicate, .blocked(.readbackInProgress))
        coordinator.discardReadback(expectedIdentity: identity)
        resume?.resume(returning: ())
        let result = await task.value
        XCTAssertEqual(result, .ignoredStale)
        XCTAssertEqual(coordinator.readbackState, .idle)
        XCTAssertFalse(coordinator.canPrepare)
        XCTAssertEqual(reader.listCalls, 1)
        XCTAssertEqual(writer.mutations.count, 1)
    }
}

@MainActor
final class ParticipantFakeWriter: ParticipantWriting {
    var isConfigured = true
    var identity: ProfileReadIdentity? = .init(accountID: 1, epoch: 1)
    var mutations: [ParticipantMutation] = []
    var operation: (ParticipantMutation) async throws -> Void = { _ in }
    func perform(_ mutation: ParticipantMutation, expectedIdentity: ProfileReadIdentity) async throws {
        guard expectedIdentity == identity else { throw ParticipantWriteError.notSent(.unauthorized) }
        mutations.append(mutation)
        try await operation(mutation)
    }
}

@MainActor
final class ParticipantFakeReader: ProfileReading {
    var isConfigured = true
    var identity: ProfileReadIdentity? = .init(accountID: 1, epoch: 1)
    var rows: [ProfileParticipant] = []
    var detail: ProfileParticipant?
    var listCalls = 0
    var detailIDs: [Int] = []
    var readError: Error?
    var beforeRead: () -> Void = {}
    var waitForRead: () async -> Void = {}
    func profileParticipants() async throws -> [ProfileParticipant] {
        listCalls += 1; beforeRead()
        await waitForRead()
        if let readError { throw readError }
        return rows
    }
    func profileParticipant(id: Int) async throws -> ProfileParticipant {
        detailIDs.append(id); beforeRead()
        await waitForRead()
        if let readError { throw readError }
        return try detail ?? participantFixture()
    }
    func profileOrders() async throws -> [ProfileOrder] { [] }
    func profileOrder(id: Int) async throws -> ProfileOrder { throw APIError.invalidRequest }
    func profileBadges() async throws -> ProfileBadgeWall { .init(identities: [], medals: []) }
}

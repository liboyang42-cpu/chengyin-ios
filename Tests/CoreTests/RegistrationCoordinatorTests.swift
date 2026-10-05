import Foundation
import XCTest
@testable import QuestifyCore

/// Manually completed service calls: no clocks, sleeps, sockets, real accounts or SDKs.
@MainActor
private final class ControlledRegistrationService: RegistrationCoordinatingService {
    enum Operation { case quote, create, read }
    private(set) var quotes: [(selection: RegistrationQuoteRequest, token: String)] = []
    private(set) var creates: [(intent: RegistrationCreateIntent, token: String)] = []
    private(set) var reads: [(id: Int, token: String)] = []
    private var pendingQuotes: [Int: CheckedContinuation<RegistrationQuote, Error>] = [:]
    private var pendingCreates: [Int: CheckedContinuation<RegistrationCreateResult, Error>] = [:]
    private var pendingReads: [Int: CheckedContinuation<RegistrationStatusSnapshot, Error>] = [:]
    private var waiters: [(Operation, Int, CheckedContinuation<Void, Never>)] = []

    func quote(_ selection: RegistrationQuoteRequest, token: String) async throws -> RegistrationQuote {
        let index = quotes.count
        quotes.append((selection, token))
        return try await withCheckedThrowingContinuation { continuation in
            pendingQuotes[index] = continuation
            notifyWaiters()
        }
    }

    func create(_ intent: RegistrationCreateIntent, token: String) async throws -> RegistrationCreateResult {
        let index = creates.count
        creates.append((intent, token))
        return try await withCheckedThrowingContinuation { continuation in
            pendingCreates[index] = continuation
            notifyWaiters()
        }
    }

    func readStatus(registrationID: Int, token: String) async throws -> RegistrationStatusSnapshot {
        let index = reads.count
        reads.append((registrationID, token))
        return try await withCheckedThrowingContinuation { continuation in
            pendingReads[index] = continuation
            notifyWaiters()
        }
    }

    func waitFor(_ operation: Operation, count: Int) async {
        if callCount(operation) >= count { return }
        await withCheckedContinuation { waiters.append((operation, count, $0)) }
    }

    func completeQuote(_ index: Int, _ result: Result<RegistrationQuote, Error>) {
        pendingQuotes.removeValue(forKey: index)!.resume(with: result)
    }
    func completeCreate(_ index: Int, _ result: Result<RegistrationCreateResult, Error>) {
        pendingCreates.removeValue(forKey: index)!.resume(with: result)
    }
    func completeRead(_ index: Int, _ result: Result<RegistrationStatusSnapshot, Error>) {
        pendingReads.removeValue(forKey: index)!.resume(with: result)
    }

    private func callCount(_ operation: Operation) -> Int {
        switch operation {
        case .quote: return quotes.count
        case .create: return creates.count
        case .read: return reads.count
        }
    }
    private func notifyWaiters() {
        let ready = waiters.filter { callCount($0.0) >= $0.1 }
        waiters.removeAll { callCount($0.0) >= $0.1 }
        for waiter in ready { waiter.2.resume() }
    }
}

@MainActor
final class RegistrationCoordinatorTests: XCTestCase {
    private let participant = RegistrationParticipantDetails(
        realName: "Synthetic Participant", phone: "synthetic-phone", email: "fixture@example.invalid"
    )

    private func quote(_ json: String = #"{"payAmount":19.99,"quoteSign":"fixture-signature"}"#) throws -> RegistrationQuote {
        try JSONDecoder().decode(RegistrationQuote.self, from: Data(json.utf8))
    }
    private func result(_ json: String = #"{"registrationId":41,"payableAmount":19.99}"#) throws -> RegistrationCreateResult {
        try JSONDecoder().decode(RegistrationCreateResult.self, from: Data(json.utf8))
    }
    private func snapshot(_ json: String = #"{"id":41,"registrationStatus":1,"paymentStatus":2,"verificationStatus":0}"#) throws -> RegistrationStatusSnapshot {
        try JSONDecoder().decode(RegistrationStatusSnapshot.self, from: Data(json.utf8))
    }
    private func makeCoordinator(_ service: ControlledRegistrationService,
                                 makeID: @escaping () -> String = { "fixture-request-id" }) throws -> RegistrationCoordinator {
        let coordinator = RegistrationCoordinator(service: service, makeRequestID: makeID)
        try coordinator.setAccount(id: 1, token: "fixture-account-one-token")
        XCTAssertEqual(coordinator.select(try RegistrationQuoteRequest(ownerID: 7, ticketID: 11)), .applied)
        return coordinator
    }
    private func loadQuote(_ coordinator: RegistrationCoordinator, _ service: ControlledRegistrationService,
                           value: RegistrationQuote? = nil) async throws {
        let count = service.quotes.count
        let task = Task { await coordinator.requestQuote() }
        await service.waitFor(.quote, count: count + 1)
        service.completeQuote(count, .success(try value ?? quote()))
        let action = await task.value
        XCTAssertEqual(action, .applied)
    }
    private func create(_ coordinator: RegistrationCoordinator, _ service: ControlledRegistrationService,
                        value: RegistrationCreateResult? = nil) async throws {
        let count = service.creates.count
        let task = Task { await coordinator.confirm(participant) }
        await service.waitFor(.create, count: count + 1)
        service.completeCreate(count, .success(try value ?? result()))
        let action = await task.value
        XCTAssertEqual(action, .applied)
    }

    func testSignedOutAndMissingSelectionNeverDispatch() async throws {
        let service = ControlledRegistrationService()
        let coordinator = RegistrationCoordinator(service: service)
        let quoteAction = await coordinator.requestQuote()
        let createAction = await coordinator.confirm(participant)
        let readAction = await coordinator.readKnownStatus()
        XCTAssertEqual(quoteAction, .blocked(.signedOut))
        XCTAssertEqual(createAction, .blocked(.signedOut))
        XCTAssertEqual(readAction, .blocked(.signedOut))
        XCTAssertEqual(coordinator.select(try RegistrationQuoteRequest(ownerID: 7)), .blocked(.signedOut))
        try coordinator.setAccount(id: 1, token: "fixture-token")
        let missing = await coordinator.requestQuote()
        XCTAssertEqual(missing, .blocked(.missingSelection))
        XCTAssertFalse(coordinator.canConfirm)
        XCTAssertTrue(service.quotes.isEmpty)
        XCTAssertTrue(service.creates.isEmpty)
        XCTAssertTrue(service.reads.isEmpty)
    }

    func testIncompleteQuotesCannotCreateButExplicitZeroCan() async throws {
        for json in [#"{"quoteSign":"fixture-signature"}"#, #"{"payAmount":0}"#,
                     #"{"payAmount":0,"quoteSign":"  "}"#] {
            let service = ControlledRegistrationService()
            let coordinator = try makeCoordinator(service)
            try await loadQuote(coordinator, service, value: quote(json))
            let action = await coordinator.confirm(participant)
            XCTAssertEqual(action, .blocked(.quoteNotUsable))
            XCTAssertFalse(coordinator.canConfirm)
            XCTAssertNil(coordinator.retainedIntent)
            XCTAssertTrue(service.creates.isEmpty)
        }
        let service = ControlledRegistrationService()
        let coordinator = try makeCoordinator(service)
        try await loadQuote(coordinator, service, value: quote(#"{"payAmount":0,"quoteSign":"fixture-zero"}"#))
        XCTAssertTrue(coordinator.canConfirm)
        XCTAssertTrue(service.creates.isEmpty, "A usable quote is not implicit confirmation")
    }

    func testSelectionAndPointsChangesInvalidateQuoteIncludingChangeAwayAndBack() async throws {
        let service = ControlledRegistrationService()
        let coordinator = try makeCoordinator(service)
        let original = try XCTUnwrap(coordinator.selection)
        try await loadQuote(coordinator, service)
        XCTAssertTrue(coordinator.canConfirm)
        for selection in [try RegistrationQuoteRequest(ownerID: 7, ticketID: 12),
                          try RegistrationQuoteRequest(ownerID: 7, ticketID: 12, usePoints: true), original] {
            XCTAssertEqual(coordinator.select(selection), .applied)
            XCTAssertEqual(coordinator.quoteState, .idle)
            let action = await coordinator.confirm(participant)
            XCTAssertEqual(action, .blocked(.quoteNotUsable))
        }
        XCTAssertTrue(service.creates.isEmpty)
    }

    func testSelectionRaceIgnoresLateQuoteForOldSelection() async throws {
        let service = ControlledRegistrationService()
        let coordinator = try makeCoordinator(service)
        let old = Task { await coordinator.requestQuote() }
        await service.waitFor(.quote, count: 1)
        let selection = try RegistrationQuoteRequest(ownerID: 8, ticketID: 12, usePoints: true)
        XCTAssertEqual(coordinator.select(selection), .applied)
        try await loadQuote(coordinator, service, value: quote(#"{"payAmount":30,"quoteSign":"new-selection"}"#))
        service.completeQuote(0, .success(try quote()))
        let action = await old.value
        XCTAssertEqual(action, .ignoredStale)
        try await create(coordinator, service)
        XCTAssertEqual(service.creates[0].intent.selection, selection)
        XCTAssertEqual(service.creates[0].intent.quoteSign, "new-selection")
    }

    func testLatestQuoteRequestWinsAndRefreshBlocksConfirmImmediately() async throws {
        let service = ControlledRegistrationService()
        let coordinator = try makeCoordinator(service)
        try await loadQuote(coordinator, service)
        let older = Task { await coordinator.requestQuote() }
        await service.waitFor(.quote, count: 2)
        let blocked = await coordinator.confirm(participant)
        XCTAssertEqual(blocked, .blocked(.quoteNotUsable))
        try await loadQuote(coordinator, service, value: quote(#"{"payAmount":22,"quoteSign":"latest"}"#))
        service.completeQuote(1, .failure(APIError.unauthorized))
        let action = await older.value
        XCTAssertEqual(action, .ignoredStale)
        XCTAssertEqual(coordinator.quoteState, .received(try quote(#"{"payAmount":22,"quoteSign":"latest"}"#)))
        XCTAssertEqual(coordinator.accountID, 1)
    }

    func testDuplicateConfirmationDispatchesOnceAndFreeResponseDoesNotCompleteRegistration() async throws {
        let service = ControlledRegistrationService()
        var idsGenerated = 0
        let coordinator = try makeCoordinator(service) { idsGenerated += 1; return "fixture-id-\(idsGenerated)" }
        try await loadQuote(coordinator, service)
        let first = Task { await coordinator.confirm(participant) }
        await service.waitFor(.create, count: 1)
        let duplicate = await coordinator.confirm(RegistrationParticipantDetails(realName: "Changed", phone: "changed"))
        XCTAssertEqual(duplicate, .blocked(.intentAlreadySubmitted))
        XCTAssertEqual(coordinator.creationState, .submitting(requestID: "fixture-id-1"))
        XCTAssertEqual(coordinator.retainedIntent?.realName, participant.realName)
        XCTAssertEqual(coordinator.select(try RegistrationQuoteRequest(ownerID: 99)), .blocked(.intentAlreadySubmitted))
        let free = try result(#"{"registrationId":41,"payableAmount":0,"payParams":{}}"#)
        service.completeCreate(0, .success(free))
        let firstAction = await first.value
        XCTAssertEqual(firstAction, .applied)
        XCTAssertEqual(coordinator.creationState, .responseReceived(requestID: "fixture-id-1", result: free))
        let afterResponse = await coordinator.confirm(participant)
        XCTAssertEqual(afterResponse, .blocked(.intentAlreadySubmitted))
        XCTAssertEqual(idsGenerated, 1)
        XCTAssertEqual(service.creates.count, 1)
        XCTAssertTrue(service.reads.isEmpty, "No automatic readback or polling")
        XCTAssertFalse(coordinator.canConfirm)
    }

    func testInvalidParticipantDoesNotAllocateIntentOrRequestID() async throws {
        let service = ControlledRegistrationService()
        var generated = 0
        let coordinator = try makeCoordinator(service) { generated += 1; return "fixture-id" }
        try await loadQuote(coordinator, service)
        let action = await coordinator.confirm(RegistrationParticipantDetails(realName: " ", phone: "fixture"))
        XCTAssertEqual(action, .blocked(.invalidRequest))
        XCTAssertEqual(generated, 0)
        XCTAssertNil(coordinator.retainedIntent)
        XCTAssertTrue(service.creates.isEmpty)
        XCTAssertTrue(coordinator.canConfirm)
    }

    func testTimeoutRetainsExactIntentAndBlocksRequoteRecreateOrUnknownIDReadback() async throws {
        let service = ControlledRegistrationService()
        let coordinator = try makeCoordinator(service)
        try await loadQuote(coordinator, service)
        let task = Task { await coordinator.confirm(participant) }
        await service.waitFor(.create, count: 1)
        let retained = try XCTUnwrap(coordinator.retainedIntent)
        service.completeCreate(0, .failure(URLError(.timedOut)))
        let action = await task.value
        XCTAssertEqual(action, .applied)
        XCTAssertEqual(coordinator.creationState, .outcomeUnknown(
            requestID: retained.requestID,
            reason: .requestDidNotProduceUsableResponse(.transport(code: URLError.timedOut.rawValue))
        ))
        coordinator.cancelPendingOperations()
        let again = await coordinator.confirm(participant)
        let quoteAgain = await coordinator.requestQuote()
        let read = await coordinator.readKnownStatus()
        XCTAssertEqual(again, .blocked(.intentAlreadySubmitted))
        XCTAssertEqual(quoteAgain, .blocked(.intentAlreadySubmitted))
        XCTAssertEqual(read, .blocked(.noKnownRegistrationID))
        XCTAssertEqual(coordinator.retainedIntent, retained)
        XCTAssertEqual(service.creates.count, 1)
        XCTAssertEqual(service.quotes.count, 1)
        XCTAssertTrue(service.reads.isEmpty)
    }

    func testMalformedBusinessAndHTTPCreateErrorsStayLockedWithoutRoutingByCode() async throws {
        let failures: [Error] = [
            APIError.malformedResponse,
            RegistrationResponseFailure(code: 409, message: "fixture price changed"),
            RegistrationResponseFailure(code: 410, message: "fixture expired"),
            RegistrationHTTPFailure(statusCode: 401, response: nil)
        ]
        for failure in failures {
            let service = ControlledRegistrationService()
            let coordinator = try makeCoordinator(service)
            try await loadQuote(coordinator, service)
            let task = Task { await coordinator.confirm(participant) }
            await service.waitFor(.create, count: 1)
            service.completeCreate(0, .failure(failure))
            _ = await task.value
            guard case .outcomeUnknown(let id, _) = coordinator.creationState else {
                XCTFail("No unverified code may authorize reset or a failure verdict")
                continue
            }
            XCTAssertEqual(id, "fixture-request-id")
            let again = await coordinator.confirm(participant)
            XCTAssertEqual(again, .blocked(.intentAlreadySubmitted))
            XCTAssertEqual(service.creates.count, 1)
            XCTAssertEqual(service.quotes.count, 1)
        }
    }

    func testLocalCancellationDuringCreateIgnoresLateSuccessAndRetainsIntent() async throws {
        let service = ControlledRegistrationService()
        let coordinator = try makeCoordinator(service)
        try await loadQuote(coordinator, service)
        let task = Task { await coordinator.confirm(participant) }
        await service.waitFor(.create, count: 1)
        let retained = coordinator.retainedIntent
        coordinator.cancelPendingOperations()
        service.completeCreate(0, .success(try result()))
        let action = await task.value
        XCTAssertEqual(action, .ignoredStale)
        XCTAssertEqual(coordinator.retainedIntent, retained)
        XCTAssertEqual(coordinator.creationState, .outcomeUnknown(requestID: "fixture-request-id", reason: .cancelledLocally))
        let again = await coordinator.confirm(participant)
        XCTAssertEqual(again, .blocked(.intentAlreadySubmitted))
    }

    func testTaskCancellationDuringCreateStaysUnknownEvenIfServiceReturnsSuccess() async throws {
        let service = ControlledRegistrationService()
        let coordinator = try makeCoordinator(service)
        try await loadQuote(coordinator, service)
        let task = Task { await coordinator.confirm(participant) }
        await service.waitFor(.create, count: 1)
        task.cancel()
        service.completeCreate(0, .success(try result()))
        _ = await task.value
        XCTAssertEqual(coordinator.creationState, .outcomeUnknown(requestID: "fixture-request-id", reason: .cancelledLocally))
        XCTAssertNotNil(coordinator.retainedIntent)
        XCTAssertEqual(service.creates.count, 1)
    }

    func testTransportCancellationDuringCreateStaysUnknown() async throws {
        let service = ControlledRegistrationService()
        let coordinator = try makeCoordinator(service)
        try await loadQuote(coordinator, service)
        let task = Task { await coordinator.confirm(participant) }
        await service.waitFor(.create, count: 1)
        service.completeCreate(0, .failure(CancellationError()))
        _ = await task.value
        XCTAssertEqual(coordinator.creationState, .outcomeUnknown(requestID: "fixture-request-id", reason: .cancelledLocally))
        XCTAssertEqual(service.creates.count, 1)
    }

    func testAlreadyCancelledConfirmationNeverDispatchesOrLocks() async throws {
        let service = ControlledRegistrationService()
        let coordinator = try makeCoordinator(service)
        try await loadQuote(coordinator, service)
        // The main actor cannot run this task before the synchronous cancel below.
        let task = Task { await coordinator.confirm(participant) }
        task.cancel()
        let action = await task.value
        XCTAssertEqual(action, .blocked(.cancelledBeforeDispatch))
        XCTAssertTrue(service.creates.isEmpty)
        XCTAssertNil(coordinator.retainedIntent)
        XCTAssertTrue(coordinator.canConfirm)
    }

    func testAccountChangeAndSameAccountReauthenticationRejectOldQuotes() async throws {
        for newID in [1, 2] {
            let service = ControlledRegistrationService()
            let coordinator = try makeCoordinator(service)
            let task = Task { await coordinator.requestQuote() }
            await service.waitFor(.quote, count: 1)
            try coordinator.setAccount(id: newID, token: "fixture-new-token")
            service.completeQuote(0, .success(try quote()))
            let action = await task.value
            XCTAssertEqual(action, .ignoredStale)
            XCTAssertEqual(coordinator.quoteState, .idle)
            XCTAssertNil(coordinator.selection)
            XCTAssertFalse(coordinator.canConfirm)
        }
    }

    func testAccountChangeDuringCreateIsolatesStateAndRestoresOriginalLockedIntent() async throws {
        let service = ControlledRegistrationService()
        var count = 0
        let coordinator = try makeCoordinator(service) { count += 1; return "fixture-account-intent-\(count)" }
        try await loadQuote(coordinator, service)
        let oldTask = Task { await coordinator.confirm(participant) }
        await service.waitFor(.create, count: 1)
        let firstIntent = coordinator.retainedIntent
        try coordinator.setAccount(id: 2, token: "fixture-account-two-token")
        XCTAssertNil(coordinator.retainedIntent)
        XCTAssertEqual(coordinator.creationState, .idle)
        XCTAssertNil(coordinator.selection)
        XCTAssertEqual(coordinator.select(try RegistrationQuoteRequest(ownerID: 8)), .applied)
        try await loadQuote(coordinator, service)
        try await create(coordinator, service, value: result(#"{"registrationId":42}"#))
        service.completeCreate(0, .success(try result()))
        let oldAction = await oldTask.value
        XCTAssertEqual(oldAction, .ignoredStale)
        XCTAssertEqual(coordinator.retainedIntent?.requestID, "fixture-account-intent-2")
        XCTAssertEqual(service.creates[0].token, "fixture-account-one-token")
        XCTAssertEqual(service.creates[1].token, "fixture-account-two-token")
        try coordinator.setAccount(id: 1, token: "fixture-account-one-new-token")
        XCTAssertEqual(coordinator.retainedIntent, firstIntent)
        XCTAssertEqual(coordinator.creationState, .outcomeUnknown(requestID: "fixture-account-intent-1", reason: .accountChanged))
        XCTAssertEqual(coordinator.selection, firstIntent?.selection)
        XCTAssertEqual(coordinator.quoteState, .idle)
        let blocked = await coordinator.confirm(participant)
        XCTAssertEqual(blocked, .blocked(.intentAlreadySubmitted))
        XCTAssertEqual(service.creates.count, 2)
    }

    func testLogoutAndReturnBeforeCreateCompletesStillRejectsOldGeneration() async throws {
        let service = ControlledRegistrationService()
        let coordinator = try makeCoordinator(service)
        try await loadQuote(coordinator, service)
        let task = Task { await coordinator.confirm(participant) }
        await service.waitFor(.create, count: 1)
        coordinator.clearAccount()
        XCTAssertNil(coordinator.retainedIntent)
        XCTAssertEqual(coordinator.creationState, .idle)
        try coordinator.setAccount(id: 1, token: "fixture-replacement-token")
        service.completeCreate(0, .failure(APIError.unauthorized))
        let action = await task.value
        XCTAssertEqual(action, .ignoredStale)
        XCTAssertEqual(coordinator.accountID, 1)
        XCTAssertEqual(coordinator.creationState, .outcomeUnknown(requestID: "fixture-request-id", reason: .accountChanged))
    }

    func testKnownIDReadbackIsExplicitRawAndDoesNotUnlockCreate() async throws {
        let service = ControlledRegistrationService()
        let coordinator = try makeCoordinator(service)
        try await loadQuote(coordinator, service)
        let createResponse = try result()
        try await create(coordinator, service, value: createResponse)
        XCTAssertTrue(service.reads.isEmpty)
        // Includes conflicting terminal-looking values, future values, and absent fields.
        for json in [#"{"id":41,"registrationStatus":3,"paymentStatus":2}"#,
                     #"{"id":41,"registrationStatus":2,"paymentStatus":4}"#,
                     #"{"id":41,"registrationStatus":999,"paymentStatus":-1,"verificationStatus":9}"#,
                     #"{"id":41}"#] {
            let raw = try snapshot(json)
            let index = service.reads.count
            let task = Task { await coordinator.readKnownStatus() }
            await service.waitFor(.read, count: index + 1)
            let duplicate = await coordinator.readKnownStatus()
            XCTAssertEqual(duplicate, .blocked(.readbackInProgress))
            XCTAssertEqual(service.reads[index].id, 41)
            XCTAssertEqual(service.reads[index].token, "fixture-account-one-token")
            service.completeRead(index, .success(raw))
            let action = await task.value
            XCTAssertEqual(action, .applied)
            XCTAssertEqual(coordinator.readbackState, .received(raw))
            XCTAssertEqual(coordinator.creationState, .responseReceived(requestID: "fixture-request-id", result: createResponse))
            XCTAssertFalse(coordinator.canConfirm)
        }
        XCTAssertEqual(service.reads.count, 4)
        XCTAssertEqual(service.creates.count, 1)
    }

    func testMismatchedReadbackIdentityAndReadErrorsNeverEraseKnownIntent() async throws {
        let service = ControlledRegistrationService()
        let coordinator = try makeCoordinator(service)
        try await loadQuote(coordinator, service)
        try await create(coordinator, service)
        let retained = coordinator.retainedIntent
        let task = Task { await coordinator.readKnownStatus() }
        await service.waitFor(.read, count: 1)
        service.completeRead(0, .success(try snapshot(#"{"id":42,"paymentStatus":2}"#)))
        _ = await task.value
        XCTAssertEqual(coordinator.readbackState, .unavailable(registrationID: 41, issue: .api(.malformedResponse)))
        let retry = Task { await coordinator.readKnownStatus() }
        await service.waitFor(.read, count: 2)
        service.completeRead(1, .failure(URLError(.timedOut)))
        _ = await retry.value
        XCTAssertEqual(coordinator.readbackState, .unavailable(registrationID: 41, issue: .transport(code: URLError.timedOut.rawValue)))
        XCTAssertEqual(coordinator.retainedIntent, retained)
        XCTAssertEqual(service.creates.count, 1)
        XCTAssertEqual(service.reads.count, 2)
    }

    func testAccountSwitchDuringReadbackRejectsOldAccountStatus() async throws {
        let service = ControlledRegistrationService()
        let coordinator = try makeCoordinator(service)
        try await loadQuote(coordinator, service)
        try await create(coordinator, service)
        let task = Task { await coordinator.readKnownStatus() }
        await service.waitFor(.read, count: 1)
        try coordinator.setAccount(id: 2, token: "fixture-other-token")
        service.completeRead(0, .success(try snapshot()))
        let action = await task.value
        XCTAssertEqual(action, .ignoredStale)
        XCTAssertEqual(coordinator.readbackState, .idle)
        XCTAssertNil(coordinator.retainedIntent)
        try coordinator.setAccount(id: 1, token: "fixture-new-token")
        XCTAssertEqual(coordinator.readbackState, .idle)
        let newTask = Task { await coordinator.readKnownStatus() }
        await service.waitFor(.read, count: 2)
        XCTAssertEqual(service.reads[1].token, "fixture-new-token")
        service.completeRead(1, .success(try snapshot()))
        _ = await newTask.value
        XCTAssertEqual(coordinator.readbackState, .received(try snapshot()))
    }

    func testCancelledReadbackIgnoresLateCompletionWithoutResettingIntent() async throws {
        let service = ControlledRegistrationService()
        let coordinator = try makeCoordinator(service)
        try await loadQuote(coordinator, service)
        try await create(coordinator, service)
        let retained = coordinator.retainedIntent
        let task = Task { await coordinator.readKnownStatus() }
        await service.waitFor(.read, count: 1)
        coordinator.cancelPendingOperations()
        service.completeRead(0, .success(try snapshot()))
        let action = await task.value
        XCTAssertEqual(action, .ignoredStale)
        XCTAssertEqual(coordinator.readbackState, .unavailable(registrationID: 41, issue: .cancelled))
        XCTAssertEqual(coordinator.retainedIntent, retained)
        XCTAssertEqual(service.creates.count, 1)
    }

    func testCancelledQuoteCannotEnableConfirmation() async throws {
        let service = ControlledRegistrationService()
        let coordinator = try makeCoordinator(service)
        let task = Task { await coordinator.requestQuote() }
        await service.waitFor(.quote, count: 1)
        coordinator.cancelPendingOperations()
        service.completeQuote(0, .success(try quote()))
        let action = await task.value
        XCTAssertEqual(action, .ignoredStale)
        XCTAssertEqual(coordinator.quoteState, .idle)
        XCTAssertFalse(coordinator.canConfirm)
    }
}

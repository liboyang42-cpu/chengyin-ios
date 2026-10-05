#if DEBUG
import Foundation
import XCTest
@testable import QuestifyCore

@MainActor private final class WaitlistFlowFixture: RegistrationCoordinatingService, RegistrationWaitlistServing {
    var statusValue: RegistrationWaitlistStatus!
    var failMutation = false
    var statuses = 0
    var joins = 0
    var cancellations = 0
    var selections: [RegistrationQuoteRequest] = []
    var creates: [RegistrationCreateIntent] = []
    var statusContinuation: CheckedContinuation<RegistrationWaitlistStatus, Error>?
    private var statusWaiter: CheckedContinuation<Void, Never>?
    var suspendStatus = false
    func status(_ scope: RegistrationWaitlistScope) async throws -> RegistrationWaitlistStatus {
        statuses += 1
        if suspendStatus {
            return try await withCheckedThrowingContinuation {
                statusContinuation = $0; statusWaiter?.resume(); statusWaiter = nil
            }
        }
        return statusValue
    }
    func waitForSuspendedStatus() async {
        if statusContinuation != nil { return }
        await withCheckedContinuation { statusWaiter = $0 }
    }
    func join(_ scope: RegistrationWaitlistScope) async throws -> RegistrationWaitlistStatus {
        joins += 1; if failMutation { throw URLError(.timedOut) }; return statusValue
    }
    func cancel(_ scope: RegistrationWaitlistScope) async throws -> RegistrationWaitlistStatus {
        cancellations += 1; if failMutation { throw URLError(.timedOut) }; return statusValue
    }
    func quote(_ selection: RegistrationQuoteRequest, token: String) async throws -> RegistrationQuote {
        selections.append(selection)
        return try JSONDecoder().decode(RegistrationQuote.self, from: Data(#"{"payAmount":0,"quoteSign":"fixture-quote"}"#.utf8))
    }
    func create(_ intent: RegistrationCreateIntent, token: String) async throws -> RegistrationCreateResult {
        creates.append(intent)
        return try JSONDecoder().decode(RegistrationCreateResult.self, from: Data(#"{"registrationId":41,"payableAmount":0}"#.utf8))
    }
    func readStatus(registrationID: Int, token: String) async throws -> RegistrationStatusSnapshot {
        throw APIError.notConfigured
    }
}

@MainActor final class RegistrationWaitlistFlowTests: XCTestCase {
    private let expiry = ISO8601DateFormatter().date(from: "2030-10-02T04:00:00Z")!
    private func status(_ state: String = "OFFERED", ticket: Int = 11) throws -> RegistrationWaitlistStatus {
        let extra = state == "OFFERED" ? ",\"offerToken\":\"fixture-offer\",\"offerExpiresAt\":\"2030-10-02 12:00:00\"" : ""
        return try JSONDecoder().decode(RegistrationWaitlistStatus.self, from: Data("{\"id\":5,\"activityId\":7,\"ticketId\":\(ticket),\"memberId\":1,\"state\":\"\(state)\",\"eligibilityState\":\"ELIGIBLE\",\"waitlistJoinAllowed\":true\(extra)}".utf8))
    }
    private func activity() throws -> ActivityDetail {
        try JSONDecoder().decode(ActivityDetail.self, from: Data(#"{"id":7,"name":"Fixture activity","omsTicketList":[{"id":11,"name":"Sold out","remainingInventory":0},{"id":12,"name":"Other","remainingInventory":5}]}"#.utf8))
    }
    private func coordinator(_ service: WaitlistFlowFixture) throws -> RegistrationCoordinator {
        let coordinator = RegistrationCoordinator(service: service)
        try coordinator.setAccount(id: 1, token: "fixture-token"); return coordinator
    }
    private func ready(_ flow: RegistrationUIFlow) {
        flow.open(); flow.setName("Fixture Person"); flow.setPhone("13800000000")
    }
    func testOnlyCurrentScopedOfferBypassesClosedTicketWindow() async throws {
        let service = WaitlistFlowFixture(); service.statusValue = try status()
        var clock = expiry.addingTimeInterval(-3600)
        let detail = try JSONDecoder().decode(ActivityDetail.self, from: Data(#"{"id":7,"name":"Fixture","omsTicketList":[{"id":11,"name":"Closed","startTime":"2020-01-01 00:00:00","remainingInventory":0},{"id":12,"name":"Other closed","startTime":"2020-01-01 00:00:00"}]}"#.utf8))
        let flow = try RegistrationUIFlow(activity: detail, coordinator: coordinator(service), currentIdentity: { .init(accountID: 1, epoch: 1) }, quoteEnabled: true, creationPolicy: .offlineFixture, waitlistService: service, now: { clock })
        ready(flow); await flow.requestQuote(); flow.setConsent(true)
        XCTAssertEqual(flow.confirmationBlock, .signupClosed)
        await flow.reviewWaitlistOffer(); flow.setConsent(true)
        XCTAssertFalse(flow.signupClosed); XCTAssertTrue(flow.prepareConfirmation())
        clock = expiry
        await flow.confirm(); XCTAssertEqual(flow.block, .signupClosed); XCTAssertTrue(service.creates.isEmpty)
        clock = expiry.addingTimeInterval(-3600)
        await flow.reviewWaitlistOffer(); flow.setConsent(true)
        XCTAssertTrue(flow.prepareConfirmation())
        XCTAssertTrue(flow.selectTicket(id: 12))
        XCTAssertTrue(flow.signupClosed); XCTAssertNil(flow.confirmation)
        await flow.confirm(); XCTAssertTrue(service.creates.isEmpty)
    }
    func testOfferStaysOnSameFormRequiresFreshQuoteAndCarriesExactPair() async throws {
        let service = WaitlistFlowFixture(); service.statusValue = try status()
        let coordinator = try coordinator(service)
        let flow = try RegistrationUIFlow(activity: activity(), coordinator: coordinator, currentIdentity: { .init(accountID: 1, epoch: 1) }, quoteEnabled: true, creationPolicy: .offlineFixture, waitlistService: service, now: { self.expiry.addingTimeInterval(-3600) })
        ready(flow); await flow.loadWaitlist(); await flow.requestQuote(); flow.setConsent(true)
        XCTAssertEqual(flow.confirmationBlock, .soldOut)
        await flow.reviewWaitlistOffer()
        XCTAssertEqual(flow.draft.trimmedName, "Fixture Person")
        XCTAssertFalse(flow.consented); XCTAssertTrue(flow.hasActiveWaitlistOffer)
        XCTAssertEqual(service.selections.last?.waitlistOffer?.id, 5)
        flow.setConsent(true); XCTAssertTrue(flow.prepareConfirmation()); await flow.confirm()
        XCTAssertEqual(service.creates.count, 1)
        XCTAssertEqual(service.creates.first?.waitlistOffer, service.selections.last?.waitlistOffer)
        XCTAssertEqual(service.creates.first?.waitlistOffer?.token, "fixture-offer")
        if case .responseReceived = flow.creationState {} else { XCTFail("Only a create receipt is expected") }
    }
    func testExpiryBetweenReviewAndConfirmDoesNotDispatchCreate() async throws {
        let service = WaitlistFlowFixture(); service.statusValue = try status(); var now = expiry.addingTimeInterval(-1)
        let flow = try RegistrationUIFlow(activity: activity(), coordinator: coordinator(service), currentIdentity: { .init(accountID: 1, epoch: 1) }, quoteEnabled: true, creationPolicy: .offlineFixture, waitlistService: service, now: { now })
        ready(flow); await flow.reviewWaitlistOffer(); flow.setConsent(true); XCTAssertTrue(flow.prepareConfirmation())
        now = expiry; await flow.confirm()
        XCTAssertTrue(service.creates.isEmpty); XCTAssertNil(flow.confirmation)
        flow.checkWaitlistDeadline(); XCTAssertNil(flow.activeWaitlistOffer)
    }
    func testTicketChangeClearsOfferConsentAndQuoteWithoutNameMatching() async throws {
        let service = WaitlistFlowFixture(); service.statusValue = try status()
        let flow = try RegistrationUIFlow(activity: activity(), coordinator: coordinator(service), currentIdentity: { .init(accountID: 1, epoch: 1) }, quoteEnabled: true, creationPolicy: .offlineFixture, waitlistService: service, now: { self.expiry.addingTimeInterval(-3600) })
        ready(flow); await flow.reviewWaitlistOffer(); flow.setConsent(true)
        XCTAssertTrue(flow.selectTicket(id: 12)); XCTAssertNil(flow.activeWaitlistOffer)
        XCTAssertNil(flow.waitlistStatus); XCTAssertFalse(flow.consented); XCTAssertEqual(flow.quoteState, .idle)
        await flow.requestQuote(); XCTAssertNil(service.selections.last?.waitlistOffer)
    }
    func testUnknownMutationBlocksRepeatAndRegistrationUntilExplicitRead() async throws {
        let service = WaitlistFlowFixture(); service.statusValue = try status("WAITING"); service.failMutation = true
        let flow = try RegistrationUIFlow(activity: activity(), coordinator: coordinator(service), currentIdentity: { .init(accountID: 1, epoch: 1) }, quoteEnabled: true, creationPolicy: .offlineFixture, waitlistService: service)
        ready(flow); await flow.loadWaitlist(); XCTAssertTrue(flow.prepareWaitlistCancellation()); await flow.cancelWaitlist()
        XCTAssertTrue(flow.waitlistOutcomeUnknown); XCTAssertFalse(flow.canCancelWaitlist)
        await flow.cancelWaitlist(); XCTAssertEqual(service.cancellations, 1)
        XCTAssertEqual(flow.confirmationBlock, .waitlistUnavailable)
        service.failMutation = false; service.statusValue = try status("CANCELLED")
        await flow.loadWaitlist(); XCTAssertFalse(flow.waitlistOutcomeUnknown)
        XCTAssertEqual(flow.waitlistStatus?.state, .cancelled)
    }
    func testCancelReviewAndLeaveDoNotCreateCancelQueueOrPay() async throws {
        let service = WaitlistFlowFixture(); service.statusValue = try status()
        let flow = try RegistrationUIFlow(activity: activity(), coordinator: coordinator(service), currentIdentity: { .init(accountID: 1, epoch: 1) }, quoteEnabled: true, creationPolicy: .offlineFixture, waitlistService: service, now: { self.expiry.addingTimeInterval(-3600) })
        ready(flow); await flow.reviewWaitlistOffer(); flow.setConsent(true); XCTAssertTrue(flow.prepareConfirmation())
        flow.cancelConfirmation(); flow.leave()
        XCTAssertTrue(service.creates.isEmpty); XCTAssertEqual(service.cancellations, 0)
        XCTAssertNil(flow.activeWaitlistOffer); XCTAssertTrue(flow.draft.realName.isEmpty)
    }
    func testWrongTicketStatusCannotInjectAnOfferOrLeaveSpinnerRunning() async throws {
        let service = WaitlistFlowFixture(); service.statusValue = try status(ticket: 12)
        let flow = try RegistrationUIFlow(activity: activity(), coordinator: coordinator(service), currentIdentity: { .init(accountID: 1, epoch: 1) }, quoteEnabled: true, creationPolicy: .offlineFixture, waitlistService: service)
        ready(flow); await flow.loadWaitlist()
        XCTAssertNil(flow.waitlistStatus); XCTAssertNil(flow.activeWaitlistOffer)
        XCTAssertFalse(flow.isReadingWaitlist); XCTAssertEqual(flow.block, .waitlistUnavailable)
    }
    func testSignoutDropsOfferAndPreventCreateEvenWithoutAnExplicitUIReset() async throws {
        let service = WaitlistFlowFixture(); service.statusValue = try status()
        var identity: ProfileReadIdentity? = .init(accountID: 1, epoch: 1)
        let coordinator = try coordinator(service)
        let flow = try RegistrationUIFlow(activity: activity(), coordinator: coordinator, currentIdentity: { identity }, quoteEnabled: true, creationPolicy: .offlineFixture, waitlistService: service, now: { self.expiry.addingTimeInterval(-3600) })
        ready(flow); await flow.reviewWaitlistOffer(); flow.setConsent(true); XCTAssertTrue(flow.prepareConfirmation())
        identity = nil; coordinator.clearAccount(); await flow.confirm()
        XCTAssertTrue(service.creates.isEmpty); XCTAssertEqual(flow.confirmationBlock, .sessionChanged)
        flow.open(); XCTAssertNil(flow.waitlistStatus)
    }
    func testReadTaskKeyTracksOpenedSessionEvenWhenTheTicketIsUnchanged() async throws {
        let service = WaitlistFlowFixture(); service.statusValue = try status()
        var identity: ProfileReadIdentity? = .init(accountID: 1, epoch: 1)
        let coordinator = try coordinator(service)
        let flow = try RegistrationUIFlow(activity: activity(), coordinator: coordinator, currentIdentity: { identity },
            quoteEnabled: true, creationPolicy: .offlineFixture, waitlistService: service,
            now: { self.expiry.addingTimeInterval(-3600) })
        XCTAssertNil(flow.waitlistReadKey)
        ready(flow)
        let originalKey = try XCTUnwrap(flow.waitlistReadKey)
        await flow.reviewWaitlistOffer()
        XCTAssertTrue(flow.hasActiveWaitlistOffer)
        let readCount = service.statuses
        identity = .init(accountID: 1, epoch: 2)
        try coordinator.setAccount(id: 1, token: "fixture-replaced-token")
        XCTAssertNil(flow.waitlistReadKey, "A replaced external identity must not launch a read using the old opened form")
        flow.open()
        XCTAssertEqual(flow.selectedTicketID, 11)
        XCTAssertNotEqual(flow.waitlistReadKey, originalKey, "The task must restart even though ticket ID 11 is unchanged")
        XCTAssertNil(flow.waitlistStatus); XCTAssertNil(flow.activeWaitlistOffer)
        XCTAssertNil(flow.confirmation); XCTAssertFalse(flow.consented)
        XCTAssertEqual(flow.quoteState, .idle)
        XCTAssertEqual(service.statuses, readCount, "Computing the key and opening the form perform no request")
        await flow.loadWaitlist() // The view's keyed task performs this read only.
        XCTAssertEqual(service.statuses, readCount + 1)
        XCTAssertEqual(flow.waitlistStatus?.state, .offered)
        XCTAssertNil(flow.activeWaitlistOffer, "Reading an offer must not select or reuse it")
        XCTAssertEqual(service.joins, 0); XCTAssertEqual(service.cancellations, 0); XCTAssertTrue(service.creates.isEmpty)
    }
    func testReadTaskKeyChangesForTicketAndClearsOnLeaveButNotContactOrPoints() throws {
        let service = WaitlistFlowFixture()
        let flow = try RegistrationUIFlow(activity: activity(), coordinator: coordinator(service),
            currentIdentity: { .init(accountID: 1, epoch: 1) }, creationPolicy: .offlineFixture, waitlistService: service)
        ready(flow)
        let originalKey = try XCTUnwrap(flow.waitlistReadKey)
        flow.setName("Edited fixture contact"); XCTAssertTrue(flow.setUsePoints(true))
        XCTAssertEqual(flow.waitlistReadKey, originalKey)
        XCTAssertTrue(flow.selectTicket(id: 12)); XCTAssertNotEqual(flow.waitlistReadKey, originalKey)
        flow.leave(); XCTAssertNil(flow.waitlistReadKey)
        XCTAssertEqual(service.statuses, 0); XCTAssertEqual(service.joins, 0)
        XCTAssertEqual(service.cancellations, 0); XCTAssertTrue(service.creates.isEmpty)
    }

    func testCanceledSuccessfulReadClearsOnlyItsSpinnerAndAllowsExplicitRefresh() async throws {
        let service = WaitlistFlowFixture(); service.suspendStatus = true
        let flow = try RegistrationUIFlow(activity: activity(), coordinator: coordinator(service),
            currentIdentity: { .init(accountID: 1, epoch: 1) }, creationPolicy: .offlineFixture, waitlistService: service)
        ready(flow)
        let originalKey = flow.waitlistReadKey
        let read = Task { await flow.loadWaitlist() }
        await service.waitForSuspendedStatus()
        XCTAssertTrue(flow.isReadingWaitlist)
        read.cancel()
        service.statusContinuation?.resume(returning: try status()); service.statusContinuation = nil
        await read.value
        XCTAssertEqual(flow.waitlistReadKey, originalKey)
        XCTAssertFalse(flow.isReadingWaitlist, "Canceled same-key success must not strand manual refresh")
        XCTAssertNil(flow.waitlistStatus); XCTAssertNil(flow.activeWaitlistOffer); XCTAssertNil(flow.block)
        service.suspendStatus = false; service.statusValue = try status("WAITING")
        await flow.loadWaitlist()
        XCTAssertEqual(service.statuses, 2); XCTAssertEqual(flow.waitlistStatus?.state, .waiting)
        XCTAssertEqual(service.joins, 0); XCTAssertEqual(service.cancellations, 0); XCTAssertTrue(service.creates.isEmpty)
    }
    func testCanceledThrowingReadPreservesPriorStatusAndClearsItsSpinner() async throws {
        let service = WaitlistFlowFixture(); service.statusValue = try status("WAITING")
        let flow = try RegistrationUIFlow(activity: activity(), coordinator: coordinator(service),
            currentIdentity: { .init(accountID: 1, epoch: 1) }, creationPolicy: .offlineFixture, waitlistService: service)
        ready(flow); await flow.loadWaitlist()
        let originalStatus = flow.waitlistStatus
        service.suspendStatus = true
        let read = Task { await flow.loadWaitlist() }
        await service.waitForSuspendedStatus(); read.cancel()
        service.statusContinuation?.resume(throwing: CancellationError()); service.statusContinuation = nil
        await read.value
        XCTAssertFalse(flow.isReadingWaitlist); XCTAssertEqual(flow.waitlistStatus, originalStatus)
        XCTAssertNil(flow.activeWaitlistOffer); XCTAssertNil(flow.block)
        XCTAssertEqual(service.joins, 0); XCTAssertEqual(service.cancellations, 0); XCTAssertTrue(service.creates.isEmpty)
    }
    func testCanceledOlderGenerationCannotClearANewerSameKeyReadSpinner() async throws {
        let service = WaitlistFlowFixture(); service.suspendStatus = true
        let flow = try RegistrationUIFlow(activity: activity(), coordinator: coordinator(service),
            currentIdentity: { .init(accountID: 1, epoch: 1) }, creationPolicy: .offlineFixture, waitlistService: service)
        ready(flow)
        let originalKey = flow.waitlistReadKey
        let oldRead = Task { await flow.loadWaitlist() }
        await service.waitForSuspendedStatus()
        let oldContinuation = try XCTUnwrap(service.statusContinuation); service.statusContinuation = nil
        flow.open()
        XCTAssertEqual(flow.waitlistReadKey, originalKey)
        let newRead = Task { await flow.loadWaitlist() }
        await service.waitForSuspendedStatus()
        oldRead.cancel(); oldContinuation.resume(returning: try status()); await oldRead.value
        XCTAssertTrue(flow.isReadingWaitlist, "The older generation must not finish the new read")
        XCTAssertNil(flow.waitlistStatus); XCTAssertNil(flow.activeWaitlistOffer)
        service.statusContinuation?.resume(returning: try status("WAITING")); service.statusContinuation = nil
        await newRead.value
        XCTAssertFalse(flow.isReadingWaitlist); XCTAssertEqual(flow.waitlistStatus?.state, .waiting)
        XCTAssertEqual(service.statuses, 2)
    }
    func testCanceledOlderTicketReadCannotClearNewerStampSpinner() async throws {
        let service = WaitlistFlowFixture(); service.suspendStatus = true
        let flow = try RegistrationUIFlow(activity: activity(), coordinator: coordinator(service),
            currentIdentity: { .init(accountID: 1, epoch: 1) }, creationPolicy: .offlineFixture, waitlistService: service)
        ready(flow)
        let oldRead = Task { await flow.loadWaitlist() }
        await service.waitForSuspendedStatus()
        let oldContinuation = try XCTUnwrap(service.statusContinuation); service.statusContinuation = nil
        XCTAssertTrue(flow.selectTicket(id: 12))
        let newRead = Task { await flow.loadWaitlist() }
        await service.waitForSuspendedStatus()
        oldRead.cancel(); oldContinuation.resume(returning: try status()); await oldRead.value
        XCTAssertTrue(flow.isReadingWaitlist, "A different ticket read owns the current spinner")
        XCTAssertNil(flow.waitlistStatus); XCTAssertNil(flow.activeWaitlistOffer)
        service.statusContinuation?.resume(returning: try status("WAITING", ticket: 12)); service.statusContinuation = nil
        await newRead.value
        XCTAssertFalse(flow.isReadingWaitlist); XCTAssertEqual(flow.waitlistStatus?.ticketID, 12)
        XCTAssertEqual(service.joins, 0); XCTAssertEqual(service.cancellations, 0); XCTAssertTrue(service.creates.isEmpty)
    }

    func testWaitlistCancellationRequiresReviewAndDismissalDoesNotWrite() async throws {
        let service = WaitlistFlowFixture(); service.statusValue = try status("WAITING")
        let flow = try RegistrationUIFlow(activity: activity(), coordinator: coordinator(service), currentIdentity: { .init(accountID: 1, epoch: 1) }, waitlistService: service)
        ready(flow); await flow.loadWaitlist(); await flow.cancelWaitlist()
        XCTAssertEqual(service.cancellations, 0)
        XCTAssertTrue(flow.prepareWaitlistCancellation()); flow.dismissWaitlistCancellation()
        await flow.cancelWaitlist(); XCTAssertEqual(service.cancellations, 0)
        XCTAssertTrue(flow.prepareWaitlistCancellation()); await flow.cancelWaitlist()
        XCTAssertEqual(service.cancellations, 1); XCTAssertEqual(service.statuses, 2)
        await flow.cancelWaitlist(); XCTAssertEqual(service.cancellations, 1)
    }
    func testCancellationRefreshTicketAndLeaveInvalidateReview() async throws {
        let service = WaitlistFlowFixture(); service.statusValue = try status("WAITING")
        let flow = try RegistrationUIFlow(activity: activity(), coordinator: coordinator(service), currentIdentity: { .init(accountID: 1, epoch: 1) }, waitlistService: service)
        ready(flow); await flow.loadWaitlist(); XCTAssertTrue(flow.prepareWaitlistCancellation())
        await flow.loadWaitlist(); XCTAssertNil(flow.waitlistCancellation); await flow.cancelWaitlist()
        XCTAssertTrue(flow.prepareWaitlistCancellation()); XCTAssertTrue(flow.selectTicket(id: 12))
        XCTAssertNil(flow.waitlistCancellation); await flow.cancelWaitlist()
        flow.open(); await flow.loadWaitlist(); XCTAssertTrue(flow.prepareWaitlistCancellation())
        flow.leave(); XCTAssertNil(flow.waitlistCancellation); await flow.cancelWaitlist(); XCTAssertEqual(service.cancellations, 0)
    }
    func testCancellationEpochChangeAndOfferExpiryDoNotWrite() async throws {
        let service = WaitlistFlowFixture(); service.statusValue = try status()
        var clock = expiry.addingTimeInterval(-1)
        var identity: ProfileReadIdentity? = .init(accountID: 1, epoch: 1)
        let flow = try RegistrationUIFlow(activity: activity(), coordinator: coordinator(service), currentIdentity: { identity }, waitlistService: service, now: { clock })
        ready(flow); await flow.loadWaitlist(); XCTAssertTrue(flow.prepareWaitlistCancellation())
        identity = .init(accountID: 1, epoch: 2); await flow.cancelWaitlist()
        XCTAssertEqual(service.cancellations, 0)
        flow.open(); await flow.loadWaitlist(); XCTAssertTrue(flow.prepareWaitlistCancellation())
        clock = expiry; await flow.cancelWaitlist(); XCTAssertEqual(service.cancellations, 0)
        XCTAssertFalse(flow.prepareWaitlistCancellation())
    }
    func testCancellationFreshReadChangedOfferRequiresNewReview() async throws {
        let service = WaitlistFlowFixture(); service.statusValue = try status("WAITING")
        let flow = try RegistrationUIFlow(activity: activity(), coordinator: coordinator(service), currentIdentity: { .init(accountID: 1, epoch: 1) }, waitlistService: service, now: { self.expiry.addingTimeInterval(-1) })
        ready(flow); await flow.loadWaitlist(); XCTAssertTrue(flow.prepareWaitlistCancellation())
        service.statusValue = try status(); await flow.cancelWaitlist()
        XCTAssertEqual(service.cancellations, 0); XCTAssertEqual(flow.block, .confirmationChanged)
        XCTAssertNil(flow.waitlistCancellation); XCTAssertEqual(flow.waitlistStatus?.state, .offered)
        XCTAssertFalse(flow.isReadingWaitlist)
    }
    func testCancellationReadInterruptedOrWrongScopeNeverWrites() async throws {
        let service = WaitlistFlowFixture(); service.statusValue = try status("WAITING")
        let flow = try RegistrationUIFlow(activity: activity(), coordinator: coordinator(service), currentIdentity: { .init(accountID: 1, epoch: 1) }, waitlistService: service)
        ready(flow); await flow.loadWaitlist(); XCTAssertTrue(flow.prepareWaitlistCancellation())
        service.suspendStatus = true
        let task = Task { await flow.cancelWaitlist() }
        await service.waitForSuspendedStatus(); task.cancel()
        service.statusContinuation?.resume(returning: try status("WAITING")); service.statusContinuation = nil
        await task.value
        XCTAssertFalse(flow.isReadingWaitlist); XCTAssertEqual(service.cancellations, 0)
        service.suspendStatus = false; XCTAssertTrue(flow.prepareWaitlistCancellation())
        service.statusValue = try status("WAITING", ticket: 12); await flow.cancelWaitlist()
        XCTAssertEqual(service.cancellations, 0); XCTAssertEqual(flow.block, .waitlistUnavailable)
    }

    func testOpeningWithoutSessionOrWithRetainedIntentClearsCancellationImmediately() async throws {
        let service = WaitlistFlowFixture(); service.statusValue = try status("WAITING")
        var identity: ProfileReadIdentity? = .init(accountID: 1, epoch: 1)
        let coordinator = try coordinator(service)
        let flow = try RegistrationUIFlow(activity: activity(), coordinator: coordinator, currentIdentity: { identity }, waitlistService: service)
        ready(flow); await flow.loadWaitlist(); XCTAssertTrue(flow.prepareWaitlistCancellation())
        identity = nil; flow.open(); XCTAssertNil(flow.waitlistCancellation)
        identity = .init(accountID: 1, epoch: 1)
        ready(flow); await flow.loadWaitlist(); XCTAssertTrue(flow.prepareWaitlistCancellation())
        _ = await coordinator.requestQuote()
        _ = await coordinator.confirm(.init(realName: "Fixture", phone: "13800000000"))
        XCTAssertNotNil(coordinator.retainedIntent)
        flow.open(); XCTAssertTrue(flow.hasRetainedIntent); XCTAssertNil(flow.waitlistCancellation)
        XCTAssertEqual(service.cancellations, 0)
    }

    func testPendingCancellationReadFencesEpochTicketLeaveAndDoubleConfirm() async throws {
        for change in ["epoch", "ticket", "leave", "double"] {
            let service = WaitlistFlowFixture(); service.statusValue = try status("WAITING")
            var identity: ProfileReadIdentity? = .init(accountID: 1, epoch: 1)
            let flow = try RegistrationUIFlow(activity: activity(), coordinator: coordinator(service), currentIdentity: { identity }, waitlistService: service)
            ready(flow); await flow.loadWaitlist(); XCTAssertTrue(flow.prepareWaitlistCancellation())
            service.suspendStatus = true
            let task = Task { await flow.cancelWaitlist() }
            await service.waitForSuspendedStatus()
            XCTAssertNil(flow.waitlistCancellation)
            switch change {
            case "epoch": identity = .init(accountID: 1, epoch: 2)
            case "ticket": XCTAssertTrue(flow.selectTicket(id: 12))
            case "leave": flow.leave(); XCTAssertNil(flow.waitlistCancellation)
            default: await flow.cancelWaitlist(); XCTAssertEqual(service.statuses, 2)
            }
            service.statusContinuation?.resume(returning: try status("WAITING")); service.statusContinuation = nil
            await task.value
            XCTAssertEqual(service.cancellations, change == "double" ? 1 : 0)
            XCTAssertTrue(service.creates.isEmpty); XCTAssertEqual(service.joins, 0)
        }
    }

}
#endif

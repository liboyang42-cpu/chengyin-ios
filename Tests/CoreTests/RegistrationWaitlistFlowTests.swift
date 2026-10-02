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
    var suspendStatus = false
    func status(_ scope: RegistrationWaitlistScope) async throws -> RegistrationWaitlistStatus {
        statuses += 1
        if suspendStatus { return try await withCheckedThrowingContinuation { statusContinuation = $0 } }
        return statusValue
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
        ready(flow); await flow.loadWaitlist(); await flow.cancelWaitlist()
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
}
#endif

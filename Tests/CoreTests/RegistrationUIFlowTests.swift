#if DEBUG
import Foundation
import XCTest
@testable import QuestifyCore

@MainActor
private final class UIRegistrationService: RegistrationCoordinatingService {
    var quoteJSON = #"{"payAmount":12.5,"pointsUsable":true,"quoteSign":"fixture-sign"}"#
    var createJSON = #"{"registrationId":41,"payableAmount":0}"#
    var statusJSON = #"{"id":41,"registrationStatus":3,"paymentStatus":2}"#
    var createError: Error?
    var suspendCreate = false
    private(set) var quotes: [RegistrationQuoteRequest] = []
    private(set) var creates: [RegistrationCreateIntent] = []
    private(set) var reads: [Int] = []
    var createContinuation: CheckedContinuation<RegistrationCreateResult, Error>?
    private var createWaiter: CheckedContinuation<Void, Never>?
    func quote(_ selection: RegistrationQuoteRequest, token: String) async throws -> RegistrationQuote {
        quotes.append(selection)
        return try JSONDecoder().decode(RegistrationQuote.self, from: Data(quoteJSON.utf8))
    }
    func create(_ intent: RegistrationCreateIntent, token: String) async throws -> RegistrationCreateResult {
        creates.append(intent)
        if suspendCreate {
            return try await withCheckedThrowingContinuation {
                createContinuation = $0; createWaiter?.resume(); createWaiter = nil
            }
        }
        if let createError { throw createError }
        return try JSONDecoder().decode(RegistrationCreateResult.self, from: Data(createJSON.utf8))
    }
    func readStatus(registrationID: Int, token: String) async throws -> RegistrationStatusSnapshot {
        reads.append(registrationID)
        return try JSONDecoder().decode(RegistrationStatusSnapshot.self, from: Data(statusJSON.utf8))
    }
    func waitForCreate() async {
        if createContinuation != nil { return }
        await withCheckedContinuation { createWaiter = $0 }
    }
}

@MainActor
private final class UIRegistrationParticipants: ProfileReading {
    var identity: ProfileReadIdentity? = .init(accountID: 1, epoch: 1)
    var isConfigured = true
    var rows: [ProfileParticipant] = []
    var fail = false
    var suspend = false
    var continuation: CheckedContinuation<[ProfileParticipant], Error>?
    private var waiter: CheckedContinuation<Void, Never>?
    func profileParticipants() async throws -> [ProfileParticipant] {
        if suspend { return try await withCheckedThrowingContinuation { continuation = $0; waiter?.resume(); waiter = nil } }
        if fail { throw APIError.httpStatus(503) }
        return rows
    }
    func waitForRead() async {
        if continuation != nil { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func profileParticipant(id: Int) async throws -> ProfileParticipant { guard let row = rows.first(where: { $0.id == id }) else { throw APIError.invalidRequest }; return row }
    func profileOrders() async throws -> [ProfileOrder] { [] }
    func profileOrder(id: Int) async throws -> ProfileOrder { throw APIError.invalidRequest }
    func profileBadges() async throws -> ProfileBadgeWall { .init(identities: [], medals: []) }
}

@MainActor
final class RegistrationUIFlowTests: XCTestCase {
    private func makeActivity(tickets: String = #"[{"id":11,"name":"First","price":12.5,"remainingInventory":4},{"id":12,"name":"Second","price":null,"remainingInventory":null}]"#,
                          id: Int = 7) throws -> ActivityDetail {
        try JSONDecoder().decode(ActivityDetail.self, from: Data("{\"id\":\(id),\"name\":\"Fixture activity\",\"omsTicketList\":\(tickets)}".utf8))
    }
    private func makeCoordinator(_ service: UIRegistrationService) throws -> RegistrationCoordinator {
        let result = RegistrationCoordinator(service: service, makeRequestID: { "fixture-ui-intent" })
        try result.setAccount(id: 1, token: "fixture-only-token")
        return result
    }
    private func makeFlow(_ service: UIRegistrationService, reader: UIRegistrationParticipants,
                      policy: RegistrationUICreationPolicy = .offlineFixture,
                      detail: ActivityDetail? = nil, quoteEnabled: Bool = true) throws -> RegistrationUIFlow {
        try RegistrationUIFlow(activity: detail ?? makeActivity(), coordinator: makeCoordinator(service),
                               participantReader: reader, currentIdentity: { reader.identity },
                               quoteEnabled: quoteEnabled, creationPolicy: policy)
    }
    private func ready(_ flow: RegistrationUIFlow) async {
        flow.open(); flow.setName("Fixture Person"); flow.setPhone("13800000000")
        flow.setConsent(true); await flow.requestQuote()
    }
    private func makeParticipants() throws -> [ProfileParticipant] {
        try JSONDecoder().decode([ProfileParticipant].self, from: Data(#"[{"id":1,"fullName":"First","mobilePhone":"13800000000"},{"id":2,"fullName":"Preferred","mobilePhone":"13900000000","isDefault":true}]"#.utf8))
    }
    func testAcknowledgedCreateReturnsAndSelectsOnlyReadbackID() async throws {
        let service = UIRegistrationService(), reader = UIRegistrationParticipants()
        reader.rows = try makeParticipants()
        let flow = try makeFlow(service, reader: reader)
        flow.open(); await flow.loadParticipants()
        XCTAssertEqual(flow.selectedParticipantID, 2)
        let row = reader.rows[0]
        await flow.selectCreatedParticipant(row, identity: .init(accountID: 1, epoch: 1))
        XCTAssertEqual(flow.selectedParticipantID, row.id)
        XCTAssertEqual(flow.draft.realName, row.fullName)
        XCTAssertEqual(flow.draft.phone, row.mobilePhone)
        XCTAssertNil(flow.confirmation)
        XCTAssertTrue(service.creates.isEmpty)
    }
    func testCreatedParticipantFencesEarlierParticipantList() async throws {
        let service = UIRegistrationService(), reader = UIRegistrationParticipants()
        reader.rows = try makeParticipants(); reader.suspend = true
        let flow = try makeFlow(service, reader: reader)
        flow.open()
        let initialList = Task { await flow.loadParticipants() }
        await reader.waitForRead()
        let receipt = reader.rows[0]
        await flow.selectCreatedParticipant(receipt, identity: .init(accountID: 1, epoch: 1))
        reader.continuation?.resume(returning: []); reader.continuation = nil
        await initialList.value
        XCTAssertEqual(flow.selectedParticipantID, receipt.id)
        XCTAssertEqual(flow.participants, [receipt])
        XCTAssertEqual(flow.participantsState, .received)
    }
    func testCreatedParticipantCannotCrossSessionOrSelectAbsentID() async throws {
        let service = UIRegistrationService(), reader = UIRegistrationParticipants()
        let receipt = try makeParticipants()[0]
        let flow = try makeFlow(service, reader: reader)
        flow.open()
        await flow.selectCreatedParticipant(receipt, identity: .init(accountID: 1, epoch: 1))
        XCTAssertNil(flow.selectedParticipantID)
        reader.rows = [receipt]; reader.identity = .init(accountID: 1, epoch: 2)
        await flow.selectCreatedParticipant(receipt, identity: .init(accountID: 1, epoch: 1))
        XCTAssertNil(flow.selectedParticipantID)
        XCTAssertTrue(flow.draft.realName.isEmpty)
    }
    func testProductionPolicyCannotCreateEvenWithUsableQuote() async throws {
        let service = UIRegistrationService(), reader = UIRegistrationParticipants()
        let flow = try makeFlow(service, reader: reader, policy: .disabled)
        await ready(flow)
        XCTAssertEqual(flow.confirmationBlock, .creationDisabled)
        XCTAssertFalse(flow.consented)
        XCTAssertFalse(flow.prepareConfirmation())
        await flow.confirm()
        XCTAssertTrue(service.creates.isEmpty)
        XCTAssertNil(flow.coordinator.retainedIntent)
    }
    func testExplicitQuoteGateAndEmptyTicketsPreserveNilSelection() async throws {
        let service = UIRegistrationService(), reader = UIRegistrationParticipants()
        let flow = try makeFlow(service, reader: reader, detail: makeActivity(tickets: "[]"), quoteEnabled: false)
        flow.open(); await flow.requestQuote()
        XCTAssertEqual(flow.block, .quotingDisabled)
        XCTAssertTrue(service.quotes.isEmpty)
        XCTAssertNil(flow.selectedTicketID)
        XCTAssertNil(flow.coordinator.selection?.ticketID)
        XCTAssertEqual(flow.coordinator.selection?.ownerID, 7)
        XCTAssertFalse(flow.selectTicket(id: 99))
    }
    func testFirstTicketAndPointsChangeInvalidateReviewAndOldQuote() async throws {
        let service = UIRegistrationService(), reader = UIRegistrationParticipants()
        let flow = try makeFlow(service, reader: reader)
        await ready(flow)
        XCTAssertEqual(flow.selectedTicketID, 11)
        XCTAssertTrue(flow.prepareConfirmation())
        XCTAssertTrue(flow.selectTicket(id: 12))
        XCTAssertNil(flow.confirmation)
        XCTAssertEqual(flow.quoteState, .idle)
        XCTAssertFalse(flow.prepareConfirmation())
        await flow.requestQuote()
        XCTAssertEqual(service.quotes.last?.ticketID, 12)
        XCTAssertTrue(flow.setUsePoints(true))
        XCTAssertEqual(flow.quoteState, .idle)
        await flow.requestQuote()
        XCTAssertEqual(service.quotes.last?.usePoints, true)
        XCTAssertFalse(flow.selectTicket(id: 999))
        XCTAssertEqual(flow.selectedTicketID, 12)
    }
    func testPreferredParticipantAutofillsRawValuesButCurrentEditsAreSubmitted() async throws {
        let service = UIRegistrationService(), reader = UIRegistrationParticipants()
        reader.rows = try makeParticipants()
        let flow = try makeFlow(service, reader: reader)
        flow.open(); await flow.loadParticipants()
        XCTAssertEqual(flow.selectedParticipantID, 2)
        XCTAssertEqual(flow.draft.phone, "13900000000")
        flow.selectParticipant(id: 1)
        XCTAssertEqual(flow.draft.phone, "13800000000")
        flow.setName(" Edited Name "); flow.setPhone(" 13700000000 "); flow.setConsent(true)
        await flow.requestQuote()
        XCTAssertTrue(flow.prepareConfirmation())
        await flow.confirm(); await flow.confirm()
        XCTAssertEqual(service.creates.count, 1)
        XCTAssertEqual(service.creates.first?.realName, "Edited Name")
        XCTAssertEqual(service.creates.first?.phone, "13700000000")
        XCTAssertNil(service.creates.first?.email)
        XCTAssertNil(service.creates.first?.participateDate)
        XCTAssertEqual(flow.coordinator.retainedIntent?.requestID, "fixture-ui-intent")
    }
    func testLateDefaultParticipantNeverOverwritesManualEdits() async throws {
        let service = UIRegistrationService(), reader = UIRegistrationParticipants()
        reader.suspend = true
        let flow = try makeFlow(service, reader: reader)
        flow.open()
        let task = Task { await flow.loadParticipants() }
        await reader.waitForRead()
        flow.setName("My edit"); flow.setPhone("13600000000")
        reader.continuation?.resume(returning: try makeParticipants())
        await task.value
        XCTAssertEqual(flow.draft.realName, "My edit")
        XCTAssertEqual(flow.draft.phone, "13600000000")
        XCTAssertNil(flow.selectedParticipantID)
        XCTAssertEqual(flow.participants.count, 2)
    }
    func testParticipantFailureStillAllowsManualContactAndQuote() async throws {
        let service = UIRegistrationService(), reader = UIRegistrationParticipants()
        reader.fail = true
        let flow = try makeFlow(service, reader: reader)
        await ready(flow); await flow.loadParticipants()
        XCTAssertEqual(flow.participantsState, .unavailable)
        XCTAssertTrue(flow.prepareConfirmation())
        XCTAssertEqual(service.quotes.count, 1)
    }
    func testDismissedParticipantReadCannotRefillClearedPII() async throws {
        let service = UIRegistrationService(), reader = UIRegistrationParticipants()
        reader.suspend = true
        let flow = try makeFlow(service, reader: reader)
        flow.open()
        let task = Task { await flow.loadParticipants() }
        await reader.waitForRead(); flow.leave()
        reader.continuation?.resume(returning: try makeParticipants())
        await task.value
        XCTAssertEqual(flow.draft, RegistrationUIFormDraft())
        XCTAssertTrue(flow.participants.isEmpty)
        XCTAssertFalse(flow.hasCurrentSession)
    }
    func testSameAccountNewEpochInvalidatesConfirmationAndHidesState() async throws {
        let service = UIRegistrationService(), reader = UIRegistrationParticipants()
        let flow = try makeFlow(service, reader: reader)
        await ready(flow)
        XCTAssertTrue(flow.prepareConfirmation())
        reader.identity = .init(accountID: 1, epoch: 2)
        try flow.coordinator.setAccount(id: 1, token: "new-fixture-token")
        XCTAssertFalse(flow.hasCurrentSession)
        XCTAssertEqual(flow.quoteState, .idle)
        await flow.confirm()
        XCTAssertTrue(service.creates.isEmpty)
        flow.open()
        XCTAssertEqual(flow.draft, RegistrationUIFormDraft())
        XCTAssertFalse(flow.consented)
    }
    func testMissingConsentAndInvalidPhoneCannotPrepare() async throws {
        let service = UIRegistrationService(), reader = UIRegistrationParticipants()
        let flow = try makeFlow(service, reader: reader)
        await ready(flow); flow.setConsent(false)
        XCTAssertEqual(flow.confirmationBlock, .missingConsent)
        XCTAssertFalse(flow.prepareConfirmation())
        flow.setConsent(true); flow.setPhone("138****0000")
        XCTAssertEqual(flow.confirmationBlock, .invalidForm)
        XCTAssertFalse(flow.prepareConfirmation())
        XCTAssertTrue(service.creates.isEmpty)
    }
    func testIncompleteQuoteAndSoldOutTicketDoNotCreate() async throws {
        let service = UIRegistrationService(), reader = UIRegistrationParticipants()
        service.quoteJSON = #"{"quoteSign":"fixture-sign"}"#
        let flow = try makeFlow(service, reader: reader)
        await ready(flow)
        XCTAssertEqual(flow.confirmationBlock, .quoteUnavailable)
        XCTAssertFalse(flow.prepareConfirmation())
        let soldOut = try self.makeFlow(UIRegistrationService(), reader: reader,
            detail: makeActivity(tickets: #"[{"id":11,"name":"Full","price":0,"remainingInventory":0}]"#))
        await ready(soldOut)
        XCTAssertEqual(soldOut.confirmationBlock, .soldOut)
        XCTAssertFalse(soldOut.prepareConfirmation())
    }
    func testContactEditAndRefreshRequireNewExplicitReview() async throws {
        let service = UIRegistrationService(), reader = UIRegistrationParticipants()
        let flow = try makeFlow(service, reader: reader)
        await ready(flow)
        XCTAssertTrue(flow.prepareConfirmation())
        flow.setPhone("13700000000")
        XCTAssertNil(flow.confirmation)
        await flow.confirm()
        XCTAssertTrue(service.creates.isEmpty)
        XCTAssertTrue(flow.prepareConfirmation())
        await flow.requestQuote()
        XCTAssertNil(flow.confirmation)
        await flow.confirm()
        XCTAssertTrue(service.creates.isEmpty)
    }
    func testUnknownCreateCannotRepeatRequoteOrRecreateAfterReopen() async throws {
        let service = UIRegistrationService(), reader = UIRegistrationParticipants()
        service.createError = URLError(.timedOut)
        let flow = try makeFlow(service, reader: reader)
        await ready(flow)
        XCTAssertTrue(flow.prepareConfirmation()); await flow.confirm()
        let retained = flow.coordinator.retainedIntent
        guard case .outcomeUnknown = flow.creationState else { return XCTFail("Unknown response must remain uncertain") }
        flow.leave(); flow.open()
        XCTAssertEqual(flow.coordinator.retainedIntent, retained)
        XCTAssertFalse(flow.canEdit)
        XCTAssertFalse(flow.canReadStatus)
        XCTAssertFalse(flow.prepareConfirmation())
        XCTAssertFalse(flow.selectTicket(id: 12))
        await flow.requestQuote(); await flow.confirm(); await flow.readKnownStatus()
        XCTAssertEqual(service.creates.count, 1)
        XCTAssertEqual(service.quotes.count, 1)
        XCTAssertTrue(service.reads.isEmpty)
        XCTAssertEqual(flow.draft, RegistrationUIFormDraft())
    }
    func testNoPaymentParametersAndZeroAmountOnlyEnableExplicitKnownIDReadback() async throws {
        let service = UIRegistrationService(), reader = UIRegistrationParticipants()
        let coordinator = try makeCoordinator(service)
        var snapshots: [RegistrationStatusSnapshot] = []
        let flow = RegistrationUIFlow(activity: try makeActivity(), coordinator: coordinator,
            participantReader: reader, currentIdentity: { reader.identity }, quoteEnabled: true,
            creationPolicy: .offlineFixture, onReadback: { snapshots.append($0) })
        await ready(flow); XCTAssertTrue(flow.prepareConfirmation()); await flow.confirm()
        guard case .responseReceived(_, let response) = flow.creationState else { return XCTFail("Expected response evidence only") }
        XCTAssertFalse(response.hasPaymentParameters)
        XCTAssertEqual(response.payableAmount, .zero)
        XCTAssertTrue(service.reads.isEmpty)
        XCTAssertTrue(snapshots.isEmpty)
        XCTAssertTrue(flow.canReadStatus)
        await flow.readKnownStatus()
        XCTAssertEqual(service.reads, [41])
        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(snapshots.first?.registrationStatus, 3)
        XCTAssertEqual(snapshots.first?.paymentStatus, 2)
        XCTAssertFalse(flow.canEdit)
        XCTAssertFalse(flow.prepareConfirmation())
    }
    func testDismissDuringCreateRetainsUnknownAndIgnoresLateResponse() async throws {
        let service = UIRegistrationService(), reader = UIRegistrationParticipants()
        service.suspendCreate = true
        let flow = try makeFlow(service, reader: reader)
        await ready(flow); XCTAssertTrue(flow.prepareConfirmation())
        let task = Task { await flow.confirm() }
        await service.waitForCreate()
        await flow.confirm()
        XCTAssertEqual(service.creates.count, 1)
        flow.leave()
        service.createContinuation?.resume(returning: try JSONDecoder().decode(RegistrationCreateResult.self,
            from: Data(#"{"registrationId":41,"payableAmount":0}"#.utf8)))
        await task.value
        flow.open()
        guard case .outcomeUnknown = flow.creationState else { return XCTFail("Dismissal must not imply server cancellation or success") }
        XCTAssertEqual(service.creates.count, 1)
        XCTAssertFalse(flow.canReadStatus)
    }
    func testRetainedOtherActivityIsBlockedRatherThanSilentlyReplaced() async throws {
        let service = UIRegistrationService(), reader = UIRegistrationParticipants()
        let flow = try makeFlow(service, reader: reader)
        await ready(flow); XCTAssertTrue(flow.prepareConfirmation()); await flow.confirm()
        flow.leave()
        let other = RegistrationUIFlow(activity: try makeActivity(id: 8), coordinator: flow.coordinator,
            currentIdentity: { reader.identity }, quoteEnabled: true, creationPolicy: .offlineFixture)
        other.open()
        XCTAssertTrue(other.retainedForAnotherActivity)
        XCTAssertFalse(other.canEdit)
        XCTAssertEqual(other.coordinator.retainedIntent?.selection.ownerID, 7)
        await other.requestQuote()
        XCTAssertEqual(service.quotes.count, 1)
        XCTAssertEqual(service.creates.count, 1)
    }
}
#endif

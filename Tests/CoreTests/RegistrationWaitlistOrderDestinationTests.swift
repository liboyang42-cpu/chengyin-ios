import Foundation
import XCTest
@testable import QuestifyCore

@MainActor private final class WaitlistOrderReadFixture: ProfileReading, RegistrationCoordinatingService, RegistrationWaitlistServing, RegistrationPendingServing {
    var identity: ProfileReadIdentity? = .init(accountID: 1, epoch: 4, viewerRevision: 3, approvalRevision: UUID())
    var isConfigured = true
    var requests: [Int] = []
    var row: ProfileOrder!
    var statusValue: RegistrationWaitlistStatus!
    var lock: RegistrationDurableCreation = .pending(registrationID: 41)
    var retainedID = 41
    var retainedError: Error?
    var retainedReads = 0
    var suspendRetained = false
    var retainedContinuation: CheckedContinuation<RegistrationStatusSnapshot, Error>?
    var retainedWaiter: CheckedContinuation<Void, Never>?
    func waitForRetainedRead() async {
        if retainedContinuation == nil { await withCheckedContinuation { retainedWaiter = $0 } }
    }
    func creationLock(_ scope: RegistrationWaitlistScope) throws -> RegistrationDurableCreation { lock }
    func readRetainedStatus(_ scope: RegistrationWaitlistScope) async throws -> RegistrationStatusSnapshot {
        retainedReads += 1
        if suspendRetained {
            return try await withCheckedThrowingContinuation {
                retainedContinuation = $0; retainedWaiter?.resume(); retainedWaiter = nil
            }
        }
        if let retainedError { throw retainedError }
        return try JSONDecoder().decode(RegistrationStatusSnapshot.self, from: Data("{\"id\":\(retainedID),\"registrationStatus\":0,\"paymentStatus\":null}".utf8))
    }
    var creates = 0
    var writes = 0
    func status(_ scope: RegistrationWaitlistScope) async throws -> RegistrationWaitlistStatus { statusValue }
    func join(_ scope: RegistrationWaitlistScope) async throws -> RegistrationWaitlistStatus { writes += 1; throw APIError.invalidRequest }
    func cancel(_ scope: RegistrationWaitlistScope) async throws -> RegistrationWaitlistStatus { writes += 1; throw APIError.invalidRequest }
    func quote(_ selection: RegistrationQuoteRequest, token: String) async throws -> RegistrationQuote { throw APIError.notConfigured }
    func create(_ intent: RegistrationCreateIntent, token: String) async throws -> RegistrationCreateResult { creates += 1; throw APIError.invalidRequest }
    func readStatus(registrationID: Int, token: String) async throws -> RegistrationStatusSnapshot { throw APIError.notConfigured }
    var suspended = false
    var continuation: CheckedContinuation<ProfileOrder, Error>?
    var waiter: CheckedContinuation<Void, Never>?
    func profileOrder(id: Int) async throws -> ProfileOrder {
        requests.append(id)
        if suspended { return try await withCheckedThrowingContinuation { continuation = $0; waiter?.resume(); waiter = nil } }
        return row
    }
    func waitForRead() async { if continuation == nil { await withCheckedContinuation { waiter = $0 } } }
    func profileOrders() async throws -> [ProfileOrder] { throw APIError.invalidRequest }
    func profileParticipants() async throws -> [ProfileParticipant] { throw APIError.invalidRequest }
    func profileParticipant(id: Int) async throws -> ProfileParticipant { throw APIError.invalidRequest }
    func profileBadges() async throws -> ProfileBadgeWall { throw APIError.invalidRequest }
}

@MainActor final class RegistrationWaitlistOrderDestinationTests: XCTestCase {
    private let identity = ProfileReadIdentity(accountID: 1, epoch: 4)
    private func status(_ state: String, order: String = "41", member: Int = 1) throws -> RegistrationWaitlistStatus {
        try JSONDecoder().decode(RegistrationWaitlistStatus.self, from: Data("""
        {"id":5,"activityId":7,"ticketId":11,"memberId":\(member),"state":"\(state)","eligibilityState":"ALREADY_REGISTERED","waitlistJoinAllowed":false,"registrationId":\(order)}
        """.utf8))
    }
    private func route(_ state: String = "CLAIMED") throws -> RegistrationWaitlistOrderDestination {
        try XCTUnwrap(RegistrationWaitlistOrderDestination(status: status(state), scope: .init(activityID: 7, ticketID: 11), identity: identity))
    }
    private func order(id: Int = 41, member: Int = 1, type: Int = 2, activity: Int = 7, ticket: String = "11") throws -> ProfileOrder {
        try JSONDecoder().decode(ProfileOrder.self, from: Data("""
        {"id":\(id),"memberId":\(member),"ownerType":\(type),"ownerId":\(activity),"ticketId":\(ticket),"registrationStatus":0,"paymentStatus":0}
        """.utf8))
    }
    func testOnlyExactClaimedAndConvertedServerIDCreatesRoute() throws {
        for state in ["CLAIMED", "CONVERTED"] { XCTAssertEqual(try route(state).registrationID, 41) }
        for state in ["NONE", "WAITING", "CANCELLED", "EXPIRED"] {
            XCTAssertNil(try RegistrationWaitlistOrderDestination(status: status(state), scope: .init(activityID: 7, ticketID: 11), identity: identity))
        }
        XCTAssertNil(try RegistrationWaitlistOrderDestination(status: status("CLAIMED", member: 2), scope: .init(activityID: 7, ticketID: 11), identity: identity))
        XCTAssertNil(try RegistrationWaitlistOrderDestination(status: status("CLAIMED"), scope: .init(activityID: 8, ticketID: 11), identity: identity))
        XCTAssertNil(try RegistrationWaitlistOrderDestination(status: status("CLAIMED"), scope: .init(activityID: 7, ticketID: 12), identity: identity))
        XCTAssertThrowsError(try status("CLAIMED", order: "null"))
        XCTAssertThrowsError(try status("CONVERTED", order: "0"))
    }
    func testBothStatesReadExactOrderWithoutInferringPaymentAndCanRefresh() async throws {
        for state in ["CLAIMED", "CONVERTED"] {
            let base = WaitlistOrderReadFixture(); base.row = try order()
            let reader = try RegistrationWaitlistOrderReader(presentation: XCTUnwrap(.init(destination: route(state), readIdentity: base.identity)), base: base, isCurrent: { true })
            let row = try await reader.profileOrder(id: 41)
            XCTAssertEqual(row.paymentStatus, 0); XCTAssertEqual(row.ticketID, 11)
            _ = try await reader.profileOrder(id: 41)
            XCTAssertEqual(base.requests, [41, 41])
        }
    }
    func testWrongRequestedIDAndUnavailableGrantNeverDispatch() async throws {
        let base = WaitlistOrderReadFixture(); base.row = try order()
        let reader = try RegistrationWaitlistOrderReader(presentation: XCTUnwrap(.init(destination: route(), readIdentity: base.identity)), base: base, isCurrent: { true })
        do { _ = try await reader.profileOrder(id: 42); XCTFail() } catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        base.isConfigured = false
        do { _ = try await reader.profileOrder(id: 41); XCTFail() } catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        XCTAssertTrue(base.requests.isEmpty)
    }
    func testWrongOrderMemberActivityTypeAndTicketFailClosed() async throws {
        for row in [try order(id: 42), try order(member: 2), try order(type: 1), try order(activity: 8), try order(ticket: "12"), try order(ticket: "null")] {
            let base = WaitlistOrderReadFixture(); base.row = row
            let reader = try RegistrationWaitlistOrderReader(presentation: XCTUnwrap(.init(destination: route(), readIdentity: base.identity)), base: base, isCurrent: { true })
            do { _ = try await reader.profileOrder(id: 41); XCTFail() } catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
        }
    }
    func testNewAccountEpochViewerOrApprovalCannotReuseFrozenRoute() async throws {
        for newIdentity in [ProfileReadIdentity(accountID: 2, epoch: 4), .init(accountID: 1, epoch: 5), .init(accountID: 1, epoch: 4, viewerRevision: 4), .init(accountID: 1, epoch: 4, viewerRevision: 3, approvalRevision: UUID())] {
            let base = WaitlistOrderReadFixture(); base.row = try order()
            let reader = try RegistrationWaitlistOrderReader(presentation: XCTUnwrap(.init(destination: route(), readIdentity: base.identity)), base: base, isCurrent: { true })
            base.identity = newIdentity
            XCTAssertNil(reader.identity)
            do { _ = try await reader.profileOrder(id: 41); XCTFail() } catch { XCTAssertEqual(error as? APIError, .unauthorized) }
            XCTAssertTrue(base.requests.isEmpty)
        }
    }
    func testLateSuccessAndLateFailureAreDiscardedAfterScopeOrSessionChanges() async throws {
        for sessionChange in [true, false] {
            for fail in [true, false] {
                let base = WaitlistOrderReadFixture(); base.row = try order(); base.suspended = true
                var current = true
                let reader = try RegistrationWaitlistOrderReader(presentation: XCTUnwrap(.init(destination: route(), readIdentity: base.identity)), base: base, isCurrent: { current })
                let read = Task { try await reader.profileOrder(id: 41) }
                await base.waitForRead()
                if sessionChange { base.identity = .init(accountID: 1, epoch: 5) } else { current = false }
                if fail { base.continuation?.resume(throwing: APIError.unauthorized) }
                else { base.continuation?.resume(returning: base.row) }
                do { _ = try await read.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
                XCTAssertNil(reader.identity)
            }
        }
    }
    func testCancelledReadCannotPublishSuccess() async throws {
        let base = WaitlistOrderReadFixture(); base.row = try order(); base.suspended = true
        let reader = try RegistrationWaitlistOrderReader(presentation: XCTUnwrap(.init(destination: route(), readIdentity: base.identity)), base: base, isCurrent: { true })
        let read = Task { try await reader.profileOrder(id: 41) }
        await base.waitForRead(); read.cancel(); base.continuation?.resume(returning: base.row)
        do { _ = try await read.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
    }
    func testSheetReconstructionCannotRebindOldPresentationToNewApproval() async throws {
        let base = WaitlistOrderReadFixture(); base.row = try order()
        let presentation = try XCTUnwrap(RegistrationWaitlistOrderPresentation(destination: route(), readIdentity: base.identity))
        base.identity = .init(accountID: 1, epoch: 4, viewerRevision: 3, approvalRevision: UUID())
        let reconstructed = RegistrationWaitlistOrderReader(presentation: presentation, base: base, isCurrent: { true })
        XCTAssertNil(reconstructed.identity); XCTAssertFalse(reconstructed.isConfigured)
        do { _ = try await reconstructed.profileOrder(id: 41); XCTFail() } catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        XCTAssertTrue(base.requests.isEmpty)
    }
    #if DEBUG
    func testFlowRouteAndCreationLockFollowSessionScopeAndAuthoritativeState() async throws {
        for state in ["CLAIMED", "CONVERTED"] {
            let service = WaitlistOrderReadFixture(); service.statusValue = try status(state)
            let coordinator = RegistrationCoordinator(service: service)
            try coordinator.setAccount(id: 1, token: "fixture-token")
            var current: ProfileReadIdentity? = identity
            let activity = try JSONDecoder().decode(ActivityDetail.self, from: Data(#"{"id":7,"name":"Fixture","omsTicketList":[{"id":11,"name":"Claimed ticket fixture","remainingInventory":5},{"id":12,"name":"Other ticket fixture","remainingInventory":5}]}"#.utf8))
            let flow = RegistrationUIFlow(activity: activity, coordinator: coordinator,
                currentIdentity: { current }, quoteEnabled: true, creationPolicy: .offlineFixture, waitlistService: service)
            flow.open(); await flow.loadWaitlist()
            XCTAssertEqual(flow.waitlistOrderDestination?.registrationID, 41)
            XCTAssertEqual(flow.confirmationBlock, .intentAlreadySubmitted)
            XCTAssertFalse(flow.prepareConfirmation()); await flow.confirm()
            XCTAssertEqual(service.creates, 0); XCTAssertEqual(service.writes, 0)
            XCTAssertTrue(flow.selectTicket(id: 12)); XCTAssertNil(flow.waitlistOrderDestination)
            _ = flow.selectTicket(id: 11); await flow.loadWaitlist()
            current = .init(accountID: 1, epoch: 5)
            XCTAssertNil(flow.waitlistOrderDestination)
            current = identity; flow.leave(); XCTAssertNil(flow.waitlistOrderDestination)
        }
    }
    #endif

}

@MainActor private final class ResultOrderCreationFixture: RegistrationCoordinatingService {
    var creates = 0
    var statusReads = 0
    var createError: Error?
    func quote(_ selection: RegistrationQuoteRequest, token: String) async throws -> RegistrationQuote {
        try JSONDecoder().decode(RegistrationQuote.self, from: Data(#"{"payAmount":0,"quoteSign":"synthetic-sign"}"#.utf8))
    }
    func create(_ intent: RegistrationCreateIntent, token: String) async throws -> RegistrationCreateResult {
        creates += 1
        if let createError { throw createError }
        return try JSONDecoder().decode(RegistrationCreateResult.self, from: Data(#"{"registrationId":41,"payableAmount":0}"#.utf8))
    }
    func readStatus(registrationID: Int, token: String) async throws -> RegistrationStatusSnapshot {
        statusReads += 1
        return try JSONDecoder().decode(RegistrationStatusSnapshot.self, from: Data(#"{"id":41,"registrationStatus":0,"paymentStatus":null}"#.utf8))
    }
}

@MainActor final class RegistrationResultOrderDestinationTests: XCTestCase {
    private func activity(_ id: Int = 7, ticket: Int? = 11) throws -> ActivityDetail {
        let tickets = ticket.map { "[{\"id\":\($0),\"name\":\"Synthetic ticket\"}]" } ?? "[]"
        return try JSONDecoder().decode(ActivityDetail.self, from: Data("{\"id\":\(id),\"name\":\"Synthetic activity\",\"omsTicketList\":\(tickets)}".utf8))
    }
    private func order(id: Int = 41, member: Int = 1, type: Int = 2, activity: Int = 7, ticket: String = "11") throws -> ProfileOrder {
        try JSONDecoder().decode(ProfileOrder.self, from: Data("""
        {"id":\(id),"memberId":\(member),"ownerType":\(type),"ownerId":\(activity),"ticketId":\(ticket),"registrationStatus":0,"paymentStatus":null}
        """.utf8))
    }
    private func opened(_ base: WaitlistOrderReadFixture, service: ResultOrderCreationFixture? = nil, ticket: Int? = 11) throws -> (RegistrationUIFlow, ResultOrderCreationFixture) {
        let service = service ?? ResultOrderCreationFixture()
        let coordinator = RegistrationCoordinator(service: service, makeRequestID: { "synthetic-result-request" })
        try coordinator.setAccount(id: 1, token: "synthetic-token")
        let flow = try RegistrationUIFlow(activity: activity(ticket: ticket), coordinator: coordinator, currentIdentity: { base.identity })
        flow.open()
        return (flow, service)
    }
    private func create(_ flow: RegistrationUIFlow) async {
        _ = await flow.coordinator.requestQuote()
        _ = await flow.coordinator.confirm(.init(realName: "Synthetic", phone: "13800000000"))
    }
    private func presentation(_ flow: RegistrationUIFlow, base: WaitlistOrderReadFixture) throws -> RegistrationResultOrderPresentation {
        try XCTUnwrap(.init(destination: XCTUnwrap(flow.resultOrderDestination), readIdentity: base.identity))
    }
    func testKnownCreateOpensExactOrderWithoutStatusOrPaymentInference() async throws {
        let base = WaitlistOrderReadFixture(); base.row = try order()
        let (flow, service) = try opened(base)
        XCTAssertNil(flow.resultOrderDestination)
        await create(flow)
        let target = try XCTUnwrap(flow.resultOrderDestination)
        XCTAssertEqual(target.requestID, "synthetic-result-request")
        XCTAssertEqual(target.activityID, 7); XCTAssertEqual(target.ticketID, 11)
        let offered = try presentation(flow, base: base)
        let reader = RegistrationResultOrderReader(presentation: offered, base: base, isCurrent: { flow.resultOrderDestination == target })
        let row = try await reader.profileOrder(id: 41)
        XCTAssertNil(row.paymentStatus); XCTAssertEqual(row.registrationStatus, 0)
        _ = try await reader.profileOrder(id: 41)
        XCTAssertEqual(base.requests, [41, 41]); XCTAssertEqual(service.creates, 1); XCTAssertEqual(service.statusReads, 0)
        XCTAssertNotNil(flow.coordinator.retainedIntent); XCTAssertFalse(flow.coordinator.canConfirm)
        XCTAssertEqual(flow.creationPolicy, .disabled)
    }
    func testUnknownCreateAndMissingTicketCannotOfferOrder() async throws {
        let base = WaitlistOrderReadFixture(), service = ResultOrderCreationFixture()
        service.createError = URLError(.timedOut)
        let (unknown, _) = try opened(base, service: service)
        await create(unknown)
        XCTAssertNil(unknown.resultOrderDestination)
        unknown.leave(); unknown.open()
        XCTAssertNil(unknown.resultOrderDestination); XCTAssertNotNil(unknown.coordinator.retainedIntent)
        let (withoutTicket, _) = try opened(base, ticket: nil)
        await create(withoutTicket)
        XCTAssertNil(withoutTicket.resultOrderDestination)
    }
    func testOtherActivityCannotBorrowRetainedReceipt() async throws {
        let base = WaitlistOrderReadFixture()
        let (flow, _) = try opened(base)
        await create(flow)
        let other = try RegistrationUIFlow(activity: activity(8), coordinator: flow.coordinator, currentIdentity: { base.identity })
        other.open(); XCTAssertTrue(other.retainedForAnotherActivity); XCTAssertNil(other.resultOrderDestination)
    }
    func testLeaveReopenAndSessionChangesRetireExactVisit() async throws {
        let base = WaitlistOrderReadFixture()
        let (flow, service) = try opened(base)
        await create(flow)
        let old = try XCTUnwrap(flow.resultOrderDestination)
        let offered = try presentation(flow, base: base)
        let reader = RegistrationResultOrderReader(presentation: offered, base: base, isCurrent: { flow.resultOrderDestination == old })
        flow.retireResultOrderNavigation()
        XCTAssertNotEqual(flow.resultOrderDestination, old); XCTAssertNil(reader.identity)
        flow.leave(); XCTAssertNil(flow.resultOrderDestination); XCTAssertNil(reader.identity)
        flow.open(); XCTAssertNotNil(flow.resultOrderDestination); XCTAssertNotEqual(flow.resultOrderDestination, old)
        XCTAssertNil(reader.identity); XCTAssertEqual(service.creates, 1)
        base.identity = .init(accountID: 1, epoch: 5)
        XCTAssertNil(flow.resultOrderDestination)
    }
    func testIndependentOwnedOrderIdentityMustMatchAccountAndEpoch() async throws {
        let base = WaitlistOrderReadFixture()
        let (flow, _) = try opened(base)
        await create(flow); let target = try XCTUnwrap(flow.resultOrderDestination)
        let mismatches: [ProfileReadIdentity?] = [nil, .init(accountID: 2, epoch: 4), .init(accountID: 1, epoch: 5)]
        for identity in mismatches {
            XCTAssertNil(RegistrationResultOrderPresentation(destination: target, readIdentity: identity))
        }
        // Separate read approvals need not share approval revision with the form.
        XCTAssertNotNil(RegistrationResultOrderPresentation(destination: target,
            readIdentity: .init(accountID: 1, epoch: 4, viewerRevision: 9, approvalRevision: UUID())))
    }
    func testWrongRequestedIDAndUnconfiguredReadCannotDispatch() async throws {
        let base = WaitlistOrderReadFixture()
        let (flow, _) = try opened(base)
        await create(flow)
        let reader = try RegistrationResultOrderReader(presentation: presentation(flow, base: base), base: base, isCurrent: { true })
        do { _ = try await reader.profileOrder(id: 7); XCTFail() } catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        base.isConfigured = false
        do { _ = try await reader.profileOrder(id: 41); XCTFail() } catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        XCTAssertTrue(base.requests.isEmpty)
    }
    func testExactOrderOwnershipTupleIsRequired() async throws {
        let base = WaitlistOrderReadFixture()
        let (flow, _) = try opened(base)
        await create(flow)
        let reader = try RegistrationResultOrderReader(presentation: presentation(flow, base: base), base: base, isCurrent: { true })
        for row in [try order(id: 42), try order(member: 2), try order(type: 1), try order(activity: 8), try order(ticket: "12"), try order(ticket: "null")] {
            base.row = row
            do { _ = try await reader.profileOrder(id: 41); XCTFail() } catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
        }
    }
    func testReconstructionCannotAdoptReplacementReadGrant() async throws {
        let base = WaitlistOrderReadFixture()
        let (flow, _) = try opened(base)
        await create(flow); let offered = try presentation(flow, base: base)
        base.identity = .init(accountID: 1, epoch: 4, viewerRevision: 3, approvalRevision: UUID())
        let reader = RegistrationResultOrderReader(presentation: offered, base: base, isCurrent: { true })
        XCTAssertNil(reader.identity)
        do { _ = try await reader.profileOrder(id: 41); XCTFail() } catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        XCTAssertTrue(base.requests.isEmpty)
    }
    func testLateSuccessAndErrorCannotSurviveDismissalOrGrantRevocation() async throws {
        for failure in [false, true] {
            for revoke in [false, true] {
                let base = WaitlistOrderReadFixture()
        let (flow, _) = try opened(base)
                await create(flow); base.suspended = true; base.row = try order()
                let offered = try presentation(flow, base: base)
                let reader = RegistrationResultOrderReader(presentation: offered, base: base,
                    isCurrent: { flow.resultOrderDestination == offered.destination })
                let task = Task { try await reader.profileOrder(id: 41) }
                await base.waitForRead()
                if revoke { base.isConfigured = false } else { flow.leave(); flow.open() }
                if failure { base.continuation?.resume(throwing: APIError.unauthorized) }
                else { base.continuation?.resume(returning: base.row) }
                do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
            }
        }
    }
    func testCancelledReadAndAdjacentMethodsAreRejected() async throws {
        let base = WaitlistOrderReadFixture()
        let (flow, _) = try opened(base)
        await create(flow); base.suspended = true; base.row = try order()
        let reader = try RegistrationResultOrderReader(presentation: presentation(flow, base: base), base: base, isCurrent: { true })
        let task = Task { try await reader.profileOrder(id: 41) }
        await base.waitForRead(); task.cancel(); base.continuation?.resume(returning: base.row)
        do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        do { _ = try await reader.profileOrders(); XCTFail() } catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        do { _ = try await reader.profileParticipants(); XCTFail() } catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        do { _ = try await reader.profileParticipant(id: 1); XCTFail() } catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        do { _ = try await reader.profileBadges(); XCTFail() } catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        XCTAssertEqual(base.requests, [41])
    }
    func testCloseAndReopenSameResultNeverRevivesOldUncancelledReader() async throws {
        let base = WaitlistOrderReadFixture()
        let (flow, _) = try opened(base)
        await create(flow); base.suspended = true; base.row = try order()
        let old = try presentation(flow, base: base)
        var current: RegistrationResultOrderPresentation? = old
        let oldReader = RegistrationResultOrderReader(presentation: old, base: base,
            isCurrent: { current == old && flow.resultOrderDestination == old.destination })
        let oldTask = Task { try await oldReader.profileOrder(id: 41) }
        await base.waitForRead()
        current = nil // Close the detail, preserving this same form and known response.
        XCTAssertNil(oldReader.identity)
        let reopened = try presentation(flow, base: base)
        XCTAssertEqual(reopened.destination, old.destination)
        XCTAssertEqual(reopened.readIdentity, old.readIdentity)
        XCTAssertNotEqual(reopened.id, old.id)
        current = reopened
        XCTAssertNil(oldReader.identity)
        // Deliberately do not cancel the task: a noncooperative completion must fail.
        base.continuation?.resume(returning: base.row)
        do { _ = try await oldTask.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        base.suspended = false
        let fresh = RegistrationResultOrderReader(presentation: reopened, base: base,
            isCurrent: { current == reopened && flow.resultOrderDestination == reopened.destination })
        let row = try await fresh.profileOrder(id: 41)
        XCTAssertEqual(row.id, 41); XCTAssertEqual(base.requests, [41, 41])
    }
}


@MainActor final class RegistrationRecoveredOrderDestinationTests: XCTestCase {
    private func opened(_ base: WaitlistOrderReadFixture) throws -> RegistrationUIFlow {
        let identity = try XCTUnwrap(base.identity)
        let grant = try RegistrationProductionApproval(
            endpoint: .init(baseURL: URL(string: "https://api.example.com/prod-api")!, namespace: "synthetic", accountID: 1,
                            paths: RegistrationProductionApproval.registrationPaths),
            identity: identity, market: .china, storefront: "CHN", product: .physicalActivity,
            activityID: 7, ticketIDs: [11], consentVersion: "synthetic-v1",
            noticeURL: URL(string: "https://legal.example.com/synthetic")!, expiresAt: Date().addingTimeInterval(3600))
        let coordinator = RegistrationCoordinator(service: base)
        try coordinator.setAccount(id: 1, token: "synthetic-token")
        let activity = try JSONDecoder().decode(ActivityDetail.self, from: Data(#"{"id":7,"name":"Synthetic","omsTicketList":[{"id":11,"name":"Synthetic"}]}"#.utf8))
        let flow = RegistrationUIFlow(activity: activity, coordinator: coordinator, currentIdentity: { base.identity },
                                      creationPolicy: .approved(grant), waitlistService: base)
        flow.open(); return flow
    }
    private func row(id: Int = 41, member: Int = 1, type: Int = 2, activity: Int = 7, ticket: String = "11") throws -> ProfileOrder {
        try JSONDecoder().decode(ProfileOrder.self, from: Data("""
        {"id":\(id),"memberId":\(member),"ownerType":\(type),"ownerId":\(activity),"ticketId":\(ticket),"registrationStatus":0,"paymentStatus":null}
        """.utf8))
    }
    private func presentation(_ flow: RegistrationUIFlow, _ base: WaitlistOrderReadFixture) throws -> RegistrationRecoveredOrderPresentation {
        try XCTUnwrap(.init(destination: XCTUnwrap(flow.recoveredOrderDestination), readIdentity: base.identity))
    }
    func testKnownJournalRequiresReadThenExactOwnedDetailWithoutCreate() async throws {
        let base = WaitlistOrderReadFixture(); base.row = try row()
        let flow = try opened(base)
        XCTAssertNil(flow.recoveredOrderDestination); XCTAssertFalse(flow.canEdit)
        await flow.readDurableStatus()
        let route = try presentation(flow, base)
        let reader = RegistrationRecoveredOrderReader(presentation: route, base: base, isCurrent: { flow.recoveredOrderDestination == route.destination })
        let result = try await reader.profileOrder(id: 41)
        XCTAssertNil(result.paymentStatus); XCTAssertEqual(base.requests, [41])
        XCTAssertEqual(base.retainedReads, 1); XCTAssertEqual(base.creates, 0); XCTAssertEqual(base.writes, 0)
        XCTAssertNil(flow.coordinator.retainedIntent); XCTAssertFalse(flow.canEdit)
        guard case .pending(let id) = flow.durableCreation else { return XCTFail("Journal lock cleared") }
        XCTAssertEqual(id, 41)
    }
    func testUnknownJournalCannotReadOrInventDestination() async throws {
        let base = WaitlistOrderReadFixture(); base.lock = .pending(registrationID: nil)
        let flow = try opened(base); await flow.readDurableStatus()
        XCTAssertNil(flow.recoveredOrderDestination); XCTAssertEqual(base.retainedReads, 0); XCTAssertFalse(flow.canEdit)
    }
    func testWrongStatusAndFailureClearRouteAndAllowReadOnlyRetry() async throws {
        let base = WaitlistOrderReadFixture(); let flow = try opened(base)
        await flow.readDurableStatus(); XCTAssertNotNil(flow.recoveredOrderDestination)
        base.retainedID = 42; await flow.readDurableStatus()
        XCTAssertNil(flow.recoveredOrderDestination); XCTAssertTrue(flow.durableStatusFailed); XCTAssertFalse(flow.isReadingStatus)
        base.retainedID = 41; base.retainedError = APIError.notConfigured; await flow.readDurableStatus()
        XCTAssertNil(flow.recoveredOrderDestination); XCTAssertTrue(flow.durableStatusFailed)
        base.retainedError = nil; await flow.readDurableStatus()
        XCTAssertNotNil(flow.recoveredOrderDestination); XCTAssertFalse(flow.durableStatusFailed)
        XCTAssertEqual(base.creates, 0); XCTAssertEqual(base.writes, 0)
    }
    func testWrongOwnerTupleAndRequestedIDFailClosed() async throws {
        for value in [try row(id: 42), try row(member: 2), try row(type: 1), try row(activity: 8), try row(ticket: "12"), try row(ticket: "null")] {
            let base = WaitlistOrderReadFixture(); base.row = value
            let flow = try opened(base); await flow.readDurableStatus()
            let reader = try RegistrationRecoveredOrderReader(presentation: presentation(flow, base), base: base, isCurrent: { true })
            do { _ = try await reader.profileOrder(id: 42); XCTFail() } catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
            XCTAssertTrue(base.requests.isEmpty)
            do { _ = try await reader.profileOrder(id: 41); XCTFail() } catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
        }
    }
    func testVisitRetirementAndReopenInvalidateOldRoute() async throws {
        let base = WaitlistOrderReadFixture(); let flow = try opened(base); await flow.readDurableStatus()
        let original = try XCTUnwrap(flow.recoveredOrderDestination)
        flow.retireResultOrderNavigation(); XCTAssertNotEqual(flow.recoveredOrderDestination, original)
        flow.open(); XCTAssertNil(flow.recoveredOrderDestination); XCTAssertFalse(flow.canEdit)
        await flow.readDurableStatus(); XCTAssertNotEqual(flow.recoveredOrderDestination, original)
        base.identity = .init(accountID: 1, epoch: 5)
        XCTAssertNil(flow.recoveredOrderDestination)
    }
    func testMissingAndWrongIndependentReadGrantCannotPresent() async throws {
        let base = WaitlistOrderReadFixture(); let flow = try opened(base); await flow.readDurableStatus()
        let destination = try XCTUnwrap(flow.recoveredOrderDestination)
        for identity in [nil, ProfileReadIdentity(accountID: 2, epoch: 4), .init(accountID: 1, epoch: 5)] {
            XCTAssertNil(RegistrationRecoveredOrderPresentation(destination: destination, readIdentity: identity))
        }
        let reader = try RegistrationRecoveredOrderReader(presentation: presentation(flow, base), base: base, isCurrent: { true })
        base.identity = .init(accountID: 1, epoch: 4, viewerRevision: 3, approvalRevision: UUID())
        XCTAssertNil(reader.identity)
        do { _ = try await reader.profileOrder(id: 41); XCTFail() } catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        XCTAssertTrue(base.requests.isEmpty)
    }
    func testPendingReadCoalescesAndLateResultsCannotEnterReopenedForm() async throws {
        for fail in [false, true] {
            let base = WaitlistOrderReadFixture(); base.suspendRetained = true
            let flow = try opened(base)
            let task = Task { await flow.readDurableStatus() }
            await base.waitForRetainedRead()
            await flow.readDurableStatus()
            XCTAssertEqual(base.retainedReads, 1); XCTAssertNil(flow.recoveredOrderDestination)
            flow.leave(); flow.open()
            if fail { base.retainedContinuation?.resume(throwing: APIError.notConfigured) }
            else {
                let snapshot = try JSONDecoder().decode(RegistrationStatusSnapshot.self, from: Data(#"{"id":41,"registrationStatus":0,"paymentStatus":null}"#.utf8))
                base.retainedContinuation?.resume(returning: snapshot)
            }
            await task.value
            XCTAssertNil(flow.recoveredOrderDestination); XCTAssertFalse(flow.durableStatusFailed)
            XCTAssertFalse(flow.isReadingStatus); XCTAssertFalse(flow.canEdit)
        }
    }
    func testClosingAndReopeningDetailUsesNewPresentationIdentity() async throws {
        let base = WaitlistOrderReadFixture(); let flow = try opened(base); await flow.readDurableStatus()
        let first = try presentation(flow, base), second = try presentation(flow, base)
        XCTAssertNotEqual(first.id, second.id); XCTAssertEqual(first.destination, second.destination)
        XCTAssertFalse(flow.canEdit); XCTAssertEqual(base.creates, 0)
    }
    func testLateOwnedReadDiscardedWhenPresentationCloses() async throws {
        let base = WaitlistOrderReadFixture(); base.row = try row(); base.suspended = true
        let flow = try opened(base); await flow.readDurableStatus()
        var current = true
        let reader = try RegistrationRecoveredOrderReader(presentation: presentation(flow, base), base: base, isCurrent: { current })
        let task = Task { try await reader.profileOrder(id: 41) }
        await base.waitForRead(); current = false; base.continuation?.resume(returning: base.row)
        do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
    }
}

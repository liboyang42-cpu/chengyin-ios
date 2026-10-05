import Foundation
import XCTest
@testable import QuestifyCore

@MainActor private final class WaitlistOrderReadFixture: ProfileReading, RegistrationCoordinatingService, RegistrationWaitlistServing {
    var identity: ProfileReadIdentity? = .init(accountID: 1, epoch: 4, viewerRevision: 3, approvalRevision: UUID())
    var isConfigured = true
    var requests: [Int] = []
    var row: ProfileOrder!
    var statusValue: RegistrationWaitlistStatus!
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

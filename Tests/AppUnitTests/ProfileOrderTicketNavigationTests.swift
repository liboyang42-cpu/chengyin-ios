import XCTest
@testable import Questify

@MainActor private final class OrderTicketOriginFixture: ProfileReading {
    var isConfigured = true
    var identity: ProfileReadIdentity? = .init(accountID: 7, epoch: 1, viewerRevision: 2, approvalRevision: UUID())
    func profileOrders() async throws -> [ProfileOrder] { throw APIError.notConfigured }
    func profileOrder(id: Int) async throws -> ProfileOrder { throw APIError.notConfigured }
    func profileParticipants() async throws -> [ProfileParticipant] { throw APIError.notConfigured }
    func profileParticipant(id: Int) async throws -> ProfileParticipant { throw APIError.notConfigured }
    func profileBadges() async throws -> ProfileBadgeWall { throw APIError.notConfigured }
}
@MainActor private final class OrderTicketReaderFixture: TicketWalletReading {
    var isConfigured = true
    var isAuthenticated = true
    let isOfflineExample = true
    var scope = UUID()
    var ids: [Int] = []
    var listReads = 0
    var returnedID = 41
    var onRead: (() -> Void)?
    var failure: APIError?
    func ticketWallet() async throws -> TicketWalletSnapshot { listReads += 1; return .init(tickets: []) }
    func ticketDetail(id: Int) async throws -> TicketWalletTicket {
        ids.append(id); await Task.yield(); onRead?()
        if let failure { throw failure }
        return try JSONDecoder().decode(TicketWalletTicket.self, from: Data("{\"id\":\(returnedID),\"registrationStatus\":2}".utf8))
    }
}

@MainActor final class ProfileOrderTicketNavigationTests: XCTestCase {
    private func order(id: Int = 41, member: Int? = 7) throws -> ProfileOrder {
        let memberField = member.map { ",\"memberId\":\($0)" } ?? ""
        return try JSONDecoder().decode(ProfileOrder.self, from: Data("{\"id\":\(id),\"ticketId\":555,\"ownerId\":999\(memberField)}".utf8))
    }
    private func makeTarget(_ origin: OrderTicketOriginFixture, _ tickets: OrderTicketReaderFixture) throws -> ProfileOrderTicketTarget {
        try XCTUnwrap(ProfileOrderTicketTarget(order: order(), requestedID: 41, origin: origin, tickets: tickets))
    }
    func testCreatingNavigationMakesNoReadAndUsesRegistrationIDOnly() throws {
        let origin = OrderTicketOriginFixture(), tickets = OrderTicketReaderFixture()
        let target = try makeTarget(origin, tickets)
        XCTAssertEqual(target.registrationID, 41); XCTAssertNotEqual(target.registrationID, 555); XCTAssertNotEqual(target.registrationID, 999)
        _ = ProfileOrderTicketReader(target: target, origin: origin, tickets: tickets)
        XCTAssertTrue(tickets.ids.isEmpty); XCTAssertEqual(tickets.listReads, 0)
    }
    func testPositiveRequestedIDAndFreshOwnerMembershipAreRequired() throws {
        let origin = OrderTicketOriginFixture(), tickets = OrderTicketReaderFixture()
        for id in [0, -1, 42] { XCTAssertNil(ProfileOrderTicketTarget(order: try order(), requestedID: id, origin: origin, tickets: tickets)) }
        for member in [Int?.none, Int?.some(8)] { XCTAssertNil(ProfileOrderTicketTarget(order: try order(member: member), requestedID: 41, origin: origin, tickets: tickets)) }
    }
    func testMissingOriginIdentityOrUnconfiguredReadersCannotActivate() throws {
        let origin = OrderTicketOriginFixture(), tickets = OrderTicketReaderFixture(); let original = origin.identity
        origin.identity = nil; XCTAssertNil(ProfileOrderTicketTarget(order: try order(), requestedID: 41, origin: origin, tickets: tickets))
        origin.identity = original; origin.isConfigured = false
        XCTAssertNil(ProfileOrderTicketTarget(order: try order(), requestedID: 41, origin: origin, tickets: tickets))
        origin.isConfigured = true; tickets.isConfigured = false
        XCTAssertNil(ProfileOrderTicketTarget(order: try order(), requestedID: 41, origin: origin, tickets: tickets))
        tickets.isConfigured = true; tickets.isAuthenticated = false
        XCTAssertNil(ProfileOrderTicketTarget(order: try order(), requestedID: 41, origin: origin, tickets: tickets))
        XCTAssertTrue(tickets.ids.isEmpty)
    }
    func testExactAccountEpochViewerAndApprovalFenceSameNumericRegistration() throws {
        let origin = OrderTicketOriginFixture(), tickets = OrderTicketReaderFixture(), original = try XCTUnwrap(OrderTicketOriginFixture().identity)
        origin.identity = original; let target = try makeTarget(origin, tickets)
        for identity in [ProfileReadIdentity(accountID: 8, epoch: original.epoch, viewerRevision: original.viewerRevision, approvalRevision: original.approvalRevision),
                         .init(accountID: 7, epoch: 2, viewerRevision: original.viewerRevision, approvalRevision: original.approvalRevision),
                         .init(accountID: 7, epoch: original.epoch, viewerRevision: 9, approvalRevision: original.approvalRevision),
                         .init(accountID: 7, epoch: original.epoch, viewerRevision: original.viewerRevision, approvalRevision: UUID())] {
            origin.identity = identity; XCTAssertFalse(target.matches(origin: origin, tickets: tickets))
        }
    }
    func testReaderReplacementAndTicketScopeChangesCannotReuseSelection() throws {
        let origin = OrderTicketOriginFixture(), tickets = OrderTicketReaderFixture(); let target = try makeTarget(origin, tickets)
        let otherOrigin = OrderTicketOriginFixture(); otherOrigin.identity = origin.identity
        XCTAssertFalse(target.matches(origin: otherOrigin, tickets: tickets))
        let otherTickets = OrderTicketReaderFixture(); otherTickets.scope = tickets.scope
        XCTAssertFalse(target.matches(origin: origin, tickets: otherTickets))
        tickets.scope = UUID(); XCTAssertFalse(target.matches(origin: origin, tickets: tickets))
    }
    func testCorrectTargetPerformsOneFreshDetailRead() async throws {
        let origin = OrderTicketOriginFixture(), tickets = OrderTicketReaderFixture()
        let proxy = ProfileOrderTicketReader(target: try makeTarget(origin, tickets), origin: origin, tickets: tickets)
        let value = try await proxy.ticketDetail(id: 41)
        XCTAssertEqual(value.id, 41); XCTAssertEqual(tickets.ids, [41]); XCTAssertEqual(tickets.listReads, 0)
    }
    func testWrongIDAndListCannotDispatchThroughSingleTargetProxy() async throws {
        let origin = OrderTicketOriginFixture(), tickets = OrderTicketReaderFixture()
        let proxy = ProfileOrderTicketReader(target: try makeTarget(origin, tickets), origin: origin, tickets: tickets)
        do { _ = try await proxy.ticketDetail(id: 555); XCTFail() } catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        do { _ = try await proxy.ticketWallet(); XCTFail() } catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        XCTAssertTrue(tickets.ids.isEmpty); XCTAssertEqual(tickets.listReads, 0)
    }
    func testOriginRevocationBeforeDispatchMakesNoRequest() async throws {
        let origin = OrderTicketOriginFixture(), tickets = OrderTicketReaderFixture()
        let proxy = ProfileOrderTicketReader(target: try makeTarget(origin, tickets), origin: origin, tickets: tickets)
        let activeScope = proxy.scope; origin.isConfigured = false
        XCTAssertFalse(proxy.isConfigured); XCTAssertFalse(proxy.isAuthenticated); XCTAssertNotEqual(proxy.scope, activeScope)
        do { _ = try await proxy.ticketDetail(id: 41); XCTFail() } catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        XCTAssertTrue(tickets.ids.isEmpty)
    }
    func testOriginRevocationAtReceiptRejectsFreshResponse() async throws {
        let origin = OrderTicketOriginFixture(), tickets = OrderTicketReaderFixture()
        let proxy = ProfileOrderTicketReader(target: try makeTarget(origin, tickets), origin: origin, tickets: tickets)
        tickets.onRead = { origin.isConfigured = false }
        do { _ = try await proxy.ticketDetail(id: 41); XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(tickets.ids, [41]); XCTAssertFalse(proxy.isConfigured)
    }
    func testTicketAccountScopeChangeRejectsLateResponse() async throws {
        let origin = OrderTicketOriginFixture(), tickets = OrderTicketReaderFixture()
        let proxy = ProfileOrderTicketReader(target: try makeTarget(origin, tickets), origin: origin, tickets: tickets)
        tickets.onRead = { tickets.scope = UUID() }
        do { _ = try await proxy.ticketDetail(id: 41); XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
    }
    func testRetirementRejectsLateSuccessAndLaterDispatch() async throws {
        let origin = OrderTicketOriginFixture(), tickets = OrderTicketReaderFixture()
        let proxy = ProfileOrderTicketReader(target: try makeTarget(origin, tickets), origin: origin, tickets: tickets)
        tickets.onRead = { proxy.retire() }
        do { _ = try await proxy.ticketDetail(id: 41); XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        do { _ = try await proxy.ticketDetail(id: 41); XCTFail() } catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        XCTAssertEqual(tickets.ids, [41])
    }
    func testStaleErrorIsCancelledAndWrongRegistrationReceiptIsRejected() async throws {
        let origin = OrderTicketOriginFixture(), tickets = OrderTicketReaderFixture()
        let proxy = ProfileOrderTicketReader(target: try makeTarget(origin, tickets), origin: origin, tickets: tickets)
        tickets.returnedID = 42
        do { _ = try await proxy.ticketDetail(id: 41); XCTFail() } catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
        tickets.failure = .unauthorized; tickets.onRead = { origin.identity = nil }
        do { _ = try await proxy.ticketDetail(id: 41); XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
    }
}

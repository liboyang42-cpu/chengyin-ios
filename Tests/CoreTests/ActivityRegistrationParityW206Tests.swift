#if DEBUG
import Foundation
import XCTest
@testable import QuestifyCore

/// Synthetic, in-memory registration boundary. No endpoint, credential or payment exists here.
@MainActor
private final class ParitySliceService: RegistrationCoordinatingService {
    var quoteJSON = #"{"payAmount":12.5,"pointsUsable":true,"quoteSign":"parity-fixture-sign"}"#
    var createError: Error?
    private(set) var quotes: [RegistrationQuoteRequest] = []
    private(set) var creates: [RegistrationCreateIntent] = []
    private(set) var reads: [Int] = []
    func quote(_ selection: RegistrationQuoteRequest, token: String) async throws -> RegistrationQuote {
        quotes.append(selection)
        return try JSONDecoder().decode(RegistrationQuote.self, from: Data(quoteJSON.utf8))
    }
    func create(_ intent: RegistrationCreateIntent, token: String) async throws -> RegistrationCreateResult {
        creates.append(intent)
        if let createError { throw createError }
        return try JSONDecoder().decode(RegistrationCreateResult.self, from: Data(#"{"registrationId":41,"payableAmount":12.5}"#.utf8))
    }
    func readStatus(registrationID: Int, token: String) async throws -> RegistrationStatusSnapshot {
        reads.append(registrationID)
        return try JSONDecoder().decode(RegistrationStatusSnapshot.self, from: Data(#"{"id":41,"registrationStatus":1,"paymentStatus":1}"#.utf8))
    }
}

@MainActor
private final class ParityOrderReader: ProfileReading {
    var identity: ProfileReadIdentity? = .init(accountID: 1, epoch: 1)
    var isConfigured = true
    var orders: [ProfileOrder] = []
    private(set) var orderListReads = 0
    func profileOrders() async throws -> [ProfileOrder] { orderListReads += 1; return orders }
    func profileOrder(id: Int) async throws -> ProfileOrder { throw APIError.invalidRequest }
    func profileParticipants() async throws -> [ProfileParticipant] { [] }
    func profileParticipant(id: Int) async throws -> ProfileParticipant { throw APIError.invalidRequest }
    func profileBadges() async throws -> ProfileBadgeWall { .init(identities: [], medals: []) }
}

@MainActor
final class ActivityRegistrationParityW206Tests: XCTestCase {
    private func detail(_ fields: String) throws -> ActivityDetail {
        try JSONDecoder().decode(ActivityDetail.self, from: Data("{\"id\":7,\"name\":\"Parity fixture\"\(fields)}".utf8))
    }
    private func quote(_ json: String) throws -> RegistrationQuote {
        try JSONDecoder().decode(RegistrationQuote.self, from: Data(json.utf8))
    }
    private func order(id: Int, member: Int = 1, owner: Int = 7, ticket: Int = 11, type: Int = 2) throws -> ProfileOrder {
        try JSONDecoder().decode(ProfileOrder.self, from: Data("""
        {"id":\(id),"memberId":\(member),"ownerType":\(type),"ownerId":\(owner),"ticketId":\(ticket),"registrationStatus":1,"paymentStatus":0}
        """.utf8))
    }
    private func makeFlow(_ service: ParitySliceService, policy: RegistrationUICreationPolicy? = .offlineFixture,
                          identity: @escaping () -> ProfileReadIdentity? = { .init(accountID: 1, epoch: 1) },
                          onReadback: @escaping (RegistrationStatusSnapshot) -> Void = { _ in }) throws -> RegistrationUIFlow {
        let coordinator = RegistrationCoordinator(service: service, makeRequestID: { "parity-fixture-intent" })
        try coordinator.setAccount(id: 1, token: "fixture-only-token")
        let activity = try detail(#","omsTicketList":[{"id":11,"name":"Parity ticket","price":12.5,"remainingInventory":3}]"#)
        if let policy {
            return RegistrationUIFlow(activity: activity, coordinator: coordinator, currentIdentity: identity,
                                      quoteEnabled: true, creationPolicy: policy, onReadback: onReadback)
        }
        return RegistrationUIFlow(activity: activity, coordinator: coordinator, currentIdentity: identity,
                                  quoteEnabled: true, onReadback: onReadback)
    }
    private func ready(_ flow: RegistrationUIFlow) async {
        flow.open(); flow.setName("Parity Person"); flow.setPhone("13800000000")
        flow.setConsent(true); await flow.requestQuote()
    }

    // MARK: Activity detail header (分类 / 集合点 / 已报名)

    func testCategoryTextJoinsSourceNamesAndKeepsMissingUnconfirmed() throws {
        let joined = ActivityDetailHeaderFacts(detail: try detail(#","sysCategoryList":[{"categoryName":"City walk"},{"categoryName":"  "},{"categoryName":"Puzzle"},{"categoryId":3}]"#))
        XCTAssertEqual(joined.categoryText, "City walk · Puzzle")
        XCTAssertNil(ActivityDetailHeaderFacts(detail: try detail("")).categoryText)
        XCTAssertNil(ActivityDetailHeaderFacts(detail: try detail(#","sysCategoryList":[]"#)).categoryText)
    }

    func testMeetingPointFollowsSourcePrecedenceAndNeverInventsAPlace() throws {
        XCTAssertEqual(ActivityDetailHeaderFacts(detail: try detail(#","addressName":" Gate A ","address":"1 Road""#)).meetingPoint, .named("Gate A"))
        XCTAssertEqual(ActivityDetailHeaderFacts(detail: try detail(#","addressName":" ","address":"1 Road""#)).meetingPoint, .named("1 Road"))
        XCTAssertEqual(ActivityDetailHeaderFacts(detail: try detail(#","latitude":30.1,"longitude":120.2"#)).meetingPoint, .mapOnly)
        XCTAssertEqual(ActivityDetailHeaderFacts(detail: try detail(#","latitude":300,"longitude":120.2"#)).meetingPoint, .unconfirmed)
        XCTAssertEqual(ActivityDetailHeaderFacts(detail: try detail("")).meetingPoint, .unconfirmed)
    }

    func testRegistrationCountIsSourceTotalAndUnknownIsNotZero() throws {
        XCTAssertEqual(ActivityDetailHeaderFacts(detail: try detail(#","registrationCount":12,"registrationList":[{"id":1,"memberId":2,"nickname":"A"}]"#)).registrationCount, 12)
        XCTAssertNil(ActivityDetailHeaderFacts(detail: try detail(#","registrationList":[{"id":1,"memberId":2,"nickname":"A"}]"#)).registrationCount)
        XCTAssertNil(ActivityDetailHeaderFacts(detail: try detail(#","registrationCount":-1"#)).registrationCount)
        XCTAssertEqual(ActivityDetailHeaderFacts(detail: try detail(#","registrationCount":0"#)).registrationCount, 0)
    }

    func testSourceDetailSectionOrderPlacesMetaBetweenCancellationAndAbout() throws {
        let order = ActivityDetailSourceSection.allCases
        XCTAssertEqual(order.first, .header)
        XCTAssertLessThan(try XCTUnwrap(order.firstIndex(of: .cancelled)), try XCTUnwrap(order.firstIndex(of: .meta)))
        XCTAssertLessThan(try XCTUnwrap(order.firstIndex(of: .meta)), try XCTUnwrap(order.firstIndex(of: .about)))
        XCTAssertLessThan(try XCTUnwrap(order.firstIndex(of: .about)), try XCTUnwrap(order.firstIndex(of: .tickets)))
    }

    // MARK: Checkout (结算) facts

    func testAlreadyRegisteredBannerRequiresExactSourceFlag() throws {
        XCTAssertTrue(RegistrationCheckoutFacts(activity: try detail(#","isSignUp":1"#), ticket: nil).viewerAlreadyRegistered)
        for fields in ["", #","isSignUp":0"#, #","isSignUp":"1""#, #","isSignUp":2"#, #","isSignUp":null"#] {
            XCTAssertFalse(RegistrationCheckoutFacts(activity: try detail(fields), ticket: nil).viewerAlreadyRegistered, fields)
        }
    }

    func testTicketMeetingPointVenueAndOrderAmountStayUnknownWhenAbsent() throws {
        let activity = try detail(#","addressName":"Venue name","address":"Venue address","omsTicketList":[{"id":11,"name":"A","price":18,"meetingPoint":" North gate "},{"id":12,"name":"B","price":null,"meetingPoint":"  "},{"id":13,"name":"C","meetingPoint":5}]"#)
        XCTAssertEqual(activity.tickets.count, 3, "A malformed optional meeting point must not drop a ticket")
        let first = RegistrationCheckoutFacts(activity: activity, ticket: activity.tickets[0])
        XCTAssertEqual(first.meetingPoint, "North gate")
        XCTAssertEqual(first.venue, "Venue address", "Checkout source prefers address over addressName")
        XCTAssertEqual(first.orderAmount, Decimal(18))
        let second = RegistrationCheckoutFacts(activity: activity, ticket: activity.tickets[1])
        XCTAssertNil(second.meetingPoint); XCTAssertNil(second.orderAmount)
        XCTAssertNil(RegistrationCheckoutFacts(activity: activity, ticket: activity.tickets[2]).meetingPoint)
        let bare = RegistrationCheckoutFacts(activity: try detail(""), ticket: nil)
        XCTAssertNil(bare.venue); XCTAssertNil(bare.orderAmount); XCTAssertNil(bare.meetingPoint)
        XCTAssertEqual(RegistrationCheckoutFacts(activity: try detail(#","addressName":"Only name""#), ticket: nil).venue, "Only name")
    }

    func testClubBenefitUsesOnlyExplicitQuoteFields() throws {
        XCTAssertEqual(RegistrationCheckoutClubBenefit.from(try quote(#"{"payAmount":10,"memberDiscountYuan":2.5,"prioritySignupEnabled":true,"quoteSign":"s"}"#)), .discount(Decimal(string: "2.5")!))
        XCTAssertEqual(RegistrationCheckoutClubBenefit.from(try quote(#"{"payAmount":10,"memberDiscountYuan":0,"prioritySignupEnabled":true,"clubMember":true,"quoteSign":"s"}"#)), .priorityActive)
        XCTAssertEqual(RegistrationCheckoutClubBenefit.from(try quote(#"{"payAmount":10,"prioritySignupEnabled":true,"quoteSign":"s"}"#)), .priorityReserved)
        XCTAssertNil(RegistrationCheckoutClubBenefit.from(try quote(#"{"payAmount":10,"quoteSign":"s"}"#)))
        let malformed = try quote(#"{"payAmount":10,"prioritySignupEnabled":"true","clubMember":true,"quoteSign":"s"}"#)
        XCTAssertFalse(malformed.prioritySignupEnabled)
        XCTAssertNil(RegistrationCheckoutClubBenefit.from(malformed))
        XCTAssertEqual(RegistrationCheckoutClubBenefit.priorityActive.noteKey, "registrationParity.clubPriorityActive")
        XCTAssertEqual(RegistrationCheckoutClubBenefit.priorityReserved.noteKey, "registrationParity.clubPriorityReserved")
        XCTAssertNil(RegistrationCheckoutClubBenefit.discount(1).noteKey)
    }

    func testCheckoutSectionOrderMatchesSource() {
        XCTAssertEqual(RegistrationCheckoutSection.allCases,
                       [.alreadyRegistered, .participants, .activity, .ticket, .fees, .waitlist, .confirmation])
        XCTAssertEqual(RegistrationCheckoutFacts.sourceTitleKey, "registrationParity.title")
    }

    // MARK: discover → detail → quote → registration → order-status slice

    func testConfirmAndReadBackCreatesOnceAndReadsReturnedIDOnce() async throws {
        let service = ParitySliceService()
        var snapshots: [RegistrationStatusSnapshot] = []
        let flow = try makeFlow(service, onReadback: { snapshots.append($0) })
        await ready(flow)
        XCTAssertEqual(service.quotes.count, 1)
        await flow.confirmAndReadBack()
        XCTAssertTrue(service.creates.isEmpty, "Creation requires an explicit prepared review first")
        XCTAssertTrue(service.reads.isEmpty)
        XCTAssertTrue(flow.prepareConfirmation())
        await flow.confirmAndReadBack()
        XCTAssertEqual(service.creates.count, 1)
        XCTAssertEqual(service.creates.first?.requestID, "parity-fixture-intent")
        XCTAssertEqual(service.reads, [41])
        XCTAssertEqual(snapshots.map(\.registrationID), [41])
        guard case .responseReceived(let requestID, _) = flow.creationState else { return XCTFail("Expected create receipt") }
        XCTAssertEqual(requestID, "parity-fixture-intent")
        XCTAssertEqual(flow.coordinator.retainedIntent?.requestID, requestID)
        guard case .received(let snapshot) = flow.readbackState else { return XCTFail("Expected authoritative readback") }
        XCTAssertEqual(snapshot.registrationStatus, 1)
        // A repeated confirmation neither creates again nor re-reads the earlier intent.
        XCTAssertFalse(flow.prepareConfirmation())
        await flow.confirmAndReadBack()
        XCTAssertEqual(service.creates.count, 1); XCTAssertEqual(service.reads, [41])
        // Reopening keeps the same request identity and lock.
        flow.leave(); flow.open()
        XCTAssertEqual(flow.coordinator.retainedIntent?.requestID, "parity-fixture-intent")
        XCTAssertFalse(flow.canEdit)
    }

    func testCreationStaysDisabledByDefaultAndForDisabledPolicy() async throws {
        for policy in [nil, RegistrationUICreationPolicy.disabled] {
            let service = ParitySliceService()
            let flow = try makeFlow(service, policy: policy)
            XCTAssertEqual(flow.creationPolicy, .disabled)
            XCTAssertFalse(flow.creationPolicy.permitsCreation)
            await ready(flow)
            XCTAssertFalse(flow.consented, "Consent cannot be recorded while creation is disabled")
            XCTAssertEqual(flow.confirmationBlock, .creationDisabled)
            XCTAssertFalse(flow.prepareConfirmation())
            await flow.confirmAndReadBack()
            XCTAssertTrue(service.creates.isEmpty); XCTAssertTrue(service.reads.isEmpty)
        }
    }

    func testUnknownOutcomeStaysLockedAndOnlyReadsOwnedOrders() async throws {
        let service = ParitySliceService(); service.createError = URLError(.timedOut)
        let reader = ParityOrderReader()
        let flow = try makeFlow(service, identity: { reader.identity })
        let before = try await flow.uncertainOutcomeEvidence(orders: reader)
        XCTAssertEqual(before, .notApplicable); XCTAssertEqual(reader.orderListReads, 0)
        await ready(flow); XCTAssertTrue(flow.prepareConfirmation())
        await flow.confirmAndReadBack()
        guard case .outcomeUnknown(let requestID, _) = flow.creationState else { return XCTFail("Timeout must stay unknown") }
        XCTAssertEqual(requestID, "parity-fixture-intent")
        XCTAssertTrue(service.reads.isEmpty, "No registration ID exists to read")
        reader.orders = [try order(id: 40), try order(id: 44), try order(id: 45, member: 2),
                         try order(id: 46, owner: 8), try order(id: 47, ticket: 12), try order(id: 48, type: 1)]
        let evidence = try await flow.uncertainOutcomeEvidence(orders: reader)
        XCTAssertEqual(evidence, .matchingOrders([44, 40]))
        reader.orders = []
        let empty = try await flow.uncertainOutcomeEvidence(orders: reader)
        XCTAssertEqual(empty, .noMatchingOrder)
        XCTAssertEqual(reader.orderListReads, 2)
        // Evidence never unlocks or replays the retained intent.
        XCTAssertEqual(service.creates.count, 1)
        XCTAssertFalse(flow.prepareConfirmation()); await flow.confirmAndReadBack()
        XCTAssertEqual(service.creates.count, 1)
        XCTAssertEqual(flow.coordinator.retainedIntent?.requestID, "parity-fixture-intent")
        // A different reader account is not applicable and performs no read.
        let other = ParityOrderReader(); other.identity = .init(accountID: 2, epoch: 1)
        let mismatched = try await flow.uncertainOutcomeEvidence(orders: other)
        XCTAssertEqual(mismatched, .notApplicable); XCTAssertEqual(other.orderListReads, 0)
    }

    func testUncertainOutcomeMatcherRequiresOwnerTicketAndMember() throws {
        let selection = try RegistrationQuoteRequest(ownerID: 7, ticketID: 11)
        let intent = try RegistrationCreateIntent(selection: selection, quote: try quote(#"{"payAmount":1,"quoteSign":"s"}"#),
                                                  realName: "Parity Person", phone: "13800000000", requestID: "parity-matcher")
        let rows = [try order(id: 3), try order(id: 3), try order(id: 9, member: 4)]
        XCTAssertEqual(RegistrationUncertainOutcomeEvidence.match(orders: rows, intent: intent, accountID: 1), .matchingOrders([3]))
        XCTAssertEqual(RegistrationUncertainOutcomeEvidence.match(orders: [], intent: intent, accountID: 1), .noMatchingOrder)
    }
}
#endif

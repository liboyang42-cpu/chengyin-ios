import XCTest
@testable import QuestifyCore

@MainActor final class ClubInvitationFeedbackTests: XCTestCase {
    func testReceivedRequiresExactClubRecipientAndKeepsSourceOrder() throws {
        let f = FeedbackFixture(), merchant = f.replacing(f.row(3), ["toType": .string("merchant")])
        let value = try f.snapshot(received: [f.row(2), f.row(1, clubID: 82), merchant, f.row(4, topic: 999)])
        XCTAssertEqual(value.rows(in: .received).map { $0.id.invitationID }, [2, 4])
        XCTAssertTrue(value.rows(in: .sent).isEmpty)
    }
    func testSentUsesFreshClubTopicMembershipNotRecipientOrFromID() throws {
        let f = FeedbackFixture()
        let value = try f.snapshot(sent: [f.row(4, topic: 92, clubID: 999), f.row(5, topic: 999), f.replacing(f.row(6), ["fromId": .id(999)])])
        XCTAssertEqual(value.rows(in: .sent).map { $0.id.invitationID }, [4, 6])
    }
    func testSameIDInDifferentDirectionsStaysDistinctButDuplicateWithinDirectionFails() throws {
        let f = FeedbackFixture(), value = try f.snapshot(received: [f.row(1)], sent: [f.row(1)])
        XCTAssertEqual(Set(value.rows.map(\.id)).count, 2)
        XCTAssertThrowsError(try f.snapshot(received: [f.row(1), f.row(1)]))
    }
    func testUnknownStatusesStayUnknownRatherThanPending() throws {
        let f = FeedbackFixture()
        let rows = try f.snapshot(received: (0...5).map { f.row($0 + 1, status: .id($0)) } + [f.row(7, status: .null), f.row(8, status: .id(99))]).rows
        XCTAssertEqual(Array(rows.prefix(6)).compactMap(\.status), [0, 1, 2, 3, 4, 5])
        XCTAssertNil(rows[6].status); XCTAssertNil(rows[7].status); XCTAssertEqual(rows[6].statusKey, "club.inviteFeedback.status.unknown")
    }
    func testNamesFallbackByDirectionAndPrivateFieldsAreNotProjected() throws {
        let f = FeedbackFixture(), row = f.replacing(f.row(1), ["partner": .object(["phone": .string("PRIVATE_PHONE")]), "shareRate": .string("PRIVATE_TERMS")])
        let value = try f.snapshot(received: [row], sent: [row])
        XCTAssertEqual(value.rows[0].partnerName, "Topic 91"); XCTAssertNil(value.rows[1].partnerName)
        XCTAssertFalse(String(reflecting: value.rows).contains("PRIVATE_PHONE")); XCTAssertFalse(String(reflecting: value.rows).contains("PRIVATE_TERMS"))
        XCTAssertEqual(value.rows[0].message, "Invitation note")
    }
    func testMissingArraysMalformedRecordsAndBadScopedIDsFailNotEmpty() {
        let f = FeedbackFixture()
        for value: CoopFlowJSON in [.object([:]), .object(["received": .array([])]), f.value(received: [.null])] {
            XCTAssertThrowsError(try ClubInvitationFeedbackSnapshot(context: f.context, topics: f.access.topics(), invitations: value))
        }
        XCTAssertThrowsError(try f.snapshot(received: [f.row(0)]))
        XCTAssertTrue(try f.snapshot().rows.isEmpty)
    }
    func testTopicSnapshotWrongScopeOperationOrDuplicateIDFails() throws {
        let f = FeedbackFixture(), good = f.access.topics()
        for bad in [ClubGovernanceSnapshot(operation: .topics, scope: .init(clubID: 82), permissions: nil, value: good.value), .init(operation: .series, scope: good.scope, permissions: nil, value: good.value)] {
            XCTAssertThrowsError(try ClubInvitationFeedbackSnapshot(context: f.context, topics: bad, invitations: f.value()))
        }
        f.access.topicIDs = [91, 91]; XCTAssertThrowsError(try f.snapshot())
    }
    func testTargetsBindExactSourceContextNonceDirectionAndRow() throws {
        let f = FeedbackFixture(), scope = f.context, value = try f.snapshot(received: [f.row(1)]), nonce = UUID()
        let target = try XCTUnwrap(value.target(key: value.rows[0].id, context: scope, snapshotID: nonce))
        XCTAssertTrue(target.isCurrent(snapshot: value, context: scope, snapshotID: nonce))
        XCTAssertFalse(target.isCurrent(snapshot: value, context: scope, snapshotID: UUID()))
        XCTAssertFalse(target.isCurrent(snapshot: try f.snapshot(received: [f.row(1, status: .id(1))]), context: scope, snapshotID: nonce))
        f.access.authorizationGeneration = UUID()
        XCTAssertNil(value.target(key: value.rows[0].id, context: f.context, snapshotID: nonce))
        XCTAssertFalse(target.isCurrent(snapshot: value, context: f.context, snapshotID: nonce))
    }
    func testOwnerAndAllReaderIdentitiesMustAlign() throws {
        let f = FeedbackFixture(); XCTAssertTrue(f.context.canRead)
        f.club.returned = FeedbackClubReader.record(owner: false); XCTAssertFalse(f.context.canRead)
        XCTAssertThrowsError(try f.snapshot()); f.club.returned = FeedbackClubReader.record()
        f.flow.session = try .init(accountID: 702, epoch: 1, token: "synthetic"); XCTAssertFalse(f.context.canRead)
        f.flow.session = try .init(accountID: 701, epoch: 2, token: "synthetic"); XCTAssertFalse(f.context.canRead)
        f.flow.session = try .init(accountID: 701, epoch: 1, token: "synthetic"); f.access.identity = nil; XCTAssertFalse(f.context.canRead)
    }
    func testExistingReadWireContractsAreUnchanged() throws {
        XCTAssertEqual(CoopFlowRead.invitations.path, "api/coop/list"); XCTAssertEqual(try CoopFlowRead.invitations.body(), .object([:]))
        XCTAssertEqual(ClubGovernanceRead.topics.path, "api/club/topics")
        XCTAssertEqual(try ClubGovernanceRead.topics.fields(scope: .init(clubID: 81)), ["id": .integer(81)])
    }
}
@MainActor private final class FeedbackClubReader: ClubReading {
    var isClubConfigured = true
    var clubIdentity = ClubReadIdentity(accountID: 701, epoch: 1)
    var returned = FeedbackClubReader.record()
    var reads = 0
    static func record(id: Int = 81, owner: Bool = true) -> ClubRecord {
        try! JSONDecoder().decode(ClubRecord.self, from: Data("{\"id\":\(id),\"isOwner\":\(owner)}".utf8))
    }
    func clubDetail(id: Int) async throws -> ClubRecord { reads += 1; return returned }
    func clubMembers(id: Int) async throws -> ClubMemberDirectory { throw CoopFlowFailure.unavailable }
    func clubHome() async throws -> ClubHome { throw CoopFlowFailure.unavailable }
    func clubOwned() async throws -> [ClubRecord] { throw CoopFlowFailure.unavailable }
    func clubDirectory(name: String?) async throws -> [ClubRecord] { throw CoopFlowFailure.unavailable }
}
@MainActor private final class FeedbackFlowReader: CoopFlowReading {
    var session: CoopFlowSession? = try! .init(accountID: 701, epoch: 1, token: "synthetic")
    var resources: [CoopFlowRead] = []
    var value: CoopFlowJSON = .object(["received": .array([]), "sent": .array([])])
    var held = false
    var entered: (() -> Void)?
    var pending: [CheckedContinuation<CoopFlowJSON, Error>] = []
    func read(_ resource: CoopFlowRead) async throws -> CoopFlowJSON {
        resources.append(resource)
        if held { return try await withCheckedThrowingContinuation { pending.append($0); entered?() } }
        return value
    }
    func settlement(source: CoopFlowSettlement.Source, id: Int) async throws -> CoopFlowSettlement { throw CoopFlowFailure.unavailable }
}
@MainActor private final class FeedbackAccess: ClubGovernanceAccess {
    var identity: ClubReadIdentity? = .init(accountID: 701, epoch: 1)
    var isConfigured = true
    var storageNamespace = "synthetic-club-feedback"
    let allowsOfflineWrites = false
    var authorizationGeneration: UUID? = UUID()
    var resources: [ClubGovernanceRead] = []
    var sends = 0
    var failure: ClubGovernanceFailure?
    var topicIDs = [91, 92]
    func topics() -> ClubGovernanceSnapshot { .init(operation: .topics, scope: .init(clubID: 81), permissions: nil, value: .array(topicIDs.map { .object(["id": .integer($0)]) })) }
    func read(_ operation: ClubGovernanceRead, scope: ClubGovernanceScope, options: [String: ClubGovernanceValue]) async throws -> ClubGovernanceSnapshot {
        resources.append(operation); XCTAssertEqual(scope, .init(clubID: 81)); XCTAssertTrue(options.isEmpty)
        if let failure { throw failure }; return topics()
    }
    func send(_ review: ClubGovernanceReview) async throws -> ClubGovernanceValue { sends += 1; throw ClubGovernanceFailure.notConfigured }
}
@MainActor private final class FeedbackFixture {
    let club = FeedbackClubReader(), flow = FeedbackFlowReader(), access = FeedbackAccess()
    var context: ClubInvitationFeedbackContext { .init(club: club.returned, clubReader: club, reader: flow, access: access) }
    func row(_ id: Int, topic: Int = 91, clubID: Int = 81, status: CoopFlowJSON = .id(0)) -> CoopFlowJSON {
        .object(["id": .id(id), "topicId": .id(topic), "toType": .string("club"), "toId": .id(clubID), "status": status,
            "partner": .object(["name": .string("Partner \(id)")]), "topicName": .string("Topic \(topic)"), "createTime": .string("2026-10-11 09:00"), "message": .string("Invitation note")])
    }
    func value(received: [CoopFlowJSON] = [], sent: [CoopFlowJSON] = []) -> CoopFlowJSON { .object(["received": .array(received), "sent": .array(sent)]) }
    func snapshot(received: [CoopFlowJSON] = [], sent: [CoopFlowJSON] = []) throws -> ClubInvitationFeedbackSnapshot {
        try .init(context: context, topics: access.topics(), invitations: value(received: received, sent: sent))
    }
    func replacing(_ row: CoopFlowJSON, _ fields: [String: CoopFlowJSON]) -> CoopFlowJSON {
        guard case .object(let object) = row else { return row }; return .object(object.merging(fields) { _, new in new })
    }
}

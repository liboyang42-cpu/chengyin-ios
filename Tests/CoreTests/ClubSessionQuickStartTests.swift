import XCTest
@testable import QuestifyCore

@MainActor final class ClubSessionQuickStartTests: XCTestCase {
    func testTopicsPreserveOrderAndCooperativePublisherOrigin() throws {
        let f = QuickStartFixture(), rows = try f.topics().rows
        XCTAssertEqual(rows.map(\.id), [91, 92]); XCTAssertEqual(rows[0].name, "Own topic")
        XCTAssertEqual(rows[0].originKey(currentClubID: 81), "club.sessionStart.owned")
        XCTAssertEqual(rows[1].originKey(currentClubID: 81), "club.sessionStart.cooperative")
    }
    func testMissingNameOriginAndDatesRemainUnknown() throws {
        let f = QuickStartFixture(); f.access.rows = [.object(["id": .integer(93), "name": .string(" \n ")])]
        let row = try XCTUnwrap(f.topics().rows.first)
        XCTAssertNil(row.name); XCTAssertNil(row.originClubID); XCTAssertNil(row.startDate); XCTAssertNil(row.endDate)
        XCTAssertEqual(row.originKey(currentClubID: 81), "club.sessionStart.originUnknown")
    }
    func testServerDateTextPreservedWithoutTimezoneOrMissingDateGuess() throws {
        let f = QuickStartFixture(); f.access.rows = [.object(["id": .integer(93), "startDate": .string("2026-10-12T08:00:00+08:00"), "endDate": .string("2026-10-16")])]
        let row = try XCTUnwrap(f.topics().rows.first)
        XCTAssertEqual(row.startDate, "2026-10-12T08:00:00+08:00"); XCTAssertEqual(row.endDate, "2026-10-16")
    }
    func testInvalidDuplicateIDsAndMalformedListFailNotEmpty() throws {
        let f = QuickStartFixture(), context = f.context
        for rows: [ClubGovernanceValue] in [[.null], [.object([:])], [.object(["id": .integer(0)])], f.access.rows + f.access.rows] {
            f.access.rows = rows; XCTAssertThrowsError(try f.topics())
        }
        let good = try f.access.snapshot()
        XCTAssertThrowsError(try ClubSessionQuickStartTopics(context: context, snapshot: .init(operation: .eventTopics, scope: good.scope, permissions: good.permissions, value: .object([:]))))
        f.access.rows = []; XCTAssertTrue(try f.topics().rows.isEmpty)
    }
    func testExactScopeOperationAndFreshActivityPermissionRequired() throws {
        let f = QuickStartFixture()
        for snapshot in [try f.access.snapshot(operation: .topics), try f.access.snapshot(scope: .init(clubID: 82)), try f.access.snapshot(scope: .init(clubID: 81, topicID: 91))] {
            XCTAssertThrowsError(try ClubSessionQuickStartTopics(context: f.context, snapshot: snapshot))
        }
        f.access.permitted = false; XCTAssertThrowsError(try f.topics())
        let snapshot = try f.access.snapshot(); XCTAssertThrowsError(try ClubSessionQuickStartTopics(context: f.context, snapshot: .init(operation: .eventTopics, scope: snapshot.scope, permissions: nil, value: snapshot.value)))
    }
    func testOwnerGateDoesNotExpandToActivityAdminOrSignedOut() {
        let f = QuickStartFixture()
        f.reader.club = QuickStartReader.record(owner: false, admin: true); XCTAssertFalse(f.context.canRead)
        f.reader.club = QuickStartReader.record(); f.reader.clubIdentity = .init(accountID: nil, epoch: 1); XCTAssertFalse(f.context.canRead)
        f.reader.clubIdentity = .init(accountID: 702, epoch: 1); XCTAssertFalse(f.context.canRead)
        f.reader.clubIdentity = .init(accountID: 701, epoch: 1); f.access.isConfigured = false; XCTAssertFalse(f.context.canRead)
    }
    func testContextFencesReaderNamespaceAuthorityEpochAndRevision() {
        let f = QuickStartFixture(), c = f.context
        XCTAssertTrue(c.matches(reader: f.reader, access: f.access, viewerRevision: f.revision))
        XCTAssertFalse(c.matches(reader: QuickStartReader(), access: f.access, viewerRevision: f.revision))
        XCTAssertFalse(c.matches(reader: f.reader, access: QuickStartAccess(), viewerRevision: f.revision))
        XCTAssertFalse(c.matches(reader: f.reader, access: f.access, viewerRevision: 8))
        f.access.storageNamespace = "other"; XCTAssertFalse(c.matches(reader: f.reader, access: f.access, viewerRevision: 7))
        f.access.storageNamespace = c.namespace; f.access.authorizationGeneration = UUID(); XCTAssertFalse(c.matches(reader: f.reader, access: f.access, viewerRevision: 7))
        f.access.authorizationGeneration = c.authorizationGeneration; f.reader.clubIdentity = .init(accountID: 701, epoch: 2); XCTAssertFalse(c.matches(reader: f.reader, access: f.access, viewerRevision: 7))
    }
    func testOnlyReturnedTopicCreatesExactClubScopeAndONCESeed() throws {
        let f = QuickStartFixture(), topics = try f.topics(), nonce = UUID(), c = f.context
        let target = try XCTUnwrap(topics.target(topicID: 92, context: c, snapshotID: nonce))
        XCTAssertEqual(target.scope, .init(clubID: 81, topicID: 92)); XCTAssertEqual(target.seed, ["recurrenceType": .string("ONCE")])
        XCTAssertTrue(target.isCurrent(topics: topics, context: c, snapshotID: nonce))
        XCTAssertNil(topics.target(topicID: 999, context: c, snapshotID: nonce))
        XCTAssertFalse(target.isCurrent(topics: topics, context: c, snapshotID: UUID()))
        f.access.rows.removeLast(); XCTAssertFalse(target.isCurrent(topics: try f.topics(), context: c, snapshotID: nonce))
    }
    func testTargetCannotCrossContextEvenWithIdenticalTopicRows() throws {
        let f = QuickStartFixture(), old = f.context, topics = try f.topics(), nonce = UUID()
        let target = try XCTUnwrap(topics.target(topicID: 91, context: old, snapshotID: nonce))
        f.revision += 1
        XCTAssertNil(topics.target(topicID: 91, context: f.context, snapshotID: nonce))
        XCTAssertFalse(target.isCurrent(topics: try f.topics(), context: old, snapshotID: nonce))
        XCTAssertFalse(target.isCurrent(topics: topics, context: f.context, snapshotID: nonce))
    }
    func testUsesExistingReadAndFormWithoutInventedLeadOrCommand() throws {
        let f = QuickStartFixture(), target = try XCTUnwrap(f.topics().target(topicID: 92, context: f.context, snapshotID: UUID()))
        XCTAssertEqual(ClubGovernanceRead.eventTopics.path, "api/club/event-ops/topics")
        XCTAssertEqual(try ClubGovernanceRead.eventTopics.fields(scope: .init(clubID: 81)), ["clubId": .integer(81)])
        let draft = ClubGovernanceFormDraft(operation: .createSeries, scope: target.scope, seed: target.seed)
        XCTAssertEqual(draft.text["recurrenceType"], "ONCE"); XCTAssertEqual(draft.text["defaultLeadMemberId"], "")
        XCTAssertThrowsError(try draft.command()); XCTAssertEqual(f.access.sends, 0)
    }
}
@MainActor private final class QuickStartReader: ClubReading {
    var isClubConfigured = true
    var clubIdentity = ClubReadIdentity(accountID: 701, epoch: 1)
    var club = QuickStartReader.record()
    var reads = 0
    var held = false
    var failure = false
    var entered: (() -> Void)?
    var pending: [CheckedContinuation<ClubRecord, Error>] = []
    static func record(id: Int = 81, owner: Bool = true, admin: Bool = false) -> ClubRecord {
        try! JSONDecoder().decode(ClubRecord.self, from: Data("{\"id\":\(id),\"isOwner\":\(owner),\"viewerIsAdmin\":\(admin)}".utf8))
    }
    func clubDetail(id: Int) async throws -> ClubRecord {
        reads += 1; XCTAssertEqual(id, 81)
        if held { return try await withCheckedThrowingContinuation { pending.append($0); entered?() } }
        if failure { throw ClubGovernanceFailure.malformed }; return club
    }
    func clubMembers(id: Int) async throws -> ClubMemberDirectory { throw ClubGovernanceFailure.notConfigured }
    func clubHome() async throws -> ClubHome { throw ClubGovernanceFailure.notConfigured }
    func clubOwned() async throws -> [ClubRecord] { throw ClubGovernanceFailure.notConfigured }
    func clubDirectory(name: String?) async throws -> [ClubRecord] { throw ClubGovernanceFailure.notConfigured }
}
@MainActor private final class QuickStartAccess: ClubGovernanceAccess {
    var identity: ClubReadIdentity? = .init(accountID: 701, epoch: 1)
    var isConfigured = true
    var storageNamespace = "synthetic-session-start"
    let allowsOfflineWrites = false
    var authorizationGeneration: UUID? = UUID()
    var resources: [ClubGovernanceRead] = []
    var sends = 0
    var permitted = true
    var failure = false
    var held = false
    var entered: (() -> Void)?
    var pending: [CheckedContinuation<ClubGovernanceSnapshot, Error>] = []
    var rows: [ClubGovernanceValue] = [.object(["id": .integer(91), "clubId": .integer(81), "name": .string(" Own topic ")]),
                                     .object(["id": .integer(92), "clubId": .integer(82), "name": .string("Cooperative topic")])]
    func snapshot(operation: ClubGovernanceRead = .eventTopics, scope: ClubGovernanceScope = .init(clubID: 81)) throws -> ClubGovernanceSnapshot {
        let permissions = try ClubGovernancePermissions(value: .object(["active": .bool(true), "club": .object(["id": .integer(81)]),
            "roleCodes": .array([]), "permissions": .array(permitted ? [.string("club:activity:manage")] : []), "canManageRoles": .bool(false)]), scope: .init(clubID: 81))
        return .init(operation: operation, scope: scope, permissions: permissions, value: .array(rows))
    }
    func read(_ operation: ClubGovernanceRead, scope: ClubGovernanceScope, options: [String: ClubGovernanceValue]) async throws -> ClubGovernanceSnapshot {
        resources.append(operation); XCTAssertEqual(operation, .eventTopics); XCTAssertEqual(scope, .init(clubID: 81)); XCTAssertTrue(options.isEmpty)
        if held { return try await withCheckedThrowingContinuation { pending.append($0); entered?() } }
        if failure { throw ClubGovernanceFailure.malformed }; return try snapshot()
    }
    func send(_ review: ClubGovernanceReview) async throws -> ClubGovernanceValue { sends += 1; throw ClubGovernanceFailure.notConfigured }
}
@MainActor private final class QuickStartFixture {
    let reader = QuickStartReader(), access = QuickStartAccess()
    var revision: UInt64 = 7
    var context: ClubSessionQuickStartContext { .init(club: reader.club, reader: reader, access: access, viewerRevision: revision) }
    func topics() throws -> ClubSessionQuickStartTopics { try .init(context: context, snapshot: access.snapshot()) }
}

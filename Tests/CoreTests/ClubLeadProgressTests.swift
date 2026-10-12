import XCTest
@testable import QuestifyCore

@MainActor final class ClubLeadProgressTests: XCTestCase {
    func testEmptyTopicsPublishEvenWithOtherProjectRecords() throws {
        let f = LeadFixture(); f.access.topicIDs = []; f.projects.page = f.page([f.project(1, accepted: true)])
        let s = try f.snapshot(); XCTAssertEqual(s.stage, .publish); XCTAssertEqual(s.topicCount, 0)
        XCTAssertEqual(s.nodes.map(\.state), [.doing, .todo, .todo, .todo])
    }
    func testInviteAndPendingStagesUseOnlyCurrentClubTopics() throws {
        let f = LeadFixture()
        XCTAssertEqual(try f.snapshot(sent: [f.row(1, topic: 999)]).stage, .invite)
        let s = try f.snapshot(sent: [f.row(1), f.row(2, topic: 999), f.row(3, topic: 92, status: .id(2))])
        XCTAssertEqual(s.stage, .pending); XCTAssertEqual(s.sentCount, 2); XCTAssertEqual(s.pendingCount, 1)
        XCTAssertEqual(s.nodes.map(\.state), [.done, .done, .doing, .todo])
    }
    func testOnlyCurrentClubNonActivityAcceptedProjectsAdvanceStage() throws {
        let f = LeadFixture()
        f.projects.page = f.page([f.project(1, club: 82, accepted: true), f.project(2, kind: "activity", accepted: true)])
        XCTAssertEqual(try f.snapshot().stage, .invite)
        f.projects.page = f.page([f.project(1, accepted: true)])
        let s = try f.snapshot(sent: [f.row(1)])
        XCTAssertEqual(s.stage, .accepted); XCTAssertEqual(s.nodes.map(\.state), [.done, .done, .done, .done])
    }
    func testAcceptedExecutionRequiresRecipientAndOwnerManageTopicAndSuppressesTimeline() throws {
        let f = LeadFixture()
        XCTAssertEqual(try f.snapshot(received: [f.row(1, topic: 999, status: .id(1)), f.row(2, clubID: 82, status: .id(1))]).stage, .invite)
        let s = try f.snapshot(received: [f.row(1, status: .id(1))])
        XCTAssertEqual(s.stage, .executionAccepted); XCTAssertTrue(s.nodes.isEmpty)
    }
    func testExecutionAcceptanceTakesPrecedenceOverMerchantAcceptance() throws {
        let f = LeadFixture(); f.projects.page = f.page([f.project(1, accepted: true)])
        XCTAssertEqual(try f.snapshot(received: [f.row(1, status: .id(1))]).stage, .executionAccepted)
    }
    func testPartialProjectPageCannotInferNoAcceptanceOrPendingAsFinalStage() throws {
        let f = LeadFixture(); f.projects.page = f.page([], total: 201)
        let s = try f.snapshot(sent: [f.row(1)])
        XCTAssertTrue(s.hasPartialProjects); XCTAssertEqual(s.stage, .partial); XCTAssertTrue(s.nodes.isEmpty)
        XCTAssertEqual(s.pendingCount, 1)
    }
    func testPositiveAcceptanceStillVisibleWithPartialWarning() throws {
        let f = LeadFixture(); f.projects.page = f.page([f.project(1, accepted: true)], total: 201)
        let s = try f.snapshot(); XCTAssertTrue(s.hasPartialProjects); XCTAssertEqual(s.stage, .accepted)
        f.access.topicIDs = []; XCTAssertEqual(try f.snapshot().stage, .publish)
    }
    func testUnknownInvitationStatusIsNeitherPendingNorAccepted() throws {
        let f = LeadFixture()
        let s = try f.snapshot(received: [f.row(1, status: .null)], sent: [f.row(2, status: .id(99))])
        XCTAssertEqual(s.stage, .invite); XCTAssertEqual(s.pendingCount, 0)
    }
    func testTimelineInvitationTimeFollowsMiniMonthDayDisplayOnly() throws {
        let f = LeadFixture()
        let a = f.replacing(f.row(1), ["createTime": .string("2026-09-12 10:30:00")])
        let b = f.replacing(f.row(2), ["createTime": .string("2026-10-11 09:00:00")])
        XCTAssertEqual(try f.snapshot(sent: [b, a]).invitationTimeText, "10-11 09:00")
        XCTAssertNil(try f.snapshot().invitationTimeText)
    }
    func testWrongTopicsOrMalformedInvitationPayloadFailInsteadOfStage() {
        let f = LeadFixture()
        XCTAssertThrowsError(try ClubLeadProgressSnapshot(context: f.context, topics: .init(operation: .topics, scope: .init(clubID: 82), permissions: nil, value: .array([])), invitations: f.value(), projects: f.projects.page))
        XCTAssertThrowsError(try ClubLeadProgressSnapshot(context: f.context, topics: f.access.topics(), invitations: .object([:]), projects: f.projects.page))
    }
    func testProjectScopeReaderAuthenticationAndConfigurationFenceContext() {
        let f = LeadFixture(), c = f.context
        XCTAssertTrue(c.matches(clubReader: f.club, reader: f.flow, access: f.access, projects: f.projects))
        f.projects.scope = UUID(); XCTAssertFalse(c.matches(clubReader: f.club, reader: f.flow, access: f.access, projects: f.projects))
        f.projects.isAuthenticated = false; XCTAssertFalse(f.context.canRead)
        f.projects.isAuthenticated = true; f.projects.isConfigured = false; XCTAssertFalse(f.context.canRead)
        f.projects.isConfigured = true; f.projects.isOfflineExample = true; XCTAssertFalse(f.context.canRead)
    }
    func testOwnerAndNamespaceAuthorityChangesRetireProgress() {
        let f = LeadFixture(), c = f.context
        f.access.storageNamespace = "other"; XCTAssertFalse(c.matches(clubReader: f.club, reader: f.flow, access: f.access, projects: f.projects))
        f.access.storageNamespace = c.feedback.namespace; f.access.authorizationGeneration = UUID()
        XCTAssertFalse(c.matches(clubReader: f.club, reader: f.flow, access: f.access, projects: f.projects))
        f.club.returned = LeadClubReader.record(owner: false); XCTAssertFalse(f.context.canRead)
    }
}
@MainActor private final class LeadClubReader: ClubReading {
    var isClubConfigured = true
    var clubIdentity = ClubReadIdentity(accountID: 701, epoch: 1)
    var returned = LeadClubReader.record()
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
@MainActor private final class LeadFlowReader: CoopFlowReading {
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
@MainActor private final class LeadAccess: ClubGovernanceAccess {
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
@MainActor private final class LeadFixture {
    let club = LeadClubReader(), flow = LeadFlowReader(), access = LeadAccess(), projects = LeadProjectReader()
    var context: ClubLeadProgressContext { .init(club: club.returned, clubReader: club, reader: flow, access: access, projects: projects) }
    func row(_ id: Int, topic: Int = 91, clubID: Int = 81, status: CoopFlowJSON = .id(0)) -> CoopFlowJSON {
        .object(["id": .id(id), "topicId": .id(topic), "toType": .string("club"), "toId": .id(clubID), "status": status,
            "partner": .object(["name": .string("Partner \(id)")]), "topicName": .string("Topic \(topic)"), "createTime": .string("2026-10-11 09:00"), "message": .string("Invitation note")])
    }
    func value(received: [CoopFlowJSON] = [], sent: [CoopFlowJSON] = []) -> CoopFlowJSON { .object(["received": .array(received), "sent": .array(sent)]) }
    func snapshot(received: [CoopFlowJSON] = [], sent: [CoopFlowJSON] = []) throws -> ClubLeadProgressSnapshot {
        try .init(context: context, topics: access.topics(), invitations: value(received: received, sent: sent), projects: projects.page)
    }
    func project(_ id: Int, club: Int = 81, kind: String = "topic", accepted: Bool = false) -> CreatorContentProject {
        try! JSONDecoder().decode(CreatorContentProject.self, from: Data("{\"id\":\(id),\"bizType\":\"\(kind)\",\"clubId\":\(club),\"acceptStatus\":\"\(accepted ? "merchantAccepted" : "pending")\"}".utf8))
    }
    func page(_ rows: [CreatorContentProject], total: Int? = nil) -> CreatorContentProjectPage { .init(rows: rows, total: total ?? rows.count) }
    func replacing(_ row: CoopFlowJSON, _ fields: [String: CoopFlowJSON]) -> CoopFlowJSON {
        guard case .object(let object) = row else { return row }; return .object(object.merging(fields) { _, new in new })
    }
}

@MainActor private final class LeadProjectReader: CreatorContentReading {
    var scope = UUID()
    var isConfigured = true
    var isAuthenticated = true
    var isOfflineExample = false
    var page = CreatorContentProjectPage(rows: [], total: 0)
    var queries: [CreatorContentQuery] = []
    var failure = false
    var held = false
    var entered: (() -> Void)?
    var pending: [CheckedContinuation<CreatorContentProjectPage, Error>] = []
    func projects(query: CreatorContentQuery) async throws -> CreatorContentProjectPage {
        queries.append(query)
        if held { return try await withCheckedThrowingContinuation { pending.append($0); entered?() } }
        if failure { throw CreatorContentReadFailure.unavailable }
        return page
    }
    func center() async throws -> CreatorContentCenter { throw CreatorContentReadFailure.unavailable }
}

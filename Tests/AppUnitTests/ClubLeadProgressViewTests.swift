import XCTest
@testable import Questify

@MainActor final class ClubLeadProgressViewTests: XCTestCase {
    private func activate(_ model: ClubLeadProgressReadModel, _ f: LeadFixture) throws -> ClubLeadProgressReadModel.Permit {
        model.bind(f.context); return try XCTUnwrap(model.activate(f.context))
    }
    private func load(_ model: ClubLeadProgressReadModel, _ f: LeadFixture, _ permit: ClubLeadProgressReadModel.Permit) async {
        await model.load(permit, clubReader: f.club, reader: f.flow, access: f.access, projects: f.projects)
    }
    private func accepted(_ model: ClubLeadProgressReadModel, _ f: LeadFixture) -> ClubLeadProgressSnapshot? {
        model.accepted(f.context, clubReader: f.club, reader: f.flow, access: f.access, projects: f.projects)
    }
    func testNormalReadUsesExactExistingOwnerProjectQueryAndZeroWrites() async throws {
        let f = LeadFixture(), m = ClubLeadProgressReadModel(), p = try activate(m, f)
        await load(m, f, p)
        XCTAssertEqual(f.club.reads, 1); XCTAssertEqual(f.access.resources, [.topics]); XCTAssertEqual(f.flow.resources, [.invitations])
        XCTAssertEqual(f.projects.queries, [.init(type: "all", state: "all", ownerType: "club")])
        XCTAssertEqual(accepted(m, f)?.stage, .invite); XCTAssertEqual(f.access.sends, 0)
    }
    func testFreshOwnerLossStopsPrivateReads() async throws {
        let f = LeadFixture(), m = ClubLeadProgressReadModel(), p = try activate(m, f)
        f.club.returned = LeadClubReader.record(owner: false); await load(m, f, p)
        XCTAssertEqual(m.phase, .denied); XCTAssertTrue(f.projects.queries.isEmpty); XCTAssertTrue(f.access.resources.isEmpty)
    }
    func testRefreshClearsPriorStageAndProjectFailureIsNotEmptyPublish() async throws {
        let f = LeadFixture(), m = ClubLeadProgressReadModel(), p = try activate(m, f)
        await load(m, f, p); XCTAssertNotNil(accepted(m, f))
        f.projects.failure = true; await load(m, f, p)
        XCTAssertEqual(m.phase, .failed); XCTAssertNil(m.snapshot)
        f.projects.failure = false; await load(m, f, p); XCTAssertEqual(m.phase, .ready)
    }
    func testTopicFailureStopsFollowingSourcesAndRetryRecovers() async throws {
        let f = LeadFixture(), m = ClubLeadProgressReadModel(), p = try activate(m, f)
        f.access.failure = .malformed; await load(m, f, p)
        XCTAssertEqual(m.phase, .failed); XCTAssertTrue(f.projects.queries.isEmpty); XCTAssertTrue(f.flow.resources.isEmpty)
        f.access.failure = nil; await load(m, f, p); XCTAssertEqual(accepted(m, f)?.topicCount, 2)
    }
    func testReturnVisibilityRetiresOldRetryAndRechecksOwner() async throws {
        let f = LeadFixture(), m = ClubLeadProgressReadModel(), old = try activate(m, f)
        await load(m, f, old); m.leave(f.context); let new = try activate(m, f)
        await load(m, f, old); XCTAssertEqual(f.club.reads, 1); XCTAssertNil(m.snapshot)
        await load(m, f, new); XCTAssertEqual(f.club.reads, 2); XCTAssertEqual(m.phase, .ready)
    }
    func testProjectScopeChangeDuringSuspendedReadCannotPublish() async throws {
        let f = LeadFixture(), m = ClubLeadProgressReadModel(), p = try activate(m, f)
        f.projects.held = true; let entered = expectation(description: "project read"); f.projects.entered = { entered.fulfill() }
        let task = Task { await self.load(m, f, p) }; await fulfillment(of: [entered], timeout: 1)
        f.projects.scope = UUID(); f.projects.pending[0].resume(returning: f.page([f.project(1, accepted: true)])); await task.value
        XCTAssertNil(m.snapshot); XCTAssertNil(accepted(m, f))
    }
    func testLatestReadWinsWhenOldProjectTransportDoesNotCancel() async throws {
        let f = LeadFixture(), m = ClubLeadProgressReadModel(), p = try activate(m, f)
        f.projects.held = true; let first = expectation(description: "first"), second = expectation(description: "second")
        f.projects.entered = { f.projects.pending.count == 1 ? first.fulfill() : second.fulfill() }
        let old = Task { await self.load(m, f, p) }; await fulfillment(of: [first], timeout: 1)
        let new = Task { await self.load(m, f, p) }; await fulfillment(of: [second], timeout: 1)
        f.projects.pending[1].resume(returning: f.page([f.project(1, accepted: true)])); await new.value
        f.projects.pending[0].resume(returning: f.page([])); await old.value
        XCTAssertEqual(accepted(m, f)?.stage, .accepted)
    }
    func testCancellationClearsLoadingWithoutPublishingSuspendedData() async throws {
        let f = LeadFixture(), m = ClubLeadProgressReadModel(), p = try activate(m, f)
        f.projects.held = true; let entered = expectation(description: "project"); f.projects.entered = { entered.fulfill() }
        let task = Task { await self.load(m, f, p) }; await fulfillment(of: [entered], timeout: 1)
        task.cancel(); f.projects.pending[0].resume(returning: f.page([])); await task.value
        XCTAssertEqual(m.phase, .idle); XCTAssertNil(m.snapshot)
    }
    func testAccountChangeAndProjectReaderReplacementHideReadyData() async throws {
        let f = LeadFixture(), m = ClubLeadProgressReadModel(), p = try activate(m, f), scope = f.context
        await load(m, f, p)
        XCTAssertNil(m.accepted(scope, clubReader: f.club, reader: f.flow, access: f.access, projects: LeadProjectReader()))
        f.club.clubIdentity = .init(accountID: 702, epoch: 2); XCTAssertNil(accepted(m, f))
    }
    func testPartialPageProducesPartialStateNotCompleteTimeline() async throws {
        let f = LeadFixture(), m = ClubLeadProgressReadModel(), p = try activate(m, f)
        f.projects.page = f.page([], total: 201); await load(m, f, p)
        let s = try XCTUnwrap(accepted(m, f)); XCTAssertEqual(s.stage, .partial); XCTAssertTrue(s.nodes.isEmpty)
        XCTAssertEqual(m.phase, .ready); XCTAssertEqual(f.access.sends, 0)
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

import XCTest
@testable import Questify

@MainActor final class ClubLeadPrimaryActionFlowTests: XCTestCase {
    private func start(_ f: PrimaryFixture? = nil) async throws -> PrimaryHarness {
        let h = PrimaryHarness(f ?? PrimaryFixture()); let initial = await h.refresh(); _ = try XCTUnwrap(initial); return h
    }
    func testNormalInviteReadRevalidateDestinationReturnRereadsSameClub() async throws {
        let h = try await start(); XCTAssertEqual(h.snapshot?.stage, .invite)
        await h.prepare(.invite)
        let route = try XCTUnwrap(h.controller.route)
        XCTAssertEqual(route.action, .merchants); XCTAssertEqual(route.context.feedback.clubID, 81)
        XCTAssertTrue(h.controller.accepts(route)); XCTAssertEqual(h.f.club.reads, 2)
        h.controller.dismiss(); _ = await h.refresh()
        XCTAssertNil(h.controller.route); XCTAssertEqual(h.f.club.reads, 3)
        XCTAssertEqual(h.f.access.resources, [.topics, .topics, .topics]); XCTAssertEqual(h.f.flow.resources, [.invitations, .invitations, .invitations])
        XCTAssertTrue(h.f.projects.queries.allSatisfy { $0 == .init(type: "all", state: "all", ownerType: "club") })
        XCTAssertEqual(h.f.access.sends, 0)
    }
    func testPublishUsesRealEmptyOwnerTopics() async throws {
        let f = PrimaryFixture(); f.access.topicIDs = []; let h = try await start(f)
        await h.prepare(.publish); XCTAssertEqual(h.controller.route?.action, .publish); XCTAssertEqual(f.access.sends, 0)
    }
    func testPendingUsesCurrentClubSentInvitations() async throws {
        let f = PrimaryFixture(); f.flow.value = f.value(sent: [f.row(1)]); let h = try await start(f)
        await h.prepare(.pending); XCTAssertEqual(h.controller.route?.action, .sentInvitations)
    }
    func testAcceptedProjectUsesExistingTopicManagement() async throws {
        let f = PrimaryFixture(); f.projects.page = f.page([f.project(1, accepted: true)]); let h = try await start(f)
        await h.prepare(.accepted); XCTAssertEqual(h.controller.route?.action, .topics)
    }
    func testExecutionAcceptedUsesExistingEventTopics() async throws {
        let f = PrimaryFixture(); f.flow.value = f.value(received: [f.row(1, status: .id(1))]); let h = try await start(f)
        await h.prepare(.executionAccepted); XCTAssertEqual(h.controller.route?.action, .events)
    }
    func testStageChangesRequireNewTapAndNeverNavigateOldDestination() async throws {
        let h = try await start(); h.f.flow.value = h.f.value(sent: [h.f.row(1)])
        await h.prepare(.invite); XCTAssertNil(h.controller.route); XCTAssertEqual(h.controller.notice, .changed)
        XCTAssertEqual(h.snapshot?.stage, .pending)
        await h.prepare(.pending); XCTAssertEqual(h.controller.route?.action, .sentInvitations)
    }
    func testPartialDisplayedStageCannotStartReadOrNavigate() async throws {
        let f = PrimaryFixture(); f.projects.page = f.page([], total: 201); let h = try await start(f)
        await h.prepare(.partial); XCTAssertNil(h.controller.route); XCTAssertEqual(f.club.reads, 1)
    }
    func testBecomingPartialOnFreshReadDoesNotNavigate() async throws {
        let h = try await start(); h.f.projects.page = h.f.page([], total: 201)
        await h.prepare(.invite); XCTAssertNil(h.controller.route); XCTAssertEqual(h.controller.notice, .changed)
    }
    func testOwnerLossStopsFollowingReadsAndRoute() async throws {
        let h = try await start(); h.f.club.returned = PrimaryClubReader.record(owner: false)
        await h.prepare(.invite); XCTAssertNil(h.controller.route); XCTAssertEqual(h.model.phase, .denied)
        XCTAssertEqual(h.f.projects.queries.count, 1); XCTAssertEqual(h.f.access.resources.count, 1)
    }
    func testFailureIsUnavailableNotEmptyPublish() async throws {
        let h = try await start(); h.f.projects.failure = true
        await h.prepare(.invite); XCTAssertNil(h.controller.route); XCTAssertEqual(h.controller.notice, .unavailable)
        h.f.projects.failure = false; await h.prepare(.invite); XCTAssertEqual(h.controller.route?.action, .merchants)
    }
    func testTopicFailureStopsInvitationAndProjectReads() async throws {
        let h = try await start(); h.f.access.failure = .malformed
        await h.prepare(.invite); XCTAssertNil(h.controller.route); XCTAssertEqual(h.f.flow.resources.count, 1)
        XCTAssertEqual(h.f.projects.queries.count, 1)
    }
    func testQueuedTapAfterLeaveAndSameContextReopenIsRejected() async throws {
        let h = try await start(); let old = try XCTUnwrap(h.controller.permit(in: h.context))
        h.controller.invalidate(); h.controller.activate(h.context)
        await h.controller.prepare(old, displayed: .invite, context: h.context, isCurrent: { true }, refresh: { await h.refresh() })
        XCTAssertEqual(h.f.club.reads, 1); XCTAssertNil(h.controller.route)
    }
    func testQueuedTapAfterDismissIsRejected() async throws {
        let h = try await start(); let old = try XCTUnwrap(h.controller.permit(in: h.context)); h.controller.dismiss()
        await h.controller.prepare(old, displayed: .invite, context: h.context, isCurrent: { true }, refresh: { await h.refresh() })
        XCTAssertEqual(h.f.club.reads, 1); XCTAssertNil(h.controller.route)
    }
    func testSameDisplayedStageDoesNotOverrideAccountFence() async throws {
        let h = try await start(); h.f.club.clubIdentity = .init(accountID: 702, epoch: 2)
        await h.prepare(.invite); XCTAssertNil(h.controller.route); XCTAssertEqual(h.f.club.reads, 1)
    }
    func testAuthorizationRotationRejectsTapBeforeRead() async throws {
        let h = try await start(); h.f.access.authorizationGeneration = UUID()
        await h.prepare(.invite); XCTAssertNil(h.controller.route); XCTAssertEqual(h.f.club.reads, 1)
    }
    func testNamespaceRotationRejectsTapBeforeRead() async throws {
        let h = try await start(); h.f.access.storageNamespace = "other"
        await h.prepare(.invite); XCTAssertNil(h.controller.route); XCTAssertEqual(h.f.club.reads, 1)
    }
    func testProjectScopeRotationRejectsTapBeforeRead() async throws {
        let h = try await start(); h.f.projects.scope = UUID()
        await h.prepare(.invite); XCTAssertNil(h.controller.route); XCTAssertEqual(h.f.club.reads, 1)
    }
    func testLateReadCannotRestoreRouteAfterLeaving() async throws {
        let h = try await start(); h.f.projects.held = true
        let entered = expectation(description: "held fresh project read"); h.f.projects.entered = { entered.fulfill() }
        let task = Task { await h.prepare(.invite) }; await fulfillment(of: [entered], timeout: 1)
        h.controller.invalidate(); h.f.projects.pending[0].resume(returning: h.f.page([])); await task.value
        XCTAssertNil(h.controller.route); XCTAssertFalse(h.controller.preparing)
    }
    func testScopeChangeDuringFreshReadCannotNavigate() async throws {
        let h = try await start(); h.f.projects.held = true
        let entered = expectation(description: "held fresh read"); h.f.projects.entered = { entered.fulfill() }
        let task = Task { await h.prepare(.invite) }; await fulfillment(of: [entered], timeout: 1)
        h.f.projects.scope = UUID(); h.f.projects.pending[0].resume(returning: h.f.page([])); await task.value
        XCTAssertNil(h.controller.route)
    }
    func testCancellationDoesNotNavigateOrLeaveSpinner() async throws {
        let h = try await start(); h.f.projects.held = true
        let entered = expectation(description: "held read"); h.f.projects.entered = { entered.fulfill() }
        let task = Task { await h.prepare(.invite) }; await fulfillment(of: [entered], timeout: 1)
        task.cancel(); h.f.projects.pending[0].resume(returning: h.f.page([])); await task.value
        XCTAssertNil(h.controller.route); XCTAssertFalse(h.controller.preparing)
    }
    func testDuplicateTapDuringPreparationCannotStartSecondRead() async throws {
        let h = try await start(); let queued = try XCTUnwrap(h.controller.permit(in: h.context)); h.f.projects.held = true
        let entered = expectation(description: "held read"); h.f.projects.entered = { entered.fulfill() }
        let task = Task { await h.prepare(.invite) }; await fulfillment(of: [entered], timeout: 1)
        XCTAssertNil(h.controller.permit(in: h.context))
        await h.controller.prepare(queued, displayed: .invite, context: h.context, isCurrent: { true }, refresh: { await h.refresh() })
        XCTAssertEqual(h.f.club.reads, 2); h.f.projects.pending[0].resume(returning: h.f.page([])); await task.value
        XCTAssertEqual(h.controller.route?.action, .merchants)
    }
    func testDestinationIsUnavailableByDefault() async throws {
        let h = try await start(); let destinations = ClubLeadPrimaryDestinations()
        XCTAssertNil(destinations.destination); XCTAssertFalse(destinations.isCurrent(h.context))
    }
    func testInvalidatedVisibleRouteCannotBeReused() async throws {
        let h = try await start(); await h.prepare(.invite); let route = try XCTUnwrap(h.controller.route)
        h.controller.invalidate(); h.controller.activate(h.context)
        XCTAssertFalse(h.controller.accepts(route)); XCTAssertNil(h.controller.route)
    }
    func testForeignClubOrNonOwnerContextCannotStart() async throws {
        let h = try await start(); h.f.club.returned = PrimaryClubReader.record(id: 82, owner: false)
        let other = h.f.context; h.controller.activate(other)
        XCTAssertNil(h.controller.permit(in: other)); XCTAssertNil(h.controller.route)
    }
}

@MainActor private final class PrimaryHarness {
    let f: PrimaryFixture
    let context: ClubLeadProgressContext
    let model = ClubLeadProgressReadModel()
    let controller = ClubLeadPrimaryActionController()
    init(_ fixture: PrimaryFixture) {
        f = fixture; context = fixture.context; model.bind(context); _ = model.activate(context); controller.activate(context)
    }
    var current: Bool { context.matches(clubReader: f.club, reader: f.flow, access: f.access, projects: f.projects) }
    var snapshot: ClubLeadProgressSnapshot? { model.accepted(context, clubReader: f.club, reader: f.flow, access: f.access, projects: f.projects) }
    func refresh() async -> ClubLeadProgressSnapshot? {
        guard let permit = model.permit(in: context) else { return nil }
        await model.load(permit, clubReader: f.club, reader: f.flow, access: f.access, projects: f.projects)
        return snapshot
    }
    func prepare(_ stage: ClubLeadProgressStage) async {
        guard let permit = controller.permit(in: context) else { return }
        await controller.prepare(permit, displayed: stage, context: context, isCurrent: { self.current }, refresh: { await self.refresh() })
    }
}
@MainActor private final class PrimaryClubReader: ClubReading {
    var isClubConfigured = true
    var clubIdentity = ClubReadIdentity(accountID: 701, epoch: 1)
    var returned = PrimaryClubReader.record()
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
@MainActor private final class PrimaryFlowReader: CoopFlowReading {
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
@MainActor private final class PrimaryAccess: ClubGovernanceAccess {
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
@MainActor private final class PrimaryFixture {
    let club = PrimaryClubReader(), flow = PrimaryFlowReader(), access = PrimaryAccess(), projects = PrimaryProjectReader()
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

@MainActor private final class PrimaryProjectReader: CreatorContentReading {
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

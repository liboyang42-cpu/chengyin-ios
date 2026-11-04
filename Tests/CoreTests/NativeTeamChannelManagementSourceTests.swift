import Foundation
import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

/// Authored offline tests. No live account, endpoint, credential or business mutation.
@MainActor final class NativeTeamChannelManagementSourceTests: XCTestCase {
    func testJoinedDetailUsesTeamIDNotItsActivityOwnerID() async throws {
        let h = try await TeamChannelSourceHarness.loaded()
        let source = try XCTUnwrap(h.source())
        XCTAssertEqual(source.scope.guildKind, 3)
        XCTAssertEqual(source.scope.guildID.rawValue, "4101")
        XCTAssertNotEqual(source.scope.guildID.rawValue, String(source.detail.team.ownerID!))
        XCTAssertTrue(source.isCurrent(for: source.scope))
    }
    func testLeaderIsNotRequiredAndDoesNotGrantChannelManagement() async throws {
        let h = try TeamChannelSourceHarness()
        h.reader.value = try teamChannelDetail(joined: true, leader: false)
        await h.flow.loadDetail(.id(4101))
        XCTAssertNotNil(h.source())
        XCTAssertTrue(h.reader.submissions.isEmpty)
    }
    func testInvitationsReadOnlyContinuationsAndAnotherIDHaveNoEntry() async throws {
        let h = try await TeamChannelSourceHarness.loaded()
        XCTAssertNil(NativeTeamChannelManagementSource(coordinator: h.flow, lookup: .invitation("SYNTHETIC-TEAM"), readOnly: false))
        XCTAssertNil(NativeTeamChannelManagementSource(coordinator: h.flow, lookup: .id(4101), readOnly: true))
        XCTAssertNil(NativeTeamChannelManagementSource(coordinator: h.flow, lookup: .id(4102), readOnly: false))
    }
    func testMissingOrRevokedMembershipNeverBecomesAuthority() async throws {
        for joined in [false, nil] as [Bool?] {
            let h = try TeamChannelSourceHarness()
            h.reader.value = try teamChannelDetail(joined: joined, leader: false)
            await h.flow.loadDetail(.id(4101))
            XCTAssertNil(h.source())
        }
    }
    func testCapturedSourceRejectsWrongKindAndWrongTeam() async throws {
        let h = try await TeamChannelSourceHarness.loaded(), source = try XCTUnwrap(h.source())
        XCTAssertFalse(source.isCurrent(for: try .init(guildKind: 1, guildID: .init("4101"))))
        XCTAssertFalse(source.isCurrent(for: try .init(guildKind: 3, guildID: .init("4102"))))
    }
    func testChildPushDoesNotEraseSourceAndBackCanReload() async throws {
        let h = try await TeamChannelSourceHarness.loaded(), source = try XCTUnwrap(h.source())
        h.flow.leaveScreen()
        XCTAssertTrue(source.isCurrent(for: source.scope))
        await h.flow.loadDetail(.id(4101))
        XCTAssertNotNil(h.source())
        XCTAssertEqual(h.reader.reads, 2)
    }
    func testChangedRosterInvalidatesRetainedSource() async throws {
        let h = try await TeamChannelSourceHarness.loaded(), source = try XCTUnwrap(h.source())
        h.reader.value = try teamChannelDetail(joined: true, leader: false)
        await h.flow.loadDetail(.id(4101))
        XCTAssertFalse(source.isCurrent(for: source.scope)); XCTAssertNotNil(h.source())
    }
    func testMembershipRevocationDropsEntryOnFreshRead() async throws {
        let h = try await TeamChannelSourceHarness.loaded(), source = try XCTUnwrap(h.source())
        h.reader.value = try teamChannelDetail(joined: false, leader: false)
        await h.flow.loadDetail(.id(4101))
        XCTAssertFalse(source.isCurrent(for: source.scope)); XCTAssertNil(h.source())
    }
    func testAccountRoleRegionAndEpochReplacementRejectOldSourceAfterFreshRead() async throws {
        for replacement in [try TeamSyntheticFixtures.session(accountID: 902),
                            try TeamSyntheticFixtures.session(epoch: 2),
                            try TeamSyntheticFixtures.session(region: "US"),
                            try TeamSyntheticFixtures.session(role: "merchant")] {
            let h = try await TeamChannelSourceHarness.loaded(), source = try XCTUnwrap(h.source())
            h.session = replacement
            XCTAssertFalse(source.isCurrent(for: source.scope)); XCTAssertNil(h.flow.detail)
            await h.flow.loadDetail(.id(4101))
            XCTAssertFalse(source.isCurrent(for: source.scope)); XCTAssertNotNil(h.source())
        }
    }
    func testSignOutAndApprovalWithdrawalCannotReviveOldSnapshot() async throws {
        let h = try await TeamChannelSourceHarness.loaded(), source = try XCTUnwrap(h.source())
        let previous = h.session
        h.session = nil // Same contract as a withdrawn TeamReadApproval closure.
        XCTAssertFalse(source.isCurrent(for: source.scope))
        h.session = previous
        await h.flow.loadDetail(.id(4101))
        XCTAssertFalse(source.isCurrent(for: source.scope)); XCTAssertNotNil(h.source())
    }
    func testLoadingAndFailedRefreshBlockCachedDetailUntilRecovery() async throws {
        let h = try await TeamChannelSourceHarness.loaded(), source = try XCTUnwrap(h.source())
        h.reader.beforeRead = { XCTAssertNil(h.source()); XCTAssertFalse(source.isCurrent(for: source.scope)) }
        h.reader.failure = TeamFailure.rejected(403)
        await h.flow.loadDetail(.id(4101))
        XCTAssertNotNil(h.flow.detail, "The source page may display its stale-read banner")
        XCTAssertNil(h.source()); XCTAssertFalse(source.isCurrent(for: source.scope))
        h.reader.beforeRead = nil; h.reader.failure = nil
        await h.flow.loadDetail(.id(4101)); XCTAssertNotNil(h.source())
    }
    func testUnresolvedMembershipOperationRetainsJournalAndBlocksEntry() async throws {
        let h = try await TeamChannelSourceHarness.loaded(), source = try XCTUnwrap(h.source())
        let original = TeamPendingRecord(operationID: UUID(), ownerKey: h.session!.ownerKey, targetKey: "team-4101")
        try h.journal.write(original); await h.flow.loadDetail(.id(4101))
        XCTAssertNil(h.source()); XCTAssertFalse(source.isCurrent(for: source.scope))
        XCTAssertEqual(h.flow.pending, original); XCTAssertEqual(h.journal.records.count, 1)
        XCTAssertTrue(h.reader.submissions.isEmpty)
    }
    func testOriginalReviewMustCloseBeforeChannelNavigation() async throws {
        let h = try await TeamChannelSourceHarness.loaded(), source = try XCTUnwrap(h.source())
        h.flow.prepare(.leave(teamID: 4101))
        XCTAssertNil(h.source()); XCTAssertFalse(source.isCurrent(for: source.scope))
        h.flow.cancelReview(); await h.flow.loadDetail(.id(4101))
        XCTAssertNotNil(h.source()); XCTAssertTrue(h.reader.submissions.isEmpty)
    }
    func testReleasedSourceScreenDoesNotStayAliveThroughRetainedClosure() async throws {
        var h: TeamChannelSourceHarness? = try await TeamChannelSourceHarness.loaded()
        let source = try XCTUnwrap(h?.source())
        weak var flow = h?.flow
        h = nil
        XCTAssertNil(flow); XCTAssertFalse(source.isCurrent(for: source.scope))
    }
}

@MainActor private final class TeamChannelSourceReader: TeamServing {
    var authority: TeamServiceAuthority = .readOnly
    var value: TeamDetail
    var failure: Error?
    var reads = 0
    var submissions: [UUID] = []
    var beforeRead: (() -> Void)?
    init() throws { value = try TeamSyntheticFixtures.detail() }
    func myTeams(session: TeamSession) async throws -> [OwnedTeam] { [] }
    func detail(_ lookup: TeamLookup, session: TeamSession) async throws -> TeamDetail {
        reads += 1; beforeRead?(); if let failure { throw failure }; return value
    }
    func creationContext(ownerID: Int, session: TeamSession) async throws -> TeamCreationContext { throw TeamFailure.notConfigured }
    func submit(_ action: TeamAction, operationID: UUID, session: TeamSession) async -> TeamWriteOutcome {
        submissions.append(operationID); return .notSent
    }
    func receipt(operationID: UUID, session: TeamSession) async throws -> TeamWriteOutcome? { nil }
}
@MainActor private final class TeamChannelSourceHarness {
    var session: TeamSession?
    let reader: TeamChannelSourceReader
    let journal = TeamMemoryJournal()
    lazy var flow = TeamCoordinator(service: reader, journal: journal, currentSession: { [weak self] in self?.session })
    init() throws { session = try TeamSyntheticFixtures.session(); reader = try TeamChannelSourceReader() }
    static func loaded() async throws -> TeamChannelSourceHarness {
        let h = try TeamChannelSourceHarness(); await h.flow.loadDetail(.id(4101)); return h
    }
    func source() -> NativeTeamChannelManagementSource? { .init(coordinator: flow, lookup: .id(4101), readOnly: false) }
}
private func teamChannelDetail(joined: Bool?, leader: Bool) throws -> TeamDetail {
    var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(TeamSyntheticFixtures.detailJSON.utf8)) as? [String: Any])
    raw["joined"] = joined; raw["leader"] = leader
    return try JSONDecoder().decode(TeamDetail.self, from: JSONSerialization.data(withJSONObject: raw))
}

extension NativeTeamChannelManagementSourceTests {
    func testNormalTeamSourceReadsActualDirectoryAndChannelContext() async throws {
        let team = try await TeamChannelSourceHarness.loaded(), source = try XCTUnwrap(team.source())
        let h = try TeamChannelDirectoryHarness(scope: source.scope)
        let flow = try h.makeFlow(); await flow.loadDirectory()
        XCTAssertEqual(flow.directory?.scope, source.scope)
        XCTAssertEqual(h.paths, ["/api/guilds/3/4101/channels"])
        XCTAssertFalse(flow.canCreate)
        let context = try await flow.service.currentChannelContext(channelID: .init("9012"))
        XCTAssertEqual(context.ownerType, "TEAM"); XCTAssertEqual(context.ownerID, source.scope.guildID)
        XCTAssertEqual(context.channelID.rawValue, "9012")
        XCTAssertEqual(context.serverPermissionNames, ["VIEW_CHANNEL", "READ_HISTORY"])
        XCTAssertFalse(context.serverPermissionNames.contains("MANAGE_CHANNEL"))
    }
    func testJoinedTeamDoesNotReplaceMissingIndependentChannelApproval() async throws {
        let team = try await TeamChannelSourceHarness.loaded(), source = try XCTUnwrap(team.source())
        let h = try TeamChannelDirectoryHarness(scope: source.scope); h.approval = nil
        XCTAssertTrue(source.isCurrent(for: source.scope))
        let flow = try h.makeFlow(); await flow.loadDirectory()
        XCTAssertFalse(flow.isCurrent); XCTAssertNil(flow.directory); XCTAssertTrue(h.paths.isEmpty)
    }
    func testChannelApprovalRevocationRetiresOldFlowEvenAfterReplacement() async throws {
        let team = try await TeamChannelSourceHarness.loaded(), source = try XCTUnwrap(team.source())
        let h = try TeamChannelDirectoryHarness(scope: source.scope), flow = try h.makeFlow()
        await flow.loadDirectory(); XCTAssertNotNil(flow.directory)
        h.approval?.revoke(); flow.synchronizeIdentity()
        XCTAssertTrue(flow.retired); XCTAssertNil(flow.directory)
        try h.issueApproval(); await flow.loadDirectory()
        XCTAssertNil(flow.directory); XCTAssertEqual(h.paths.count, 1)
        let fresh = try h.makeFlow(); await fresh.loadDirectory(); XCTAssertNotNil(fresh.directory)
    }
    func testPendingChannelOriginalSurvivesBackAndSameOwnerReauthenticationButNotAccountSwitch() async throws {
        let team = try await TeamChannelSourceHarness.loaded(), source = try XCTUnwrap(team.source())
        let h = try TeamChannelDirectoryHarness(scope: source.scope), flow = try h.makeFlow()
        let journal = NativeChannelManagementJournal(owner: flow.service.owner, scope: source.scope, storage: h.storage)
        var draft = NativeChannelManagementDraft(); draft.name = "Synthetic team channel"
        let original = try NativeChannelManagementIntent.create(scope: source.scope, draft: draft,
            reason: "Synthetic source recovery", requestID: "team-original-recovery-001")
        try journal.saveBeforeDispatch(original); flow.restoreOriginal(); flow.retire()
        XCTAssertNil(flow.pending); XCTAssertEqual(try journal.restore(), original)
        try h.replaceSession(accountID: 901, epoch: 2)
        let sameOwner = try h.makeFlow(); sameOwner.restoreOriginal()
        XCTAssertEqual(sameOwner.pending, original)
        try h.replaceSession(accountID: 902, epoch: 3)
        let otherOwner = try h.makeFlow(); otherOwner.restoreOriginal()
        XCTAssertNil(otherOwner.pending); XCTAssertEqual(try journal.restore(), original)
        XCTAssertTrue(h.paths.isEmpty, "Opening recovery never sends or resends the original command")
    }
}
@MainActor private final class TeamChannelDirectoryStorage: ProjectEditDataStorage {
    var values: [String: Data] = [:]
    func read(_ key: String) throws -> Data? { values[key] }
    func write(_ data: Data, key: String) throws { values[key] = data }
    func remove(_ key: String) throws { values[key] = nil }
}
@MainActor private final class TeamChannelDirectoryHarness {
    let api: APIConfiguration
    let scope: NativeChannelManagementScope
    let storage = TeamChannelDirectoryStorage()
    var context: RuntimeDependencyContext
    var approval: NativeChannelManagementApproval?
    var paths: [String] = []
    init(scope: NativeChannelManagementScope) throws {
        self.scope = scope; api = try APIConfiguration(baseURL: URL(string: "https://example.test/")!)
        context = .init(market: .china, baseURL: api.baseURL, role: "player",
            session: try .init(accountID: 901, epoch: 1, namespace: "team-channel-offline", token: "synthetic-only"))
        try issueApproval()
    }
    func issueApproval() throws {
        approval = try .init(context: context, viewerRevision: 2, scope: scope,
            operations: [.directory, .detail], expiresAt: Date().addingTimeInterval(60))
    }
    func replaceSession(accountID: Int, epoch: UInt64) throws {
        context = .init(market: .china, baseURL: api.baseURL, role: "player",
            session: try .init(accountID: accountID, epoch: epoch, namespace: "team-channel-offline", token: "synthetic-only"))
        try issueApproval()
    }
    func makeFlow() throws -> NativeChannelManagementCoordinator {
        let dispatcher = NativeChannelManagementDispatchTransport { [self] request, fence in
            guard fence.isCurrent else { throw NativeChannelManagementError.changedIdentity }
            XCTAssertEqual(request.httpMethod, "GET")
            paths.append(request.url!.path)
            let row: [String: Any] = ["id": "9012", "guild_kind": 3, "guild_id": "4101", "parent_id": "0", "kind": 1,
                "name": "Synthetic channel", "position": 0, "is_default": 0, "status": 0, "version": "5", "perm_version": "8",
                "visibility": 1, "slowmode_sec": 0, "my_permissions_list": ["VIEW_CHANNEL", "READ_HISTORY"]]
            let data: Any = request.url!.path == "/api/channels/9012" ? row
                : ["guild_kind": 3, "guild_id": "4101", "groups": [], "ungrouped": [row]] as [String: Any]
            return (try JSONSerialization.data(withJSONObject: ["code": 200, "data": data]), 200)
        }
        let service = try NativeChannelManagementHTTPService(context: context, viewerRevision: 2, scope: scope,
            configuration: api, transport: dispatcher, current: { [self] in context }, viewer: { 2 },
            selectedApproval: { [self] in approval })
        let journal = NativeChannelManagementJournal(owner: service.owner, scope: scope, storage: storage)
        return try NativeChannelManagementCoordinator(service: service, journal: journal)
    }
}

import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class PlayPlayerTeamReadbackTests: XCTestCase {
    private func row(_ status: String = "CONFIRMED", id: Int = 8, name: PlayWireValue = .string("Synthetic teammate"), role: PlayWireValue = .string("OBSERVER")) -> PlayWireValue {
        .object(["memberId": .int(id), "displayName": name, "roleCode": role, "status": .string(status)])
    }
    private func raw(_ rows: PlayWireValue = .array([]), session: Int = 501, team: Int = 61, revision: Int = 2) throws -> PlayWireValue {
        var root = try XCTUnwrap(PlayExperienceSyntheticFixtures.wire(PlayExperienceSyntheticFixtures.player).object)
        var player = try XCTUnwrap(root["player"]?.object)
        player["teamActions"] = rows; player["teamId"] = .int(team); root["player"] = .object(player)
        root["sessionId"] = .int(session); root["revision"] = .int(revision)
        return .object(root)
    }
    private func members(_ state: PlayPlayerTeamState) throws -> [PlayPlayerTeamMember] {
        guard case .members(let rows) = state else { XCTFail("Expected server collaboration rows"); throw APIError.invalidRequest }
        return rows
    }
    func testAllSevenStatusesRemainDistinctAndInServerOrder() throws {
        let statuses = PlayPlayerTeamMember.Status.allCases
        let result = try members(.read(.array(statuses.enumerated().map { row($0.element.rawValue, id: 90 - $0.offset) })))
        XCTAssertEqual(result.map(\.status), statuses)
        XCTAssertEqual(result.map(\.id), Array(84...90).reversed().map { $0 })
        XCTAssertEqual(Set(result.map { $0.status.titleKey }).count, 7)
    }
    func testMissingNullMalformedAndEmptyAreDistinct() throws {
        for value in [PlayWireValue.null, .string("missing"), .object([:]), .bool(false)] {
            XCTAssertEqual(PlayPlayerTeamState.read(value), .unconfirmed)
        }
        XCTAssertEqual(PlayPlayerTeamState.read(.array([])), .empty)
        let missing = try PlayPlayerGameProjection(PlayExperienceSyntheticFixtures.wire(PlayExperienceSyntheticFixtures.player))
        XCTAssertEqual(PlayPlayerTeamState.read(missing.teamActions), .unconfirmed)
    }
    func testUnknownAndMissingStatusNeverBecomeAssignmentOrCompletion() throws {
        for status in ["", "completed", "PENDING", "APPROVED", "UNKNOWN"] {
            XCTAssertEqual(PlayPlayerTeamState.read(.array([row(status)])), .unconfirmed)
        }
        var missing = try XCTUnwrap(row().object); missing.removeValue(forKey: "status")
        XCTAssertEqual(PlayPlayerTeamState.read(.array([.object(missing)])), .unconfirmed)
    }
    func testDuplicateMalformedAndUnsafeIdentityInvalidateWholeProjection() throws {
        for rows in [[row(id: 0)], [row(id: -1)], [row(), row("COMPLETED")], [.null], [row(), .string("bad")]] {
            XCTAssertEqual(PlayPlayerTeamState.read(.array(rows)), .unconfirmed)
        }
        var stringID = try XCTUnwrap(row().object); stringID["memberId"] = .string("8")
        XCTAssertEqual(PlayPlayerTeamState.read(.array([.object(stringID)])), .unconfirmed)
    }
    func testOptionalNameAndRoleUseOnlyPublicFieldsAndSafeBounds() throws {
        var source = try XCTUnwrap(row(name: .null, role: .null).object)
        source["phone"] = .string("private"); source["evidenceUrls"] = .array([.string("private")])
        source["latitude"] = .number(1); source["realName"] = .string("private")
        let member = try XCTUnwrap(members(.read(.array([.object(source)]))).first)
        XCTAssertNil(member.displayName); XCTAssertNil(member.roleCode)
        XCTAssertEqual(member, .init(id: 8, displayName: nil, roleCode: nil, status: .confirmed))
        for value in [PlayWireValue.int(4), .array([]), .string(String(repeating: "x", count: 81)), .string("bad\u{0}name")] {
            XCTAssertEqual(PlayPlayerTeamState.read(.array([row(name: value)])), .unconfirmed)
        }
        XCTAssertEqual(PlayPlayerTeamState.read(.array([row(role: .string(String(repeating: "x", count: 65)))])), .unconfirmed)
        let trimmed = try XCTUnwrap(members(.read(.array([row(name: .string("  Name  "), role: .string("  "))]))).first)
        XCTAssertEqual(trimmed.displayName, "Name"); XCTAssertNil(trimmed.roleCode)
    }
    private func setup(_ rows: PlayWireValue? = nil, enabled: Set<PlayExperienceCapability> = [.reads, .playerCommands], lifetime: PlayInteractionLifetime? = nil) throws -> (TeamReadOwner, TeamReadTransport, PlayPlayerGameCoordinator, PlayPlayerSubmissionReadback, PlayPlayerTeamReadback) {
        let owner = try TeamReadOwner(), transport = TeamReadTransport(response: try raw(rows ?? .array([row()])))
        let service = PlayExperienceService(configuration: try .init(baseURL: URL(string: "https://example.test")!), transport: transport, enabled: enabled, readLifetime: lifetime)
        let model = PlayPlayerGameCoordinator(activityID: 41, service: service, currentSession: { owner.value })
        return (owner, transport, model, PlayPlayerSubmissionReadback(model: model), PlayPlayerTeamReadback(model: model))
    }
    func testUsesExistingReadWithNoAdditionalRequestOrWriteEligibilityChange() async throws {
        let (_, transport, model, submissions, team) = try setup()
        XCTAssertEqual(team.state, .unconfirmed)
        await submissions.open(); team.acceptFreshRead()
        XCTAssertEqual(try members(team.state).first?.status, .confirmed)
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(transport.requests.first?.url?.path, "/api/game/session/view")
        XCTAssertEqual(transport.requests.first?.httpMethod, "GET")
        let projection = try XCTUnwrap(model.projection)
        let command = try PlayPlayerCommand(activityID: 41, nodeID: 701, expectedRevision: 2, action: .submit,
            payload: ["taskCode": .string("OBSERVE"), "evidenceUrls": .array([.string("text:synthetic")])])
        let eligible = projection.allows(command); _ = team.state
        XCTAssertTrue(eligible); XCTAssertEqual(projection.allows(command), eligible)
        XCTAssertEqual(submissions.state(nodeID: 701), .none)
        team.dismiss(); team.acceptFreshRead(); XCTAssertEqual(team.state, .unconfirmed)
        XCTAssertEqual(transport.requests.count, 1)
    }
    func testInitialFailureCanRecoverThroughExistingRefresh() async throws {
        let (_, transport, _, submissions, team) = try setup()
        transport.fail = true; await submissions.open(); team.acceptFreshRead()
        XCTAssertEqual(team.state, .unconfirmed)
        transport.fail = false; await submissions.refresh(); team.acceptFreshRead()
        XCTAssertEqual(try members(team.state).first?.status, .confirmed)
    }
    func testRefreshFailureHidesOldNamesAndStatusUntilFreshRead() async throws {
        let (_, transport, _, submissions, team) = try setup(.array([row("COMPLETED")]))
        await submissions.open(); team.acceptFreshRead()
        transport.fail = true; await submissions.refresh(); team.acceptFreshRead()
        XCTAssertEqual(team.state, .unconfirmed)
        transport.fail = false; transport.response = try raw(.array([row("SUBMITTED")]), revision: 3)
        await submissions.refresh(); team.acceptFreshRead()
        XCTAssertEqual(try members(team.state).first?.status, .submitted)
    }
    func testAccountEpochNamespaceRoleTokenAndLogoutRevokeBeforeAnyNewRead() async throws {
        let (owner, transport, _, submissions, team) = try setup()
        await submissions.open(); team.acceptFreshRead()
        for replacement in [
            try PlayExperienceSession(accountID: 2, epoch: 1, namespace: "synthetic", token: "synthetic-token"),
            try PlayExperienceSession(accountID: 1, epoch: 2, namespace: "synthetic", token: "synthetic-token"),
            try PlayExperienceSession(accountID: 1, epoch: 1, namespace: "another", token: "synthetic-token"),
            try PlayExperienceSession(accountID: 1, epoch: 1, namespace: "synthetic", token: "synthetic-token", role: "merchant"),
            try PlayExperienceSession(accountID: 1, epoch: 1, namespace: "synthetic", token: "replacement-token")
        ] { owner.value = replacement; team.acceptFreshRead(); XCTAssertEqual(team.state, .unconfirmed) }
        owner.value = nil; XCTAssertEqual(team.state, .unconfirmed); XCTAssertEqual(transport.requests.count, 1)
    }
    func testDifferentGameOrTeamCannotRebindExistingLease() async throws {
        for changeTeam in [false, true] {
            let (_, transport, _, submissions, team) = try setup()
            await submissions.open(); team.acceptFreshRead()
            transport.response = try raw(.array([row("COMPLETED")]), session: changeTeam ? 501 : 999, team: changeTeam ? 999 : 61, revision: 3)
            await submissions.refresh(); XCTAssertEqual(team.state, .unconfirmed); team.acceptFreshRead()
            transport.response = try raw(.array([row("COMPLETED")]), revision: 4)
            await submissions.refresh(); team.acceptFreshRead()
            XCTAssertEqual(team.state, .unconfirmed, "A changed scope needs a new screen lease")
        }
    }
    func testRevisionRollbackCannotReplaceNewerCollaborationStatus() async throws {
        let (_, transport, _, submissions, team) = try setup()
        await submissions.open(); team.acceptFreshRead()
        transport.response = try raw(.array([row("SUBMITTED")]), revision: 4)
        await submissions.refresh(); team.acceptFreshRead()
        transport.response = try raw(.array([row("COMPLETED")]), revision: 3)
        await submissions.refresh(); team.acceptFreshRead()
        XCTAssertEqual(team.state, .unconfirmed)
    }
    func testUnknownWriteHidesCollaborationAndDoesNotBecomeCompletion() async throws {
        let (_, transport, model, submissions, team) = try setup()
        await submissions.open(); team.acceptFreshRead()
        let command = try PlayPlayerCommand(activityID: 41, nodeID: 701, expectedRevision: 2, action: .choice, payload: ["choiceId": .string("LEFT")])
        transport.fail = true; await model.submit(command)
        XCTAssertEqual(model.phase, "unknown"); XCTAssertNotNil(model.pending)
        team.acceptFreshRead(); XCTAssertEqual(team.state, .unconfirmed)
    }
    func testDisabledReadsCannotBindOrDispatch() async throws {
        let (_, transport, _, submissions, team) = try setup(enabled: [])
        await submissions.open(); team.acceptFreshRead()
        XCTAssertEqual(team.state, .unconfirmed); XCTAssertTrue(transport.requests.isEmpty)
    }
    func testLateReadAfterDismissalAndCancellationCannotRestoreNames() async throws {
        let (_, transport, _, submissions, team) = try setup()
        let started = expectation(description: "projection suspended")
        transport.suspend = true; transport.onRead = { started.fulfill() }
        let task = Task { await submissions.open(); team.acceptFreshRead() }
        await fulfillment(of: [started], timeout: 2)
        team.dismiss(); submissions.dismiss(); task.cancel(); transport.resume(); await task.value
        XCTAssertEqual(team.state, .unconfirmed); XCTAssertEqual(transport.requests.count, 1)
    }
    func testReopenRequiresFreshReadAndOldLeaseStaysRetired() async throws {
        let (_, transport, model, submissions, team) = try setup()
        await submissions.open(); team.acceptFreshRead(); submissions.dismiss(); team.dismiss()
        let reopened = PlayPlayerTeamReadback(model: model), reads = PlayPlayerSubmissionReadback(model: model)
        XCTAssertEqual(reopened.state, .unconfirmed)
        let started = expectation(description: "fresh read suspended")
        transport.suspend = true; transport.onRead = { started.fulfill() }
        let task = Task { await reads.open(); reopened.acceptFreshRead() }
        await fulfillment(of: [started], timeout: 2)
        XCTAssertEqual(reopened.state, .unconfirmed)
        transport.resume(); await task.value
        XCTAssertEqual(try members(reopened.state).first?.status, .confirmed)
        XCTAssertEqual(team.state, .unconfirmed); XCTAssertEqual(transport.requests.count, 2)
    }
    func testReadLifetimeRevocationOverridesPreviouslyLoadedSuccess() async throws {
        let owner = try TeamReadOwner()
        let rootWire = TeamReadTransport(response: try PlayExperienceSyntheticFixtures.wire(#"{"mode":1,"topicId":71,"registered":true,"playable":true,"nodes":[{"nodeId":701,"done":false,"arrived":true,"validationMethod":6}]}"#))
        let rootService = PlayExperienceService(configuration: try .init(baseURL: URL(string: "https://example.test")!), transport: rootWire, enabled: [.reads])
        let root = PlayExperienceCoordinator(scope: .activity(41), service: rootService, recovery: PlayMemoryCompletionRecovery(),
            pausedStorage: PlayMemoryPausedStorage(), currentSession: { owner.value })
        await root.load()
        let lifetime = try XCTUnwrap(root.makeInteractionLifetime())
        let (_, transport, _, submissions, team) = try setup(.array([row("COMPLETED")]), lifetime: lifetime)
        await submissions.open(); team.acceptFreshRead()
        XCTAssertEqual(try members(team.state).first?.status, .completed)
        owner.value = nil
        XCTAssertFalse(lifetime.isCurrent); XCTAssertEqual(team.state, .unconfirmed)
        await submissions.refresh(); team.acceptFreshRead()
        XCTAssertEqual(team.state, .unconfirmed); XCTAssertEqual(transport.requests.count, 1)
    }
}

@MainActor private final class TeamReadOwner {
    var value: PlayExperienceSession?
    init() throws { value = try .init(accountID: 1, epoch: 1, namespace: "synthetic", token: "synthetic-token") }
}
private final class TeamReadTransport: HTTPTransport {
    @MainActor var response: PlayWireValue
    @MainActor var requests: [URLRequest] = []
    @MainActor var fail = false
    @MainActor var suspend = false
    @MainActor var onRead: (() -> Void)?
    @MainActor private var continuation: CheckedContinuation<Void, Never>?
    @MainActor init(response: PlayWireValue) { self.response = response }
    func send(_ request: URLRequest) async throws -> (Data, Int) { try await execute(request) }
    @MainActor private func execute(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); let snapshot = response
        if suspend { await withCheckedContinuation { continuation = $0; onRead?() } }
        else { onRead?() }
        if fail { throw APIError.malformedResponse }
        return (try JSONEncoder().encode(PlayWireValue.object(["code": .int(200), "data": snapshot])), 200)
    }
    @MainActor func resume() { suspend = false; continuation?.resume(); continuation = nil }
}

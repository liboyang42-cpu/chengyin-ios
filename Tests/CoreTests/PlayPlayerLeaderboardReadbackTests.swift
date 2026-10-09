import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class PlayPlayerLeaderboardReadbackTests: XCTestCase {
    private func row(id: Int = 8, rank: Int = 1, score: Int = 3, name: PlayWireValue = .string("Synthetic team")) -> PlayWireValue {
        .object(["teamId": .int(id), "rank": .int(rank), "score": .int(score), "displayName": name])
    }
    private func board(_ rows: [PlayWireValue]? = nil) -> PlayWireValue {
        .object(["visible": .bool(true), "entries": .array(rows ?? [row()])])
    }
    private func raw(_ board: PlayWireValue? = nil, session: Int = 501, team: Int = 61, revision: Int = 2) throws -> PlayWireValue {
        var root = try XCTUnwrap(PlayExperienceSyntheticFixtures.wire(PlayExperienceSyntheticFixtures.player).object)
        var player = try XCTUnwrap(root["player"]?.object)
        player["leaderboard"] = board ?? self.board(); player["teamId"] = .int(team)
        root["player"] = .object(player); root["sessionId"] = .int(session); root["revision"] = .int(revision)
        return .object(root)
    }
    private func entries(_ state: PlayPlayerLeaderboardState) throws -> [PlayPlayerLeaderboardEntry] {
        guard case .entries(let rows) = state else { XCTFail("Expected visible server ranking"); throw APIError.invalidRequest }
        return rows
    }
    func testOnlyExplicitServerVisibilityShowsLeaderboard() throws {
        for value in [PlayWireValue.null, .array([]), .string("visible"), .bool(true), .object([:]),
                      .object(["visible": .bool(false), "entries": .array([row()])]),
                      .object(["visible": .string("true"), "entries": .array([row()])]),
                      .object(["visible": .int(1), "entries": .array([row()])]),
                      .object(["entries": .array([row()])])] {
            XCTAssertEqual(PlayPlayerLeaderboardState.read(value), .hidden)
        }
        let missing = try PlayPlayerGameProjection(PlayExperienceSyntheticFixtures.wire(PlayExperienceSyntheticFixtures.player))
        XCTAssertEqual(PlayPlayerLeaderboardState.read(missing.playerLeaderboard), .hidden)
    }
    func testVisibleEmptyDiffersFromMissingMalformedEntries() {
        XCTAssertEqual(PlayPlayerLeaderboardState.read(board([])), .empty)
        for value in [PlayWireValue.null, .object([:]), .string("rows"), .bool(false)] {
            XCTAssertEqual(PlayPlayerLeaderboardState.read(.object(["visible": .bool(true), "entries": value])), .unconfirmed)
        }
        XCTAssertEqual(PlayPlayerLeaderboardState.read(.object(["visible": .bool(true)])), .unconfirmed)
    }
    func testServerRankScoreAndOrderArePreservedWithoutClientScoring() throws {
        let rows = try entries(.read(board([row(id: 19, rank: 2, score: 7), row(id: 4, rank: 9, score: 0)])))
        XCTAssertEqual(rows.map(\.id), [19, 4]); XCTAssertEqual(rows.map(\.rank), [2, 9])
        XCTAssertEqual(rows.map(\.score), [7, 0])
    }
    func testDuplicateTeamDuplicateRankAndReversedRankInvalidateWholeBoard() {
        for rows in [[row(), row(rank: 2)], [row(), row(id: 9)], [row(rank: 2), row(id: 9, rank: 1)], [row(), .null]] {
            XCTAssertEqual(PlayPlayerLeaderboardState.read(board(rows)), .unconfirmed)
        }
    }
    func testMalformedNegativeFractionalStringAndUnsafeNumericFieldsFailClosed() throws {
        for key in ["teamId", "rank", "score"] {
            for value in [PlayWireValue.null, .string("1"), .bool(true), .number(1.5), .int(-1), .number(9_007_199_254_740_992)] {
                var bad = try XCTUnwrap(row().object); bad[key] = value
                XCTAssertEqual(PlayPlayerLeaderboardState.read(board([.object(bad)])), .unconfirmed)
            }
        }
        XCTAssertEqual(PlayPlayerLeaderboardState.read(board([row(id: 0)])), .unconfirmed)
        XCTAssertEqual(PlayPlayerLeaderboardState.read(board([row(rank: 0)])), .unconfirmed)
        XCTAssertEqual(try entries(.read(board([row(score: 0)]))).first?.score, 0)
    }
    func testOptionalPublicNameHasBoundsAndDoesNotReadPrivateFields() throws {
        var source = try XCTUnwrap(row(name: .null).object)
        source["phone"] = .string("private"); source["evidenceUrls"] = .array([.string("private")])
        source["latitude"] = .number(1); source["realName"] = .string("private")
        let entry = try XCTUnwrap(entries(.read(board([.object(source)]))).first)
        XCTAssertEqual(entry, .init(id: 8, rank: 1, displayName: nil, score: 3))
        for name in [PlayWireValue.int(4), .array([]), .string(String(repeating: "x", count: 81)), .string("bad\u{0}name")] {
            XCTAssertEqual(PlayPlayerLeaderboardState.read(board([row(name: name)])), .unconfirmed)
        }
        XCTAssertEqual(try entries(.read(board([row(name: .string("  Team  "))]))).first?.displayName, "Team")
        XCTAssertNil(try entries(.read(board([row(name: .string("   "))]))).first?.displayName)
    }
    private func setup(_ board: PlayWireValue? = nil, enabled: Set<PlayExperienceCapability> = [.reads, .playerCommands], lifetime: PlayInteractionLifetime? = nil) throws -> (LeaderboardReadOwner, LeaderboardReadTransport, PlayPlayerGameCoordinator, PlayPlayerSubmissionReadback, PlayPlayerLeaderboardReadback) {
        let owner = try LeaderboardReadOwner(), transport = LeaderboardReadTransport(response: try raw(board))
        let service = PlayExperienceService(configuration: try .init(baseURL: URL(string: "https://example.test")!), transport: transport, enabled: enabled, readLifetime: lifetime)
        let model = PlayPlayerGameCoordinator(activityID: 41, service: service, currentSession: { owner.value })
        return (owner, transport, model, PlayPlayerSubmissionReadback(model: model), PlayPlayerLeaderboardReadback(model: model))
    }
    func testUsesExistingSingleReadWithoutChangingLegacyWriteEligibility() async throws {
        let (_, transport, model, submissions, leaderboard) = try setup()
        XCTAssertEqual(leaderboard.state, .hidden)
        await submissions.open(); leaderboard.acceptFreshRead()
        XCTAssertEqual(try entries(leaderboard.state).first?.score, 3)
        XCTAssertEqual(transport.requests.count, 1)
        XCTAssertEqual(transport.requests.first?.url?.path, "/api/game/session/view")
        XCTAssertEqual(transport.requests.first?.httpMethod, "GET")
        let projection = try XCTUnwrap(model.projection)
        let command = try PlayPlayerCommand(activityID: 41, nodeID: 701, expectedRevision: 2, action: .submit,
            payload: ["taskCode": .string("OBSERVE"), "evidenceUrls": .array([.string("text:synthetic")])])
        let eligible = projection.allows(command); _ = leaderboard.state
        XCTAssertTrue(eligible); XCTAssertEqual(projection.allows(command), eligible)
        XCTAssertEqual(submissions.state(nodeID: 701), .none)
        leaderboard.dismiss(); leaderboard.acceptFreshRead(); XCTAssertEqual(leaderboard.state, .hidden)
        XCTAssertEqual(transport.requests.count, 1)
    }
    func testMalformedBoardDoesNotChangeLegacySubmissionEligibility() async throws {
        let (_, _, model, submissions, leaderboard) = try setup(.object(["visible": .bool(true), "entries": .string("bad")]))
        await submissions.open(); leaderboard.acceptFreshRead()
        XCTAssertEqual(leaderboard.state, .unconfirmed); XCTAssertEqual(model.phase, "ready")
        let command = try PlayPlayerCommand(activityID: 41, nodeID: 701, expectedRevision: 2, action: .choice, payload: ["choiceId": .string("LEFT")])
        XCTAssertTrue(try XCTUnwrap(model.projection).allows(command))
    }
    func testRefreshRemovesBoardWhenServerHidesOrOmitsIt() async throws {
        for hidden in [PlayWireValue.null, .object(["visible": .bool(false), "entries": .array([row()])])] {
            let (_, transport, _, submissions, leaderboard) = try setup()
            await submissions.open(); leaderboard.acceptFreshRead()
            XCTAssertEqual(try entries(leaderboard.state).count, 1)
            transport.response = try raw(hidden, revision: 3)
            await submissions.refresh(); leaderboard.acceptFreshRead()
            XCTAssertEqual(leaderboard.state, .hidden); XCTAssertEqual(transport.requests.count, 2)
        }
    }
    func testInitialFailureCanRecoverThroughExistingRefresh() async throws {
        let (_, transport, _, submissions, leaderboard) = try setup()
        transport.fail = true; await submissions.open(); leaderboard.acceptFreshRead()
        XCTAssertEqual(leaderboard.state, .hidden)
        transport.fail = false; await submissions.refresh(); leaderboard.acceptFreshRead()
        XCTAssertEqual(try entries(leaderboard.state).first?.score, 3)
    }
    func testRefreshFailureHidesOldRankingUntilFreshRead() async throws {
        let (_, transport, _, submissions, leaderboard) = try setup()
        await submissions.open(); leaderboard.acceptFreshRead()
        transport.fail = true; await submissions.refresh(); leaderboard.acceptFreshRead()
        XCTAssertEqual(leaderboard.state, .hidden)
        transport.fail = false; transport.response = try raw(board([row(score: 5)]), revision: 3)
        await submissions.refresh(); leaderboard.acceptFreshRead()
        XCTAssertEqual(try entries(leaderboard.state).first?.score, 5)
    }
    func testAccountEpochNamespaceRoleTokenAndLogoutRevokeBeforeNewRead() async throws {
        let (owner, transport, _, submissions, leaderboard) = try setup()
        await submissions.open(); leaderboard.acceptFreshRead()
        for replacement in [
            try PlayExperienceSession(accountID: 2, epoch: 1, namespace: "synthetic", token: "synthetic-token"),
            try PlayExperienceSession(accountID: 1, epoch: 2, namespace: "synthetic", token: "synthetic-token"),
            try PlayExperienceSession(accountID: 1, epoch: 1, namespace: "another", token: "synthetic-token"),
            try PlayExperienceSession(accountID: 1, epoch: 1, namespace: "synthetic", token: "synthetic-token", role: "merchant"),
            try PlayExperienceSession(accountID: 1, epoch: 1, namespace: "synthetic", token: "replacement-token")
        ] { owner.value = replacement; leaderboard.acceptFreshRead(); XCTAssertEqual(leaderboard.state, .hidden) }
        owner.value = nil; XCTAssertEqual(leaderboard.state, .hidden); XCTAssertEqual(transport.requests.count, 1)
    }
    func testDifferentGameOrTeamCannotRebindLeaseOrRestoreOldBoard() async throws {
        for changeTeam in [false, true] {
            let (_, transport, _, submissions, leaderboard) = try setup()
            await submissions.open(); leaderboard.acceptFreshRead()
            transport.response = try raw(session: changeTeam ? 501 : 999, team: changeTeam ? 999 : 61, revision: 3)
            await submissions.refresh(); XCTAssertEqual(leaderboard.state, .hidden); leaderboard.acceptFreshRead()
            transport.response = try raw(revision: 4)
            await submissions.refresh(); leaderboard.acceptFreshRead()
            XCTAssertEqual(leaderboard.state, .hidden)
        }
    }
    func testRevisionRollbackCannotRestoreFormerlyVisibleRanks() async throws {
        let (_, transport, _, submissions, leaderboard) = try setup()
        await submissions.open(); leaderboard.acceptFreshRead()
        transport.response = try raw(.null, revision: 4)
        await submissions.refresh(); leaderboard.acceptFreshRead()
        transport.response = try raw(revision: 3)
        await submissions.refresh(); leaderboard.acceptFreshRead()
        XCTAssertEqual(leaderboard.state, .hidden)
    }
    func testUnknownWriteHidesBoardAndPreservesFrozenPendingCommand() async throws {
        let (_, transport, model, submissions, leaderboard) = try setup()
        await submissions.open(); leaderboard.acceptFreshRead()
        let command = try PlayPlayerCommand(activityID: 41, nodeID: 701, expectedRevision: 2, action: .choice, payload: ["choiceId": .string("LEFT")])
        transport.fail = true; await model.submit(command)
        XCTAssertEqual(model.phase, "unknown"); XCTAssertEqual(model.pending, command)
        leaderboard.acceptFreshRead(); XCTAssertEqual(leaderboard.state, .hidden)
        XCTAssertEqual(model.pending, command)
    }
    func testDisabledReadsCannotBindOrDispatch() async throws {
        let (_, transport, _, submissions, leaderboard) = try setup(enabled: [])
        await submissions.open(); leaderboard.acceptFreshRead()
        XCTAssertEqual(leaderboard.state, .hidden); XCTAssertTrue(transport.requests.isEmpty)
    }
    func testLoadingHidesOldRanksAndLateDismissedReadCannotRestoreThem() async throws {
        let (_, transport, _, submissions, leaderboard) = try setup()
        await submissions.open(); leaderboard.acceptFreshRead()
        let started = expectation(description: "projection suspended")
        transport.suspend = true; transport.onRead = { started.fulfill() }
        let task = Task { await submissions.refresh(); leaderboard.acceptFreshRead() }
        await fulfillment(of: [started], timeout: 2)
        XCTAssertEqual(leaderboard.state, .hidden)
        leaderboard.dismiss(); submissions.dismiss(); task.cancel(); transport.resume(); await task.value
        XCTAssertEqual(leaderboard.state, .hidden); XCTAssertEqual(transport.requests.count, 2)
    }
    func testReopenRequiresFreshReadAndOldLeaseStaysRetired() async throws {
        let (_, transport, model, submissions, leaderboard) = try setup()
        await submissions.open(); leaderboard.acceptFreshRead(); submissions.dismiss(); leaderboard.dismiss()
        let reopened = PlayPlayerLeaderboardReadback(model: model), reads = PlayPlayerSubmissionReadback(model: model)
        XCTAssertEqual(reopened.state, .hidden)
        let started = expectation(description: "fresh read suspended")
        transport.suspend = true; transport.onRead = { started.fulfill() }
        let task = Task { await reads.open(); reopened.acceptFreshRead() }
        await fulfillment(of: [started], timeout: 2)
        XCTAssertEqual(reopened.state, .hidden)
        transport.resume(); await task.value
        XCTAssertEqual(try entries(reopened.state).first?.score, 3)
        XCTAssertEqual(leaderboard.state, .hidden); XCTAssertEqual(transport.requests.count, 2)
    }
    func testReadLifetimeRevocationOverridesPreviouslyVisibleBoard() async throws {
        let owner = try LeaderboardReadOwner()
        let rootWire = LeaderboardReadTransport(response: try PlayExperienceSyntheticFixtures.wire(#"{"mode":1,"topicId":71,"registered":true,"playable":true,"nodes":[{"nodeId":701,"done":false,"arrived":true,"validationMethod":6}]}"#))
        let rootService = PlayExperienceService(configuration: try .init(baseURL: URL(string: "https://example.test")!), transport: rootWire, enabled: [.reads])
        let root = PlayExperienceCoordinator(scope: .activity(41), service: rootService, recovery: PlayMemoryCompletionRecovery(),
            pausedStorage: PlayMemoryPausedStorage(), currentSession: { owner.value })
        await root.load()
        let lifetime = try XCTUnwrap(root.makeInteractionLifetime())
        let (_, transport, _, submissions, leaderboard) = try setup(lifetime: lifetime)
        await submissions.open(); leaderboard.acceptFreshRead()
        XCTAssertEqual(try entries(leaderboard.state).first?.score, 3)
        owner.value = nil
        XCTAssertFalse(lifetime.isCurrent); XCTAssertEqual(leaderboard.state, .hidden)
        await submissions.refresh(); leaderboard.acceptFreshRead()
        XCTAssertEqual(leaderboard.state, .hidden); XCTAssertEqual(transport.requests.count, 1)
    }
}

@MainActor private final class LeaderboardReadOwner {
    var value: PlayExperienceSession?
    init() throws { value = try .init(accountID: 1, epoch: 1, namespace: "synthetic", token: "synthetic-token") }
}
private final class LeaderboardReadTransport: HTTPTransport {
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

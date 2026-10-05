import XCTest
@testable import QuestifyCore

@available(macOS 14.0, *)
@MainActor final class PlayAdvancedTeamTests: XCTestCase {
    private func json(version: Int = 1, leader: Int = 9001, assignment: String = "LEADER", myRole: String = "starter", completed: Int = 0, deadline: Int64? = nil) -> String {
        let units = completed > 0 ? #"["server-unit"]"# : "[]"
        let time = deadline.map { ",\"deadlineAt\":\($0)" } ?? ""
        return """
        {"sessionId":501,"activityId":41,"topicId":71,"nodeId":701,"ownerType":2,"version":\(version),"status":"RUNNING"\(time),"config":{"multiplayer":{"enabled":true,"assignment":"\(assignment)","requiredTurns":2,"roles":[{"id":"starter","label":"Starter","min":1,"max":1},{"id":"finisher","label":"Finisher","min":1,"max":2}]},"leaderboard":{"enabled":true,"metric":"SCORE"}},"multiplayer":{"members":[{"memberId":9001,"name":"Synthetic actor"},{"memberId":9002,"name":"Synthetic teammate"}],"leaderMemberId":\(leader),"myRole":"\(myRole)","roleAssignments":{"9001":"starter"},"turnIndex":\(completed),"completedUnitIds":\(units)}}
        """
    }
    private func state(_ raw: String) throws -> PlayAdvancedState { try .init(JSONDecoder().decode(PlayWireValue.self, from: Data(raw.utf8))) }
    private func owner(_ epoch: UInt64 = 1) throws -> PlayExperienceSession { try .init(accountID: 9001, epoch: epoch, namespace: "synthetic", token: "synthetic") }
    private func make(_ transport: PlayRecoveryRecordingTransport, current: @escaping () -> PlayExperienceSession?) throws -> PlayAdvancedCoordinator {
        let service = PlayExperienceService(configuration: try .init(baseURL: URL(string: "https://example.com/fixture/")!), transport: transport, enabled: [.reads, .advanced])
        return .init(activityID: 41, topicID: 71, nodeID: 701, service: service, currentSession: current)
    }
    private func prepare(_ transport: PlayRecoveryRecordingTransport, raw: String? = nil) {
        transport.responses["/fixture/api/play/advanced/start"] = .reply(PlayExperienceSyntheticFixtures.envelope(raw ?? json()), 200)
        transport.responses["/fixture/api/play/advanced/action"] = .reply(PlayExperienceSyntheticFixtures.envelope(json(version: 2, completed: 1)), 200)
        transport.responses["/fixture/api/play/advanced/state"] = .reply(PlayExperienceSyntheticFixtures.envelope(json(version: 2, completed: 1)), 200)
        transport.responses["/fixture/api/play/advanced/leaderboard"] = .reply(PlayExperienceSyntheticFixtures.envelope(#"[{"rank":1,"ownerType":2,"ownerId":91,"displayName":"Synthetic team","score":7,"completedUnits":2,"elapsedSeconds":60}]"#), 200)
    }
    private func wait(_ transport: PlayRecoveryRecordingTransport) async {
        for _ in 0..<1000 { if transport.isAwaitingResponse { break }; await Task.yield() }
        XCTAssertTrue(transport.isAwaitingResponse)
    }
    func testActualLeaderProjectionAndCapacity() throws {
        let team = try XCTUnwrap(PlayAdvancedTeamProjection(state: state(json()), actorID: 9001))
        XCTAssertTrue(team.isLeader)
        XCTAssertEqual(team.members.first?.roleID, "starter")
        XCTAssertFalse(team.canAssign(memberID: 9002, roleID: "starter"))
        XCTAssertTrue(team.canAssign(memberID: 9002, roleID: "finisher"))
        XCTAssertTrue(team.canRequestUnit)
    }
    func testNonleaderIgnoresEvenUnexpectedRoleAssignments() throws {
        let team = try XCTUnwrap(PlayAdvancedTeamProjection(state: state(json(leader: 9002)), actorID: 9001))
        XCTAssertFalse(team.isLeader); XCTAssertTrue(team.roles.isEmpty)
        XCTAssertTrue(team.members.allSatisfy { $0.roleID == nil })
        XCTAssertEqual(team.myRole, "starter")
        XCTAssertFalse(team.canAssign(memberID: 9002, roleID: "finisher"))
    }
    func testAutoAssignmentAndNoRoleCannotInventAuthority() throws {
        let team = try XCTUnwrap(PlayAdvancedTeamProjection(state: state(json(assignment: "AUTO", myRole: "")), actorID: 9001))
        XCTAssertFalse(team.canAssign(memberID: 9002, roleID: "finisher")); XCTAssertFalse(team.canRequestUnit)
    }
    func testMissingOwnerTypeFailsClosed() throws {
        let raw = json().replacingOccurrences(of: "\"ownerType\":2,", with: "")
        XCTAssertNil(PlayAdvancedTeamProjection(state: try state(raw), actorID: 9001))
    }
    func testDismissedOrVersionChangedReviewDoesNotDispatch() async throws {
        let owner = try owner(); let transport = PlayRecoveryRecordingTransport(); prepare(transport)
        let model = try make(transport, current: { owner }); await model.start(); model.beginTeamSurface()
        let review = try model.reviewTeamAction(.completeUnit)
        model.endTeamSurface(); model.beginTeamSurface(); await model.submitTeamReview(review)
        XCTAssertEqual(transport.requests.count, 1)
        let next = try model.reviewTeamAction(.completeUnit)
        await model.refreshAuthoritative(); await model.submitTeamReview(next)
        XCTAssertEqual(transport.requests.count, 2)
    }
    func testDuplicateClickWaitsForServerAndUsesFrozenRequest() async throws {
        let owner = try owner(); let transport = PlayRecoveryRecordingTransport(); prepare(transport)
        let model = try make(transport, current: { owner }); await model.start(); model.beginTeamSurface()
        let review = try model.reviewTeamAction(.completeUnit); transport.pauseResponse = true
        let first = Task { await model.submitTeamReview(review) }; await wait(transport)
        await model.submitTeamReview(review)
        XCTAssertEqual(transport.requests.count, 2)
        XCTAssertEqual(model.teamProjection?.completedUnits, 0)
        transport.resumeResponse(); await first.value
        XCTAssertEqual(model.teamProjection?.completedUnits, 1)
        let data = try XCTUnwrap(transport.requests.last?.httpBody)
        let body = try JSONDecoder().decode(PlayWireValue.self, from: data)
        XCTAssertEqual(body["action"].text, "COMPLETE_UNIT")
        XCTAssertEqual(body["payload"]["unitId"].text, "unit-501-v1")
        XCTAssertNil(body["payload"]["score"].integer)
    }
    func testRoleAssignmentUsesFrozenMemberAndRoleOnly() async throws {
        let owner = try owner(); let transport = PlayRecoveryRecordingTransport(); prepare(transport)
        let model = try make(transport, current: { owner }); await model.start(); model.beginTeamSurface()
        let review = try model.reviewTeamAction(.assign(memberID: 9002, roleID: "finisher"))
        await model.submitTeamReview(review)
        let request = try XCTUnwrap(transport.requests.last)
        let body = try JSONDecoder().decode(PlayWireValue.self, from: XCTUnwrap(request.httpBody))
        XCTAssertEqual(body["action"].text, "ASSIGN_ROLE")
        XCTAssertEqual(body["payload"].object?.keys.sorted(), ["memberId", "roleId"])
        XCTAssertEqual(body["payload"]["memberId"].integer, 9002)
        XCTAssertEqual(body["payload"]["roleId"].text, "finisher")
    }
    func testUnknownTeamWriteRecoversThenRetriesExactBytes() async throws {
        let owner = try owner(); let transport = PlayRecoveryRecordingTransport(); prepare(transport)
        let model = try make(transport, current: { owner }); await model.start(); model.beginTeamSurface()
        transport.responses["/fixture/api/play/advanced/action"] = .failure(.unknownResult)
        await model.submitTeamReview(try model.reviewTeamAction(.completeUnit))
        let original = transport.requests.last?.httpBody
        XCTAssertEqual(model.phase, "unknown"); XCTAssertNotNil(model.pending)
        XCTAssertEqual(model.teamProjection?.completedUnits, 0)
        await model.recover(); XCTAssertEqual(model.phase, "retryable"); XCTAssertNotNil(model.pending)
        transport.responses["/fixture/api/play/advanced/action"] = .reply(PlayExperienceSyntheticFixtures.envelope(json(version: 2, completed: 1)), 200)
        await model.retryExact()
        XCTAssertEqual(transport.requests.last?.httpBody, original)
        XCTAssertNil(model.pending); XCTAssertEqual(model.teamProjection?.completedUnits, 1)
    }
    func testNonleaderAndExpiredRequestsNeverDispatch() async throws {
        let owner = try owner()
        for raw in [json(leader: 9002), json(deadline: 1)] {
            let transport = PlayRecoveryRecordingTransport(); prepare(transport, raw: raw)
            let model = try make(transport, current: { owner }); await model.start(); model.beginTeamSurface()
            XCTAssertThrowsError(try model.reviewTeamAction(.assign(memberID: 9002, roleID: "finisher")))
            XCTAssertEqual(transport.requests.count, 1)
        }
    }
    func testLeaderboardUsesSeparateExactReadQueryAndMetric() async throws {
        let owner = try owner(); let transport = PlayRecoveryRecordingTransport(); prepare(transport)
        let model = try make(transport, current: { owner }); await model.start(); model.beginTeamSurface(); await model.loadAdvancedLeaderboard()
        XCTAssertEqual(model.leaderboardPhase, "ready"); XCTAssertEqual(model.leaderboardMetric, .score)
        XCTAssertEqual(model.leaderboard.count, 1)
        let request = try XCTUnwrap(transport.requests.last)
        XCTAssertEqual(request.httpMethod, "GET"); XCTAssertEqual(request.url?.path, "/fixture/api/play/advanced/leaderboard")
        let query = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertEqual(query?.first { $0.name == "activityId" }?.value, "41")
        XCTAssertEqual(query?.first { $0.name == "topicId" }?.value, "71")
        XCTAssertEqual(query?.first { $0.name == "nodeId" }?.value, "701")
    }
    func testLeaderboardEmptyFailureAndRetry() async throws {
        let owner = try owner(); let transport = PlayRecoveryRecordingTransport(); prepare(transport)
        let model = try make(transport, current: { owner }); await model.start(); model.beginTeamSurface()
        transport.responses["/fixture/api/play/advanced/leaderboard"] = .failure(.unknownResult)
        await model.loadAdvancedLeaderboard(); XCTAssertEqual(model.leaderboardPhase, "failed"); XCTAssertTrue(model.leaderboard.isEmpty)
        transport.responses["/fixture/api/play/advanced/leaderboard"] = .reply(PlayExperienceSyntheticFixtures.envelope("[]"), 200)
        await model.loadAdvancedLeaderboard(); XCTAssertEqual(model.leaderboardPhase, "ready"); XCTAssertTrue(model.leaderboard.isEmpty)
    }
    func testLeaderboard401ClosesReadyTeamInteraction() async throws {
        let owner = try owner(); let transport = PlayRecoveryRecordingTransport(); prepare(transport)
        let model = try make(transport, current: { owner }); await model.start(); model.beginTeamSurface()
        XCTAssertTrue(model.canTeamInteract)
        transport.responses["/fixture/api/play/advanced/leaderboard"] = .reply(Data("{\"code\":401}".utf8), 200)
        await model.loadAdvancedLeaderboard()
        XCTAssertEqual(model.phase, "stale"); XCTAssertFalse(model.canTeamInteract)
        XCTAssertNil(model.teamProjection); XCTAssertTrue(model.leaderboard.isEmpty)
        XCTAssertThrowsError(try model.reviewTeamAction(.completeUnit))
    }
    func testOldEpochLate401DoesNotInvalidateCurrentSession() async throws {
        var current: PlayExperienceSession? = try owner(); let transport = PlayRecoveryRecordingTransport(); prepare(transport)
        let old = try make(transport, current: { current }); await old.start(); old.beginTeamSurface()
        transport.responses["/fixture/api/play/advanced/leaderboard"] = .reply(Data("{\"code\":401}".utf8), 200)
        transport.pauseResponse = true
        let read = Task { await old.loadAdvancedLeaderboard() }; await wait(transport)
        current = try owner(2)
        let freshTransport = PlayRecoveryRecordingTransport(); prepare(freshTransport)
        let fresh = try make(freshTransport, current: { current }); await fresh.start(); fresh.beginTeamSurface()
        transport.resumeResponse(); await read.value
        XCTAssertTrue(fresh.canTeamInteract); XCTAssertEqual(fresh.phase, "ready")
        XCTAssertEqual(current?.epoch, 2); XCTAssertTrue(old.leaderboard.isEmpty)
    }
    func testRepeatedActiveAndBackgroundReturnDoNotStrandBoardLoading() async throws {
        let owner = try owner(); let transport = PlayRecoveryRecordingTransport(); prepare(transport)
        let model = try make(transport, current: { owner }); await model.start(); model.beginTeamSurface()
        transport.pauseResponse = true
        let read = Task { await model.loadAdvancedLeaderboard() }; await wait(transport)
        model.beginTeamSurface() // Repeated foreground callback is idempotent.
        transport.resumeResponse(); await read.value
        XCTAssertEqual(model.leaderboardPhase, "ready")
        model.endTeamSurface(); XCTAssertEqual(model.leaderboardPhase, "idle")
        model.beginTeamSurface(); await model.loadAdvancedLeaderboard()
        XCTAssertEqual(model.leaderboardPhase, "ready"); XCTAssertEqual(model.leaderboard.count, 1)
    }
    func testOldInlineDisappearanceCannotCancelNewFallbackSurface() async throws {
        let owner = try owner(); let transport = PlayRecoveryRecordingTransport(); prepare(transport)
        let model = try make(transport, current: { owner }); await model.start()
        let inline = UUID(), fallback = UUID()
        model.beginTeamSurface(id: inline)
        let oldReview = try model.reviewTeamAction(.completeUnit, surfaceID: inline)
        model.beginTeamSurface(id: fallback); model.endTeamSurface(id: inline)
        XCTAssertNoThrow(try model.reviewTeamAction(.completeUnit, surfaceID: fallback))
        await model.submitTeamReview(oldReview)
        await model.loadAdvancedLeaderboard(surfaceID: inline)
        XCTAssertNil(model.issue)
        XCTAssertThrowsError(try model.reviewTeamAction(.completeUnit, surfaceID: inline))
        XCTAssertEqual(transport.requests.count, 1)
        await model.loadAdvancedLeaderboard(surfaceID: fallback); XCTAssertEqual(model.leaderboardPhase, "ready")
        model.endTeamSurface(id: fallback)
        XCTAssertThrowsError(try model.reviewTeamAction(.completeUnit, surfaceID: fallback))
    }
    func testLateLeaderboardAfterExitCannotRepopulate() async throws {
        let owner = try owner(); let transport = PlayRecoveryRecordingTransport(); prepare(transport)
        let model = try make(transport, current: { owner }); await model.start(); model.beginTeamSurface(); transport.pauseResponse = true
        let read = Task { await model.loadAdvancedLeaderboard() }; await wait(transport)
        model.endTeamSurface(); transport.resumeResponse(); await read.value
        XCTAssertTrue(model.leaderboard.isEmpty); XCTAssertEqual(model.leaderboardPhase, "idle")
    }
    func testLateLeaderboardAfterSameAccountReloginIsHidden() async throws {
        var current: PlayExperienceSession? = try owner(); let transport = PlayRecoveryRecordingTransport(); prepare(transport)
        let model = try make(transport, current: { current }); await model.start(); model.beginTeamSurface(); transport.pauseResponse = true
        let read = Task { await model.loadAdvancedLeaderboard() }; await wait(transport)
        current = try owner(2); transport.resumeResponse(); await read.value
        XCTAssertTrue(model.leaderboard.isEmpty); XCTAssertNil(model.leaderboardMetric); XCTAssertNil(model.teamProjection)
    }
}

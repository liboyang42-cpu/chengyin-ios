import XCTest
@testable import QuestifyCore

@MainActor final class NearbyTeamTests: XCTestCase {
    private let session = NearbyTeamSyntheticFixtures.session
    private let context = NearbyTeamSyntheticFixtures.context
    private func response(_ json: String) -> NearbyTeamResponse { NearbyTeamSyntheticFixtures.response(json) }
    private func decode<T: Decodable>(_ json: String, as type: T.Type = T.self) throws -> T { try JSONDecoder().decode(type, from: Data(json.utf8)) }
    private func model(_ steps: [NearbyTeamFakeTransport.Step]) -> (NearbyTeamCoordinator, NearbyTeamFakeTransport) {
        let fake = NearbyTeamFakeTransport(steps: steps)
        return (.init(service: .init(fake: fake), session: session, locks: .init()), fake)
    }
    func testExactNearbyQueryAndRadii() throws {
        let request = try NearbyTeamRequest.nearby(context)
        XCTAssertEqual(request.method, "GET"); XCTAssertEqual(request.path, "/api/team/nearby")
        XCTAssertEqual(request.query, ["lat": "37.78", "lng": "-122.42", "radius": "3000"]); XCTAssertNil(request.body)
        XCTAssertEqual(NearbyQueryContext(latitude: 0, longitude: 0, radius: 20000).nextRadius().radius, 1000)
        for radius in NearbyQueryContext.radii { XCTAssertNoThrow(try NearbyTeamRequest.nearby(.init(latitude: 0, longitude: 0, radius: radius))) }
        XCTAssertThrowsError(try NearbyTeamRequest.nearby(.init(latitude: .nan, longitude: 0)))
        XCTAssertThrowsError(try NearbyTeamRequest.nearby(.init(latitude: 0, longitude: 181)))
    }
    func testExactMutationBodiesUseDistinctIdentities() throws {
        let request = try NearbyTeamRequest.action(.handle(team: .init(12), applicant: .init(34), approved: false))
        XCTAssertEqual(request.path, "/api/team/handle"); XCTAssertEqual(request.method, "POST")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.body)) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["teamId", "memberId", "approved"])
        XCTAssertEqual(object["teamId"] as? Int, 12); XCTAssertEqual(object["memberId"] as? Int, 34); XCTAssertEqual(object["approved"] as? Bool, false)
        for action in [NearbyTeamAction.apply(.init(12)), .withdraw(.init(12))] {
            let r = try NearbyTeamRequest.action(action)
            XCTAssertEqual(r.path, "/api/team/\(action.operation)"); XCTAssertEqual(String(data: try XCTUnwrap(r.body), encoding: .utf8), "{\"teamId\":12}")
        }
        XCTAssertNil(NearbyTeamRequest.myApplications().body)
        XCTAssertFalse(try NearbyTeamRequest.applications(.init(12)).mutation)
    }
    func testServerExpirySecondsMillisecondsAndNoInventedDeadline() throws {
        let seconds: NearbyServerTime = try decode("\"1700000000\"")
        let millis: NearbyServerTime = try decode("1700000000000")
        XCTAssertEqual(seconds.date(), millis.date())
        XCTAssertNil(NearbyServerTime.text("nonsense").date())
        XCTAssertNil(NearbyServerTime.text("123").date())
        XCTAssertNil(NearbyServerTime.number(.infinity).date())
        XCTAssertNil(NearbyServerTime.number(1e100).date())
        let now = Date(timeIntervalSince1970: 1700000000)
        XCTAssertNil(seconds.remainingMinutes(now: now))
        XCTAssertEqual(NearbyServerTime.number(1700000001000).remainingMinutes(now: now), 1)
        XCTAssertEqual(NearbyServerTime.number(1700003600000).remainingMinutes(now: now), 60)
    }
    func testErrorCodeMatrixNeverMatchesMessage() {
        XCTAssertEqual(NearbyErrorEffect.resolve(operation: "apply", errorCode: ""), .init())
        XCTAssertEqual(NearbyErrorEffect.resolve(operation: "apply", errorCode: "TEAM_FULL").dropTeam, true)
        for code in ["TEAM_FULL", "ACTIVITY_STARTED", "TEAM_UNDER_REVIEW", "TEAM_NOT_PUBLIC"] { XCTAssertTrue(NearbyErrorEffect.resolve(operation: "apply", errorCode: code).dropTeam) }
        XCTAssertEqual(NearbyErrorEffect.resolve(operation: "apply", errorCode: "TICKET_REQUIRED").ticket, false)
        XCTAssertEqual(NearbyErrorEffect.resolve(operation: "apply", errorCode: "TICKET_REQUIRED").status, NearbyViewerStatus.none)
        XCTAssertEqual(NearbyErrorEffect.resolve(operation: "apply", errorCode: "APPLY_REJECTED").status, .rejected)
        XCTAssertEqual(NearbyErrorEffect.resolve(operation: "apply", errorCode: "APPLY_PENDING").status, .pending)
        XCTAssertEqual(NearbyErrorEffect.resolve(operation: "apply", errorCode: "ALREADY_JOINED").status, .joined)
        for code in ["APPLY_NOT_PENDING", "TICKET_REQUIRED", "APPLY_BLOCKED"] { XCTAssertTrue(NearbyErrorEffect.resolve(operation: "handle", errorCode: code).dropApplicant) }
        XCTAssertTrue(NearbyErrorEffect.resolve(operation: "handle", errorCode: "TEAM_FULL").refresh)
        XCTAssertTrue(NearbyErrorEffect.resolve(operation: "withdraw", errorCode: "APPLY_NOT_PENDING").refresh)
        XCTAssertFalse(NearbyErrorEffect.resolve(operation: "apply", errorCode: "APPLY_BLOCKED").dropTeam)
    }
    func testUnknownStatusAndPrivateFieldsCannotAuthorize() throws {
        let team: NearbyTeam = try decode("{\"teamId\":8,\"viewerStatus\":\"captain\",\"viewerHasTicket\":\"true\",\"leaderMemberId\":7001,\"inviteCode\":\"private\"}")
        XCTAssertEqual(team.viewerStatus, .unknown); XCTAssertFalse(team.viewerHasTicket); XCTAssertEqual(team.mode, "unknown")
    }
    func testDefaultServiceCannotReadOrSubmit() async {
        let service = NearbyTeamService()
        XCTAssertFalse(service.configured); XCTAssertFalse(service.synthetic)
        do { _ = try await service.nearby(context, session: session); XCTFail() } catch { XCTAssertEqual(error as? NearbyTeamFailure, .unconfigured) }
        let outcome = await service.submit(.apply(.init(1)), session: session); XCTAssertEqual(outcome, .notSent)
    }
    func testApplyRequiresPresentNoneStatusAndTicketEvidence() async throws {
        let (model, fake) = model([.response(response(NearbyTeamSyntheticFixtures.teams))])
        XCTAssertFalse(model.allowed(.apply(.init(501))))
        await model.loadNearby(context)
        XCTAssertTrue(model.allowed(.apply(.init(501))))
        for id in [502, 503, 504, 505, 506, 999] { XCTAssertFalse(model.allowed(.apply(.init(id)))) }
        model.prepare(.apply(.init(501)))
        let review = try XCTUnwrap(model.review)
        let original = try XCTUnwrap(review.team)
        XCTAssertEqual(original.viewerStatus, NearbyViewerStatus.none); XCTAssertTrue(original.viewerHasTicket)
        // NONE is a concrete server status, not Optional.none. Both review and dispatch require it.
        for status in [NearbyViewerStatus.none, .pending, .joined, .leader, .rejected, .unknown] {
            for ticket in [false, true] {
                var team = original; team.patch(status: status, ticket: ticket)
                let snapshot = NearbyTeamReview(id: UUID(), action: review.action, session: session, revision: review.revision, team: team, applicant: nil, application: nil)
                let evidence = NearbyTeamWriteEvidence(session: session, team: team)
                XCTAssertEqual(evidence.validates(snapshot, now: Date()), status == NearbyViewerStatus.none && ticket)
            }
        }
        let missing = NearbyTeamReview(id: UUID(), action: review.action, session: session, revision: review.revision, team: nil, applicant: nil, application: nil)
        XCTAssertFalse(NearbyTeamWriteEvidence(session: session, team: nil).validates(missing, now: Date()))
        XCTAssertEqual(fake.requests.count, 1)
    }
    func testWithdrawResetsStatusAndExpiryWithoutAllowingReplay() async throws {
        let (model, fake) = model([.response(response(NearbyTeamSyntheticFixtures.teams)), .response(response(NearbyTeamSyntheticFixtures.applications)), .response(response("{\"code\":200}"))])
        await model.loadNearby(context); await model.loadMine()
        model.prepare(.withdraw(.init(502)))
        let review = try XCTUnwrap(model.review)
        XCTAssertEqual(review.team?.viewerStatus, .pending); XCTAssertNotNil(review.team?.applyExpireTime)
        await model.confirm(review)
        let team = try XCTUnwrap(model.teams.first { $0.id == .init(502) })
        XCTAssertEqual(team.viewerStatus, NearbyViewerStatus.none); XCTAssertNil(team.applyExpireTime)
        XCTAssertEqual(model.myApplications.map(\.id), [.init(506)])
        XCTAssertFalse(model.allowed(.withdraw(.init(502))))
        await model.confirm(review); XCTAssertEqual(fake.requests.count, 3)
    }
    func testApplyCopiesOnlyServerExpiryAndPreventsReplay() async throws {
        let (model, fake) = model([.response(response(NearbyTeamSyntheticFixtures.teams)), .response(response("{\"code\":200,\"data\":{\"applyExpireTime\":\"2099-10-02T01:00:00Z\"}}"))])
        await model.loadNearby(context); model.prepare(.apply(.init(501)))
        let review = try XCTUnwrap(model.review); await model.confirm(review); await model.confirm(review)
        XCTAssertEqual(fake.requests.count, 2); XCTAssertEqual(model.teams[0].viewerStatus, .pending)
        XCTAssertEqual(model.teams[0].applyExpireTime, .text("2099-10-02T01:00:00Z"))
    }
    func testMissingSuccessExpiryRemainsNil() async throws {
        let (model, _) = model([.response(response(NearbyTeamSyntheticFixtures.teams)), .response(response("{\"code\":200}"))])
        await model.loadNearby(context); model.prepare(.apply(.init(501))); await model.confirm(try XCTUnwrap(model.review))
        XCTAssertNil(model.teams[0].applyExpireTime)
    }
    func testNetworkAmbiguityLocksAcrossSessionEpochAndRecreation() async throws {
        let locks = NearbyTeamLockStore()
        let fake = NearbyTeamFakeTransport(steps: [.response(response(NearbyTeamSyntheticFixtures.teams)), .failure])
        let model = NearbyTeamCoordinator(service: .init(fake: fake), session: session, locks: locks)
        await model.loadNearby(context); model.prepare(.apply(.init(501))); await model.confirm(try XCTUnwrap(model.review))
        XCTAssertTrue(model.uncertain); XCTAssertEqual(model.teams[0].viewerStatus, .none)
        model.bind(nil); model.bind(.init(accountID: session.accountID, epoch: 2, region: session.region, namespace: session.namespace, role: "player")); XCTAssertTrue(model.uncertain)
        let restored = NearbyTeamCoordinator(service: .init(fake: fake), session: session, locks: locks); XCTAssertTrue(restored.uncertain)
        XCTAssertEqual(fake.requests.count, 2)
    }
    func testErrorMessageWithoutCodeDoesNotPatch() async throws {
        let (model, _) = model([.response(response(NearbyTeamSyntheticFixtures.teams)), .response(response("{\"code\":409,\"msg\":\"TEAM_FULL\"}"))])
        await model.loadNearby(context); model.prepare(.apply(.init(501))); await model.confirm(try XCTUnwrap(model.review))
        XCTAssertEqual(model.teams.count, 6); XCTAssertEqual(model.teams[0].viewerStatus, .none); XCTAssertFalse(model.uncertain)
        XCTAssertEqual(model.serverMessage, "TEAM_FULL"); XCTAssertEqual(model.messageKey, "nearby.actionFailed")
    }
    func testLeaderAndApplicantGuardsAndRejectReceipt() async throws {
        let (model, fake) = model([.response(response(NearbyTeamSyntheticFixtures.teams)), .response(response(NearbyTeamSyntheticFixtures.applicants)), .response(response("{\"code\":200}"))])
        await model.loadNearby(context); await model.loadApplicants(teamID: .init(501)); XCTAssertEqual(fake.requests.count, 1)
        await model.loadApplicants(teamID: .init(503))
        XCTAssertFalse(model.allowed(.handle(team: .init(503), applicant: .init(503), approved: true)))
        model.prepare(.handle(team: .init(503), applicant: .init(6001), approved: false)); await model.confirm(try XCTUnwrap(model.review))
        XCTAssertTrue(model.applicants.isEmpty); XCTAssertEqual(fake.requests.count, 3)
    }
    func testExpiredApplicantCannotBeReviewed() async {
        let (model, _) = model([.response(response(NearbyTeamSyntheticFixtures.teams)), .response(response("{\"code\":200,\"data\":[{\"memberId\":6001,\"applyExpireTime\":1700000000000}]}"))])
        await model.loadNearby(context); await model.loadApplicants(teamID: .init(503))
        XCTAssertFalse(model.allowed(.handle(team: .init(503), applicant: .init(6001), approved: true)))
    }
    func testCancelledReviewAndChangedSessionNeverSend() async throws {
        let (model, fake) = model([.response(response(NearbyTeamSyntheticFixtures.teams))])
        await model.loadNearby(context); model.prepare(.apply(.init(501))); let review = try XCTUnwrap(model.review)
        model.cancelReview(); await model.confirm(review); XCTAssertEqual(fake.requests.count, 1)
        model.prepare(.apply(.init(501))); let next = try XCTUnwrap(model.review); model.bind(nil); await model.confirm(next)
        XCTAssertEqual(fake.requests.count, 1); XCTAssertTrue(model.teams.isEmpty)
    }
    func testLateReadAfterLogoutIsDiscarded() async {
        let (model, fake) = model([.suspended])
        let task = Task { await model.loadNearby(context) }
        while fake.requests.isEmpty { await Task.yield() }
        model.bind(nil); fake.resume(response(NearbyTeamSyntheticFixtures.teams)); await task.value
        XCTAssertTrue(model.teams.isEmpty); XCTAssertFalse(model.busy)
    }
    func testLateMutationUnknownSurvivesLogout() async throws {
        let (model, fake) = model([.response(response(NearbyTeamSyntheticFixtures.teams)), .suspended])
        await model.loadNearby(context); model.prepare(.apply(.init(501))); let review = try XCTUnwrap(model.review)
        let task = Task { await model.confirm(review) }
        while fake.requests.count < 2 { await Task.yield() }
        model.bind(nil); fake.resume(response("{\"wrong\":true}")); await task.value; model.bind(session)
        XCTAssertTrue(model.uncertain); XCTAssertTrue(model.teams.isEmpty)
    }
    func testMarkerNamespacingAndCoordinatesDoNotAuthorize() throws {
        let team: NearbyTeam = try decode("{\"teamId\":12,\"activityId\":98,\"latitude\":0,\"longitude\":0,\"viewerStatus\":\"NONE\"}")
        XCTAssertEqual(NearbyTeamBridge.markers([team]).first?.id, "124")
        XCTAssertEqual(NearbyTeamBridge.markerDestination("124"), .team(.init(12)))
        XCTAssertNil(NearbyTeamBridge.markerDestination("121")); XCTAssertNil(NearbyTeamBridge.markerDestination("123"))
        XCTAssertEqual(NearbyTeamBridge.purchaseDestination(team), .activity(98)); XCTAssertFalse(team.viewerHasTicket)
        XCTAssertEqual(NearbyTeamBridge.roamQuery(latitude: 0, longitude: 0).radius, 1000)
    }
    func testJoinedRowsWinAndRejectedDoesNotCount() throws {
        let joined: [OwnedTeam] = try decode("[{\"id\":12,\"status\":0,\"ownerType\":2,\"ownerId\":91},{\"id\":13,\"status\":3}]")
        let applications: [NearbyMyApplication] = try decode("[{\"teamId\":12,\"applyStatus\":\"PENDING\"},{\"teamId\":14,\"applyStatus\":\"REJECTED\"},{\"teamId\":15,\"applyStatus\":\"PENDING\"}]")
        let rows = NearbyTeamBridge.myRows(joined: joined, applications: applications)
        XCTAssertEqual(rows.map(\.id), [.init(12), .init(14), .init(15)]); XCTAssertEqual(NearbyTeamBridge.activeCount(rows), 2)
        if case .joined(let team) = rows[0] { XCTAssertEqual(team.ownerID, 91) } else { XCTFail() }
    }
    func testMerchantRoleDoesNotRead() async {
        let (model, fake) = model([])
        model.bind(.init(accountID: 1, epoch: 1, region: "US", namespace: "test", role: "merchant"))
        await model.loadNearby(context); XCTAssertTrue(fake.requests.isEmpty)
    }
}

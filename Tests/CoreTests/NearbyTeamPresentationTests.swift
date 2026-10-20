import XCTest
@testable import QuestifyCore

/// Mini-program subpackageRoam/nearby + my-teams presentation over already-read rows (map-team.js, my-teams/index.js).
@MainActor final class NearbyTeamPresentationTests: XCTestCase {
    private func teams(_ json: String) throws -> [NearbyTeam] { try JSONDecoder().decode([NearbyTeam].self, from: Data(json.utf8)) }

    func testBadgesFollowCardModeTable() throws {
        let rows = try teams(#"[{"teamId":1,"viewerStatus":"NONE","viewerHasTicket":false},{"teamId":2,"viewerStatus":"NONE","viewerHasTicket":true},{"teamId":3,"viewerStatus":"PENDING"},{"teamId":4,"viewerStatus":"JOINED"},{"teamId":5,"viewerStatus":"REJECTED"},{"teamId":6,"viewerStatus":"LEADER"},{"teamId":7,"viewerStatus":"???"}]"#)
        XCTAssertEqual(rows.map { NearbyTeamBadge(mode: $0.mode) }, [.buy, .apply, .pending, .joined, .rejected, .leader, .apply])
        XCTAssertEqual(NearbyTeamBadge.buy.key, "nearby.w208.badge.buy")
    }

    func testDistanceAndRangeMatchMiniProgramKm() {
        XCTAssertEqual(NearbyTeamPresentation.distanceText(0), "0 m")
        XCTAssertEqual(NearbyTeamPresentation.distanceText(999.4), "999 m")
        XCTAssertEqual(NearbyTeamPresentation.distanceText(1000), "1 km")
        XCTAssertEqual(NearbyTeamPresentation.distanceText(1549), "1.5 km")
        XCTAssertEqual(NearbyTeamPresentation.distanceText(-5), "0 m")
        XCTAssertEqual(NearbyTeamPresentation.rangeText(3000), "3 km")
        XCTAssertEqual(NearbyTeamPresentation.rangeText(20000), "20 km")
    }

    func testSeatsHeadingAndPlaceUseOnlyServerFields() throws {
        let rows = try teams(#"[{"teamId":1,"title":"T","activityName":"Clues","joinedCount":3,"maxMembers":4,"coordSource":"GATHER","addressName":"Gate"},{"teamId":2,"title":"Full","joinedCount":4,"maxMembers":4},{"teamId":3,"title":"Over","joinedCount":5,"maxMembers":4,"leaderAvatar":" https://img.example/a.png "}]"#)
        XCTAssertEqual(rows.map(NearbyTeamPresentation.remainingSeats), [1, 0, 0])
        XCTAssertEqual(NearbyTeamPresentation.heading(rows[0]), "Clues")
        XCTAssertEqual(NearbyTeamPresentation.heading(rows[1]), "Full")
        XCTAssertTrue(NearbyTeamPresentation.placeIsGather(rows[0]))
        XCTAssertFalse(NearbyTeamPresentation.placeIsGather(rows[1]))
        XCTAssertEqual(rows[2].leaderAvatar, "https://img.example/a.png")
        XCTAssertEqual(rows[0].leaderAvatar, "")
    }

    func testRecruitingKeepsOnlyUnappliedRows() throws {
        struct Envelope: Decodable { let data: [NearbyTeam] }
        let fixture = try JSONDecoder().decode(Envelope.self, from: Data(NearbyTeamSyntheticFixtures.teams.utf8)).data
        let ids = NearbyTeamPresentation.recruiting(fixture).map(\.id.rawValue)
        XCTAssertEqual(ids, [501, 504])
        XCTAssertEqual(NearbyTeamPresentation.recruitingRadius, 3000)
        XCTAssertTrue(NearbyQueryContext.radii.contains(NearbyTeamPresentation.recruitingRadius))
    }

    func testStartTextAndFaces() {
        XCTAssertEqual(NearbyTeamPresentation.startText("2026-10-19 08:30:00"), "10/19 08:30")
        XCTAssertEqual(NearbyTeamPresentation.startText("2026-10-19T08:30:00"), "10/19 08:30")
        XCTAssertNil(NearbyTeamPresentation.startText("2026-10-19"))
        XCTAssertNil(NearbyTeamPresentation.startText(nil))
        XCTAssertNil(NearbyTeamPresentation.startText("not a date at all!!"))
        XCTAssertEqual(NearbyTeamPresentation.faceCount(real: 0, members: nil), 1)
        XCTAssertEqual(NearbyTeamPresentation.faceCount(real: 1, members: 2), 2)
        XCTAssertEqual(NearbyTeamPresentation.faceCount(real: 0, members: 9), 3)
    }

    func testMyApplicationOptionalCardFields() throws {
        let rows = try JSONDecoder().decode([NearbyMyApplication].self, from: Data(#"[{"teamId":9,"applyStatus":"PENDING","activityName":" Night walk ","leaderAvatar":"a","joinedCount":"2","maxMembers":4},{"teamId":10,"applyStatus":"REJECTED","joinedCount":-1,"maxMembers":0}]"#.utf8))
        XCTAssertEqual(rows[0].activityName, "Night walk"); XCTAssertEqual(rows[0].leaderAvatar, "a")
        XCTAssertEqual(rows[0].joinedCount, 2); XCTAssertEqual(rows[0].maxMembers, 4)
        XCTAssertNil(rows[1].joinedCount); XCTAssertNil(rows[1].maxMembers); XCTAssertEqual(rows[1].activityName, "")
    }

    func testLoadIssueMapping() {
        XCTAssertEqual(NearbyLoadIssue(messageKey: "nearby.signIn"), .signIn)
        XCTAssertEqual(NearbyLoadIssue(messageKey: "nearby.w208.denied"), .denied)
        XCTAssertEqual(NearbyLoadIssue(messageKey: "nearby.loadFailed"), .failed)
        XCTAssertNil(NearbyLoadIssue(messageKey: "nearby.simulated"))
        XCTAssertNil(NearbyLoadIssue(messageKey: nil))
        XCTAssertEqual(NearbyLoadIssue.signIn.actionKey, "nearby.w208.issue.signInAction")
        XCTAssertEqual(NearbyLoadIssue.denied.actionKey, "nearby.w208.issue.retry")
    }

    func testForbiddenReadIsDeniedNotGenericFailure() async {
        for body in [#"{"code":403,"msg":"no"}"#, #"{"code":200,"data":[]}"#] {
            let fake = NearbyTeamFakeTransport(steps: [.response(.init(status: body.contains("403") ? 200 : 403, data: Data(body.utf8)))])
            let model = NearbyTeamCoordinator(service: .init(fake: fake), session: NearbyTeamSyntheticFixtures.session, locks: .init())
            await model.loadNearby(NearbyTeamSyntheticFixtures.context)
            XCTAssertEqual(model.messageKey, "nearby.w208.denied")
            XCTAssertTrue(model.teams.isEmpty); XCTAssertTrue(model.authenticated)
        }
    }
}

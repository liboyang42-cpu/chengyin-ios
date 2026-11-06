import XCTest
@testable import QuestifyCore

final class GrowthAndLeaderboardParityAuditTests: XCTestCase {
    func testLeaderboardFormEncodedBodyAndContentTypeCompliance() {
        let audit = GrowthAndLeaderboardParityAudit()
        XCTAssertTrue(audit.isAllCompliant)
        XCTAssertEqual(audit.contentType, "application/x-www-form-urlencoded")

        let encoded = GrowthAndLeaderboardParityAudit.encodeLeaderboardFormBody(
            type: "SEASON_EXP",
            pageNum: 1,
            pageSize: 20
        )
        XCTAssertEqual(encoded, "type=SEASON_EXP&pageNum=1&pageSize=20")

        XCTAssertNil(GrowthAndLeaderboardParityAudit.encodeLeaderboardFormBody(type: "   ", pageNum: 1, pageSize: 20))
        XCTAssertNil(GrowthAndLeaderboardParityAudit.encodeLeaderboardFormBody(type: "SEASON_EXP", pageNum: 0, pageSize: 20))
        XCTAssertNil(GrowthAndLeaderboardParityAudit.encodeLeaderboardFormBody(type: "SEASON_EXP", pageNum: 1, pageSize: 0))
    }

    func testServerStandingPreservationNeverFabricatesRankWhenAbsent() {
        XCTAssertEqual(
            GrowthAndLeaderboardParityAudit.resolveServerStanding(serverRank: 7),
            .ranked(7)
        )
        XCTAssertEqual(
            GrowthAndLeaderboardParityAudit.resolveServerStanding(serverRank: nil),
            .unrankedServerOmitted
        )
        XCTAssertEqual(
            GrowthAndLeaderboardParityAudit.resolveServerStanding(serverRank: 0),
            .unrankedServerOmitted
        )
        XCTAssertEqual(
            GrowthAndLeaderboardParityAudit.resolveServerStanding(serverRank: -1),
            .unrankedServerOmitted
        )
    }

    func testBlankNicknameAvatarMonogramFallsBackToAnonymousCharacter() {
        XCTAssertEqual(GrowthAndLeaderboardParityAudit.avatarMonogram(for: nil), "匿")
        XCTAssertEqual(GrowthAndLeaderboardParityAudit.avatarMonogram(for: ""), "匿")
        XCTAssertEqual(GrowthAndLeaderboardParityAudit.avatarMonogram(for: "   \n\t "), "匿")
        XCTAssertEqual(GrowthAndLeaderboardParityAudit.avatarMonogram(for: "橙印玩家"), "橙")
        XCTAssertEqual(GrowthAndLeaderboardParityAudit.avatarMonogram(for: "Alice"), "A")
    }

    func testProfileReadFailureSeparates403DeniedFrom401SessionExpiry() {
        let denied403 = GrowthAndLeaderboardParityAudit.classifyHTTPFailure(statusCode: 403)
        XCTAssertTrue(denied403.isDenied)
        XCTAssertFalse(denied403.isSessionExpired)

        let expired401 = GrowthAndLeaderboardParityAudit.classifyHTTPFailure(statusCode: 401)
        XCTAssertFalse(expired401.isDenied)
        XCTAssertTrue(expired401.isSessionExpired)

        let server500 = GrowthAndLeaderboardParityAudit.classifyHTTPFailure(statusCode: 500)
        XCTAssertFalse(server500.isDenied)
        XCTAssertFalse(server500.isSessionExpired)
    }
}

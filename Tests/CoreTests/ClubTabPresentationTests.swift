import XCTest
@testable import QuestifyCore

/// Mini-program pages/talent/list (俱乐部 tab) presentation. Synthetic rows only.
final class ClubTabPresentationTests: XCTestCase {
    private func club(_ json: String) throws -> ClubRecord { try JSONDecoder().decode(ClubRecord.self, from: Data(json.utf8)) }
    private func home(_ json: String) throws -> ClubHome { try JSONDecoder().decode(ClubHome.self, from: Data(json.utf8)) }

    func testSectionMarksOwnerAndJoinedLikeSourceNormalization() throws {
        let row = try club(#"{"id":7,"name":"Synthetic"}"#)
        XCTAssertTrue(ClubTabPresentation.isOwner(row, in: .owned)); XCTAssertFalse(ClubTabPresentation.isOwner(row, in: .joined))
        XCTAssertTrue(ClubTabPresentation.isJoined(row, in: .joined)); XCTAssertFalse(ClubTabPresentation.isJoined(row, in: .nearby))
        XCTAssertFalse(ClubTabPresentation.tags(row, in: .owned).freeToJoin)
        XCTAssertFalse(ClubTabPresentation.tags(row, in: .joined).freeToJoin)
        XCTAssertTrue(ClubTabPresentation.tags(row, in: .nearby).freeToJoin)
        XCTAssertFalse(ClubTabPresentation.tags(try club(#"{"id":7,"isJoined":true}"#), in: .nearby).freeToJoin)
    }

    func testTagSplittingMatchesSourceSplitList() throws {
        let row = try club(#"{"id":7,"clubType":"[\"Walk\",\" Food \",3]","keywords":"Food，Night;Art、Walk"}"#)
        XCTAssertEqual(ClubTabPresentation.tags(row, in: .nearby).labels, ["Walk", "Food", "Night", "Art"])
        XCTAssertEqual(ClubTabPresentation.splitList("[broken"), [])
        XCTAssertEqual(ClubTabPresentation.splitList(nil), [])
    }

    func testLevelCopy() {
        XCTAssertEqual(ClubTabPresentation.levelKey(3).key, "club.tab.level.3")
        XCTAssertEqual(ClubTabPresentation.levelKey(7).fallback, "Lv.7")
        XCTAssertNil(ClubTabPresentation.levelKey(0).key); XCTAssertNil(ClubTabPresentation.levelKey(0).fallback)
    }

    func testEmptyStatesForPlayersAndMerchants() throws {
        let empty = try home("{}")
        XCTAssertTrue(ClubTabPresentation.isEmpty(empty, nearby: [], merchant: false))
        let owned = try home(#"{"owned":[{"id":1}]}"#)
        XCTAssertFalse(ClubTabPresentation.isEmpty(owned, nearby: [], merchant: false))
        XCTAssertTrue(ClubTabPresentation.isEmpty(owned, nearby: [], merchant: true), "merchants see only same-city clubs")
        XCTAssertTrue(ClubTabPresentation.emptyKeys(merchant: false).offersCreate)
        XCTAssertEqual(ClubTabPresentation.emptyKeys(merchant: true).title, "club.tab.empty.merchant")
        XCTAssertEqual(ClubTabPresentation.feedEmptyKeys(clubCount: 0).detail, "club.tab.feed.noClub.detail")
        XCTAssertEqual(ClubTabPresentation.feedEmptyKeys(clubCount: 2).detail, "club.tab.feed.empty.detail")
    }

    func testPriorityMemberBadgeAndTopicCountCopy() {
        let active = ClubPriorityMemberBadge(prioritySignup: true, topicCount: 3)
        XCTAssertEqual(active.badgeText, "成员优先报名")
        XCTAssertEqual(active.topicCountText, "3 个主题")

        let zeroTopics = ClubPriorityMemberBadge(prioritySignup: false, topicCount: 0)
        XCTAssertNil(zeroTopics.badgeText)
        XCTAssertNil(zeroTopics.topicCountText)

        let missingTopics = ClubPriorityMemberBadge(prioritySignup: true, topicCount: nil)
        XCTAssertEqual(missingTopics.badgeText, "成员优先报名")
        XCTAssertNil(missingTopics.topicCountText)
    }

    func testStrictShapeCheckValidatesClubHomeKeys() {
        let valid: [String: Any] = [
            "owned": [],
            "joined": [],
            "nearby": [],
            "leaderStatus": 1
        ]
        XCTAssertTrue(ClubHomeStrictShapeCheck.validate(jsonObject: valid))
        XCTAssertFalse(ClubHomeStrictShapeCheck.validate(jsonObject: ["owned": [], "joined": [], "nearby": []]))
        XCTAssertFalse(ClubHomeStrictShapeCheck.validate(jsonObject: ["owned": [], "joined": [], "nearby": [], "leaderStatus": NSNull()]))
    }
}

final class ClubTabTopTabTests: XCTestCase {
    func testTopTabsMatchSourceOrderAndCopy() {
        XCTAssertEqual(ClubTabPresentation.TopTab.allCases, [.feed, .club])
        XCTAssertEqual(ClubTabPresentation.TopTab.feed.key, "club.tab.top.feed")
        XCTAssertEqual(ClubTabPresentation.TopTab.club.key, "club.tab.top.club")
    }
}

import XCTest
@testable import QuestifyCore

final class ClubContractTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }
    func testAbsentMembershipIsNotPendingAndDoesNotGrantAccess() throws {
        let club = try decode(ClubRecord.self, #"{"id":7,"name":"Fixture"}"#)
        XCTAssertFalse(club.isJoined); XCTAssertFalse(club.isOwner); XCTAssertFalse(club.viewerIsAdmin)
        XCTAssertFalse(club.canSeeMembers); XCTAssertFalse(club.canGovern)
        XCTAssertNil(club.myJoinStatus); XCTAssertFalse(club.joinPending)
    }
    func testViewerAdministrationDoesNotGrantMemberListAccess() throws {
        let club = try decode(ClubRecord.self, #"{"id":7,"viewerIsAdmin":true}"#)
        XCTAssertTrue(club.canGovern)
        XCTAssertFalse(club.canSeeMembers)
    }
    func testJoinedAndOwnerIndependentlyGrantSourceMemberVisibility() throws {
        for field in ["isJoined", "isOwner"] {
            let club = try decode(ClubRecord.self, "{\"id\":7,\"\(field)\":true}")
            XCTAssertTrue(club.canSeeMembers)
        }
    }
    func testStringOrNumericRoleFlagsNeverGrantPermission() {
        for json in [#"{"id":7,"isOwner":"true"}"#, #"{"id":7,"isJoined":1}"#, #"{"id":7,"viewerIsAdmin":"true"}"#] {
            XCTAssertThrowsError(try decode(ClubRecord.self, json))
        }
    }
    func testUnknownJoinStatusIsRetainedWithoutGuessingPending() throws {
        let club = try decode(ClubRecord.self, #"{"id":7,"myJoinStatus":91,"joinPolicy":8}"#)
        XCTAssertEqual(club.myJoinStatus, 91); XCTAssertFalse(club.joinPending)
        XCTAssertEqual(club.joinPolicy, 0); XCTAssertFalse(club.needsApproval)
        XCTAssertTrue(try decode(ClubRecord.self, #"{"id":7,"myJoinStatus":0,"joinPolicy":1}"#).joinPending)
    }
    func testRawStringsAndURLFieldsArePreserved() throws {
        let club = try decode(ClubRecord.self, #"{"id":7,"name":"  Source name  ","logo":"/uploads/club.png","cover":"https://cdn.example.com/cover.png?q=1","description":"Server text","activityPrefs":" walking,, photography, "}"#)
        XCTAssertEqual(club.name, "  Source name  ")
        XCTAssertEqual(club.logo, "/uploads/club.png")
        XCTAssertEqual(club.cover, "https://cdn.example.com/cover.png?q=1")
        XCTAssertEqual(club.activityPrefs, [" walking", " photography"])
    }
    func testHomePreservesFourSectionsAndDoesNotInferMembershipFromSection() throws {
        let home = try decode(ClubHome.self, #"{"owned":[{"id":1}],"joined":[{"id":2}],"nearby":[{"id":3}],"events":[{"id":4,"title":"Server event","clubId":1}]}"#)
        XCTAssertEqual(home.owned.map(\.id), [1]); XCTAssertEqual(home.joined.map(\.id), [2])
        XCTAssertEqual(home.nearby.map(\.id), [3]); XCTAssertEqual(home.events.map(\.id), [4])
        XCTAssertFalse(home.owned[0].isOwner)
        XCTAssertFalse(home.joined[0].isJoined)
        XCTAssertFalse(home.isEmpty)
    }
    func testMissingHomeSectionsUseSourceEmptyDefaults() throws {
        XCTAssertTrue(try decode(ClubHome.self, "{}").isEmpty)
        XCTAssertThrowsError(try decode(ClubHome.self, #"{"nearby":{}}"#))
    }
    func testHomeEventUsesTitleCoverAndClubIDNotTopicEntityFields() throws {
        let event = try decode(ClubHomeEvent.self, #"{"id":4,"clubId":1,"title":"Event title","cover":"event.png","name":"Wrong","imgUrl":"wrong.png"}"#)
        XCTAssertEqual(event.title, "Event title"); XCTAssertEqual(event.cover, "event.png"); XCTAssertEqual(event.clubId, 1)
    }
    func testMemberOwnerAndAdministratorAreDistinct() throws {
        let member = try decode(ClubMember.self, #"{"memberId":9,"role":1,"isOwner":false,"nickname":"  Fixture  "}"#)
        XCTAssertTrue(member.isAdmin); XCTAssertFalse(member.isOwner)
        XCTAssertEqual(member.trimmedNickname, "Fixture")
        let creator = try decode(ClubMember.self, #"{"memberId":8,"role":0,"isOwner":true}"#)
        XCTAssertTrue(creator.isOwner); XCTAssertFalse(creator.isAdmin)
    }
    func testUnknownMemberRoleStaysUnknownAndBlankNicknameUsesIDFallback() throws {
        let member = try decode(ClubMember.self, #"{"memberId":9,"role":48,"nickname":"  "}"#)
        XCTAssertEqual(member.role, 48); XCTAssertFalse(member.isAdmin); XCTAssertNil(member.trimmedNickname)
    }
    func testMemberDisplayUsesOnlyReturnedLevelAndJoinTime() throws {
        let member = try decode(ClubMember.self, #"{"memberId":9,"levelId":4,"joinTime":"2026-02-03 10:15:00"}"#)
        XCTAssertEqual(member.levelId, 4)
        XCTAssertEqual(member.displayedLevel, 4)
        XCTAssertEqual(member.joinTime, "2026-02-03 10:15:00")
        XCTAssertEqual(member.displayedJoinTime, "2026-02-03 10:15:00")
        XCTAssertFalse(member.isOwner); XCTAssertFalse(member.isAdmin)
    }
    func testMemberDisplayOmitsMissingNullAndNonpositiveLevels() throws {
        for fields in ["", ",\"levelId\":null", ",\"levelId\":0", ",\"levelId\":-1"] {
            let member = try decode(ClubMember.self, "{\"memberId\":9\(fields)}")
            XCTAssertNil(member.displayedLevel)
        }
        let member = try decode(ClubMember.self, #"{"memberId":9,"level":8,"playerLevel":5}"#)
        XCTAssertNil(member.levelId); XCTAssertNil(member.displayedLevel)
    }
    func testMemberDisplayDoesNotLimitValidSourceLevelToClubHostLevels() throws {
        let member = try decode(ClubMember.self, #"{"memberId":9,"levelId":37}"#)
        XCTAssertEqual(member.displayedLevel, 37)
        XCTAssertEqual(member.role, 0); XCTAssertFalse(member.isAdmin); XCTAssertFalse(member.isOwner)
    }
    func testMemberDisplayOmitsMissingNullAndBlankJoinTimes() throws {
        for json in [#"{"memberId":9}"#, #"{"memberId":9,"joinTime":null}"#,
                     #"{"memberId":9,"joinTime":""}"#, #"{"memberId":9,"joinTime":"  \n  "}"#] {
            let member = try decode(ClubMember.self, json)
            XCTAssertNil(member.displayedJoinTime)
        }
        let member = try decode(ClubMember.self, #"{"memberId":9,"createTime":"2026-02-03","joinedAt":"2026-02-04"}"#)
        XCTAssertNil(member.joinTime); XCTAssertNil(member.displayedJoinTime)
    }
    func testMemberDisplayKeepsServerDateTextWithoutTimezoneGuess() throws {
        let member = try decode(ClubMember.self, #"{"memberId":9,"joinTime":"  2026-02-03 10:15:00  "}"#)
        XCTAssertEqual(member.joinTime, "  2026-02-03 10:15:00  ")
        XCTAssertEqual(member.displayedJoinTime, "2026-02-03 10:15:00")
    }
    func testCreatorDisplaySuppressesJoinTimeButKeepsReturnedLevel() throws {
        let member = try decode(ClubMember.self, #"{"memberId":9,"isOwner":true,"role":2,"levelId":7,"joinTime":"2026-01-01 09:00:00"}"#)
        XCTAssertEqual(member.joinTime, "2026-01-01 09:00:00")
        XCTAssertNil(member.displayedJoinTime)
        XCTAssertEqual(member.displayedLevel, 7)
        XCTAssertTrue(member.isOwner); XCTAssertFalse(member.isAdmin)
    }
    func testAdministratorDisplayDoesNotHideJoinTimeOrPromoteOwner() throws {
        let member = try decode(ClubMember.self, #"{"memberId":9,"role":1,"levelId":4,"joinTime":"2026-02-03 10:15:00"}"#)
        XCTAssertEqual(member.displayedJoinTime, "2026-02-03 10:15:00")
        XCTAssertTrue(member.isAdmin); XCTAssertFalse(member.isOwner)
    }
    func testMalformedMemberDisplayTypesFailWithoutCoercion() throws {
        for fields in [#""levelId":"4""#, #""levelId":true"#, #""levelId":1.5"#,
                       #""levelId":{}"#, #""joinTime":20260203"#, #""joinTime":true"#,
                       #""joinTime":[]"#, #""joinTime":{}"#] {
            XCTAssertThrowsError(try decode(ClubMember.self, "{\"memberId\":9,\(fields)}"), fields)
        }
    }
    func testEmptyMembersDoesNotContradictReportedCount() throws {
        let populated = try decode(ClubRecord.self, #"{"id":7,"memberCount":128}"#)
        let empty = try decode(ClubRecord.self, #"{"id":7,"memberCount":0}"#)
        XCTAssertTrue(ClubMemberDirectory(club: populated, members: []).isReportedListUnavailable)
        XCTAssertFalse(ClubMemberDirectory(club: empty, members: []).isReportedListUnavailable)
    }
    func testInvalidIdentitiesCannotCreateNavigableRows() {
        for json in ["{}", #"{"id":0}"#, #"{"id":-1}"#, #"{"id":"7"}"#] {
            XCTAssertThrowsError(try decode(ClubRecord.self, json))
        }
        XCTAssertThrowsError(try decode(ClubMember.self, #"{"memberId":0}"#))
        XCTAssertThrowsError(try decode(ClubHomeEvent.self, #"{"id":4,"clubId":0}"#))
    }
}

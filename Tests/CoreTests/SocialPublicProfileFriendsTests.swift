import XCTest
@testable import QuestifyCore

final class SocialPublicProfileFriendsTests: XCTestCase {
    func testFriendCountIsReadFromPublicMemberAndAbsentStaysUnknown() throws {
        let value = try JSONDecoder().decode(SocialPublicProfile.self, from: Data(#"{"id":5,"friendNum":3,"followNum":4,"fansNum":6}"#.utf8))
        XCTAssertEqual(value.friends, 3); XCTAssertEqual(value.following, 4); XCTAssertEqual(value.followers, 6)
        let absent = try JSONDecoder().decode(SocialPublicProfile.self, from: Data(#"{"id":5}"#.utf8))
        XCTAssertNil(absent.friends)
    }
}

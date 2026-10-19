import XCTest
@testable import QuestifyCore

final class PlayCircleLegacyLinkTests: XCTestCase {
    func testOldShareLinksRedirectToUnifiedPlayOrShowMissingState() {
        XCTAssertEqual(PlayCircleLegacyLink.resolve([:]), .missingParameter)
        XCTAssertEqual(PlayCircleLegacyLink.resolve(["topicId": ""]), .missingParameter)
        XCTAssertEqual(PlayCircleLegacyLink.resolve(["topicId": "abc", "themeCode": "FITNESS"]), .missingParameter)
        XCTAssertEqual(PlayCircleLegacyLink.resolve(["topicId": "12", "themeCode": "FITNESS"]), .play(topicID: 12, inviteCode: nil, registrationID: nil))
        let link = PlayCircleLegacyLink.resolve(["topicId": " 12 ", "inviteCode": " AB12 ", "registrationId": "88"])
        XCTAssertEqual(link, .play(topicID: 12, inviteCode: "AB12", registrationID: 88))
        XCTAssertEqual(link.playScope, .topic(12))
        XCTAssertEqual(PlayCircleLegacyLink.resolve(["topicId": "12", "inviteCode": "a b/../", "registrationId": "-1"]), .play(topicID: 12, inviteCode: nil, registrationID: nil))
        XCTAssertNil(PlayCircleLegacyLink.missingParameter.playScope)
    }
}

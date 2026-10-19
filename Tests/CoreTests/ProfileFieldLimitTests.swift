import XCTest
@testable import QuestifyCore

final class ProfileFieldLimitTests: XCTestCase {
    func testShortTextIsUntouchedAndLongTextStopsAt140Units() {
        XCTAssertEqual(ProfileFieldLimit.clamp("城市漫步"), "城市漫步")
        let long = String(repeating: "走", count: 150)
        XCTAssertEqual(ProfileFieldLimit.count(ProfileFieldLimit.clamp(long)), 140)
        XCTAssertTrue(ProfileFieldLimit.exceeds(long)); XCTAssertFalse(ProfileFieldLimit.exceeds(String(repeating: "走", count: 140)))
    }
    func testSurrogatePairsAndClustersAreNeverSplit() {
        let text = String(repeating: "a", count: 139) + "🚲x"
        let clamped = ProfileFieldLimit.clamp(text)
        XCTAssertEqual(clamped, String(repeating: "a", count: 139))
        XCTAssertEqual(ProfileFieldLimit.clamp(String(repeating: "🚲", count: 71)).count, 70)
    }
}

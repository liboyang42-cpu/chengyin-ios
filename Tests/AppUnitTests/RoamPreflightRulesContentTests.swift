import XCTest
@testable import Questify

final class RoamPreflightRulesContentTests: XCTestCase {
    func testRulesAppearInExistingLiveFlowOrder() {
        XCTAssertEqual(RoamPreflightRule.allCases, [.explore, .arrival, .finish, .privacy])
    }
    func testStableSectionIdentifiersAreUnique() {
        XCTAssertEqual(Set(RoamPreflightRule.allCases.map(\.id)), ["explore", "arrival", "finish", "privacy"])
    }
    func testExploreReusesNativeLiveRuleWithoutIndependentRadius() {
        XCTAssertEqual(RoamPreflightRule.explore.titleKey, "roam.live.ruleExploreTitle")
        XCTAssertEqual(RoamPreflightRule.explore.bodyKeys, ["roam.live.ruleExplore"])
    }
    func testArrivalKeepsServerCheckedArrivalCopy() {
        XCTAssertEqual(RoamPreflightRule.arrival.titleKey, "roam.live.ruleArrivalTitle")
        XCTAssertEqual(RoamPreflightRule.arrival.bodyKeys, ["roam.live.ruleArrival"])
    }
    func testFinishKeepsMeasuredRecordAndConfirmedAwardCopy() {
        XCTAssertEqual(RoamPreflightRule.finish.titleKey, "roam.live.ruleFinishTitle")
        XCTAssertEqual(RoamPreflightRule.finish.bodyKeys, ["roam.live.ruleFinish"])
    }
    func testPrivacyIncludesBothPresenceDisclosureAndPauseBoundary() {
        XCTAssertEqual(RoamPreflightRule.privacy.titleKey, "roam.live.rulePrivacyTitle")
        XCTAssertEqual(RoamPreflightRule.privacy.bodyKeys, ["roam.live.presencePrivacy", "roam.live.leaveHint"])
    }
    func testEveryDisplayedBodyHasAStableDistinctKey() {
        let keys = RoamPreflightRule.allCases.flatMap(\.bodyKeys)
        XCTAssertEqual(keys.count, 5); XCTAssertEqual(Set(keys).count, keys.count)
        XCTAssertTrue(keys.allSatisfy { $0.hasPrefix("roam.live.") })
    }
}

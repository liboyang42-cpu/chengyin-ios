import XCTest
@testable import QuestifyCore

final class RootTabTests: XCTestCase {
    func testOrderMatchesMiniProgramConsumerTabBar() {
        XCTAssertEqual(RootTab.allCases, [.home, .roam, .publish, .club, .mine])
        XCTAssertEqual(RootTab.allCases.map(\.rawValue), [0, 1, 2, 3, 4])
    }

    func testEveryTabHasDistinctTitleKeyAndIcon() {
        let keys = RootTab.allCases.map(\.titleKey)
        XCTAssertEqual(keys, ["tabBar.home", "tabBar.roam", "tabBar.publish", "tabBar.club", "tabBar.mine"])
        XCTAssertEqual(Set(RootTab.allCases.map(\.systemImage)).count, RootTab.allCases.count)
    }
}

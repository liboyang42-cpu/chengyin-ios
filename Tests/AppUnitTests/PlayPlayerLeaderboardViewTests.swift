import XCTest
import SwiftUI
@testable import Questify

/// Synthetic App-hosted checks only. Apple execution and visual acceptance are separate.
@MainActor final class PlayPlayerLeaderboardViewTests: XCTestCase {
    func testVisibleRankingConstructsInBothLocalesIncludingZeroScore() {
        let rows = [PlayPlayerLeaderboardEntry(id: 8, rank: 1, displayName: "Synthetic team", score: 4),
                    PlayPlayerLeaderboardEntry(id: 9, rank: 2, displayName: nil, score: 0)]
        for language in ["en", "zh-Hans"] {
            let view = PlayPlayerLeaderboardView(state: .entries(rows)).environment(\.locale, Locale(identifier: language))
            let size = UIHostingController(rootView: view).sizeThatFits(in: CGSize(width: 300, height: 20_000))
            XCTAssertGreaterThan(size.height, 0); XCTAssertLessThanOrEqual(size.width, 301)
        }
    }
    func testHiddenRankingDoesNotLeaveLeaderboardCard() {
        let size = UIHostingController(rootView: PlayPlayerLeaderboardView(state: .hidden))
            .sizeThatFits(in: CGSize(width: 300, height: 20_000))
        XCTAssertEqual(size.height, 0, accuracy: 0.1)
    }
    func testEmptyAndUnconfirmedStatesConstructInBothLocales() {
        for state in [PlayPlayerLeaderboardState.empty, .unconfirmed] {
            for language in ["en", "zh-Hans"] {
                let view = PlayPlayerLeaderboardView(state: state).environment(\.locale, Locale(identifier: language))
                let size = UIHostingController(rootView: view).sizeThatFits(in: CGSize(width: 300, height: 20_000))
                XCTAssertGreaterThan(size.height, 0); XCTAssertLessThanOrEqual(size.width, 301)
            }
        }
    }
    func testLongTeamNameGrowsAtAccessibilitySizeWithoutHorizontalOverflow() {
        let row = PlayPlayerLeaderboardEntry(id: 8, rank: 123, displayName: String(repeating: "Synthetic 队伍 ", count: 6), score: 999)
        func measure(_ size: DynamicTypeSize) -> CGSize {
            UIHostingController(rootView: PlayPlayerLeaderboardView(state: .entries([row])).dynamicTypeSize(size))
                .sizeThatFits(in: CGSize(width: 300, height: 20_000))
        }
        let normal = measure(.large), accessible = measure(.accessibility5)
        XCTAssertGreaterThan(accessible.height, normal.height); XCTAssertLessThanOrEqual(accessible.width, 301)
    }
}

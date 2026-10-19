import XCTest
@testable import QuestifyCore

final class GlobalSearchRecommendedKeywordsTests: XCTestCase {
    func testChinaUsesMiniProgramFixedOrder() {
        XCTAssertEqual(GlobalSearchRecommendedKeywords.keywords(for: .china),
                       ["骑行", "城市", "外滩", "书店", "美术馆", "摄影", "苏州河", "菜场"])
    }

    func testOtherOrUnknownMarketsHaveNoRecommendations() {
        XCTAssertEqual(GlobalSearchRecommendedKeywords.keywords(for: .unitedStates), [])
        XCTAssertEqual(GlobalSearchRecommendedKeywords.keywords(for: nil), [])
    }

    func testKeywordsAreUniqueAndSearchable() {
        let words = GlobalSearchRecommendedKeywords.china
        XCTAssertEqual(Set(words).count, words.count)
        XCTAssertTrue(words.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
    }
}

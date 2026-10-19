import XCTest
@testable import QuestifyCore

/// Mini-program pages/searchmap presentation rules over synthetic inputs only.
final class SearchMapParityPresentationTests: XCTestCase {
    func testNodeLevelClampsLikeMiniProgramAndMissingIsStandard() {
        XCTAssertEqual(SearchMapNodeLevelStyle.resolve(nil).level, 1)
        XCTAssertEqual(SearchMapNodeLevelStyle.resolve(0).level, 1)
        XCTAssertEqual(SearchMapNodeLevelStyle.resolve(2).glyph, "◆")
        XCTAssertEqual(SearchMapNodeLevelStyle.resolve(3).labelKey, "searchMap.w208.level.official")
        XCTAssertEqual(SearchMapNodeLevelStyle.resolve(9).level, 4)
        XCTAssertEqual(Set((1...4).map { SearchMapNodeLevelStyle.resolve($0).symbol }).count, 4)
    }

    func testCityNodeDecodesOptionalNodeLevelWithoutFailingOnBadType() throws {
        let nodes = try JSONDecoder().decode([SearchMapCityNode].self, from: Data(SearchMapSyntheticFixtures.cityNodes.utf8))
        XCTAssertEqual(nodes.first?.nodeLevel, 3)
        let odd = try JSONDecoder().decode(SearchMapCityNode.self, from: Data(#"{"poiId":5,"name":"x","nodeLevel":"high"}"#.utf8))
        XCTAssertNil(odd.nodeLevel)
        let absent = try JSONDecoder().decode(SearchMapCityNode.self, from: Data(#"{"poiId":6}"#.utf8))
        XCTAssertNil(absent.nodeLevel)
    }

    func testPinPresentationTopicIconAndMerchantFallback() {
        XCTAssertEqual(SearchMapPinPresentation.activitySymbol(linkedTopicID: 72), "flag.fill")
        XCTAssertEqual(SearchMapPinPresentation.activitySymbol(linkedTopicID: nil), "calendar")
        XCTAssertEqual(SearchMapPinPresentation.merchantTitle(name: " ", merchantName: "Shop"), "Shop")
        XCTAssertNil(SearchMapPinPresentation.merchantTitle(name: "", merchantName: "  "))
    }

    func testCapsuleStatesFollowLoadingFailureEmptyThenResults() {
        XCTAssertEqual(SearchMapResultCapsule.resolve(loading: true, failed: true, rows: 3, listOnly: 0), .loading)
        XCTAssertEqual(SearchMapResultCapsule.resolve(loading: false, failed: true, rows: 0, listOnly: 0), .failed)
        XCTAssertEqual(SearchMapResultCapsule.resolve(loading: false, failed: false, rows: 0, listOnly: 0), .empty)
        let result = SearchMapResultCapsule.resolve(loading: false, failed: true, rows: 2, listOnly: 5)
        XCTAssertEqual(result, .results(total: 2, listOnly: 2))
        XCTAssertTrue(result.opensSheet)
        XCTAssertFalse(SearchMapResultCapsule.failed.opensSheet)
    }

    func testDateChoiceIsDerivedFromConcreteBounds() throws {
        let zone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        var draft = SearchMapDateFilterDraft(filter: GlobalSearchQuery())
        XCTAssertNil(SearchMapDateChoice.current(draft, now: now, timeZone: zone))
        try draft.select(.today, now: now, timeZone: zone)
        XCTAssertEqual(SearchMapDateChoice.current(draft, now: now, timeZone: zone), .today)
        try draft.select(.tomorrow, now: now, timeZone: zone)
        XCTAssertEqual(SearchMapDateChoice.current(draft, now: now, timeZone: zone), .tomorrow)
        draft.endDate = "2099-01-01"
        XCTAssertEqual(SearchMapDateChoice.current(draft, now: now, timeZone: zone), .custom)
    }

    func testPriceMessageNamesTheEditedBoundOnlyWhenOrderIsInvalid() {
        XCTAssertNil(SearchMapPriceRule.messageKey(minimum: "10", maximum: "20", edited: .minimum))
        XCTAssertNil(SearchMapPriceRule.messageKey(minimum: "", maximum: "20", edited: .maximum))
        XCTAssertEqual(SearchMapPriceRule.messageKey(minimum: "20", maximum: "20", edited: .minimum), "searchMap.w208.price.minNotBelowMax")
        XCTAssertEqual(SearchMapPriceRule.messageKey(minimum: "30", maximum: "20", edited: .maximum), "searchMap.w208.price.maxNotAboveMin")
    }

    func testOfflineBannerUsesNetworkStateAndLastSettledLoadOnly() {
        let date = Date(timeIntervalSince1970: 1_900_000_000)
        XCTAssertEqual(SearchMapOfflineBanner.resolve(online: true, lastLoaded: date, hasResults: true), .none)
        XCTAssertEqual(SearchMapOfflineBanner.resolve(online: false, lastLoaded: nil, hasResults: true), .noCache)
        XCTAssertEqual(SearchMapOfflineBanner.resolve(online: false, lastLoaded: date, hasResults: false), .noCache)
        XCTAssertEqual(SearchMapOfflineBanner.resolve(online: false, lastLoaded: date, hasResults: true), .cached(date))
        XCTAssertNil(SearchMapOfflineBanner.none.key)
        XCTAssertTrue(SearchMapOfflineBanner.shouldRefreshOnReconnect(wasOnline: false, isOnline: true, hasResults: true))
        XCTAssertFalse(SearchMapOfflineBanner.shouldRefreshOnReconnect(wasOnline: false, isOnline: true, hasResults: false))
        XCTAssertFalse(SearchMapOfflineBanner.shouldRefreshOnReconnect(wasOnline: true, isOnline: true, hasResults: true))
    }
}

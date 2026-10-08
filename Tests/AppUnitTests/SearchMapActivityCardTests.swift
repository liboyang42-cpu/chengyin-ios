import XCTest
import SwiftUI
@testable import Questify

@MainActor final class SearchMapActivityCardTests: XCTestCase {
    private func activity(long: Bool = false) throws -> ActivitySummary {
        let raw: [String: Any] = ["id": 71, "name": long ? String(repeating: "Complete source title 完整活动标题。", count: 8) : "Synthetic activity",
            "address": long ? String(repeating: "Source address 源地址。", count: 8) : "Synthetic address",
            "sysCategoryList": [["categoryName": "文化"], ["categoryName": "A source category"]],
            "topicId": 72, "startDate": "2026-10-08 00:30:00", "endDate": "2026-10-08 02:30:00"]
        return try JSONDecoder().decode(ActivitySummary.self, from: JSONSerialization.data(withJSONObject: raw))
    }
    func testListAndSelectedCardReceiveIdenticalPresentation() throws {
        let row = try activity()
        let listCard = SearchMapActivityCard(item: row, offline: true)
        let selectedCard = SearchMapActivityCard(item: row, offline: true)
        XCTAssertEqual(listCard.presentation, selectedCard.presentation)
        XCTAssertEqual(listCard.presentation.primaryDestination, .activity(71))
        XCTAssertEqual(selectedCard.presentation.relatedDestination, .topic(72))
    }
    func testCardGrowsForAccessibilityTextWithoutHorizontalOverflow() throws {
        let row = try activity(long: true)
        func measure(_ size: DynamicTypeSize) -> CGSize {
            UIHostingController(rootView: SearchMapActivityCard(item: row, offline: true).dynamicTypeSize(size))
                .sizeThatFits(in: CGSize(width: 300, height: 20_000))
        }
        let normal = measure(.large), largest = measure(.accessibility5)
        XCTAssertGreaterThan(largest.height, normal.height)
        XCTAssertLessThanOrEqual(largest.width, 301)
    }
    func testMissingAddressAndTimeStatesConstructInBothLanguages() throws {
        let row = try JSONDecoder().decode(ActivitySummary.self, from: Data(#"{"id":73,"name":"Synthetic indoor activity"}"#.utf8))
        for language in ["en", "zh-Hans"] {
            let card = SearchMapActivityCard(item: row, offline: true)
            XCTAssertNil(card.presentation.address); XCTAssertEqual(card.presentation.starts, .unknown)
            XCTAssertEqual(card.presentation.ends, .unknown); XCTAssertEqual(card.presentation.pointKind, .activity)
            let size = UIHostingController(rootView: card.environment(\.locale, Locale(identifier: language))
                .dynamicTypeSize(.accessibility5)).sizeThatFits(in: CGSize(width: 300, height: 20_000))
            XCTAssertGreaterThan(size.height, 230); XCTAssertLessThanOrEqual(size.width, 301)
        }
    }
    func testOfflineRenderingDoesNotRemoveRealCategoryOrThemeMetadata() throws {
        let row = try activity()
        let live = SearchMapActivityCard(item: row, offline: false).presentation
        let offline = SearchMapActivityCard(item: row, offline: true).presentation
        XCTAssertEqual(live, offline)
        XCTAssertEqual(offline.categoryNames, ["文化", "A source category"])
        XCTAssertEqual(offline.pointKind, .topic)
    }
}

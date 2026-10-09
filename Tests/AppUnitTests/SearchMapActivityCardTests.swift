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
        for language in ["en", "zh-Hans"] {
            let normal = intrinsicSize(row, dynamicType: .large, language: language)
            let largest = intrinsicSize(row, dynamicType: .accessibility5, language: language)
            XCTAssertGreaterThan(largest.height, normal.height, language)
            assertBoundedIntrinsicSize(normal)
            assertBoundedIntrinsicSize(largest)
        }
    }
    func testIntrinsicCardHeightDoesNotFollowHostingProposal() throws {
        let row = try activity(long: true)
        for language in ["en", "zh-Hans"] {
            let first = intrinsicSize(row, dynamicType: .accessibility5, language: language, proposedHeight: 10_000)
            let second = intrinsicSize(row, dynamicType: .accessibility5, language: language, proposedHeight: 20_000)
            assertBoundedIntrinsicSize(first)
            assertBoundedIntrinsicSize(second)
            XCTAssertEqual(first.height, second.height, accuracy: 0.5, language)
            XCTAssertEqual(first.width, second.width, accuracy: 0.5, language)
        }
    }
    func testMissingAddressAndTimeStatesConstructInBothLanguages() throws {
        let row = try JSONDecoder().decode(ActivitySummary.self, from: Data(#"{"id":73,"name":"Synthetic indoor activity"}"#.utf8))
        for language in ["en", "zh-Hans"] {
            let card = SearchMapActivityCard(item: row, offline: true)
            XCTAssertNil(card.presentation.address); XCTAssertEqual(card.presentation.starts, .unknown)
            XCTAssertEqual(card.presentation.ends, .unknown); XCTAssertEqual(card.presentation.pointKind, .activity)
            let size = intrinsicSize(row, dynamicType: .accessibility5, language: language)
            XCTAssertGreaterThan(size.height, 230)
            assertBoundedIntrinsicSize(size)
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

    private func intrinsicSize(_ row: ActivitySummary, dynamicType: DynamicTypeSize,
                               language: String, proposedHeight: CGFloat = 20_000) -> CGSize {
        let card = SearchMapActivityCard(item: row, offline: true)
            .environment(\.locale, Locale(identifier: language))
            .dynamicTypeSize(dynamicType)
            // Both shipping map-card surfaces are children of a vertical ScrollView.
            // Ask for ideal height while retaining the 300pt width proposal, as in
            // ReferenceMapCardAppTests. A large finite height alone lets the shared
            // image card's flexible Spacer consume the entire hosting proposal.
            .fixedSize(horizontal: false, vertical: true)
        return UIHostingController(rootView: card)
            .sizeThatFits(in: CGSize(width: 300, height: proposedHeight))
    }

    private func assertBoundedIntrinsicSize(_ size: CGSize, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(size.width.isFinite && size.height.isFinite, file: file, line: line)
        XCTAssertGreaterThan(size.width, 0, file: file, line: line)
        XCTAssertLessThanOrEqual(size.width, 301, file: file, line: line)
        XCTAssertGreaterThanOrEqual(size.height, 230, file: file, line: line)
        XCTAssertLessThan(size.height, 10_000, "Intrinsic content must not fill the measurement proposal", file: file, line: line)
    }
}

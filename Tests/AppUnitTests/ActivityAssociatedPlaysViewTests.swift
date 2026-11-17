import XCTest
import SwiftUI
import UIKit
@testable import Questify

@MainActor final class ActivityAssociatedPlaysViewTests: XCTestCase {
    func testStandaloneIntroductionRetainsActivityIdentityAndWrapsLongContentAtAccessibilitySize() throws {
        let summary = try JSONDecoder().decode(ActivitySummary.self, from: Data(#"{"id":42,"name":"TEST 一处集合点的长标题活动介绍，不借用主题身份","addressName":"TEST 上海市虚拟集合点","startDate":"2099-11-18 10:00:00","endDate":"2099-11-18 11:30:00"}"#.utf8))
        XCTAssertEqual(summary.id, 42)
        XCTAssertNil(summary.linkedTopicID)
        let host = UIHostingController(rootView: ActivityDetailHeader(summary: summary)
            .environment(\.dynamicTypeSize, .accessibility3))
        host.loadViewIfNeeded()
        let size = host.sizeThatFits(in: CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude))
        XCTAssertGreaterThan(size.height, 44)
        XCTAssertLessThanOrEqual(size.width, 320)
        XCTAssertTrue(size.height.isFinite)
    }
    func testIntroductionGrowsForCompleteServerDescriptionInBothAppearances() throws {
        let description = String(repeating: "TEST 活动介绍保留完整文字与换行。\n", count: 50)
        let data = try JSONSerialization.data(withJSONObject: ["id": 42, "name": "TEST 活动", "description": description])
        let summary = try JSONDecoder().decode(ActivitySummary.self, from: data)
        XCTAssertNil(summary.imageURL)
        XCTAssertEqual(summary.description, description)
        for appearance in [ColorScheme.light, .dark] {
            let host = UIHostingController(rootView: ActivityDetailHeader(summary: summary)
                .environment(\.dynamicTypeSize, .accessibility3).environment(\.colorScheme, appearance))
            host.loadViewIfNeeded()
            let size = host.sizeThatFits(in: CGSize(width: 320, height: CGFloat.greatestFiniteMagnitude))
            XCTAssertGreaterThan(size.height, 480, "Full text must expand beyond the minimum hero height")
            XCTAssertLessThanOrEqual(size.width, 320)
            XCTAssertTrue(size.height.isFinite)
        }
    }
    func testReadOnlyMetadataRowBuildsWithoutReaderTemplateIDOrDestination() throws {
        let row = try JSONDecoder().decode(ActivityAssociatedPlay.self, from: Data(#"{"title":"Synthetic play","players":"2–6","duration":30.5}"#.utf8))
        let host = UIHostingController(rootView: ActivityAssociatedPlayRow(play: row).environment(\.dynamicTypeSize, .accessibility3))
        host.loadViewIfNeeded(); host.view.layoutIfNeeded()
        XCTAssertEqual(row.players, "2–6"); XCTAssertEqual(row.durationMinutes, 30.5)
        XCTAssertNotNil(host.view)
    }
    func testEmptyAndUnknownRowsDoNotCreateFallbackActivitiesOrValues() throws {
        XCTAssertTrue(ActivityAssociatedPlaysSection(plays: []).plays.isEmpty)
        let row = try JSONDecoder().decode(ActivityAssociatedPlay.self, from: Data("{}".utf8))
        let view = ActivityAssociatedPlayRow(play: row)
        XCTAssertNil(view.play.title); XCTAssertNil(view.play.players); XCTAssertNil(view.play.durationMinutes)
    }
}

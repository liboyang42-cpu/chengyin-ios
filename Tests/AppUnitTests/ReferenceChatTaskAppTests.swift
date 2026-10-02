import XCTest
import SwiftUI
@testable import Questify

@MainActor final class ReferenceChatTaskAppTests: XCTestCase {
    func testBilingualBubbleGrowsWithoutClippingAtMaximumText() {
        func measure(_ text: String, _ size: DynamicTypeSize, own: Bool) -> CGSize {
            let view = ChatMessageBubble(isOwn: own, timestamp: "2026-10-02 10:20") {
                Text(verbatim: "Sender / 发送者")
            } content: { Text(verbatim: text) }
                .dynamicTypeSize(size)
            return UIHostingController(rootView: view).sizeThatFits(in: CGSize(width: 300, height: 20_000))
        }
        for own in [true, false] {
            let short = measure("Hello", .large, own: own)
            let long = measure(String(repeating: "Long message / 完整长消息。", count: 12), .large, own: own)
            let maximum = measure(String(repeating: "Long message / 完整长消息。", count: 12), .accessibility5, own: own)
            XCTAssertGreaterThan(long.height, short.height); XCTAssertGreaterThan(maximum.height, long.height)
            XCTAssertLessThanOrEqual(maximum.width, 301); XCTAssertTrue(maximum.height.isFinite)
        }
    }
    func testProgressTextUsesSelectedLocaleRatherThanProcessLanguage() {
        let english = String(format: appLocalized("referenceTask.completedCount", locale: Locale(identifier: "en")), 2, 5)
        let chinese = String(format: appLocalized("referenceTask.completedCount", locale: Locale(identifier: "zh-Hans")), 2, 5)
        XCTAssertEqual(english, "Completed 2 of 5"); XCTAssertEqual(chinese, "已完成 2 / 共 5")
    }
    func testSummaryCanRenderBothLanguagesAtMaximumTextWithAnimationsDisabled() throws {
        let result = try JSONDecoder().decode(PlayNodesResult.self, from: Data(PlayExperienceSyntheticFixtures.classic.utf8))
        let snapshot = try PlaySnapshot(scope: .activity(41), result: result)
        for language in ["en", "zh-Hans"] {
            let view = PlayTaskSummaryView(snapshot: snapshot, phase: "ready")
                .environment(\.locale, Locale(identifier: language))
                // OS Reduce Motion is read-only. This unit case bounds static layout;
                // ReferenceChatTaskFlowTests exercises the DEBUG reduced-motion policy.
                .transaction { $0.animation = nil; $0.disablesAnimations = true }
                .dynamicTypeSize(.accessibility5)
            let size = UIHostingController(rootView: view).sizeThatFits(in: CGSize(width: 300, height: 20_000))
            XCTAssertGreaterThan(size.height, 44); XCTAssertLessThanOrEqual(size.width, 301)
            XCTAssertEqual(snapshot.displayedDoneCount, 0, "Rendering must not complete the task")
        }
    }
}

import XCTest
import SwiftUI
import UIKit
@testable import Questify

@MainActor final class MerchantNPCConversationHistoryAppTests: XCTestCase {
    private func history(text: String = "Synthetic plain text") throws -> MerchantNPCConversationHistory {
        let data = try JSONSerialization.data(withJSONObject: ["outcomeStatus": "SUCCEEDED", "safeText": text])
        var history = MerchantNPCConversationHistory()
        history.record(requestID: UUID(), question: "Synthetic question", reply: try JSONDecoder().decode(MerchantNPCReply.self, from: data))
        return history
    }
    func testEmptyHistoryConstructsWithoutAnyServiceOrAction() {
        let value = MerchantNPCConversationHistory()
        let host = UIHostingController(rootView: MerchantNPCConversationHistoryView(history: value))
        host.loadViewIfNeeded(); XCTAssertTrue(value.turns.isEmpty)
    }
    func testTextProjectionHasNoFormattingOrHiddenProviderFields() throws {
        let value = try history(text: "**Raw text** https://synthetic.invalid")
        let host = UIHostingController(rootView: MerchantNPCConversationHistoryView(history: value))
        host.loadViewIfNeeded(); XCTAssertEqual(value.turns.first?.safeText, "**Raw text** https://synthetic.invalid")
    }
    func testBothLocalesAndLargeTextConstructWithoutChangingHistory() throws {
        let value = try history()
        for locale in ["en", "zh-Hans"] {
            let host = UIHostingController(rootView: ScrollView {
                MerchantNPCConversationHistoryView(history: value)
            }.environment(\.locale, Locale(identifier: locale)).dynamicTypeSize(.accessibility5))
            host.loadViewIfNeeded(); XCTAssertEqual(value.turns.count, 1)
        }
    }
}

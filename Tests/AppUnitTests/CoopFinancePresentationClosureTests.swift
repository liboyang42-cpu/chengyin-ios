import XCTest
import SwiftUI
import UIKit
@testable import Questify

/// UI-only regression and render smoke. No real reader, wallet or mutation factory.
@MainActor final class CoopFinancePresentationClosureTests: XCTestCase {
    private func value(_ json: String) throws -> CoopFlowJSON {
        try JSONDecoder().decode(CoopFlowJSON.self, from: Data(json.utf8))
    }
    private func source(_ name: String) throws -> String {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: root.appendingPathComponent("App/" + name), encoding: .utf8)
    }
    private func render<V: View>(_ view: V, locale: String, size: DynamicTypeSize) {
        let host = UIHostingController(rootView: view.environment(\.locale, Locale(identifier: locale)).environment(\.dynamicTypeSize, size))
        host.loadViewIfNeeded(); host.view.frame = CGRect(x: 0, y: 0, width: 320, height: 640)
        host.view.setNeedsLayout(); host.view.layoutIfNeeded()
        XCTAssertNotNil(host.view)
    }
    func testSummaryRendersLargeAmountsAndLongReasonAtAccessibilitySize() throws {
        let data = try value(#"{"topics":[{"settled":true,"myIncome":123456789.12,"myIncomeArrived":true}],"adjustments":{"pendingAmount":3,"executedAmount":2,"pendingReason":"Original server explanation with a long reason and a second line\n保留服务端原始说明，不截断金额或更改精度。"}}"#)
        let summary = CoopFinanceSummary(data)
        XCTAssertEqual(summary.creditedIncome, Decimal(string: "123456789.12"))
        for locale in ["en", "zh-Hans"] {
            render(List { CoopFinanceSummarySection(summary: summary) }, locale: locale, size: .accessibility5)
        }
    }
    func testUnknownAndZeroRemainDifferentBeforePresentation() throws {
        let unknown = CoopFinanceSummary(try value(#"{"topics":[{"settled":true,"myIncome":5}]}"#))
        let zero = CoopFinanceSummary(try value(#"{"topics":[],"adjustments":{"pendingAmount":0,"executedAmount":0}}"#))
        XCTAssertNil(unknown.creditedIncome); XCTAssertTrue(unknown.showsPendingAdjustment)
        XCTAssertEqual(zero.creditedIncome, 0); XCTAssertFalse(zero.showsPendingAdjustment)
        render(List { CoopFinanceSummarySection(summary: unknown) }, locale: "en", size: .accessibility3)
        render(List { CoopFinanceSummarySection(summary: zero) }, locale: "zh-Hans", size: .large)
    }
    func testFinancialRowsSupportCompactAndVerticalAccessibilityLayouts() {
        for size in [DynamicTypeSize.large, .accessibility5] {
            render(List {
                LabeledContent { Text(verbatim: "−¥1234567890123.45").monospacedDigit() }
                    label: { Text(verbatim: "Existing adjustment amount / 原调整金额") }
            }.labeledContentStyle(CoopFinancialRowStyle()).modifier(CoopOperationListPresentation()), locale: "en", size: size)
        }
    }
    func testProfitSupportActionStillOnlyOpensContactSheetUnderOriginalGate() throws {
        let ui = try source("CoopFinanceProfitView.swift")
        XCTAssertTrue(ui.contains("if profit.canWithdraw, loadedSession == reader.session { showsSupport = true }"))
        XCTAssertTrue(ui.contains(".sheet(isPresented: $showsSupport) { WithdrawalSupportContactView() }"))
        XCTAssertTrue(ui.contains(".disabled(!profit.canWithdraw)"))
        XCTAssertTrue(ui.contains("if profit.isOwner, let walletReader { CoopFinanceFundsStagesSection(reader: walletReader) }"))
        for forbidden in ["URLSession", "confirmPayment", "createTransfer", "submitWithdrawal", "CoopDepositRefundOriginalEntry"] {
            XCTAssertFalse(ui.contains(forbidden), forbidden)
        }
    }
    func testAmountUnknownOriginalPrecisionAndSignArePreserved() throws {
        let summary = try source("CoopFinanceSummarySection.swift")
        XCTAssertTrue(summary.contains("guard let value else { return Text(verbatim: \"—\") }"))
        XCTAssertTrue(summary.contains("formatter.minimumFractionDigits = 2; formatter.maximumFractionDigits = 2"))
        XCTAssertTrue(summary.contains("(negative ? \"−¥\" : \"¥\") + text"))
        let profit = try source("CoopFinanceProfitView.swift")
        XCTAssertTrue(profit.contains("guard let amount = stat.amount else { return \"—\" }"))
        XCTAssertTrue(profit.contains("(stat.key == .adjustExecuted ? \"−¥\" : \"¥\") + CoopFinanceProfit.plainText(amount)"))
        XCTAssertTrue(profit.contains("topic.status != .unsettled && topic.status != .settlementUnknown"))
    }
    func testAcceptedProjectKeepsActualSourceGateAndLifecycle() throws {
        let ui = try source("MerchantAcceptedProjectView.swift")
        XCTAssertTrue(ui.contains("projectEntryIsCurrent: { gate.canPresent && gate.destination?.id == destination.id }"))
        XCTAssertTrue(ui.contains(".id(destination.id)"))
        XCTAssertTrue(ui.contains("if phase == .active { gate.activate(); Task { await gate.load() } } else { gate.retire() }"))
        XCTAssertTrue(ui.contains(".onDisappear { gate.retire() }"))
        XCTAssertFalse(ui.contains("CoopDepositRefundOriginal"))
    }
}

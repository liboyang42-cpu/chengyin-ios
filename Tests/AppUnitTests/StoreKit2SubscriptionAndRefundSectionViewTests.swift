import XCTest
import SwiftUI
#if canImport(QuestifyApp)
@testable import QuestifyApp
#if canImport(QuestifyCore)
import QuestifyCore
#elseif canImport(Core)
import Core
#endif
#else
@testable import Questify
#endif

@MainActor
final class StoreKit2SubscriptionAndRefundSectionViewTests: XCTestCase {
    func testDefaultReadySnapshotCoversAllFourStoreKit2LifecycleControls() {
        let snapshot = StoreKit2LifecycleSnapshot.defaultReady
        XCTAssertTrue(snapshot.isFullyCompliant)
        XCTAssertTrue(snapshot.verifiesJWSAndServerEntitlementBeforeFinish)
        XCTAssertTrue(snapshot.exposesExplicitRestorePurchasesButton)
        XCTAssertEqual(snapshot.compliantCount, 4)
        XCTAssertEqual(snapshot.warningCount, 0)
        XCTAssertEqual(snapshot.rows.map(\.id), [
            "transaction-updates-listener",
            "jws-verification-before-finish",
            "restore-purchases-action",
            "revocation-and-refund-handling"
        ])
        XCTAssertEqual(snapshot.summaryText, "合规控制项 4/4 · 告警 0 · JWS 先验后结 开启")
    }

    func testNonCompliantStoreKitControlWarningStateMarksSnapshotNonCompliant() {
        var rows = StoreKit2LifecycleSnapshot.defaultReady.rows
        rows[1] = StoreKit2ControlRow(
            id: "jws-verification-before-finish",
            kind: .jwsVerificationBeforeFinish,
            title: "JWS 验签与服务端权益入账后调用 finish()",
            storeKitAPI: "transaction.finish()",
            enforcementRule: "检测到未完成服务端入账即调用 finish()",
            status: .warningNonCompliant
        )
        let snapshot = StoreKit2LifecycleSnapshot(
            verifiesJWSAndServerEntitlementBeforeFinish: false,
            exposesExplicitRestorePurchasesButton: true,
            rows: rows
        )
        XCTAssertFalse(snapshot.isFullyCompliant)
        XCTAssertEqual(snapshot.compliantCount, 3)
        XCTAssertEqual(snapshot.warningCount, 1)
        XCTAssertEqual(rows[1].badgeText, "WARNING")
        XCTAssertEqual(snapshot.summaryText, "合规控制项 3/4 · 告警 1 · JWS 先验后结 缺失")
    }

    func testViewInstantiatesAndEvaluatesBodyOnMainActor() {
        let view = StoreKit2SubscriptionAndRefundSectionView()
        _ = view.body
        XCTAssertEqual(view.snapshot, .defaultReady)
        XCTAssertTrue(view.snapshot.isFullyCompliant)
    }
}


@MainActor
final class StoreKit2CloseoutLayoutTests: XCTestCase {
    func testDefaultDiagnosticWrapsAtNarrowWidthWithAccessibilityText() {
        assertLayout(StoreKit2LifecycleSnapshot.defaultReady)
    }
    func testWarningDiagnosticWrapsLongOriginalRulesWithoutChangingSnapshot() {
        var rows = StoreKit2LifecycleSnapshot.defaultReady.rows
        rows[1] = StoreKit2ControlRow(id: rows[1].id, kind: rows[1].kind,
            title: String(repeating: "Original review rule 原规则 ", count: 8),
            storeKitAPI: rows[1].storeKitAPI,
            enforcementRule: String(repeating: "Verified server entitlement is required before finish. ", count: 12),
            status: .warningNonCompliant)
        let snapshot = StoreKit2LifecycleSnapshot(verifiesJWSAndServerEntitlementBeforeFinish: false,
            exposesExplicitRestorePurchasesButton: true, rows: rows)
        assertLayout(snapshot)
        XCTAssertFalse(snapshot.isFullyCompliant)
        XCTAssertEqual(snapshot.warningCount, 1)
        XCTAssertEqual(snapshot.rows[1].enforcementRule, rows[1].enforcementRule)
    }
    private func assertLayout(_ snapshot: StoreKit2LifecycleSnapshot, file: StaticString = #filePath, line: UInt = #line) {
        for language in ["en", "zh-Hans"] {
            let content = List { StoreKit2SubscriptionAndRefundSectionView(snapshot: snapshot) }
                .environment(\.locale, Locale(identifier: language))
                .dynamicTypeSize(.accessibility5)
            let controller = UIHostingController(rootView: content)
            let size = controller.sizeThatFits(in: CGSize(width: 320, height: 20_000))
            XCTAssertTrue(size.height.isFinite, file: file, line: line)
            XCTAssertGreaterThan(size.height, 0, file: file, line: line)
            XCTAssertLessThanOrEqual(size.width, 321, file: file, line: line)
        }
    }
}

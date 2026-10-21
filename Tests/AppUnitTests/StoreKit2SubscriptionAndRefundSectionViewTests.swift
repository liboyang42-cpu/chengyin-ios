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

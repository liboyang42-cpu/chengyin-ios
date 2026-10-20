import XCTest
import SwiftUI
#if canImport(QuestifyApp)
@testable import QuestifyApp
import QuestifyCore
#else
@testable import Questify
#endif

@MainActor
final class MemberSubscriptionAndOrderInvoiceSectionViewTests: XCTestCase {
    func testDefaultReadySnapshotVerifiesSubscriptionOrderLifecycleAndRefundReadback() {
        let snapshot = MemberSubscriptionAndOrderSnapshot.defaultReady
        XCTAssertTrue(snapshot.isAllCompliant)
        XCTAssertEqual(snapshot.rows.count, 3)
        XCTAssertEqual(snapshot.rows.map(\.scopeCode), ["w2-02", "w2-03", "w2-04"])
        XCTAssertEqual(
            snapshot.supportedOrderStates,
            ["pending", "paid", "fulfilled", "cancelled", "refunded"]
        )
        for row in snapshot.rows {
            XCTAssertTrue(row.isCompliant)
            XCTAssertFalse(row.liveChargeEnabled)
            XCTAssertEqual(row.statusBadgeText, "COMPLIANT • FAIL-CLOSED")
        }
    }

    func testNonCompliantOrderStateOrLiveChargeSurfacesWarningStrings() {
        var modifiedRows = MemberSubscriptionAndOrderSnapshot.defaultRows
        modifiedRows[1] = MemberOrderAuditRow(
            id: "w2-03",
            scopeCode: "w2-03",
            title: "5-State Order Lifecycle State Machine",
            policyDetail: "Missing refunded state",
            isCompliant: false,
            liveChargeEnabled: true
        )
        let warningSnapshot = MemberSubscriptionAndOrderSnapshot(
            rows: modifiedRows,
            supportedOrderStates: ["pending", "paid", "fulfilled", "cancelled"],
            storeKit2GateFailClosed: false,
            refundReceiptReadbackRequired: false
        )
        let view = MemberSubscriptionAndOrderInvoiceSectionView(snapshot: warningSnapshot)

        XCTAssertFalse(view.snapshot.isAllCompliant)
        XCTAssertEqual(
            view.statusBadgeText,
            "Subscription & Order Gate: WARNING (Non-Compliant State)"
        )
        XCTAssertEqual(
            view.subscriptionSummaryText,
            "w2-02 StoreKit 2 & Subscription Gate: WARNING — unverified charge path enabled"
        )
        XCTAssertEqual(
            view.lifecycleStatesSummaryText,
            "w2-03 Order Lifecycle (4 states): pending → paid → fulfilled → cancelled"
        )
        XCTAssertEqual(
            view.refundReceiptSummaryText,
            "w2-04 Refund & Invoice Readback: WARNING — readback lock bypassed"
        )
        XCTAssertEqual(view.snapshot.rows[1].statusBadgeText, "WARNING • REVIEW REQUIRED")
    }

    func testMainActorViewBodyInstantiationAndDefaultPresentationStrings() {
        let view = MemberSubscriptionAndOrderInvoiceSectionView()
        _ = view.body

        XCTAssertEqual(
            view.statusBadgeText,
            "Subscription & Order Gate: READY (3/3 Compliant)"
        )
        XCTAssertEqual(
            view.subscriptionSummaryText,
            "w2-02 StoreKit 2 & Subscription Gate: FAIL-CLOSED (No unapproved external charge)"
        )
        XCTAssertEqual(
            view.lifecycleStatesSummaryText,
            "w2-03 Order Lifecycle (5 states): pending → paid → fulfilled → cancelled → refunded"
        )
        XCTAssertEqual(
            view.refundReceiptSummaryText,
            "w2-04 Refund & Invoice Readback: ENFORCED (UNKNOWN outcomes stay locked until server receipt)"
        )
    }
}

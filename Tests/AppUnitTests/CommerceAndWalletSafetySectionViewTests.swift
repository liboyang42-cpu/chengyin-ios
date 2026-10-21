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
final class CommerceAndWalletSafetySectionViewTests: XCTestCase {
    func testFailClosedDefaultSnapshotRendersAllFiveCommerceSafetyPillars() {
        let view = CommerceAndWalletSafetySectionView()
        _ = view.body

        XCTAssertTrue(view.snapshot.isAllCompliant)
        XCTAssertEqual(view.snapshot.pillars.count, 5)
        XCTAssertEqual(view.snapshot.compliantPillarCount, 5)
        XCTAssertEqual(
            view.snapshot.pillars.map(\.code),
            ["w2-03", "w2-05", "I04", "G-W06/W07", "W17.4"]
        )
        XCTAssertEqual(
            view.overallGateBadgeText,
            "Commerce & Wallet Gate: FAIL-CLOSED (5/5 Pillars Safe)"
        )
        XCTAssertEqual(
            view.refundLockBannerText,
            "UNKNOWN Refund Lock: 0 pending locks (readback-only resolution active)"
        )
        XCTAssertEqual(
            view.nonCashPolicyBannerText,
            "W17.4 Non-Cash Policy: ENFORCED — points & coupons are non-withdrawable"
        )
        for pillar in view.snapshot.pillars {
            XCTAssertEqual(pillar.statusBadgeText, "FAIL-CLOSED (SAFE)")
            XCTAssertFalse(pillar.liveCashMutationEnabled)
            XCTAssertTrue(pillar.isFailClosedCompliant)
        }
    }

    func testUnknownRefundLockCountSurfacesPendingReadbackBannerWhileKeepingGateCompliant() {
        let snapshot = CommerceAndWalletSafetySnapshot(
            unknownRefundLockedCount: 2,
            pointsWithdrawableAllowed: false
        )
        let view = CommerceAndWalletSafetySectionView(snapshot: snapshot)
        _ = view.body

        XCTAssertTrue(view.snapshot.isAllCompliant)
        XCTAssertEqual(
            view.refundLockBannerText,
            "UNKNOWN Refund Lock: 2 pending order(s) locked awaiting server readback"
        )
        XCTAssertEqual(
            view.overallGateBadgeText,
            "Commerce & Wallet Gate: FAIL-CLOSED (5/5 Pillars Safe)"
        )
    }

    func testLiveCashMutationOrWithdrawablePointsFlagsSurfaceViolationState() {
        var mutatedPillars = CommerceAndWalletSafetySnapshot.defaultPillars
        mutatedPillars[1] = CommerceSafetyPillarRow(
            id: "w2-05",
            code: "w2-05",
            title: "Fail-Closed Withdrawal Gate",
            policySummary: "Withdrawal gate overridden",
            isFailClosedCompliant: false,
            liveCashMutationEnabled: true
        )
        let violatingSnapshot = CommerceAndWalletSafetySnapshot(
            pillars: mutatedPillars,
            unknownRefundLockedCount: 0,
            pointsWithdrawableAllowed: true
        )
        let view = CommerceAndWalletSafetySectionView(snapshot: violatingSnapshot)
        _ = view.body

        XCTAssertFalse(view.snapshot.isAllCompliant)
        XCTAssertEqual(view.snapshot.compliantPillarCount, 4)
        XCTAssertEqual(
            view.overallGateBadgeText,
            "Commerce & Wallet Gate: ATTENTION REQUIRED (4/5 Pillars Safe)"
        )
        XCTAssertEqual(
            view.nonCashPolicyBannerText,
            "W17.4 Non-Cash Policy: VIOLATION — points marked withdrawable"
        )
        XCTAssertEqual(view.snapshot.pillars[1].statusBadgeText, "VIOLATION (REVIEW REQUIRED)")
    }
}

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
final class CouponAndSponsoredRewardSafetySectionViewTests: XCTestCase {
    func testCompliantSampleSnapshotCoversAllFourSafetyPillars() {
        let snapshot = CouponAndSponsoredRewardSafetySnapshot.compliantSample
        XCTAssertTrue(snapshot.isAllCompliant)
        XCTAssertEqual(snapshot.compliantRowCount, 4)
        XCTAssertEqual(snapshot.rows.map(\.kind), CouponSponsoredSafetyRow.PillarKind.allCases)

        let view = CouponAndSponsoredRewardSafetySectionView(snapshot: snapshot)
        XCTAssertEqual(
            CouponAndSponsoredRewardSafetySectionView.overallStatusText(for: snapshot),
            "整体状态：卡券与赞助奖池四大安全围栏全部生效（4/4）"
        )
        XCTAssertEqual(
            CouponAndSponsoredRewardSafetySectionView.couponJourneyStatusText(for: snapshot),
            "w2-05 卡券运行态：只读回读与核销状态核验已就绪"
        )
        XCTAssertEqual(
            CouponAndSponsoredRewardSafetySectionView.poolDisclosureStatusText(for: snapshot),
            "G-W07 奖池披露：赞助主体、有效期与非现金声明已齐备"
        )
        XCTAssertEqual(
            CouponAndSponsoredRewardSafetySectionView.frozenVoucherStatusText(for: snapshot),
            "冻结券回读保护：FROZEN 锁定与防重放回读已启用"
        )
        XCTAssertEqual(
            CouponAndSponsoredRewardSafetySectionView.capabilitiesGateStatusText(for: snapshot),
            "SponsoredRewardCapabilities：默认关闭（Fail-Closed）已核验"
        )
        _ = view.body
    }

    func testUnverifiedPoolDisclosureOrUnprotectedFrozenVoucherFailsClosed() {
        let rows: [CouponSponsoredSafetyRow] = [
            CouponSponsoredSafetyRow(
                kind: .w205CouponRuntimeJourney,
                title: "w2-05 卡券运行态只读核验链路",
                summary: "已核验",
                evidenceText: "OK",
                isCompliant: true
            ),
            CouponSponsoredSafetyRow(
                kind: .gW07PoolDisclosure,
                title: "G-W07 赞助奖池透明披露",
                summary: "缺少有效期说明",
                evidenceText: "missing-expiry",
                isCompliant: false
            ),
            CouponSponsoredSafetyRow(
                kind: .frozenVoucherReadbackProtection,
                title: "冻结券与未知结果回读保护",
                summary: "未锁定重试按钮",
                evidenceText: "unlocked",
                isCompliant: false
            ),
            CouponSponsoredSafetyRow(
                kind: .sponsoredRewardCapabilitiesGate,
                title: "SponsoredRewardCapabilities 默认关闭围栏",
                summary: "默认关闭",
                evidenceText: "disabled",
                isCompliant: true
            )
        ]

        let nonCompliant = CouponAndSponsoredRewardSafetySnapshot(
            couponRuntimeReadOnlyJourneyVerified: true,
            sponsoredPoolDisclosureComplete: false,
            frozenVoucherReadbackProtected: false,
            sponsoredRewardCapabilitiesFailClosed: true,
            rows: rows
        )
        XCTAssertFalse(nonCompliant.isAllCompliant)
        XCTAssertEqual(nonCompliant.compliantRowCount, 2)
        XCTAssertEqual(
            CouponAndSponsoredRewardSafetySectionView.overallStatusText(for: nonCompliant),
            "整体状态：存在未生效的卡券或赞助奖池安全围栏（2/4）"
        )
        XCTAssertEqual(
            CouponAndSponsoredRewardSafetySectionView.poolDisclosureStatusText(for: nonCompliant),
            "G-W07 奖池披露：赞助主体或非现金声明缺失"
        )
        XCTAssertEqual(
            CouponAndSponsoredRewardSafetySectionView.frozenVoucherStatusText(for: nonCompliant),
            "冻结券回读保护：FROZEN 锁定或防重放回读未启用"
        )

        let view = CouponAndSponsoredRewardSafetySectionView(snapshot: nonCompliant)
        _ = view.body
    }

    func testEmptyRowsSnapshotIsNotCompliantAndRendersEmptyState() {
        let emptySnapshot = CouponAndSponsoredRewardSafetySnapshot(
            couponRuntimeReadOnlyJourneyVerified: true,
            sponsoredPoolDisclosureComplete: true,
            frozenVoucherReadbackProtected: true,
            sponsoredRewardCapabilitiesFailClosed: true,
            rows: []
        )
        XCTAssertFalse(emptySnapshot.isAllCompliant)
        XCTAssertEqual(emptySnapshot.compliantRowCount, 0)

        let view = CouponAndSponsoredRewardSafetySectionView(snapshot: emptySnapshot)
        XCTAssertTrue(view.snapshot.rows.isEmpty)
        _ = view.body
    }
}

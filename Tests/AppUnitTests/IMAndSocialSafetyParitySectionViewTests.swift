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
final class IMAndSocialSafetyParitySectionViewTests: XCTestCase {
    func testCompliantSampleSnapshotCoversAllFourSafetyPillars() {
        let snapshot = IMAndSocialSafetyParitySnapshot.compliantSample
        XCTAssertTrue(snapshot.isAllCompliant)
        XCTAssertEqual(snapshot.verifiedRowCount, 4)
        XCTAssertEqual(snapshot.rows.map(\.kind), IMSocialSafetyPillarRow.PillarKind.allCases)

        let view = IMAndSocialSafetyParitySectionView(snapshot: snapshot)
        XCTAssertEqual(
            IMAndSocialSafetyParitySectionView.overallStatusText(for: snapshot),
            "整体状态：四大社交与私信安全支柱全部达标（4/4）"
        )
        XCTAssertEqual(
            IMAndSocialSafetyParitySectionView.memberProfileStatusText(for: snapshot),
            "w2-03/04 会员与社交主页：权限与拉黑隔离已核验"
        )
        XCTAssertEqual(
            IMAndSocialSafetyParitySectionView.growthStatusText(for: snapshot),
            "w2-10/I07 成长与排行榜：非现金荣誉约束已核验"
        )
        XCTAssertEqual(
            IMAndSocialSafetyParitySectionView.squareStatusText(for: snapshot),
            "w2-13/I05 广场与主题点赞：举报/缓存驱逐与写围栏已核验"
        )
        XCTAssertEqual(
            IMAndSocialSafetyParitySectionView.imInboxStatusText(for: snapshot),
            "w2-20 站内信与会话安全：举报/屏蔽与撤回准则已核验"
        )
        _ = view.body
    }

    func testUnverifiedSquareOrIMPillarFailsClosed() {
        let rows: [IMSocialSafetyPillarRow] = [
            IMSocialSafetyPillarRow(
                kind: .w203MemberSocialProfile,
                title: "w2-03/04 会员与社交主页对齐",
                summary: "已核验",
                safetyVerificationNote: "OK",
                isVerified: true
            ),
            IMSocialSafetyPillarRow(
                kind: .w210GrowthAndLeaderboard,
                title: "w2-10/I07 成长体系与排行榜安全",
                summary: "已核验",
                safetyVerificationNote: "OK",
                isVerified: true
            ),
            IMSocialSafetyPillarRow(
                kind: .w213SquareAndTopicLike,
                title: "w2-13/I05 广场动态与主题点赞围栏",
                summary: "404 缓存未驱逐",
                safetyVerificationNote: "pending",
                isVerified: false
            ),
            IMSocialSafetyPillarRow(
                kind: .w220ImInboxSafety,
                title: "w2-20 站内信与会话安全",
                summary: "缺少拉黑入口",
                safetyVerificationNote: "pending",
                isVerified: false
            )
        ]

        let nonCompliant = IMAndSocialSafetyParitySnapshot(
            memberSocialProfileParityVerified: true,
            growthAndLeaderboardNonCashVerified: true,
            squareModerationAndTopicLikeGateVerified: false,
            imInboxReportBlockAndRevokeVerified: false,
            rows: rows
        )
        XCTAssertFalse(nonCompliant.isAllCompliant)
        XCTAssertEqual(nonCompliant.verifiedRowCount, 2)
        XCTAssertEqual(
            IMAndSocialSafetyParitySectionView.overallStatusText(for: nonCompliant),
            "整体状态：存在未达标的社交或私信安全支柱（2/4）"
        )
        XCTAssertEqual(
            IMAndSocialSafetyParitySectionView.squareStatusText(for: nonCompliant),
            "w2-13/I05 广场与主题点赞：举报/缓存驱逐或写围栏待核验"
        )
        XCTAssertEqual(
            IMAndSocialSafetyParitySectionView.imInboxStatusText(for: nonCompliant),
            "w2-20 站内信与会话安全：举报/屏蔽或撤回准则待核验"
        )

        let view = IMAndSocialSafetyParitySectionView(snapshot: nonCompliant)
        _ = view.body
    }

    func testEmptyRowsSnapshotIsNotCompliantAndRendersEmptyState() {
        let emptySnapshot = IMAndSocialSafetyParitySnapshot(
            memberSocialProfileParityVerified: true,
            growthAndLeaderboardNonCashVerified: true,
            squareModerationAndTopicLikeGateVerified: true,
            imInboxReportBlockAndRevokeVerified: true,
            rows: []
        )
        XCTAssertFalse(emptySnapshot.isAllCompliant)
        XCTAssertEqual(emptySnapshot.verifiedRowCount, 0)

        let view = IMAndSocialSafetyParitySectionView(snapshot: emptySnapshot)
        XCTAssertTrue(view.snapshot.rows.isEmpty)
        _ = view.body
    }
}

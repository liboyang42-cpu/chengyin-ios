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
final class PrivacyAndSecurityRedactionSectionViewTests: XCTestCase {
    func testCompliantSampleSnapshotCoversAllFourPillars() {
        let snapshot = PrivacyAndSecurityRedactionSnapshot.compliantSample
        XCTAssertTrue(snapshot.isAllCompliant)
        XCTAssertTrue(snapshot.hasCompleteLocationDisclosures)
        XCTAssertEqual(snapshot.enforcedRowCount, 4)
        XCTAssertEqual(snapshot.rows.map(\.kind), PrivacyRedactionPillarRow.PillarKind.allCases)

        let view = PrivacyAndSecurityRedactionSectionView(snapshot: snapshot)
        XCTAssertEqual(
            PrivacyAndSecurityRedactionSectionView.overallStatusText(for: snapshot),
            "整体状态：四大隐私脱敏与安全围栏全部生效（4/4）"
        )
        XCTAssertEqual(
            PrivacyAndSecurityRedactionSectionView.homeRedactionStatusText(for: snapshot),
            "W19 私人据点：坐标已脱敏（HomeReturnCheck[redacted]）"
        )
        XCTAssertEqual(
            PrivacyAndSecurityRedactionSectionView.locationDisclosureStatusText(for: snapshot),
            "W13.5 位置共享告知：6/6 项已齐备"
        )
        XCTAssertEqual(
            PrivacyAndSecurityRedactionSectionView.npcSafetyStatusText(for: snapshot),
            "G-W04/I08 NPC 对话安全：敏感词过滤与删除围栏已启用"
        )
        XCTAssertEqual(
            PrivacyAndSecurityRedactionSectionView.cacheEvictionStatusText(for: snapshot),
            "I05 媒体缓存驱逐：404/DELETED 即时清理已启用"
        )
        _ = view.body
    }

    func testIncompleteDisclosureOrUnenforcedPillarFailsClosed() {
        let partialRows: [PrivacyRedactionPillarRow] = [
            PrivacyRedactionPillarRow(
                kind: .w19PrivateHomeRedaction,
                title: "W19 私人据点坐标脱敏",
                summary: "据点脱敏",
                redactionSample: "HomeReturnCheck[redacted]",
                isEnforced: true
            ),
            PrivacyRedactionPillarRow(
                kind: .w13LocationShareDisclosure,
                title: "W13.5 位置共享六项必读告知",
                summary: "缺少撤回说明",
                redactionSample: "5/6",
                isEnforced: false
            ),
            PrivacyRedactionPillarRow(
                kind: .gW04NpcSensitiveFilterAndDelete,
                title: "G-W04 / I08 NPC 对话敏感过滤与删除围栏",
                summary: "已启用",
                redactionSample: "[敏感信息已拦截]",
                isEnforced: true
            ),
            PrivacyRedactionPillarRow(
                kind: .i05DeletedMediaCacheEviction,
                title: "I05 404/DELETED 媒体缓存即时驱逐",
                summary: "未启用",
                redactionSample: "stale-cache",
                isEnforced: false
            )
        ]

        let nonCompliant = PrivacyAndSecurityRedactionSnapshot(
            privateHomeCoordinatesRedacted: true,
            locationShareDisclosureItemsCount: 5,
            npcSensitiveFilterAndDeletionFenced: true,
            deletedMediaCacheEvictedImmediately: false,
            rows: partialRows
        )
        XCTAssertFalse(nonCompliant.hasCompleteLocationDisclosures)
        XCTAssertFalse(nonCompliant.isAllCompliant)
        XCTAssertEqual(nonCompliant.enforcedRowCount, 2)
        XCTAssertEqual(
            PrivacyAndSecurityRedactionSectionView.overallStatusText(for: nonCompliant),
            "整体状态：存在未生效的隐私脱敏或安全围栏项（2/4）"
        )
        XCTAssertEqual(
            PrivacyAndSecurityRedactionSectionView.locationDisclosureStatusText(for: nonCompliant),
            "W13.5 位置共享告知：5/6 项已齐备"
        )
        XCTAssertEqual(
            PrivacyAndSecurityRedactionSectionView.cacheEvictionStatusText(for: nonCompliant),
            "I05 媒体缓存驱逐：404/DELETED 即时清理未启用"
        )

        let view = PrivacyAndSecurityRedactionSectionView(snapshot: nonCompliant)
        _ = view.body
    }

    func testEmptyRowsSnapshotIsNotCompliantAndRendersEmptyState() {
        let emptySnapshot = PrivacyAndSecurityRedactionSnapshot(
            privateHomeCoordinatesRedacted: true,
            locationShareDisclosureItemsCount: 6,
            npcSensitiveFilterAndDeletionFenced: true,
            deletedMediaCacheEvictedImmediately: true,
            rows: []
        )
        XCTAssertFalse(emptySnapshot.isAllCompliant)
        XCTAssertEqual(emptySnapshot.enforcedRowCount, 0)

        let view = PrivacyAndSecurityRedactionSectionView(snapshot: emptySnapshot)
        XCTAssertTrue(view.snapshot.rows.isEmpty)
        _ = view.body
    }
}

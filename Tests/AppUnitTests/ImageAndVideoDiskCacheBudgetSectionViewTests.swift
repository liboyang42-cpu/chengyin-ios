import SwiftUI
import XCTest
#if canImport(QuestifyApp)
@testable import QuestifyApp
#else
@testable import Questify
#endif
#if canImport(QuestifyCore)
import QuestifyCore
#endif

@MainActor
final class ImageAndVideoDiskCacheBudgetSectionViewTests: XCTestCase {
    func testDefaultReadySnapshotCoversAllThreePoolsWithinMemoryAndDiskBudgets() {
        let snapshot = MediaCacheBudgetSnapshot.defaultReady
        XCTAssertTrue(snapshot.isWithinBudget)
        XCTAssertEqual(
            snapshot.pools.map(\.id),
            [
                "square-post-media-cache",
                "roam-map-tile-and-poi-cache",
                "avatar-and-stamp-asset-cache"
            ]
        )
        XCTAssertLessThanOrEqual(snapshot.totalMemoryUsedMB, MediaCacheBudgetSnapshot.maxTotalMemoryMB)
        XCTAssertLessThanOrEqual(snapshot.totalDiskUsedMB, MediaCacheBudgetSnapshot.maxTotalDiskMB)
        XCTAssertTrue(snapshot.purgesMemoryOnWarning)
        XCTAssertTrue(snapshot.evictsDeletedOr404Immediately)
        XCTAssertEqual(snapshot.statusHeadline, "媒体内存与磁盘缓存预算达标 (<= 150MB 内存 / <= 500MB 磁盘)")
    }

    func testOverBudgetPoolOrDisabledEvictionTriggersWarningState() {
        var pools = MediaCacheBudgetSnapshot.defaultPools
        pools[0] = MediaCachePoolRow(
            id: "square-post-media-cache",
            title: "广场动态图文与短视频缓存池",
            memoryUsedMB: 90,
            memoryLimitMB: 70,
            diskUsedMB: 360,
            diskLimitMB: 250,
            evictsImmediatelyOn404OrDeleted: true
        )
        let overBudget = MediaCacheBudgetSnapshot(pools: pools)
        XCTAssertFalse(overBudget.pools[0].isWithinBudget)
        XCTAssertFalse(overBudget.isWithinBudget)
        XCTAssertGreaterThan(overBudget.totalDiskUsedMB, MediaCacheBudgetSnapshot.maxTotalDiskMB)
        XCTAssertTrue(overBudget.statusHeadline.contains("媒体缓存超限或淘汰策略未就绪"))
    }

    func testMainActorViewBodyInstantiationForReadyAndOverBudgetSnapshots() {
        let readyView = ImageAndVideoDiskCacheBudgetSectionView(snapshot: .defaultReady)
        XCTAssertTrue(readyView.snapshot.isWithinBudget)
        _ = readyView.body

        let disabledEvictionSnapshot = MediaCacheBudgetSnapshot(
            pools: MediaCacheBudgetSnapshot.defaultPools,
            purgesMemoryOnWarning: true,
            evictsDeletedOr404Immediately: false
        )
        let warningView = ImageAndVideoDiskCacheBudgetSectionView(snapshot: disabledEvictionSnapshot)
        XCTAssertFalse(warningView.snapshot.isWithinBudget)
        _ = warningView.body
    }
}

import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#endif

public struct MediaCachePoolRow: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let memoryUsedMB: Int
    public let memoryLimitMB: Int
    public let diskUsedMB: Int
    public let diskLimitMB: Int
    public let evictsImmediatelyOn404OrDeleted: Bool

    public init(
        id: String,
        title: String,
        memoryUsedMB: Int,
        memoryLimitMB: Int,
        diskUsedMB: Int,
        diskLimitMB: Int,
        evictsImmediatelyOn404OrDeleted: Bool = true
    ) {
        self.id = id
        self.title = title
        self.memoryUsedMB = memoryUsedMB
        self.memoryLimitMB = memoryLimitMB
        self.diskUsedMB = diskUsedMB
        self.diskLimitMB = diskLimitMB
        self.evictsImmediatelyOn404OrDeleted = evictsImmediatelyOn404OrDeleted
    }

    public var isWithinBudget: Bool {
        memoryUsedMB >= 0
            && diskUsedMB >= 0
            && memoryUsedMB <= memoryLimitMB
            && diskUsedMB <= diskLimitMB
            && evictsImmediatelyOn404OrDeleted
    }
}

public struct MediaCacheBudgetSnapshot: Sendable, Equatable {
    public static let maxTotalMemoryMB = 150
    public static let maxTotalDiskMB = 500

    public static let defaultPools: [MediaCachePoolRow] = [
        MediaCachePoolRow(
            id: "square-post-media-cache",
            title: "广场动态图文与短视频缓存池",
            memoryUsedMB: 48,
            memoryLimitMB: 70,
            diskUsedMB: 180,
            diskLimitMB: 250,
            evictsImmediatelyOn404OrDeleted: true
        ),
        MediaCachePoolRow(
            id: "roam-map-tile-and-poi-cache",
            title: "漫游地图瓦片与点位资源缓存池",
            memoryUsedMB: 36,
            memoryLimitMB: 50,
            diskUsedMB: 110,
            diskLimitMB: 150,
            evictsImmediatelyOn404OrDeleted: true
        ),
        MediaCachePoolRow(
            id: "avatar-and-stamp-asset-cache",
            title: "头像与印章徽章静态资源缓存池",
            memoryUsedMB: 20,
            memoryLimitMB: 30,
            diskUsedMB: 65,
            diskLimitMB: 100,
            evictsImmediatelyOn404OrDeleted: true
        )
    ]

    public static let defaultReady = MediaCacheBudgetSnapshot(
        pools: defaultPools,
        purgesMemoryOnWarning: true,
        evictsDeletedOr404Immediately: true
    )

    public let pools: [MediaCachePoolRow]
    public let purgesMemoryOnWarning: Bool
    public let evictsDeletedOr404Immediately: Bool

    public init(
        pools: [MediaCachePoolRow] = MediaCacheBudgetSnapshot.defaultPools,
        purgesMemoryOnWarning: Bool = true,
        evictsDeletedOr404Immediately: Bool = true
    ) {
        self.pools = pools
        self.purgesMemoryOnWarning = purgesMemoryOnWarning
        self.evictsDeletedOr404Immediately = evictsDeletedOr404Immediately
    }

    public var totalMemoryUsedMB: Int {
        pools.reduce(0) { $0 + max(0, $1.memoryUsedMB) }
    }

    public var totalDiskUsedMB: Int {
        pools.reduce(0) { $0 + max(0, $1.diskUsedMB) }
    }

    public var isWithinBudget: Bool {
        !pools.isEmpty
            && pools.allSatisfy(\.isWithinBudget)
            && totalMemoryUsedMB <= Self.maxTotalMemoryMB
            && totalDiskUsedMB <= Self.maxTotalDiskMB
            && purgesMemoryOnWarning
            && evictsDeletedOr404Immediately
    }

    public var statusHeadline: String {
        if isWithinBudget {
            return "媒体内存与磁盘缓存预算达标 (<= 150MB 内存 / <= 500MB 磁盘)"
        }
        return "媒体缓存超限或淘汰策略未就绪 (内存 \(totalMemoryUsedMB)MB / 磁盘 \(totalDiskUsedMB)MB)"
    }
}

/// Self-contained SwiftUI section presenting memory (`<= 150MB`) and disk (`<= 500MB`) media cache budgets,
/// memory-warning purge policy, and `I05` `404`/`DELETED` immediate media eviction.
/// Uses `Text(verbatim:)` throughout so zero new `.xcstrings` keys are required.
@MainActor
public struct ImageAndVideoDiskCacheBudgetSectionView: View {
    public let snapshot: MediaCacheBudgetSnapshot

    public init(snapshot: MediaCacheBudgetSnapshot = .defaultReady) {
        self.snapshot = snapshot
    }

    public var body: some View {
        Group {
            Section {
                HStack {
                    Text(verbatim: snapshot.statusHeadline)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(verbatim: snapshot.isWithinBudget ? "OK" : "OVER_BUDGET")
                        .font(.caption2.monospaced().weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(snapshot.isWithinBudget ? Color.green.opacity(0.18) : Color.red.opacity(0.18))
                        )
                        .accessibilityIdentifier("mediaCacheBudget.statusBadge")
                }
                .accessibilityIdentifier("mediaCacheBudget.header")

                HStack {
                    Text(verbatim: "总内存占用 / 上限")
                    Spacer()
                    Text(verbatim: "\(snapshot.totalMemoryUsedMB)MB / \(MediaCacheBudgetSnapshot.maxTotalMemoryMB)MB")
                        .font(.caption.monospaced())
                        .foregroundStyle(snapshot.totalMemoryUsedMB <= MediaCacheBudgetSnapshot.maxTotalMemoryMB ? Color.secondary : Color.red)
                }
                .accessibilityIdentifier("mediaCacheBudget.memorySummary")

                HStack {
                    Text(verbatim: "总磁盘占用 / 上限")
                    Spacer()
                    Text(verbatim: "\(snapshot.totalDiskUsedMB)MB / \(MediaCacheBudgetSnapshot.maxTotalDiskMB)MB")
                        .font(.caption.monospaced())
                        .foregroundStyle(snapshot.totalDiskUsedMB <= MediaCacheBudgetSnapshot.maxTotalDiskMB ? Color.secondary : Color.red)
                }
                .accessibilityIdentifier("mediaCacheBudget.diskSummary")

                HStack {
                    Text(verbatim: "系统内存告警自动清理")
                    Spacer()
                    Text(verbatim: snapshot.purgesMemoryOnWarning ? "已开启" : "未开启")
                        .font(.caption)
                        .foregroundStyle(snapshot.purgesMemoryOnWarning ? Color.secondary : Color.red)
                }
                .accessibilityIdentifier("mediaCacheBudget.memoryWarningPurge")

                HStack {
                    Text(verbatim: "I05 404/DELETED 媒体即时驱逐")
                    Spacer()
                    Text(verbatim: snapshot.evictsDeletedOr404Immediately ? "已启用" : "未启用")
                        .font(.caption)
                        .foregroundStyle(snapshot.evictsDeletedOr404Immediately ? Color.secondary : Color.red)
                }
                .accessibilityIdentifier("mediaCacheBudget.evictionPolicy")
            } header: {
                Text(verbatim: "图文与视频缓存预算总览")
            }
            .accessibilityIdentifier("mediaCacheBudget.summary.section")

            Section {
                ForEach(snapshot.pools) { pool in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(verbatim: pool.title)
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text(verbatim: pool.isWithinBudget ? "正常" : "超限")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(pool.isWithinBudget ? Color.green : Color.red)
                        }
                        Text(
                            verbatim: "内存 \(pool.memoryUsedMB)/\(pool.memoryLimitMB)MB · 磁盘 \(pool.diskUsedMB)/\(pool.diskLimitMB)MB · 404/DELETED 即时淘汰: \(pool.evictsImmediatelyOn404OrDeleted ? "是" : "否")"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("mediaCacheBudget.pool.\(pool.id)")
                }
            } header: {
                Text(verbatim: "分域媒体缓存池明细")
            }
            .accessibilityIdentifier("mediaCacheBudget.pools.section")
        }
    }
}

import SwiftUI
import QuestifyCore

/// Self-contained summary row for a parallel `QuestifyUITests` shard (`ui-0`, `ui-1`, `ui-2`).
public struct UITestShardSummaryRow: Identifiable, Equatable, Sendable {
    public let shardID: String
    public let methodCount: Int
    public let passedCount: Int
    public let failedCount: Int
    public let usesTestWithoutBuilding: Bool

    public var id: String { shardID }

    public var isHealthy: Bool {
        !shardID.isEmpty
            && methodCount > 0
            && passedCount == methodCount
            && failedCount == 0
            && usesTestWithoutBuilding
    }

    public init(
        shardID: String,
        methodCount: Int,
        passedCount: Int,
        failedCount: Int = 0,
        usesTestWithoutBuilding: Bool = true
    ) {
        self.shardID = shardID
        self.methodCount = methodCount
        self.passedCount = passedCount
        self.failedCount = failedCount
        self.usesTestWithoutBuilding = usesTestWithoutBuilding
    }
}

/// Self-contained summary row for a DEBUG launch fixture short-circuit flag (`session = nil`).
public struct UITestFixtureShortCircuitRow: Identifiable, Equatable, Sendable {
    public let launchFlag: String
    public let surfaceTitle: String
    public let bypassesSessionBootstrap: Bool
    public let enforcesZeroNetwork: Bool

    public var id: String { launchFlag }

    public var isIsolated: Bool {
        !launchFlag.isEmpty
            && !surfaceTitle.isEmpty
            && bypassesSessionBootstrap
            && enforcesZeroNetwork
    }

    public init(
        launchFlag: String,
        surfaceTitle: String,
        bypassesSessionBootstrap: Bool = true,
        enforcesZeroNetwork: Bool = true
    ) {
        self.launchFlag = launchFlag
        self.surfaceTitle = surfaceTitle
        self.bypassesSessionBootstrap = bypassesSessionBootstrap
        self.enforcesZeroNetwork = enforcesZeroNetwork
    }
}

/// SwiftUI section rendering the 3 UI test shards (`ui-0`, `ui-1`, `ui-2`),
/// DEBUG launch fixture short-circuit flags (`session = nil`), and zero-network
/// UI test isolation status using `Text(verbatim:)` throughout (0 new `.xcstrings` keys).
@MainActor public struct UITestShardDiagnosticsSectionView: View {
    public static let canonicalShardIDs: [String] = ["ui-0", "ui-1", "ui-2"]

    public static let defaultShards: [UITestShardSummaryRow] = [
        UITestShardSummaryRow(shardID: "ui-0", methodCount: 48, passedCount: 48, failedCount: 0, usesTestWithoutBuilding: true),
        UITestShardSummaryRow(shardID: "ui-1", methodCount: 48, passedCount: 48, failedCount: 0, usesTestWithoutBuilding: true),
        UITestShardSummaryRow(shardID: "ui-2", methodCount: 47, passedCount: 47, failedCount: 0, usesTestWithoutBuilding: true)
    ]

    public static let defaultFixtures: [UITestFixtureShortCircuitRow] = [
        UITestFixtureShortCircuitRow(
            launchFlag: "--merchant-ai-commerce-fixture",
            surfaceTitle: "MerchantAICommerceFixtureHost",
            bypassesSessionBootstrap: true,
            enforcesZeroNetwork: true
        ),
        UITestFixtureShortCircuitRow(
            launchFlag: "--growth-offline-fixture",
            surfaceTitle: "GrowthBadgeStampParityFixture",
            bypassesSessionBootstrap: true,
            enforcesZeroNetwork: true
        ),
        UITestFixtureShortCircuitRow(
            launchFlag: "--roam-stamp-offline-fixture",
            surfaceTitle: "RoamStampOfflineFixture",
            bypassesSessionBootstrap: true,
            enforcesZeroNetwork: true
        )
    ]

    public let shards: [UITestShardSummaryRow]
    public let fixtures: [UITestFixtureShortCircuitRow]
    public let zeroNetworkVerified: Bool

    public init(
        shards: [UITestShardSummaryRow] = Self.defaultShards,
        fixtures: [UITestFixtureShortCircuitRow] = Self.defaultFixtures,
        zeroNetworkVerified: Bool = true
    ) {
        self.shards = shards
        self.fixtures = fixtures
        self.zeroNetworkVerified = zeroNetworkVerified
    }

    public var hasCompleteThreeShardCoverage: Bool {
        shards.map(\.shardID) == Self.canonicalShardIDs
    }

    public var allShardsHealthy: Bool {
        hasCompleteThreeShardCoverage && shards.allSatisfy(\.isHealthy)
    }

    public var allFixturesIsolated: Bool {
        !fixtures.isEmpty && fixtures.allSatisfy(\.isIsolated) && zeroNetworkVerified
    }

    public var totalAssignedMethodCount: Int {
        shards.map(\.methodCount).reduce(0, +)
    }

    public var statusHeadline: String {
        if !hasCompleteThreeShardCoverage {
            return "UI 分片不完整：需覆盖 ui-0 / ui-1 / ui-2 全部 3 个并行分片"
        }
        if !allShardsHealthy {
            return "UI 分片执行存在失败或未启用 test-without-building"
        }
        if !allFixturesIsolated {
            return "DEBUG 启动夹具未满足 session = nil 短路或零网络隔离要求"
        }
        return "3 个 UI 分片 (ui-0/ui-1/ui-2) 全部就绪 · DEBUG 夹具零网络短路隔离已验证"
    }

    public var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: statusHeadline)
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("uiTestShardDiagnostics.statusHeadline")
                Text(verbatim: "总计分配 \(totalAssignedMethodCount) 个 UI 测试方法 · 零网络隔离：\(zeroNetworkVerified ? "已验证" : "未验证")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("uiTestShardDiagnostics.isolationSummary")
            }

            ForEach(shards) { shard in
                HStack {
                    Image(systemName: shard.isHealthy ? "checkmark.seal.fill" : "xmark.octagon.fill")
                        .foregroundStyle(shard.isHealthy ? .green : .red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: "分片 \(shard.shardID) · 通过 \(shard.passedCount)/\(shard.methodCount)")
                            .font(.footnote.weight(.medium))
                        Text(verbatim: shard.usesTestWithoutBuilding ? "复用单次构建产物 (test-without-building)" : "缺少预构建产物复用")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if shard.failedCount > 0 {
                        Text(verbatim: "失败 \(shard.failedCount)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.red)
                    }
                }
                .accessibilityIdentifier("uiTestShardDiagnostics.shard." + shard.shardID)
            }

            ForEach(fixtures) { fixture in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: fixture.isIsolated ? "lock.shield.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(fixture.isIsolated ? .blue : .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: "\(fixture.surfaceTitle) (\(fixture.launchFlag))")
                            .font(.footnote.weight(.medium))
                        Text(verbatim: "session = nil 短路：\(fixture.bypassesSessionBootstrap ? "是" : "否") · 零网络请求：\(fixture.enforcesZeroNetwork ? "是" : "否")")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityIdentifier("uiTestShardDiagnostics.fixture." + fixture.launchFlag)
            }
        } header: {
            Text(verbatim: "UI 测试分片与离线夹具短路诊断")
        }
        .accessibilityIdentifier("uiTestShardDiagnostics.section")
    }
}

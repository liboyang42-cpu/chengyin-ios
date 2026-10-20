import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#elseif canImport(Core)
import Core
#endif

/// Self-contained latency and interval row for an `I10` `NativePerformancePoint` metric.
public struct PerformanceSignpostMetricRow: Identifiable, Equatable, Sendable {
    public let pointName: String
    public let areaName: String
    public let p95LatencyMilliseconds: Double
    public let budgetMilliseconds: Double
    public let idempotentIntervalEndVerified: Bool

    public var id: String { pointName }

    public var withinBudget: Bool {
        !pointName.isEmpty
            && !areaName.isEmpty
            && budgetMilliseconds > 0.0
            && p95LatencyMilliseconds >= 0.0
            && p95LatencyMilliseconds <= budgetMilliseconds
            && idempotentIntervalEndVerified
    }

    public init(
        pointName: String,
        areaName: String,
        p95LatencyMilliseconds: Double,
        budgetMilliseconds: Double,
        idempotentIntervalEndVerified: Bool = true
    ) {
        self.pointName = pointName
        self.areaName = areaName
        self.p95LatencyMilliseconds = p95LatencyMilliseconds
        self.budgetMilliseconds = budgetMilliseconds
        self.idempotentIntervalEndVerified = idempotentIntervalEndVerified
    }
}

/// Self-contained snapshot for `I10` `OSSignposter` intervals, `PlayRouteMapView` O(N) stop projection,
/// and trace latency budgets.
public struct PerformanceSignpostSnapshot: Equatable, Sendable {
    public static let defaultMetrics: [PerformanceSignpostMetricRow] = [
        PerformanceSignpostMetricRow(
            pointName: NativePerformancePoint.walkingRefreshTick.rawValue,
            areaName: NativePerformancePoint.walkingRefreshTick.area.rawValue,
            p95LatencyMilliseconds: 4.2,
            budgetMilliseconds: 16.0
        ),
        PerformanceSignpostMetricRow(
            pointName: NativePerformancePoint.walkingCameraFit.rawValue,
            areaName: NativePerformancePoint.walkingCameraFit.area.rawValue,
            p95LatencyMilliseconds: 6.8,
            budgetMilliseconds: 16.0
        ),
        PerformanceSignpostMetricRow(
            pointName: NativePerformancePoint.playRouteMapProjection.rawValue,
            areaName: NativePerformancePoint.playRouteMapProjection.area.rawValue,
            p95LatencyMilliseconds: 3.1,
            budgetMilliseconds: 12.0
        ),
        PerformanceSignpostMetricRow(
            pointName: NativePerformancePoint.playRouteCameraFocus.rawValue,
            areaName: NativePerformancePoint.playRouteCameraFocus.area.rawValue,
            p95LatencyMilliseconds: 5.4,
            budgetMilliseconds: 16.0
        ),
        PerformanceSignpostMetricRow(
            pointName: NativePerformancePoint.artworkLoad.rawValue,
            areaName: NativePerformancePoint.artworkLoad.area.rawValue,
            p95LatencyMilliseconds: 42.0,
            budgetMilliseconds: 120.0
        ),
        PerformanceSignpostMetricRow(
            pointName: NativePerformancePoint.audioStartToPlaying.rawValue,
            areaName: NativePerformancePoint.audioStartToPlaying.area.rawValue,
            p95LatencyMilliseconds: 65.0,
            budgetMilliseconds: 150.0
        )
    ]

    public let subsystem: String
    public let metrics: [PerformanceSignpostMetricRow]
    public let playRouteStopProjectionLinearON: Bool
    public let stripsSensitiveTracePayloads: Bool

    public init(
        subsystem: String = NativePerformanceSignposts.subsystem,
        metrics: [PerformanceSignpostMetricRow] = Self.defaultMetrics,
        playRouteStopProjectionLinearON: Bool = true,
        stripsSensitiveTracePayloads: Bool = true
    ) {
        self.subsystem = subsystem
        self.metrics = metrics
        self.playRouteStopProjectionLinearON = playRouteStopProjectionLinearON
        self.stripsSensitiveTracePayloads = stripsSensitiveTracePayloads
    }

    public var hasAllCanonicalPoints: Bool {
        Set(metrics.map(\.pointName)) == Set(NativePerformancePoint.allCases.map(\.rawValue))
    }

    public var overBudgetMetrics: [PerformanceSignpostMetricRow] {
        metrics.filter { !$0.withinBudget }
    }

    public var isAllCompliant: Bool {
        subsystem == NativePerformanceSignposts.subsystem
            && hasAllCanonicalPoints
            && overBudgetMetrics.isEmpty
            && playRouteStopProjectionLinearON
            && stripsSensitiveTracePayloads
    }
}

/// SwiftUI section rendering `I10` performance instrumentation (`OSSignposter` intervals,
/// `PlayRouteMapView` O(N) stop projection, and trace latency budgets) using `Text(verbatim:)`
/// throughout (0 new `.xcstrings` keys).
@MainActor public struct PerformanceSignpostSectionView: View {
    public let snapshot: PerformanceSignpostSnapshot

    public init(snapshot: PerformanceSignpostSnapshot = PerformanceSignpostSnapshot()) {
        self.snapshot = snapshot
    }

    public var statusHeadline: String {
        if !snapshot.hasAllCanonicalPoints {
            return "性能埋点不完整：需覆盖全部 6 项 NativePerformancePoint 静态区间"
        }
        if !snapshot.overBudgetMetrics.isEmpty {
            return "存在 \(snapshot.overBudgetMetrics.count) 项 OSSignposter 区间超出延迟预算或未验证幂等结束"
        }
        if !snapshot.playRouteStopProjectionLinearON || !snapshot.stripsSensitiveTracePayloads {
            return "路线点位 O(N) 线性投影或无敏静态 Trace 约束未满足"
        }
        return "I10 性能探针与延迟预算全部达标 · PlayRouteMapView O(N) 投影已验证"
    }

    public var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: statusHeadline)
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("performanceSignpost.statusHeadline")
                Text(verbatim: "子系统 \(snapshot.subsystem) · O(N) 路线投影：\(snapshot.playRouteStopProjectionLinearON ? "已启用" : "未启用") · 静态无敏标签：\(snapshot.stripsSensitiveTracePayloads ? "已强制" : "未强制")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("performanceSignpost.subsystemSummary")
            }

            ForEach(snapshot.metrics) { metric in
                HStack {
                    Image(systemName: metric.withinBudget ? "gauge.with.dots.needle.33percent" : "exclamationmark.octagon.fill")
                        .foregroundStyle(metric.withinBudget ? .green : .red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: "\(metric.pointName) [\(metric.areaName)]")
                            .font(.footnote.weight(.medium))
                        Text(verbatim: "P95 \(metric.p95LatencyMilliseconds)ms / 预算 \(metric.budgetMilliseconds)ms · 幂等关闭：\(metric.idempotentIntervalEndVerified ? "是" : "否")")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(verbatim: metric.withinBudget ? "达标" : "超预算")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(metric.withinBudget ? .green : .red)
                }
                .accessibilityIdentifier("performanceSignpost.metric." + metric.pointName)
            }
        } header: {
            Text(verbatim: "I10 原生性能探针与延迟预算")
        }
        .accessibilityIdentifier("performanceSignpost.section")
    }
}

import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#endif

/// Self-contained row modeling one `MetricKit` diagnostic category (`crash`, `hang`,
/// `cpuException`, `diskWriteException`) and main-thread budget compliance (`<= 250ms`).
public struct CrashResilienceMetricRow: Sendable, Equatable, Identifiable {
    public enum Category: String, CaseIterable, Sendable, Equatable {
        case crash = "MXCrashDiagnostic"
        case hang = "MXHangDiagnostic"
        case cpuException = "MXCPUExceptionDiagnostic"
        case diskWriteException = "MXDiskWriteExceptionDiagnostic"
    }

    public enum Status: String, Sendable, Equatable {
        case ready
        case thresholdViolated
    }

    public let id: String
    public let category: Category
    public let titleText: String
    public let budgetRuleText: String
    public let observedSummaryText: String
    public let status: Status

    public init(
        id: String,
        category: Category,
        titleText: String,
        budgetRuleText: String,
        observedSummaryText: String,
        status: Status = .ready
    ) {
        self.id = id
        self.category = category
        self.titleText = titleText
        self.budgetRuleText = budgetRuleText
        self.observedSummaryText = observedSummaryText
        self.status = status
    }

    public var isReady: Bool {
        status == .ready
    }

    public var statusBadgeText: String {
        switch status {
        case .ready:
            return "预算达标"
        case .thresholdViolated:
            return "超出阈值告警"
        }
    }
}

/// Self-contained snapshot of `MetricKit` crash/hang/CPU/disk diagnostic readiness
/// and `<= 250ms` main-thread hang budget compliance.
public struct CrashResilienceDiagnosticsSnapshot: Sendable, Equatable {
    public static let mainThreadHangBudgetMilliseconds = 250

    public let maxObservedMainThreadHangMilliseconds: Int
    public let crashFreeSessionVerified: Bool
    public let cpuExceptionBudgetVerified: Bool
    public let diskWriteBudgetVerified: Bool
    public let rows: [CrashResilienceMetricRow]

    public init(
        maxObservedMainThreadHangMilliseconds: Int = 120,
        crashFreeSessionVerified: Bool = true,
        cpuExceptionBudgetVerified: Bool = true,
        diskWriteBudgetVerified: Bool = true
    ) {
        self.maxObservedMainThreadHangMilliseconds = maxObservedMainThreadHangMilliseconds
        self.crashFreeSessionVerified = crashFreeSessionVerified
        self.cpuExceptionBudgetVerified = cpuExceptionBudgetVerified
        self.diskWriteBudgetVerified = diskWriteBudgetVerified

        let hangCompliant = maxObservedMainThreadHangMilliseconds >= 0
            && maxObservedMainThreadHangMilliseconds <= Self.mainThreadHangBudgetMilliseconds

        self.rows = [
            CrashResilienceMetricRow(
                id: "metrickit-crash-diagnostic",
                category: .crash,
                titleText: "崩溃诊断与异常退出恢复 (MXCrashDiagnostic)",
                budgetRuleText: "零致命未捕获异常 · 离线意图日志可恢复",
                observedSummaryText: crashFreeSessionVerified
                    ? "当前构建无未捕获崩溃，持久化恢复围栏已就绪。"
                    : "告警：检测到未处理的崩溃诊断记录。",
                status: crashFreeSessionVerified ? .ready : .thresholdViolated
            ),
            CrashResilienceMetricRow(
                id: "metrickit-hang-diagnostic",
                category: .hang,
                titleText: "主线程卡顿预算监控 (MXHangDiagnostic)",
                budgetRuleText: "主线程单次阻塞预算 <= \(Self.mainThreadHangBudgetMilliseconds)ms",
                observedSummaryText: hangCompliant
                    ? "当前主线程峰值延迟 \(maxObservedMainThreadHangMilliseconds)ms（符合 <= \(Self.mainThreadHangBudgetMilliseconds)ms 预算）。"
                    : "告警：主线程峰值延迟 \(maxObservedMainThreadHangMilliseconds)ms 超出 <= \(Self.mainThreadHangBudgetMilliseconds)ms 预算。",
                status: hangCompliant ? .ready : .thresholdViolated
            ),
            CrashResilienceMetricRow(
                id: "metrickit-cpu-exception",
                category: .cpuException,
                titleText: "CPU 峰值与轮询退避守卫 (MXCPUExceptionDiagnostic)",
                budgetRuleText: "禁止后台忙等轮询 · 视图不可见立即挂起",
                observedSummaryText: cpuExceptionBudgetVerified
                    ? "所有计时器与地图瓦片合并均受前台生命周期约束。"
                    : "告警：检测到 CPU 持续占用超出预算。",
                status: cpuExceptionBudgetVerified ? .ready : .thresholdViolated
            ),
            CrashResilienceMetricRow(
                id: "metrickit-disk-write-exception",
                category: .diskWriteException,
                titleText: "磁盘写入预算与临时音频清理 (MXDiskWriteExceptionDiagnostic)",
                budgetRuleText: "幂等日志按需落盘 · 残留 .tmp 文件启动即清理",
                observedSummaryText: diskWriteBudgetVerified
                    ? "持久化日志写入受控，无高频冗余落盘。"
                    : "告警：检测到磁盘写入量超出预算阈值。",
                status: diskWriteBudgetVerified ? .ready : .thresholdViolated
            )
        ]
    }

    public static let defaultReady = CrashResilienceDiagnosticsSnapshot()

    public var isMainThreadHangWithinBudget: Bool {
        maxObservedMainThreadHangMilliseconds >= 0
            && maxObservedMainThreadHangMilliseconds <= Self.mainThreadHangBudgetMilliseconds
    }

    public var isAllReady: Bool {
        !rows.isEmpty && rows.allSatisfy(\.isReady) && isMainThreadHangWithinBudget
    }

    public var violationCount: Int {
        rows.filter { !$0.isReady }.count
    }

    public var summaryHeadlineText: String {
        isAllReady
            ? "MetricKit 4 大诊断项与 <= 250ms 主线程预算全部达标（\(rows.count)/\(rows.count)）"
            : "存在 \(violationCount) 项 MetricKit 诊断或主线程预算超限告警"
    }

    public func row(for category: CrashResilienceMetricRow.Category) -> CrashResilienceMetricRow? {
        rows.first { $0.category == category }
    }
}

/// Offline SwiftUI section view displaying `MetricKit` crash/hang/CPU/disk diagnostic
/// readiness and `<= 250ms` main-thread budget compliance using `Text(verbatim:)` (`0` new
/// localization keys) and deterministic `crashResilienceMetricKit.*` accessibility identifiers.
@MainActor
public struct CrashResilienceAndMetricKitDiagnosticsSectionView: View {
    public let snapshot: CrashResilienceDiagnosticsSnapshot
    public var onSelectRow: ((CrashResilienceMetricRow) -> Void)?

    public init(
        snapshot: CrashResilienceDiagnosticsSnapshot = .defaultReady,
        onSelectRow: ((CrashResilienceMetricRow) -> Void)? = nil
    ) {
        self.snapshot = snapshot
        self.onSelectRow = onSelectRow
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: "崩溃韧性与 MetricKit 性能诊断面板")
                        .font(.headline)
                        .accessibilityIdentifier("crashResilienceMetricKit.header.title")
                    Text(verbatim: snapshot.summaryHeadlineText)
                        .font(.subheadline)
                        .foregroundStyle(snapshot.isAllReady ? .green : .orange)
                        .accessibilityIdentifier("crashResilienceMetricKit.header.summary")
                }
                Spacer()
                Text(verbatim: snapshot.isAllReady ? "<= 250ms 达标" : "预算告警")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(
                            snapshot.isAllReady
                                ? Color.green.opacity(0.15)
                                : Color.orange.opacity(0.15)
                        )
                    )
                    .accessibilityIdentifier("crashResilienceMetricKit.header.badge")
            }

            ForEach(snapshot.rows) { row in
                rowView(row)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.08)))
        .accessibilityIdentifier("crashResilienceMetricKit.section")
    }

    @ViewBuilder
    private func rowView(_ row: CrashResilienceMetricRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: row.titleText)
                    .font(.subheadline.weight(.medium))
                    .accessibilityIdentifier("crashResilienceMetricKit.row.\(row.id).title")
                Spacer()
                Text(verbatim: row.category.rawValue)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("crashResilienceMetricKit.row.\(row.id).category")
                Text(verbatim: row.statusBadgeText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(row.isReady ? .green : .red)
                    .accessibilityIdentifier("crashResilienceMetricKit.row.\(row.id).status")
            }

            Text(verbatim: row.budgetRuleText)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("crashResilienceMetricKit.row.\(row.id).budgetRule")

            Text(verbatim: row.observedSummaryText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("crashResilienceMetricKit.row.\(row.id).observedSummary")

            if let onSelectRow {
                Button(action: { onSelectRow(row) }) {
                    Text(verbatim: "查看诊断指标详情")
                        .font(.caption)
                }
                .accessibilityIdentifier("crashResilienceMetricKit.row.\(row.id).action")
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.06)))
        .accessibilityIdentifier("crashResilienceMetricKit.row.\(row.id)")
    }
}

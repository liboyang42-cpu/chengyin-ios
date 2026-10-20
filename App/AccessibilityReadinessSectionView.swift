import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#endif

/// Per-surface accessibility & performance readiness check row (`I10` & App Store accessibility readiness).
public struct AccessibilitySurfaceCheckRow: Identifiable, Equatable, Sendable {
    public static let minimumWCAGContrastRatio: Double = 4.5

    public let id: String
    public let surfaceName: String
    public let voiceOverAnchorIdentifier: String
    public let voiceOverMounted: Bool
    public let reduceMotionFallbackVerified: Bool
    public let contrastRatio: Double

    public init(
        id: String,
        surfaceName: String,
        voiceOverAnchorIdentifier: String,
        voiceOverMounted: Bool,
        reduceMotionFallbackVerified: Bool,
        contrastRatio: Double
    ) {
        self.id = id
        self.surfaceName = surfaceName
        self.voiceOverAnchorIdentifier = voiceOverAnchorIdentifier
        self.voiceOverMounted = voiceOverMounted
        self.reduceMotionFallbackVerified = reduceMotionFallbackVerified
        self.contrastRatio = contrastRatio
    }

    public var meetsWCAGAA: Bool {
        contrastRatio >= Self.minimumWCAGContrastRatio
    }

    public var isCompliant: Bool {
        voiceOverMounted && reduceMotionFallbackVerified && meetsWCAGAA
    }
}

/// Self-contained snapshot for `I10` & App Store accessibility readiness:
/// VoiceOver anchor coverage, Reduce Motion fallback, WCAG 4.5:1 day/night contrast status,
/// and `OSSignposter` performance instrumentation.
public struct AccessibilityReadinessSnapshot: Equatable, Sendable {
    public let signposterSubsystem: String
    public let signposterCategory: String
    public let signposterInstrumentationActive: Bool
    public let reduceMotionSystemActive: Bool
    public let dayNightContrastVerified: Bool
    public let rows: [AccessibilitySurfaceCheckRow]

    public init(
        signposterSubsystem: String = "com.chengyin.questify.performance",
        signposterCategory: String = "I10AccessibilityReadiness",
        signposterInstrumentationActive: Bool,
        reduceMotionSystemActive: Bool,
        dayNightContrastVerified: Bool,
        rows: [AccessibilitySurfaceCheckRow]
    ) {
        self.signposterSubsystem = signposterSubsystem
        self.signposterCategory = signposterCategory
        self.signposterInstrumentationActive = signposterInstrumentationActive
        self.reduceMotionSystemActive = reduceMotionSystemActive
        self.dayNightContrastVerified = dayNightContrastVerified
        self.rows = rows
    }

    public var voiceOverCoveredCount: Int {
        rows.filter(\.voiceOverMounted).count
    }

    public var reduceMotionVerifiedCount: Int {
        rows.filter(\.reduceMotionFallbackVerified).count
    }

    public var wcagPassingCount: Int {
        rows.filter(\.meetsWCAGAA).count
    }

    public var isAllCompliant: Bool {
        signposterInstrumentationActive &&
            dayNightContrastVerified &&
            !rows.isEmpty &&
            rows.allSatisfy(\.isCompliant)
    }

    public static let compliantSample = AccessibilityReadinessSnapshot(
        signposterInstrumentationActive: true,
        reduceMotionSystemActive: true,
        dayNightContrastVerified: true,
        rows: [
            AccessibilitySurfaceCheckRow(
                id: "mapCore",
                surfaceName: "地图探索主入口",
                voiceOverAnchorIdentifier: "mapCore.manualBrowse",
                voiceOverMounted: true,
                reduceMotionFallbackVerified: true,
                contrastRatio: 5.2
            ),
            AccessibilitySurfaceCheckRow(
                id: "roamHistory",
                surfaceName: "漫游历史与轨迹",
                voiceOverAnchorIdentifier: "roamFinishedHistory.filter",
                voiceOverMounted: true,
                reduceMotionFallbackVerified: true,
                contrastRatio: 4.8
            ),
            AccessibilitySurfaceCheckRow(
                id: "projectEditor",
                surfaceName: "主题项目编辑器",
                voiceOverAnchorIdentifier: "projectEditor.name",
                voiceOverMounted: true,
                reduceMotionFallbackVerified: true,
                contrastRatio: 4.6
            )
        ]
    )
}

@MainActor
public struct AccessibilityReadinessSectionView: View {
    public let snapshot: AccessibilityReadinessSnapshot

    public init(snapshot: AccessibilityReadinessSnapshot = .compliantSample) {
        self.snapshot = snapshot
    }

    public var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: "无障碍与性能就绪审计 (I10)")
                    .font(.headline)
                    .accessibilityIdentifier("accessibilityReadiness.title")

                Text(verbatim: Self.overallStatusText(for: snapshot))
                    .font(.subheadline)
                    .foregroundStyle(snapshot.isAllCompliant ? .green : .red)
                    .accessibilityIdentifier("accessibilityReadiness.overallStatus")

                Text(verbatim: Self.voiceOverSummaryText(for: snapshot))
                    .font(.footnote)
                    .accessibilityIdentifier("accessibilityReadiness.voiceOverSummary")

                Text(verbatim: Self.reduceMotionSummaryText(for: snapshot))
                    .font(.footnote)
                    .accessibilityIdentifier("accessibilityReadiness.reduceMotionStatus")

                Text(verbatim: Self.contrastSummaryText(for: snapshot))
                    .font(.footnote)
                    .accessibilityIdentifier("accessibilityReadiness.contrastStatus")

                Text(verbatim: Self.signposterSummaryText(for: snapshot))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("accessibilityReadiness.signposterStatus")
            }
            .padding(.vertical, 4)

            if snapshot.rows.isEmpty {
                Text(verbatim: "暂无无障碍页面检查项")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("accessibilityReadiness.empty")
            } else {
                ForEach(snapshot.rows) { row in
                    AccessibilitySurfaceRowView(row: row)
                }
            }
        }
        .accessibilityIdentifier("accessibilityReadiness.section")
    }

    public static func overallStatusText(for snapshot: AccessibilityReadinessSnapshot) -> String {
        snapshot.isAllCompliant
            ? "整体状态：已通过全部无障碍与性能探针检查"
            : "整体状态：存在未达标的无障碍或性能探针项"
    }

    public static func voiceOverSummaryText(for snapshot: AccessibilityReadinessSnapshot) -> String {
        "VoiceOver 锚点覆盖：\(snapshot.voiceOverCoveredCount)/\(snapshot.rows.count)"
    }

    public static func reduceMotionSummaryText(for snapshot: AccessibilityReadinessSnapshot) -> String {
        let mode = snapshot.reduceMotionSystemActive ? "已启用减弱动态效果回退" : "标准动效模式"
        return "Reduce Motion：\(mode)（已验证 \(snapshot.reduceMotionVerifiedCount)/\(snapshot.rows.count)）"
    }

    public static func contrastSummaryText(for snapshot: AccessibilityReadinessSnapshot) -> String {
        let dayNight = snapshot.dayNightContrastVerified ? "日间/夜间双态已核验" : "日间/夜间双态待核验"
        return "WCAG 4.5:1 对比度：\(snapshot.wcagPassingCount)/\(snapshot.rows.count) 达标 · \(dayNight)"
    }

    public static func signposterSummaryText(for snapshot: AccessibilityReadinessSnapshot) -> String {
        let state = snapshot.signposterInstrumentationActive ? "已激活" : "未激活"
        return "OSSignposter：\(state)（\(snapshot.signposterSubsystem) / \(snapshot.signposterCategory)）"
    }
}

@MainActor
private struct AccessibilitySurfaceRowView: View {
    let row: AccessibilitySurfaceCheckRow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(verbatim: row.surfaceName)
                    .font(.subheadline.bold())
                Spacer()
                Text(verbatim: row.isCompliant ? "达标" : "待修复")
                    .font(.caption)
                    .foregroundStyle(row.isCompliant ? .green : .red)
            }

            Text(verbatim: "VoiceOver 锚点：\(row.voiceOverAnchorIdentifier)（\(row.voiceOverMounted ? "已挂载" : "缺失")）")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(verbatim: String(format: "对比度：%.2f:1（最低 %.1f:1） · Reduce Motion：%@", row.contrastRatio, AccessibilitySurfaceCheckRow.minimumWCAGContrastRatio, row.reduceMotionFallbackVerified ? "已回退" : "未验证"))
                .font(.caption2)
                .foregroundStyle(row.meetsWCAGAA ? .secondary : .red)
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("accessibilityReadiness.row")
    }
}

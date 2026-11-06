import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#elseif canImport(Core)
import Core
#endif

/// Self-contained surface row for `I10` `accessibilityReduceMotion` crossfade replacement,
/// `>= 120ms` haptic cooldown, and Low Power Mode shader throttling.
public struct MotionHapticSurfaceRow: Sendable, Equatable, Identifiable {
    public static let minimumHapticCooldownMilliseconds: Int = 120

    public let surfaceID: String
    public let title: String
    public let detail: String
    public let replacesSpringWithCrossfadeOnReduceMotion: Bool
    public let hapticCooldownMilliseconds: Int
    public let throttlesShadersInLowPowerMode: Bool

    public var id: String { surfaceID }

    public var isCompliant: Bool {
        !surfaceID.isEmpty
            && !title.isEmpty
            && replacesSpringWithCrossfadeOnReduceMotion
            && hapticCooldownMilliseconds >= Self.minimumHapticCooldownMilliseconds
            && throttlesShadersInLowPowerMode
    }

    public init(
        surfaceID: String,
        title: String,
        detail: String,
        replacesSpringWithCrossfadeOnReduceMotion: Bool = true,
        hapticCooldownMilliseconds: Int = 150,
        throttlesShadersInLowPowerMode: Bool = true
    ) {
        self.surfaceID = surfaceID
        self.title = title
        self.detail = detail
        self.replacesSpringWithCrossfadeOnReduceMotion = replacesSpringWithCrossfadeOnReduceMotion
        self.hapticCooldownMilliseconds = hapticCooldownMilliseconds
        self.throttlesShadersInLowPowerMode = throttlesShadersInLowPowerMode
    }
}

/// Self-contained snapshot for `I10` `accessibilityReduceMotion` crossfade replacement,
/// `>= 120ms` haptic cooldown, and Low Power Mode shader throttling.
public struct MotionHapticComplianceSnapshot: Sendable, Equatable {
    public static let defaultRows: [MotionHapticSurfaceRow] = [
        MotionHapticSurfaceRow(
            surfaceID: "play-route-camera-and-sheet",
            title: "剧本游玩路线镜头与抽屉转场",
            detail: "减弱动态效果开启时替换弹性缩放为静态淡入淡出 · 触感冷却 150ms",
            replacesSpringWithCrossfadeOnReduceMotion: true,
            hapticCooldownMilliseconds: 150,
            throttlesShadersInLowPowerMode: true
        ),
        MotionHapticSurfaceRow(
            surfaceID: "roam-stamp-and-badge-unlock",
            title: "漫游盖章与徽章点亮反馈",
            detail: "连续盖章触感限流 >= 120ms · 低电量模式降级粒子与高刷特效",
            replacesSpringWithCrossfadeOnReduceMotion: true,
            hapticCooldownMilliseconds: 160,
            throttlesShadersInLowPowerMode: true
        ),
        MotionHapticSurfaceRow(
            surfaceID: "object-card-pile-gather",
            title: "物卡收拢与散开切换",
            detail: "减弱动态效果下禁用物理抛洒位移动画 · 低电量模式静态阴影",
            replacesSpringWithCrossfadeOnReduceMotion: true,
            hapticCooldownMilliseconds: 120,
            throttlesShadersInLowPowerMode: true
        )
    ]

    public static let defaultReady = MotionHapticComplianceSnapshot()

    public let rows: [MotionHapticSurfaceRow]
    public let reduceMotionCrossfadeEnforced: Bool
    public let minConfiguredHapticCooldownMs: Int
    public let lowPowerModeShaderThrottlingEnabled: Bool

    public init(
        rows: [MotionHapticSurfaceRow] = Self.defaultRows,
        reduceMotionCrossfadeEnforced: Bool = true,
        minConfiguredHapticCooldownMs: Int = 120,
        lowPowerModeShaderThrottlingEnabled: Bool = true
    ) {
        self.rows = rows
        self.reduceMotionCrossfadeEnforced = reduceMotionCrossfadeEnforced
        self.minConfiguredHapticCooldownMs = minConfiguredHapticCooldownMs
        self.lowPowerModeShaderThrottlingEnabled = lowPowerModeShaderThrottlingEnabled
    }

    public var hasReduceMotionViolation: Bool {
        !reduceMotionCrossfadeEnforced || rows.contains { !$0.replacesSpringWithCrossfadeOnReduceMotion }
    }

    public var hasHapticCooldownViolation: Bool {
        minConfiguredHapticCooldownMs < MotionHapticSurfaceRow.minimumHapticCooldownMilliseconds
            || rows.contains { $0.hapticCooldownMilliseconds < MotionHapticSurfaceRow.minimumHapticCooldownMilliseconds }
    }

    public var isReady: Bool {
        !rows.isEmpty
            && !hasReduceMotionViolation
            && !hasHapticCooldownViolation
            && lowPowerModeShaderThrottlingEnabled
            && rows.allSatisfy(\.isCompliant)
    }
}

/// SwiftUI section displaying `I10` `accessibilityReduceMotion` crossfade replacement,
/// `>= 120ms` haptic cooldown, and Low Power Mode shader throttling using `Text(verbatim:)`
/// throughout (0 new `.xcstrings` keys).
@MainActor public struct HapticFeedbackAndMotionReduceSectionView: View {
    public let snapshot: MotionHapticComplianceSnapshot

    public init(snapshot: MotionHapticComplianceSnapshot = .defaultReady) {
        self.snapshot = snapshot
    }

    public var statusHeadline: String {
        if snapshot.hasReduceMotionViolation {
            return "减弱动态效果告警：存在未替换为静态淡入淡出 (Crossfade) 的位移动画"
        }
        if snapshot.hasHapticCooldownViolation {
            return "触感反馈限流告警：触感冷却间隔低于 120ms 下限"
        }
        if !snapshot.lowPowerModeShaderThrottlingEnabled || !snapshot.isReady {
            return "低电量模式特效降级未开启或触感/动效子系统存在未达标项"
        }
        return "I10 减弱动态效果 Crossfade 替换 · >=120ms 触感限流 · 低电量特效降级全部就绪"
    }

    public var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: statusHeadline)
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("hapticMotionCompliance.statusHeadline")
                Text(verbatim: "Crossfade 降级：\(snapshot.reduceMotionCrossfadeEnforced ? "已强制" : "未强制") · 最小触感冷却：\(snapshot.minConfiguredHapticCooldownMs)ms · 低电量节流：\(snapshot.lowPowerModeShaderThrottlingEnabled ? "已启用" : "未启用")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("hapticMotionCompliance.summary")
            }

            ForEach(snapshot.rows) { row in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: row.isCompliant ? "hand.tap.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(row.isCompliant ? .green : .red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: row.title)
                            .font(.footnote.weight(.medium))
                        Text(verbatim: "\(row.detail)（冷却 \(row.hapticCooldownMilliseconds)ms）")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(verbatim: row.isCompliant ? "合规" : "告警")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(row.isCompliant ? .green : .red)
                }
                .accessibilityIdentifier("hapticMotionCompliance.row." + row.surfaceID)
            }
        } header: {
            Text(verbatim: "I10 触感限流与减弱动态效果门控")
        }
        .accessibilityIdentifier("hapticMotionCompliance.section")
    }
}

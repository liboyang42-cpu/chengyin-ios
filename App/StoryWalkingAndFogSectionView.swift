import SwiftUI

/// Reform plan v9 §23 (W15.1, W15.2, W15.6) & §12.5 / §22 (W14.6, MV25–MV28).
/// Renders `StoryWalkingNavigationHostBridge` stop/arrival-verification/entrance state and
/// `PersonalFogRoamOverlayProjection` confirmed vs predicted cell counts with `Text(verbatim:)` throughout.
@MainActor
public struct StoryWalkingAndFogSectionView: View {
    public let bridge: StoryWalkingNavigationHostBridge
    public let fogProjection: PersonalFogRoamOverlayProjection

    public init(
        bridge: StoryWalkingNavigationHostBridge,
        fogProjection: PersonalFogRoamOverlayProjection
    ) {
        self.bridge = bridge
        self.fogProjection = fogProjection
    }

    public init(
        bridge: StoryWalkingNavigationHostBridge,
        fogCoordinator: PersonalFogRoamHostCoordinator
    ) {
        self.bridge = bridge
        self.fogProjection = fogCoordinator.overlayProjection
    }

    public var body: some View {
        Section {
            LabeledContent {
                Text(verbatim: currentStopSummary)
                    .font(.subheadline.monospacedDigit())
            } label: {
                Text(verbatim: "当前导航站点 (W15.1)")
            }
            .accessibilityIdentifier("story.walking.currentStop")

            LabeledContent {
                Text(verbatim: verificationStatusSummary)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(verificationAccentColor)
            } label: {
                Text(verbatim: "到达核验状态 (W15.6)")
            }
            .accessibilityIdentifier("story.walking.verificationStatus")

            LabeledContent {
                Text(verbatim: entranceSummary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } label: {
                Text(verbatim: "可通行入口 (W15.2)")
            }
            .accessibilityIdentifier("story.walking.entrance")

            HStack {
                Text(verbatim: "个人迷雾图层 (W14.6)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(verbatim: fogSyncBadgeText)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
                    .accessibilityIdentifier("story.fog.syncBadge")
            }

            LabeledContent {
                Text(verbatim: "\(fogProjection.confirmedTileCodes.count) 格已确认 / \(fogProjection.pendingPredictedTileCodes.count) 格本地预测")
                    .font(.footnote.monospacedDigit())
            } label: {
                Text(verbatim: "迷雾格统计")
            }
            .accessibilityIdentifier("story.fog.cellCounts")

            if !fogProjection.rolledBackTileCodes.isEmpty {
                Text(verbatim: "已回退未通过格：\(fogProjection.rolledBackTileCodes.count) 格")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("story.fog.rolledBackCount")
            }
        } header: {
            Text(verbatim: "剧情步行与个人迷雾协同")
        }
        .accessibilityIdentifier("story.walkingAndFog.section")
    }

    private var currentStopSummary: String {
        if let stop = bridge.activeWalkingStop {
            return "任务 #\(bridge.missionID) · 站点 #\(stop.id)"
        }
        switch bridge.phase {
        case .awaitingAuthority:
            return "等待服务端路线权威状态"
        case .navigating(let stop):
            return "任务 #\(bridge.missionID) · 站点 #\(stop.id)"
        case .verificationAvailable(let stop):
            return "已到达站点 #\(stop.id)（步行引导已结束）"
        case .verificationSubmitted(let stop):
            return "站点 #\(stop.id) 核验待权威确认"
        case .noNavigableStop:
            return "当前无可导航站点"
        case .finished:
            return "任务 #\(bridge.missionID) 已完成"
        }
    }

    private var verificationStatusSummary: String {
        switch bridge.phase {
        case .verificationAvailable(let stop):
            return "站点 #\(stop.id) 已开放核验入口（不自动过站）"
        case .verificationSubmitted(let stop):
            return "站点 #\(stop.id) 已提交核验，等待权威回读"
        case .navigating:
            return "步行前往中，到达后开放核验"
        case .finished:
            return "全部站点已核验完成"
        case .awaitingAuthority, .noNavigableStop:
            return "未进入核验阶段"
        }
    }

    private var verificationAccentColor: Color {
        switch bridge.phase {
        case .verificationAvailable:
            return .orange
        case .verificationSubmitted:
            return .blue
        case .finished:
            return .green
        case .awaitingAuthority, .navigating, .noNavigableStop:
            return .secondary
        }
    }

    private var entranceSummary: String {
        guard let entrance = bridge.activeEntrance else {
            return "无已审核结构化入口"
        }
        if let floor = entrance.floor, !floor.isEmpty {
            return "\(entrance.label) · \(floor)"
        }
        return entrance.label
    }

    private var fogSyncBadgeText: String {
        fogProjection.revealSyncEnabled ? "云端同步已开启" : "云端写入关闭 (revealSyncEnabled=false)"
    }
}

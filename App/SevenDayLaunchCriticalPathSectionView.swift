import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#elseif canImport(Core)
import Core
#endif

public struct LaunchDayMilestoneRow: Sendable, Equatable, Identifiable {
    public enum MilestoneStatus: String, Sendable, Equatable {
        case codeComplete = "CODE_COMPLETE"
        case awaitingExternalOps = "AWAITING_EXTERNAL_OPS"
        case blocked = "BLOCKED"
    }

    public let id: String
    public let dayLabel: String
    public let title: String
    public let deliverableSummary: String
    public let status: MilestoneStatus

    public var statusBadgeText: String {
        switch status {
        case .codeComplete:
            return "代码已完备"
        case .awaitingExternalOps:
            return "待外部联调"
        case .blocked:
            return "存在阻塞"
        }
    }

    public init(
        id: String,
        dayLabel: String,
        title: String,
        deliverableSummary: String,
        status: MilestoneStatus
    ) {
        self.id = id
        self.dayLabel = dayLabel
        self.title = title
        self.deliverableSummary = deliverableSummary
        self.status = status
    }
}

public struct SevenDayLaunchPlanSnapshot: Sendable, Equatable {
    public let sectionTitle: String
    public let planBadgeText: String
    public let localXcconfigCheckText: String
    public let userInfoRoleContractText: String
    public let testFlightArchiveCheckText: String
    public let hasBlockedMilestone: Bool
    public let bannerSummaryText: String
    public let days: [LaunchDayMilestoneRow]

    public var coversAllSevenDays: Bool {
        days.count == 7 && days.map(\.dayLabel) == [
            "Day 1", "Day 2", "Day 3", "Day 4", "Day 5", "Day 6", "Day 7"
        ]
    }

    public var isLaunchPathReady: Bool {
        coversAllSevenDays &&
            !hasBlockedMilestone &&
            days.allSatisfy { $0.status != .blocked }
    }

    public init(
        sectionTitle: String = "7天上线关键路径与外部运维核验看板",
        planBadgeText: String = "Day 1..Day 7 · RC",
        localXcconfigCheckText: String = "Config/Local.xcconfig 域名与签名配置注入",
        userInfoRoleContractText: String = "/api/userInfo 角色权限与 Realm 隔离校验",
        testFlightArchiveCheckText: String = "TestFlight Archive 符号表与隐私清单核验",
        hasBlockedMilestone: Bool = false,
        bannerSummaryText: String = "7天上线关键路径代码侧 100% 完备 · 仅剩外部运维开关与真机签名归档",
        days: [LaunchDayMilestoneRow] = [
            .init(
                id: "day-1",
                dayLabel: "Day 1",
                title: "环境配置与生产 HTTPS 门禁冻结",
                deliverableSummary: "注入 Config/Local.xcconfig，阻断 47.103.124.64 与非 HTTPS 路由",
                status: .codeComplete
            ),
            .init(
                id: "day-2",
                dayLabel: "Day 2",
                title: "认证会话、/api/userInfo 角色与 403/401 分离",
                deliverableSummary: "完成 SMS 验证码节流、圈子 403 保持会话与多 Realm 隔离",
                status: .codeComplete
            ),
            .init(
                id: "day-3",
                dayLabel: "Day 3",
                title: "地图视觉 MV01..MV41 与个人迷雾默认关闭",
                deliverableSummary: "6层确定性渲染、GCJ-02/WGS-84 坐标系隔离、revealSyncEnabled 默认关闭",
                status: .codeComplete
            ),
            .init(
                id: "day-4",
                dayLabel: "Day 4",
                title: "漫游打卡、支线照片举证与同行握手安全校验",
                deliverableSummary: "照片待审防自动完成、二维码单次 Nonce 与 TTL <= 300s 校验",
                status: .codeComplete
            ),
            .init(
                id: "day-5",
                dayLabel: "Day 5",
                title: "商户装修入驻四步向导与主题发布审核闭环",
                deliverableSummary: "decor/save JSON、shop/apply 四步向导、结局布尔 fallback 与 UGC 1.2",
                status: .codeComplete
            ),
            .init(
                id: "day-6",
                dayLabel: "Day 6",
                title: "回城恢复 H-W19、城市看板增量 H-W20 与无障碍巡检",
                deliverableSummary: "拒绝 ALL_GAMES 通配符、隐藏私宅坐标、ReduceMotion 与触觉节流",
                status: .codeComplete
            ),
            .init(
                id: "day-7",
                dayLabel: "Day 7",
                title: "TestFlight 归档提审与真机全链路回归",
                deliverableSummary: "执行生产构建归档、上传 App Store Connect 并完成提审前冒烟",
                status: .awaitingExternalOps
            )
        ]
    ) {
        self.sectionTitle = sectionTitle
        self.planBadgeText = planBadgeText
        self.localXcconfigCheckText = localXcconfigCheckText
        self.userInfoRoleContractText = userInfoRoleContractText
        self.testFlightArchiveCheckText = testFlightArchiveCheckText
        self.hasBlockedMilestone = hasBlockedMilestone
        self.bannerSummaryText = bannerSummaryText
        self.days = days
    }

    public static let defaultReady = SevenDayLaunchPlanSnapshot()
}

@MainActor
public struct SevenDayLaunchCriticalPathSectionView: View {
    public let snapshot: SevenDayLaunchPlanSnapshot

    public init(snapshot: SevenDayLaunchPlanSnapshot = .defaultReady) {
        self.snapshot = snapshot
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerView
            statusBannerView
            externalOpsChecklistCardView
            dayMilestonesSectionView
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sevenDayLaunchPlan.root")
    }

    private var headerView: some View {
        HStack(spacing: 8) {
            Text(verbatim: snapshot.sectionTitle)
                .font(.headline)
                .accessibilityIdentifier("sevenDayLaunchPlan.title")
            Spacer()
            Text(verbatim: snapshot.planBadgeText)
                .font(.caption.monospaced())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                .accessibilityIdentifier("sevenDayLaunchPlan.planBadge")
        }
    }

    private var statusBannerView: some View {
        HStack(spacing: 8) {
            Text(verbatim: snapshot.hasBlockedMilestone ? "LAUNCH_PATH_BLOCKED" : "LAUNCH_PATH_READY")
                .font(.caption2.monospaced().weight(.bold))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    Capsule().fill(
                        snapshot.hasBlockedMilestone
                            ? Color.red.opacity(0.22)
                            : Color.green.opacity(0.2)
                    )
                )
                .accessibilityIdentifier("sevenDayLaunchPlan.bannerState")

            Text(verbatim: snapshot.bannerSummaryText)
                .font(.caption)
                .accessibilityIdentifier("sevenDayLaunchPlan.bannerSummary")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sevenDayLaunchPlan.bannerSection")
    }

    private var externalOpsChecklistCardView: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(verbatim: "外部运维与环境核验项")
                .font(.caption.weight(.semibold))
                .accessibilityIdentifier("sevenDayLaunchPlan.opsHeader")

            Text(verbatim: "• \(snapshot.localXcconfigCheckText)")
                .font(.caption2.monospaced())
                .accessibilityIdentifier("sevenDayLaunchPlan.opsLocalXcconfig")

            Text(verbatim: "• \(snapshot.userInfoRoleContractText)")
                .font(.caption2.monospaced())
                .accessibilityIdentifier("sevenDayLaunchPlan.opsUserInfoRole")

            Text(verbatim: "• \(snapshot.testFlightArchiveCheckText)")
                .font(.caption2.monospaced())
                .accessibilityIdentifier("sevenDayLaunchPlan.opsTestFlightArchive")
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sevenDayLaunchPlan.opsChecklistCard")
    }

    private var dayMilestonesSectionView: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: "7天里程碑排期 (\(snapshot.days.count) 天)")
                .font(.subheadline.weight(.semibold))
                .accessibilityIdentifier("sevenDayLaunchPlan.daysHeader")

            ForEach(snapshot.days) { milestone in
                HStack(alignment: .top, spacing: 8) {
                    Text(verbatim: milestone.dayLabel)
                        .font(.caption.monospaced().weight(.bold))
                        .frame(width: 48, alignment: .leading)
                        .accessibilityIdentifier("sevenDayLaunchPlan.day.\(milestone.id).label")

                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: milestone.title)
                            .font(.caption.weight(.semibold))
                            .accessibilityIdentifier("sevenDayLaunchPlan.day.\(milestone.id).title")
                        Text(verbatim: milestone.deliverableSummary)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("sevenDayLaunchPlan.day.\(milestone.id).summary")
                    }

                    Spacer()

                    Text(verbatim: milestone.statusBadgeText)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor.opacity(0.14)))
                        .accessibilityIdentifier("sevenDayLaunchPlan.day.\(milestone.id).status")
                }
                .padding(.vertical, 3)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("sevenDayLaunchPlan.day.\(milestone.id)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sevenDayLaunchPlan.daysSection")
    }
}

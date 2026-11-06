import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#endif

/// Single governance pillar row for club, team, and co-op parity & reform verification.
public struct ClubCoopGovernancePillarRow: Identifiable, Equatable, Sendable {
    public enum Pillar: String, CaseIterable, Equatable, Sendable {
        case teamAndClubTabs = "w2-12"
        case clubOpsAndGovernance = "w2-14..16"
        case coopScheduleAndLeadPolling = "I09"
        case teamFirstMeetingAndMultiInvite = "H-W16/U02-U07"
    }

    public enum Status: String, Equatable, Sendable {
        case parityVerified
        case contractAndOfflineUIReady
        case actionRequired
    }

    public let id: String
    public let pillar: Pillar
    public let referenceBadge: String
    public let titleText: String
    public let summaryText: String
    public let invariants: [String]
    public let status: Status

    public init(
        id: String,
        pillar: Pillar,
        referenceBadge: String,
        titleText: String,
        summaryText: String,
        invariants: [String],
        status: Status
    ) {
        self.id = id
        self.pillar = pillar
        self.referenceBadge = referenceBadge
        self.titleText = titleText
        self.summaryText = summaryText
        self.invariants = invariants
        self.status = status
    }

    public var isHealthy: Bool {
        status == .parityVerified || status == .contractAndOfflineUIReady
    }

    public var statusBadgeText: String {
        switch status {
        case .parityVerified:
            return "已对齐"
        case .contractAndOfflineUIReady:
            return "契约与离线视图就绪"
        case .actionRequired:
            return "需处理"
        }
    }
}

/// Self-contained snapshot of the 4 club, team & co-op governance pillars:
/// - `w2-12` team/club tabs
/// - `w2-14..16` club ops & governance
/// - `I09` schedule & lead progress polling
/// - `H-W16/U02–U07` QR-only handshake, multi-invite, revocation & Beijing governing time
public struct ClubAndTeamCoopGovernanceSnapshot: Equatable, Sendable {
    public let rows: [ClubCoopGovernancePillarRow]

    public init(rows: [ClubCoopGovernancePillarRow] = Self.defaultPillars()) {
        self.rows = rows
    }

    public var allPillarsHealthy: Bool {
        !rows.isEmpty && rows.allSatisfy(\.isHealthy)
    }

    public var healthyCount: Int {
        rows.filter(\.isHealthy).count
    }

    public var headlineSummaryText: String {
        allPillarsHealthy
            ? "社团、组队与共创治理 4 大支柱均已就绪（\(healthyCount)/\(rows.count)）"
            : "存在待处理的社团/组队治理项（已就绪 \(healthyCount)/\(rows.count)）"
    }

    public func row(for pillar: ClubCoopGovernancePillarRow.Pillar) -> ClubCoopGovernancePillarRow? {
        rows.first { $0.pillar == pillar }
    }

    public static func defaultPillars(
        teamAndClubTabsVerified: Bool = true,
        clubOpsGovernanceVerified: Bool = true,
        coopSchedulePollingVerified: Bool = true,
        teamMeetingAndInviteReady: Bool = true
    ) -> [ClubCoopGovernancePillarRow] {
        [
            ClubCoopGovernancePillarRow(
                id: "w2-12-team-club-tabs",
                pillar: .teamAndClubTabs,
                referenceBadge: "w2-12",
                titleText: "组队大厅与社团分栏导航",
                summaryText: "组队详情、邀请码加入与我的队伍列表按服务端确认状态渲染，站内消息入口与未读角标保持门控对齐。",
                invariants: [
                    "队伍列表与详情回读一致",
                    "邀请码加入显式确认",
                    "社团分栏工具栏消息入口对齐"
                ],
                status: teamAndClubTabsVerified ? .parityVerified : .actionRequired
            ),
            ClubCoopGovernancePillarRow(
                id: "w2-14-16-club-ops-governance",
                pillar: .clubOpsAndGovernance,
                referenceBadge: "w2-14..16",
                titleText: "社团运营、活动管理与成员治理",
                summaryText: "社团资料、成员角色审批与活动发布均受角色权限与业务路由白名单约束，任何未知结果均通过服务端回读消解。",
                invariants: [
                    "跨社团/非管理员写操作本地拒绝",
                    "危险操作显式复核确认",
                    "未决提交强制回读核实"
                ],
                status: clubOpsGovernanceVerified ? .parityVerified : .actionRequired
            ),
            ClubCoopGovernancePillarRow(
                id: "i09-coop-schedule-lead-polling",
                pillar: .coopScheduleAndLeadPolling,
                referenceBadge: "I09",
                titleText: "共创排期与线索进度轮询门控",
                summaryText: "共创合作排期、收益台账只读展示与线索进度轮询遵循前台可见性与会话世代隔离。",
                invariants: [
                    "会话切换立即终止旧轮询",
                    "线索状态仅采信服务端权威进度",
                    "排期变更需显式复核"
                ],
                status: coopSchedulePollingVerified ? .parityVerified : .actionRequired
            ),
            ClubCoopGovernancePillarRow(
                id: "h-w16-u02-u07-meeting-invite",
                pillar: .teamFirstMeetingAndMultiInvite,
                referenceBadge: "H-W16 · U02–U07",
                titleText: "确认成团当面二维码核验、多选邀请与北京时间截止",
                summaryText: "仅已确认队伍开放见面步（无兴趣匹配），实名仅限陌生人见面步，仅提供动态二维码（NFC 禁用），好友多选仅重试失败项，撤回终态优先，截止时间双时区展示并以北京时间为准。",
                invariants: [
                    "CONFIRMED 队伍准入且仅动态二维码核验 (NFC 永不开启)",
                    "好友多选复核失效保护与未明状态先回读",
                    "撤回优先 (Revoke-Wins) 与北京时间 (Asia/Shanghai) 双时区基准"
                ],
                status: teamMeetingAndInviteReady ? .contractAndOfflineUIReady : .actionRequired
            )
        ]
    }
}

/// Offline SwiftUI section rendering `ClubAndTeamCoopGovernanceSnapshot` using `Text(verbatim:)`
/// throughout (0 new `.xcstrings` keys) and deterministic `clubTeamGovernance.*` accessibility hooks.
@MainActor
public struct ClubAndTeamCoopGovernanceSectionView: View {
    public let snapshot: ClubAndTeamCoopGovernanceSnapshot
    public var onSelectPillar: ((ClubCoopGovernancePillarRow) -> Void)?

    public init(
        snapshot: ClubAndTeamCoopGovernanceSnapshot = ClubAndTeamCoopGovernanceSnapshot(),
        onSelectPillar: ((ClubCoopGovernancePillarRow) -> Void)? = nil
    ) {
        self.snapshot = snapshot
        self.onSelectPillar = onSelectPillar
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: "社团、组队与共创治理全景状态")
                        .font(.headline)
                        .accessibilityIdentifier("clubTeamGovernance.header.title")
                    Text(verbatim: snapshot.headlineSummaryText)
                        .font(.subheadline)
                        .foregroundStyle(snapshot.allPillarsHealthy ? .green : .orange)
                        .accessibilityIdentifier("clubTeamGovernance.header.summary")
                }
                Spacer()
                Text(verbatim: snapshot.allPillarsHealthy ? "治理就绪" : "需关注")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(
                            snapshot.allPillarsHealthy
                                ? Color.green.opacity(0.15)
                                : Color.orange.opacity(0.15)
                        )
                    )
                    .accessibilityIdentifier("clubTeamGovernance.header.badge")
            }

            ForEach(snapshot.rows) { row in
                pillarRowView(row)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.08)))
        .accessibilityIdentifier("clubTeamGovernance.section")
    }

    @ViewBuilder
    private func pillarRowView(_ row: ClubCoopGovernancePillarRow) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: row.titleText)
                    .font(.subheadline.weight(.medium))
                    .accessibilityIdentifier("clubTeamGovernance.row.\(row.id).title")
                Spacer()
                Text(verbatim: row.referenceBadge)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("clubTeamGovernance.row.\(row.id).ref")
                Text(verbatim: row.statusBadgeText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(row.isHealthy ? .green : .red)
                    .accessibilityIdentifier("clubTeamGovernance.row.\(row.id).status")
            }

            Text(verbatim: row.summaryText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("clubTeamGovernance.row.\(row.id).summary")

            VStack(alignment: .leading, spacing: 2) {
                ForEach(row.invariants, id: \.self) { invariant in
                    Text(verbatim: "• \(invariant)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .accessibilityIdentifier("clubTeamGovernance.row.\(row.id).invariants")

            if let onSelectPillar {
                Button(action: { onSelectPillar(row) }) {
                    Text(verbatim: "查看治理支柱详情")
                        .font(.caption)
                }
                .accessibilityIdentifier("clubTeamGovernance.row.\(row.id).action")
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.06)))
        .accessibilityIdentifier("clubTeamGovernance.row.\(row.id)")
    }
}

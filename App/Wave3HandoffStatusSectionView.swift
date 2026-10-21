import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#endif

public struct Wave3HandoffLaneRow: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let mergedPR: String
    public let statusSummary: String
    public let isMerged: Bool

    public init(
        id: String,
        title: String,
        mergedPR: String,
        statusSummary: String,
        isMerged: Bool = true
    ) {
        self.id = id
        self.title = title
        self.mergedPR = mergedPR
        self.statusSummary = statusSummary
        self.isMerged = isMerged
    }
}

public struct Wave3HandoffGateRow: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let stateBadge: String
    public let detail: String
    public let isEnabled: Bool

    public init(
        id: String,
        title: String,
        stateBadge: String,
        detail: String,
        isEnabled: Bool = false
    ) {
        self.id = id
        self.title = title
        self.stateBadge = stateBadge
        self.detail = detail
        self.isEnabled = isEnabled
    }
}

/// Self-contained SwiftUI section rendering all 13 Wave-3 handoff lanes (`I00`..`I11` + `BK`),
/// merged PR references (`#35`..`#55`), and backend prerequisite gates (`IOS-I00-1`, `AI-DELETE` OFF, `TopicLike` OFF).
/// Uses `Text(verbatim:)` throughout so zero new `.xcstrings` catalog keys are required.
@MainActor
public struct Wave3HandoffStatusSectionView: View {
    public static let defaultLaneRows: [Wave3HandoffLaneRow] = [
        Wave3HandoffLaneRow(id: "I00", title: "基础环境与契约门禁基线", mergedPR: "#35", statusSummary: "已合入基线 (需后端 IOS-I00-1 配合)"),
        Wave3HandoffLaneRow(id: "I01", title: "入口与隐私合规对齐", mergedPR: "#36", statusSummary: "已合入主干"),
        Wave3HandoffLaneRow(id: "I02", title: "首页与发现流卡片投影", mergedPR: "#38", statusSummary: "已合入主干"),
        Wave3HandoffLaneRow(id: "I03", title: "漫游探索与点位迷雾账本", mergedPR: "#40", statusSummary: "已合入主干"),
        Wave3HandoffLaneRow(id: "I04", title: "步行导航与剧本题序校验", mergedPR: "#42", statusSummary: "已合入主干"),
        Wave3HandoffLaneRow(id: "I05", title: "组局报名与票夹核销状态", mergedPR: "#44", statusSummary: "已合入主干"),
        Wave3HandoffLaneRow(id: "I06", title: "主题详情与话题点赞门控", mergedPR: "#46", statusSummary: "已合入主干 (TopicLike 默认关闭)"),
        Wave3HandoffLaneRow(id: "I07", title: "商户工作台与员工权限矩阵", mergedPR: "#48", statusSummary: "已合入主干"),
        Wave3HandoffLaneRow(id: "I08", title: "商户 AI 创编与双域审批", mergedPR: "#50", statusSummary: "已合入主干"),
        Wave3HandoffLaneRow(id: "I09", title: "订单行级履约与售后状态", mergedPR: "#51", statusSummary: "已合入主干"),
        Wave3HandoffLaneRow(id: "I10", title: "赞助奖池与非现金奖励披露", mergedPR: "#52", statusSummary: "已合入主干"),
        Wave3HandoffLaneRow(id: "I11", title: "场景 AI 隔离与记忆删除门控", mergedPR: "#54", statusSummary: "已合入主干 (AI-DELETE 默认关闭)"),
        Wave3HandoffLaneRow(id: "BK", title: "跨泳道账本与契约回归套件", mergedPR: "#55", statusSummary: "已合入主干")
    ]

    public static let defaultPrerequisiteGates: [Wave3HandoffGateRow] = [
        Wave3HandoffGateRow(
            id: "IOS-I00-1",
            title: "后端契约前置项 IOS-I00-1",
            stateBadge: "PENDING",
            detail: "待后端评审并放行白名单路由后方可挂载线上请求",
            isEnabled: false
        ),
        Wave3HandoffGateRow(
            id: "AI-DELETE",
            title: "NPC 记忆清除写门控 (AI-DELETE)",
            stateBadge: "OFF",
            detail: "客户端删除请求默认关闭，仅保留本地重读围栏契约",
            isEnabled: false
        ),
        Wave3HandoffGateRow(
            id: "TopicLike",
            title: "话题点赞写操作门控 (TopicLike)",
            stateBadge: "OFF",
            detail: "点赞写接口尚未纳入已审白名单，保持只读展示",
            isEnabled: false
        )
    ]

    public let laneRows: [Wave3HandoffLaneRow]
    public let prerequisiteGates: [Wave3HandoffGateRow]

    public init(
        laneRows: [Wave3HandoffLaneRow] = Wave3HandoffStatusSectionView.defaultLaneRows,
        prerequisiteGates: [Wave3HandoffGateRow] = Wave3HandoffStatusSectionView.defaultPrerequisiteGates
    ) {
        self.laneRows = laneRows
        self.prerequisiteGates = prerequisiteGates
    }

    public var mergedCount: Int {
        laneRows.filter(\.isMerged).count
    }

    public var prRangeSummary: String {
        guard let first = laneRows.first?.mergedPR, let last = laneRows.last?.mergedPR else {
            return "无 PR 记录"
        }
        return "\(first)..\(last)"
    }

    public var body: some View {
        Group {
            Section {
                HStack {
                    Text(verbatim: "Wave 3 移交泳道总数")
                    Spacer()
                    Text(verbatim: "\(mergedCount)/\(laneRows.count) 已合入 (\(prRangeSummary))")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("wave3Handoff.summary")

                ForEach(laneRows) { row in
                    HStack(alignment: .top, spacing: 10) {
                        Text(verbatim: row.id)
                            .font(.caption.monospaced().weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.blue.opacity(0.14)))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: row.title)
                                .font(.subheadline.weight(.medium))
                            Text(verbatim: row.statusSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(verbatim: row.mergedPR)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityIdentifier("wave3Handoff.lane.\(row.id)")
                }
            } header: {
                Text(verbatim: "Wave 3 移交泳道状态 (I00..I11 + BK)")
            }
            .accessibilityIdentifier("wave3Handoff.lanes.section")

            Section {
                ForEach(prerequisiteGates) { gate in
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: gate.title)
                                .font(.subheadline.weight(.medium))
                            Text(verbatim: gate.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Text(verbatim: gate.stateBadge)
                            .font(.caption2.monospaced().weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                Capsule().fill(gate.isEnabled ? Color.green.opacity(0.18) : Color.orange.opacity(0.18))
                            )
                    }
                    .accessibilityIdentifier("wave3Handoff.gate.\(gate.id)")
                }
            } header: {
                Text(verbatim: "后端前置项与默认关闭门控")
            }
            .accessibilityIdentifier("wave3Handoff.gates.section")
        }
    }
}

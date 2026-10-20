import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#elseif canImport(Core)
import Core
#endif

/// Self-contained row for Wave-3 `I02` `GameJournalComposition` (`userStamps` + `completedTasks`
/// composition and `I00` standalone `loadUserStamps()` non-regression).
public struct GameJournalSliceRow: Sendable, Equatable, Identifiable {
    public enum SliceKind: String, Sendable, Equatable {
        case userStamps = "userStamps"
        case completedTasks = "completedTasks"
        case standaloneStampNonRegression = "standaloneStampNonRegression"
    }

    public enum Status: String, Sendable, Equatable {
        case ready
        case partialDegraded
        case failed
    }

    public let id: String
    public let kind: SliceKind
    public let title: String
    public let sourceContract: String
    public let itemCount: Int
    public let status: Status
    public let detail: String

    public init(
        id: String,
        kind: SliceKind,
        title: String,
        sourceContract: String,
        itemCount: Int,
        status: Status,
        detail: String
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.sourceContract = sourceContract
        self.itemCount = itemCount
        self.status = status
        self.detail = detail
    }

    public var badgeText: String {
        switch status {
        case .ready:
            return "READY"
        case .partialDegraded:
            return "DEGRADED"
        case .failed:
            return "FAILED"
        }
    }
}

/// Self-contained snapshot for Wave-3 `I02` `GameJournalComposition` and `I00` `loadUserStamps()` non-regression.
public struct GameJournalCompositionSnapshot: Sendable, Equatable {
    public let sessionOwnerScope: String
    public let standaloneLoadUserStampsIntact: Bool
    public let rows: [GameJournalSliceRow]

    public init(
        sessionOwnerScope: String,
        standaloneLoadUserStampsIntact: Bool,
        rows: [GameJournalSliceRow]
    ) {
        self.sessionOwnerScope = sessionOwnerScope
        self.standaloneLoadUserStampsIntact = standaloneLoadUserStampsIntact
        self.rows = rows
    }

    public static let defaultReady = GameJournalCompositionSnapshot(
        sessionOwnerScope: "member-i02-journal",
        standaloneLoadUserStampsIntact: true,
        rows: [
            GameJournalSliceRow(
                id: "user-stamps",
                kind: .userStamps,
                title: "已获印章切片 (userStamps)",
                sourceContract: "GameJournalComposition.userStamps · I02",
                itemCount: 6,
                status: .ready,
                detail: "按会话作用域聚合印章摘要，支持部分字段缺失时单切片降级展示"
            ),
            GameJournalSliceRow(
                id: "completed-tasks",
                kind: .completedTasks,
                title: "已完成任务切片 (completedTasks)",
                sourceContract: "GameJournalComposition.completedTasks · I02",
                itemCount: 4,
                status: .ready,
                detail: "按权威完赛记录聚合任务摘要，不伪造未确认奖励或时长"
            ),
            GameJournalSliceRow(
                id: "i00-standalone-stamps",
                kind: .standaloneStampNonRegression,
                title: "独立印章读取无回归 (loadUserStamps)",
                sourceContract: "loadUserStamps() · I00 Non-Regression",
                itemCount: 6,
                status: .ready,
                detail: "手账组合层保持独立印章列表路由与解码契约零回归"
            )
        ]
    )

    public var totalStampsCount: Int {
        rows.first(where: { $0.kind == .userStamps })?.itemCount ?? 0
    }

    public var totalCompletedTasksCount: Int {
        rows.first(where: { $0.kind == .completedTasks })?.itemCount ?? 0
    }

    public var isFullyReady: Bool {
        standaloneLoadUserStampsIntact && rows.allSatisfy { $0.status == .ready }
    }

    public var summaryText: String {
        "印章 \(totalStampsCount) 枚 · 完成任务 \(totalCompletedTasksCount) 项 · I00 独立读取 \(standaloneLoadUserStampsIntact ? "无回归" : "异常")"
    }
}

/// Renders Wave-3 `I02` `GameJournalComposition` (`userStamps` + `completedTasks` & `I00` standalone
/// `loadUserStamps()` non-regression) using `Text(verbatim:)` throughout.
@MainActor
public struct GameJournalCompositionAndPlaySummarySectionView: View {
    public let snapshot: GameJournalCompositionSnapshot

    public init(snapshot: GameJournalCompositionSnapshot = .defaultReady) {
        self.snapshot = snapshot
    }

    public var body: some View {
        Section {
            HStack {
                Text(verbatim: "手账组合层与游玩摘要 (I02)")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(verbatim: snapshot.isFullyReady ? "组合就绪 (I02_READY)" : "存在降级或异常")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background((snapshot.isFullyReady ? Color.green : Color.orange).opacity(0.15), in: Capsule())
                    .foregroundStyle(snapshot.isFullyReady ? Color.green : Color.orange)
                    .accessibilityIdentifier("gameJournalComposition.overallBadge")
            }

            LabeledContent {
                Text(verbatim: snapshot.standaloneLoadUserStampsIntact ? "loadUserStamps() 保持独立无回归" : "loadUserStamps() 回归告警")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(snapshot.standaloneLoadUserStampsIntact ? .green : .red)
            } label: {
                Text(verbatim: "I00 独立印章通道")
            }
            .accessibilityIdentifier("gameJournalComposition.standaloneNonRegression")

            LabeledContent {
                Text(verbatim: snapshot.summaryText)
                    .font(.footnote.monospacedDigit())
            } label: {
                Text(verbatim: "组合摘要统计")
            }
            .accessibilityIdentifier("gameJournalComposition.summary")

            ForEach(snapshot.rows) { row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(verbatim: row.title)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(verbatim: "\(row.itemCount) 项 · \(row.badgeText)")
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(badgeColor(for: row.status).opacity(0.15), in: Capsule())
                            .foregroundStyle(badgeColor(for: row.status))
                    }
                    Text(verbatim: row.sourceContract)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Text(verbatim: row.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("gameJournalComposition.row.\(row.id)")
            }
        } header: {
            Text(verbatim: "游戏手账组合与完赛摘要 (I02 / I00)")
        }
        .accessibilityIdentifier("gameJournalComposition.section")
    }

    private func badgeColor(for status: GameJournalSliceRow.Status) -> Color {
        switch status {
        case .ready:
            return .green
        case .partialDegraded:
            return .orange
        case .failed:
            return .red
        }
    }
}

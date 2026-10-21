import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#elseif canImport(Core)
import Core
#endif

/// Self-contained group row for the 99-Page Decision Ledger (`1:1 Mini-Program Parity`
/// vs `iOS Native Superset Preserved`).
public struct MiniProgram99GroupDecisionRow: Sendable, Equatable, Identifiable {
    public let groupID: String
    public let title: String
    public let strictOneToOnePageCount: Int
    public let nativeSupersetPageCount: Int
    public let undecidedPageCount: Int

    public var id: String { groupID }

    public var totalPageCount: Int {
        strictOneToOnePageCount + nativeSupersetPageCount + undecidedPageCount
    }

    public var isCompliant: Bool {
        !groupID.isEmpty
            && !title.isEmpty
            && strictOneToOnePageCount >= 0
            && nativeSupersetPageCount >= 0
            && undecidedPageCount == 0
            && totalPageCount > 0
    }

    public init(
        groupID: String,
        title: String,
        strictOneToOnePageCount: Int,
        nativeSupersetPageCount: Int,
        undecidedPageCount: Int = 0
    ) {
        self.groupID = groupID
        self.title = title
        self.strictOneToOnePageCount = strictOneToOnePageCount
        self.nativeSupersetPageCount = nativeSupersetPageCount
        self.undecidedPageCount = undecidedPageCount
    }
}

/// Self-contained snapshot for the 99-Page Decision Ledger across 5 domain groups.
public struct MiniProgram99DecisionLedgerSnapshot: Sendable, Equatable {
    public static let canonicalTotalPages: Int = 99

    public static let defaultRows: [MiniProgram99GroupDecisionRow] = [
        MiniProgram99GroupDecisionRow(
            groupID: "explore-roam-map",
            title: "探索主页 · 城市漫游 · 迷雾与印章",
            strictOneToOnePageCount: 14,
            nativeSupersetPageCount: 8,
            undecidedPageCount: 0
        ),
        MiniProgram99GroupDecisionRow(
            groupID: "play-script-runtime",
            title: "剧本详情 · 沉浸游玩 · 结算与评价",
            strictOneToOnePageCount: 15,
            nativeSupersetPageCount: 6,
            undecidedPageCount: 0
        ),
        MiniProgram99GroupDecisionRow(
            groupID: "member-profile-growth",
            title: "个人主页 · 成长中心 · 徽章墙与物卡",
            strictOneToOnePageCount: 13,
            nativeSupersetPageCount: 6,
            undecidedPageCount: 0
        ),
        MiniProgram99GroupDecisionRow(
            groupID: "club-topic-im-social",
            title: "俱乐部 · 广场推文 · 私信与社交关系",
            strictOneToOnePageCount: 15,
            nativeSupersetPageCount: 5,
            undecidedPageCount: 0
        ),
        MiniProgram99GroupDecisionRow(
            groupID: "merchant-creator-commerce",
            title: "商户工作台 · 创作者工坊 · 票务与核销",
            strictOneToOnePageCount: 11,
            nativeSupersetPageCount: 6,
            undecidedPageCount: 0
        )
    ]

    public static let defaultReady = MiniProgram99DecisionLedgerSnapshot()

    public let rows: [MiniProgram99GroupDecisionRow]
    public let preservesAllNativeSupersets: Bool

    public init(
        rows: [MiniProgram99GroupDecisionRow] = Self.defaultRows,
        preservesAllNativeSupersets: Bool = true
    ) {
        self.rows = rows
        self.preservesAllNativeSupersets = preservesAllNativeSupersets
    }

    public var totalStrictOneToOnePages: Int {
        rows.map(\.strictOneToOnePageCount).reduce(0, +)
    }

    public var totalNativeSupersetPages: Int {
        rows.map(\.nativeSupersetPageCount).reduce(0, +)
    }

    public var totalUndecidedPages: Int {
        rows.map(\.undecidedPageCount).reduce(0, +)
    }

    public var totalPages: Int {
        rows.map(\.totalPageCount).reduce(0, +)
    }

    public var hasPageCountMismatch: Bool {
        totalPages != Self.canonicalTotalPages || totalUndecidedPages > 0
    }

    public var isReady: Bool {
        rows.count == 5
            && !hasPageCountMismatch
            && preservesAllNativeSupersets
            && rows.allSatisfy(\.isCompliant)
    }
}

/// SwiftUI section displaying the 99-Page Decision Ledger (`1:1 Mini-Program Parity`
/// vs `iOS Native Superset Preserved`) using `Text(verbatim:)` throughout (0 new `.xcstrings` keys).
@MainActor public struct MiniProgramPageByPage99DecisionSectionView: View {
    public let snapshot: MiniProgram99DecisionLedgerSnapshot

    public init(snapshot: MiniProgram99DecisionLedgerSnapshot = .defaultReady) {
        self.snapshot = snapshot
    }

    public var statusHeadline: String {
        if snapshot.hasPageCountMismatch {
            return "页面决策台账告警：当前统计 \(snapshot.totalPages)/\(MiniProgram99DecisionLedgerSnapshot.canonicalTotalPages) 页或存在未裁决页面"
        }
        if !snapshot.preservesAllNativeSupersets || !snapshot.isReady {
            return "原生超集能力保护未开启或 5 大业务域决策台账未完全就绪"
        }
        return "99 页逐页决策台账已锁定：\(snapshot.totalStrictOneToOnePages) 页 1:1 严格对齐 · \(snapshot.totalNativeSupersetPages) 页保留 iOS 原生超集"
    }

    public var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: statusHeadline)
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("mp99DecisionLedger.statusHeadline")
                Text(verbatim: "总页数：\(snapshot.totalPages)/99 · 1:1 对齐：\(snapshot.totalStrictOneToOnePages) · 原生超集：\(snapshot.totalNativeSupersetPages) · 未裁决：\(snapshot.totalUndecidedPages)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("mp99DecisionLedger.summary")
            }

            ForEach(snapshot.rows) { row in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: row.isCompliant ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(row.isCompliant ? .green : .red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: "\(row.title)（共 \(row.totalPageCount) 页）")
                            .font(.footnote.weight(.medium))
                        Text(verbatim: "1:1 小程序对齐 \(row.strictOneToOnePageCount) 页 · iOS 原生超集保留 \(row.nativeSupersetPageCount) 页")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(verbatim: row.isCompliant ? "已锁定" : "待裁决")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(row.isCompliant ? .green : .red)
                }
                .accessibilityIdentifier("mp99DecisionLedger.row." + row.groupID)
            }
        } header: {
            Text(verbatim: "99 页小程序对齐与原生超集决策台账")
        }
        .accessibilityIdentifier("mp99DecisionLedger.section")
    }
}

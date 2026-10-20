import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#endif

/// Presentation row for one of the 5 `w2-09` private exploration tools:
/// `TimeCapsule`, `ExplorationGoals`, `ExplorationExport`, `ExplorationAnniversary`, and `MonthlyRecap`.
public struct ExplorationPrivateToolRow: Sendable, Equatable, Identifiable {
    public enum ToolKind: String, CaseIterable, Sendable, Equatable {
        case timeCapsule = "TimeCapsule"
        case explorationGoals = "ExplorationGoals"
        case explorationExport = "ExplorationExport"
        case explorationAnniversary = "ExplorationAnniversary"
        case monthlyRecap = "MonthlyRecap"

        public var miniProgramSlug: String {
            switch self {
            case .timeCapsule: return "capsule"
            case .explorationGoals: return "exploration-goals"
            case .explorationExport: return "exploration-export"
            case .explorationAnniversary: return "exploration-anniversary"
            case .monthlyRecap: return "monthly-recap"
            }
        }
    }

    public let id: String
    public let kind: ToolKind
    public let title: String
    public let routeSummary: String
    public let isAccountScopedReadReady: Bool
    public let isLiveWriteDormant: Bool

    public var isCompliant: Bool {
        isAccountScopedReadReady && isLiveWriteDormant
    }

    public init(
        kind: ToolKind,
        title: String,
        routeSummary: String,
        isAccountScopedReadReady: Bool = true,
        isLiveWriteDormant: Bool = true
    ) {
        self.id = kind.rawValue
        self.kind = kind
        self.title = title
        self.routeSummary = routeSummary
        self.isAccountScopedReadReady = isAccountScopedReadReady
        self.isLiveWriteDormant = isLiveWriteDormant
    }
}

/// Self-contained snapshot of all 5 `w2-09` private exploration tools and `RoamPrivateTools.xcstrings` catalog status.
public struct ExplorationPrivateToolsSnapshot: Sendable, Equatable {
    public let tools: [ExplorationPrivateToolRow]
    public let catalogTableName: String
    public let isCatalogBilingualComplete: Bool
    public let isAccountFenceActive: Bool

    public var hasAllFiveTools: Bool {
        let presentKinds = Set(tools.map(\.kind))
        return tools.count == 5 && presentKinds == Set(ExplorationPrivateToolRow.ToolKind.allCases)
    }

    public var allCompliant: Bool {
        hasAllFiveTools
            && isCatalogBilingualComplete
            && isAccountFenceActive
            && tools.allSatisfy(\.isCompliant)
    }

    public init(
        tools: [ExplorationPrivateToolRow],
        catalogTableName: String = "RoamPrivateTools.xcstrings",
        isCatalogBilingualComplete: Bool = true,
        isAccountFenceActive: Bool = true
    ) {
        self.tools = tools
        self.catalogTableName = catalogTableName
        self.isCatalogBilingualComplete = isCatalogBilingualComplete
        self.isAccountFenceActive = isAccountFenceActive
    }

    public static let defaultReady = ExplorationPrivateToolsSnapshot(
        tools: [
            ExplorationPrivateToolRow(
                kind: .timeCapsule,
                title: "TimeCapsule · 时间胶囊",
                routeSummary: "subpackageRoam/capsule · 账户隔离只读与写操作静默保护"
            ),
            ExplorationPrivateToolRow(
                kind: .explorationGoals,
                title: "ExplorationGoals · 探索目标",
                routeSummary: "subpackageRoam/exploration-goals · 目标进度读回与离线门禁"
            ),
            ExplorationPrivateToolRow(
                kind: .explorationExport,
                title: "ExplorationExport · 漫游记录导出",
                routeSummary: "subpackageRoam/exploration-export · 导出任务状态只读核对"
            ),
            ExplorationPrivateToolRow(
                kind: .explorationAnniversary,
                title: "ExplorationAnniversary · 探索纪念日",
                routeSummary: "subpackageRoam/exploration-anniversary · 里程碑快照展示"
            ),
            ExplorationPrivateToolRow(
                kind: .monthlyRecap,
                title: "MonthlyRecap · 月度漫游回顾",
                routeSummary: "subpackageRoam/monthly-recap · 月度统计只读汇总"
            )
        ],
        catalogTableName: "RoamPrivateTools.xcstrings",
        isCatalogBilingualComplete: true,
        isAccountFenceActive: true
    )
}

/// SwiftUI section view displaying the 5 `w2-09` private exploration tools and `RoamPrivateTools.xcstrings`
/// table status using `Text(verbatim:)` exclusively (zero new `.xcstrings` keys).
@MainActor
public struct ExplorationPrivateToolsAndCapsuleSectionView: View {
    public let snapshot: ExplorationPrivateToolsSnapshot

    public init(snapshot: ExplorationPrivateToolsSnapshot = .defaultReady) {
        self.snapshot = snapshot
    }

    public var body: some View {
        Section {
            HStack {
                Text(
                    verbatim: snapshot.allCompliant
                        ? "漫游私人工具集：5/5 项已对齐且保持 Fail-Closed"
                        : "漫游私人工具集：存在未闭合工具或词表告警"
                )
                .font(.subheadline.weight(.semibold))
                Spacer()
                Text(verbatim: snapshot.allCompliant ? "READY" : "WARNING")
                    .font(.caption.monospaced())
                    .foregroundStyle(snapshot.allCompliant ? .green : .red)
            }
            .accessibilityIdentifier("explorationPrivateTools.summary")

            ForEach(snapshot.tools) { tool in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(verbatim: tool.title)
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Text(verbatim: tool.isCompliant ? "FAIL-CLOSED" : "NON-COMPLIANT")
                            .font(.caption.monospaced())
                            .foregroundStyle(tool.isCompliant ? .secondary : .red)
                            .accessibilityIdentifier("explorationPrivateTools.tool.\(tool.id).status")
                    }
                    Text(verbatim: tool.routeSummary)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                .accessibilityIdentifier("explorationPrivateTools.tool.\(tool.id)")
            }

            HStack {
                Text(verbatim: "双语词表 (\(snapshot.catalogTableName))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(
                    verbatim: snapshot.isCatalogBilingualComplete
                        ? "en + zh-Hans 完整"
                        : "词表缺失或未翻译"
                )
                .font(.caption.monospaced())
                .foregroundStyle(snapshot.isCatalogBilingualComplete ? .secondary : .red)
            }
            .accessibilityIdentifier("explorationPrivateTools.catalogStatus")

            if !snapshot.allCompliant {
                Text(verbatim: "告警：检测到私人漫游工具缺少账户隔离、未静默远端写操作或双语词表不完整。")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("explorationPrivateTools.warningBanner")
            }
        } header: {
            Text(verbatim: "漫游护照私人工具与时间胶囊 (w2-09)")
        }
        .accessibilityIdentifier("explorationPrivateTools.section")
    }
}

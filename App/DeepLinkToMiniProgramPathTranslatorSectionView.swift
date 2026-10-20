import SwiftUI
import QuestifyCore

/// Self-contained route mapping row for bidirectional Mini-Program path <-> Native Universal Link translation.
public struct MiniProgramRouteMappingRow: Sendable, Equatable, Identifiable {
    public let routeID: String
    public let miniProgramPath: String
    public let universalLinkPath: String
    public let preservesQueryParametersLosslessly: Bool
    public let supportsBidirectionalRoundtrip: Bool

    public var id: String { routeID }

    public var isCompliant: Bool {
        !routeID.isEmpty
            && !miniProgramPath.isEmpty
            && !universalLinkPath.isEmpty
            && preservesQueryParametersLosslessly
            && supportsBidirectionalRoundtrip
    }

    public init(
        routeID: String,
        miniProgramPath: String,
        universalLinkPath: String,
        preservesQueryParametersLosslessly: Bool = true,
        supportsBidirectionalRoundtrip: Bool = true
    ) {
        self.routeID = routeID
        self.miniProgramPath = miniProgramPath
        self.universalLinkPath = universalLinkPath
        self.preservesQueryParametersLosslessly = preservesQueryParametersLosslessly
        self.supportsBidirectionalRoundtrip = supportsBidirectionalRoundtrip
    }
}

/// Self-contained snapshot for bidirectional Mini-Program path <-> Native Universal Link
/// route translation and lossless query parameter preservation.
public struct MiniProgramPathTranslatorSnapshot: Sendable, Equatable {
    public static let defaultRows: [MiniProgramRouteMappingRow] = [
        MiniProgramRouteMappingRow(
            routeID: "play-project-detail",
            miniProgramPath: "/pages/play/detail/index",
            universalLinkPath: "/play/detail",
            preservesQueryParametersLosslessly: true,
            supportsBidirectionalRoundtrip: true
        ),
        MiniProgramRouteMappingRow(
            routeID: "roam-stamp-album",
            miniProgramPath: "/subpackageP3/pages/stamp-album/index/index",
            universalLinkPath: "/roam/stamp-album",
            preservesQueryParametersLosslessly: true,
            supportsBidirectionalRoundtrip: true
        ),
        MiniProgramRouteMappingRow(
            routeID: "badge-wall-focus",
            miniProgramPath: "/subpackageP3/pages/badge-wall/index/index",
            universalLinkPath: "/profile/badge-wall",
            preservesQueryParametersLosslessly: true,
            supportsBidirectionalRoundtrip: true
        ),
        MiniProgramRouteMappingRow(
            routeID: "growth-leaderboard",
            miniProgramPath: "/subpackageP3/pages/growthcenter/leaderboard/index",
            universalLinkPath: "/growth/leaderboard",
            preservesQueryParametersLosslessly: true,
            supportsBidirectionalRoundtrip: true
        )
    ]

    public static let defaultReady = MiniProgramPathTranslatorSnapshot()

    public let rows: [MiniProgramRouteMappingRow]
    public let droppedQueryParameterCount: Int
    public let rejectsUnknownSchemeOrHost: Bool

    public init(
        rows: [MiniProgramRouteMappingRow] = Self.defaultRows,
        droppedQueryParameterCount: Int = 0,
        rejectsUnknownSchemeOrHost: Bool = true
    ) {
        self.rows = rows
        self.droppedQueryParameterCount = droppedQueryParameterCount
        self.rejectsUnknownSchemeOrHost = rejectsUnknownSchemeOrHost
    }

    public var hasQueryParameterLoss: Bool {
        droppedQueryParameterCount > 0 || rows.contains { !$0.preservesQueryParametersLosslessly }
    }

    public var isReady: Bool {
        !rows.isEmpty
            && !hasQueryParameterLoss
            && rejectsUnknownSchemeOrHost
            && rows.allSatisfy(\.isCompliant)
    }
}

/// SwiftUI section displaying bidirectional Mini-Program path <-> Native Universal Link route translation
/// and lossless query parameter preservation using `Text(verbatim:)` throughout (0 new `.xcstrings` keys).
@MainActor public struct DeepLinkToMiniProgramPathTranslatorSectionView: View {
    public let snapshot: MiniProgramPathTranslatorSnapshot

    public init(snapshot: MiniProgramPathTranslatorSnapshot = .defaultReady) {
        self.snapshot = snapshot
    }

    public var statusHeadline: String {
        if snapshot.hasQueryParameterLoss {
            return "查询参数丢失告警：小程序路径与原生 Universal Link 互转存在参数截断"
        }
        if !snapshot.rejectsUnknownSchemeOrHost || !snapshot.isReady {
            return "未知域名白名单拦截未开启或双向路径映射存在未达标路由"
        }
        return "小程序路径 <-> 原生 Universal Link 双向无损互转与参数保留全部就绪"
    }

    public var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: statusHeadline)
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("mpPathTranslator.statusHeadline")
                Text(verbatim: "已映射路由：\(snapshot.rows.count) · 参数丢失数：\(snapshot.droppedQueryParameterCount) · 未知源拦截：\(snapshot.rejectsUnknownSchemeOrHost ? "已开启" : "未开启")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("mpPathTranslator.summary")
            }

            ForEach(snapshot.rows) { row in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: row.isCompliant ? "arrow.left.arrow.right.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(row.isCompliant ? .green : .red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: "\(row.miniProgramPath) ⇄ \(row.universalLinkPath)")
                            .font(.footnote.weight(.medium))
                        Text(verbatim: "参数无损保留：\(row.preservesQueryParametersLosslessly ? "是" : "否") · 双向回环：\(row.supportsBidirectionalRoundtrip ? "是" : "否")")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(verbatim: row.isCompliant ? "无损" : "异常")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(row.isCompliant ? .green : .red)
                }
                .accessibilityIdentifier("mpPathTranslator.row." + row.routeID)
            }
        } header: {
            Text(verbatim: "小程序路径与原生深链双向互转诊断")
        }
        .accessibilityIdentifier("mpPathTranslator.section")
    }
}

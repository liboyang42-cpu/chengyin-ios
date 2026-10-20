import SwiftUI
import QuestifyCore

/// Self-contained diagnostic row for `AppSessionContainer`, `ContentDraftContextFence`,
/// and `AccountSessionGate` composition invariants.
public struct AppSessionDiagnosticRow: Identifiable, Equatable, Sendable {
    public let componentID: String
    public let title: String
    public let detail: String
    public let isCompliant: Bool

    public var id: String { componentID }

    public init(
        componentID: String,
        title: String,
        detail: String,
        isCompliant: Bool
    ) {
        self.componentID = componentID
        self.title = title
        self.detail = detail
        self.isCompliant = isCompliant
    }
}

/// Self-contained snapshot for `AppSessionContainer` fixture short-circuiting (`session = nil`),
/// `ContentDraftContextFence` reader isolation, and `AccountSessionGate` status.
public struct AppSessionCompositionSnapshot: Equatable, Sendable {
    public static let canonicalComponentIDs: [String] = [
        "AppSessionContainer",
        "ContentDraftContextFence",
        "AccountSessionGate"
    ]

    public let isFixtureLaunchMode: Bool
    public let sessionIsNilOnFixtureShortCircuit: Bool
    public let contentDraftReaderIsolatedByScope: Bool
    public let accountSessionGateEnforced: Bool
    public let rows: [AppSessionDiagnosticRow]

    public init(
        isFixtureLaunchMode: Bool = true,
        sessionIsNilOnFixtureShortCircuit: Bool = true,
        contentDraftReaderIsolatedByScope: Bool = true,
        accountSessionGateEnforced: Bool = true,
        customRows: [AppSessionDiagnosticRow]? = nil
    ) {
        self.isFixtureLaunchMode = isFixtureLaunchMode
        self.sessionIsNilOnFixtureShortCircuit = sessionIsNilOnFixtureShortCircuit
        self.contentDraftReaderIsolatedByScope = contentDraftReaderIsolatedByScope
        self.accountSessionGateEnforced = accountSessionGateEnforced

        let containerOK = !isFixtureLaunchMode || sessionIsNilOnFixtureShortCircuit
        if let customRows {
            self.rows = customRows
        } else {
            self.rows = [
                AppSessionDiagnosticRow(
                    componentID: "AppSessionContainer",
                    title: "AppSessionContainer 夹具短路",
                    detail: isFixtureLaunchMode
                        ? (sessionIsNilOnFixtureShortCircuit ? "夹具启动已短路 session = nil" : "夹具启动未短路 session")
                        : "常规会话容器模式",
                    isCompliant: containerOK
                ),
                AppSessionDiagnosticRow(
                    componentID: "ContentDraftContextFence",
                    title: "ContentDraftContextFence 读隔离",
                    detail: contentDraftReaderIsolatedByScope
                        ? "草稿上下文按账号与作用域严格隔离"
                        : "草稿上下文缺少作用域隔离围栏",
                    isCompliant: contentDraftReaderIsolatedByScope
                ),
                AppSessionDiagnosticRow(
                    componentID: "AccountSessionGate",
                    title: "AccountSessionGate 鉴权门控",
                    detail: accountSessionGateEnforced
                        ? "未登录/切换账号时自动阻断跨账号读写"
                        : "账号门控未生效",
                    isCompliant: accountSessionGateEnforced
                )
            ]
        }
    }

    public var hasCanonicalComponents: Bool {
        rows.map(\.componentID) == Self.canonicalComponentIDs
    }

    public var isAllCompliant: Bool {
        let containerOK = !isFixtureLaunchMode || sessionIsNilOnFixtureShortCircuit
        return containerOK
            && contentDraftReaderIsolatedByScope
            && accountSessionGateEnforced
            && hasCanonicalComponents
            && rows.allSatisfy(\.isCompliant)
    }
}

/// SwiftUI section rendering `AppSessionContainer` fixture short-circuiting (`session = nil`),
/// `ContentDraftContextFence` reader isolation, and `AccountSessionGate` status using
/// `Text(verbatim:)` throughout (0 new `.xcstrings` keys).
@MainActor public struct AppSessionCompositionDiagnosticsSectionView: View {
    public let snapshot: AppSessionCompositionSnapshot

    public init(snapshot: AppSessionCompositionSnapshot = AppSessionCompositionSnapshot()) {
        self.snapshot = snapshot
    }

    public var statusHeadline: String {
        if snapshot.isFixtureLaunchMode && !snapshot.sessionIsNilOnFixtureShortCircuit {
            return "夹具短路异常：AppSessionContainer 在夹具模式下必须保持 session = nil"
        }
        if !snapshot.contentDraftReaderIsolatedByScope {
            return "草稿隔离异常：ContentDraftContextFence 未按作用域隔离读取器"
        }
        if !snapshot.accountSessionGateEnforced {
            return "会话门控异常：AccountSessionGate 未开启跨账号访问拦截"
        }
        if !snapshot.isAllCompliant {
            return "应用会话装配诊断存在未达标组件"
        }
        return "AppSessionContainer 夹具短路 · ContentDraftContextFence 隔离 · AccountSessionGate 门控全部就绪"
    }

    public var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: statusHeadline)
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("appSessionComposition.statusHeadline")
                Text(verbatim: "启动模式：\(snapshot.isFixtureLaunchMode ? "离线夹具 (session = \(snapshot.sessionIsNilOnFixtureShortCircuit ? "nil" : "active"))" : "标准运行") · 整体合规：\(snapshot.isAllCompliant ? "是" : "否")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("appSessionComposition.modeSummary")
            }

            ForEach(snapshot.rows) { row in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: row.isCompliant ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(row.isCompliant ? .green : .red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: row.title)
                            .font(.footnote.weight(.medium))
                        Text(verbatim: row.detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(verbatim: row.isCompliant ? "正常" : "异常")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(row.isCompliant ? .green : .red)
                }
                .accessibilityIdentifier("appSessionComposition.row." + row.componentID)
            }
        } header: {
            Text(verbatim: "应用会话装配与作用域围栏诊断")
        }
        .accessibilityIdentifier("appSessionComposition.section")
    }
}

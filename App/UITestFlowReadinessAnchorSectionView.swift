import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#endif

/// Self-contained row for one of the 5 offline UI test readiness surfaces (`projectEditor`,
/// `profileSelfEdit`, `roamFinishedHistory`, `couponRuntimeJourney`, `mapCoreEntry`).
public struct UIFlowReadinessAnchorRow: Identifiable, Equatable, Sendable {
    public enum SurfaceID: String, CaseIterable, Equatable, Sendable {
        case projectEditor = "projectEditor"
        case profileSelfEdit = "profileSelfEdit"
        case roamFinishedHistory = "roamFinishedHistory"
        case couponRuntimeJourney = "couponRuntimeJourney"
        case mapCoreEntry = "mapCoreEntry"
    }

    public enum AnchorState: String, Equatable, Sendable {
        case wiredAndAnchored
        case missingLaunchFlag
        case missingAccessibilityAnchor
    }

    public let id: String
    public let surface: SurfaceID
    public let title: String
    public let launchArgument: String
    public let rootAccessibilityID: String
    public let testSuiteName: String
    public let state: AnchorState

    public init(
        surface: SurfaceID,
        title: String,
        launchArgument: String,
        rootAccessibilityID: String,
        testSuiteName: String,
        state: AnchorState
    ) {
        self.id = surface.rawValue
        self.surface = surface
        self.title = title
        self.launchArgument = launchArgument
        self.rootAccessibilityID = rootAccessibilityID
        self.testSuiteName = testSuiteName
        self.state = state
    }

    public var badgeText: String {
        switch state {
        case .wiredAndAnchored:
            return "ANCHORED"
        case .missingLaunchFlag:
            return "NO_FLAG"
        case .missingAccessibilityAnchor:
            return "NO_ANCHOR"
        }
    }
}

/// Self-contained snapshot covering the 5 UI test readiness surfaces (`projectEditor`,
/// `profileSelfEdit`, `roamFinishedHistory`, `couponRuntimeJourney`, `mapCoreEntry`).
public struct UITestFlowReadinessSnapshot: Equatable, Sendable {
    public static let canonicalSurfaces: [UIFlowReadinessAnchorRow.SurfaceID] = UIFlowReadinessAnchorRow.SurfaceID.allCases

    public let rows: [UIFlowReadinessAnchorRow]

    public init(rows: [UIFlowReadinessAnchorRow]) {
        self.rows = rows
    }

    public static let defaultAllFiveSurfaces = UITestFlowReadinessSnapshot(
        rows: [
            UIFlowReadinessAnchorRow(
                surface: .projectEditor,
                title: "工程编辑器与节点编排 (projectEditor)",
                launchArgument: "--uitesting-project-editor",
                rootAccessibilityID: "uiAnchor.projectEditor.root",
                testSuiteName: "ProjectEditorFlowTests",
                state: .wiredAndAnchored
            ),
            UIFlowReadinessAnchorRow(
                surface: .profileSelfEdit,
                title: "个人资料与主页自编辑 (profileSelfEdit)",
                launchArgument: "--uitesting-profile-self-edit",
                rootAccessibilityID: "uiAnchor.profileSelfEdit.root",
                testSuiteName: "ProfileSelfEditFlowTests",
                state: .wiredAndAnchored
            ),
            UIFlowReadinessAnchorRow(
                surface: .roamFinishedHistory,
                title: "漫游完赛历史与印章记录 (roamFinishedHistory)",
                launchArgument: "--uitesting-roam-finished-history",
                rootAccessibilityID: "uiAnchor.roamFinishedHistory.root",
                testSuiteName: "RoamFinishedHistoryFlowTests",
                state: .wiredAndAnchored
            ),
            UIFlowReadinessAnchorRow(
                surface: .couponRuntimeJourney,
                title: "票夹与优惠券核销码旅程 (couponRuntimeJourney)",
                launchArgument: "--uitesting-coupon-runtime",
                rootAccessibilityID: "uiAnchor.couponRuntimeJourney.root",
                testSuiteName: "CouponRuntimeJourneyFlowTests",
                state: .wiredAndAnchored
            ),
            UIFlowReadinessAnchorRow(
                surface: .mapCoreEntry,
                title: "地图核心入口与图层图例 (mapCoreEntry)",
                launchArgument: "--uitesting-map-core-entry",
                rootAccessibilityID: "uiAnchor.mapCoreEntry.hub",
                testSuiteName: "MapCoreEntryFlowTests",
                state: .wiredAndAnchored
            )
        ]
    )

    public var coversAllFiveSurfaces: Bool {
        Set(rows.map(\.surface)) == Set(Self.canonicalSurfaces)
    }

    public var anchoredCount: Int {
        rows.filter { $0.state == .wiredAndAnchored }.count
    }

    public var isFullyAnchored: Bool {
        coversAllFiveSurfaces && anchoredCount == rows.count
    }

    public var summaryText: String {
        "已锚定离线 UI 旅程 \(anchoredCount)/\(Self.canonicalSurfaces.count)"
    }
}

/// Renders the 5 UI test readiness surfaces (`projectEditor`, `profileSelfEdit`,
/// `roamFinishedHistory`, `couponRuntimeJourney`, `mapCoreEntry`) using `Text(verbatim:)` throughout.
@MainActor
public struct UITestFlowReadinessAnchorSectionView: View {
    public let snapshot: UITestFlowReadinessSnapshot

    public init(snapshot: UITestFlowReadinessSnapshot = .defaultAllFiveSurfaces) {
        self.snapshot = snapshot
    }

    public var body: some View {
        Section {
            HStack {
                Text(verbatim: "离线 UI 测试入口锚点总览")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(verbatim: snapshot.isFullyAnchored ? "5/5 全部锚定" : "\(snapshot.anchoredCount)/5 待修复")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background((snapshot.isFullyAnchored ? Color.green : Color.orange).opacity(0.15), in: Capsule())
                    .foregroundStyle(snapshot.isFullyAnchored ? Color.green : Color.orange)
                    .accessibilityIdentifier("uiFlowReadinessAudit.overallBadge")
            }

            LabeledContent {
                Text(verbatim: snapshot.summaryText)
                    .font(.footnote.monospacedDigit())
            } label: {
                Text(verbatim: "锚点统计")
            }
            .accessibilityIdentifier("uiFlowReadinessAudit.summary")

            ForEach(snapshot.rows) { row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(verbatim: row.title)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(verbatim: row.badgeText)
                            .font(.caption2.weight(.bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(badgeColor(for: row.state).opacity(0.15), in: Capsule())
                            .foregroundStyle(badgeColor(for: row.state))
                    }
                    Text(verbatim: "启动参数：\(row.launchArgument)")
                        .font(.caption.monospaced())
                    Text(verbatim: "根锚点 ID：\(row.rootAccessibilityID) · 用例套件：\(row.testSuiteName)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("uiFlowReadinessAudit.row.\(row.id)")
            }
        } header: {
            Text(verbatim: "UI 自动化旅程就绪核查 (UITest Readiness)")
        }
        .accessibilityIdentifier("uiFlowReadinessAudit.section")
    }

    private func badgeColor(for state: UIFlowReadinessAnchorRow.AnchorState) -> Color {
        switch state {
        case .wiredAndAnchored:
            return .green
        case .missingLaunchFlag:
            return .orange
        case .missingAccessibilityAnchor:
            return .red
        }
    }
}

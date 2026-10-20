import SwiftUI
import QuestifyCore

/// Self-contained row for a `ScenePhase` or `BGTask` lifecycle subsystem check.
public struct SceneLifecycleSubsystemRow: Sendable, Equatable, Identifiable {
    public let subsystemID: String
    public let title: String
    public let detail: String
    public let suspendsBackgroundPolling: Bool
    public let flushesDurableDraftsOnBackground: Bool
    public let registersBGTaskExpirationHandler: Bool

    public var id: String { subsystemID }

    public var isCompliant: Bool {
        !subsystemID.isEmpty
            && !title.isEmpty
            && suspendsBackgroundPolling
            && flushesDurableDraftsOnBackground
            && registersBGTaskExpirationHandler
    }

    public init(
        subsystemID: String,
        title: String,
        detail: String,
        suspendsBackgroundPolling: Bool = true,
        flushesDurableDraftsOnBackground: Bool = true,
        registersBGTaskExpirationHandler: Bool = true
    ) {
        self.subsystemID = subsystemID
        self.title = title
        self.detail = detail
        self.suspendsBackgroundPolling = suspendsBackgroundPolling
        self.flushesDurableDraftsOnBackground = flushesDurableDraftsOnBackground
        self.registersBGTaskExpirationHandler = registersBGTaskExpirationHandler
    }
}

/// Self-contained snapshot for `ScenePhase` background polling suspension, durable draft flush,
/// and `BGTask` expiration handler readiness.
public struct ScenePhaseLifecycleSnapshot: Sendable, Equatable {
    public static let defaultRows: [SceneLifecycleSubsystemRow] = [
        SceneLifecycleSubsystemRow(
            subsystemID: "walking-gps-polling",
            title: "漫游与步行定位轮询",
            detail: "进入 .background 时立即暂停前台高频刷新定时器",
            suspendsBackgroundPolling: true,
            flushesDurableDraftsOnBackground: true,
            registersBGTaskExpirationHandler: true
        ),
        SceneLifecycleSubsystemRow(
            subsystemID: "content-draft-autosave",
            title: "创作与漫游印章草稿持久化",
            detail: "进入 .inactive / .background 时同步落盘加密草稿状态",
            suspendsBackgroundPolling: true,
            flushesDurableDraftsOnBackground: true,
            registersBGTaskExpirationHandler: true
        ),
        SceneLifecycleSubsystemRow(
            subsystemID: "bgtask-expiration-fence",
            title: "BGTask 到期清理回调",
            detail: "注册 expirationHandler 并幂等取消悬挂任务、标记 setTaskCompleted",
            suspendsBackgroundPolling: true,
            flushesDurableDraftsOnBackground: true,
            registersBGTaskExpirationHandler: true
        )
    ]

    public static let defaultReady = ScenePhaseLifecycleSnapshot()

    public let rows: [SceneLifecycleSubsystemRow]
    public let activePollingCountInBackground: Int
    public let pendingUnflushedDraftCount: Int
    public let bgTaskExpirationHandlerRegistered: Bool

    public init(
        rows: [SceneLifecycleSubsystemRow] = Self.defaultRows,
        activePollingCountInBackground: Int = 0,
        pendingUnflushedDraftCount: Int = 0,
        bgTaskExpirationHandlerRegistered: Bool = true
    ) {
        self.rows = rows
        self.activePollingCountInBackground = activePollingCountInBackground
        self.pendingUnflushedDraftCount = pendingUnflushedDraftCount
        self.bgTaskExpirationHandlerRegistered = bgTaskExpirationHandlerRegistered
    }

    public var hasBackgroundPollingLeak: Bool {
        activePollingCountInBackground > 0 || rows.contains { !$0.suspendsBackgroundPolling }
    }

    public var isReady: Bool {
        !rows.isEmpty
            && !hasBackgroundPollingLeak
            && pendingUnflushedDraftCount == 0
            && bgTaskExpirationHandlerRegistered
            && rows.allSatisfy(\.isCompliant)
    }
}

/// SwiftUI section displaying `ScenePhase` background polling suspension, durable draft flush,
/// and `BGTask` expiration handler readiness using `Text(verbatim:)` throughout (0 new `.xcstrings` keys).
@MainActor public struct BackgroundTaskAndScenePhaseLifecycleSectionView: View {
    public let snapshot: ScenePhaseLifecycleSnapshot

    public init(snapshot: ScenePhaseLifecycleSnapshot = .defaultReady) {
        self.snapshot = snapshot
    }

    public var statusHeadline: String {
        if snapshot.hasBackgroundPollingLeak {
            return "后台轮询泄漏告警：进入 .background 后仍存在未暂停轮询任务"
        }
        if snapshot.pendingUnflushedDraftCount > 0 {
            return "草稿落盘告警：存在 \(snapshot.pendingUnflushedDraftCount) 项草稿未在退后台前完成持久化"
        }
        if !snapshot.bgTaskExpirationHandlerRegistered || !snapshot.isReady {
            return "BGTask 到期清理回调未注册或生命周期子系统存在未达标项"
        }
        return "ScenePhase 退后台轮询暂停 · 草稿落盘 · BGTask 到期清理全部就绪"
    }

    public var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: statusHeadline)
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("scenePhaseLifecycle.statusHeadline")
                Text(verbatim: "后台残留轮询：\(snapshot.activePollingCountInBackground) · 待落盘草稿：\(snapshot.pendingUnflushedDraftCount) · BGTask 回调：\(snapshot.bgTaskExpirationHandlerRegistered ? "已注册" : "未注册")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("scenePhaseLifecycle.summary")
            }

            ForEach(snapshot.rows) { row in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: row.isCompliant ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(row.isCompliant ? .green : .red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: row.title)
                            .font(.footnote.weight(.medium))
                        Text(verbatim: row.detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(verbatim: row.isCompliant ? "就绪" : "告警")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(row.isCompliant ? .green : .red)
                }
                .accessibilityIdentifier("scenePhaseLifecycle.row." + row.subsystemID)
            }
        } header: {
            Text(verbatim: "ScenePhase 生命周期与后台任务门控")
        }
        .accessibilityIdentifier("scenePhaseLifecycle.section")
    }
}

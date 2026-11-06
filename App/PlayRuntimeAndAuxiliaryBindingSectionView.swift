import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#endif

/// Self-contained row for each of the 5 play runtime & authority pillars:
/// `w2-11` play session lifecycle, `I01` node submission idempotency,
/// `I02` auxiliary sensor/step non-proof binding, `I09` pause clock & relaunch recovery,
/// and `H-W03` authoritative run CAS & pending intent journal.
public struct PlayRuntimeAuditPillarRow: Identifiable, Equatable, Sendable {
    public enum PillarKind: String, CaseIterable, Equatable, Sendable {
        case w211PlaySessionLifecycle = "w2-11"
        case i01NodeSubmissionIdempotency = "I01"
        case i02AuxiliarySensorNonProof = "I02"
        case i09PauseClockAndRecovery = "I09"
        case hW03RunAuthorityCasAndJournal = "H-W03"
    }

    public let id: String
    public let kind: PillarKind
    public let title: String
    public let summary: String
    public let verificationEvidence: String
    public let isVerified: Bool

    public init(
        id: String? = nil,
        kind: PillarKind,
        title: String,
        summary: String,
        verificationEvidence: String,
        isVerified: Bool
    ) {
        self.id = id ?? kind.rawValue
        self.kind = kind
        self.title = title
        self.summary = summary
        self.verificationEvidence = verificationEvidence
        self.isVerified = isVerified
    }
}

/// Self-contained snapshot for the 5 play runtime & auxiliary binding pillars (`w2-11`, `I01`, `I02`, `I09`, `H-W03`).
public struct PlayRuntimeAndAuxiliaryBindingSnapshot: Equatable, Sendable {
    public let playSessionLifecycleParityVerified: Bool
    public let nodeSubmissionIdempotencyVerified: Bool
    public let auxiliaryStepAndAudioBoundAsNonProof: Bool
    public let pauseClockAndRelaunchRecoveryVerified: Bool
    public let runAuthorityCasAndJournalVerified: Bool
    public let rows: [PlayRuntimeAuditPillarRow]

    public init(
        playSessionLifecycleParityVerified: Bool,
        nodeSubmissionIdempotencyVerified: Bool,
        auxiliaryStepAndAudioBoundAsNonProof: Bool,
        pauseClockAndRelaunchRecoveryVerified: Bool,
        runAuthorityCasAndJournalVerified: Bool,
        rows: [PlayRuntimeAuditPillarRow]
    ) {
        self.playSessionLifecycleParityVerified = playSessionLifecycleParityVerified
        self.nodeSubmissionIdempotencyVerified = nodeSubmissionIdempotencyVerified
        self.auxiliaryStepAndAudioBoundAsNonProof = auxiliaryStepAndAudioBoundAsNonProof
        self.pauseClockAndRelaunchRecoveryVerified = pauseClockAndRelaunchRecoveryVerified
        self.runAuthorityCasAndJournalVerified = runAuthorityCasAndJournalVerified
        self.rows = rows
    }

    public var verifiedRowCount: Int {
        rows.filter(\.isVerified).count
    }

    public var isAllCompliant: Bool {
        playSessionLifecycleParityVerified &&
            nodeSubmissionIdempotencyVerified &&
            auxiliaryStepAndAudioBoundAsNonProof &&
            pauseClockAndRelaunchRecoveryVerified &&
            runAuthorityCasAndJournalVerified &&
            Set(rows.map(\.kind)) == Set(PlayRuntimeAuditPillarRow.PillarKind.allCases) &&
            rows.allSatisfy(\.isVerified)
    }

    public static let compliantSample = PlayRuntimeAndAuxiliaryBindingSnapshot(
        playSessionLifecycleParityVerified: true,
        nodeSubmissionIdempotencyVerified: true,
        auxiliaryStepAndAudioBoundAsNonProof: true,
        pauseClockAndRelaunchRecoveryVerified: true,
        runAuthorityCasAndJournalVerified: true,
        rows: [
            PlayRuntimeAuditPillarRow(
                kind: .w211PlaySessionLifecycle,
                title: "w2-11 游玩运行态与章节推进对齐",
                summary: "章节/节点进度、线索揭晓、答案校验与完赛状态严格对齐服务端回读",
                verificationEvidence: "PlayRunLifecycle 状态机已核验 · 禁止客户端自造通关奖励",
                isVerified: true
            ),
            PlayRuntimeAuditPillarRow(
                kind: .i01NodeSubmissionIdempotency,
                title: "I01 节点提交幂等与防重放锁定",
                summary: "同一节点提交固定绑定 requestId，结果未知时保持锁定并仅重放同一意图",
                verificationEvidence: "PAYLOAD_CONFLICT 即时拦截 · 未知结果先回读回执",
                isVerified: true
            ),
            PlayRuntimeAuditPillarRow(
                kind: .i02AuxiliarySensorNonProof,
                title: "I02 步数/传感器辅助绑定（非通关证明）",
                summary: "iPhone 步数与运动读数仅作活动回顾参考，不作为完赛证明且不解锁任何奖励",
                verificationEvidence: "NSMotionUsageDescription 非证明声明已对齐 · 拒绝无权时优雅降级",
                isVerified: true
            ),
            PlayRuntimeAuditPillarRow(
                kind: .i09PauseClockAndRecovery,
                title: "I09 暂停计时、前后台切换与冷启动恢复",
                summary: "进入后台或暂停态立即冻结交互并在恢复前台时重新拉取服务端权威快照",
                verificationEvidence: "暂停态禁止提交动作 · 冷启动先校验会话租约",
                isVerified: true
            ),
            PlayRuntimeAuditPillarRow(
                kind: .hW03RunAuthorityCasAndJournal,
                title: "H-W03 权威进度 CAS 版本校验与恢复日志",
                summary: "expectedStateVersion 冲突触发 refreshRequired，落盘意图在重启后仍保持幂等",
                verificationEvidence: "RunAuthorityProjection + RunAuthorityRecovery 已核验（默认关闭）",
                isVerified: true
            )
        ]
    )
}

@MainActor
public struct PlayRuntimeAndAuxiliaryBindingSectionView: View {
    public let snapshot: PlayRuntimeAndAuxiliaryBindingSnapshot

    public init(snapshot: PlayRuntimeAndAuxiliaryBindingSnapshot = .compliantSample) {
        self.snapshot = snapshot
    }

    public var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: "游玩运行态、传感器边界与权威状态审计")
                    .font(.headline)
                    .accessibilityIdentifier("playRuntimeAudit.title")

                Text(verbatim: Self.overallStatusText(for: snapshot))
                    .font(.subheadline)
                    .foregroundStyle(snapshot.isAllCompliant ? .green : .red)
                    .accessibilityIdentifier("playRuntimeAudit.overallStatus")

                Text(verbatim: Self.lifecycleStatusText(for: snapshot))
                    .font(.footnote)
                    .accessibilityIdentifier("playRuntimeAudit.lifecycleStatus")

                Text(verbatim: Self.idempotencyStatusText(for: snapshot))
                    .font(.footnote)
                    .accessibilityIdentifier("playRuntimeAudit.idempotencyStatus")

                Text(verbatim: Self.auxiliaryBindingStatusText(for: snapshot))
                    .font(.footnote)
                    .accessibilityIdentifier("playRuntimeAudit.auxiliaryBindingStatus")

                Text(verbatim: Self.pauseRecoveryStatusText(for: snapshot))
                    .font(.footnote)
                    .accessibilityIdentifier("playRuntimeAudit.pauseRecoveryStatus")

                Text(verbatim: Self.runAuthorityStatusText(for: snapshot))
                    .font(.footnote)
                    .accessibilityIdentifier("playRuntimeAudit.runAuthorityStatus")
            }
            .padding(.vertical, 4)

            if snapshot.rows.isEmpty {
                Text(verbatim: "暂无游玩运行态与权威状态检查项")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("playRuntimeAudit.empty")
            } else {
                ForEach(snapshot.rows) { row in
                    PlayRuntimeAuditPillarRowView(row: row)
                }
            }
        }
        .accessibilityIdentifier("playRuntimeAudit.section")
    }

    public static func overallStatusText(for snapshot: PlayRuntimeAndAuxiliaryBindingSnapshot) -> String {
        snapshot.isAllCompliant
            ? "整体状态：五大游玩运行态与权威状态支柱全部达标（\(snapshot.verifiedRowCount)/\(snapshot.rows.count)）"
            : "整体状态：存在未达标的游玩运行态或权威状态支柱（\(snapshot.verifiedRowCount)/\(snapshot.rows.count)）"
    }

    public static func lifecycleStatusText(for snapshot: PlayRuntimeAndAuxiliaryBindingSnapshot) -> String {
        snapshot.playSessionLifecycleParityVerified
            ? "w2-11 游玩生命周期：章节推进与服务端回读已对齐"
            : "w2-11 游玩生命周期：章节推进或回读对齐待修复"
    }

    public static func idempotencyStatusText(for snapshot: PlayRuntimeAndAuxiliaryBindingSnapshot) -> String {
        snapshot.nodeSubmissionIdempotencyVerified
            ? "I01 节点提交幂等：requestId 锁定与防重放已启用"
            : "I01 节点提交幂等：requestId 锁定或防重放未启用"
    }

    public static func auxiliaryBindingStatusText(for snapshot: PlayRuntimeAndAuxiliaryBindingSnapshot) -> String {
        snapshot.auxiliaryStepAndAudioBoundAsNonProof
            ? "I02 辅助传感器边界：步数仅作参考且不解锁奖励已核验"
            : "I02 辅助传感器边界：存在将步数视为证明的风险"
    }

    public static func pauseRecoveryStatusText(for snapshot: PlayRuntimeAndAuxiliaryBindingSnapshot) -> String {
        snapshot.pauseClockAndRelaunchRecoveryVerified
            ? "I09 暂停与恢复：前后台冻结与权威快照重读已核验"
            : "I09 暂停与恢复：前后台冻结或快照重读待核验"
    }

    public static func runAuthorityStatusText(for snapshot: PlayRuntimeAndAuxiliaryBindingSnapshot) -> String {
        snapshot.runAuthorityCasAndJournalVerified
            ? "H-W03 权威进度 CAS：expectedStateVersion 与恢复日志已核验"
            : "H-W03 权威进度 CAS：expectedStateVersion 或恢复日志未就绪"
    }
}

@MainActor
private struct PlayRuntimeAuditPillarRowView: View {
    let row: PlayRuntimeAuditPillarRow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(verbatim: row.title)
                    .font(.subheadline.bold())
                Spacer()
                Text(verbatim: row.isVerified ? "已核验" : "待修复")
                    .font(.caption)
                    .foregroundStyle(row.isVerified ? .green : .red)
            }

            Text(verbatim: row.summary)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(verbatim: "验证凭据：\(row.verificationEvidence)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("playRuntimeAudit.row")
    }
}

import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#endif

/// Self-contained row for each of the 4 received stamps & private passport tools audit pillars:
/// `I00` session role admission, `I11` received stamps read-only ledger,
/// `w2-09` private passport tools owner scoping, and non-cash honor-only stamp boundary.
public struct PassportToolAuditRow: Identifiable, Equatable, Sendable {
    public enum PillarKind: String, CaseIterable, Equatable, Sendable {
        case i00SessionRoleAdmission = "I00"
        case i11ReceivedStampsReadOnly = "I11"
        case w209PrivatePassportTools = "w2-09"
        case nonCashStampHonorBoundary = "STAMP-NON-CASH"
    }

    public let id: String
    public let kind: PillarKind
    public let title: String
    public let summary: String
    public let verificationNote: String
    public let isVerified: Bool

    public init(
        id: String? = nil,
        kind: PillarKind,
        title: String,
        summary: String,
        verificationNote: String,
        isVerified: Bool
    ) {
        self.id = id ?? kind.rawValue
        self.kind = kind
        self.title = title
        self.summary = summary
        self.verificationNote = verificationNote
        self.isVerified = isVerified
    }
}

/// Self-contained snapshot for `I00+I11` received stamps and `w2-09` private passport tools status.
public struct ReceivedStampsAndPassportToolsSnapshot: Equatable, Sendable {
    public let sessionRoleAdmissionVerified: Bool
    public let receivedStampsReadOnlyParityVerified: Bool
    public let privatePassportToolsScopedToOwner: Bool
    public let stampsNonCashHonorOnlyVerified: Bool
    public let rows: [PassportToolAuditRow]

    public init(
        sessionRoleAdmissionVerified: Bool,
        receivedStampsReadOnlyParityVerified: Bool,
        privatePassportToolsScopedToOwner: Bool,
        stampsNonCashHonorOnlyVerified: Bool,
        rows: [PassportToolAuditRow]
    ) {
        self.sessionRoleAdmissionVerified = sessionRoleAdmissionVerified
        self.receivedStampsReadOnlyParityVerified = receivedStampsReadOnlyParityVerified
        self.privatePassportToolsScopedToOwner = privatePassportToolsScopedToOwner
        self.stampsNonCashHonorOnlyVerified = stampsNonCashHonorOnlyVerified
        self.rows = rows
    }

    public var verifiedRowCount: Int {
        rows.filter(\.isVerified).count
    }

    public var isAllCompliant: Bool {
        sessionRoleAdmissionVerified &&
            receivedStampsReadOnlyParityVerified &&
            privatePassportToolsScopedToOwner &&
            stampsNonCashHonorOnlyVerified &&
            Set(rows.map(\.kind)) == Set(PassportToolAuditRow.PillarKind.allCases) &&
            rows.allSatisfy(\.isVerified)
    }

    public static let compliantSample = ReceivedStampsAndPassportToolsSnapshot(
        sessionRoleAdmissionVerified: true,
        receivedStampsReadOnlyParityVerified: true,
        privatePassportToolsScopedToOwner: true,
        stampsNonCashHonorOnlyVerified: true,
        rows: [
            PassportToolAuditRow(
                kind: .i00SessionRoleAdmission,
                title: "I00 会话准入与角色边界核验",
                summary: "印章簿与随身工具箱严格绑定当前已核验会话身份，跨账号或未登录态立即阻断",
                verificationNote: "AccountSessionGate 准入已通过 · 租约代际一致",
                isVerified: true
            ),
            PassportToolAuditRow(
                kind: .i11ReceivedStampsReadOnly,
                title: "I11 已获印章簿只读回放",
                summary: "按服务端事实展示已获印章、加盖时间、关联活动与空态提示，不伪造未获印章",
                verificationNote: "只读印章列表与详情已对齐 · 零本地自造写路径",
                isVerified: true
            ),
            PassportToolAuditRow(
                kind: .w209PrivatePassportTools,
                title: "w2-09 私人随身工具与纪念册隔离",
                summary: "个人收藏、手账工具与通关纪念册仅对本人可见可操作，不向他人公开泄漏",
                verificationNote: "本人专属作用域已核验 · 跨用户访问已拒绝",
                isVerified: true
            ),
            PassportToolAuditRow(
                kind: .nonCashStampHonorBoundary,
                title: "印章与纪念物非现金荣誉边界",
                summary: "印章、徽章与碎片仅作活动纪念与荣誉展示，不可提现、转让或折算现金",
                verificationNote: "W17.4 非现金账本约束已核验",
                isVerified: true
            )
        ]
    )
}

@MainActor
public struct ReceivedStampsAndPassportToolsSectionView: View {
    public let snapshot: ReceivedStampsAndPassportToolsSnapshot

    public init(snapshot: ReceivedStampsAndPassportToolsSnapshot = .compliantSample) {
        self.snapshot = snapshot
    }

    public var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: "已获印章簿与私人随身工具审计 (I00+I11 / w2-09)")
                    .font(.headline)
                    .accessibilityIdentifier("receivedStampsPassport.title")

                Text(verbatim: Self.overallStatusText(for: snapshot))
                    .font(.subheadline)
                    .foregroundStyle(snapshot.isAllCompliant ? .green : .red)
                    .accessibilityIdentifier("receivedStampsPassport.overallStatus")

                Text(verbatim: Self.sessionAdmissionStatusText(for: snapshot))
                    .font(.footnote)
                    .accessibilityIdentifier("receivedStampsPassport.sessionAdmissionStatus")

                Text(verbatim: Self.receivedStampsStatusText(for: snapshot))
                    .font(.footnote)
                    .accessibilityIdentifier("receivedStampsPassport.receivedStampsStatus")

                Text(verbatim: Self.privateToolsStatusText(for: snapshot))
                    .font(.footnote)
                    .accessibilityIdentifier("receivedStampsPassport.privateToolsStatus")

                Text(verbatim: Self.nonCashHonorStatusText(for: snapshot))
                    .font(.footnote)
                    .accessibilityIdentifier("receivedStampsPassport.nonCashHonorStatus")
            }
            .padding(.vertical, 4)

            if snapshot.rows.isEmpty {
                Text(verbatim: "暂无印章簿与随身工具检查项")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("receivedStampsPassport.empty")
            } else {
                ForEach(snapshot.rows) { row in
                    PassportToolAuditRowView(row: row)
                }
            }
        }
        .accessibilityIdentifier("receivedStampsPassport.section")
    }

    public static func overallStatusText(for snapshot: ReceivedStampsAndPassportToolsSnapshot) -> String {
        snapshot.isAllCompliant
            ? "整体状态：印章簿与私人随身工具四大支柱全部达标（\(snapshot.verifiedRowCount)/\(snapshot.rows.count)）"
            : "整体状态：存在未达标的印章簿或私人随身工具检查项（\(snapshot.verifiedRowCount)/\(snapshot.rows.count)）"
    }

    public static func sessionAdmissionStatusText(for snapshot: ReceivedStampsAndPassportToolsSnapshot) -> String {
        snapshot.sessionRoleAdmissionVerified
            ? "I00 会话准入：当前账号身份与角色租约已核验"
            : "I00 会话准入：账号身份或角色租约未通过核验"
    }

    public static func receivedStampsStatusText(for snapshot: ReceivedStampsAndPassportToolsSnapshot) -> String {
        snapshot.receivedStampsReadOnlyParityVerified
            ? "I11 已获印章簿：服务端只读事实与空态展示已对齐"
            : "I11 已获印章簿：只读事实或空态展示待对齐"
    }

    public static func privateToolsStatusText(for snapshot: ReceivedStampsAndPassportToolsSnapshot) -> String {
        snapshot.privatePassportToolsScopedToOwner
            ? "w2-09 私人随身工具：本人专属作用域与隐私隔离已启用"
            : "w2-09 私人随身工具：本人专属作用域或隐私隔离未启用"
    }

    public static func nonCashHonorStatusText(for snapshot: ReceivedStampsAndPassportToolsSnapshot) -> String {
        snapshot.stampsNonCashHonorOnlyVerified
            ? "非现金荣誉边界：印章不可提现、不可转让已核验"
            : "非现金荣誉边界：印章非现金约束未核验"
    }
}

@MainActor
private struct PassportToolAuditRowView: View {
    let row: PassportToolAuditRow

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

            Text(verbatim: "核验说明：\(row.verificationNote)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .accessibilityIdentifier("receivedStampsPassport.row")
    }
}

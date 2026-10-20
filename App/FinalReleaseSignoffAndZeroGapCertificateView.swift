import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#endif

public struct ReleaseCertificatePillarRow: Sendable, Equatable, Identifiable {
    public let id: String
    public let pillarTitle: String
    public let scopeSummary: String
    public let isCertified: Bool
    public let statusText: String
    public let commitSHA: String?
    public let evidenceLink: String?
    public let blockerNote: String?

    public init(
        id: String,
        pillarTitle: String,
        scopeSummary: String,
        isCertified: Bool = false,
        statusText: String = "UNVERIFIED",
        commitSHA: String? = nil,
        evidenceLink: String? = nil,
        blockerNote: String? = nil
    ) {
        self.id = id
        self.pillarTitle = pillarTitle
        self.scopeSummary = scopeSummary
        self.isCertified = isCertified
        self.statusText = statusText
        self.commitSHA = commitSHA
        self.evidenceLink = evidenceLink
        self.blockerNote = blockerNote
    }
}

public struct FinalReleaseCertificateSnapshot: Sendable, Equatable {
    /// Fail-closed default: without external SHA-bound verification evidence, every pillar starts unverified.
    public static let defaultUnverifiedPillars: [ReleaseCertificatePillarRow] = [
        ReleaseCertificatePillarRow(
            id: "Wave 1–3 Tickets",
            pillarTitle: "Wave 1–3 Tickets",
            scopeSummary: "Wave 1 (B..H)、Wave 2 (w2-01..w2-21) 与 Wave 3 (I00..I11 + BK) 范围映射与真机验收状态",
            isCertified: false,
            statusText: "PENDING_VERIFICATION",
            blockerNote: "需绑定最新整合 SHA 的完整真机/模拟器与后端联调证据"
        ),
        ReleaseCertificatePillarRow(
            id: "Reform v9 W02..W20",
            pillarTitle: "Reform v9 W02..W20",
            scopeSummary: "原方案 176 项稳定 ID (MV01..MV41 / U01..U08 / W01..W20) 逐条代码、接线、测试与部署状态",
            isCertified: false,
            statusText: "PENDING_VERIFICATION",
            blockerNote: "跨仓后端运行态与模拟器全量回归尚未全部落锤"
        ),
        ReleaseCertificatePillarRow(
            id: "Mini-Program 99 Pages",
            pillarTitle: "Mini-Program 99 Pages",
            scopeSummary: "小程序 99 个真实页面路由逐条对齐台账（区分代码、生产接线、测试与后端状态）",
            isCertified: false,
            statusText: "PENDING_VERIFICATION",
            blockerNote: "部分页面依赖独立生产门禁或后端权限核验，未默认全绿"
        ),
        ReleaseCertificatePillarRow(
            id: "RC-GATE-01..06",
            pillarTitle: "RC-GATE-01..06",
            scopeSummary: "六大发布候选安全与商业边界门禁默认关闭 (fail-closed) 核验",
            isCertified: false,
            statusText: "PENDING_VERIFICATION",
            blockerNote: "需对最终发布 SHA 完成独立门禁证据核验"
        ),
        ReleaseCertificatePillarRow(
            id: "App Store Privacy & UGC",
            pillarTitle: "App Store Privacy & UGC",
            scopeSummary: "隐私门禁、账号注销、UGC 举报拉黑与权属声明合规核验",
            isCertified: false,
            statusText: "PENDING_VERIFICATION",
            blockerNote: "需绑定最终发布构建产物与审核元数据核验记录"
        ),
        ReleaseCertificatePillarRow(
            id: "Cloud CI & ContractChecks",
            pillarTitle: "Cloud CI & ContractChecks",
            scopeSummary: "静态门禁、Swift 类型检查、Python 契约检查与 Simulator/Device XCTest 分片核验",
            isCertified: false,
            statusText: "NOT_RUN_ON_SIMULATOR",
            blockerNote: "本地仅完成静态/typecheck/ContractChecks，Simulator/XCUITest 分片需独立运行证据"
        )
    ]

    /// Preview/fixture-only rows used by UI previews or synthetic unit tests. Never used as default release status.
    public static let previewFixturePillars: [ReleaseCertificatePillarRow] = defaultUnverifiedPillars.map { row in
        ReleaseCertificatePillarRow(
            id: row.id,
            pillarTitle: row.pillarTitle,
            scopeSummary: row.scopeSummary,
            isCertified: true,
            statusText: "PASS (FIXTURE)",
            commitSHA: "fixture-preview-sha",
            evidenceLink: "docs/handoff/issue-61-response-20261020.md",
            blockerNote: nil
        )
    }

    public static let defaultPillars: [ReleaseCertificatePillarRow] = defaultUnverifiedPillars

    public static let defaultUnverified = FinalReleaseCertificateSnapshot(
        certificateID: "RC-UNVERIFIED-20261020",
        targetCommitSHA: nil,
        pillars: defaultUnverifiedPillars
    )

    /// Synthetic preview fixture snapshot; explicitly labeled for tests/previews.
    public static let previewReadyFixture = FinalReleaseCertificateSnapshot(
        certificateID: "RC-FIXTURE-PREVIEW",
        targetCommitSHA: "fixture-preview-sha",
        pillars: previewFixturePillars
    )

    public let certificateID: String
    public let targetCommitSHA: String?
    public let pillars: [ReleaseCertificatePillarRow]

    public init(
        certificateID: String = "RC-UNVERIFIED-20261020",
        targetCommitSHA: String? = nil,
        pillars: [ReleaseCertificatePillarRow] = FinalReleaseCertificateSnapshot.defaultUnverifiedPillars
    ) {
        self.certificateID = certificateID
        self.targetCommitSHA = targetCommitSHA
        self.pillars = pillars
    }

    public var certifiedPillarCount: Int {
        guard let sha = targetCommitSHA?.trimmingCharacters(in: .whitespacesAndNewlines), !sha.isEmpty else {
            return 0
        }
        return pillars.filter {
            $0.isCertified &&
            $0.commitSHA == sha &&
            !($0.evidenceLink?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }.count
    }

    public var uncertifiedPillars: [ReleaseCertificatePillarRow] {
        guard let sha = targetCommitSHA?.trimmingCharacters(in: .whitespacesAndNewlines), !sha.isEmpty else {
            return pillars
        }
        return pillars.filter {
            !$0.isCertified ||
            $0.commitSHA != sha ||
            ($0.evidenceLink?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        }
    }

    public var isZeroGapCertified: Bool {
        guard let sha = targetCommitSHA?.trimmingCharacters(in: .whitespacesAndNewlines), !sha.isEmpty else {
            return false
        }
        return pillars.count == 6 && uncertifiedPillars.isEmpty
    }

    public var statusHeadline: String {
        if isZeroGapCertified {
            return "发布签收证据已齐备 (\(certifiedPillarCount)/\(pillars.count))"
        }
        return "未验证/未签收：存在 \(uncertifiedPillars.count) 项待核验阻断，暂不可签发发布证书"
    }
}

/// Self-contained SwiftUI view displaying the 6-pillar Final Release Signoff & Zero-Gap Certificate.
/// Defaults to `.defaultUnverified` (fail-closed) unless an explicit verified/fixture snapshot is supplied.
@MainActor
public struct FinalReleaseSignoffAndZeroGapCertificateView: View {
    public let snapshot: FinalReleaseCertificateSnapshot

    public init(snapshot: FinalReleaseCertificateSnapshot = .defaultUnverified) {
        self.snapshot = snapshot
    }

    public var body: some View {
        Group {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: snapshot.statusHeadline)
                            .font(.subheadline.weight(.semibold))
                        Text(verbatim: "证书编号: \(snapshot.certificateID) · SHA: \(snapshot.targetCommitSHA ?? "未绑定")")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(verbatim: snapshot.isZeroGapCertified ? "CERTIFIED" : "UNVERIFIED")
                        .font(.caption2.monospaced().weight(.bold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(snapshot.isZeroGapCertified ? Color.green.opacity(0.18) : Color.red.opacity(0.18))
                        )
                        .accessibilityIdentifier("finalReleaseCertificate.badge")
                }
                .accessibilityIdentifier("finalReleaseCertificate.header")
            } header: {
                Text(verbatim: "最终发布签收与证据核验状态")
            }
            .accessibilityIdentifier("finalReleaseCertificate.summary.section")

            Section {
                ForEach(snapshot.pillars) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Image(systemName: row.isCertified ? "checkmark.seal.fill" : "xmark.octagon.fill")
                                .foregroundStyle(row.isCertified ? Color.green : Color.red)
                                .accessibilityHidden(true)
                            Text(verbatim: row.pillarTitle)
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text(verbatim: row.isCertified ? row.statusText : "BLOCKED (\(row.statusText))")
                                .font(.caption2.monospaced().weight(.semibold))
                                .foregroundStyle(row.isCertified ? Color.green : Color.red)
                        }
                        Text(verbatim: row.scopeSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let sha = row.commitSHA, !sha.isEmpty {
                            Text(verbatim: "绑定 SHA: \(sha) · 证据: \(row.evidenceLink ?? "无")")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        if let blocker = row.blockerNote, !blocker.isEmpty {
                            Text(verbatim: "未签收原因: \(blocker)")
                                .font(.caption)
                                .foregroundStyle(Color.red)
                        }
                    }
                    .accessibilityIdentifier("finalReleaseCertificate.pillar.\(row.id)")
                }
            } header: {
                Text(verbatim: "六大签收支柱核验清单")
            }
            .accessibilityIdentifier("finalReleaseCertificate.pillars.section")
        }
    }
}

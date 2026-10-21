import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#endif

public struct ReleaseCertificatePillarRow: Sendable, Equatable, Identifiable {
    public let id: String
    public let pillarTitle: String
    public let scopeSummary: String
    public let corePillar: ReleaseCertificatePillar
    public let isCertifiedByCore: Bool
    public let statusText: String
    public let commitSHA: String?
    public let evidenceLink: String?
    public let blockerNote: String?

    public var isCertified: Bool {
        isCertifiedByCore
    }

    public init(
        corePillar: ReleaseCertificatePillar,
        pillarTitle: String,
        scopeSummary: String,
        isCertifiedByCore: Bool,
        statusText: String = "UNVERIFIED",
        blockerNote: String? = nil
    ) {
        self.id = corePillar.id
        self.pillarTitle = pillarTitle
        self.scopeSummary = scopeSummary
        self.corePillar = corePillar
        self.isCertifiedByCore = isCertifiedByCore
        self.statusText = statusText
        let trimmedSHA = corePillar.commitSHA.trimmingCharacters(in: .whitespacesAndNewlines)
        self.commitSHA = trimmedSHA.isEmpty ? nil : trimmedSHA
        self.evidenceLink = corePillar.evidenceLinks.first
        self.blockerNote = blockerNote
    }
}

public struct FinalReleaseCertificateSnapshot: Sendable, Equatable {
    private struct PillarMetadata: Sendable, Equatable {
        let id: String
        let displayTitle: String
        let scopeSummary: String
        let defaultStatusText: String
        let defaultBlockerNote: String
    }

    private static let canonicalMetadata: [PillarMetadata] = [
        PillarMetadata(
            id: "pillar-wave1-to-wave3-tickets",
            displayTitle: "Wave 1–3 Tickets",
            scopeSummary: "Wave 1 (B..H)、Wave 2 (w2-01..w2-21) 与 Wave 3 (I00..I11 + BK) 范围映射与真机验收状态",
            defaultStatusText: "PENDING_VERIFICATION",
            defaultBlockerNote: "需绑定最新整合 SHA 的完整真机/模拟器与后端联调证据"
        ),
        PillarMetadata(
            id: "pillar-reform-v9-w02-to-w20",
            displayTitle: "Reform v9 W02..W20",
            scopeSummary: "客户端跟踪索引 176 项 (MV01..MV41 / U01..U08 / W01..W20) 逐条代码、接线、测试与部署状态",
            defaultStatusText: "PENDING_VERIFICATION",
            defaultBlockerNote: "跨仓后端运行态与模拟器全量回归尚未全部落锤"
        ),
        PillarMetadata(
            id: "pillar-miniprogram-99-pages",
            displayTitle: "Mini-Program 99 Pages",
            scopeSummary: "小程序 99 页基线子集逐条对齐台账（区分代码、生产接线、测试与后端状态）",
            defaultStatusText: "PENDING_VERIFICATION",
            defaultBlockerNote: "部分页面依赖独立生产门禁或后端权限核验，未默认全绿"
        ),
        PillarMetadata(
            id: "pillar-rc-gates-01-to-06",
            displayTitle: "RC-GATE-01..06",
            scopeSummary: "六大发布候选安全与商业边界门禁默认关闭 (fail-closed) 核验",
            defaultStatusText: "PENDING_VERIFICATION",
            defaultBlockerNote: "需对最终发布 SHA 完成独立门禁证据核验"
        ),
        PillarMetadata(
            id: "pillar-appstore-privacy-and-ugc",
            displayTitle: "App Store Privacy & UGC",
            scopeSummary: "隐私门禁、账号注销、UGC 举报拉黑与权属声明合规核验",
            defaultStatusText: "PENDING_VERIFICATION",
            defaultBlockerNote: "需绑定最终发布构建产物与审核元数据核验记录"
        ),
        PillarMetadata(
            id: "pillar-cloud-ci-and-contract-checks",
            displayTitle: "Cloud CI & ContractChecks",
            scopeSummary: "静态门禁、Swift 类型检查、Python 契约检查与 Simulator/Device XCTest 分片核验",
            defaultStatusText: "NOT_RUN_ON_SIMULATOR",
            defaultBlockerNote: "本地仅完成静态/ContractChecks，Simulator/XCUITest 分片需独立运行证据"
        )
    ]

    public static let defaultUnverified = FinalReleaseCertificateSnapshot(
        certificateID: "RC-UNVERIFIED-20261020",
        targetCommitSHA: nil,
        corePillars: FinalReleaseSignoffAndZeroGapCertificateContract.canonicalPillars
    )

    /// Synthetic preview fixture snapshot; uses `.previewFixture` Core pillars so Core evaluation
    /// keeps `isZeroGapCertified == false` and prevents preview fixtures from masquerading as formal signoff.
    public static let previewReadyFixture = FinalReleaseCertificateSnapshot(
        certificateID: "RC-FIXTURE-PREVIEW",
        targetCommitSHA: "fixture-preview-sha",
        corePillars: FinalReleaseSignoffAndZeroGapCertificateContract.previewFixturePillars()
    )

    public static var defaultUnverifiedPillars: [ReleaseCertificatePillarRow] {
        defaultUnverified.pillars
    }

    public static var previewFixturePillars: [ReleaseCertificatePillarRow] {
        previewReadyFixture.pillars
    }

    public static var defaultPillars: [ReleaseCertificatePillarRow] {
        defaultUnverified.pillars
    }

    public let certificateID: String
    public let targetCommitSHA: String?
    public let notBeforeISO8601: String?
    public let hasMergeConflict: Bool
    public let corePillars: [ReleaseCertificatePillar]

    public init(
        certificateID: String = "RC-UNVERIFIED-20261020",
        targetCommitSHA: String? = nil,
        notBeforeISO8601: String? = nil,
        hasMergeConflict: Bool = false,
        corePillars: [ReleaseCertificatePillar] = FinalReleaseSignoffAndZeroGapCertificateContract.canonicalPillars
    ) {
        self.certificateID = certificateID
        self.targetCommitSHA = targetCommitSHA
        self.notBeforeISO8601 = notBeforeISO8601
        self.hasMergeConflict = hasMergeConflict
        self.corePillars = corePillars
    }

    /// Constructs a snapshot directly from external formal evidence via `FinalReleaseSignoffAndZeroGapCertificateContract.evaluateCertificate`.
    public static func fromFormalEvidence(
        certificateID: String = "RC-FORMAL-EVALUATION",
        expectedCommitSHA: String,
        notBeforeISO8601: String? = nil,
        hasMergeConflict: Bool = false,
        evidence: [ReleasePillarEvidenceInput]
    ) -> FinalReleaseCertificateSnapshot {
        let evaluated = FinalReleaseSignoffAndZeroGapCertificateContract.evaluateCertificate(
            expectedCommitSHA: expectedCommitSHA,
            notBeforeISO8601: notBeforeISO8601,
            hasMergeConflict: hasMergeConflict,
            evidence: evidence
        )
        return FinalReleaseCertificateSnapshot(
            certificateID: certificateID,
            targetCommitSHA: expectedCommitSHA,
            notBeforeISO8601: notBeforeISO8601,
            hasMergeConflict: hasMergeConflict,
            corePillars: evaluated.evaluatedPillars
        )
    }

    private var coreEvaluation: (totalPillars: Int, certifiedPillars: Int, isZeroGapCertified: Bool) {
        FinalReleaseSignoffAndZeroGapCertificateContract.issueCertificate(
            pillars: corePillars,
            expectedCommitSHA: targetCommitSHA ?? "",
            notBeforeISO8601: notBeforeISO8601,
            hasMergeConflict: hasMergeConflict
        )
    }

    public var pillars: [ReleaseCertificatePillarRow] {
        let metadataByID = Dictionary(uniqueKeysWithValues: Self.canonicalMetadata.map { ($0.id, $0) })
        let expectedSHA = targetCommitSHA ?? ""
        return corePillars.map { pillar in
            let meta = metadataByID[pillar.id]
            let certified = FinalReleaseSignoffAndZeroGapCertificateContract.isCanonicalPillarCertified(
                pillar,
                in: corePillars,
                expectedCommitSHA: expectedSHA,
                notBeforeISO8601: notBeforeISO8601,
                hasMergeConflict: hasMergeConflict
            )
            let statusText: String
            let blockerNote: String?
            if certified {
                statusText = "PASSED"
                blockerNote = nil
            } else if pillar.isPreviewFixture {
                statusText = "PREVIEW_FIXTURE_NOT_FORMAL"
                blockerNote = "预览/测试夹具不可作为正式签收证据"
            } else {
                statusText = meta?.defaultStatusText ?? pillar.status.rawValue.uppercased()
                blockerNote = meta?.defaultBlockerNote ?? "未满足正式签收证据或 SHA 绑定要求"
            }
            return ReleaseCertificatePillarRow(
                corePillar: pillar,
                pillarTitle: meta?.displayTitle ?? pillar.title,
                scopeSummary: meta?.scopeSummary ?? pillar.title,
                isCertifiedByCore: certified,
                statusText: statusText,
                blockerNote: blockerNote
            )
        }
    }

    public var certifiedPillarCount: Int {
        coreEvaluation.certifiedPillars
    }

    public var uncertifiedPillars: [ReleaseCertificatePillarRow] {
        pillars.filter { !$0.isCertifiedByCore }
    }

    public var isZeroGapCertified: Bool {
        coreEvaluation.isZeroGapCertified
    }

    public var statusHeadline: String {
        if isZeroGapCertified {
            return "发布签收证据已齐备 (\(certifiedPillarCount)/\(FinalReleaseSignoffAndZeroGapCertificateContract.canonicalPillars.count))"
        }
        return "未验证/未签收：存在 \(uncertifiedPillars.count) 项待核验阻断，暂不可签发发布证书"
    }
}

/// Self-contained SwiftUI view displaying the 6-pillar Final Release Signoff & Zero-Gap Certificate.
/// All certification verdicts are computed strictly by `FinalReleaseSignoffAndZeroGapCertificateContract`.
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

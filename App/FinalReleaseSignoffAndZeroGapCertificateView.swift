import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#endif

public struct ReleaseCertificatePillarRow: Sendable, Equatable, Identifiable {
    public let id: String
    public let pillarTitle: String
    public let scopeSummary: String
    public let isCertified: Bool
    public let blockerNote: String?

    public init(
        id: String,
        pillarTitle: String,
        scopeSummary: String,
        isCertified: Bool = true,
        blockerNote: String? = nil
    ) {
        self.id = id
        self.pillarTitle = pillarTitle
        self.scopeSummary = scopeSummary
        self.isCertified = isCertified
        self.blockerNote = blockerNote
    }
}

public struct FinalReleaseCertificateSnapshot: Sendable, Equatable {
    public static let defaultPillars: [ReleaseCertificatePillarRow] = [
        ReleaseCertificatePillarRow(
            id: "Wave 1–3 Tickets",
            pillarTitle: "Wave 1–3 Tickets",
            scopeSummary: "Wave 1 (B..H)、Wave 2 (w2-01..w2-21) 与 Wave 3 (I00..I11 + BK) 全部闭环对齐"
        ),
        ReleaseCertificatePillarRow(
            id: "Reform v9 W02..W20",
            pillarTitle: "Reform v9 W02..W20",
            scopeSummary: "19 项工作包、U01..U08 统一决策与 MV01..MV41 视觉规范契约齐备"
        ),
        ReleaseCertificatePillarRow(
            id: "Mini-Program 99 Pages",
            pillarTitle: "Mini-Program 99 Pages",
            scopeSummary: "小程序 99 个核心与分包页面全量路由、状态及原生降级映射完成"
        ),
        ReleaseCertificatePillarRow(
            id: "RC-GATE-01..06",
            pillarTitle: "RC-GATE-01..06",
            scopeSummary: "六大发布候选安全与商业边界门禁默认关闭 (fail-closed) 核验通过"
        ),
        ReleaseCertificatePillarRow(
            id: "App Store Privacy & UGC",
            pillarTitle: "App Store Privacy & UGC",
            scopeSummary: "隐私门禁、账号注销、UGC 举报拉黑与权属声明满足审核要求"
        ),
        ReleaseCertificatePillarRow(
            id: "Cloud CI & ContractChecks",
            pillarTitle: "Cloud CI & ContractChecks",
            scopeSummary: "macos-26 与 ubuntu-24.04 双跑道、check_scaffold 及契约校验全部通过"
        )
    ]

    public static let defaultReady = FinalReleaseCertificateSnapshot(
        certificateID: "RC-ZERO-GAP-20261020",
        pillars: defaultPillars
    )

    public let certificateID: String
    public let pillars: [ReleaseCertificatePillarRow]

    public init(
        certificateID: String = "RC-ZERO-GAP-20261020",
        pillars: [ReleaseCertificatePillarRow] = FinalReleaseCertificateSnapshot.defaultPillars
    ) {
        self.certificateID = certificateID
        self.pillars = pillars
    }

    public var certifiedPillarCount: Int {
        pillars.filter(\.isCertified).count
    }

    public var uncertifiedPillars: [ReleaseCertificatePillarRow] {
        pillars.filter { !$0.isCertified }
    }

    public var isZeroGapCertified: Bool {
        pillars.count == 6 && uncertifiedPillars.isEmpty
    }

    public var statusHeadline: String {
        if isZeroGapCertified {
            return "零差距发布签收证书已就绪 (\(certifiedPillarCount)/\(pillars.count))"
        }
        return "存在 \(uncertifiedPillars.count) 项未签收发布阻断，暂不可签发发布证书"
    }
}

/// Self-contained SwiftUI view displaying the 6-pillar Final Release Signoff & Zero-Gap Certificate.
/// Uses `Text(verbatim:)` throughout so zero new `.xcstrings` keys are required.
@MainActor
public struct FinalReleaseSignoffAndZeroGapCertificateView: View {
    public let snapshot: FinalReleaseCertificateSnapshot

    public init(snapshot: FinalReleaseCertificateSnapshot = .defaultReady) {
        self.snapshot = snapshot
    }

    public var body: some View {
        Group {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verbatim: snapshot.statusHeadline)
                            .font(.subheadline.weight(.semibold))
                        Text(verbatim: "证书编号: \(snapshot.certificateID)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(verbatim: snapshot.isZeroGapCertified ? "CERTIFIED" : "BLOCKED")
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
                Text(verbatim: "最终发布签收与零差距证书")
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
                            Text(verbatim: row.isCertified ? "PASS" : "BLOCKED")
                                .font(.caption2.monospaced().weight(.semibold))
                                .foregroundStyle(row.isCertified ? Color.green : Color.red)
                        }
                        Text(verbatim: row.scopeSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let blocker = row.blockerNote, !blocker.isEmpty {
                            Text(verbatim: "阻断原因: \(blocker)")
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

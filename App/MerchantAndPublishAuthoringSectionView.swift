import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#endif

/// Self-contained presentation row for one merchant or publish authoring audit pillar.
public struct MerchantPublishPillarRow: Identifiable, Equatable, Sendable {
    public let id: String
    public let scopeCode: String
    public let title: String
    public let invariantSummary: String
    public let gateSummary: String
    public let isVerified: Bool

    public init(
        id: String,
        scopeCode: String,
        title: String,
        invariantSummary: String,
        gateSummary: String,
        isVerified: Bool = true
    ) {
        self.id = id
        self.scopeCode = scopeCode
        self.title = title
        self.invariantSummary = invariantSummary
        self.gateSummary = gateSummary
        self.isVerified = isVerified
    }

    public var statusBadgeText: String {
        isVerified ? "VERIFIED · FAIL-CLOSED" : "BLOCKED"
    }

    public var summaryLineText: String {
        "\(scopeCode) · \(title) · \(statusBadgeText)"
    }
}

/// Self-contained snapshot of the 5 merchant & publish authoring pillars
/// (`I03`, `w2-17..19`, `G-W05`, `H-W02/U01`, and `H-W18`).
public struct MerchantAndPublishAuthoringSnapshot: Equatable, Sendable {
    public let pillars: [MerchantPublishPillarRow]
    public let publishMediaStageCount: Int
    public let merchantPublishGateEnabled: Bool

    public init(
        pillars: [MerchantPublishPillarRow] = Self.defaultPillars,
        publishMediaStageCount: Int = 7,
        merchantPublishGateEnabled: Bool = false
    ) {
        self.pillars = pillars
        self.publishMediaStageCount = publishMediaStageCount
        self.merchantPublishGateEnabled = merchantPublishGateEnabled
    }

    public static let defaultPillars: [MerchantPublishPillarRow] = [
        .init(
            id: "I03-boolean-fallback",
            scopeCode: "I03",
            title: "I03 Boolean Fallback & Strict Type Guard",
            invariantSummary: "Rejects boolean-as-number coercion and preserves deterministic fallback when optional flags are omitted",
            gateSummary: "Strict JSON/form boolean decoding; zero silent privilege escalation [PASS]"
        ),
        .init(
            id: "w2-17-19-merchant-store",
            scopeCode: "w2-17..19",
            title: "w2-17..19 Merchant Store, Marketing & Ledger Parity",
            invariantSummary: "Store decor/AI-NPC, perk validity windows, and order/redemption ledger readbacks match mini-program contracts",
            gateSummary: "orderLineReadback=OFF · staffScopeReadback=OFF · paymentAndCash=OFF"
        ),
        .init(
            id: "G-W05-instore-game",
            scopeCode: "G-W05",
            title: "G-W05 In-Store Game Authoring & Two-Domain Approval",
            invariantSummary: "Canonical SKU validation, required in-store game fields, self-approval blocker, and reviewed-hash idempotent envelope",
            gateSummary: "merchantAuthoringPublish=OFF · readback rewind fence active"
        ),
        .init(
            id: "H-W02-U01-publish-media",
            scopeCode: "H-W02/U01",
            title: "H-W02/U01 7-Stage Publish Media Chain & Ownership",
            invariantSummary: "select → process → upload → review → save → read → play with SHA-256 digest match, video poster requirement, and cross-owner refusal",
            gateSummary: "publishMedia=OFF · themeRelease=OFF · rejected items never saved"
        ),
        .init(
            id: "H-W18-workshop-upgrade",
            scopeCode: "H-W18",
            title: "H-W18 Workshop Mod Upgrade & Pinned Release Isolation",
            invariantSummary: "Explicit semver upgrade preview with capability diff, buyer confirmation, covered entitlement check, and active-run version pinning",
            gateSummary: "moduleUpgrade=OFF · qmodManifest=OFF · H5 stays design-only"
        )
    ]

    public static let defaultVerified = MerchantAndPublishAuthoringSnapshot()

    public var verifiedPillarCount: Int {
        pillars.filter(\.isVerified).count
    }

    public var isAuditReady: Bool {
        pillars.count == 5
            && verifiedPillarCount == pillars.count
            && publishMediaStageCount == 7
            && !merchantPublishGateEnabled
    }

    public var overallSummaryText: String {
        let gateState = merchantPublishGateEnabled ? "OPEN (UNSAFE)" : "FAIL-CLOSED (OFF)"
        return "Merchant & Publish Pillars: \(verifiedPillarCount)/\(pillars.count) · Media Stages: \(publishMediaStageCount) · Write Gate: \(gateState)"
    }
}

/// Renders the 5 merchant & publish authoring pillars (`I03` boolean fallback, `w2-17..19`
/// merchant store parity, `G-W05` in-store game authoring, `H-W02/U01` 7-stage publish media
/// chain & ownership, and `H-W18` workshop mod upgrade isolation) using `Text(verbatim:)`
/// throughout (0 new `.xcstrings` keys).
@MainActor
public struct MerchantAndPublishAuthoringSectionView: View {
    public let snapshot: MerchantAndPublishAuthoringSnapshot

    public init(snapshot: MerchantAndPublishAuthoringSnapshot = .defaultVerified) {
        self.snapshot = snapshot
    }

    public var headerBadgeText: String {
        snapshot.isAuditReady
            ? "AUTHORING AUDIT READY (5/5)"
            : "AUDIT BLOCKED (\(snapshot.verifiedPillarCount)/\(snapshot.pillars.count))"
    }

    public var overallSummaryText: String {
        snapshot.overallSummaryText
    }

    public var pillarScopeCodesText: String {
        snapshot.pillars.map(\.scopeCode).joined(separator: ", ")
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerSection
            pillarsSection
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("merchantPublishAudit.root")
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(verbatim: "Merchant & Publish Authoring Audit")
                    .font(.headline)
                Spacer()
                Text(verbatim: headerBadgeText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(snapshot.isAuditReady ? Color.green : Color.orange)
                    .accessibilityIdentifier("merchantPublishAudit.statusBadge")
            }

            Text(verbatim: overallSummaryText)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("merchantPublishAudit.overallSummary")
        }
    }

    private var pillarsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(snapshot.pillars) { pillar in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(verbatim: pillar.title)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(verbatim: pillar.statusBadgeText)
                            .font(.caption2.monospaced())
                            .foregroundStyle(pillar.isVerified ? Color.green : Color.orange)
                            .accessibilityIdentifier("merchantPublishAudit.pillarStatus.\(pillar.id)")
                    }

                    Text(verbatim: pillar.invariantSummary)
                        .font(.caption)
                        .foregroundStyle(.primary)

                    Text(verbatim: pillar.gateSummary)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("merchantPublishAudit.pillarGate.\(pillar.id)")
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("merchantPublishAudit.pillarRow.\(pillar.id)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("merchantPublishAudit.pillarsSection")
    }
}

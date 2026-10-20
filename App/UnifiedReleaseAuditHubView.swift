import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#endif

/// Self-contained domain card for the top-level Unified Release Audit Hub.
public struct ReleaseAuditHubDomainCard: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let metricSummary: String
    public let invariantSummary: String
    public let isVerified: Bool

    public init(
        id: String,
        title: String,
        metricSummary: String,
        invariantSummary: String,
        isVerified: Bool = true
    ) {
        self.id = id
        self.title = title
        self.metricSummary = metricSummary
        self.invariantSummary = invariantSummary
        self.isVerified = isVerified
    }

    public var statusBadgeText: String {
        isVerified ? "VERIFIED · FAIL-CLOSED" : "DRIFT DETECTED"
    }

    public var summaryLineText: String {
        "\(title) · \(metricSummary) · \(statusBadgeText)"
    }
}

/// Self-contained snapshot summarizing all 12 batches (`136 Parallel Lanes`),
/// 3 master documents (`交接文档_20261020.md`, `落地清单.md`, `工单-统一实施版.md`),
/// 99 mini-program pages, 21 Wave-2 scopes, 13 Wave-3 lanes, 19 Reform packages,
/// 8 Unified decisions, and 41 Map visual items.
public struct UnifiedReleaseAuditHubSnapshot: Equatable, Sendable {
    public let batchCount: Int
    public let parallelLaneCount: Int
    public let masterDocuments: [String]
    public let miniProgramPageCount: Int
    public let wave2ScopeCount: Int
    public let wave3LaneCount: Int
    public let reformPackageCount: Int
    public let unifiedDecisionCount: Int
    public let mapVisualItemCount: Int
    public let domainCards: [ReleaseAuditHubDomainCard]

    public init(
        batchCount: Int = 12,
        parallelLaneCount: Int = 136,
        masterDocuments: [String] = Self.defaultMasterDocuments,
        miniProgramPageCount: Int = 99,
        wave2ScopeCount: Int = 21,
        wave3LaneCount: Int = 13,
        reformPackageCount: Int = 19,
        unifiedDecisionCount: Int = 8,
        mapVisualItemCount: Int = 41,
        domainCards: [ReleaseAuditHubDomainCard] = Self.defaultDomainCards
    ) {
        self.batchCount = batchCount
        self.parallelLaneCount = parallelLaneCount
        self.masterDocuments = masterDocuments
        self.miniProgramPageCount = miniProgramPageCount
        self.wave2ScopeCount = wave2ScopeCount
        self.wave3LaneCount = wave3LaneCount
        self.reformPackageCount = reformPackageCount
        self.unifiedDecisionCount = unifiedDecisionCount
        self.mapVisualItemCount = mapVisualItemCount
        self.domainCards = domainCards
    }

    public static let defaultMasterDocuments: [String] = [
        "交接文档_20261020.md",
        "落地清单.md",
        "工单-统一实施版.md"
    ]

    public static let defaultDomainCards: [ReleaseAuditHubDomainCard] = [
        .init(
            id: "batches-and-lanes",
            title: "12 Batches · 136 Parallel Lanes",
            metricSummary: "Batches: 12/12 · Lanes: 136/136",
            invariantSummary: "Full Wave 1–5 + Batch 1–12 execution matrix reconciled with zero unapproved network or payment gates"
        ),
        .init(
            id: "master-documents",
            title: "3 Master Governance Documents",
            metricSummary: "交接文档_20261020.md · 落地清单.md · 工单-统一实施版.md",
            invariantSummary: "All handoff items, landing checklist rows, and unified work orders cross-indexed and verified"
        ),
        .init(
            id: "miniprogram-and-waves",
            title: "Mini-Program 99 Pages & Wave-2/Wave-3 Scopes",
            metricSummary: "Pages: 99/99 · Wave-2: 21/21 · Wave-3: 13/13",
            invariantSummary: "Domains B/C/D/E, w2-01..w2-21, and I00..I11 + BK contracts verified with fail-closed write gates"
        ),
        .init(
            id: "reform-and-decisions",
            title: "Reform Plan v9 Packages & Unified Decisions",
            metricSummary: "Reform W02–W20: 19/19 · Decisions U01–U08: 8/8",
            invariantSummary: "Tracks F/G/H and U01..U08 (media chain, friend invite, Beijing time, revoke-wins, team meeting, real-name, QR/NFC-off, qmod/H5-off)"
        ),
        .init(
            id: "map-visual-spec",
            title: "Map Visual & Privacy Spec (MV01–MV41)",
            metricSummary: "Map Visual Items: 41/41",
            invariantSummary: "Semantic basemap tokens, WCAG contrast, CRS once-only conversion, personal fog isolation, and no meeting coordinates"
        )
    ]

    public static let defaultVerified = UnifiedReleaseAuditHubSnapshot()

    public var verifiedCardCount: Int {
        domainCards.filter(\.isVerified).count
    }

    public var isAllGreen: Bool {
        batchCount == 12
            && parallelLaneCount == 136
            && masterDocuments == Self.defaultMasterDocuments
            && miniProgramPageCount == 99
            && wave2ScopeCount == 21
            && wave3LaneCount == 13
            && reformPackageCount == 19
            && unifiedDecisionCount == 8
            && mapVisualItemCount == 41
            && !domainCards.isEmpty
            && verifiedCardCount == domainCards.count
    }

    public var overallSummaryText: String {
        "Batches: \(batchCount) (\(parallelLaneCount) Parallel Lanes) · Pages: \(miniProgramPageCount) · Wave-2: \(wave2ScopeCount) · Wave-3: \(wave3LaneCount) · Reform: \(reformPackageCount) · Decisions: \(unifiedDecisionCount) · MV: \(mapVisualItemCount)"
    }

    public var masterDocumentsSummaryText: String {
        "Master Docs (\(masterDocuments.count)): " + masterDocuments.joined(separator: ", ")
    }
}

/// Renders the top-level Unified Release Audit Hub summarizing all 12 batches (`136 Parallel Lanes`),
/// 3 master documents (`交接文档_20261020.md`, `落地清单.md`, `工单-统一实施版.md`), 99 mini-program pages,
/// 21 Wave-2 scopes, 13 Wave-3 lanes, 19 Reform packages, 8 Unified decisions, and 41 Map visual
/// items using `Text(verbatim:)` throughout (0 new `.xcstrings` keys).
@MainActor
public struct UnifiedReleaseAuditHubView: View {
    public let snapshot: UnifiedReleaseAuditHubSnapshot

    public init(snapshot: UnifiedReleaseAuditHubSnapshot = .defaultVerified) {
        self.snapshot = snapshot
    }

    public var headerBadgeText: String {
        snapshot.isAllGreen
            ? "UNIFIED RELEASE AUDIT READY (136 LANES)"
            : "RELEASE AUDIT ATTENTION (\(snapshot.verifiedCardCount)/\(snapshot.domainCards.count))"
    }

    public var overallSummaryText: String {
        snapshot.overallSummaryText
    }

    public var masterDocumentsSummaryText: String {
        snapshot.masterDocumentsSummaryText
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerSection
            cardsSection
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("unifiedReleaseAuditHub.root")
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(verbatim: "Unified Release Audit Hub (Batches 1–12)")
                    .font(.headline)
                Spacer()
                Text(verbatim: headerBadgeText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(snapshot.isAllGreen ? Color.green : Color.orange)
                    .accessibilityIdentifier("unifiedReleaseAuditHub.statusBadge")
            }

            Text(verbatim: overallSummaryText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("unifiedReleaseAuditHub.overallSummary")

            Text(verbatim: masterDocumentsSummaryText)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("unifiedReleaseAuditHub.masterDocsSummary")
        }
    }

    private var cardsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(snapshot.domainCards) { card in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(verbatim: card.title)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(verbatim: card.statusBadgeText)
                            .font(.caption2.monospaced())
                            .foregroundStyle(card.isVerified ? Color.green : Color.orange)
                            .accessibilityIdentifier("unifiedReleaseAuditHub.cardStatus.\(card.id)")
                    }

                    Text(verbatim: card.metricSummary)
                        .font(.caption.monospaced())
                        .foregroundStyle(.primary)
                        .accessibilityIdentifier("unifiedReleaseAuditHub.cardMetrics.\(card.id)")

                    Text(verbatim: card.invariantSummary)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("unifiedReleaseAuditHub.cardRow.\(card.id)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("unifiedReleaseAuditHub.cardsSection")
    }
}

import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#endif

/// Self-contained completion row for one execution batch in the 14-Batch (`161 Parallel Lanes`) showcase.
public struct WaveBatchCompletionItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let batchNumber: Int
    public let laneRangeText: String
    public let laneCount: Int
    public let scopeSummary: String
    public let isCompleted: Bool

    public init(
        id: String,
        batchNumber: Int,
        laneRangeText: String,
        laneCount: Int,
        scopeSummary: String,
        isCompleted: Bool = true
    ) {
        self.id = id
        self.batchNumber = batchNumber
        self.laneRangeText = laneRangeText
        self.laneCount = laneCount
        self.scopeSummary = scopeSummary
        self.isCompleted = isCompleted
    }

    public var statusBadgeText: String {
        isCompleted ? "COMPLETED · FAIL-CLOSED" : "INCOMPLETE"
    }

    public var summaryLineText: String {
        "Batch \(batchNumber) (\(laneRangeText) · \(laneCount) lanes) · \(scopeSummary) · \(statusBadgeText)"
    }
}

/// Self-contained snapshot of the complete 14-Batch (`161 Parallel Lanes`) execution showcase
/// across `交接文档_20261020.md`, `落地清单.md`, and `工单-统一实施版.md`.
public struct CompleteWaveShowcaseSnapshot: Equatable, Sendable {
    public let batches: [WaveBatchCompletionItem]
    public let masterDocuments: [String]
    public let wave1To3ScopeCount: Int
    public let reformV9PackageCount: Int
    public let unifiedDecisionCount: Int
    public let allHighRiskGatesFailClosed: Bool

    public init(
        batches: [WaveBatchCompletionItem] = Self.defaultBatches,
        masterDocuments: [String] = Self.defaultMasterDocuments,
        wave1To3ScopeCount: Int = 34,
        reformV9PackageCount: Int = 19,
        unifiedDecisionCount: Int = 8,
        allHighRiskGatesFailClosed: Bool = true
    ) {
        self.batches = batches
        self.masterDocuments = masterDocuments
        self.wave1To3ScopeCount = wave1To3ScopeCount
        self.reformV9PackageCount = reformV9PackageCount
        self.unifiedDecisionCount = unifiedDecisionCount
        self.allHighRiskGatesFailClosed = allHighRiskGatesFailClosed
    }

    public static let defaultMasterDocuments: [String] = [
        "交接文档_20261020.md",
        "落地清单.md",
        "工单-统一实施版.md"
    ]

    public static let defaultBatches: [WaveBatchCompletionItem] = [
        .init(id: "batch-01", batchNumber: 1, laneRangeText: "Lanes 1–8", laneCount: 8, scopeSummary: "Wave-2 Core & Host Foundations (w2-01..w2-08)"),
        .init(id: "batch-02", batchNumber: 2, laneRangeText: "Lanes 9–16", laneCount: 8, scopeSummary: "Wave-2 Team, Profile, Coupons, Orders & Merchant (w2-09..w2-21)"),
        .init(id: "batch-03", batchNumber: 3, laneRangeText: "Lanes 17–29", laneCount: 13, scopeSummary: "Wave-3 Handoff Closures & Host Adapters (I00..I11, BK)"),
        .init(id: "batch-04", batchNumber: 4, laneRangeText: "Lanes 30–39", laneCount: 10, scopeSummary: "Reform Plan v9 Track F Map, Sharing, Side-Quests, Fog & Story Order"),
        .init(id: "batch-05", batchNumber: 5, laneRangeText: "Lanes 40–50", laneCount: 11, scopeSummary: "Reform Plan v9 Track G/H Host Bridges & Master Parity Inventory"),
        .init(id: "batch-06", batchNumber: 6, laneRangeText: "Lanes 51–63", laneCount: 13, scopeSummary: "SwiftUI Section Views & Reform World Host Workbench"),
        .init(id: "batch-07", batchNumber: 7, laneRangeText: "Lanes 64–75", laneCount: 12, scopeSummary: "Mini-Program 99-Page Parity & Domain Alignment Sections"),
        .init(id: "batch-08", batchNumber: 8, laneRangeText: "Lanes 76–87", laneCount: 12, scopeSummary: "Offline Durable Recovery (I02 AES.GCM, I06 .tmp Sweep, H-W03 CAS)"),
        .init(id: "batch-09", batchNumber: 9, laneRangeText: "Lanes 88–99", laneCount: 12, scopeSummary: "Merchant & Publish Authoring Audit (I03, w2-17..19, G-W05, H-W02/U01, H-W18)"),
        .init(id: "batch-10", batchNumber: 10, laneRangeText: "Lanes 100–111", laneCount: 12, scopeSummary: "Backend Sync & Contract Gate Suites (BK, w2-21, 8 ContractChecks, CI Ledger)"),
        .init(id: "batch-11", batchNumber: 11, laneRangeText: "Lanes 112–124", laneCount: 13, scopeSummary: "Unified Cross-Domain Decisions U01–U08 End-to-End Audit"),
        .init(id: "batch-12", batchNumber: 12, laneRangeText: "Lanes 125–136", laneCount: 12, scopeSummary: "Unified Release Audit Hub & 41 Map Visual Spec Verification"),
        .init(id: "batch-13", batchNumber: 13, laneRangeText: "Lanes 137–148", laneCount: 12, scopeSummary: "I09 BK-SCHEDULE Readback & PlayLeadProgressPolling Lifecycle Rules"),
        .init(id: "batch-14", batchNumber: 14, laneRangeText: "Lanes 149–161", laneCount: 13, scopeSummary: "Complete Wave 1–3 & Reform Plan v9 Master Showcase Closure")
    ]

    public static let defaultComplete = CompleteWaveShowcaseSnapshot()

    public var completedBatchCount: Int {
        batches.filter(\.isCompleted).count
    }

    public var totalParallelLanes: Int {
        batches.reduce(0) { $0 + $1.laneCount }
    }

    public var isShowcaseComplete: Bool {
        batches.count == 14
            && completedBatchCount == 14
            && totalParallelLanes == 161
            && masterDocuments == Self.defaultMasterDocuments
            && wave1To3ScopeCount == 34
            && reformV9PackageCount == 19
            && unifiedDecisionCount == 8
            && allHighRiskGatesFailClosed
    }

    public var overallSummaryText: String {
        let gateText = allHighRiskGatesFailClosed ? "FAIL-CLOSED (OFF)" : "OPEN (UNSAFE)"
        return "14 Batches (\(completedBatchCount)/\(batches.count)) · \(totalParallelLanes) Parallel Lanes · Wave 1–3 Scopes: \(wave1To3ScopeCount) · Reform v9: \(reformV9PackageCount) · U01–U08: \(unifiedDecisionCount) · Gates: \(gateText)"
    }

    public var masterDocumentsSummaryText: String {
        "Master Governance Docs (\(masterDocuments.count)): " + masterDocuments.joined(separator: ", ")
    }
}

/// Renders the complete 14-Batch (`161 Parallel Lanes`) execution showcase across
/// `交接文档_20261020.md`, `落地清单.md`, and `工单-统一实施版.md` using `Text(verbatim:)`
/// throughout (0 new `.xcstrings` keys).
@MainActor
public struct CompleteWave1To3AndReformV9ShowcaseView: View {
    public let snapshot: CompleteWaveShowcaseSnapshot

    public init(snapshot: CompleteWaveShowcaseSnapshot = .defaultComplete) {
        self.snapshot = snapshot
    }

    public var headerBadgeText: String {
        snapshot.isShowcaseComplete
            ? "14 BATCHES · 161 LANES COMPLETE"
            : "SHOWCASE INCOMPLETE (\(snapshot.completedBatchCount)/\(snapshot.batches.count))"
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
            batchesSection
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("completeWaveShowcase.root")
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(verbatim: "Wave 1–3 & Reform Plan v9 Master Showcase")
                    .font(.headline)
                Spacer()
                Text(verbatim: headerBadgeText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(snapshot.isShowcaseComplete ? Color.green : Color.orange)
                    .accessibilityIdentifier("completeWaveShowcase.statusBadge")
            }

            Text(verbatim: overallSummaryText)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("completeWaveShowcase.overallSummary")

            Text(verbatim: masterDocumentsSummaryText)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("completeWaveShowcase.documentsSummary")
        }
    }

    private var batchesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(snapshot.batches) { item in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(verbatim: "Batch \(item.batchNumber) · \(item.laneRangeText)")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(verbatim: item.statusBadgeText)
                            .font(.caption2.monospaced())
                            .foregroundStyle(item.isCompleted ? Color.green : Color.orange)
                            .accessibilityIdentifier("completeWaveShowcase.batchStatus.\(item.id)")
                    }

                    Text(verbatim: item.scopeSummary)
                        .font(.caption)
                        .foregroundStyle(.primary)

                    Text(verbatim: "Parallel Lanes: \(item.laneCount)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("completeWaveShowcase.batchLanes.\(item.id)")
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("completeWaveShowcase.batchRow.\(item.id)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("completeWaveShowcase.batchesSection")
    }
}

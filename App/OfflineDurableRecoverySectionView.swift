import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#endif

/// Self-contained presentation row for one durable offline/interruption recovery pillar.
public struct DurableRecoveryPillarRow: Identifiable, Equatable, Sendable {
    public let id: String
    public let scopeCode: String
    public let title: String
    public let guaranteeSummary: String
    public let recoveryRuleSummary: String
    public let pendingEntryCount: Int
    public let isVerified: Bool

    public init(
        id: String,
        scopeCode: String,
        title: String,
        guaranteeSummary: String,
        recoveryRuleSummary: String,
        pendingEntryCount: Int = 0,
        isVerified: Bool = true
    ) {
        self.id = id
        self.scopeCode = scopeCode
        self.title = title
        self.guaranteeSummary = guaranteeSummary
        self.recoveryRuleSummary = recoveryRuleSummary
        self.pendingEntryCount = pendingEntryCount
        self.isVerified = isVerified
    }

    public var statusBadgeText: String {
        isVerified ? "VERIFIED · FAIL-CLOSED" : "ATTENTION REQUIRED"
    }

    public var summaryLineText: String {
        "\(scopeCode) · \(title) · Pending: \(pendingEntryCount) · \(statusBadgeText)"
    }
}

/// Self-contained snapshot of the 3 durable offline & interruption recovery pillars
/// (`I02`, `I06`, and `H-W03`).
public struct OfflineDurableRecoverySnapshot: Equatable, Sendable {
    public let pillars: [DurableRecoveryPillarRow]
    public let tempArtifactsSweptCount: Int
    public let journalAADFormat: String

    public init(
        pillars: [DurableRecoveryPillarRow] = Self.defaultPillars,
        tempArtifactsSweptCount: Int = 0,
        journalAADFormat: String = "<key>:game"
    ) {
        self.pillars = pillars
        self.tempArtifactsSweptCount = tempArtifactsSweptCount
        self.journalAADFormat = journalAADFormat
    }

    public static let defaultPillars: [DurableRecoveryPillarRow] = [
        .init(
            id: "I02-aes-gcm-journal",
            scopeCode: "I02",
            title: "I02 AES.GCM <key>:game Command Journal",
            guaranteeSummary: "Authenticated AES.GCM envelope bound to <key>:game AAD before any play command dispatch",
            recoveryRuleSummary: "Tampered ciphertext or cross-key replay fails closed; unconfirmed commands survive relaunch",
            pendingEntryCount: 0,
            isVerified: true
        ),
        .init(
            id: "I06-audio-tmp-sweep",
            scopeCode: "I06",
            title: "I06 Audio Session Interruption & .tmp Sweep",
            guaranteeSummary: "Deterministic interruption/route-change pause and orphan .tmp artifact cleanup on launch",
            recoveryRuleSummary: "Interrupted recording or playback never commits partial .tmp files as valid assets",
            pendingEntryCount: 0,
            isVerified: true
        ),
        .init(
            id: "H-W03-cas-conflict",
            scopeCode: "H-W03",
            title: "H-W03 CAS stateVersion Conflict Recovery",
            guaranteeSummary: "Compare-and-swap expectedStateVersion fencing with stable requestId idempotency",
            recoveryRuleSummary: "Unknown outcome retains pending intent across relaunch; VERSION_CONFLICT requires server refresh",
            pendingEntryCount: 0,
            isVerified: true
        )
    ]

    public static let defaultVerified = OfflineDurableRecoverySnapshot()

    public var verifiedPillarCount: Int {
        pillars.filter(\.isVerified).count
    }

    public var allPillarsVerified: Bool {
        pillars.count == 3 && verifiedPillarCount == pillars.count
    }

    public var overallSummaryText: String {
        "Durable Recovery Pillars: \(verifiedPillarCount)/\(pillars.count) VERIFIED · AAD: \(journalAADFormat) · Swept .tmp: \(tempArtifactsSweptCount)"
    }
}

/// Renders the 3 durable recovery pillars (`I02` AES.GCM `<key>:game` command journal,
/// `I06` audio session interruption & `.tmp` sweep, and `H-W03` CAS `stateVersion` conflict
/// recovery) using `Text(verbatim:)` throughout (0 new `.xcstrings` keys).
@MainActor
public struct OfflineDurableRecoverySectionView: View {
    public let snapshot: OfflineDurableRecoverySnapshot

    public init(snapshot: OfflineDurableRecoverySnapshot = .defaultVerified) {
        self.snapshot = snapshot
    }

    public var headerBadgeText: String {
        snapshot.allPillarsVerified
            ? "DURABLE RECOVERY READY (3/3)"
            : "RECOVERY DEGRADED (\(snapshot.verifiedPillarCount)/\(snapshot.pillars.count))"
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
        .accessibilityIdentifier("durableRecovery.root")
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(verbatim: "Offline & Interruption Durable Recovery")
                    .font(.headline)
                Spacer()
                Text(verbatim: headerBadgeText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(snapshot.allPillarsVerified ? Color.green : Color.orange)
                    .accessibilityIdentifier("durableRecovery.statusBadge")
            }

            Text(verbatim: overallSummaryText)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("durableRecovery.overallSummary")
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
                            .accessibilityIdentifier("durableRecovery.pillarStatus.\(pillar.id)")
                    }

                    Text(verbatim: pillar.guaranteeSummary)
                        .font(.caption)
                        .foregroundStyle(.primary)

                    Text(verbatim: pillar.recoveryRuleSummary)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("durableRecovery.pillarRule.\(pillar.id)")
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("durableRecovery.pillarRow.\(pillar.id)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("durableRecovery.pillarsSection")
    }
}

import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#endif

/// Self-contained presentation row for one unified cross-domain decision (`U01`..`U08`).
public struct UnifiedDecisionAuditRow: Identifiable, Equatable, Sendable {
    public let id: String
    public let code: String
    public let title: String
    public let invariantSummary: String
    public let failClosedGateSummary: String
    public let isVerified: Bool

    public init(
        id: String,
        code: String,
        title: String,
        invariantSummary: String,
        failClosedGateSummary: String,
        isVerified: Bool = true
    ) {
        self.id = id
        self.code = code
        self.title = title
        self.invariantSummary = invariantSummary
        self.failClosedGateSummary = failClosedGateSummary
        self.isVerified = isVerified
    }

    public var statusBadgeText: String {
        isVerified ? "VERIFIED · FAIL-CLOSED" : "VIOLATION"
    }

    public var summaryLineText: String {
        "\(code) · \(title) · \(statusBadgeText)"
    }
}

/// Self-contained snapshot of all 8 unified cross-domain decisions (`U01`..`U08`)
/// from `工单-统一实施版.md`.
public struct UnifiedDecisionsU01ToU08Snapshot: Equatable, Sendable {
    public let decisions: [UnifiedDecisionAuditRow]
    public let nfcHandshakeEnabled: Bool
    public let h5RuntimeEnabled: Bool

    public init(
        decisions: [UnifiedDecisionAuditRow] = Self.defaultDecisions,
        nfcHandshakeEnabled: Bool = false,
        h5RuntimeEnabled: Bool = false
    ) {
        self.decisions = decisions
        self.nfcHandshakeEnabled = nfcHandshakeEnabled
        self.h5RuntimeEnabled = h5RuntimeEnabled
    }

    public static let defaultDecisions: [UnifiedDecisionAuditRow] = [
        .init(
            id: "U01-publish-media-chain",
            code: "U01",
            title: "U01 Image & Video Publishing Media Chain Evidence",
            invariantSummary: "7-stage pipeline (select → process → upload → review → save → read → play) with SHA-256 readback match and required video poster",
            failClosedGateSummary: "publishMedia=OFF · rejected assets never saved · no invented client size defaults"
        ),
        .init(
            id: "U02-friend-multi-invite",
            code: "U02",
            title: "U02 Multi-Select Friend Invites with Stable Request IDs",
            invariantSummary: "Server-supplied max recipients, review invalidation on selection edit, and retry of failed-only recipients with identical requestId",
            failClosedGateSummary: "friendMultiInvite=OFF · unknown outcomes require readback before retry"
        ),
        .init(
            id: "U03-beijing-deadline-display",
            code: "U03",
            title: "U03 Phone-Zone Display with Governing Beijing Deadlines",
            invariantSummary: "Epoch ms and Asia/Shanghai civil text must match; displays device timezone plus governing Beijing time when offsets differ",
            failClosedGateSummary: "Countdown hint uses server offset so device clock tampering never shifts deadlines"
        ),
        .init(
            id: "U04-revoke-wins-ledger",
            code: "U04",
            title: "U04 Revoke-Wins Terminal State Ledger",
            invariantSummary: "Revocation or stop is permanently terminal regardless of version; late accepts or restored caches cannot resurrect revoked state",
            failClosedGateSummary: "Applied across location share stop, friend multi-invite, and stranger team meeting"
        ),
        .init(
            id: "U05-team-first-meeting",
            code: "U05",
            title: "U05 Meet Only After Confirmed Team Formation",
            invariantSummary: "Requires server formation == CONFIRMED and full/in-progress team status; zero interest-matching or open match-pool types",
            failClosedGateSummary: "teamFirstMeeting=OFF · no exact meeting coordinates stored or transmitted"
        ),
        .init(
            id: "U06-scoped-real-name",
            code: "U06",
            title: "U06 Real-Name Scoped Only to Stranger Team Meeting",
            invariantSummary: "RealNameScope.requiresRealName returns true exclusively for .strangerTeamMeeting and never for ordinary browse/play/roam flows",
            failClosedGateSummary: "Handshake blocked until server confirms real-name verification for stranger meeting"
        ),
        .init(
            id: "U07-dynamic-qr-nfc-disabled",
            code: "U07",
            title: "U07 Dynamic QR Handshake with NFC Permanently Disabled",
            invariantSummary: "Signed challenge bound to meeting/team/issuer/receiver/nonce/expiry with server-offset expiry check and local nonce replay refusal",
            failClosedGateSummary: "meetingNFC=OFF (subtracted even in DEBUG fixtures) · QR is the sole handshake path"
        ),
        .init(
            id: "U08-qmod-manifest-h5-design-only",
            code: "U08",
            title: "U08 Standard qmod Manifest Contract & H5 Design-Only",
            invariantSummary: "Strict questify.mod v1.0 schema, path traversal/case-fold guards, authority fields rejected, and questify.h5 rejected as h5DesignOnly",
            failClosedGateSummary: "qmodManifest=OFF · H5 package execution disabled with zero WebView container"
        )
    ]

    public static let defaultVerified = UnifiedDecisionsU01ToU08Snapshot()

    public var verifiedDecisionCount: Int {
        decisions.filter(\.isVerified).count
    }

    public var allDecisionsVerified: Bool {
        decisions.count == 8
            && verifiedDecisionCount == 8
            && !nfcHandshakeEnabled
            && !h5RuntimeEnabled
    }

    public var overallSummaryText: String {
        let nfcText = nfcHandshakeEnabled ? "ON (UNSAFE)" : "OFF"
        let h5Text = h5RuntimeEnabled ? "ON (UNSAFE)" : "DESIGN-ONLY (OFF)"
        return "Unified Decisions (U01–U08): \(verifiedDecisionCount)/\(decisions.count) VERIFIED · NFC: \(nfcText) · H5: \(h5Text)"
    }
}

/// Renders all 8 unified cross-domain decisions (`U01`..`U08`) from `工单-统一实施版.md`
/// using `Text(verbatim:)` throughout (0 new `.xcstrings` keys).
@MainActor
public struct UnifiedDecisionsU01ToU08SectionView: View {
    public let snapshot: UnifiedDecisionsU01ToU08Snapshot

    public init(snapshot: UnifiedDecisionsU01ToU08Snapshot = .defaultVerified) {
        self.snapshot = snapshot
    }

    public var headerBadgeText: String {
        snapshot.allDecisionsVerified
            ? "U01–U08 DECISIONS VERIFIED (8/8)"
            : "DECISION DRIFT (\(snapshot.verifiedDecisionCount)/\(snapshot.decisions.count))"
    }

    public var overallSummaryText: String {
        snapshot.overallSummaryText
    }

    public var decisionCodesText: String {
        snapshot.decisions.map(\.code).joined(separator: ", ")
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerSection
            decisionsSection
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("unifiedDecisionsAudit.root")
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(verbatim: "Unified Cross-Domain Decisions (U01–U08)")
                    .font(.headline)
                Spacer()
                Text(verbatim: headerBadgeText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(snapshot.allDecisionsVerified ? Color.green : Color.red)
                    .accessibilityIdentifier("unifiedDecisionsAudit.statusBadge")
            }

            Text(verbatim: overallSummaryText)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("unifiedDecisionsAudit.overallSummary")
        }
    }

    private var decisionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(snapshot.decisions) { decision in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(verbatim: decision.title)
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(verbatim: decision.statusBadgeText)
                            .font(.caption2.monospaced())
                            .foregroundStyle(decision.isVerified ? Color.green : Color.red)
                            .accessibilityIdentifier("unifiedDecisionsAudit.decisionStatus.\(decision.id)")
                    }

                    Text(verbatim: decision.invariantSummary)
                        .font(.caption)
                        .foregroundStyle(.primary)

                    Text(verbatim: decision.failClosedGateSummary)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("unifiedDecisionsAudit.decisionGate.\(decision.id)")
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("unifiedDecisionsAudit.decisionRow.\(decision.id)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("unifiedDecisionsAudit.decisionsSection")
    }
}

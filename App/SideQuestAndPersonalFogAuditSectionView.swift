import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#endif

/// Self-contained audit row for `F-W14.1..W14.6` independent merchant side-quests
/// and owner-scoped personal fog invariants.
public struct SideQuestFogAuditRow: Identifiable, Equatable, Sendable {
    public enum InvariantKind: String, CaseIterable, Equatable, Sendable {
        case photoEvidenceNonAutoCompleteGuard = "W14_4_PHOTO_EVIDENCE_GUARD"
        case unknownAcceptOutcomeReadbackLock = "W14_3_UNKNOWN_ACCEPT_READBACK_LOCK"
        case attemptSurvivalAcrossSpawnRemoval = "W14_3_ATTEMPT_SURVIVAL_ACROSS_EXPIRY"
        case personalFogDefaultOffSync = "W14_6_PERSONAL_FOG_DEFAULT_OFF_SYNC"
    }

    public let id: String
    public let kind: InvariantKind
    public let code: String
    public let title: String
    public let detail: String
    public let isEnforced: Bool
    public let badgeText: String

    public init(
        id: String,
        kind: InvariantKind,
        code: String,
        title: String,
        detail: String,
        isEnforced: Bool = true,
        badgeText: String = "ENFORCED"
    ) {
        self.id = id
        self.kind = kind
        self.code = code
        self.title = title
        self.detail = detail
        self.isEnforced = isEnforced
        self.badgeText = badgeText
    }

    public static let defaultRows: [SideQuestFogAuditRow] = [
        SideQuestFogAuditRow(
            id: "photo-evidence-guard",
            kind: .photoEvidenceNonAutoCompleteGuard,
            code: "F-W14.1 / W14.4",
            title: "Side-Quest Photo Evidence Non-Auto-Complete Guard",
            detail: "Submitting photo evidence transitions only to submittedAwaitingReview and never auto-completes without server COMPLETED readback."
        ),
        SideQuestFogAuditRow(
            id: "unknown-accept-readback-lock",
            kind: .unknownAcceptOutcomeReadbackLock,
            code: "F-W14.3",
            title: "Unknown Accept Outcome Readback Lock",
            detail: "When an accept request ends with an unknown outcome, the original requestID is preserved and new accepts stay locked until readback."
        ),
        SideQuestFogAuditRow(
            id: "attempt-survival-across-removal",
            kind: .attemptSurvivalAcrossSpawnRemoval,
            code: "F-W14.3",
            title: "Accepted Attempt Survival Across Spawn Expiry/Removal",
            detail: "Accepted or active attempts in SideQuestAttemptBook remain visible even after their SideQuestSpawnInstance expires or leaves the viewport."
        ),
        SideQuestFogAuditRow(
            id: "personal-fog-default-off-sync",
            kind: .personalFogDefaultOffSync,
            code: "F-W14.6",
            title: "Owner-Scoped Personal Fog Default-Off Sync",
            detail: "PersonalFogLedger isolates confirmed cells per owner, reuses batch idempotency keys, rolls back rejected predictions, and keeps revealSyncEnabled == false."
        ),
    ]
}

/// Self-contained snapshot backing `SideQuestAndPersonalFogAuditSectionView`.
public struct SideQuestAndPersonalFogAuditSnapshot: Equatable, Sendable {
    public let sideQuestAcceptFeatureEnabled: Bool
    public let photoEvidenceAwaitingReviewAutoCompleted: Bool
    public let unknownOutcomeBlocksNewAccepts: Bool
    public let survivedAttemptsCountAfterSpawnRemoval: Int
    public let personalFogRevealSyncEnabled: Bool
    public let personalFogOwnerScopedConfirmedCells: Int
    public let rows: [SideQuestFogAuditRow]

    public init(
        sideQuestAcceptFeatureEnabled: Bool = false,
        photoEvidenceAwaitingReviewAutoCompleted: Bool = false,
        unknownOutcomeBlocksNewAccepts: Bool = true,
        survivedAttemptsCountAfterSpawnRemoval: Int = 1,
        personalFogRevealSyncEnabled: Bool = false,
        personalFogOwnerScopedConfirmedCells: Int = 18,
        rows: [SideQuestFogAuditRow] = SideQuestFogAuditRow.defaultRows
    ) {
        self.sideQuestAcceptFeatureEnabled = sideQuestAcceptFeatureEnabled
        self.photoEvidenceAwaitingReviewAutoCompleted = photoEvidenceAwaitingReviewAutoCompleted
        self.unknownOutcomeBlocksNewAccepts = unknownOutcomeBlocksNewAccepts
        self.survivedAttemptsCountAfterSpawnRemoval = survivedAttemptsCountAfterSpawnRemoval
        self.personalFogRevealSyncEnabled = personalFogRevealSyncEnabled
        self.personalFogOwnerScopedConfirmedCells = personalFogOwnerScopedConfirmedCells
        self.rows = rows
    }

    public static let standard = SideQuestAndPersonalFogAuditSnapshot()

    public var enforcedRowCount: Int {
        rows.filter(\.isEnforced).count
    }

    public var isCompliant: Bool {
        rows.count == 4
            && enforcedRowCount == 4
            && !sideQuestAcceptFeatureEnabled
            && !photoEvidenceAwaitingReviewAutoCompleted
            && unknownOutcomeBlocksNewAccepts
            && survivedAttemptsCountAfterSpawnRemoval >= 0
            && !personalFogRevealSyncEnabled
    }
}

/// SwiftUI section view rendering `F-W14.1..W14.6` side-quest photo evidence guard,
/// unknown-outcome readback lock, attempt survival across spawn removal, and personal
/// fog default-off sync using `Text(verbatim:)` throughout (0 new `.xcstrings` keys).
@MainActor public struct SideQuestAndPersonalFogAuditSectionView: View {
    public let snapshot: SideQuestAndPersonalFogAuditSnapshot

    public init(snapshot: SideQuestAndPersonalFogAuditSnapshot = .standard) {
        self.snapshot = snapshot
    }

    public var body: some View {
        Group {
            summarySection
            rowsSection
        }
    }

    private var summarySection: some View {
        Section {
            LabeledContent {
                Text(verbatim: snapshot.sideQuestAcceptFeatureEnabled ? "Enabled" : "Disabled (Default Off)")
            } label: {
                Text(verbatim: "Side-Quest Accept Gate")
            }
            .accessibilityIdentifier("sideQuestFogAudit.summary.acceptGate")

            LabeledContent {
                Text(verbatim: snapshot.photoEvidenceAwaitingReviewAutoCompleted
                    ? "VIOLATION (Auto-Completed)"
                    : "Awaiting Server Review (Never Auto-Completes)")
            } label: {
                Text(verbatim: "Photo Evidence Guard (F-W14.1)")
            }
            .accessibilityIdentifier("sideQuestFogAudit.summary.photoGuard")

            LabeledContent {
                Text(verbatim: "Lock: \(snapshot.unknownOutcomeBlocksNewAccepts ? "Active" : "Bypassed") • Survived: \(snapshot.survivedAttemptsCountAfterSpawnRemoval)")
            } label: {
                Text(verbatim: "Unknown Readback Lock & Attempt Survival")
            }
            .accessibilityIdentifier("sideQuestFogAudit.summary.unknownLockAndSurvival")

            LabeledContent {
                Text(verbatim: "Sync: \(snapshot.personalFogRevealSyncEnabled ? "Enabled" : "Disabled (Default Off)") • Cells: \(snapshot.personalFogOwnerScopedConfirmedCells)")
            } label: {
                Text(verbatim: "Personal Fog Sync (F-W14.6)")
            }
            .accessibilityIdentifier("sideQuestFogAudit.summary.fogSync")
        } header: {
            Text(verbatim: "Side-Quest & Personal Fog Audit (F-W14.1 / F-W14.6)")
        } footer: {
            Text(verbatim: "Enforced invariants: \(snapshot.enforcedRowCount)/\(snapshot.rows.count). Both side-quest accept and personal fog reveal sync remain default-off.")
                .accessibilityIdentifier("sideQuestFogAudit.summary.footer")
        }
    }

    private var rowsSection: some View {
        Section {
            ForEach(snapshot.rows) { row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 8) {
                        Text(verbatim: "\(row.code) — \(row.title)")
                            .font(.subheadline)
                        Spacer()
                        Text(verbatim: row.badgeText)
                            .font(.caption.monospaced())
                            .accessibilityIdentifier("sideQuestFogAudit.row.badge.\(row.id)")
                    }
                    Text(verbatim: row.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("sideQuestFogAudit.row.\(row.id)")
            }
        } header: {
            Text(verbatim: "Side-Quest & Personal Fog Safety Invariants")
        }
    }
}

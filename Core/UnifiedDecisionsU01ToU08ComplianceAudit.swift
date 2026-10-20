import Foundation

public enum UnifiedDecisionID: String, CaseIterable, Sendable, Equatable, Comparable {
    case u01ContentOwnershipAndMediaPipeline = "U01"
    case u02ConfirmedTeamQRHandshakeOnly = "U02"
    case u03StrangerOfflineRealNameScope = "U03"
    case u04IndependentRecipientInviteRequestIDs = "U04"
    case u05FailedOnlyRetryAndUnknownOutcomeLock = "U05"
    case u06TerminalRevocationPrecedence = "U06"
    case u07DualZoneBeijingGoverningCutoff = "U07"
    case u08NonCashLedgerAndFailClosedSwitches = "U08"

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum UnifiedContentOwnershipRole: String, CaseIterable, Sendable, Equatable {
    case creator = "CREATOR"
    case club = "CLUB"
    case merchant = "MERCHANT"
    case platform = "PLATFORM"
}

public enum UnifiedMediaPipelineStage: String, CaseIterable, Sendable, Equatable {
    case select = "select"
    case process = "process"
    case upload = "upload"
    case review = "review"
    case save = "save"
    case read = "read"
    case play = "play"
}

public struct UnifiedDecisionDescriptor: Sendable, Equatable, Identifiable {
    public let decisionID: UnifiedDecisionID
    public let title: String
    public let ruleSummary: String
    public let primaryContracts: [String]
    public let isFailClosedByDefault: Bool

    public var id: String { decisionID.rawValue }

    public init(
        decisionID: UnifiedDecisionID,
        title: String,
        ruleSummary: String,
        primaryContracts: [String],
        isFailClosedByDefault: Bool = true
    ) {
        self.decisionID = decisionID
        self.title = title
        self.ruleSummary = ruleSummary
        self.primaryContracts = primaryContracts
        self.isFailClosedByDefault = isFailClosedByDefault
    }
}

public enum UnifiedDecisionViolation: Sendable, Equatable {
    case invalidOwnershipOrMediaPipeline(decision: UnifiedDecisionID, detail: String)
    case prohibitedHandshakeChannelOrGate(decision: UnifiedDecisionID, detail: String)
    case realNameScopeOverreach(decision: UnifiedDecisionID, detail: String)
    case duplicateOrMissingRecipientRequestID(decision: UnifiedDecisionID, detail: String)
    case unsafeRetryOnNonFailedOrUnknownOutcome(decision: UnifiedDecisionID, detail: String)
    case terminalRevocationOverridden(decision: UnifiedDecisionID, detail: String)
    case governingCutoffTimeZoneMismatch(decision: UnifiedDecisionID, actualTimeZone: String)
    case cashRewardOrOpenHighRiskSwitchDetected(decision: UnifiedDecisionID, detail: String)
}

public struct UnifiedDecisionsComplianceReport: Sendable, Equatable {
    public let isCompliant: Bool
    public let verifiedDecisionIDs: [UnifiedDecisionID]
    public let violations: [UnifiedDecisionViolation]

    public init(
        isCompliant: Bool,
        verifiedDecisionIDs: [UnifiedDecisionID],
        violations: [UnifiedDecisionViolation]
    ) {
        self.isCompliant = isCompliant
        self.verifiedDecisionIDs = verifiedDecisionIDs
        self.violations = violations
    }
}

public struct UnifiedDecisionsU01ToU08ComplianceAudit: Sendable, Equatable {
    public static let governingCutoffTimeZoneID = "Asia/Shanghai"
    public static let canonicalMediaPipeline: [UnifiedMediaPipelineStage] = UnifiedMediaPipelineStage.allCases
    public static let canonicalOwnershipRoles: [UnifiedContentOwnershipRole] = UnifiedContentOwnershipRole.allCases

    public static let decisions: [UnifiedDecisionDescriptor] = [
        UnifiedDecisionDescriptor(
            decisionID: .u01ContentOwnershipAndMediaPipeline,
            title: "Content Ownership (CREATOR/CLUB/MERCHANT/PLATFORM) & 7-Stage Media Pipeline",
            ruleSummary: "Enforces strict four-party ownership boundaries and canonical 7-stage media pipeline (select -> process -> upload -> review -> save -> read -> play).",
            primaryContracts: ["PublishMediaEditorBridge", "PublishMediaEditorSectionView"]
        ),
        UnifiedDecisionDescriptor(
            decisionID: .u02ConfirmedTeamQRHandshakeOnly,
            title: "Confirmed-Team First Meeting Handshake (QR-Only, NFC Disabled, No Interest Gate)",
            ruleSummary: "First offline meeting handshake uses QR code only; NFC remains disabled and interest-matching gates are prohibited.",
            primaryContracts: ["TeamMeetingHandshakeCoordinator", "TeamMeetingHandshakeSectionView"]
        ),
        UnifiedDecisionDescriptor(
            decisionID: .u03StrangerOfflineRealNameScope,
            title: "Real-Name Verification Restricted Strictly to Stranger Offline Meetings",
            ruleSummary: "Real-name verification is required only for stranger offline meetings and never imposed on browse, solo roam, or friend-only flows.",
            primaryContracts: ["TeamMeetingHandshakeCoordinator", "AccountComplianceGuard"]
        ),
        UnifiedDecisionDescriptor(
            decisionID: .u04IndependentRecipientInviteRequestIDs,
            title: "Friend Multi-Invite Batch with Independent Per-Recipient Request IDs",
            ruleSummary: "Every recipient in a multi-invite batch carries a distinct idempotent requestID so partial outcomes never alias.",
            primaryContracts: ["TeamMeetingHandshakeCoordinator", "InviteBatchCardPresentation"]
        ),
        UnifiedDecisionDescriptor(
            decisionID: .u05FailedOnlyRetryAndUnknownOutcomeLock,
            title: "Failed-Only Retry & Unknown-Outcome Readback Lock Before Retry",
            ruleSummary: "Only explicitly FAILED operations may retry; UNKNOWN/TIMEOUT outcomes stay locked until authoritative server readback.",
            primaryContracts: ["RunAuthorityHostCoordinator", "PlayGameCommandJournal", "OfflineDurableRecoveryAudit"]
        ),
        UnifiedDecisionDescriptor(
            decisionID: .u06TerminalRevocationPrecedence,
            title: "Terminal Revocation Precedence in Invite & Handshake Ledger",
            ruleSummary: "Once an invite or meeting handshake is REVOKED, terminal revocation takes precedence over late or stale accept/confirm events.",
            primaryContracts: ["TeamMeetingHandshakeCoordinator", "TeamMeetingHandshakeSectionView"]
        ),
        UnifiedDecisionDescriptor(
            decisionID: .u07DualZoneBeijingGoverningCutoff,
            title: "Dual-Zone Time Display with Beijing Time (Asia/Shanghai) Governing Cutoff",
            ruleSummary: "Displays local and Beijing time side-by-side while enforcing Asia/Shanghai as the authoritative deadline cutoff.",
            primaryContracts: ["TeamMeetingHandshakeSectionView", "EnvironmentBranchHostPresentation"]
        ),
        UnifiedDecisionDescriptor(
            decisionID: .u08NonCashLedgerAndFailClosedSwitches,
            title: "Non-Cash Reward Ledger (W17.4) & Fail-Closed High-Risk Switches",
            ruleSummary: "Reward ledger prohibits cash/withdrawal/points-to-cash conversion and keeps all high-risk write/payment switches fail-closed by default.",
            primaryContracts: ["RewardLedgerHostPresentation", "WaveUnifiedParityInventory", "AppStoreSubmissionReadinessAudit"]
        )
    ]

    public static func descriptor(for id: UnifiedDecisionID) -> UnifiedDecisionDescriptor? {
        decisions.first { $0.decisionID == id }
    }

    public static func evaluateCompliance(
        ownershipRoles: [UnifiedContentOwnershipRole] = canonicalOwnershipRoles,
        mediaPipelineStages: [UnifiedMediaPipelineStage] = canonicalMediaPipeline,
        handshakeUsesQROnly: Bool = true,
        handshakeNFCEnabled: Bool = false,
        hasInterestMatchingGate: Bool = false,
        realNameRequiredOnlyForStrangerOfflineMeeting: Bool = true,
        recipientRequestIDs: [String: String] = ["user-1": "req-1", "user-2": "req-2"],
        allowsRetryOnlyOnExplicitFailure: Bool = true,
        locksRetryOnUnknownOutcomeUntilReadback: Bool = true,
        revocationIsTerminal: Bool = true,
        governingCutoffTimeZone: String = governingCutoffTimeZoneID,
        supportsCashOrPointsToCashInLedger: Bool = false,
        anyHighRiskSwitchEnabledByDefault: Bool = false
    ) -> UnifiedDecisionsComplianceReport {
        var violations: [UnifiedDecisionViolation] = []

        if Set(ownershipRoles) != Set(canonicalOwnershipRoles) || mediaPipelineStages != canonicalMediaPipeline {
            violations.append(
                .invalidOwnershipOrMediaPipeline(
                    decision: .u01ContentOwnershipAndMediaPipeline,
                    detail: "Expected 4 ownership roles and 7 ordered media stages (select..play)"
                )
            )
        }

        if !handshakeUsesQROnly || handshakeNFCEnabled || hasInterestMatchingGate {
            violations.append(
                .prohibitedHandshakeChannelOrGate(
                    decision: .u02ConfirmedTeamQRHandshakeOnly,
                    detail: "Handshake must be QR-only with NFC disabled and no interest-matching gate"
                )
            )
        }

        if !realNameRequiredOnlyForStrangerOfflineMeeting {
            violations.append(
                .realNameScopeOverreach(
                    decision: .u03StrangerOfflineRealNameScope,
                    detail: "Real-name verification must be restricted strictly to stranger offline meetings"
                )
            )
        }

        let trimmedIDs = recipientRequestIDs.values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        if recipientRequestIDs.isEmpty
            || trimmedIDs.contains(where: \.isEmpty)
            || Set(trimmedIDs).count != recipientRequestIDs.count {
            violations.append(
                .duplicateOrMissingRecipientRequestID(
                    decision: .u04IndependentRecipientInviteRequestIDs,
                    detail: "Each invited recipient must have a non-empty, unique requestID"
                )
            )
        }

        if !allowsRetryOnlyOnExplicitFailure || !locksRetryOnUnknownOutcomeUntilReadback {
            violations.append(
                .unsafeRetryOnNonFailedOrUnknownOutcome(
                    decision: .u05FailedOnlyRetryAndUnknownOutcomeLock,
                    detail: "Retry is permitted only after explicit failure and locked on unknown outcome"
                )
            )
        }

        if !revocationIsTerminal {
            violations.append(
                .terminalRevocationOverridden(
                    decision: .u06TerminalRevocationPrecedence,
                    detail: "Terminal revocation cannot be overridden by late accept events"
                )
            )
        }

        if governingCutoffTimeZone != governingCutoffTimeZoneID {
            violations.append(
                .governingCutoffTimeZoneMismatch(
                    decision: .u07DualZoneBeijingGoverningCutoff,
                    actualTimeZone: governingCutoffTimeZone
                )
            )
        }

        if supportsCashOrPointsToCashInLedger || anyHighRiskSwitchEnabledByDefault {
            violations.append(
                .cashRewardOrOpenHighRiskSwitchDetected(
                    decision: .u08NonCashLedgerAndFailClosedSwitches,
                    detail: "Reward ledger must remain non-cash and high-risk switches must stay fail-closed"
                )
            )
        }

        let violatedIDs = Set(violations.map { violation -> UnifiedDecisionID in
            switch violation {
            case .invalidOwnershipOrMediaPipeline(let id, _),
                 .prohibitedHandshakeChannelOrGate(let id, _),
                 .realNameScopeOverreach(let id, _),
                 .duplicateOrMissingRecipientRequestID(let id, _),
                 .unsafeRetryOnNonFailedOrUnknownOutcome(let id, _),
                 .terminalRevocationOverridden(let id, _),
                 .governingCutoffTimeZoneMismatch(let id, _),
                 .cashRewardOrOpenHighRiskSwitchDetected(let id, _):
                return id
            }
        })

        let verifiedIDs = UnifiedDecisionID.allCases.filter { !violatedIDs.contains($0) }
        return UnifiedDecisionsComplianceReport(
            isCompliant: violations.isEmpty,
            verifiedDecisionIDs: verifiedIDs,
            violations: violations
        )
    }
}

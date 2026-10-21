import Foundation

/// App Store Review & TestFlight submission readiness audit (`IOS-REL-01`..`IOS-REL-08`).
/// Pure value-type contract covering Info.plist privacy usage descriptions, `w2-01`/`I08`
/// account and NPC chat deletion compliance, `W17.4` non-cash ledger rules, `I05`/`w2-13`/`w2-20`
/// UGC moderation & 404/DELETED media cache eviction, and Sign in with Apple parity gating.
public enum AppStoreSubmissionReadinessAudit: Equatable, Sendable {
    /// Canonical App Store submission readiness check identifiers (`IOS-REL-01`..`IOS-REL-08`).
    public enum CheckID: String, CaseIterable, Comparable, Equatable, Sendable {
        case iosRel01PrivacyUsageDescriptions = "IOS-REL-01"
        case iosRel02AccountDeletionGate = "IOS-REL-02"
        case iosRel03NPCChatLogDeletionGate = "IOS-REL-03"
        case iosRel04NonCashRewardLedger = "IOS-REL-04"
        case iosRel05DeletedMediaCacheEviction = "IOS-REL-05"
        case iosRel06SquareUGCModeration = "IOS-REL-06"
        case iosRel07IMConversationSafety = "IOS-REL-07"
        case iosRel08SignInWithAppleParity = "IOS-REL-08"

        public static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    /// Required iOS privacy usage description keys for App Store submission (`IOS-REL-01`).
    public enum PrivacyUsageKey: String, CaseIterable, Comparable, Equatable, Sendable {
        case locationWhenInUse = "NSLocationWhenInUseUsageDescription"
        case camera = "NSCameraUsageDescription"
        case microphone = "NSMicrophoneUsageDescription"
        case photoLibrary = "NSPhotoLibraryUsageDescription"
        case photoLibraryAdd = "NSPhotoLibraryAddUsageDescription"

        public static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    public static let requiredPrivacyUsageKeys: [String] = PrivacyUsageKey.allCases.map(\.rawValue)

    private static let placeholderTokens: [String] = [
        "todo",
        "tbd",
        "placeholder",
        "fixme",
        "lorem ipsum",
        "invalid.example"
    ]

    /// Validates that an `Info.plist` dictionary contains non-empty, non-placeholder strings
    /// for all required iOS privacy usage keys (`IOS-REL-01`).
    public static func validatePrivacyUsageDescriptions(
        infoPlist: [String: String]
    ) -> [PrivacyUsageKey] {
        PrivacyUsageKey.allCases.filter { key in
            guard let raw = infoPlist[key.rawValue] else { return true }
            return !isValidPrivacyUsageString(raw)
        }
    }

    public static func isValidPrivacyUsageString(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 12 else { return false }
        guard !trimmed.contains("$(") && !trimmed.contains("${") else { return false }
        let lowered = trimmed.lowercased()
        if lowered == "test" || lowered == "example" || lowered == "none" || lowered == "n/a" {
            return false
        }
        return !placeholderTokens.contains(where: { lowered.contains($0) })
    }

    /// Account deletion (`w2-01`) and NPC chat log deletion (`I08`) compliance policy (`IOS-REL-02`, `IOS-REL-03`).
    public struct DeletionCompliancePolicy: Equatable, Sendable {
        public let inAppAccountDeletionEntryAvailable: Bool
        public let accountDeletionRequiresExplicitConfirmation: Bool
        public let accountDeletionRevokesLocalSessionOnReceipt: Bool
        public let npcChatLocalClearAvailable: Bool
        public let npcChatRemoteDeleteEnabled: Bool
        public let npcChatRemoteDeleteEndpointApproved: Bool

        public init(
            inAppAccountDeletionEntryAvailable: Bool,
            accountDeletionRequiresExplicitConfirmation: Bool,
            accountDeletionRevokesLocalSessionOnReceipt: Bool,
            npcChatLocalClearAvailable: Bool,
            npcChatRemoteDeleteEnabled: Bool = false,
            npcChatRemoteDeleteEndpointApproved: Bool = false
        ) {
            self.inAppAccountDeletionEntryAvailable = inAppAccountDeletionEntryAvailable
            self.accountDeletionRequiresExplicitConfirmation = accountDeletionRequiresExplicitConfirmation
            self.accountDeletionRevokesLocalSessionOnReceipt = accountDeletionRevokesLocalSessionOnReceipt
            self.npcChatLocalClearAvailable = npcChatLocalClearAvailable
            self.npcChatRemoteDeleteEnabled = npcChatRemoteDeleteEnabled
            self.npcChatRemoteDeleteEndpointApproved = npcChatRemoteDeleteEndpointApproved
        }

        public var isAccountDeletionCompliant: Bool {
            inAppAccountDeletionEntryAvailable &&
                accountDeletionRequiresExplicitConfirmation &&
                accountDeletionRevokesLocalSessionOnReceipt
        }

        public var isNPCChatDeletionCompliant: Bool {
            guard npcChatLocalClearAvailable else { return false }
            if npcChatRemoteDeleteEnabled {
                return npcChatRemoteDeleteEndpointApproved
            }
            return true
        }
    }

    /// Non-cash point / reward ledger domain (`W17.4` / `IOS-REL-04`).
    public enum NonCashLedgerAssetKind: String, CaseIterable, Comparable, Equatable, Sendable {
        case points = "POINTS"
        case stamps = "STAMPS"
        case fragments = "FRAGMENTS"
        case seasonScores = "SEASON_SCORES"

        public static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    public struct NonCashLedgerAssetRule: Equatable, Sendable {
        public let kind: NonCashLedgerAssetKind
        public let withdrawable: Bool
        public let transferable: Bool
        public let redeemableForCash: Bool

        public init(
            kind: NonCashLedgerAssetKind,
            withdrawable: Bool = false,
            transferable: Bool = false,
            redeemableForCash: Bool = false
        ) {
            self.kind = kind
            self.withdrawable = withdrawable
            self.transferable = transferable
            self.redeemableForCash = redeemableForCash
        }

        public var isNonCashCompliant: Bool {
            !withdrawable && !transferable && !redeemableForCash
        }
    }

    public struct NonCashRewardLedgerPolicy: Equatable, Sendable {
        public let rules: [NonCashLedgerAssetRule]

        public init(rules: [NonCashLedgerAssetRule]) {
            self.rules = rules
        }

        public static let compliantDefault = NonCashRewardLedgerPolicy(
            rules: NonCashLedgerAssetKind.allCases.map { NonCashLedgerAssetRule(kind: $0) }
        )

        /// Returns any asset kinds that are missing, duplicated, or permit cash withdrawal/transfer/redemption.
        public var violatingAssetKinds: [NonCashLedgerAssetKind] {
            var bad: Set<NonCashLedgerAssetKind> = []
            for kind in NonCashLedgerAssetKind.allCases {
                let matching = rules.filter { $0.kind == kind }
                if matching.count != 1 || matching.contains(where: { !$0.isNonCashCompliant }) {
                    bad.insert(kind)
                }
            }
            return bad.sorted()
        }
    }

    /// UGC moderation, report/block & 404/DELETED media cache eviction policy (`IOS-REL-05`..`IOS-REL-07`).
    public struct UGCSafetyAndCacheEvictionPolicy: Equatable, Sendable {
        /// `I05`: Evicts cached media immediately upon HTTP 404 or `DELETED` tombstone state.
        public let evictsCachedMediaOnHTTP404: Bool
        public let evictsCachedMediaOnDeletedState: Bool
        /// `w2-13`: Square UGC moderation, report, and author block controls.
        public let squareReportEntryAvailable: Bool
        public let squareBlockAuthorAvailable: Bool
        public let squareModerationGateEnabled: Bool
        /// `w2-20`: IM conversation safety report and block controls.
        public let imReportConversationAvailable: Bool
        public let imBlockPeerAvailable: Bool

        public init(
            evictsCachedMediaOnHTTP404: Bool,
            evictsCachedMediaOnDeletedState: Bool,
            squareReportEntryAvailable: Bool,
            squareBlockAuthorAvailable: Bool,
            squareModerationGateEnabled: Bool,
            imReportConversationAvailable: Bool,
            imBlockPeerAvailable: Bool
        ) {
            self.evictsCachedMediaOnHTTP404 = evictsCachedMediaOnHTTP404
            self.evictsCachedMediaOnDeletedState = evictsCachedMediaOnDeletedState
            self.squareReportEntryAvailable = squareReportEntryAvailable
            self.squareBlockAuthorAvailable = squareBlockAuthorAvailable
            self.squareModerationGateEnabled = squareModerationGateEnabled
            self.imReportConversationAvailable = imReportConversationAvailable
            self.imBlockPeerAvailable = imBlockPeerAvailable
        }

        public var isMediaCacheEvictionCompliant: Bool {
            evictsCachedMediaOnHTTP404 && evictsCachedMediaOnDeletedState
        }

        public var isSquareUGCModerationCompliant: Bool {
            squareReportEntryAvailable && squareBlockAuthorAvailable && squareModerationGateEnabled
        }

        public var isIMConversationSafetyCompliant: Bool {
            imReportConversationAvailable && imBlockPeerAvailable
        }
    }

    /// `w2-01` `AuthFeatureFlags` Sign in with Apple & third-party login parity gate (`IOS-REL-08`).
    /// Third-party login must remain disabled unless Sign in with Apple is enabled and configured.
    public struct SignInParityPolicy: Equatable, Sendable {
        public let wechatSignInEnabled: Bool
        public let otherThirdPartySignInEnabled: Bool
        public let appleSignInEnabled: Bool
        public let appleSignInEntitlementConfigured: Bool

        public init(
            wechatSignInEnabled: Bool = false,
            otherThirdPartySignInEnabled: Bool = false,
            appleSignInEnabled: Bool = false,
            appleSignInEntitlementConfigured: Bool = false
        ) {
            self.wechatSignInEnabled = wechatSignInEnabled
            self.otherThirdPartySignInEnabled = otherThirdPartySignInEnabled
            self.appleSignInEnabled = appleSignInEnabled
            self.appleSignInEntitlementConfigured = appleSignInEntitlementConfigured
        }

        public static let failClosedDefault = SignInParityPolicy()

        public var hasAnyThirdPartySignInEnabled: Bool {
            wechatSignInEnabled || otherThirdPartySignInEnabled
        }

        public var isCompliant: Bool {
            if appleSignInEnabled && !appleSignInEntitlementConfigured {
                return false
            }
            if hasAnyThirdPartySignInEnabled {
                return appleSignInEnabled && appleSignInEntitlementConfigured
            }
            return true
        }
    }

    /// Specific compliance violations flagged by the submission readiness audit.
    public enum Violation: Equatable, Sendable {
        case missingOrInvalidPrivacyUsageKeys([PrivacyUsageKey])
        case accountDeletionNonCompliant
        case npcChatDeletionNonCompliant
        case nonCashRewardLedgerViolations([NonCashLedgerAssetKind])
        case deletedMediaCacheEvictionNonCompliant
        case squareUGCModerationNonCompliant
        case imConversationSafetyNonCompliant
        case signInWithAppleParityViolated
    }

    public struct AuditReport: Equatable, Sendable {
        public let passedChecks: [CheckID]
        public let failedChecks: [CheckID]
        public let violations: [Violation]

        public var isReadyForSubmission: Bool {
            violations.isEmpty && failedChecks.isEmpty && passedChecks.count == CheckID.allCases.count
        }
    }

    /// Evaluates all `IOS-REL-01`..`IOS-REL-08` App Store submission readiness checks.
    public static func evaluate(
        infoPlist: [String: String],
        deletionPolicy: DeletionCompliancePolicy,
        ledgerPolicy: NonCashRewardLedgerPolicy = .compliantDefault,
        ugcPolicy: UGCSafetyAndCacheEvictionPolicy,
        signInPolicy: SignInParityPolicy = .failClosedDefault
    ) -> AuditReport {
        var passed: [CheckID] = []
        var failed: [CheckID] = []
        var violations: [Violation] = []

        // IOS-REL-01: Privacy usage descriptions
        let invalidPrivacyKeys = validatePrivacyUsageDescriptions(infoPlist: infoPlist)
        if invalidPrivacyKeys.isEmpty {
            passed.append(.iosRel01PrivacyUsageDescriptions)
        } else {
            failed.append(.iosRel01PrivacyUsageDescriptions)
            violations.append(.missingOrInvalidPrivacyUsageKeys(invalidPrivacyKeys))
        }

        // IOS-REL-02: Account deletion compliance (w2-01)
        if deletionPolicy.isAccountDeletionCompliant {
            passed.append(.iosRel02AccountDeletionGate)
        } else {
            failed.append(.iosRel02AccountDeletionGate)
            violations.append(.accountDeletionNonCompliant)
        }

        // IOS-REL-03: NPC chat log deletion gate (I08)
        if deletionPolicy.isNPCChatDeletionCompliant {
            passed.append(.iosRel03NPCChatLogDeletionGate)
        } else {
            failed.append(.iosRel03NPCChatLogDeletionGate)
            violations.append(.npcChatDeletionNonCompliant)
        }

        // IOS-REL-04: Non-cash point / reward ledger compliance (W17.4)
        let badAssets = ledgerPolicy.violatingAssetKinds
        if badAssets.isEmpty {
            passed.append(.iosRel04NonCashRewardLedger)
        } else {
            failed.append(.iosRel04NonCashRewardLedger)
            violations.append(.nonCashRewardLedgerViolations(badAssets))
        }

        // IOS-REL-05: 404/DELETED media cache eviction (I05)
        if ugcPolicy.isMediaCacheEvictionCompliant {
            passed.append(.iosRel05DeletedMediaCacheEviction)
        } else {
            failed.append(.iosRel05DeletedMediaCacheEviction)
            violations.append(.deletedMediaCacheEvictionNonCompliant)
        }

        // IOS-REL-06: Square UGC moderation (w2-13)
        if ugcPolicy.isSquareUGCModerationCompliant {
            passed.append(.iosRel06SquareUGCModeration)
        } else {
            failed.append(.iosRel06SquareUGCModeration)
            violations.append(.squareUGCModerationNonCompliant)
        }

        // IOS-REL-07: IM conversation safety (w2-20)
        if ugcPolicy.isIMConversationSafetyCompliant {
            passed.append(.iosRel07IMConversationSafety)
        } else {
            failed.append(.iosRel07IMConversationSafety)
            violations.append(.imConversationSafetyNonCompliant)
        }

        // IOS-REL-08: Sign in with Apple & third-party login parity (w2-01)
        if signInPolicy.isCompliant {
            passed.append(.iosRel08SignInWithAppleParity)
        } else {
            failed.append(.iosRel08SignInWithAppleParity)
            violations.append(.signInWithAppleParityViolated)
        }

        return AuditReport(
            passedChecks: passed,
            failedChecks: failed,
            violations: violations
        )
    }
}

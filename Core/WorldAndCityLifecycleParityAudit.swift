import Foundation

/// Reform Plan v9 audit gate for the 3 World & City Lifecycle parity pillars:
/// 1. `G-W05.5–W05.7`: `EnvironmentBranchHostPresentation` pinned active run snapshot isolation,
///    closed-window fallback, and severe-weather safe exit.
/// 2. `H-W19`: `HomeReturnRestoreCoordinator` explicit `GLOBAL`/`RUN`/`THEME` resource scope,
///    wildcard `"ALL_GAMES"` rejection, cooldown wait, and `[redacted]` coordinate privacy.
/// 3. `H-W20`: `CityActionAndDeltaCoordinator` `CityBoardLifecycle`, self-payer quote confirmation,
///    `VERSION_CONFLICT` task attempt preservation, and contiguous delta stream / snapshot reload.
public enum WorldAndCityLifecycleParityAudit {

    // MARK: - Pillar 1: G-W05.5–W05.7 (EnvironmentBranchHostPresentation)

    public struct EnvironmentBranchAuditInput: Sendable, Equatable {
        public let pinnedRunSnapshotID: String
        public let incomingEnvironmentSnapshotID: String
        public let mutatesActiveRunSnapshotInPlace: Bool
        public let isTimeWindowOpen: Bool
        public let hasClosedWindowFallbackNode: Bool
        public let isSevereWeatherAlertActive: Bool
        public let triggersSafeExitOnSevereWeather: Bool

        public init(
            pinnedRunSnapshotID: String,
            incomingEnvironmentSnapshotID: String,
            mutatesActiveRunSnapshotInPlace: Bool = false,
            isTimeWindowOpen: Bool = true,
            hasClosedWindowFallbackNode: Bool = true,
            isSevereWeatherAlertActive: Bool = false,
            triggersSafeExitOnSevereWeather: Bool = true
        ) {
            self.pinnedRunSnapshotID = pinnedRunSnapshotID
            self.incomingEnvironmentSnapshotID = incomingEnvironmentSnapshotID
            self.mutatesActiveRunSnapshotInPlace = mutatesActiveRunSnapshotInPlace
            self.isTimeWindowOpen = isTimeWindowOpen
            self.hasClosedWindowFallbackNode = hasClosedWindowFallbackNode
            self.isSevereWeatherAlertActive = isSevereWeatherAlertActive
            self.triggersSafeExitOnSevereWeather = triggersSafeExitOnSevereWeather
        }
    }

    public enum EnvironmentBranchAuditVerdict: Sendable, Equatable {
        case activeBranchProceeds(pinnedSnapshotID: String)
        case routedToClosedWindowFallback(pinnedSnapshotID: String)
        case routedToSevereWeatherSafeExit(pinnedSnapshotID: String)
        case snapshotIsolationViolated(pinnedSnapshotID: String, incomingSnapshotID: String)
        case missingClosedWindowFallback
        case missingSevereWeatherSafeExit
    }

    public static func auditEnvironmentBranchHost(_ input: EnvironmentBranchAuditInput) -> EnvironmentBranchAuditVerdict {
        let pinned = input.pinnedRunSnapshotID.trimmingCharacters(in: .whitespacesAndNewlines)
        let incoming = input.incomingEnvironmentSnapshotID.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !pinned.isEmpty, !input.mutatesActiveRunSnapshotInPlace else {
            return .snapshotIsolationViolated(pinnedSnapshotID: pinned, incomingSnapshotID: incoming)
        }

        if input.isSevereWeatherAlertActive {
            guard input.triggersSafeExitOnSevereWeather else {
                return .missingSevereWeatherSafeExit
            }
            return .routedToSevereWeatherSafeExit(pinnedSnapshotID: pinned)
        }

        if !input.isTimeWindowOpen {
            guard input.hasClosedWindowFallbackNode else {
                return .missingClosedWindowFallback
            }
            return .routedToClosedWindowFallback(pinnedSnapshotID: pinned)
        }

        return .activeBranchProceeds(pinnedSnapshotID: pinned)
    }

    // MARK: - Pillar 2: H-W19 (HomeReturnRestoreCoordinator)

    public enum ExplicitRestoreResourceScope: String, CaseIterable, Sendable, Equatable {
        case global = "GLOBAL"
        case run = "RUN"
        case theme = "THEME"
    }

    public struct HomeReturnRestoreAuditInput: Sendable, Equatable {
        public static let forbiddenWildcardScope = "ALL_GAMES"
        public static let redactedCoordinatePlaceholder = "[redacted]"

        public let requestedRawScope: String
        public let remainingCooldownSeconds: Int
        public let diagnosticCoordinateSummary: String

        public init(
            requestedRawScope: String,
            remainingCooldownSeconds: Int = 0,
            diagnosticCoordinateSummary: String = Self.redactedCoordinatePlaceholder
        ) {
            self.requestedRawScope = requestedRawScope
            self.remainingCooldownSeconds = remainingCooldownSeconds
            self.diagnosticCoordinateSummary = diagnosticCoordinateSummary
        }
    }

    public enum HomeReturnRestoreAuditVerdict: Sendable, Equatable {
        case restorePermitted(scope: ExplicitRestoreResourceScope, redactedCoordinateSummary: String)
        case wildcardScopeRejected(rawScope: String)
        case unknownScopeRejected(rawScope: String)
        case cooldownWaitRequired(remainingSeconds: Int, scope: ExplicitRestoreResourceScope)
        case unredactedCoordinatePrivacyViolation(exposedValue: String)
    }

    public static func auditHomeReturnRestore(_ input: HomeReturnRestoreAuditInput) -> HomeReturnRestoreAuditVerdict {
        let normalizedScope = input.requestedRawScope
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()

        if normalizedScope == HomeReturnRestoreAuditInput.forbiddenWildcardScope || normalizedScope == "*" {
            return .wildcardScopeRejected(rawScope: input.requestedRawScope)
        }

        guard let explicitScope = ExplicitRestoreResourceScope(rawValue: normalizedScope) else {
            return .unknownScopeRejected(rawScope: input.requestedRawScope)
        }

        let trimmedCoord = input.diagnosticCoordinateSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedCoord == HomeReturnRestoreAuditInput.redactedCoordinatePlaceholder else {
            return .unredactedCoordinatePrivacyViolation(exposedValue: input.diagnosticCoordinateSummary)
        }

        if input.remainingCooldownSeconds > 0 {
            return .cooldownWaitRequired(
                remainingSeconds: input.remainingCooldownSeconds,
                scope: explicitScope
            )
        }

        return .restorePermitted(
            scope: explicitScope,
            redactedCoordinateSummary: HomeReturnRestoreAuditInput.redactedCoordinatePlaceholder
        )
    }

    // MARK: - Pillar 3: H-W20 (CityActionAndDeltaCoordinator)

    public enum CityBoardLifecycleState: String, CaseIterable, Sendable, Equatable {
        case bootstrapping = "BOOTSTRAPPING"
        case activeSynced = "ACTIVE_SYNCED"
        case applyingDelta = "APPLYING_DELTA"
        case reloadingSnapshot = "RELOADING_SNAPSHOT"
        case conflictRecovery = "CONFLICT_RECOVERY"
    }

    public struct CityActionAndDeltaAuditInput: Sendable, Equatable {
        public let lifecycleState: CityBoardLifecycleState
        public let actorMemberID: Int
        public let payerMemberID: Int
        public let hasExplicitQuoteConfirmation: Bool
        public let errorCode: String?
        public let preservesLocalTaskAttemptOnConflict: Bool
        public let localBoardVersion: Int
        public let incomingDeltaFromVersion: Int
        public let incomingDeltaToVersion: Int

        public init(
            lifecycleState: CityBoardLifecycleState = .activeSynced,
            actorMemberID: Int,
            payerMemberID: Int,
            hasExplicitQuoteConfirmation: Bool = true,
            errorCode: String? = nil,
            preservesLocalTaskAttemptOnConflict: Bool = true,
            localBoardVersion: Int,
            incomingDeltaFromVersion: Int,
            incomingDeltaToVersion: Int
        ) {
            self.lifecycleState = lifecycleState
            self.actorMemberID = actorMemberID
            self.payerMemberID = payerMemberID
            self.hasExplicitQuoteConfirmation = hasExplicitQuoteConfirmation
            self.errorCode = errorCode
            self.preservesLocalTaskAttemptOnConflict = preservesLocalTaskAttemptOnConflict
            self.localBoardVersion = localBoardVersion
            self.incomingDeltaFromVersion = incomingDeltaFromVersion
            self.incomingDeltaToVersion = incomingDeltaToVersion
        }
    }

    public enum CityActionAndDeltaAuditVerdict: Sendable, Equatable {
        case contiguousDeltaApplied(newBoardVersion: Int)
        case snapshotReloadRequired(localVersion: Int, incomingFromVersion: Int)
        case versionConflictPreservedTaskAttempt(localVersion: Int)
        case versionConflictDiscardedTaskAttemptViolation
        case thirdPartyPayerRejected(actorMemberID: Int, payerMemberID: Int)
        case missingQuoteConfirmation
    }

    public static func auditCityActionAndDelta(_ input: CityActionAndDeltaAuditInput) -> CityActionAndDeltaAuditVerdict {
        guard input.actorMemberID > 0,
              input.payerMemberID > 0,
              input.actorMemberID == input.payerMemberID else {
            return .thirdPartyPayerRejected(
                actorMemberID: input.actorMemberID,
                payerMemberID: input.payerMemberID
            )
        }

        guard input.hasExplicitQuoteConfirmation else {
            return .missingQuoteConfirmation
        }

        if input.errorCode == "VERSION_CONFLICT" {
            guard input.preservesLocalTaskAttemptOnConflict else {
                return .versionConflictDiscardedTaskAttemptViolation
            }
            return .versionConflictPreservedTaskAttempt(localVersion: input.localBoardVersion)
        }

        guard input.localBoardVersion >= 0,
              input.incomingDeltaFromVersion == input.localBoardVersion,
              input.incomingDeltaToVersion == input.localBoardVersion + 1 else {
            return .snapshotReloadRequired(
                localVersion: input.localBoardVersion,
                incomingFromVersion: input.incomingDeltaFromVersion
            )
        }

        return .contiguousDeltaApplied(newBoardVersion: input.incomingDeltaToVersion)
    }

    // MARK: - Unified 3-Pillar Summary Gate

    public struct WorldAndCityLifecycleReport: Sendable, Equatable {
        public let environmentBranchVerdict: EnvironmentBranchAuditVerdict
        public let homeReturnRestoreVerdict: HomeReturnRestoreAuditVerdict
        public let cityActionAndDeltaVerdict: CityActionAndDeltaAuditVerdict

        public var isCompliant: Bool {
            let pillar1Pass: Bool
            switch environmentBranchVerdict {
            case .activeBranchProceeds, .routedToClosedWindowFallback, .routedToSevereWeatherSafeExit:
                pillar1Pass = true
            case .snapshotIsolationViolated, .missingClosedWindowFallback, .missingSevereWeatherSafeExit:
                pillar1Pass = false
            }

            let pillar2Pass: Bool
            switch homeReturnRestoreVerdict {
            case .restorePermitted, .cooldownWaitRequired:
                pillar2Pass = true
            case .wildcardScopeRejected, .unknownScopeRejected, .unredactedCoordinatePrivacyViolation:
                pillar2Pass = false
            }

            let pillar3Pass: Bool
            switch cityActionAndDeltaVerdict {
            case .contiguousDeltaApplied, .snapshotReloadRequired, .versionConflictPreservedTaskAttempt:
                pillar3Pass = true
            case .versionConflictDiscardedTaskAttemptViolation, .thirdPartyPayerRejected, .missingQuoteConfirmation:
                pillar3Pass = false
            }

            return pillar1Pass && pillar2Pass && pillar3Pass
        }

        public init(
            environmentBranchVerdict: EnvironmentBranchAuditVerdict,
            homeReturnRestoreVerdict: HomeReturnRestoreAuditVerdict,
            cityActionAndDeltaVerdict: CityActionAndDeltaAuditVerdict
        ) {
            self.environmentBranchVerdict = environmentBranchVerdict
            self.homeReturnRestoreVerdict = homeReturnRestoreVerdict
            self.cityActionAndDeltaVerdict = cityActionAndDeltaVerdict
        }
    }
}

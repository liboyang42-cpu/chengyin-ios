import Foundation

/// Pure self-contained audit of the 5 play runtime & durable authority pillars:
/// 1. `w2-11` (`PlayRuntimeAuxiliaryBinding` session/run-scoped auxiliary panel binding),
/// 2. `I01` (`PlayArrivalAccuracy` 80m advisory threshold + `>100m` / `>30s` `invalidAction` rejection),
/// 3. `I02` (`PlayGameCommandJournal` & `PlayGameSessionComposition` `<key>:game` encrypted recovery slot),
/// 4. `I09` (`PlayLeadProgressPolling` lifecycle-scoped polling),
/// 5. `H-W03` (`RunAuthorityHostCoordinator` CAS `stateVersion` conflict & unknown-outcome lock).
public enum PlayRuntimeAndAuxiliaryBindingAudit {

    // MARK: - Pillar Enumeration & Violation Types

    public enum Pillar: String, CaseIterable, Equatable, Sendable {
        case w211RuntimeAuxiliaryBinding = "W2_11_PLAY_RUNTIME_AUXILIARY_BINDING"
        case i01ArrivalAccuracyThresholds = "I01_PLAY_ARRIVAL_ACCURACY"
        case i02GameCommandJournalSlot = "I02_PLAY_GAME_COMMAND_JOURNAL"
        case i09LeadProgressPolling = "I09_PLAY_LEAD_PROGRESS_POLLING"
        case hW03RunAuthorityCASAndLock = "H_W03_RUN_AUTHORITY_CAS_LOCK"
    }

    public enum AuditViolation: Equatable, Sendable {
        case auxiliaryCrossRunBinding(expectedRunID: String, boundRunID: String)
        case auxiliaryActiveWhileSessionInactive
        case arrivalFixAcceptedDespiteInaccurateHorizontal(accuracyMeters: Double)
        case arrivalFixAcceptedDespiteStaleTimestamp(fixAgeSeconds: Double)
        case arrivalAdvisoryMissingBetween80And100Meters(accuracyMeters: Double)
        case invalidGameRecoverySlotKey(expected: String, actual: String)
        case commandDispatchedWithoutPreWriteJournal
        case pollingRemainsActiveOutsideForegroundOrActiveRun
        case casConflictIgnored(expectedVersion: Int64, serverVersion: Int64)
        case competingMutationAllowedDuringUnknownOutcomeLock(pendingRequestID: String)
        case retryChangedIdempotentRequestID(originalID: String, retryID: String)
    }

    // MARK: - Pillar 1: w2-11 PlayRuntimeAuxiliaryBinding Audit

    public struct AuxiliaryBindingEvaluation: Equatable, Sendable {
        public let activeRunID: String
        public let boundRunID: String
        public let isSessionActive: Bool
        public let allowsAuxiliaryPresentation: Bool
        public let violations: [AuditViolation]

        public var isCompliant: Bool { violations.isEmpty }

        public init(
            activeRunID: String,
            boundRunID: String,
            isSessionActive: Bool,
            allowsAuxiliaryPresentation: Bool
        ) {
            self.activeRunID = activeRunID
            self.boundRunID = boundRunID
            self.isSessionActive = isSessionActive
            self.allowsAuxiliaryPresentation = allowsAuxiliaryPresentation

            var foundViolations: [AuditViolation] = []
            if !activeRunID.isEmpty, activeRunID != boundRunID, allowsAuxiliaryPresentation {
                foundViolations.append(
                    .auxiliaryCrossRunBinding(expectedRunID: activeRunID, boundRunID: boundRunID)
                )
            }
            if !isSessionActive && allowsAuxiliaryPresentation {
                foundViolations.append(.auxiliaryActiveWhileSessionInactive)
            }
            self.violations = foundViolations
        }
    }

    public static func auditAuxiliaryBinding(
        activeRunID: String,
        boundRunID: String,
        isSessionActive: Bool,
        allowsAuxiliaryPresentation: Bool
    ) -> AuxiliaryBindingEvaluation {
        AuxiliaryBindingEvaluation(
            activeRunID: activeRunID,
            boundRunID: boundRunID,
            isSessionActive: isSessionActive,
            allowsAuxiliaryPresentation: allowsAuxiliaryPresentation
        )
    }

    // MARK: - Pillar 2: I01 PlayArrivalAccuracy (80m Advisory + >100m / >30s invalidAction)

    public enum ArrivalClassification: String, Equatable, Sendable {
        case preciseReady = "PRECISE_READY"
        case advisoryWarning = "ADVISORY_WARNING_80_TO_100M"
        case rejectedInvalidAction = "REJECTED_INVALID_ACTION"
    }

    public struct ArrivalAccuracyEvaluation: Equatable, Sendable {
        public static let advisoryThresholdMeters: Double = 80.0
        public static let hardRejectionMeters: Double = 100.0
        public static let maxFixAgeSeconds: Double = 30.0
        public static let minFutureSkewSeconds: Double = -5.0

        public let accuracyMeters: Double
        public let fixAgeSeconds: Double
        public let classification: ArrivalClassification
        public let shows80mAdvisory: Bool
        public let dispatchesArrivalAction: Bool
        public let violations: [AuditViolation]

        public var isCompliant: Bool { violations.isEmpty }

        public init(
            accuracyMeters: Double,
            fixAgeSeconds: Double,
            shows80mAdvisory: Bool? = nil,
            dispatchesArrivalAction: Bool? = nil
        ) {
            self.accuracyMeters = accuracyMeters
            self.fixAgeSeconds = fixAgeSeconds

            let accuracyValid = accuracyMeters.isFinite && accuracyMeters >= 0 && accuracyMeters <= Self.hardRejectionMeters
            let ageValid = fixAgeSeconds.isFinite && fixAgeSeconds >= Self.minFutureSkewSeconds && fixAgeSeconds <= Self.maxFixAgeSeconds

            let expectedClass: ArrivalClassification
            if !accuracyValid || !ageValid {
                expectedClass = .rejectedInvalidAction
            } else if accuracyMeters > Self.advisoryThresholdMeters {
                expectedClass = .advisoryWarning
            } else {
                expectedClass = .preciseReady
            }
            self.classification = expectedClass

            let effectiveAdvisory = shows80mAdvisory ?? (expectedClass == .advisoryWarning)
            let effectiveDispatch = dispatchesArrivalAction ?? (expectedClass != .rejectedInvalidAction)
            self.shows80mAdvisory = effectiveAdvisory
            self.dispatchesArrivalAction = effectiveDispatch

            var foundViolations: [AuditViolation] = []
            if !accuracyValid && effectiveDispatch {
                foundViolations.append(.arrivalFixAcceptedDespiteInaccurateHorizontal(accuracyMeters: accuracyMeters))
            }
            if !ageValid && effectiveDispatch {
                foundViolations.append(.arrivalFixAcceptedDespiteStaleTimestamp(fixAgeSeconds: fixAgeSeconds))
            }
            if expectedClass == .advisoryWarning && !effectiveAdvisory {
                foundViolations.append(.arrivalAdvisoryMissingBetween80And100Meters(accuracyMeters: accuracyMeters))
            }
            self.violations = foundViolations
        }
    }

    public static func auditArrivalAccuracy(
        accuracyMeters: Double,
        fixAgeSeconds: Double,
        shows80mAdvisory: Bool? = nil,
        dispatchesArrivalAction: Bool? = nil
    ) -> ArrivalAccuracyEvaluation {
        ArrivalAccuracyEvaluation(
            accuracyMeters: accuracyMeters,
            fixAgeSeconds: fixAgeSeconds,
            shows80mAdvisory: shows80mAdvisory,
            dispatchesArrivalAction: dispatchesArrivalAction
        )
    }

    // MARK: - Pillar 3: I02 PlayGameCommandJournal & <key>:game Encrypted Recovery Slot

    public struct GameCommandJournalEvaluation: Equatable, Sendable {
        public let baseSessionKey: String
        public let configuredGameSlotKey: String
        public let journalWrittenBeforeDispatch: Bool
        public let retainsUnknownOutcomeAcrossRelaunch: Bool
        public let violations: [AuditViolation]

        public var expectedGameSlotKey: String { "\(baseSessionKey):game" }
        public var isCompliant: Bool { violations.isEmpty }

        public init(
            baseSessionKey: String,
            configuredGameSlotKey: String,
            journalWrittenBeforeDispatch: Bool = true,
            retainsUnknownOutcomeAcrossRelaunch: Bool = true
        ) {
            self.baseSessionKey = baseSessionKey
            self.configuredGameSlotKey = configuredGameSlotKey
            self.journalWrittenBeforeDispatch = journalWrittenBeforeDispatch
            self.retainsUnknownOutcomeAcrossRelaunch = retainsUnknownOutcomeAcrossRelaunch

            let expectedSlot = "\(baseSessionKey):game"
            var foundViolations: [AuditViolation] = []
            if configuredGameSlotKey != expectedSlot || baseSessionKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                foundViolations.append(.invalidGameRecoverySlotKey(expected: expectedSlot, actual: configuredGameSlotKey))
            }
            if !journalWrittenBeforeDispatch || !retainsUnknownOutcomeAcrossRelaunch {
                foundViolations.append(.commandDispatchedWithoutPreWriteJournal)
            }
            self.violations = foundViolations
        }
    }

    public static func auditGameCommandJournalSlot(
        baseSessionKey: String,
        configuredGameSlotKey: String,
        journalWrittenBeforeDispatch: Bool = true,
        retainsUnknownOutcomeAcrossRelaunch: Bool = true
    ) -> GameCommandJournalEvaluation {
        GameCommandJournalEvaluation(
            baseSessionKey: baseSessionKey,
            configuredGameSlotKey: configuredGameSlotKey,
            journalWrittenBeforeDispatch: journalWrittenBeforeDispatch,
            retainsUnknownOutcomeAcrossRelaunch: retainsUnknownOutcomeAcrossRelaunch
        )
    }

    // MARK: - Pillar 4: I09 PlayLeadProgressPolling Lifecycle-Scoped Polling

    public struct LeadProgressPollingEvaluation: Equatable, Sendable {
        public let isSurfaceVisible: Bool
        public let isAppForeground: Bool
        public let isRunActive: Bool
        public let isPollingTaskRunning: Bool
        public let violations: [AuditViolation]

        public var shouldPoll: Bool { isSurfaceVisible && isAppForeground && isRunActive }
        public var isCompliant: Bool { violations.isEmpty }

        public init(
            isSurfaceVisible: Bool,
            isAppForeground: Bool,
            isRunActive: Bool,
            isPollingTaskRunning: Bool
        ) {
            self.isSurfaceVisible = isSurfaceVisible
            self.isAppForeground = isAppForeground
            self.isRunActive = isRunActive
            self.isPollingTaskRunning = isPollingTaskRunning

            let allowedToPoll = isSurfaceVisible && isAppForeground && isRunActive
            var foundViolations: [AuditViolation] = []
            if !allowedToPoll && isPollingTaskRunning {
                foundViolations.append(.pollingRemainsActiveOutsideForegroundOrActiveRun)
            }
            self.violations = foundViolations
        }
    }

    public static func auditLeadProgressPolling(
        isSurfaceVisible: Bool,
        isAppForeground: Bool,
        isRunActive: Bool,
        isPollingTaskRunning: Bool
    ) -> LeadProgressPollingEvaluation {
        LeadProgressPollingEvaluation(
            isSurfaceVisible: isSurfaceVisible,
            isAppForeground: isAppForeground,
            isRunActive: isRunActive,
            isPollingTaskRunning: isPollingTaskRunning
        )
    }

    // MARK: - Pillar 5: H-W03 RunAuthorityHostCoordinator CAS Conflict & Unknown-Outcome Lock

    public struct RunAuthorityCASAndLockEvaluation: Equatable, Sendable {
        public let expectedStateVersion: Int64
        public let serverStateVersion: Int64
        public let pendingUnknownRequestID: String?
        public let retryRequestID: String?
        public let allowsCompetingMutation: Bool
        public let requiresStateRefetchOnConflict: Bool
        public let violations: [AuditViolation]

        public var hasVersionConflict: Bool { expectedStateVersion != serverStateVersion }
        public var isLockedForUnknownOutcome: Bool { pendingUnknownRequestID != nil }
        public var isCompliant: Bool { violations.isEmpty }

        public init(
            expectedStateVersion: Int64,
            serverStateVersion: Int64,
            pendingUnknownRequestID: String? = nil,
            retryRequestID: String? = nil,
            allowsCompetingMutation: Bool = false,
            requiresStateRefetchOnConflict: Bool = true
        ) {
            self.expectedStateVersion = expectedStateVersion
            self.serverStateVersion = serverStateVersion
            self.pendingUnknownRequestID = pendingUnknownRequestID
            self.retryRequestID = retryRequestID
            self.allowsCompetingMutation = allowsCompetingMutation
            self.requiresStateRefetchOnConflict = requiresStateRefetchOnConflict

            var foundViolations: [AuditViolation] = []
            if expectedStateVersion != serverStateVersion && !requiresStateRefetchOnConflict {
                foundViolations.append(
                    .casConflictIgnored(expectedVersion: expectedStateVersion, serverVersion: serverStateVersion)
                )
            }
            if let pendingID = pendingUnknownRequestID {
                if allowsCompetingMutation {
                    foundViolations.append(
                        .competingMutationAllowedDuringUnknownOutcomeLock(pendingRequestID: pendingID)
                    )
                }
                if let retryID = retryRequestID, retryID != pendingID {
                    foundViolations.append(
                        .retryChangedIdempotentRequestID(originalID: pendingID, retryID: retryID)
                    )
                }
            }
            self.violations = foundViolations
        }
    }

    public static func auditRunAuthorityCASAndLock(
        expectedStateVersion: Int64,
        serverStateVersion: Int64,
        pendingUnknownRequestID: String? = nil,
        retryRequestID: String? = nil,
        allowsCompetingMutation: Bool = false,
        requiresStateRefetchOnConflict: Bool = true
    ) -> RunAuthorityCASAndLockEvaluation {
        RunAuthorityCASAndLockEvaluation(
            expectedStateVersion: expectedStateVersion,
            serverStateVersion: serverStateVersion,
            pendingUnknownRequestID: pendingUnknownRequestID,
            retryRequestID: retryRequestID,
            allowsCompetingMutation: allowsCompetingMutation,
            requiresStateRefetchOnConflict: requiresStateRefetchOnConflict
        )
    }
}

import Foundation

/// Self-contained audit and verification gate for `F-W14.1/W14.3` Merchant Side-Quests
/// and `F-W14.6` Personal Fog Host invariants:
/// 1. Default-off `SideQuestFeature` accept gate.
/// 2. Independent (`themeReleaseID == nil`) vs theme-bound spawn discoverability.
/// 3. Photo-evidence `.submittedAwaitingReview` non-auto-complete guard until authoritative `.completed` readback.
/// 4. Unknown-outcome readback lock (`isLockedByUnknownOutcome`) and attempt survival across spawn expiry/removal.
/// 5. Personal fog `revealSyncEnabled == false` default and disjoint confirmed vs predicted cell counts.
public enum SideQuestAndPersonalFogHostAudit {

    // MARK: - 1. Default-Off SideQuestFeature Accept Gate

    public struct FeatureGateAuditInput: Sendable, Equatable {
        public let isEnabledByDefault: Bool
        public let isCurrentlyEnabled: Bool
        public let attemptsAcceptWhileDisabled: Bool

        public init(
            isEnabledByDefault: Bool = false,
            isCurrentlyEnabled: Bool = true,
            attemptsAcceptWhileDisabled: Bool = false
        ) {
            self.isEnabledByDefault = isEnabledByDefault
            self.isCurrentlyEnabled = isCurrentlyEnabled
            self.attemptsAcceptWhileDisabled = attemptsAcceptWhileDisabled
        }
    }

    public enum FeatureGateAuditVerdict: Sendable, Equatable {
        case compliant(canAccept: Bool)
        case defaultNotOffViolation
        case acceptAllowedWhileDisabledViolation
    }

    public static func auditFeatureGate(_ input: FeatureGateAuditInput) -> FeatureGateAuditVerdict {
        guard !input.isEnabledByDefault else {
            return .defaultNotOffViolation
        }
        if !input.isCurrentlyEnabled && input.attemptsAcceptWhileDisabled {
            return .acceptAllowedWhileDisabledViolation
        }
        return .compliant(canAccept: input.isCurrentlyEnabled)
    }

    // MARK: - 2. Independent vs Theme-Bound Spawn Discoverability

    public struct SpawnDiscoverabilityAuditInput: Sendable, Equatable {
        public let spawnID: String
        public let themeReleaseID: String?
        public let activeThemeReleaseID: String?

        public var isIndependentSpawn: Bool {
            themeReleaseID == nil
        }

        public init(
            spawnID: String,
            themeReleaseID: String?,
            activeThemeReleaseID: String?
        ) {
            self.spawnID = spawnID
            self.themeReleaseID = themeReleaseID
            self.activeThemeReleaseID = activeThemeReleaseID
        }
    }

    public enum SpawnDiscoverabilityVerdict: Sendable, Equatable {
        case discoverableIndependent(spawnID: String)
        case discoverableThemeBound(spawnID: String, themeReleaseID: String)
        case hiddenThemeMismatch(spawnID: String, requiredThemeReleaseID: String, activeThemeReleaseID: String?)
        case invalidEmptyThemeReleaseID(spawnID: String)
    }

    public static func auditSpawnDiscoverability(_ input: SpawnDiscoverabilityAuditInput) -> SpawnDiscoverabilityVerdict {
        guard let rawThemeID = input.themeReleaseID else {
            return .discoverableIndependent(spawnID: input.spawnID)
        }
        let trimmedRequired = rawThemeID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedRequired.isEmpty else {
            return .invalidEmptyThemeReleaseID(spawnID: input.spawnID)
        }
        let trimmedActive = input.activeThemeReleaseID?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedActive == trimmedRequired else {
            return .hiddenThemeMismatch(
                spawnID: input.spawnID,
                requiredThemeReleaseID: trimmedRequired,
                activeThemeReleaseID: trimmedActive
            )
        }
        return .discoverableThemeBound(spawnID: input.spawnID, themeReleaseID: trimmedRequired)
    }

    // MARK: - 3. Photo-Evidence .submittedAwaitingReview Non-Auto-Complete Guard

    public enum SideQuestAttemptStatus: String, CaseIterable, Sendable, Equatable {
        case acceptedInProgress = "ACCEPTED_IN_PROGRESS"
        case submittedAwaitingReview = "SUBMITTED_AWAITING_REVIEW"
        case completed = "COMPLETED"
        case rejected = "REJECTED"
    }

    public struct PhotoEvidenceSubmissionAuditInput: Sendable, Equatable {
        public let attemptID: String
        public let requiresPhotoEvidence: Bool
        public let localStatusAfterUpload: SideQuestAttemptStatus
        public let authoritativeServerReadbackStatus: SideQuestAttemptStatus?
        public let locallyAutoCompletedBeforeServerReadback: Bool

        public init(
            attemptID: String,
            requiresPhotoEvidence: Bool = true,
            localStatusAfterUpload: SideQuestAttemptStatus = .submittedAwaitingReview,
            authoritativeServerReadbackStatus: SideQuestAttemptStatus? = nil,
            locallyAutoCompletedBeforeServerReadback: Bool = false
        ) {
            self.attemptID = attemptID
            self.requiresPhotoEvidence = requiresPhotoEvidence
            self.localStatusAfterUpload = localStatusAfterUpload
            self.authoritativeServerReadbackStatus = authoritativeServerReadbackStatus
            self.locallyAutoCompletedBeforeServerReadback = locallyAutoCompletedBeforeServerReadback
        }
    }

    public enum PhotoEvidenceAuditVerdict: Sendable, Equatable {
        case awaitingAuthoritativeReview(attemptID: String)
        case completedAfterAuthoritativeReadback(attemptID: String)
        case forbiddenLocalAutoCompleteViolation(attemptID: String)
    }

    public static func auditPhotoEvidenceSubmission(_ input: PhotoEvidenceSubmissionAuditInput) -> PhotoEvidenceAuditVerdict {
        if input.requiresPhotoEvidence {
            if input.locallyAutoCompletedBeforeServerReadback {
                return .forbiddenLocalAutoCompleteViolation(attemptID: input.attemptID)
            }
            if input.localStatusAfterUpload == .completed && input.authoritativeServerReadbackStatus != .completed {
                return .forbiddenLocalAutoCompleteViolation(attemptID: input.attemptID)
            }
        }
        if input.authoritativeServerReadbackStatus == .completed {
            return .completedAfterAuthoritativeReadback(attemptID: input.attemptID)
        }
        return .awaitingAuthoritativeReview(attemptID: input.attemptID)
    }

    // MARK: - 4. Unknown-Outcome Readback Lock & Attempt Survival Across Spawn Expiry/Removal

    public struct AttemptLifecycleResilienceAuditInput: Sendable, Equatable {
        public let attemptID: String
        public let hasUncertainNetworkMutationOutcome: Bool
        public let isLockedByUnknownOutcome: Bool
        public let allowsConcurrentMutationWhileLocked: Bool
        public let underlyingSpawnExpiredOrRemoved: Bool
        public let activeAttemptPreservedAfterSpawnRemoval: Bool

        public init(
            attemptID: String,
            hasUncertainNetworkMutationOutcome: Bool,
            isLockedByUnknownOutcome: Bool,
            allowsConcurrentMutationWhileLocked: Bool = false,
            underlyingSpawnExpiredOrRemoved: Bool = true,
            activeAttemptPreservedAfterSpawnRemoval: Bool = true
        ) {
            self.attemptID = attemptID
            self.hasUncertainNetworkMutationOutcome = hasUncertainNetworkMutationOutcome
            self.isLockedByUnknownOutcome = isLockedByUnknownOutcome
            self.allowsConcurrentMutationWhileLocked = allowsConcurrentMutationWhileLocked
            self.underlyingSpawnExpiredOrRemoved = underlyingSpawnExpiredOrRemoved
            self.activeAttemptPreservedAfterSpawnRemoval = activeAttemptPreservedAfterSpawnRemoval
        }
    }

    public enum AttemptLifecycleResilienceVerdict: Sendable, Equatable {
        case resilientAndCompliant(attemptID: String, isLockedByUnknownOutcome: Bool)
        case missingUnknownOutcomeReadbackLockViolation(attemptID: String)
        case concurrentMutationAllowedWhileLockedViolation(attemptID: String)
        case attemptDroppedOnSpawnExpiryOrRemovalViolation(attemptID: String)
    }

    public static func auditAttemptLifecycleResilience(_ input: AttemptLifecycleResilienceAuditInput) -> AttemptLifecycleResilienceVerdict {
        if input.hasUncertainNetworkMutationOutcome && !input.isLockedByUnknownOutcome {
            return .missingUnknownOutcomeReadbackLockViolation(attemptID: input.attemptID)
        }
        if input.isLockedByUnknownOutcome && input.allowsConcurrentMutationWhileLocked {
            return .concurrentMutationAllowedWhileLockedViolation(attemptID: input.attemptID)
        }
        if input.underlyingSpawnExpiredOrRemoved && !input.activeAttemptPreservedAfterSpawnRemoval {
            return .attemptDroppedOnSpawnExpiryOrRemovalViolation(attemptID: input.attemptID)
        }
        return .resilientAndCompliant(
            attemptID: input.attemptID,
            isLockedByUnknownOutcome: input.isLockedByUnknownOutcome
        )
    }

    // MARK: - 5. Personal Fog revealSyncEnabled Default-Off & Disjoint Cell Counts

    public struct PersonalFogHostAuditInput: Sendable, Equatable {
        public let revealSyncEnabledByDefault: Bool
        public let confirmedCells: Set<String>
        public let predictedCells: Set<String>

        public var confirmedCellCount: Int {
            confirmedCells.count
        }

        public var predictedCellCount: Int {
            predictedCells.count
        }

        public init(
            revealSyncEnabledByDefault: Bool = false,
            confirmedCells: Set<String> = ["cell-c1", "cell-c2"],
            predictedCells: Set<String> = ["cell-p1"]
        ) {
            self.revealSyncEnabledByDefault = revealSyncEnabledByDefault
            self.confirmedCells = confirmedCells
            self.predictedCells = predictedCells
        }
    }

    public enum PersonalFogHostAuditVerdict: Sendable, Equatable {
        case compliant(confirmedCount: Int, predictedCount: Int)
        case revealSyncDefaultNotOffViolation
        case overlappingConfirmedAndPredictedCellsViolation(overlap: Set<String>)
    }

    public static func auditPersonalFogHost(_ input: PersonalFogHostAuditInput) -> PersonalFogHostAuditVerdict {
        guard !input.revealSyncEnabledByDefault else {
            return .revealSyncDefaultNotOffViolation
        }
        let overlap = input.confirmedCells.intersection(input.predictedCells)
        guard overlap.isEmpty else {
            return .overlappingConfirmedAndPredictedCellsViolation(overlap: overlap)
        }
        return .compliant(
            confirmedCount: input.confirmedCellCount,
            predictedCount: input.predictedCellCount
        )
    }

    // MARK: - Unified Summary Report

    public struct FullHostAuditReport: Sendable, Equatable {
        public let featureGateVerdict: FeatureGateAuditVerdict
        public let spawnDiscoverabilityVerdict: SpawnDiscoverabilityVerdict
        public let photoEvidenceVerdict: PhotoEvidenceAuditVerdict
        public let attemptResilienceVerdict: AttemptLifecycleResilienceVerdict
        public let personalFogVerdict: PersonalFogHostAuditVerdict

        public var isCompliant: Bool {
            guard case .compliant = featureGateVerdict else { return false }
            switch spawnDiscoverabilityVerdict {
            case .discoverableIndependent, .discoverableThemeBound, .hiddenThemeMismatch:
                break
            case .invalidEmptyThemeReleaseID:
                return false
            }
            switch photoEvidenceVerdict {
            case .awaitingAuthoritativeReview, .completedAfterAuthoritativeReadback:
                break
            case .forbiddenLocalAutoCompleteViolation:
                return false
            }
            guard case .resilientAndCompliant = attemptResilienceVerdict else { return false }
            guard case .compliant = personalFogVerdict else { return false }
            return true
        }

        public init(
            featureGateVerdict: FeatureGateAuditVerdict,
            spawnDiscoverabilityVerdict: SpawnDiscoverabilityVerdict,
            photoEvidenceVerdict: PhotoEvidenceAuditVerdict,
            attemptResilienceVerdict: AttemptLifecycleResilienceVerdict,
            personalFogVerdict: PersonalFogHostAuditVerdict
        ) {
            self.featureGateVerdict = featureGateVerdict
            self.spawnDiscoverabilityVerdict = spawnDiscoverabilityVerdict
            self.photoEvidenceVerdict = photoEvidenceVerdict
            self.attemptResilienceVerdict = attemptResilienceVerdict
            self.personalFogVerdict = personalFogVerdict
        }
    }
}

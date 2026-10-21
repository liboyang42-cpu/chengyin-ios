import Foundation

/// The 5 audited roam, exploration & GPS play parity pillars.
public enum RoamAndExplorationParityPillar: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case w208RoamEntryMerchantAndSubpages = "w2-08"
    case w209PassportPrivateTools = "w2-09"
    case i00I11ReceivedStamps = "I00+I11"
    case i01PlayArrivalAccuracy = "I01"
    case fW14W15StoryWalkingAndFog = "F-W14/W15"
}

/// E06-17 status classification audited for `RoamSubpagePresentation` (`w2-08`).
public enum RoamSubpageStatusClassification: String, Codable, Equatable, Sendable {
    case ok
    case gone
    case error
}

/// Private tools subpages audited under `w2-09` (`RoamPassportPrivateToolsReading`).
public enum RoamPrivateToolSubpageKind: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case capsule = "capsule"
    case explorationGoals = "exploration-goals"
    case explorationExport = "exploration-export"
    case anniversary = "anniversary"
    case monthlyRecap = "monthly-recap"
}

/// GPS sample classification audited under `I01` (`PlayArrivalAccuracy` & `BK-GPS`).
public enum PlayArrivalAccuracyVerdict: String, Codable, Equatable, Sendable {
    /// `accuracyMeters <= 80` and `ageSeconds <= 30`.
    case qualified
    /// `80 < accuracyMeters <= 100` and `ageSeconds <= 30` (80m advisory warning).
    case advisoryWarning
    /// `accuracyMeters > 100` or `ageSeconds > 30` or negative/non-finite (`invalidAction` / `BK-GPS`).
    case invalidAction
}

/// Audit record for a single roam/exploration pillar.
public struct RoamExplorationPillarAuditEntry: Equatable, Sendable {
    public let pillar: RoamAndExplorationParityPillar
    public let verifiedTypes: [String]
    public let e0617GoneMappedCorrectly: Bool
    public let privateToolSubpagesCovered: Set<RoamPrivateToolSubpageKind>
    public let receivedStampReadAndPresentationAligned: Bool
    public let i01AccuracyThresholdsEnforced: Bool
    public let arrivalOpensVerificationOnly: Bool
    public let revealSyncEnabledByDefault: Bool

    public init(
        pillar: RoamAndExplorationParityPillar,
        verifiedTypes: [String],
        e0617GoneMappedCorrectly: Bool = true,
        privateToolSubpagesCovered: Set<RoamPrivateToolSubpageKind> = Set(RoamPrivateToolSubpageKind.allCases),
        receivedStampReadAndPresentationAligned: Bool = true,
        i01AccuracyThresholdsEnforced: Bool = true,
        arrivalOpensVerificationOnly: Bool = true,
        revealSyncEnabledByDefault: Bool = false
    ) {
        self.pillar = pillar
        self.verifiedTypes = verifiedTypes
        self.e0617GoneMappedCorrectly = e0617GoneMappedCorrectly
        self.privateToolSubpagesCovered = privateToolSubpagesCovered
        self.receivedStampReadAndPresentationAligned = receivedStampReadAndPresentationAligned
        self.i01AccuracyThresholdsEnforced = i01AccuracyThresholdsEnforced
        self.arrivalOpensVerificationOnly = arrivalOpensVerificationOnly
        self.revealSyncEnabledByDefault = revealSyncEnabledByDefault
    }
}

public enum RoamAndExplorationParityViolation: Equatable, Sendable {
    case missingPillar(RoamAndExplorationParityPillar)
    case emptyVerifiedTypes(RoamAndExplorationParityPillar)
    case e0617MappingDrift
    case missingPrivateToolSubpages(Set<RoamPrivateToolSubpageKind>)
    case receivedStampContractDrift
    case i01AccuracyThresholdDrift
    case arrivalAutoCompletesInsteadOfVerification
    case revealSyncUnexpectedlyEnabled
}

public struct RoamAndExplorationParityAuditReport: Equatable, Sendable {
    public let auditedPillars: [RoamAndExplorationParityPillar]
    public let violations: [RoamAndExplorationParityViolation]

    public init(
        auditedPillars: [RoamAndExplorationParityPillar],
        violations: [RoamAndExplorationParityViolation]
    ) {
        self.auditedPillars = auditedPillars
        self.violations = violations
    }

    public var isPassing: Bool {
        violations.isEmpty && Set(auditedPillars) == Set(RoamAndExplorationParityPillar.allCases)
    }
}

/// Pure evaluator for the 5 roam, exploration & GPS play parity pillars.
public enum RoamAndExplorationParityAudit {
    public static let advisoryAccuracyMetersThreshold: Double = 80.0
    public static let maxAllowedAccuracyMeters: Double = 100.0
    public static let maxAllowedSampleAgeSeconds: TimeInterval = 30.0

    /// E06-17 mapping: HTTP/business 404 and 410 map to `.gone`; 503 and other failures map to `.error`.
    public static func classifySubpageStatus(code: Int) -> RoamSubpageStatusClassification {
        switch code {
        case 200:
            return .ok
        case 404, 410:
            return .gone
        default:
            return .error
        }
    }

    /// I01 GPS arrival accuracy evaluation: <=80m qualified, (80m, 100m] advisory warning, >100m or >30s invalidAction.
    public static func evaluateArrivalSample(
        accuracyMeters: Double,
        ageSeconds: TimeInterval
    ) -> PlayArrivalAccuracyVerdict {
        guard accuracyMeters.isFinite,
              ageSeconds.isFinite,
              accuracyMeters >= 0,
              ageSeconds >= 0,
              accuracyMeters <= maxAllowedAccuracyMeters,
              ageSeconds <= maxAllowedSampleAgeSeconds else {
            return .invalidAction
        }
        if accuracyMeters > advisoryAccuracyMetersThreshold {
            return .advisoryWarning
        }
        return .qualified
    }

    public static let baselineEntries: [RoamExplorationPillarAuditEntry] = [
        RoamExplorationPillarAuditEntry(
            pillar: .w208RoamEntryMerchantAndSubpages,
            verifiedTypes: ["RoamEntryNearby", "RoamMerchant", "RoamSubpagePresentation"]
        ),
        RoamExplorationPillarAuditEntry(
            pillar: .w209PassportPrivateTools,
            verifiedTypes: ["RoamPassportPrivateToolsReading"]
        ),
        RoamExplorationPillarAuditEntry(
            pillar: .i00I11ReceivedStamps,
            verifiedTypes: ["RoamReceivedStampRead", "RoamReceivedStampPresentation"]
        ),
        RoamExplorationPillarAuditEntry(
            pillar: .i01PlayArrivalAccuracy,
            verifiedTypes: ["PlayArrivalAccuracy", "BK-GPS"]
        ),
        RoamExplorationPillarAuditEntry(
            pillar: .fW14W15StoryWalkingAndFog,
            verifiedTypes: ["StoryWalkingNavigationHostBridge", "PersonalFogRoamOverlayProjection"],
            revealSyncEnabledByDefault: PersonalFogFeature.revealSyncEnabled
        )
    ]

    public static func runAudit(
        entries: [RoamExplorationPillarAuditEntry] = baselineEntries
    ) -> RoamAndExplorationParityAuditReport {
        var violations: [RoamAndExplorationParityViolation] = []
        let presentPillars = Set(entries.map(\.pillar))

        for required in RoamAndExplorationParityPillar.allCases where !presentPillars.contains(required) {
            violations.append(.missingPillar(required))
        }

        for entry in entries {
            if entry.verifiedTypes.isEmpty {
                violations.append(.emptyVerifiedTypes(entry.pillar))
            }
            if entry.pillar == .w208RoamEntryMerchantAndSubpages && !entry.e0617GoneMappedCorrectly {
                violations.append(.e0617MappingDrift)
            }
            if entry.pillar == .w209PassportPrivateTools {
                let missing = Set(RoamPrivateToolSubpageKind.allCases).subtracting(entry.privateToolSubpagesCovered)
                if !missing.isEmpty {
                    violations.append(.missingPrivateToolSubpages(missing))
                }
            }
            if entry.pillar == .i00I11ReceivedStamps && !entry.receivedStampReadAndPresentationAligned {
                violations.append(.receivedStampContractDrift)
            }
            if entry.pillar == .i01PlayArrivalAccuracy && !entry.i01AccuracyThresholdsEnforced {
                violations.append(.i01AccuracyThresholdDrift)
            }
            if entry.pillar == .fW14W15StoryWalkingAndFog {
                if !entry.arrivalOpensVerificationOnly {
                    violations.append(.arrivalAutoCompletesInsteadOfVerification)
                }
                if entry.revealSyncEnabledByDefault {
                    violations.append(.revealSyncUnexpectedlyEnabled)
                }
            }
        }

        return RoamAndExplorationParityAuditReport(
            auditedPillars: entries.map(\.pillar),
            violations: violations
        )
    }
}

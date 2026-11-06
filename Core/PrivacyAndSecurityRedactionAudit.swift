import Foundation

/// Unified privacy, consent, and redaction audit across Wave 2, Wave 3, and Reform Plan v9:
/// 1. `W19` private-home return/restore coordinate redaction (`[redacted]` descriptions, zero coordinate export),
/// 2. `W13.5` location sharing 6-disclosure gate and OS location permission decoupling,
/// 3. `G-W04` & `I08` NPC AI sensitive data class filtering and `AI-DELETE` fail-closed remote deletion fence,
/// 4. `I05` `SquareWorkspacePrivacy` `URLCache` media eviction on 404/DELETED responses.
public enum PrivacyAndSecurityRedactionAudit {

    // MARK: - Pillar Enumeration & Violation Types

    public enum Pillar: String, CaseIterable, Equatable, Sendable {
        case privateHomeRedaction = "W19_PRIVATE_HOME_REDACTION"
        case locationSharingDisclosureGate = "W13_5_LOCATION_SHARING_CONSENT"
        case npcAIDataIsolationAndDeleteFence = "G_W04_I08_NPC_AI_PRIVACY"
        case squareMediaCacheEviction = "I05_SQUARE_MEDIA_EVICTION"
    }

    public enum AuditViolation: Equatable, Sendable {
        case unredactedCoordinateOrPII(sample: String)
        case missingRedactedMarker(description: String)
        case osPermissionTreatedAsSharingConsent
        case incompleteLocationShareDisclosures(missingCount: Int)
        case locationSharePreciseGrantUnexpectedlyEnabled
        case forbiddenNPCAIDataClassExposed(scenario: String, dataClass: String)
        case npcRemoteDeleteEnabledWithoutApproval
        case npcUnknownDeleteRetriedAutomatically
        case revokedPostMediaRetainedInCache(urlCount: Int)
    }

    // MARK: - Pillar 1: W19 Private-Home Coordinate Redaction Audit

    public struct PrivateHomeRedactionEvaluation: Equatable, Sendable {
        public let checkDescription: String
        public let debugDescription: String
        public let hasRedactedMarker: Bool
        public let containsRawCoordinateOrPII: Bool
        public let violations: [AuditViolation]

        public var isCompliant: Bool { violations.isEmpty && hasRedactedMarker && !containsRawCoordinateOrPII }

        public init(
            checkDescription: String,
            debugDescription: String,
            diagnosticSamples: [String] = []
        ) {
            self.checkDescription = checkDescription
            self.debugDescription = debugDescription
            self.hasRedactedMarker = checkDescription == "HomeReturnCheck[redacted]"
                && debugDescription == "HomeReturnCheck[redacted]"

            var foundViolations: [AuditViolation] = []
            if !self.hasRedactedMarker {
                foundViolations.append(.missingRedactedMarker(description: checkDescription))
            }

            let allSamples = [checkDescription, debugDescription] + diagnosticSamples
            var leaked = false
            for sample in allSamples {
                if PrivacyAndSecurityRedactionAudit.containsCoordinateOrPIILeak(sample) {
                    leaked = true
                    foundViolations.append(.unredactedCoordinateOrPII(sample: sample))
                }
            }
            self.containsRawCoordinateOrPII = leaked
            self.violations = foundViolations
        }
    }

    /// Detects raw latitude/longitude key-value patterns, decimal coordinate pairs, or phone numbers in logs/descriptions.
    public static func containsCoordinateOrPIILeak(_ text: String) -> Bool {
        let lower = text.lowercased()
        for token in ["latitude", "longitude", "lat:", "lng:", "lon:", "coord:"] {
            if lower.contains(token) {
                return true
            }
        }
        // Decimal degree coordinate pair pattern e.g. "31.2304, 121.4737"
        if text.range(of: #"-?\d{1,3}\.\d{3,}\s*,\s*-?\d{1,3}\.\d{3,}"#, options: .regularExpression) != nil {
            return true
        }
        // Unredacted 11-digit mainland mobile number pattern
        if text.range(of: #"\b1[3-9]\d{9}\b"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    public static func auditPrivateHomeCheck(
        _ check: HomeReturnCheck,
        additionalDiagnosticSamples: [String] = []
    ) -> PrivateHomeRedactionEvaluation {
        PrivateHomeRedactionEvaluation(
            checkDescription: String(describing: check),
            debugDescription: String(reflecting: check),
            diagnosticSamples: additionalDiagnosticSamples
        )
    }

    // MARK: - Pillar 2: W13.5 Location Sharing 6-Disclosure Gate & OS Permission Decoupling

    public struct LocationSharingConsentEvaluation: Equatable, Sendable {
        public static let requiredDisclosureCount = 6

        public let osPermissionGranted: Bool
        public let acknowledgedDisclosureCount: Int
        public let missingDisclosureKeys: [String]
        public let preciseGrantDefaultDisabled: Bool
        public let canFormShareGrantRequest: Bool
        public let violations: [AuditViolation]

        public var isCompliant: Bool { violations.isEmpty }

        public init(
            draft: LocationShareDraft,
            osPermissionGranted: Bool,
            treatsOSPermissionAsSharingConsent: Bool = false
        ) {
            self.osPermissionGranted = osPermissionGranted
            let missing = draft.missingDisclosures.map(\.rawValue)
            self.missingDisclosureKeys = missing
            self.acknowledgedDisclosureCount = LocationShareDisclosure.allCases.count - missing.count
            self.preciseGrantDefaultDisabled = !LocationShareFeature.preciseGrantEnabled

            let validAudience = draft.audience?.isValid == true
            self.canFormShareGrantRequest = validAudience
                && missing.isEmpty
                && LocationShareFeature.preciseGrantEnabled

            var foundViolations: [AuditViolation] = []
            if treatsOSPermissionAsSharingConsent {
                foundViolations.append(.osPermissionTreatedAsSharingConsent)
            }
            if !self.preciseGrantDefaultDisabled {
                foundViolations.append(.locationSharePreciseGrantUnexpectedlyEnabled)
            }
            if !missing.isEmpty {
                foundViolations.append(.incompleteLocationShareDisclosures(missingCount: missing.count))
            }
            self.violations = foundViolations
        }
    }

    public static func auditLocationSharingConsent(
        draft: LocationShareDraft,
        osPermissionGranted: Bool,
        treatsOSPermissionAsSharingConsent: Bool = false
    ) -> LocationSharingConsentEvaluation {
        LocationSharingConsentEvaluation(
            draft: draft,
            osPermissionGranted: osPermissionGranted,
            treatsOSPermissionAsSharingConsent: treatsOSPermissionAsSharingConsent
        )
    }

    // MARK: - Pillar 3: G-W04 & I08 NPC AI Sensitive Data Filtering & AI-DELETE Fence

    public struct NPCAIPrivacyAndDeleteEvaluation: Equatable, Sendable {
        public let allScenariosDisjoint: Bool
        public let universalForbiddenClassesBlocked: Bool
        public let deleteEndpointPath: String
        public let remoteDeleteDefaultDisabled: Bool
        public let unknownOutcomeRequiresExportReadback: Bool
        public let violations: [AuditViolation]

        public var isCompliant: Bool { violations.isEmpty }

        public init(
            remoteDeleteEnabledWithoutApproval: Bool = false,
            autoRetriesUnknownDelete: Bool = false
        ) {
            self.deleteEndpointPath = NPCChatLogDeletion.path
            self.remoteDeleteDefaultDisabled = !MerchantAICommerceGates.reviewedEndpoints.contains(NPCChatLogDeletion.path)
                && !remoteDeleteEnabledWithoutApproval
            self.unknownOutcomeRequiresExportReadback = !autoRetriesUnknownDelete

            let universalForbidden: [SceneAIDataClass] = [
                .lockedCluesAndEndings,
                .otherThemeContent,
                .otherPlayerMemory,
                .merchantPriceFloor,
                .unpurchasedAnswers
            ]

            var disjointOK = true
            var forbiddenOK = true
            var foundViolations: [AuditViolation] = []

            for scenario in SceneAIScenario.allCases {
                if !scenario.allowedData.isDisjoint(with: scenario.forbiddenData) {
                    disjointOK = false
                }
                for dataClass in universalForbidden where scenario.allowedData.contains(dataClass) {
                    forbiddenOK = false
                    foundViolations.append(
                        .forbiddenNPCAIDataClassExposed(scenario: scenario.rawValue, dataClass: dataClass.rawValue)
                    )
                }
                if scenario != .merchantPrivateAssistant,
                   scenario.allowedData.contains(.privateStoreOperations) {
                    forbiddenOK = false
                    foundViolations.append(
                        .forbiddenNPCAIDataClassExposed(
                            scenario: scenario.rawValue,
                            dataClass: SceneAIDataClass.privateStoreOperations.rawValue
                        )
                    )
                }
            }

            if remoteDeleteEnabledWithoutApproval {
                foundViolations.append(.npcRemoteDeleteEnabledWithoutApproval)
            }
            if autoRetriesUnknownDelete {
                foundViolations.append(.npcUnknownDeleteRetriedAutomatically)
            }

            self.allScenariosDisjoint = disjointOK
            self.universalForbiddenClassesBlocked = forbiddenOK
            self.violations = foundViolations
        }
    }

    public static func auditNPCAIPrivacyAndDeleteFence(
        remoteDeleteEnabledWithoutApproval: Bool = false,
        autoRetriesUnknownDelete: Bool = false
    ) -> NPCAIPrivacyAndDeleteEvaluation {
        NPCAIPrivacyAndDeleteEvaluation(
            remoteDeleteEnabledWithoutApproval: remoteDeleteEnabledWithoutApproval,
            autoRetriesUnknownDelete: autoRetriesUnknownDelete
        )
    }

    // MARK: - Pillar 4: I05 SquareWorkspacePrivacy URLCache Media Eviction on 404 / DELETED

    public struct SquareMediaEvictionEvaluation: Equatable, Sendable {
        public let isRevocationEvent: Bool
        public let candidateAbsoluteURLs: Set<URL>
        public let evictedURLs: Set<URL>
        public let violations: [AuditViolation]

        public var isCompliant: Bool { violations.isEmpty }

        public init(
            httpOrBusinessCode: Int?,
            postLifecycle: String?,
            rawMediaURLStrings: [String],
            evictedURLs: Set<URL>
        ) {
            let revokedByCode = httpOrBusinessCode == 404
            let revokedByLifecycle = postLifecycle?.uppercased() == "DELETED"
            let isRevoked = revokedByCode || revokedByLifecycle
            self.isRevocationEvent = isRevoked

            let validURLs = Set(rawMediaURLStrings.compactMap { raw -> URL? in
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let url = URL(string: trimmed),
                      let scheme = url.scheme?.lowercased(),
                      scheme == "http" || scheme == "https",
                      url.host != nil else {
                    return nil
                }
                return url
            })
            self.candidateAbsoluteURLs = validURLs
            self.evictedURLs = evictedURLs

            var foundViolations: [AuditViolation] = []
            if isRevoked {
                let retained = validURLs.subtracting(evictedURLs)
                if !retained.isEmpty {
                    foundViolations.append(.revokedPostMediaRetainedInCache(urlCount: retained.count))
                }
            }
            self.violations = foundViolations
        }
    }

    public static func auditSquareMediaEviction(
        httpOrBusinessCode: Int?,
        postLifecycle: String?,
        rawMediaURLStrings: [String],
        evictedURLs: Set<URL>
    ) -> SquareMediaEvictionEvaluation {
        SquareMediaEvictionEvaluation(
            httpOrBusinessCode: httpOrBusinessCode,
            postLifecycle: postLifecycle,
            rawMediaURLStrings: rawMediaURLStrings,
            evictedURLs: evictedURLs
        )
    }

    // MARK: - Aggregate 4-Pillar Summary

    public struct FullPrivacyAuditReport: Equatable, Sendable {
        public let homeRedaction: PrivateHomeRedactionEvaluation
        public let locationSharing: LocationSharingConsentEvaluation
        public let npcAIPrivacy: NPCAIPrivacyAndDeleteEvaluation
        public let squareMediaEviction: SquareMediaEvictionEvaluation

        public var allPillarsCompliant: Bool {
            homeRedaction.isCompliant
                && locationSharing.isCompliant
                && npcAIPrivacy.isCompliant
                && squareMediaEviction.isCompliant
        }

        public var allViolations: [AuditViolation] {
            homeRedaction.violations
                + locationSharing.violations
                + npcAIPrivacy.violations
                + squareMediaEviction.violations
        }

        public init(
            homeRedaction: PrivateHomeRedactionEvaluation,
            locationSharing: LocationSharingConsentEvaluation,
            npcAIPrivacy: NPCAIPrivacyAndDeleteEvaluation,
            squareMediaEviction: SquareMediaEvictionEvaluation
        ) {
            self.homeRedaction = homeRedaction
            self.locationSharing = locationSharing
            self.npcAIPrivacy = npcAIPrivacy
            self.squareMediaEviction = squareMediaEviction
        }
    }
}

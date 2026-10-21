import Foundation

/// Comprehensive audit and verification gate for the 5 Merchant & Publish Authoring pillars:
/// 1. `I03` & `w2-11/13`: `ProjectEditStoryContract.validatePayload` & `ProjectEditRichStoryContract.attachEndings` boolean-only `fallback` validation.
/// 2. `w2-17/18/19`: Merchant store parity (`poi/detail`, `decor/save` JSON body, `shop/apply` 4-step wizard, `npc/voice/status`, `merchant/insight` top-level keys).
/// 3. `G-W05`: `MerchantInStoreGameAuthoringPresentation` 3-part authoring, `maxParticipants` capacity, canonical SKU binding, and dual-domain approvals.
/// 4. `H-W02 / U01`: `PublishMediaEditorBridge` content ownership (`CREATOR`/`CLUB`/`MERCHANT`/`PLATFORM`), cross-owner/cross-world edit refusal, 7-stage media pipeline, and video poster enforcement.
/// 5. `H-W18`: `WorkshopModUpgradePresentation` pinned active run isolation, H5 design-only package guard, and explicit upgrade confirmation.
public enum MerchantAndPublishAuthoringAudit {

    // MARK: - Pillar 1: I03 & w2-11/13 (Story Ending Boolean-Only Fallback Validation)

    public enum JSONScalarOrValue: Sendable, Equatable {
        case bool(Bool)
        case string(String)
        case int(Int)
        case double(Double)
        case null
        case array([JSONScalarOrValue])
        case object([String: JSONScalarOrValue])
    }

    public struct StoryEndingAuditItem: Sendable, Equatable {
        public let chapterID: Int
        public let isOpening: Bool
        public let recruitEnabled: Bool
        public let nodeCount: Int
        public let fallbackValue: JSONScalarOrValue?
        public let whenConditionCount: Int

        public init(
            chapterID: Int,
            isOpening: Bool = false,
            recruitEnabled: Bool = false,
            nodeCount: Int = 0,
            fallbackValue: JSONScalarOrValue?,
            whenConditionCount: Int
        ) {
            self.chapterID = chapterID
            self.isOpening = isOpening
            self.recruitEnabled = recruitEnabled
            self.nodeCount = nodeCount
            self.fallbackValue = fallbackValue
            self.whenConditionCount = whenConditionCount
        }
    }

    public enum StoryEndingAuditVerdict: Sendable, Equatable {
        case valid(endingCount: Int, fallbackChapterID: Int?)
        case rejectedNonBooleanFallback(chapterID: Int, actualValue: JSONScalarOrValue)
        case rejectedInvalidEndingChapterShape(chapterID: Int)
        case rejectedMissingOrInvalidWhenConditions(chapterID: Int, count: Int)
        case rejectedFallbackCountMismatch(endingCount: Int, fallbackCount: Int)
    }

    /// Audits `ProjectEditStoryContract.validatePayload` and `ProjectEditRichStoryContract.attachEndings`
    /// parity (`I03`, `w2-11`, `w2-13`): `fallback` when present MUST be a JSON boolean (`true` or `false`);
    /// strings (`"true"`), numbers (`1`), and `null` are strictly rejected.
    public static func auditStoryEndings(_ endings: [StoryEndingAuditItem]) -> StoryEndingAuditVerdict {
        guard !endings.isEmpty else {
            return .valid(endingCount: 0, fallbackChapterID: nil)
        }

        var fallbackChapterIDs: [Int] = []

        for item in endings {
            guard item.chapterID > 0, !item.isOpening, !item.recruitEnabled, item.nodeCount == 0 else {
                return .rejectedInvalidEndingChapterShape(chapterID: item.chapterID)
            }

            let isFallback: Bool
            if let rawFallback = item.fallbackValue {
                switch rawFallback {
                case .bool(let flag):
                    isFallback = flag
                default:
                    return .rejectedNonBooleanFallback(chapterID: item.chapterID, actualValue: rawFallback)
                }
            } else {
                isFallback = false
            }

            if isFallback {
                fallbackChapterIDs.append(item.chapterID)
            } else {
                guard (1...16).contains(item.whenConditionCount) else {
                    return .rejectedMissingOrInvalidWhenConditions(
                        chapterID: item.chapterID,
                        count: item.whenConditionCount
                    )
                }
            }
        }

        guard fallbackChapterIDs.count == 1 else {
            return .rejectedFallbackCountMismatch(
                endingCount: endings.count,
                fallbackCount: fallbackChapterIDs.count
            )
        }

        return .valid(endingCount: endings.count, fallbackChapterID: fallbackChapterIDs.first)
    }

    // MARK: - Pillar 2: w2-17/18/19 (Merchant Store Parity)

    public enum ShopApplyWizardStep: String, CaseIterable, Sendable, Equatable {
        case basicInfo = "BASIC_INFO"
        case qualificationLicense = "QUALIFICATION_LICENSE"
        case storefrontMedia = "STOREFRONT_MEDIA"
        case settlementAgreement = "SETTLEMENT_AGREEMENT"
    }

    public struct MerchantStoreParitySnapshot: Sendable, Equatable {
        public static let poiDetailEndpoint = "api/merchant/poi/detail"
        public static let decorSaveEndpoint = "api/merchant/decor/save"
        public static let shopApplyEndpoint = "api/merchant/shop/apply"
        public static let npcVoiceStatusEndpoint = "api/merchant/npc/voice/status"
        public static let merchantInsightEndpoint = "api/merchant/insight"

        public static let canonicalInsightTopLevelKeys: Set<String> = [
            "exposureCount",
            "checkInCount",
            "conversionRate",
            "repeatVisitRate",
            "couponRedemptionCount"
        ]

        public let poiDetailPath: String
        public let decorSavePath: String
        public let decorSaveUsesJSONBody: Bool
        public let decorSaveBodyKeys: Set<String>
        public let shopApplyWizardSteps: [ShopApplyWizardStep]
        public let npcVoiceStatusPath: String
        public let insightTopLevelKeys: Set<String>

        public init(
            poiDetailPath: String = Self.poiDetailEndpoint,
            decorSavePath: String = Self.decorSaveEndpoint,
            decorSaveUsesJSONBody: Bool = true,
            decorSaveBodyKeys: Set<String> = ["merchantId", "decorConfig", "themeVersion"],
            shopApplyWizardSteps: [ShopApplyWizardStep] = ShopApplyWizardStep.allCases,
            npcVoiceStatusPath: String = Self.npcVoiceStatusEndpoint,
            insightTopLevelKeys: Set<String> = Self.canonicalInsightTopLevelKeys
        ) {
            self.poiDetailPath = poiDetailPath
            self.decorSavePath = decorSavePath
            self.decorSaveUsesJSONBody = decorSaveUsesJSONBody
            self.decorSaveBodyKeys = decorSaveBodyKeys
            self.shopApplyWizardSteps = shopApplyWizardSteps
            self.npcVoiceStatusPath = npcVoiceStatusPath
            self.insightTopLevelKeys = insightTopLevelKeys
        }
    }

    public enum MerchantStoreParityVerdict: Sendable, Equatable {
        case compliant
        case endpointMismatch(expected: String, actual: String)
        case decorSaveInvalidBody
        case incompleteShopApplyWizard(steps: [ShopApplyWizardStep])
        case missingInsightTopLevelKeys(missing: Set<String>)
    }

    public static func auditMerchantStoreParity(_ snapshot: MerchantStoreParitySnapshot) -> MerchantStoreParityVerdict {
        guard snapshot.poiDetailPath == MerchantStoreParitySnapshot.poiDetailEndpoint else {
            return .endpointMismatch(
                expected: MerchantStoreParitySnapshot.poiDetailEndpoint,
                actual: snapshot.poiDetailPath
            )
        }
        guard snapshot.decorSavePath == MerchantStoreParitySnapshot.decorSaveEndpoint else {
            return .endpointMismatch(
                expected: MerchantStoreParitySnapshot.decorSaveEndpoint,
                actual: snapshot.decorSavePath
            )
        }
        guard snapshot.decorSaveUsesJSONBody,
              snapshot.decorSaveBodyKeys.contains("merchantId"),
              snapshot.decorSaveBodyKeys.contains("decorConfig") else {
            return .decorSaveInvalidBody
        }
        guard snapshot.shopApplyWizardSteps == ShopApplyWizardStep.allCases else {
            return .incompleteShopApplyWizard(steps: snapshot.shopApplyWizardSteps)
        }
        guard snapshot.npcVoiceStatusPath == MerchantStoreParitySnapshot.npcVoiceStatusEndpoint else {
            return .endpointMismatch(
                expected: MerchantStoreParitySnapshot.npcVoiceStatusEndpoint,
                actual: snapshot.npcVoiceStatusPath
            )
        }
        let missingKeys = MerchantStoreParitySnapshot.canonicalInsightTopLevelKeys.subtracting(snapshot.insightTopLevelKeys)
        guard missingKeys.isEmpty else {
            return .missingInsightTopLevelKeys(missing: missingKeys)
        }
        return .compliant
    }

    // MARK: - Pillar 3: G-W05 (MerchantInStoreGameAuthoringPresentation)

    public enum InStoreGameAuthoringPart: String, CaseIterable, Sendable, Equatable {
        case spaceAndNpcSetup = "SPACE_AND_NPC_SETUP"
        case taskAndRuleFlow = "TASK_AND_RULE_FLOW"
        case rewardAndSettlement = "REWARD_AND_SETTLEMENT"
    }

    public struct InStoreGameAuthoringAuditInput: Sendable, Equatable {
        public let completedParts: [InStoreGameAuthoringPart]
        public let maxParticipants: Int
        public let canonicalSkuID: String
        public let merchantStoreApproved: Bool
        public let contentSafetyApproved: Bool

        public init(
            completedParts: [InStoreGameAuthoringPart],
            maxParticipants: Int,
            canonicalSkuID: String,
            merchantStoreApproved: Bool,
            contentSafetyApproved: Bool
        ) {
            self.completedParts = completedParts
            self.maxParticipants = maxParticipants
            self.canonicalSkuID = canonicalSkuID
            self.merchantStoreApproved = merchantStoreApproved
            self.contentSafetyApproved = contentSafetyApproved
        }
    }

    public enum InStoreGameAuthoringVerdict: Sendable, Equatable {
        case readyForPublish(boundSkuID: String, maxParticipants: Int)
        case incompleteThreePartAuthoring(completed: [InStoreGameAuthoringPart])
        case invalidMaxParticipantsCapacity(Int)
        case missingCanonicalSkuBinding
        case pendingDualDomainApproval(merchantStoreApproved: Bool, contentSafetyApproved: Bool)
    }

    public static func auditInStoreGameAuthoring(_ input: InStoreGameAuthoringAuditInput) -> InStoreGameAuthoringVerdict {
        guard input.completedParts == InStoreGameAuthoringPart.allCases else {
            return .incompleteThreePartAuthoring(completed: input.completedParts)
        }
        guard (1...500).contains(input.maxParticipants) else {
            return .invalidMaxParticipantsCapacity(input.maxParticipants)
        }
        let trimmedSku = input.canonicalSkuID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSku.isEmpty, trimmedSku.hasPrefix("SKU-") else {
            return .missingCanonicalSkuBinding
        }
        guard input.merchantStoreApproved && input.contentSafetyApproved else {
            return .pendingDualDomainApproval(
                merchantStoreApproved: input.merchantStoreApproved,
                contentSafetyApproved: input.contentSafetyApproved
            )
        }
        return .readyForPublish(boundSkuID: trimmedSku, maxParticipants: input.maxParticipants)
    }

    // MARK: - Pillar 4: H-W02 / U01 (PublishMediaEditorBridge Ownership & 7-Stage Pipeline)

    public enum ContentOwnerDomain: String, CaseIterable, Sendable, Equatable {
        case creator = "CREATOR"
        case club = "CLUB"
        case merchant = "MERCHANT"
        case platform = "PLATFORM"
    }

    public enum MediaPipelineStage: String, CaseIterable, Sendable, Equatable {
        case ingest = "INGEST"
        case transcode = "TRANSCODE"
        case posterExtract = "POSTER_EXTRACT"
        case watermarkAudit = "WATERMARK_AUDIT"
        case contentSafetyScan = "CONTENT_SAFETY_SCAN"
        case cdnUpload = "CDN_UPLOAD"
        case commitDraft = "COMMIT_DRAFT"
    }

    public struct PublishMediaEditorAuditInput: Sendable, Equatable {
        public let resourceOwnerDomain: ContentOwnerDomain
        public let resourceOwnerID: Int
        public let resourceWorldID: String
        public let actorOwnerDomain: ContentOwnerDomain
        public let actorOwnerID: Int
        public let actorWorldID: String
        public let executedStages: [MediaPipelineStage]
        public let hasVideoAttachment: Bool
        public let videoPosterURL: String?

        public init(
            resourceOwnerDomain: ContentOwnerDomain,
            resourceOwnerID: Int,
            resourceWorldID: String,
            actorOwnerDomain: ContentOwnerDomain,
            actorOwnerID: Int,
            actorWorldID: String,
            executedStages: [MediaPipelineStage] = MediaPipelineStage.allCases,
            hasVideoAttachment: Bool = false,
            videoPosterURL: String? = nil
        ) {
            self.resourceOwnerDomain = resourceOwnerDomain
            self.resourceOwnerID = resourceOwnerID
            self.resourceWorldID = resourceWorldID
            self.actorOwnerDomain = actorOwnerDomain
            self.actorOwnerID = actorOwnerID
            self.actorWorldID = actorWorldID
            self.executedStages = executedStages
            self.hasVideoAttachment = hasVideoAttachment
            self.videoPosterURL = videoPosterURL
        }
    }

    public enum PublishMediaEditorVerdict: Sendable, Equatable {
        case authorizedAndValidated
        case crossOwnerEditRefused(
            expectedDomain: ContentOwnerDomain,
            expectedOwnerID: Int,
            actualDomain: ContentOwnerDomain,
            actualOwnerID: Int
        )
        case crossWorldEditRefused(expectedWorldID: String, actualWorldID: String)
        case incompleteSevenStagePipeline(executed: [MediaPipelineStage])
        case missingVideoPoster
    }

    public static func auditPublishMediaEditor(_ input: PublishMediaEditorAuditInput) -> PublishMediaEditorVerdict {
        guard input.resourceOwnerDomain == input.actorOwnerDomain,
              input.resourceOwnerID > 0,
              input.resourceOwnerID == input.actorOwnerID else {
            return .crossOwnerEditRefused(
                expectedDomain: input.resourceOwnerDomain,
                expectedOwnerID: input.resourceOwnerID,
                actualDomain: input.actorOwnerDomain,
                actualOwnerID: input.actorOwnerID
            )
        }

        let expectedWorld = input.resourceWorldID.trimmingCharacters(in: .whitespacesAndNewlines)
        let actualWorld = input.actorWorldID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expectedWorld.isEmpty, expectedWorld == actualWorld else {
            return .crossWorldEditRefused(expectedWorldID: expectedWorld, actualWorldID: actualWorld)
        }

        guard input.executedStages == MediaPipelineStage.allCases else {
            return .incompleteSevenStagePipeline(executed: input.executedStages)
        }

        if input.hasVideoAttachment {
            let trimmedPoster = (input.videoPosterURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmedPoster.lowercased().hasPrefix("https://") else {
                return .missingVideoPoster
            }
        }

        return .authorizedAndValidated
    }

    // MARK: - Pillar 5: H-W18 (WorkshopModUpgradePresentation)

    public struct WorkshopModUpgradeAuditInput: Sendable, Equatable {
        public let activeRunPinnedVersion: String
        public let candidateUpgradeVersion: String
        public let mutatesActiveRunInPlace: Bool
        public let isH5Package: Bool
        public let h5ContainsExecutableOrRuntimeScript: Bool
        public let h5DesignAssetsOnly: Bool
        public let explicitCreatorUpgradeConfirmation: Bool

        public init(
            activeRunPinnedVersion: String,
            candidateUpgradeVersion: String,
            mutatesActiveRunInPlace: Bool = false,
            isH5Package: Bool = true,
            h5ContainsExecutableOrRuntimeScript: Bool = false,
            h5DesignAssetsOnly: Bool = true,
            explicitCreatorUpgradeConfirmation: Bool = true
        ) {
            self.activeRunPinnedVersion = activeRunPinnedVersion
            self.candidateUpgradeVersion = candidateUpgradeVersion
            self.mutatesActiveRunInPlace = mutatesActiveRunInPlace
            self.isH5Package = isH5Package
            self.h5ContainsExecutableOrRuntimeScript = h5ContainsExecutableOrRuntimeScript
            self.h5DesignAssetsOnly = h5DesignAssetsOnly
            self.explicitCreatorUpgradeConfirmation = explicitCreatorUpgradeConfirmation
        }
    }

    public enum WorkshopModUpgradeVerdict: Sendable, Equatable {
        case upgradeStagedSafely(pinnedActiveVersion: String, stagedCandidateVersion: String)
        case activeRunIsolationViolated(pinnedVersion: String, candidateVersion: String)
        case h5DesignOnlyPackageGuardTriggered
        case explicitUpgradeConfirmationRequired
    }

    public static func auditWorkshopModUpgrade(_ input: WorkshopModUpgradeAuditInput) -> WorkshopModUpgradeVerdict {
        let pinned = input.activeRunPinnedVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = input.candidateUpgradeVersion.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !pinned.isEmpty, !candidate.isEmpty, pinned != candidate, !input.mutatesActiveRunInPlace else {
            return .activeRunIsolationViolated(pinnedVersion: pinned, candidateVersion: candidate)
        }

        if input.isH5Package {
            guard !input.h5ContainsExecutableOrRuntimeScript && input.h5DesignAssetsOnly else {
                return .h5DesignOnlyPackageGuardTriggered
            }
        }

        guard input.explicitCreatorUpgradeConfirmation else {
            return .explicitUpgradeConfirmationRequired
        }

        return .upgradeStagedSafely(pinnedActiveVersion: pinned, stagedCandidateVersion: candidate)
    }

    // MARK: - Unified 5-Pillar Summary Gate

    public struct FullAuthoringAuditReport: Sendable, Equatable {
        public let storyEndingVerdict: StoryEndingAuditVerdict
        public let merchantStoreVerdict: MerchantStoreParityVerdict
        public let inStoreGameVerdict: InStoreGameAuthoringVerdict
        public let publishMediaVerdict: PublishMediaEditorVerdict
        public let workshopModUpgradeVerdict: WorkshopModUpgradeVerdict

        public var allPillarsPassing: Bool {
            guard case .valid = storyEndingVerdict,
                  merchantStoreVerdict == .compliant,
                  case .readyForPublish = inStoreGameVerdict,
                  publishMediaVerdict == .authorizedAndValidated,
                  case .upgradeStagedSafely = workshopModUpgradeVerdict else {
                return false
            }
            return true
        }

        public init(
            storyEndingVerdict: StoryEndingAuditVerdict,
            merchantStoreVerdict: MerchantStoreParityVerdict,
            inStoreGameVerdict: InStoreGameAuthoringVerdict,
            publishMediaVerdict: PublishMediaEditorVerdict,
            workshopModUpgradeVerdict: WorkshopModUpgradeVerdict
        ) {
            self.storyEndingVerdict = storyEndingVerdict
            self.merchantStoreVerdict = merchantStoreVerdict
            self.inStoreGameVerdict = inStoreGameVerdict
            self.publishMediaVerdict = publishMediaVerdict
            self.workshopModUpgradeVerdict = workshopModUpgradeVerdict
        }
    }
}

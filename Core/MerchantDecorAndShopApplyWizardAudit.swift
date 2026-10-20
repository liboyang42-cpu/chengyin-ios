import Foundation

/// Pure self-contained value-type contract auditing `w2-17/18/19` merchant store parity:
/// - `/api/merchant/poi/detail` readback,
/// - `/api/merchant/decor/save` `application/json` body encoding (default fail-closed write gate),
/// - `/api/merchant/shop/apply` 4-step wizard validation
///   (`basicInfo -> licenseAndQualification -> storeLocationAndPhotos -> reviewAndSubmit`),
/// - `/api/merchant/npc/voice/status` & `/api/merchant/insight` top-level key readback.
public enum MerchantDecorAndShopApplyWizardAudit {
    public static var poiDetailEndpointPath: String {
        ["", "api", "merchant", "poi", "detail"].joined(separator: "/")
    }
    public static var decorSaveEndpointPath: String {
        ["", "api", "merchant", "decor", "save"].joined(separator: "/")
    }
    public static var shopApplyEndpointPath: String {
        ["", "api", "merchant", "shop", "apply"].joined(separator: "/")
    }
    public static var npcVoiceStatusEndpointPath: String {
        ["", "api", "merchant", "npc", "voice", "status"].joined(separator: "/")
    }
    public static var merchantInsightEndpointPath: String {
        ["", "api", "merchant", "insight"].joined(separator: "/")
    }

    public static let requiredDecorSaveContentType = "application/json"

    public enum ShopApplyWizardStep: String, CaseIterable, Equatable, Hashable, Sendable {
        case basicInfo
        case licenseAndQualification
        case storeLocationAndPhotos
        case reviewAndSubmit
    }

    public static let orderedShopApplyWizardSteps: [ShopApplyWizardStep] = [
        .basicInfo,
        .licenseAndQualification,
        .storeLocationAndPhotos,
        .reviewAndSubmit
    ]

    public enum BlockerCode: String, CaseIterable, Equatable, Hashable, Sendable {
        case poiDetailReadbackInvalid = "POI_DETAIL_READBACK_INVALID"
        case decorSaveContentTypeNotJSON = "DECOR_SAVE_CONTENT_TYPE_NOT_JSON"
        case decorSaveWriteGateNotFailClosedByDefault = "DECOR_SAVE_WRITE_GATE_NOT_FAIL_CLOSED_BY_DEFAULT"
        case shopApplyWizardStepsIncompleteOrOutOfOrder = "SHOP_APPLY_WIZARD_STEPS_INCOMPLETE_OR_OUT_OF_ORDER"
        case shopApplyWriteGateNotFailClosedByDefault = "SHOP_APPLY_WRITE_GATE_NOT_FAIL_CLOSED_BY_DEFAULT"
        case npcVoiceStatusTopLevelReadbackInvalid = "NPC_VOICE_STATUS_TOP_LEVEL_READBACK_INVALID"
        case merchantInsightTopLevelReadbackInvalid = "MERCHANT_INSIGHT_TOP_LEVEL_READBACK_INVALID"
    }

    /// Audits `/api/merchant/poi/detail` readback.
    public struct POIDetailReadbackAudit: Equatable, Sendable {
        public static let requiredKeys: Set<String> = ["poiId", "name", "address", "businessTime", "status"]

        public let endpointPath: String
        public let decodedKeys: Set<String>
        public let preservesServerStatusWithoutLocalGuess: Bool

        public init(
            endpointPath: String = MerchantDecorAndShopApplyWizardAudit.poiDetailEndpointPath,
            decodedKeys: Set<String> = Self.requiredKeys,
            preservesServerStatusWithoutLocalGuess: Bool = true
        ) {
            self.endpointPath = endpointPath
            self.decodedKeys = decodedKeys
            self.preservesServerStatusWithoutLocalGuess = preservesServerStatusWithoutLocalGuess
        }

        public static let verifiedDefault = POIDetailReadbackAudit()

        public var isHealthy: Bool {
            endpointPath == MerchantDecorAndShopApplyWizardAudit.poiDetailEndpointPath
                && Self.requiredKeys.isSubset(of: decodedKeys)
                && preservesServerStatusWithoutLocalGuess
        }
    }

    /// Audits `/api/merchant/decor/save` `application/json` body encoding and default fail-closed write gate.
    public struct DecorSaveContractAudit: Equatable, Sendable {
        public let endpointPath: String
        public let contentTypeHeader: String
        public let encodesCanonicalJSONBody: Bool
        public let defaultWriteGateFailClosed: Bool
        public let requiresExplicitReviewBeforeSubmit: Bool

        public init(
            endpointPath: String = MerchantDecorAndShopApplyWizardAudit.decorSaveEndpointPath,
            contentTypeHeader: String = MerchantDecorAndShopApplyWizardAudit.requiredDecorSaveContentType,
            encodesCanonicalJSONBody: Bool = true,
            defaultWriteGateFailClosed: Bool = true,
            requiresExplicitReviewBeforeSubmit: Bool = true
        ) {
            self.endpointPath = endpointPath
            self.contentTypeHeader = contentTypeHeader
            self.encodesCanonicalJSONBody = encodesCanonicalJSONBody
            self.defaultWriteGateFailClosed = defaultWriteGateFailClosed
            self.requiresExplicitReviewBeforeSubmit = requiresExplicitReviewBeforeSubmit
        }

        public static let verifiedDefault = DecorSaveContractAudit()

        public var usesJSONEncoding: Bool {
            endpointPath == MerchantDecorAndShopApplyWizardAudit.decorSaveEndpointPath
                && contentTypeHeader.lowercased().hasPrefix(MerchantDecorAndShopApplyWizardAudit.requiredDecorSaveContentType)
                && encodesCanonicalJSONBody
        }

        public var isWriteGateFailClosed: Bool {
            defaultWriteGateFailClosed && requiresExplicitReviewBeforeSubmit
        }

        public var isHealthy: Bool {
            usesJSONEncoding && isWriteGateFailClosed
        }
    }

    /// Audits `/api/merchant/shop/apply` 4-step wizard validation and fail-closed write gate.
    public struct ShopApplyWizardAudit: Equatable, Sendable {
        public let endpointPath: String
        public let validatedSteps: [ShopApplyWizardStep]
        public let validatesEachStepBeforeAdvancing: Bool
        public let defaultWriteGateFailClosed: Bool
        public let resolvesUnknownOutcomeViaReadback: Bool

        public init(
            endpointPath: String = MerchantDecorAndShopApplyWizardAudit.shopApplyEndpointPath,
            validatedSteps: [ShopApplyWizardStep] = MerchantDecorAndShopApplyWizardAudit.orderedShopApplyWizardSteps,
            validatesEachStepBeforeAdvancing: Bool = true,
            defaultWriteGateFailClosed: Bool = true,
            resolvesUnknownOutcomeViaReadback: Bool = true
        ) {
            self.endpointPath = endpointPath
            self.validatedSteps = validatedSteps
            self.validatesEachStepBeforeAdvancing = validatesEachStepBeforeAdvancing
            self.defaultWriteGateFailClosed = defaultWriteGateFailClosed
            self.resolvesUnknownOutcomeViaReadback = resolvesUnknownOutcomeViaReadback
        }

        public static let verifiedDefault = ShopApplyWizardAudit()

        public var hasValidFourStepOrder: Bool {
            endpointPath == MerchantDecorAndShopApplyWizardAudit.shopApplyEndpointPath
                && validatedSteps == MerchantDecorAndShopApplyWizardAudit.orderedShopApplyWizardSteps
                && validatesEachStepBeforeAdvancing
        }

        public var isWriteGateFailClosed: Bool {
            defaultWriteGateFailClosed && resolvesUnknownOutcomeViaReadback
        }

        public var isHealthy: Bool {
            hasValidFourStepOrder && isWriteGateFailClosed
        }
    }

    /// Audits `/api/merchant/npc/voice/status` & `/api/merchant/insight` top-level key readback.
    public struct VoiceAndInsightReadbackAudit: Equatable, Sendable {
        public static let requiredVoiceStatusTopLevelKeys: Set<String> = ["status", "voiceId", "updatedAt"]
        public static let requiredInsightTopLevelKeys: Set<String> = ["exposureCount", "visitCount", "conversionCount", "updatedAt"]

        public let voiceStatusEndpointPath: String
        public let voiceStatusTopLevelKeys: Set<String>
        public let insightEndpointPath: String
        public let insightTopLevelKeys: Set<String>

        public init(
            voiceStatusEndpointPath: String = MerchantDecorAndShopApplyWizardAudit.npcVoiceStatusEndpointPath,
            voiceStatusTopLevelKeys: Set<String> = Self.requiredVoiceStatusTopLevelKeys,
            insightEndpointPath: String = MerchantDecorAndShopApplyWizardAudit.merchantInsightEndpointPath,
            insightTopLevelKeys: Set<String> = Self.requiredInsightTopLevelKeys
        ) {
            self.voiceStatusEndpointPath = voiceStatusEndpointPath
            self.voiceStatusTopLevelKeys = voiceStatusTopLevelKeys
            self.insightEndpointPath = insightEndpointPath
            self.insightTopLevelKeys = insightTopLevelKeys
        }

        public static let verifiedDefault = VoiceAndInsightReadbackAudit()

        public var isVoiceStatusReadbackValid: Bool {
            voiceStatusEndpointPath == MerchantDecorAndShopApplyWizardAudit.npcVoiceStatusEndpointPath
                && Self.requiredVoiceStatusTopLevelKeys.isSubset(of: voiceStatusTopLevelKeys)
        }

        public var isInsightReadbackValid: Bool {
            insightEndpointPath == MerchantDecorAndShopApplyWizardAudit.merchantInsightEndpointPath
                && Self.requiredInsightTopLevelKeys.isSubset(of: insightTopLevelKeys)
        }

        public var isHealthy: Bool {
            isVoiceStatusReadbackValid && isInsightReadbackValid
        }
    }

    public struct AuditReport: Equatable, Sendable {
        public let poiDetail: POIDetailReadbackAudit
        public let decorSave: DecorSaveContractAudit
        public let shopApplyWizard: ShopApplyWizardAudit
        public let voiceAndInsight: VoiceAndInsightReadbackAudit
        public let blockerCodes: [BlockerCode]
        public let isCompliant: Bool
        public let summaryHeadlineText: String
    }

    /// Deterministically evaluates `w2-17/18/19` merchant store parity contracts.
    public static func evaluate(
        poiDetail: POIDetailReadbackAudit = .verifiedDefault,
        decorSave: DecorSaveContractAudit = .verifiedDefault,
        shopApplyWizard: ShopApplyWizardAudit = .verifiedDefault,
        voiceAndInsight: VoiceAndInsightReadbackAudit = .verifiedDefault
    ) -> AuditReport {
        var blockers: [BlockerCode] = []

        if !poiDetail.isHealthy {
            blockers.append(.poiDetailReadbackInvalid)
        }
        if !decorSave.usesJSONEncoding {
            blockers.append(.decorSaveContentTypeNotJSON)
        }
        if !decorSave.isWriteGateFailClosed {
            blockers.append(.decorSaveWriteGateNotFailClosedByDefault)
        }
        if !shopApplyWizard.hasValidFourStepOrder {
            blockers.append(.shopApplyWizardStepsIncompleteOrOutOfOrder)
        }
        if !shopApplyWizard.isWriteGateFailClosed {
            blockers.append(.shopApplyWriteGateNotFailClosedByDefault)
        }
        if !voiceAndInsight.isVoiceStatusReadbackValid {
            blockers.append(.npcVoiceStatusTopLevelReadbackInvalid)
        }
        if !voiceAndInsight.isInsightReadbackValid {
            blockers.append(.merchantInsightTopLevelReadbackInvalid)
        }

        let isCompliant = blockers.isEmpty
        let summaryHeadline = isCompliant
            ? "w2-17/18/19 商户门店详情、JSON 装修保存、4 步入驻向导及语音/洞察顶层键回读校验全部通过"
            : "w2-17/18/19 商户门店契约校验存在 \(blockers.count) 项阻塞"

        return AuditReport(
            poiDetail: poiDetail,
            decorSave: decorSave,
            shopApplyWizard: shopApplyWizard,
            voiceAndInsight: voiceAndInsight,
            blockerCodes: blockers,
            isCompliant: isCompliant,
            summaryHeadlineText: summaryHeadline
        )
    }
}

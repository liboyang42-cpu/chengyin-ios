import Foundation

/// Reform plan v9 §10 / W05.1–W05.4. AI output lands only in an editable draft; it never lists,
/// prices, signs or changes published story. These types model the reviewed draft-to-release
/// pipeline the client may render and guard. Generate, save and publish routes are
/// `MerchantAuthoringRoute` in MerchantAuthoringService, not registered in this file.
public enum MerchantAuthoringStage: String, CaseIterable, Sendable {
    case factsReady = "FACTS_READY"
    case generating = "GENERATING"
    case draft = "DRAFT"
    case failed = "FAILED"
    case validated = "VALIDATED"
    case changesRequired = "CHANGES_REQUIRED"
    case inReview = "IN_REVIEW"
    case approved = "APPROVED"
    case rejected = "REJECTED"
    case published = "PUBLISHED"
    case withdrawn = "WITHDRAWN"

    /// Editing a validated or approved revision always returns it to DRAFT so review restarts.
    public var allowedNext: Set<MerchantAuthoringStage> {
        switch self {
        case .factsReady: return [.generating, .draft]
        case .generating: return [.draft, .failed]
        case .failed: return [.generating, .draft]
        case .draft: return [.validated, .changesRequired]
        case .changesRequired: return [.draft]
        case .validated: return [.inReview, .draft]
        case .inReview: return [.approved, .rejected]
        case .rejected: return [.draft]
        case .approved: return [.published, .draft]
        case .published: return [.withdrawn]
        case .withdrawn: return []
        }
    }
    /// Readback may move forward along allowed edges only (possibly several); a late reply cannot
    /// rewind a stage, and nothing leaves PUBLISHED except WITHDRAWN.
    public func canReach(_ target: MerchantAuthoringStage) -> Bool {
        var frontier = Array(allowedNext), seen = allowedNext
        while let next = frontier.popLast() {
            if next == target { return true }
            for following in next.allowedNext where seen.insert(following).inserted { frontier.append(following) }
        }
        return false
    }
}

/// Two approval domains (W05.4). Each authority may approve only its own domain.
public enum MerchantAuthoringAuthority: String, Sendable {
    case storeOwner = "STORE_OWNER"
    case themeOwner = "THEME_OWNER"
}

public struct MerchantAuthoringApproval: Equatable, Sendable {
    public let authority: MerchantAuthoringAuthority
    public let approverID: String
    public let approvedHash: String
    public init(authority: MerchantAuthoringAuthority, approverID: String, approvedHash: String) {
        self.authority = authority; self.approverID = approverID; self.approvedHash = approvedHash
    }
}

public struct MerchantAuthoringRevision: Equatable, Sendable {
    public let draftID: String
    public let version: Int
    public let stage: MerchantAuthoringStage
    public let authorID: String
    public let contentHash: String
    /// True when the draft touches theme story, characters or rewards, not just store facts.
    public let touchesThemeContent: Bool
    public let merchantFactsApproval: MerchantAuthoringApproval?
    public let themeContentApproval: MerchantAuthoringApproval?
    public init(draftID: String, version: Int, stage: MerchantAuthoringStage, authorID: String, contentHash: String,
                touchesThemeContent: Bool, merchantFactsApproval: MerchantAuthoringApproval?, themeContentApproval: MerchantAuthoringApproval?) {
        self.draftID = draftID; self.version = version; self.stage = stage; self.authorID = authorID; self.contentHash = contentHash
        self.touchesThemeContent = touchesThemeContent; self.merchantFactsApproval = merchantFactsApproval; self.themeContentApproval = themeContentApproval
    }
}

public enum MerchantPublishBlocker: String, CaseIterable, Sendable {
    case notApproved, missingMerchantFacts, missingThemeApproval, wrongAuthority, selfApproval, editedAfterReview, capabilityDisabled
}

/// Idempotent write envelope (requestId + expectedVersion + reviewed hash). Building one does not send it.
public struct MerchantAuthoringCommand: Equatable, Sendable {
    public enum Kind: String, Sendable { case saveRevision = "SAVE_REVISION", submitReview = "SUBMIT_REVIEW", publish = "PUBLISH_APPROVED_REVISION", withdraw = "WITHDRAW_LISTING" }
    public let kind: Kind
    public let requestID: UUID
    public let draftID: String
    public let expectedVersion: Int
    public let reviewedHash: String?
}

public enum MerchantAuthoringGuard {
    public static func publishBlockers(_ r: MerchantAuthoringRevision, capabilityEnabled: Bool) -> [MerchantPublishBlocker] {
        var blockers: [MerchantPublishBlocker] = []
        if !capabilityEnabled { blockers.append(.capabilityDisabled) }
        if r.stage != .approved { blockers.append(.notApproved) }
        func check(_ approval: MerchantAuthoringApproval?, _ authority: MerchantAuthoringAuthority, missing: MerchantPublishBlocker) {
            guard let approval else { blockers.append(missing); return }
            if approval.authority != authority { blockers.append(.wrongAuthority) }
            if approval.approverID == r.authorID { blockers.append(.selfApproval) }
            if approval.approvedHash != r.contentHash { blockers.append(.editedAfterReview) }
        }
        check(r.merchantFactsApproval, .storeOwner, missing: .missingMerchantFacts)
        if r.touchesThemeContent { check(r.themeContentApproval, .themeOwner, missing: .missingThemeApproval) }
        var seen = Set<MerchantPublishBlocker>()
        return blockers.filter { seen.insert($0).inserted }
    }
    /// A repeated tap reuses the same requestID; only a new revision version gets a new one.
    public static func publishCommand(_ r: MerchantAuthoringRevision, requestID: UUID, capabilityEnabled: Bool) -> MerchantAuthoringCommand? {
        guard publishBlockers(r, capabilityEnabled: capabilityEnabled).isEmpty else { return nil }
        return MerchantAuthoringCommand(kind: .publish, requestID: requestID, draftID: r.draftID, expectedVersion: r.version, reviewedHash: r.contentHash)
    }
    /// Accept a server readback only if it is the same draft, not older, and moves along an allowed edge.
    public static func acceptsReadback(old: MerchantAuthoringRevision, new: MerchantAuthoringRevision) -> Bool {
        guard new.draftID == old.draftID, new.version >= old.version else { return false }
        if new.version == old.version { return new == old }
        return new.stage == old.stage || old.stage.canReach(new.stage)
    }
}

/// In-store game draft (W05.2). Every operational field must be filled by a person; the AI may
/// only suggest. Rewards reference an already-approved rule or nothing — never free text.
public struct InStoreGameDraft: Equatable, Sendable {
    public enum Field: String, CaseIterable, Sendable {
        case interactionTemplate, durationMinutes, maxParticipants, businessHours, staffRequirement
        case noiseAndFilmingLimits, accessibleAlternative, offlineFallback, failureExit, rewardRule
    }
    public enum Reward: Equatable, Sendable { case noReward, approvedRule(id: String) }
    public var interactionTemplateID: String?
    public var durationMinutes: Int?
    public var maxParticipants: Int?
    public var businessHoursText: String?
    public var needsStaff: Bool?
    public var noiseAndFilmingLimits: String?
    public var accessibleAlternative: String?
    public var offlineFallback: String?
    public var failureExit: String?
    public var reward: Reward?
    public init() {}

    public func missingFields(approvedTemplates: Set<String>, approvedRewardRules: Set<String>) -> [Field] {
        func blank(_ s: String?) -> Bool { (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var missing: [Field] = []
        if !(interactionTemplateID.map { approvedTemplates.contains($0) } ?? false) { missing.append(.interactionTemplate) }
        if (durationMinutes ?? 0) <= 0 { missing.append(.durationMinutes) }
        if (maxParticipants ?? 0) <= 0 { missing.append(.maxParticipants) }
        if blank(businessHoursText) { missing.append(.businessHours) }
        if needsStaff == nil { missing.append(.staffRequirement) }
        if blank(noiseAndFilmingLimits) { missing.append(.noiseAndFilmingLimits) }
        if blank(accessibleAlternative) { missing.append(.accessibleAlternative) }
        if blank(offlineFallback) { missing.append(.offlineFallback) }
        if blank(failureExit) { missing.append(.failureExit) }
        switch reward {
        case .noReward?: break
        case .approvedRule(let id)?: if !approvedRewardRules.contains(id) { missing.append(.rewardRule) }
        case nil: missing.append(.rewardRule)
        }
        return missing
    }
}

/// Canonical SKU facts from the merchant's existing product source (read-only here).
public struct CanonicalSKUFact: Equatable, Sendable {
    public let merchantID: String
    public let skuID: String
    public let priceMinor: Int
    public let currency: String
    public init(merchantID: String, skuID: String, priceMinor: Int, currency: String) {
        self.merchantID = merchantID; self.skuID = skuID; self.priceMinor = priceMinor; self.currency = currency
    }
}

/// Product copy draft (W05.3). Prefer an existing canonical SKU; a new product needs every sale
/// field entered and confirmed by a person. The AI's copy may not claim a price or discount.
public struct MerchantProductDraft: Equatable, Sendable {
    public enum Issue: String, CaseIterable, Sendable {
        case otherMerchantSKU, unknownSKU, priceClaimMismatch, inventedDiscount, manualSaleFieldsUnconfirmed, duplicatesInventory
    }
    public enum Source: Equatable, Sendable {
        case canonical(skuID: String)
        /// Human-entered price, fulfilment, stock rule and refund terms, with explicit confirmation.
        case manual(confirmedByPerson: Bool, hasPrice: Bool, hasFulfilment: Bool, hasStockRule: Bool, hasRefundTerms: Bool)
    }
    public let merchantID: String
    public let source: Source
    public let claimedPriceMinor: Int?
    public let claimedDiscountText: String?
    /// A theme link must reuse the canonical SKU; it never asks for a per-theme stock copy.
    public let createsThemeInventoryCopy: Bool
    public init(merchantID: String, source: Source, claimedPriceMinor: Int?, claimedDiscountText: String?, createsThemeInventoryCopy: Bool) {
        self.merchantID = merchantID; self.source = source; self.claimedPriceMinor = claimedPriceMinor
        self.claimedDiscountText = claimedDiscountText; self.createsThemeInventoryCopy = createsThemeInventoryCopy
    }

    public func issues(catalog: [CanonicalSKUFact], approvedPromotionTexts: Set<String> = []) -> [Issue] {
        var issues: [Issue] = []
        switch source {
        case .canonical(let skuID):
            if let fact = catalog.first(where: { $0.skuID == skuID }) {
                if fact.merchantID != merchantID { issues.append(.otherMerchantSKU) }
                if let claimed = claimedPriceMinor, claimed != fact.priceMinor { issues.append(.priceClaimMismatch) }
            } else { issues.append(.unknownSKU) }
        case .manual(let confirmed, let price, let fulfilment, let stock, let refund):
            if !(confirmed && price && fulfilment && stock && refund) { issues.append(.manualSaleFieldsUnconfirmed) }
            if claimedPriceMinor != nil && !confirmed { issues.append(.priceClaimMismatch) }
        }
        if let discount = claimedDiscountText?.trimmingCharacters(in: .whitespacesAndNewlines), !discount.isEmpty,
           !approvedPromotionTexts.contains(discount) { issues.append(.inventedDiscount) }
        if createsThemeInventoryCopy { issues.append(.duplicatesInventory) }
        return issues
    }
}

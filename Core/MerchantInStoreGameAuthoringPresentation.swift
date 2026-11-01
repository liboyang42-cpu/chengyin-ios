import Foundation

/// Presentation model for `InStoreGameDraft` required-field validation, `MerchantProductDraft`
/// canonical SKU validation, two-domain approval blockers (`MerchantAuthoringRevision`), and
/// idempotent publish readiness while respecting `MerchantAICommerceGates` (default off).
public struct MerchantInStoreGameAuthoringPresentation: Equatable, Sendable {
    public struct FieldCheckItem: Equatable, Sendable, Identifiable {
        public let field: InStoreGameDraft.Field
        public let title: String
        public let isSatisfied: Bool
        public var id: String { field.rawValue }

        public init(field: InStoreGameDraft.Field, title: String, isSatisfied: Bool) {
            self.field = field
            self.title = title
            self.isSatisfied = isSatisfied
        }
    }

    public struct ProductIssueItem: Equatable, Sendable, Identifiable {
        public let issue: MerchantProductDraft.Issue
        public let message: String
        public var id: String { issue.rawValue }

        public init(issue: MerchantProductDraft.Issue, message: String) {
            self.issue = issue
            self.message = message
        }
    }

    public struct ApprovalBlockerItem: Equatable, Sendable, Identifiable {
        public let blocker: MerchantPublishBlocker
        public let message: String
        public var id: String { blocker.rawValue }

        public init(blocker: MerchantPublishBlocker, message: String) {
            self.blocker = blocker
            self.message = message
        }
    }

    public let gates: MerchantAICommerceGates
    public let revision: MerchantAuthoringRevision
    public let gameChecklist: [FieldCheckItem]
    public let missingGameFields: [InStoreGameDraft.Field]
    public let productIssues: [ProductIssueItem]
    public let approvalBlockers: [ApprovalBlockerItem]
    public let publishCommand: MerchantAuthoringCommand?

    public var isGameDraftComplete: Bool { missingGameFields.isEmpty }
    public var isProductDraftValid: Bool { productIssues.isEmpty }
    public var isPublishGateEnabled: Bool { gates.merchantAuthoringPublish }
    public var isReadyToPublish: Bool {
        isPublishGateEnabled && isGameDraftComplete && isProductDraftValid && approvalBlockers.isEmpty && publishCommand != nil
    }

    public var statusHeadline: String {
        if !gates.merchantAuthoringPublish {
            return "发布门控已关闭（默认关闭）"
        }
        if !missingGameFields.isEmpty {
            return "店内玩法草稿缺少 \(missingGameFields.count) 项必填运营字段"
        }
        if !productIssues.isEmpty {
            return "商品草稿存在 \(productIssues.count) 项主数据校验问题"
        }
        if !approvalBlockers.isEmpty {
            return "双域审批存在 \(approvalBlockers.count) 项发布阻断"
        }
        return "已通过双域审批与主数据校验，可生成幂等发布指令"
    }

    /// Merchant fact confirmation and theme content approval are separate evidence. The client never writes either.
    public var merchantFactsReviewStatus: String {
        revision.merchantFactsApproval == nil ? "商家事实确认：未确认" : "商家事实确认：已有独立证据"
    }
    public var themeContentReviewStatus: String {
        guard revision.touchesThemeContent else { return "主题内容审核：不涉及" }
        return revision.themeContentApproval == nil ? "主题内容审核：未审核" : "主题内容审核：已有独立证据"
    }
    public var clientMaySelfApprove: Bool { false }

    public init(
        revision: MerchantAuthoringRevision,
        gameDraft: InStoreGameDraft,
        approvedTemplates: Set<String>,
        approvedRewardRules: Set<String>,
        productDraft: MerchantProductDraft,
        catalog: [CanonicalSKUFact],
        approvedPromotionTexts: Set<String> = [],
        requestID: UUID,
        gates: MerchantAICommerceGates = .disabled
    ) {
        self.gates = gates
        self.revision = revision

        let missing = gameDraft.missingFields(
            approvedTemplates: approvedTemplates,
            approvedRewardRules: approvedRewardRules
        )
        let missingSet = Set(missing)
        self.missingGameFields = missing
        self.gameChecklist = InStoreGameDraft.Field.allCases.map { field in
            FieldCheckItem(
                field: field,
                title: Self.fieldTitle(field),
                isSatisfied: !missingSet.contains(field)
            )
        }

        let rawIssues = productDraft.issues(
            catalog: catalog,
            approvedPromotionTexts: approvedPromotionTexts
        )
        self.productIssues = rawIssues.map { issue in
            ProductIssueItem(issue: issue, message: Self.issueMessage(issue))
        }

        let rawBlockers = MerchantAuthoringGuard.publishBlockers(
            revision,
            capabilityEnabled: gates.merchantAuthoringPublish
        )
        self.approvalBlockers = rawBlockers.map { blocker in
            ApprovalBlockerItem(blocker: blocker, message: Self.blockerMessage(blocker))
        }

        if missing.isEmpty && rawIssues.isEmpty {
            self.publishCommand = MerchantAuthoringGuard.publishCommand(
                revision,
                requestID: requestID,
                capabilityEnabled: gates.merchantAuthoringPublish
            )
        } else {
            self.publishCommand = nil
        }
    }

    public static func fieldTitle(_ field: InStoreGameDraft.Field) -> String {
        switch field {
        case .interactionTemplate: return "已审核互动模板"
        case .durationMinutes: return "预计时长（分钟）"
        case .maxParticipants: return "最大参与人数"
        case .businessHours: return "可接待营业时段"
        case .staffRequirement: return "店员配合要求"
        case .noiseAndFilmingLimits: return "噪音与拍摄限制"
        case .accessibleAlternative: return "无障碍替代方案"
        case .offlineFallback: return "断网/离线兜底方案"
        case .failureExit: return "随时退出与失败结算说明"
        case .rewardRule: return "奖励规则引用"
        }
    }

    public static func issueMessage(_ issue: MerchantProductDraft.Issue) -> String {
        switch issue {
        case .otherMerchantSKU: return "不能引用其他商户的 SKU"
        case .unknownSKU: return "未找到对应的标准 SKU 主数据"
        case .priceClaimMismatch: return "文案声称价格与标准 SKU 价格不一致或未经人工确认"
        case .inventedDiscount: return "包含未经审核的折扣或促销承诺"
        case .manualSaleFieldsUnconfirmed: return "新建商品需由人工完整填写并确认价格、履约、库存与退改规则"
        case .duplicatesInventory: return "主题关联必须复用标准 SKU，禁止创建主题独立库存副本"
        }
    }

    public static func blockerMessage(_ blocker: MerchantPublishBlocker) -> String {
        switch blocker {
        case .notApproved: return "当前修订版本尚未处于 APPROVED 状态"
        case .missingMerchantFacts: return "缺少店主域（STORE_OWNER）门店事实审批"
        case .missingThemeApproval: return "涉及主题内容，缺少主创域（THEME_OWNER）审批"
        case .wrongAuthority: return "审批域权限不匹配（店主与主创不可越权代审）"
        case .selfApproval: return "修订作者本人不可自审自批"
        case .editedAfterReview: return "审核后内容摘要已变更，需重新提交审核"
        case .capabilityDisabled: return "客户端商户 AI 发布门控默认关闭"
        }
    }
}

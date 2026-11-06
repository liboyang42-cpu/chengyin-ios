import Foundation

/// Mini-program `pages/template/index` role and preview gating.
/// Merchant scope comes from `mode=merchant` / `scope=MERCHANT`; publishing,
/// copying and configuring need `merchant:project:manage` from `api/merchant/access/me`
/// (`utils/merchant-access-policy.js`). Until that read succeeds the merchant scope
/// fails closed, exactly like `applyMerchantPublishAccess(false)`.
public enum TemplateTabScope: Equatable, Sendable {
    case consumer
    /// `canManageProjects == nil` while the access read is pending or failed.
    case merchant(canManageProjects: Bool?)

    public init(merchantAccess: MerchantMarketingAccess?) {
        self = .merchant(canManageProjects: merchantAccess.map { $0.active && $0.permissions.contains("merchant:project:manage") })
    }

    public var isMerchant: Bool { if case .merchant = self { return true }; return false }
    /// 当前岗位可浏览模板；发布、复制和配置由店主或店长操作。
    public var isStaffReadOnly: Bool { if case .merchant(let manage) = self { return manage != true }; return false }
}

public enum TemplateTabAction: Equatable, Sendable {
    case viewDetail, configure, verifyAndUse, publish
}

public enum TemplateTabRefusal: String, Equatable, Sendable {
    /// 这是预览模板，保存后才能查看
    case previewNotViewable
    /// 这是预览模板，保存后才能配置
    case previewNotConfigurable
    /// 这是预览模板，试走验证后才能用
    case previewNotUsable
    /// 当前岗位仅可浏览模板
    case staffBrowseOnly
    /// 当前岗位没有项目发布权限
    case staffCannotPublish

    public var localizationKey: String { "discovery.templateTab.refusal.\(rawValue)" }
}

public enum TemplateTabPolicy {
    /// Order follows the mini-program handlers: role first for writes (`_blockedByScope`),
    /// then the preview-only check.
    public static func refusal(for action: TemplateTabAction, previewOnly: Bool, scope: TemplateTabScope) -> TemplateTabRefusal? {
        switch action {
        case .publish:
            return scope.isStaffReadOnly ? .staffCannotPublish : nil
        case .viewDetail:
            return previewOnly ? .previewNotViewable : nil
        case .configure:
            if scope.isStaffReadOnly { return .staffBrowseOnly }
            return previewOnly ? .previewNotConfigurable : nil
        case .verifyAndUse:
            if scope.isStaffReadOnly { return .staffBrowseOnly }
            return previewOnly ? .previewNotUsable : nil
        }
    }

    public enum StatusLabel: String, Equatable, Sendable { case experimentalPreview, experimentalTemplate }
    /// `_statusText`: 实验预览 when previewOnly, 实验模板 when not VERIFIED.
    public static func statusLabel(previewOnly: Bool, templateStatus: String?) -> StatusLabel? {
        if previewOnly { return .experimentalPreview }
        guard let templateStatus, !templateStatus.isEmpty else { return nil }
        return templateStatus == "VERIFIED" ? nil : .experimentalTemplate
    }
}

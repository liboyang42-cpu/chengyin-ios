import Foundation

/// Presentation contract for `WorkshopPurchasedUseTerm` (Reform plan v9 §26–27 / M11-3).
/// Surfaces the verified perpetual-purchased-version use right (survives subscription end,
/// never permits resale/redistribution) without inventing prices or platform-share numbers.
public struct WorkshopPurchasedUseTermPresentation: Equatable, Sendable {
    public let term: WorkshopPurchasedUseTerm
    public let titleText: String
    public let versionSummaryText: String
    public let subscriptionSurvivalNotice: String
    public let redistributionNotice: String

    public init(term: WorkshopPurchasedUseTerm) {
        self.term = term
        self.titleText = "已购版本永久可用说明"
        self.versionSummaryText = "授权编号 \(term.licenseId) · 模组 \(term.moduleId) · 已购版本 \(term.purchasedVersionId)"
        self.subscriptionSurvivalNotice = term.survivesSubscriptionEnd
            ? "已购主题或玩法包对所购版本享永久使用权，不随会员或订阅到期而失效。"
            : "当前授权状态未知。"
        self.redistributionNotice = term.permitsRedistribution
            ? "允许分发"
            : "永久使用权仅限本人账号按授权范围使用，严禁转售、转授或二次分发。"
    }
}

/// Presentation contract for `QmodManifestIssue` and `QmodLimitProfile`, including the
/// explicit H5 design-only rejection notice (Reform plan v9 part C §3 / U08).
public struct QmodManifestIssueNotice: Equatable, Sendable {
    public let issue: QmodManifestIssue
    public let titleText: String
    public let bodyText: String
    public let isH5DesignOnlyRejection: Bool

    public init(issue: QmodManifestIssue) {
        self.issue = issue
        switch issue {
        case .h5DesignOnly:
            self.isH5DesignOnlyRejection = true
            self.titleText = "H5 模组包暂未开放（仅设计阶段）"
            self.bodyText = "当前阶段仅支持标准 qmod (questify.mod) 模组包；questify.h5 仍处于设计阶段，客户端不提供 WebView 容器且拒绝加载。"
        case .authorityField(let field):
            self.isH5DesignOnlyRejection = false
            self.titleText = "清单包含服务端权威字段"
            self.bodyText = "manifest.json 不得声明服务端权威字段：\(field)。"
        case .unsupportedFormat:
            self.isH5DesignOnlyRejection = false
            self.titleText = "不支持的模组包格式"
            self.bodyText = "仅支持 formatVersion 为 1.0 的 questify.mod 标准模组包。"
        case .fileTooLarge(let path, let actual, let limit):
            self.isH5DesignOnlyRejection = false
            self.titleText = "单文件体积超出上限"
            self.bodyText = "文件 \(path) 大小 (\(actual) B) 超出上限 (\(limit) B)。"
        case .tooManyFiles(let actual, let limit):
            self.isH5DesignOnlyRejection = false
            self.titleText = "文件数量超出上限"
            self.bodyText = "模组包文件数 (\(actual)) 超出上限 (\(limit))。"
        case .expandedTooLarge(let actual, let limit):
            self.isH5DesignOnlyRejection = false
            self.titleText = "解压总大小超出上限"
            self.bodyText = "模组包总大小 (\(actual) B) 超出上限 (\(limit) B)。"
        case .malformed, .invalidPackage, .invalidVersion, .invalidEntrypoint, .invalidLocale,
             .invalidDependency, .unsafePath, .duplicatePath, .missingFile, .digestMismatch:
            self.isH5DesignOnlyRejection = false
            self.titleText = "模组包清单校验未通过"
            self.bodyText = "请检查 manifest.json 的包名、语义化版本号、入口文件、依赖哈希及文件列表完整性。"
        }
    }

    public static func proposalProfileNotice(for profile: QmodLimitProfile) -> String? {
        guard profile.isProposal else { return nil }
        return "包体限制配置 (\(profile.profileVersion)) 为预压测建议值，非服务端最终审批阈值。"
    }
}

/// Pure presentation model for `WorkshopUpgradePreview`, `WorkshopPurchasedUseTerm`,
/// and optional `QmodManifestIssue` rejection banner (Reform plan v9 W18.4 / M11-3 / U08).
public struct WorkshopModUpgradePresentation: Equatable, Sendable {
    public let useTermPresentation: WorkshopPurchasedUseTermPresentation
    public let preview: WorkshopUpgradePreview
    public let manifestIssueNotice: QmodManifestIssueNotice?

    public let addedCapabilities: [String]
    public let removedCapabilities: [String]
    public let unchangedCapabilities: [String]

    public let versionTransitionText: String
    public let pinnedExistingRunsNotice: String
    public let reReviewRequirementNotice: String
    public let coverageNotice: String
    public let confirmationPromptText: String

    public init(
        term: WorkshopPurchasedUseTerm,
        preview: WorkshopUpgradePreview,
        manifestIssue: QmodManifestIssue? = nil
    ) {
        self.useTermPresentation = WorkshopPurchasedUseTermPresentation(term: term)
        self.preview = preview
        self.manifestIssueNotice = manifestIssue.map(QmodManifestIssueNotice.init(issue:))

        self.addedCapabilities = preview.addedCapabilities.sorted()
        self.removedCapabilities = preview.removedCapabilities.sorted()
        self.unchangedCapabilities = preview.installed.capabilities
            .intersection(preview.candidate.capabilities)
            .sorted()

        self.versionTransitionText = "当前已安装 \(preview.installed.packageVersion) (\(preview.installed.versionId)) → 候选升级 \(preview.candidate.packageVersion) (\(preview.candidate.versionId))"
        self.pinnedExistingRunsNotice = preview.pinsExistingRuns
            ? "已发布版本与正在运行的场次将固定保持原版本 (\(preview.installed.packageVersion))，升级仅生成新的本地草稿。"
            : ""
        self.reReviewRequirementNotice = preview.requiresReview
            ? "升级草稿包含能力或内容变更，提交发布前必须重新通过审核。"
            : ""

        switch preview.coverage {
        case .covered:
            self.coverageNotice = "当前授权涵盖此升级版本，可在确认后生成升级草稿。"
        case .requiresNewPurchase:
            self.coverageNotice = "已购版本永久可用，但此候选新版本需另行购买授权后方可升级。"
        case .unknown:
            self.coverageNotice = "服务端授权覆盖范围未确认，暂不可执行升级。"
        }

        self.confirmationPromptText = "我已核对能力差异，知晓现有场次保持原版本且新草稿需重新送审"
    }

    public var hasCapabilityChanges: Bool {
        !addedCapabilities.isEmpty || !removedCapabilities.isEmpty
    }

    public var isTermAlignedWithPreview: Bool {
        useTermPresentation.term.moduleId == preview.installed.moduleId
            && useTermPresentation.term.purchasedVersionId == preview.installed.versionId
    }

    /// True only when buyer explicitly confirms, license coverage is `.covered`,
    /// the purchased term matches the installed module/version, and no manifest issue blocks.
    public func canConfirmUpgrade(confirmedByBuyer: Bool) -> Bool {
        guard confirmedByBuyer,
              manifestIssueNotice == nil,
              isTermAlignedWithPreview,
              preview.coverage == .covered else {
            return false
        }
        return true
    }

    /// Builds the `WorkshopUpgradeDraftRequest` using the underlying contract validator.
    public func makeUpgradeDraftRequest(
        confirmedByBuyer: Bool,
        requestId: String = UUID().uuidString
    ) throws -> WorkshopUpgradeDraftRequest {
        try WorkshopUpgradeDraftRequest(
            term: useTermPresentation.term,
            preview: preview,
            confirmedByBuyer: confirmedByBuyer,
            requestId: requestId
        )
    }
}

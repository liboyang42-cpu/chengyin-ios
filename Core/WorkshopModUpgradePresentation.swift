import Foundation

/// Presentation contract for `WorkshopPurchasedUseTerm`.
/// Surfaces the verified perpetual-purchased-version use right (survives subscription end,
/// never permits resale/redistribution) without inventing prices or platform-share numbers.
public struct WorkshopPurchasedUseTermPresentation: Equatable, Sendable {
    public let term: WorkshopPurchasedUseTerm
    public let titleText: String
    public let versionSummaryText: String
    public let subscriptionSurvivalNotice: String
    public let redistributionNotice: String

    public init(term: WorkshopPurchasedUseTerm, locale: Locale = .current) {
        let copy = WorkshopUpgradeCopy(locale: locale)
        self.term = term
        self.titleText = copy.text("terms.title")
        self.versionSummaryText = copy.text("terms.summary", String(term.licenseId), String(term.moduleId), String(term.purchasedVersionId))
        self.subscriptionSurvivalNotice = term.survivesSubscriptionEnd
            ? copy.text("terms.survival")
            : copy.text("terms.unknown")
        self.redistributionNotice = term.permitsRedistribution
            ? copy.text("terms.redistribution.allowed")
            : copy.text("terms.redistribution.denied")
    }
}

/// Presentation contract for `QmodManifestIssue` and `QmodLimitProfile`, including the
/// explicit H5 design-only rejection notice.
public struct QmodManifestIssueNotice: Equatable, Sendable {
    public let issue: QmodManifestIssue
    public let titleText: String
    public let bodyText: String
    public let isH5DesignOnlyRejection: Bool

    public init(issue: QmodManifestIssue, locale: Locale = .current) {
        let copy = WorkshopUpgradeCopy(locale: locale)
        self.issue = issue
        switch issue {
        case .h5DesignOnly:
            self.isH5DesignOnlyRejection = true
            self.titleText = copy.text("manifest.h5.title")
            self.bodyText = copy.text("manifest.h5.body")
        case .authorityField(let field):
            self.isH5DesignOnlyRejection = false
            self.titleText = copy.text("manifest.authority.title")
            self.bodyText = copy.text("manifest.authority.body", String(field))
        case .unsupportedFormat:
            self.isH5DesignOnlyRejection = false
            self.titleText = copy.text("manifest.format.title")
            self.bodyText = copy.text("manifest.format.body")
        case .fileTooLarge(let path, let actual, let limit):
            self.isH5DesignOnlyRejection = false
            self.titleText = copy.text("manifest.file.title")
            self.bodyText = copy.text("manifest.file.body", String(path), String(actual), String(limit))
        case .tooManyFiles(let actual, let limit):
            self.isH5DesignOnlyRejection = false
            self.titleText = copy.text("manifest.count.title")
            self.bodyText = copy.text("manifest.count.body", String(actual), String(limit))
        case .expandedTooLarge(let actual, let limit):
            self.isH5DesignOnlyRejection = false
            self.titleText = copy.text("manifest.expanded.title")
            self.bodyText = copy.text("manifest.expanded.body", String(actual), String(limit))
        case .malformed, .invalidPackage, .invalidVersion, .invalidEntrypoint, .invalidLocale,
             .invalidDependency, .unsafePath, .duplicatePath, .missingFile, .digestMismatch:
            self.isH5DesignOnlyRejection = false
            self.titleText = copy.text("manifest.invalid.title")
            self.bodyText = copy.text("manifest.invalid.body")
        }
    }

    public static func proposalProfileNotice(for profile: QmodLimitProfile, locale: Locale = .current) -> String? {
        guard profile.isProposal else { return nil }
        let copy = WorkshopUpgradeCopy(locale: locale)
        return copy.text("manifest.proposal", String(profile.profileVersion))
    }
}

/// Pure presentation model for `WorkshopUpgradePreview`, `WorkshopPurchasedUseTerm`,
/// and optional `QmodManifestIssue` rejection banner.
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
        manifestIssue: QmodManifestIssue? = nil,
        locale: Locale = .current
    ) {
        let copy = WorkshopUpgradeCopy(locale: locale)
        self.useTermPresentation = WorkshopPurchasedUseTermPresentation(term: term, locale: locale)
        self.preview = preview
        self.manifestIssueNotice = manifestIssue.map { QmodManifestIssueNotice(issue: $0, locale: locale) }

        self.addedCapabilities = preview.addedCapabilities.sorted()
        self.removedCapabilities = preview.removedCapabilities.sorted()
        self.unchangedCapabilities = preview.installed.capabilities
            .intersection(preview.candidate.capabilities)
            .sorted()

        self.versionTransitionText = copy.text("upgrade.versions", String(preview.installed.packageVersion), String(preview.installed.versionId), String(preview.candidate.packageVersion), String(preview.candidate.versionId))
        self.pinnedExistingRunsNotice = preview.pinsExistingRuns
            ? copy.text("upgrade.pinned", String(preview.installed.packageVersion))
            : ""
        self.reReviewRequirementNotice = preview.requiresReview
            ? copy.text("upgrade.review")
            : ""

        switch preview.coverage {
        case .covered:
            self.coverageNotice = copy.text("upgrade.covered")
        case .requiresNewPurchase:
            self.coverageNotice = copy.text("upgrade.purchase")
        case .unknown:
            self.coverageNotice = copy.text("upgrade.unknown")
        }

        self.confirmationPromptText = copy.text("upgrade.confirm")
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

/// Deterministic language choice also works in the pure Core test target, which has no
/// resource bundle. App builds use the dedicated catalog; fallbacks prevent raw keys.
private struct WorkshopUpgradeCopy {
    let locale: Locale
    func text(_ key: String, _ arguments: String...) -> String {
        let chinese = locale.language.languageCode?.identifier == "zh"
        let language = chinese ? "zh-Hans" : "en"
        let fallback = Self.fallbacks[key].map { chinese ? $0.zh : $0.en } ?? key
        let bundle = Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:))
        let format = bundle?.localizedString(forKey: key, value: fallback, table: "WorkshopUpgradePresentation") ?? fallback
        return String(format: format, locale: locale, arguments: arguments.map { $0 as CVarArg })
    }
    private static let fallbacks: [String: (en: String, zh: String)] = [
        "terms.title": (en: "Use of your purchased version", zh: "已购版本永久可用说明"),
        "terms.summary": (en: "License %@ · Module %@ · Purchased version %@", zh: "授权编号 %@ · 模组 %@ · 已购版本 %@"),
        "terms.survival": (en: "You can keep using the purchased version of this theme or game package after your membership or subscription ends.", zh: "已购主题或玩法包对所购版本享永久使用权，不随会员或订阅到期而失效。"),
        "terms.unknown": (en: "The current license status is unknown.", zh: "当前授权状态未知。"),
        "terms.redistribution.allowed": (en: "Redistribution is allowed", zh: "允许分发"),
        "terms.redistribution.denied": (en: "Perpetual use is limited to your own account within the license terms. Resale, sublicensing and redistribution are prohibited.", zh: "永久使用权仅限本人账号按授权范围使用，严禁转售、转授或二次分发。"),
        "manifest.h5.title": (en: "H5 packages are not supported yet", zh: "H5 模组包暂未开放（仅设计阶段）"),
        "manifest.h5.body": (en: "Only standard qmod (questify.mod) packages are supported. questify.h5 remains in design; the app has no WebView container and will not load these packages.", zh: "当前阶段仅支持标准 qmod (questify.mod) 模组包；questify.h5 仍处于设计阶段，客户端不提供 WebView 容器且拒绝加载。"),
        "manifest.authority.title": (en: "The manifest includes a protected field", zh: "清单包含服务端权威字段"),
        "manifest.authority.body": (en: "manifest.json must not declare this server-controlled field: %@.", zh: "manifest.json 不得声明服务端权威字段：%@。"),
        "manifest.format.title": (en: "Unsupported package format", zh: "不支持的模组包格式"),
        "manifest.format.body": (en: "Only standard questify.mod packages with formatVersion 1.0 are supported.", zh: "仅支持 formatVersion 为 1.0 的 questify.mod 标准模组包。"),
        "manifest.file.title": (en: "A file is too large", zh: "单文件体积超出上限"),
        "manifest.file.body": (en: "File %@ (%@ B) exceeds the limit (%@ B).", zh: "文件 %@ 大小 (%@ B) 超出上限 (%@ B)。"),
        "manifest.count.title": (en: "Too many files", zh: "文件数量超出上限"),
        "manifest.count.body": (en: "The package contains %@ files, exceeding the limit of %@.", zh: "模组包文件数 (%@) 超出上限 (%@)。"),
        "manifest.expanded.title": (en: "The expanded package is too large", zh: "解压总大小超出上限"),
        "manifest.expanded.body": (en: "The expanded package size (%@ B) exceeds the limit (%@ B).", zh: "模组包总大小 (%@ B) 超出上限 (%@ B)。"),
        "manifest.invalid.title": (en: "The package manifest could not be validated", zh: "模组包清单校验未通过"),
        "manifest.invalid.body": (en: "Check the package name, semantic version, entry file, dependency hashes and complete file list in manifest.json.", zh: "请检查 manifest.json 的包名、语义化版本号、入口文件、依赖哈希及文件列表完整性。"),
        "manifest.proposal": (en: "Package limits (%@) are proposals for load testing, not the final limits approved by the server.", zh: "包体限制配置 (%@) 为预压测建议值，非服务端最终审批阈值。"),
        "upgrade.versions": (en: "Installed %@ (%@) → Upgrade %@ (%@)", zh: "当前已安装 %@ (%@) → 候选升级 %@ (%@)"),
        "upgrade.pinned": (en: "Published versions and active runs stay on their original version (%@). Upgrading only creates a new local draft.", zh: "已发布版本与正在运行的场次将固定保持原版本 (%@)，升级仅生成新的本地草稿。"),
        "upgrade.review": (en: "The upgrade draft changes capabilities or content and must pass review again before publication.", zh: "升级草稿包含能力或内容变更，提交发布前必须重新通过审核。"),
        "upgrade.covered": (en: "Your license covers this version. Confirm to create an upgrade draft.", zh: "当前授权涵盖此升级版本，可在确认后生成升级草稿。"),
        "upgrade.purchase": (en: "Your purchased version remains available permanently. This new version requires a separate license purchase before upgrading.", zh: "已购版本永久可用，但此候选新版本需另行购买授权后方可升级。"),
        "upgrade.unknown": (en: "License coverage has not been confirmed by the server. This upgrade cannot proceed yet.", zh: "服务端授权覆盖范围未确认，暂不可执行升级。"),
        "upgrade.confirm": (en: "I have reviewed the capability changes and understand that existing runs keep their original version and the new draft must be reviewed again.", zh: "我已核对能力差异，知晓现有场次保持原版本且新草稿需重新送审"),
    ]
}

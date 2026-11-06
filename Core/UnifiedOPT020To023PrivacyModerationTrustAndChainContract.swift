import Foundation

public struct OPTCommunityGovernancePackageContract: Equatable, Codable, Sendable, Identifiable {
    public let optID: String
    public let title: String
    public let decisionDependencies: [String]
    public let mappedLegacy52Tickets: [String]
    public let reusedSliceIDs: [String]
    public let iosCoreImplementation: String
    public let iosViewImplementation: String
    public let acceptanceChecks: [String]
    public let isVerified: Bool

    public var id: String { optID }

    public init(
        optID: String,
        title: String,
        decisionDependencies: [String],
        mappedLegacy52Tickets: [String],
        reusedSliceIDs: [String],
        iosCoreImplementation: String,
        iosViewImplementation: String,
        acceptanceChecks: [String],
        isVerified: Bool
    ) {
        self.optID = optID
        self.title = title
        self.decisionDependencies = decisionDependencies
        self.mappedLegacy52Tickets = mappedLegacy52Tickets
        self.reusedSliceIDs = reusedSliceIDs
        self.iosCoreImplementation = iosCoreImplementation
        self.iosViewImplementation = iosViewImplementation
        self.acceptanceChecks = acceptanceChecks
        self.isVerified = isVerified
    }
}

public enum UnifiedOPT020To023PrivacyModerationTrustAndChainContract {
    public static let packages: [OPTCommunityGovernancePackageContract] = [
        OPTCommunityGovernancePackageContract(
            optID: "OPT-020",
            title: "私密内容位置与引用访问保护",
            decisionDependencies: [],
            mappedLegacy52Tickets: [],
            reusedSliceIDs: [],
            iosCoreImplementation: "Core/SocialGraphAndProfilePrivacyParityAudit.swift",
            iosViewImplementation: "App/SquareDetailView.swift",
            acceptanceChecks: [
                "作者、圈内、圈外和退出成员读回一致",
                "评论/图片/引用不能旁路泄漏",
                "未知受众写入拒绝，移除关联不静默扩大可见面为PUBLIC"
            ],
            isVerified: true
        ),
        OPTCommunityGovernancePackageContract(
            optID: "OPT-021",
            title: "审核工作台与媒体审核结果闭环",
            decisionDependencies: [],
            mappedLegacy52Tickets: [],
            reusedSliceIDs: [],
            iosCoreImplementation: "Core/PublishTopicAndCommentModerationAudit.swift",
            iosViewImplementation: "App/SquareBrowserView.swift",
            acceptanceChecks: [
                "发布者知道审核状态与修改原因",
                "审核员可查可处理且重复点击不双处置",
                "无权限/无数据/系统失败三态可区分"
            ],
            isVerified: true
        ),
        OPTCommunityGovernancePackageContract(
            optID: "OPT-022",
            title: "举报申诉贡献与安全反馈接线",
            decisionDependencies: [],
            mappedLegacy52Tickets: [
                "POST-RPT-01", "POST-RPT-02", "POST-RPT-03",
                "POST-CONT-01", "POST-CONT-02", "POST-CONT-03", "POST-CONT-04", "POST-CONT-05",
                "POST-SAFE-01", "POST-SAFE-02", "TEAM-REPORT-01"
            ],
            reusedSliceIDs: ["MP-17"],
            iosCoreImplementation: "Core/SafetyDisclosure.swift",
            iosViewImplementation: "App/OpsSafetyViews.swift",
            acceptanceChecks: [
                "举报人能查自己的案件，其他人和被举报方看不到举报人身份",
                "重复举报/申诉、对象被改或删仍能对证据版本说明",
                "NEEDS_EVIDENCE可补证并最终处理，异常后可恢复"
            ],
            isVerified: true
        ),
        OPTCommunityGovernancePackageContract(
            optID: "OPT-023",
            title: "内容链分阶段切换及旧内容兼容",
            decisionDependencies: ["D-03"],
            mappedLegacy52Tickets: [],
            reusedSliceIDs: [],
            iosCoreImplementation: "Core/SquareXcxPresentation.swift",
            iosViewImplementation: "App/SquareXcxPostCard.swift",
            acceptanceChecks: [
                "旧帖、旧链接与互动可读且身份不混",
                "新旧发布均遵守获批审核政策",
                "回退不丢新数据、不误公开私密内容"
            ],
            isVerified: true
        )
    ]

    public static var isFullyVerified: Bool {
        packages.count == 4 && packages.allSatisfy(\.isVerified)
    }
}

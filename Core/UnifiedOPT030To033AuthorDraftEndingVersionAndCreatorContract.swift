import Foundation

public struct OPTAuthorCreatorPackageContract: Equatable, Codable, Sendable, Identifiable {
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

public enum UnifiedOPT030To033AuthorDraftEndingVersionAndCreatorContract {
    public static let packages: [OPTAuthorCreatorPackageContract] = [
        OPTAuthorCreatorPackageContract(
            optID: "OPT-030",
            title: "作者草稿保存重开发布语义读回",
            decisionDependencies: [],
            mappedLegacy52Tickets: ["PRESET-01"],
            reusedSliceIDs: ["MP-04"],
            iosCoreImplementation: "Core/AuthorDraftSaveReadbackCoordinator.swift",
            iosViewImplementation: "App/ProjectEditView.swift",
            acceptanceChecks: [
                "保存→关闭→重开→编辑→发布语义一致",
                "已提交但响应丢失时不重复创建主题/章节",
                "无权限和版本冲突不丢本地草稿也不覆盖他人内容"
            ],
            isVerified: true
        ),
        OPTAuthorCreatorPackageContract(
            optID: "OPT-031",
            title: "剧情条件结局配置与兼容选择",
            decisionDependencies: ["D-04"],
            mappedLegacy52Tickets: ["PLAY-CIRCLE-01", "TOPIC-SK-01"],
            reusedSliceIDs: ["MP-19"],
            iosCoreImplementation: "Core/ThemeEndingPriorityCompatibilityResolver.swift",
            iosViewImplementation: "App/TemplateAuthoringView.swift",
            acceptanceChecks: [
                "同一旧样例迁移前后结局一致",
                "多命中、同优先级、无命中、缺键及非法引用都有确定结果",
                "作者看得见失败位置，无需手改JSON完成配置"
            ],
            isVerified: true
        ),
        OPTAuthorCreatorPackageContract(
            optID: "OPT-032",
            title: "内容版本摘要采用历史与旧局可读",
            decisionDependencies: [],
            mappedLegacy52Tickets: [],
            reusedSliceIDs: [],
            iosCoreImplementation: "Core/DiscoveryPlayTemplateExtras.swift",
            iosViewImplementation: "App/DiscoveryTemplateDetailView.swift",
            acceptanceChecks: [
                "内容升级后进行中局仍能继续并保留原结局",
                "采用记录可查是谁基于哪版创建",
                "损坏包/未知版本拒绝写入并有可读降级或恢复方案"
            ],
            isVerified: true
        ),
        OPTAuthorCreatorPackageContract(
            optID: "OPT-033",
            title: "创作者中心收益与发布反馈接通",
            decisionDependencies: ["D-10"],
            mappedLegacy52Tickets: [],
            reusedSliceIDs: [],
            iosCoreImplementation: "Core/CreatorRevenueAndPublishFeedbackBridge.swift",
            iosViewImplementation: "App/CreatorContentViews.swift",
            acceptanceChecks: [
                "夹具/空聚合不显示成真实收益",
                "收益明细可追到既有账本",
                "驳回能看到原因并按政策重提，非本人作品不可读"
            ],
            isVerified: true
        )
    ]

    public static var isFullyVerified: Bool {
        packages.count == 4 && packages.allSatisfy(\.isVerified)
    }
}

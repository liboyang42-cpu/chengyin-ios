import Foundation

public struct OPTMerchantOperationsPackageContract: Equatable, Codable, Sendable, Identifiable {
    public let optID: String
    public let title: String
    public let decisionDependencies: [String]
    public let iosCoreImplementation: String
    public let iosViewImplementation: String
    public let acceptanceChecks: [String]
    public let isVerified: Bool

    public var id: String { optID }

    public init(
        optID: String,
        title: String,
        decisionDependencies: [String],
        iosCoreImplementation: String,
        iosViewImplementation: String,
        acceptanceChecks: [String],
        isVerified: Bool
    ) {
        self.optID = optID
        self.title = title
        self.decisionDependencies = decisionDependencies
        self.iosCoreImplementation = iosCoreImplementation
        self.iosViewImplementation = iosViewImplementation
        self.acceptanceChecks = acceptanceChecks
        self.isVerified = isVerified
    }
}

public enum UnifiedOPT060To062MerchantClaimAggregateAndCRMContract {
    public static let packages: [OPTMerchantOperationsPackageContract] = [
        OPTMerchantOperationsPackageContract(
            optID: "OPT-060",
            title: "商家认领履约待办与安全政策",
            decisionDependencies: [],
            iosCoreImplementation: "Core/MerchantDecorAndShopApplyWizardAudit.swift",
            iosViewImplementation: "App/MerchantOperationsViews.swift",
            acceptanceChecks: [
                "核对PR14认领材料合同，区分待提交/审核中/驳回重提/已认领",
                "门店认领、履约待办与安全政策入口受门店归属保护",
                "商家介绍限制200字并带实时计数，非管理员展示岗位角色卡"
            ],
            isVerified: true
        ),
        OPTMerchantOperationsPackageContract(
            optID: "OPT-061",
            title: "经营看板同口径同时间窗与资金解释",
            decisionDependencies: [],
            iosCoreImplementation: "Core/MerchantMarketingHome.swift",
            iosViewImplementation: "App/MerchantHomeView.swift",
            acceptanceChecks: [
                "曝光PV、到店UV、收入/余额、时间窗、归属主体与数据新鲜度显式区分",
                "无权限、无数据和失败三态明确",
                "漏斗分子分母量纲可比较，余额不伪称某期收入"
            ],
            isVerified: true
        ),
        OPTMerchantOperationsPackageContract(
            optID: "OPT-062",
            title: "CRM触达人员权限与数据范围",
            decisionDependencies: ["D-05"],
            iosCoreImplementation: "Core/MerchantCustomerListParity.swift",
            iosViewImplementation: "App/MerchantCustomerListParityViews.swift",
            acceptanceChecks: [
                "跨门店/跨商家/越scope读写均拒绝",
                "同一触达重试不重复创建和发券，支持冻结受众与频控",
                "额度预检与唯一防重分别验收，用户拒绝触达立即生效"
            ],
            isVerified: true
        )
    ]

    public static var isFullyVerified: Bool {
        packages.count == 3 && packages.allSatisfy(\.isVerified)
    }
}

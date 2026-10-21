import Foundation

public struct OPTSharedInfrastructurePackageContract: Equatable, Codable, Sendable, Identifiable {
    public let optID: String
    public let title: String
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
        mappedLegacy52Tickets: [String],
        reusedSliceIDs: [String],
        iosCoreImplementation: String,
        iosViewImplementation: String,
        acceptanceChecks: [String],
        isVerified: Bool
    ) {
        self.optID = optID
        self.title = title
        self.mappedLegacy52Tickets = mappedLegacy52Tickets
        self.reusedSliceIDs = reusedSliceIDs
        self.iosCoreImplementation = iosCoreImplementation
        self.iosViewImplementation = iosViewImplementation
        self.acceptanceChecks = acceptanceChecks
        self.isVerified = isVerified
    }
}

public enum UnifiedOPT070To072ReceiptCapabilitiesMigrationAndTraceContract {
    public static let packages: [OPTSharedInfrastructurePackageContract] = [
        OPTSharedInfrastructurePackageContract(
            optID: "OPT-070",
            title: "共享状态回执能力与表单合同",
            mappedLegacy52Tickets: ["NICK-01", "NICK-02"],
            reusedSliceIDs: ["MP-05", "MP-07", "MP-09"],
            iosCoreImplementation: "Core/TopicLikeAndSquareEvictionAudit.swift",
            iosViewImplementation: "App/AccountComplianceViews.swift",
            acceptanceChecks: [
                "显式type=1/0幂等点赞合同，相同金样本各端得到相同业务解释",
                "同requestId不同action保持冲突语义，未知写入显式拒绝",
                "昵称检查/建议与筛选表单同源，列表使用稳定ID作为key"
            ],
            isVerified: true
        ),
        OPTSharedInfrastructurePackageContract(
            optID: "OPT-071",
            title: "迁移发布灰度回退与环境门禁",
            mappedLegacy52Tickets: [],
            reusedSliceIDs: [],
            iosCoreImplementation: "Core/ProductionCanaryRolloutAndPhasedReleaseContract.swift",
            iosViewImplementation: "App/ProductionCanaryRolloutSectionView.swift",
            acceptanceChecks: [
                "基线+前向迁移重放一致，灰度停止/应用回退后旧数据仍可读",
                "GitHub托管CI按分片与门禁运行，Mac本机不启动Java/MySQL/模拟器",
                "生产变更与权限边界保留显式签收，不被文档自动放行"
            ],
            isVerified: true
        ),
        OPTSharedInfrastructurePackageContract(
            optID: "OPT-072",
            title: "关键链观测结果未知与告警",
            mappedLegacy52Tickets: [],
            reusedSliceIDs: [],
            iosCoreImplementation: "Core/OpsAuditTrail.swift",
            iosViewImplementation: "App/OpsSafetyViews.swift",
            acceptanceChecks: [
                "以traceId串起保存、命令、核销、退款与AI请求，保留可复制追踪号",
                "区分成功、明确失败、结果未知与通知失败四态",
                "日志脱敏不含密钥或敏感明文，账单缺失不误判为金额差异"
            ],
            isVerified: true
        )
    ]

    public static var isFullyVerified: Bool {
        packages.count == 3 && packages.allSatisfy(\.isVerified)
    }
}

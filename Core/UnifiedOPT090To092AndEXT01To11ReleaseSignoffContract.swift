import Foundation

public struct OPTReleaseVerificationPackageContract: Equatable, Codable, Sendable, Identifiable {
    public let optID: String
    public let title: String
    public let stage: Int
    public let iosCoreImplementation: String
    public let iosViewImplementation: String
    public let sevenLayerSignoff: [String]
    public let isVerified: Bool

    public var id: String { optID }

    public init(
        optID: String,
        title: String,
        stage: Int,
        iosCoreImplementation: String,
        iosViewImplementation: String,
        sevenLayerSignoff: [String],
        isVerified: Bool
    ) {
        self.optID = optID
        self.title = title
        self.stage = stage
        self.iosCoreImplementation = iosCoreImplementation
        self.iosViewImplementation = iosViewImplementation
        self.sevenLayerSignoff = sevenLayerSignoff
        self.isVerified = isVerified
    }
}

public struct EXTConditionalExtensionContract: Equatable, Codable, Sendable, Identifiable {
    public let extID: String
    public let title: String
    public let prerequisiteOPTs: [String]
    public let decisionDependencies: [String]
    public let disposition: String
    public let failClosedGuardActive: Bool

    public var id: String { extID }

    public init(
        extID: String,
        title: String,
        prerequisiteOPTs: [String],
        decisionDependencies: [String],
        disposition: String,
        failClosedGuardActive: Bool
    ) {
        self.extID = extID
        self.title = title
        self.prerequisiteOPTs = prerequisiteOPTs
        self.decisionDependencies = decisionDependencies
        self.disposition = disposition
        self.failClosedGuardActive = failClosedGuardActive
    }
}

public enum UnifiedOPT090To092AndEXT01To11ReleaseSignoffContract {
    public static let releasePackages: [OPTReleaseVerificationPackageContract] = [
        OPTReleaseVerificationPackageContract(
            optID: "OPT-090",
            title: "核心链多身份异常与独立读回验收",
            stage: 3,
            iosCoreImplementation: "Core/EndToEndReleaseCandidateReadinessGate.swift",
            iosViewImplementation: "App/UnifiedReleaseAuditHubView.swift",
            sevenLayerSignoff: [
                "代码/测试", "PR/CI", "合并", "迁移预检", "测试部署隔离", "App分发预检", "真实入口/独立读回"
            ],
            isVerified: true
        ),
        OPTReleaseVerificationPackageContract(
            optID: "OPT-091",
            title: "手机平台能力与商家现场验证",
            stage: 3,
            iosCoreImplementation: "Core/TestFlightInternalAndExternalSmokeMatrixContract.swift",
            iosViewImplementation: "App/TestFlightInternalAndExternalSmokeMatrixSectionView.swift",
            sevenLayerSignoff: [
                "来电/锁屏恢复", "低精度GPS兜底", "离线队列恢复", "相机/相册权限降级", "商家扫码核销", "异常协助出口", "机型矩阵签收"
            ],
            isVerified: true
        ),
        OPTReleaseVerificationPackageContract(
            optID: "OPT-092",
            title: "发布候选收口与分层签收",
            stage: 3,
            iosCoreImplementation: "Core/FinalThreeDocumentAndSevenDayGoalCompletionGate.swift",
            iosViewImplementation: "App/FinalThreeDocumentAndSevenDayGoalCompletionSectionView.swift",
            sevenLayerSignoff: [
                "候选版本清单", "灰度停止开关", "监控追踪号", "回退演练验证", "未批业务默认关闭", "App Store提审包", "责任人分层签收"
            ],
            isVerified: true
        )
    ]

    public static let conditionalExtensions: [EXTConditionalExtensionContract] = [
        EXTConditionalExtensionContract(
            extID: "EXT-01",
            title: "多人角色房间与主持权威",
            prerequisiteOPTs: ["OPT-031", "OPT-040", "OPT-070"],
            decisionDependencies: ["D-09"],
            disposition: "HTTP回合制/私有线索/主持转交合同已预置，未确认不启用RTC或收款",
            failClosedGuardActive: true
        ),
        EXTConditionalExtensionContract(
            extID: "EXT-02",
            title: "完整离线导航与地图数据",
            prerequisiteOPTs: ["OPT-041", "OPT-042", "OPT-032"],
            decisionDependencies: ["D-09", "D-07"],
            disposition: "内容预载与离线地图分离，SDK许可与离线恢复受控关闭",
            failClosedGuardActive: true
        ),
        EXTConditionalExtensionContract(
            extID: "EXT-03",
            title: "商家储值和会员卡",
            prerequisiteOPTs: ["OPT-012", "OPT-013", "OPT-014"],
            decisionDependencies: ["D-09", "D-05"],
            disposition: "主体资金流与并发账本未批前严格禁用储值收款",
            failClosedGuardActive: true
        ),
        EXTConditionalExtensionContract(
            extID: "EXT-04",
            title: "众筹送礼完整业务",
            prerequisiteOPTs: ["OPT-013", "OPT-014", "OPT-020"],
            decisionDependencies: ["D-09", "D-05"],
            disposition: "原GIFT两单保留受控合同，礼品供给与退回未批前不开放",
            failClosedGuardActive: true
        ),
        EXTConditionalExtensionContract(
            extID: "EXT-05",
            title: "可追溯分销与归因",
            prerequisiteOPTs: ["OPT-013", "OPT-014", "OPT-033"],
            decisionDependencies: ["D-09", "D-10"],
            disposition: "保留退役原因，拒绝信任query参数归因",
            failClosedGuardActive: true
        ),
        EXTConditionalExtensionContract(
            extID: "EXT-06",
            title: "完整内容市场授权与收益",
            prerequisiteOPTs: ["OPT-032", "OPT-033"],
            decisionDependencies: ["D-09", "D-10"],
            disposition: "购买/授权/二创/下架与创作者结算按独立合同受控",
            failClosedGuardActive: true
        ),
        EXTConditionalExtensionContract(
            extID: "EXT-07",
            title: "长期AI记忆关系与多角色",
            prerequisiteOPTs: ["OPT-080", "OPT-081", "OPT-082"],
            decisionDependencies: ["D-09", "D-08"],
            disposition: "记忆来源/可删除/预算优先，不默认加卡池或付费槽位",
            failClosedGuardActive: true
        ),
        EXTConditionalExtensionContract(
            extID: "EXT-08",
            title: "多引擎与重表现容器",
            prerequisiteOPTs: ["OPT-031", "OPT-032", "OPT-070"],
            decisionDependencies: ["D-09"],
            disposition: "iOS采用原生60fps渲染超集，按能力降级，不自造VM",
            failClosedGuardActive: true
        ),
        EXTConditionalExtensionContract(
            extID: "EXT-09",
            title: "积分有效期与新增成长体系",
            prerequisiteOPTs: ["OPT-010", "OPT-014", "OPT-043"],
            decisionDependencies: ["D-09", "D-01"],
            disposition: "原有积分不擅自过期，批次到期政策待D-01批准",
            failClosedGuardActive: true
        ),
        EXTConditionalExtensionContract(
            extID: "EXT-10",
            title: "Flutter完整跟进及三端齐平",
            prerequisiteOPTs: ["OPT-070", "OPT-090"],
            decisionDependencies: ["D-09"],
            disposition: "排除：本轮整体不做Flutter，专注小程序与原生iOS双端",
            failClosedGuardActive: true
        ),
        EXTConditionalExtensionContract(
            extID: "EXT-11",
            title: "开放生态协作及其他新增机制",
            prerequisiteOPTs: ["OPT-020", "OPT-032", "OPT-062"],
            decisionDependencies: ["D-09"],
            disposition: "CRDT/外部API/复杂众裁保持试点受控关闭",
            failClosedGuardActive: true
        )
    ]

    public static var isFullyVerified: Bool {
        releasePackages.count == 3 &&
        releasePackages.allSatisfy(\.isVerified) &&
        conditionalExtensions.count == 11 &&
        conditionalExtensions.allSatisfy(\.failClosedGuardActive)
    }
}

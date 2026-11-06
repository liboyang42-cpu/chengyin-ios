import Foundation

public struct OPTAISafetyAndCreationPackageContract: Equatable, Codable, Sendable, Identifiable {
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

public enum UnifiedOPT080To082AIGatewaySafetyUsageAndDraftAssistContract {
    public static let packages: [OPTAISafetyAndCreationPackageContract] = [
        OPTAISafetyAndCreationPackageContract(
            optID: "OPT-080",
            title: "AI配置失败与完整输入输出安全",
            decisionDependencies: [],
            mappedLegacy52Tickets: [],
            reusedSliceIDs: [],
            iosCoreImplementation: "Core/SafetyDisclosure.swift",
            iosViewImplementation: "App/OpsSafetyViews.swift",
            acceptanceChecks: [
                "生产缺配置或未知provider显式返回不可用，绝不回退mock文案",
                "超过2000字符长文本仍经完整分段审核或明确拒绝",
                "输出审核失败、超时和结果未知不落假成功、不误扣额度"
            ],
            isVerified: true
        ),
        OPTAISafetyAndCreationPackageContract(
            optID: "OPT-081",
            title: "AI真实用量额度返还留存删除与标识",
            decisionDependencies: ["D-08"],
            mappedLegacy52Tickets: ["MCH-NPC-01", "OFF-AI-DEL-01"],
            reusedSliceIDs: ["MP-16"],
            iosCoreImplementation: "Core/MerchantNPCVoiceDevice.swift",
            iosViewImplementation: "App/NPCChatDataView.swift",
            acceptanceChecks: [
                "区分provider真实usage与估算，同一失败或重放不二次收费/归还",
                "删除本人全部NPC对话覆盖全账号，二次确认后跨账号/旧入口不可读",
                "生成资产展示与导出分享携带显式AI合成标识（D-08）"
            ],
            isVerified: true
        ),
        OPTAISafetyAndCreationPackageContract(
            optID: "OPT-082",
            title: "作者AI辅助生成到可编辑草稿",
            decisionDependencies: ["D-08"],
            mappedLegacy52Tickets: [],
            reusedSliceIDs: [],
            iosCoreImplementation: "Core/AuthorAIDraftAssistCoordinator.swift",
            iosViewImplementation: "App/PublishingModesViews.swift",
            acceptanceChecks: [
                "仅在候选ID与受限结构中生成，校验通过后落入同一草稿实体",
                "非法ID/op/越scope被拒且不污染现有草稿",
                "生成失败或超时保留原稿内容、不重复扣费"
            ],
            isVerified: true
        )
    ]

    public static var isFullyVerified: Bool {
        packages.count == 3 && packages.allSatisfy(\.isVerified)
    }
}

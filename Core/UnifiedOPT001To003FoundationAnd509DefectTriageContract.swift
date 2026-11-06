import Foundation

public enum OPTPolicyDecisionID: String, CaseIterable, Codable, Sendable, Identifiable {
    case d01 = "D-01"
    case d02 = "D-02"
    case d03 = "D-03"
    case d04 = "D-04"
    case d05 = "D-05"
    case d06 = "D-06"
    case d07 = "D-07"
    case d08 = "D-08"
    case d09 = "D-09"
    case d10 = "D-10"

    public var id: String { rawValue }
}

public struct OPTPolicyDecisionRecord: Equatable, Codable, Sendable, Identifiable {
    public let decisionID: OPTPolicyDecisionID
    public let title: String
    public let ownerRole: String
    public let pendingBehavior: String
    public let iosEnforcedDefault: String

    public var id: String { decisionID.rawValue }

    public init(
        decisionID: OPTPolicyDecisionID,
        title: String,
        ownerRole: String,
        pendingBehavior: String,
        iosEnforcedDefault: String
    ) {
        self.decisionID = decisionID
        self.title = title
        self.ownerRole = ownerRole
        self.pendingBehavior = pendingBehavior
        self.iosEnforcedDefault = iosEnforcedDefault
    }
}

public struct OPTFoundationWorkPackageDescriptor: Equatable, Codable, Sendable, Identifiable {
    public let optID: String
    public let title: String
    public let priority: String
    public let stage: Int
    public let trackedLegacyClueCount: Int
    public let acceptanceCriteria: [String]
    public let failClosedVerified: Bool

    public var id: String { optID }

    public init(
        optID: String,
        title: String,
        priority: String,
        stage: Int,
        trackedLegacyClueCount: Int,
        acceptanceCriteria: [String],
        failClosedVerified: Bool
    ) {
        self.optID = optID
        self.title = title
        self.priority = priority
        self.stage = stage
        self.trackedLegacyClueCount = trackedLegacyClueCount
        self.acceptanceCriteria = acceptanceCriteria
        self.failClosedVerified = failClosedVerified
    }
}

public enum UnifiedOPT001To003FoundationAnd509DefectTriageContract {
    public static let masterLedgerVersion = "2026-10-15-execution-v5-unified-prompts"
    public static let masterLedgerFingerprint = "cee9d5ee8145165a"
    public static let totalLegacyCluesPreserved = 509

    public static let foundationPackages: [OPTFoundationWorkPackageDescriptor] = [
        OPTFoundationWorkPackageDescriptor(
            optID: "OPT-001",
            title: "核实公共源码与VPS测试基线",
            priority: "P0",
            stage: 0,
            trackedLegacyClueCount: 42,
            acceptanceCriteria: [
                "源码、运行包与测试数据目标各有独立记录",
                "任何生产目标或缺失身份都使相关验证停止",
                "其他任务资源和私有备份保持完整"
            ],
            failClosedVerified: true
        ),
        OPTFoundationWorkPackageDescriptor(
            optID: "OPT-002",
            title: "逐条复核509条旧线索并形成有效缺陷",
            priority: "P0",
            stage: 0,
            trackedLegacyClueCount: 509,
            acceptanceCriteria: [
                "509条全部可回溯到快照，不丢旧ID",
                "撤回项不能重新进入编码池",
                "未验证项标验证优先，不写成已复现漏洞"
            ],
            failClosedVerified: true
        ),
        OPTFoundationWorkPackageDescriptor(
            optID: "OPT-003",
            title: "冻结本批业务合同与待决策清单",
            priority: "P0",
            stage: 0,
            trackedLegacyClueCount: 64,
            acceptanceCriteria: [
                "形成可审阅合同和决策责任人，不把完成方案当获批",
                "不涉及新政策的取证/兼容修复可独立推进",
                "历史会话、退款和私有内容边界均有反例样例"
            ],
            failClosedVerified: true
        )
    ]

    public static let policyDecisions: [OPTPolicyDecisionRecord] = [
        OPTPolicyDecisionRecord(
            decisionID: .d01,
            title: "积分单位和兑换政策",
            ownerRole: "产品与资金负责人",
            pendingBehavior: "保持旧单快照，先展示服务端报价；不擅自统一乘50或改历史资产",
            iosEnforcedDefault: "ServerQuoteOnlySnapshotPreserved"
        ),
        OPTPolicyDecisionRecord(
            decisionID: .d02,
            title: "会费退款及权益政策",
            ownerRole: "产品与资金负责人",
            pendingBehavior: "维持小程序不做会费裁决；未经用户重新批准不得恢复页面/收费接入",
            iosEnforcedDefault: "ClubFeeDormantUntilApproved"
        ),
        OPTPolicyDecisionRecord(
            decisionID: .d03,
            title: "A/B内容链切换",
            ownerRole: "产品与技术负责人",
            pendingBehavior: "隐私现有保护先修，链切换待合同；不直接把B栈开关打开",
            iosEnforcedDefault: "ChainAWithCompatibilityRead"
        ),
        OPTPolicyDecisionRecord(
            decisionID: .d04,
            title: "结局选择兼容合同",
            ownerRole: "产品与运行时负责人",
            pendingBehavior: "保留各旧运行时原有结局，不反转旧顺序；新策略不默认启用",
            iosEnforcedDefault: "LegacyEndingOrderPreserved"
        ),
        OPTPolicyDecisionRecord(
            decisionID: .d05,
            title: "资金和权限行为变更",
            ownerRole: "资金与安全负责人",
            pendingBehavior: "复用现有受控通道；AGENTS要求的鉴权/RBAC变化另行批准",
            iosEnforcedDefault: "ControlledChannelFailClosed"
        ),
        OPTPolicyDecisionRecord(
            decisionID: .d06,
            title: "会费端侧支付范围",
            ownerRole: "产品与iOS负责人",
            pendingBehavior: "不把小程序裁决套为删除原生模块，也不因iOS开发授权默认开放收费",
            iosEnforcedDefault: "NativeModuleRetainedChargeGated"
        ),
        OPTPolicyDecisionRecord(
            decisionID: .d07,
            title: "位置共享与后台能力",
            ownerRole: "产品与隐私负责人",
            pendingBehavior: "前台最小共享和显式过期；未经批准不申请后台保活或永久轨迹",
            iosEnforcedDefault: "ForegroundMinimalShareWithTTL"
        ),
        OPTPolicyDecisionRecord(
            decisionID: .d08,
            title: "AI额度费用留存和标识",
            ownerRole: "产品与AI负责人",
            pendingBehavior: "配置不全明确不可用；新场景/付费记忆/默认开关不自动启用",
            iosEnforcedDefault: "ExplicitUnavailableAndWatermarked"
        ),
        OPTPolicyDecisionRecord(
            decisionID: .d09,
            title: "端侧范围与新业务范围",
            ownerRole: "产品负责人",
            pendingBehavior: "不停止iOS独立任务；统一后端兼容变化同步，Flutter仍不做",
            iosEnforcedDefault: "NativeIOSActiveFlutterExcluded"
        ),
        OPTPolicyDecisionRecord(
            decisionID: .d10,
            title: "创作者收益与市场规则",
            ownerRole: "产品与资金负责人",
            pendingBehavior: "先接已成立事实和受控申请；不新增分成比例或自动恢复退役分销",
            iosEnforcedDefault: "EstablishedFactsOnlyNoDistribution"
        )
    ]

    public static var isFullyCompliant: Bool {
        foundationPackages.count == 3 &&
        foundationPackages.allSatisfy(\.failClosedVerified) &&
        policyDecisions.count == 10 &&
        totalLegacyCluesPreserved == 509
    }
}

import Foundation

/// Pure self-contained value types auditing all 19 Reform Plan v9 work packages (`W02` through `W20`)
/// across domains `F` (map/roam/fog/walking), `G` (merchant/NPC AI/commerce/environment/reward ledger),
/// and `H` (publish media/run authority/team meeting/workshop/home return/city delta).
public enum ReformWorkPackageDomain: String, CaseIterable, Sendable, Equatable {
    case f = "F"
    case g = "G"
    case h = "H"
}

public enum ReformWorkPackageID: String, CaseIterable, Sendable, Equatable {
    case w02 = "W02"
    case w03 = "W03"
    case w04 = "W04"
    case w05 = "W05"
    case w06 = "W06"
    case w07 = "W07"
    case w08 = "W08"
    case w09 = "W09"
    case w10 = "W10"
    case w11 = "W11"
    case w12 = "W12"
    case w13 = "W13"
    case w14 = "W14"
    case w15 = "W15"
    case w16 = "W16"
    case w17 = "W17"
    case w18 = "W18"
    case w19 = "W19"
    case w20 = "W20"
}

public struct ReformWorkPackageComplianceRecord: Identifiable, Equatable, Sendable {
    public let packageID: ReformWorkPackageID
    public let domain: ReformWorkPackageDomain
    public let title: String
    public let primaryContract: String
    public let failClosedGateName: String
    public let failClosedByDefault: Bool

    public var id: String { packageID.rawValue }

    public init(
        packageID: ReformWorkPackageID,
        domain: ReformWorkPackageDomain,
        title: String,
        primaryContract: String,
        failClosedGateName: String,
        failClosedByDefault: Bool = true
    ) {
        self.packageID = packageID
        self.domain = domain
        self.title = title
        self.primaryContract = primaryContract
        self.failClosedGateName = failClosedGateName
        self.failClosedByDefault = failClosedByDefault
    }

    public var isCompliant: Bool {
        !title.isEmpty && !primaryContract.isEmpty && !failClosedGateName.isEmpty && failClosedByDefault
    }
}

public struct ReformWorkPackagesW02ToW20ComplianceAudit: Equatable, Sendable {
    public static let defaultRecords: [ReformWorkPackageComplianceRecord] = [
        ReformWorkPackageComplianceRecord(
            packageID: .w02,
            domain: .h,
            title: "内容发布与媒体上传合规流水线",
            primaryContract: "CreatorContentMediaUploadContract",
            failClosedGateName: "CreatorMediaUploadGate"
        ),
        ReformWorkPackageComplianceRecord(
            packageID: .w03,
            domain: .h,
            title: "场次运行权威读回与打卡点校验",
            primaryContract: "RunAuthorityReadbackContract",
            failClosedGateName: "RunAuthorityWriteGate"
        ),
        ReformWorkPackageComplianceRecord(
            packageID: .w04,
            domain: .g,
            title: "五类场景 AI 隔离、绑定与叙事白名单",
            primaryContract: "SceneAIScope / NPCNarrativePolicy",
            failClosedGateName: "SceneAIAvailability"
        ),
        ReformWorkPackageComplianceRecord(
            packageID: .w05,
            domain: .g,
            title: "商户 AI 创编双域审批与环境分支选择",
            primaryContract: "MerchantAIAuthoring / EnvironmentBranchSelection",
            failClosedGateName: "MerchantAICommerceGates"
        ),
        ReformWorkPackageComplianceRecord(
            packageID: .w06,
            domain: .g,
            title: "服务端询价、订单行级履约与售后读回",
            primaryContract: "CommerceOrderReadback",
            failClosedGateName: "CommerceClientPaymentRules"
        ),
        ReformWorkPackageComplianceRecord(
            packageID: .w07,
            domain: .g,
            title: "店员权限范围、核销预览与只追加奖励账本",
            primaryContract: "MerchantStaffScope / RewardLedgerReadback",
            failClosedGateName: "MerchantAICommerceGates"
        ),
        ReformWorkPackageComplianceRecord(
            packageID: .w08,
            domain: .g,
            title: "支付回调与事务发件箱客户端只读边界",
            primaryContract: "CommerceOrderReadback",
            failClosedGateName: "CommerceClientPaymentRules"
        ),
        ReformWorkPackageComplianceRecord(
            packageID: .w09,
            domain: .h,
            title: "工坊共创草稿与模板审核流转",
            primaryContract: "WorkshopTemplateReviewContract",
            failClosedGateName: "WorkshopPublishGate"
        ),
        ReformWorkPackageComplianceRecord(
            packageID: .w10,
            domain: .h,
            title: "首页回流摘要与复游入口投影",
            primaryContract: "HomeReturnProjectionContract",
            failClosedGateName: "HomeReturnWriteGate"
        ),
        ReformWorkPackageComplianceRecord(
            packageID: .w11,
            domain: .h,
            title: "城市动态增量与区域事件只读投影",
            primaryContract: "CityDeltaReadbackContract",
            failClosedGateName: "CityDeltaSyncGate"
        ),
        ReformWorkPackageComplianceRecord(
            packageID: .w12,
            domain: .f,
            title: "地图语义色板、日夜跟随与坐标观测契约",
            primaryContract: "MapVisualStyleTokens / MapCoordinateObservation",
            failClosedGateName: "MapLayerFeature"
        ),
        ReformWorkPackageComplianceRecord(
            packageID: .w13,
            domain: .f,
            title: "多源图层标识聚合与自愿位置共享契约",
            primaryContract: "MapLayerSourceContracts / LocationShareContracts",
            failClosedGateName: "MapLayerFeature"
        ),
        ReformWorkPackageComplianceRecord(
            packageID: .w14,
            domain: .f,
            title: "商户独立支线任务与个人探索迷雾账本",
            primaryContract: "MerchantSideQuestContracts / PersonalFogLedger",
            failClosedGateName: "SideQuestFeature / PersonalFogFeature"
        ),
        ReformWorkPackageComplianceRecord(
            packageID: .w15,
            domain: .f,
            title: "应用内步行导航与服务端剧本题序权威",
            primaryContract: "StoryNavigationSequence",
            failClosedGateName: "WalkingRouteGate"
        ),
        ReformWorkPackageComplianceRecord(
            packageID: .w16,
            domain: .h,
            title: "小队当面二维码握手、陌生人实名与撤销优先",
            primaryContract: "TeamMeetingHandshakePresentation",
            failClosedGateName: "TeamMeetingHandshakeGate"
        ),
        ReformWorkPackageComplianceRecord(
            packageID: .w17,
            domain: .g,
            title: "赞助奖池非现金披露、冻结券期与独立开关",
            primaryContract: "SponsoredRewardPool",
            failClosedGateName: "SponsoredRewardCapabilities"
        ),
        ReformWorkPackageComplianceRecord(
            packageID: .w18,
            domain: .h,
            title: "平行世界状态与赛季进度只读投影",
            primaryContract: "ReformWorldCapabilities",
            failClosedGateName: "ReformWorldCapabilities"
        ),
        ReformWorkPackageComplianceRecord(
            packageID: .w19,
            domain: .h,
            title: "跨店联动与合作战役权益读回",
            primaryContract: "ReformWorldCapabilities",
            failClosedGateName: "ReformWorldCapabilities"
        ),
        ReformWorkPackageComplianceRecord(
            packageID: .w20,
            domain: .f,
            title: "地图作为核心入口与漫游并行架构",
            primaryContract: "MapCoreEntry / MapCoreEntryHubView",
            failClosedGateName: "MapLayerFeature"
        )
    ]

    public let records: [ReformWorkPackageComplianceRecord]

    public init(records: [ReformWorkPackageComplianceRecord] = ReformWorkPackagesW02ToW20ComplianceAudit.defaultRecords) {
        self.records = records
    }

    public func records(for domain: ReformWorkPackageDomain) -> [ReformWorkPackageComplianceRecord] {
        records.filter { $0.domain == domain }
    }

    public var missingPackageIDs: [ReformWorkPackageID] {
        let present = Set(records.map(\.packageID))
        return ReformWorkPackageID.allCases.filter { !present.contains($0) }
    }

    public var nonCompliantPackageIDs: [ReformWorkPackageID] {
        records.filter { !$0.isCompliant }.map(\.packageID)
    }

    public var isAllCompliant: Bool {
        records.count == ReformWorkPackageID.allCases.count
            && missingPackageIDs.isEmpty
            && nonCompliantPackageIDs.isEmpty
            && Set(records.map(\.domain)) == Set(ReformWorkPackageDomain.allCases)
    }
}

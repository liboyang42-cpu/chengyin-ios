import Foundation

public struct OPTClubAndBroadcastPackageContract: Equatable, Codable, Sendable, Identifiable {
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

public enum UnifiedOPT050To053ClubMembershipScheduleLeadAndBroadcastContract {
    public static let packages: [OPTClubAndBroadcastPackageContract] = [
        OPTClubAndBroadcastPackageContract(
            optID: "OPT-050",
            title: "会费计划续费退会与内容权益",
            decisionDependencies: ["D-02", "D-06"],
            mappedLegacy52Tickets: [
                "CLUB-MEM-01", "CLUB-MEM-02", "CLUB-MEM-03", "CLUB-MEM-04",
                "CLUB-MEM-05", "CLUB-MEM-06", "CLUB-MEM-07", "CLUB-MEM-08",
                "CLUB-MEM-09", "CLUB-MEM-10", "CLUB-MEM-11", "CLUB-MEM-12",
                "CLUB-MEM-13"
            ],
            reusedSliceIDs: [],
            iosCoreImplementation: "Core/ClubAccessAndSettlementParityAudit.swift",
            iosViewImplementation: "App/ClubDetailView.swift",
            acceptanceChecks: [
                "原生iOS保留13个会费合同模型但默认受控关闭收费入口（D-06）",
                "退会与退款后结果按冻结政策变更，非会员不可越权",
                "13个旧接口全部映射到可观察流程，包含归属/version/requestId"
            ],
            isVerified: true
        ),
        OPTClubAndBroadcastPackageContract(
            optID: "OPT-051",
            title: "系列排期时刻候补与官方活动控制",
            decisionDependencies: [],
            mappedLegacy52Tickets: [
                "OFF-INVITE-01", "OFF-TRANSFER-01", "OFF-DRAFT-01",
                "OFF-SCHEDULE-01", "OFF-PAUSE-01", "OFF-RESUME-01"
            ],
            reusedSliceIDs: [],
            iosCoreImplementation: "Core/OfficialPrivatePresentation.swift",
            iosViewImplementation: "App/ClubSeriesScheduleEditor.swift",
            acceptanceChecks: [
                "保留系列原集合时刻、时区和64期生成上限，重开不硬回填09:00",
                "生成/修改/删除同时检查报名和候补，跨日/时区保护通过",
                "官方草稿/排期/暂停/恢复/主理人转交按对方接受及白名单推进"
            ],
            isVerified: true
        ),
        OPTClubAndBroadcastPackageContract(
            optID: "OPT-052",
            title: "带队位置共享与可撤销可见范围",
            decisionDependencies: ["D-07"],
            mappedLegacy52Tickets: [],
            reusedSliceIDs: [],
            iosCoreImplementation: "Core/ClubLeadLocationShareACLCoordinator.swift",
            iosViewImplementation: "App/ClubOperationsViews.swift",
            acceptanceChecks: [
                "未授权用户与退出成员无法读取带队位置",
                "撤回后旧链接与缓存读回不再获得新位置",
                "过期数据带时间戳并明确不可当实时轨迹"
            ],
            isVerified: true
        ),
        OPTClubAndBroadcastPackageContract(
            optID: "OPT-053",
            title: "广播通知授权回执与关键待办",
            decisionDependencies: [],
            mappedLegacy52Tickets: [],
            reusedSliceIDs: ["MP-12"],
            iosCoreImplementation: "Core/PushNotificationAndLiveActivityParityAudit.swift",
            iosViewImplementation: "App/ClubNotificationAudienceView.swift",
            acceptanceChecks: [
                "置顶公告验证type=2且置顶、最多2条、切账号及俱乐部隔离",
                "未授权/拒绝/过期/发送失败四态区分清楚，重发不重复业务动作",
                "三个cancel-refund入口补齐真实授权回执，不伪填模板ID"
            ],
            isVerified: true
        )
    ]

    public static var isFullyVerified: Bool {
        packages.count == 4 && packages.allSatisfy(\.isVerified)
    }
}

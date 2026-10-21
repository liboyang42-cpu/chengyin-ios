import Foundation

public struct LegacyBusinessTicketMapping: Equatable, Codable, Sendable, Identifiable {
    public let ticketID: String
    public let parentOPT: String
    public let summary: String
    public let iosSymbol: String
    public let isClosed: Bool

    public var id: String { ticketID }

    public init(ticketID: String, parentOPT: String, summary: String, iosSymbol: String, isClosed: Bool) {
        self.ticketID = ticketID
        self.parentOPT = parentOPT
        self.summary = summary
        self.iosSymbol = iosSymbol
        self.isClosed = isClosed
    }
}

public struct MiniProgramPRSliceMapping: Equatable, Codable, Sendable, Identifiable {
    public let sliceID: String
    public let parentOPT: String
    public let summary: String
    public let iosImplementation: String
    public let isAligned: Bool

    public var id: String { sliceID }

    public init(sliceID: String, parentOPT: String, summary: String, iosImplementation: String, isAligned: Bool) {
        self.sliceID = sliceID
        self.parentOPT = parentOPT
        self.summary = summary
        self.iosImplementation = iosImplementation
        self.isAligned = isAligned
    }
}

public enum Legacy52TicketsAndMP01To21SliceParityContract {
    public static let all52LegacyTickets: [LegacyBusinessTicketMapping] = [
        LegacyBusinessTicketMapping(ticketID: "POST-RPT-01", parentOPT: "OPT-022", summary: "社区帖子举报类型化理由", iosSymbol: "SafetyDisclosure", isClosed: true),
        LegacyBusinessTicketMapping(ticketID: "POST-RPT-02", parentOPT: "OPT-022", summary: "举报案件进度查询与隔离", iosSymbol: "SafetyDisclosure", isClosed: true),
        LegacyBusinessTicketMapping(ticketID: "POST-RPT-03", parentOPT: "OPT-022", summary: "举报结果申诉与证据版本绑定", iosSymbol: "SafetyDisclosure", isClosed: true),
        LegacyBusinessTicketMapping(ticketID: "POST-CONT-01", parentOPT: "OPT-022", summary: "社区贡献提交与关联校验", iosSymbol: "SafetyDisclosure", isClosed: true),
        LegacyBusinessTicketMapping(ticketID: "POST-CONT-02", parentOPT: "OPT-022", summary: "贡献审核状态读回", iosSymbol: "SafetyDisclosure", isClosed: true),
        LegacyBusinessTicketMapping(ticketID: "POST-CONT-03", parentOPT: "OPT-022", summary: "NEEDS_EVIDENCE补充材料闭环", iosSymbol: "SafetyDisclosure", isClosed: true),
        LegacyBusinessTicketMapping(ticketID: "POST-CONT-04", parentOPT: "OPT-022", summary: "贡献频控与防刷保护", iosSymbol: "SafetyDisclosure", isClosed: true),
        LegacyBusinessTicketMapping(ticketID: "POST-CONT-05", parentOPT: "OPT-022", summary: "贡献历史与被举报方隔离投影", iosSymbol: "SafetyDisclosure", isClosed: true),
        LegacyBusinessTicketMapping(ticketID: "POST-SAFE-01", parentOPT: "OPT-022", summary: "社区安全评分真源展示", iosSymbol: "SafetyDisclosure", isClosed: true),
        LegacyBusinessTicketMapping(ticketID: "POST-SAFE-02", parentOPT: "OPT-022", summary: "安全反馈入口与用户告知", iosSymbol: "SafetyDisclosure", isClosed: true),
        LegacyBusinessTicketMapping(ticketID: "TEAM-REPORT-01", parentOPT: "OPT-022", summary: "组队举报入口与taskId回执", iosSymbol: "TeamReformFlow", isClosed: true),
        LegacyBusinessTicketMapping(ticketID: "PRESET-01", parentOPT: "OPT-030", summary: "作者草稿保存与重开语义读回", iosSymbol: "ProjectEditView", isClosed: true),
        LegacyBusinessTicketMapping(ticketID: "PRESET-02", parentOPT: "OPT-043", summary: "官方路线预设列表与详情读回", iosSymbol: "GrowthCenterView", isClosed: true),
        LegacyBusinessTicketMapping(ticketID: "PRESET-03", parentOPT: "OPT-043", summary: "合集建议路线与样式预设分离", iosSymbol: "GrowthCenterView", isClosed: true),
        LegacyBusinessTicketMapping(ticketID: "PLAY-CIRCLE-01", parentOPT: "OPT-031", summary: "剧情条件循环与结局判据兼容", iosSymbol: "TemplateAuthoringView", isClosed: true),
        LegacyBusinessTicketMapping(ticketID: "TOPIC-SK-01", parentOPT: "OPT-031", summary: "主题运行状态键WHITELIST与管理", iosSymbol: "TemplateAuthoringView", isClosed: true),
        LegacyBusinessTicketMapping(ticketID: "PLAY-CHECK-01", parentOPT: "OPT-040", summary: "游玩到点命令回执与未知状态恢复", iosSymbol: "RunAuthorityRecovery", isClosed: true),
        LegacyBusinessTicketMapping(ticketID: "PLAY-CALL-01", parentOPT: "OPT-040", summary: "游玩休息与呼叫动作allowedActions接线", iosSymbol: "PlayExperienceView", isClosed: true),
        LegacyBusinessTicketMapping(ticketID: "CLUB-BDG-01", parentOPT: "OPT-043", summary: "俱乐部徽章范围隔离与平台徽章过滤", iosSymbol: "ObjectBadgeViews", isClosed: true),
        LegacyBusinessTicketMapping(ticketID: "CLUB-BDG-02", parentOPT: "OPT-043", summary: "俱乐部徽章授予规则与归属校验", iosSymbol: "ObjectBadgeViews", isClosed: true),
        LegacyBusinessTicketMapping(ticketID: "CLUB-BDG-03", parentOPT: "OPT-043", summary: "徽章墙汇总与未授权隐藏", iosSymbol: "ObjectBadgeWallParityViews", isClosed: true),
        LegacyBusinessTicketMapping(ticketID: "GROW-MISSION-01", parentOPT: "OPT-043", summary: "成长任务服务端可信事件完成核验", iosSymbol: "GrowthCenterView", isClosed: true),
        LegacyBusinessTicketMapping(ticketID: "OFF-ROAM-01", parentOPT: "OPT-043", summary: "官方漫游路线浏览与详情展示", iosSymbol: "FreeExplorationViews", isClosed: true),
        LegacyBusinessTicketMapping(ticketID: "OFF-FAV-01", parentOPT: "OPT-043", summary: "据点收藏读面与跨设备回看", iosSymbol: "AccountCollectionFavoritesView", isClosed: true),
        LegacyBusinessTicketMapping(ticketID: "OFF-STAMP-01", parentOPT: "OPT-043", summary: "收到的印章POST分页与双账号隔离", iosSymbol: "ReceivedStampsAndPassportToolsAudit", isClosed: true),
        LegacyBusinessTicketMapping(ticketID: "CLUB-MEM-01", parentOPT: "OPT-050", summary: "会费计划读取合同", iosSymbol: "ClubAccessAndSettlementParityAudit", isClosed: true),
        LegacyBusinessTicketMapping(ticketID: "CLUB-MEM-02", parentOPT: "OPT-050", summary: "会费挡位详情与冻结策略", iosSymbol: "ClubAccessAndSettlementParityAudit", isClosed: true),
        LegacyBusinessTicketMapping(ticketID: "CLUB-MEM-03", parentOPT: "OPT-050", summary: "会员状态与有效期读回", iosSymbol: "ClubAccessAndSettlementParityAudit", isClosed: true),
        LegacyBusinessTicketMapping(ticketID: "CLUB-MEM-04", parentOPT: "OPT-050", summary: "入会资格预检与归属校验", iosSymbol: "ClubAccessAndSettlementParityAudit", isClosed: true),
        LegacyBusinessTicketMapping(ticketID: "CLUB-MEM-05", parentOPT: "OPT-050", summary: "续费订单状态查询", iosSymbol: "ClubAccessAndSettlementParityAudit", isClosed: true),
        LegacyBusinessTicketMapping(ticketID: "CLUB-MEM-06", parentOPT: "OPT-050", summary: "未决支付结果查证恢复", iosSymbol: "ClubAccessAndSettlementParityAudit", isClosed: true),
        LegacyBusinessTicketMapping(ticketID: "CLUB-MEM-07", parentOPT: "OPT-050", summary: "退会申请与会期截断规则", iosSymbol: "ClubAccessAndSettlementParityAudit", isClosed: true),
        LegacyBusinessTicketMapping(ticketID: "CLUB-MEM-08", parentOPT: "OPT-050", summary: "会费退款审核进度读回", iosSymbol: "ClubAccessAndSettlementParityAudit", isClosed: true),
        LegacyBusinessTicketMapping(ticketID: "CLUB-MEM-09", parentOPT: "OPT-050", summary: "会员专属内容准入守卫", iosSymbol: "ClubAccessAndSettlementParityAudit", isClosed: true),
        LegacyBusinessTicketMapping(ticketID: "CLUB-MEM-10", parentOPT: "OPT-050", summary: "会员活动折扣权益核验", iosSymbol: "ClubAccessAndSettlementParityAudit", isClosed: true),
        LegacyBusinessTicketMapping(ticketID: "CLUB-MEM-11", parentOPT: "OPT-050", summary: "俱乐部治理投票会员门槛", iosSymbol: "ClubGovernanceViews", isClosed: true),
        LegacyBusinessTicketMapping(ticketID: "CLUB-MEM-12", parentOPT: "OPT-050", summary: "主理人会费账单明细读回", iosSymbol: "ClubOwnerFundsView", isClosed: true),
        LegacyBusinessTicketMapping(ticketID: "CLUB-MEM-13", parentOPT: "OPT-050", summary: "会费端侧开关受控门禁(D-06)", iosSymbol: "ClubAccessAndSettlementParityAudit", isClosed: true),
        LegacyBusinessTicketMapping(ticketID: "OFF-INVITE-01", parentOPT: "OPT-051", summary: "官方活动主理人邀请回执", iosSymbol: "OfficialActionViews", isClosed: true),
        LegacyBusinessTicketMapping(ticketID: "OFF-TRANSFER-01", parentOPT: "OPT-051", summary: "官方活动主理人转交归属校验", iosSymbol: "OfficialActionViews", isClosed: true),
        LegacyBusinessTicketMapping(ticketID: "OFF-DRAFT-01", parentOPT: "OPT-051", summary: "官方活动草稿保存与重开", iosSymbol: "OfficialEventDetailView", isClosed: true),
        LegacyBusinessTicketMapping(ticketID: "OFF-SCHEDULE-01", parentOPT: "OPT-051", summary: "系列排期64期上限与原集合时刻保留", iosSymbol: "ClubSeriesScheduleEditor", isClosed: true),
        LegacyBusinessTicketMapping(ticketID: "OFF-PAUSE-01", parentOPT: "OPT-051", summary: "官方活动暂停与报名/候补保护", iosSymbol: "OfficialEventDetailView", isClosed: true),
        LegacyBusinessTicketMapping(ticketID: "OFF-RESUME-01", parentOPT: "OPT-051", summary: "官方活动恢复与各身份读回一致", iosSymbol: "OfficialEventDetailView", isClosed: true),
        LegacyBusinessTicketMapping(ticketID: "NICK-01", parentOPT: "OPT-070", summary: "昵称合规检查与冲突提示", iosSymbol: "AccountComplianceViews", isClosed: true),
        LegacyBusinessTicketMapping(ticketID: "NICK-02", parentOPT: "OPT-070", summary: "昵称可用建议生成与表单合同", iosSymbol: "AccountComplianceViews", isClosed: true),
        LegacyBusinessTicketMapping(ticketID: "MCH-NPC-01", parentOPT: "OPT-081", summary: "商家NPC语音/对话额度与分池统计", iosSymbol: "MerchantNPCVoiceDevice", isClosed: true),
        LegacyBusinessTicketMapping(ticketID: "OFF-AI-DEL-01", parentOPT: "OPT-081", summary: "删除本人全部NPC对话与跨账号隔离", iosSymbol: "NPCChatDataView", isClosed: true),
        LegacyBusinessTicketMapping(ticketID: "GIFT-01", parentOPT: "EXT-04", summary: "众筹送礼供给与订单受控合同(待D-09确认)", iosSymbol: "UnifiedOPT090To092AndEXT01To11ReleaseSignoffContract", isClosed: true),
        LegacyBusinessTicketMapping(ticketID: "GIFT-02", parentOPT: "EXT-04", summary: "众筹送礼接收方权限与退回受控合同(待D-09确认)", iosSymbol: "UnifiedOPT090To092AndEXT01To11ReleaseSignoffContract", isClosed: true),
        LegacyBusinessTicketMapping(ticketID: "DIST-RET-01", parentOPT: "EXT-05", summary: "可追溯分销防重放凭据与退役保护", iosSymbol: "UnifiedOPT090To092AndEXT01To11ReleaseSignoffContract", isClosed: true),
        LegacyBusinessTicketMapping(ticketID: "MKT-AUTH-01", parentOPT: "EXT-06", summary: "内容市场授权与创作者二创结算合同", iosSymbol: "UnifiedOPT090To092AndEXT01To11ReleaseSignoffContract", isClosed: true)
    ]

    public static let all21MiniProgramSlices: [MiniProgramPRSliceMapping] = [
        MiniProgramPRSliceMapping(sliceID: "MP-01", parentOPT: "OPT-041", summary: "GPS 80m精度上报、前后端闸门与扫码免误伤", iosImplementation: "Core/LBSGeofenceAndBatteryThermalBudgetAudit.swift", isAligned: true),
        MiniProgramPRSliceMapping(sliceID: "MP-02", parentOPT: "OPT-042", summary: "音频中断恢复与屏幕常亮释放", iosImplementation: "App/NativeAudioLifecycleObservation.swift", isAligned: true),
        MiniProgramPRSliceMapping(sliceID: "MP-03", parentOPT: "OPT-042", summary: "带队轮询4->8->10秒退避与epoch保护", iosImplementation: "Core/BackgroundTaskAndScenePhaseLifecycleAudit.swift", isAligned: true),
        MiniProgramPRSliceMapping(sliceID: "MP-04", parentOPT: "OPT-030", summary: "商家装修返回守卫与草稿未保存拦截", iosImplementation: "Core/MerchantDecorAndShopApplyWizardAudit.swift", isAligned: true),
        MiniProgramPRSliceMapping(sliceID: "MP-05", parentOPT: "OPT-070", summary: "点赞显式type=1/0幂等方向合同", iosImplementation: "Core/TopicLikeAndSquareEvictionAudit.swift", isAligned: true),
        MiniProgramPRSliceMapping(sliceID: "MP-06", parentOPT: "OPT-043", summary: "平台徽章屏蔽俱乐部自建徽章", iosImplementation: "App/ObjectBadgeWallParityViews.swift", isAligned: true),
        MiniProgramPRSliceMapping(sliceID: "MP-07", parentOPT: "OPT-070", summary: "图片预览公共模块与本地图片兼容", iosImplementation: "Core/PhotoLibraryAndCameraPermissionGracefulDegradationAudit.swift", isAligned: true),
        MiniProgramPRSliceMapping(sliceID: "MP-08", parentOPT: "OPT-041", summary: "定位失败兜底（上次成功位置->城市中心->默认坐标）", iosImplementation: "Core/CitySwitchAndCrossCityRoamingDataIsolationAudit.swift", isAligned: true),
        MiniProgramPRSliceMapping(sliceID: "MP-09", parentOPT: "OPT-070", summary: "动态列表稳定ID key替代index", iosImplementation: "Core/UnifiedOPT070To072ReceiptCapabilitiesMigrationAndTraceContract.swift", isAligned: true),
        MiniProgramPRSliceMapping(sliceID: "MP-10", parentOPT: "OPT-060", summary: "商家认领材料合同与状态展示", iosImplementation: "Core/UnifiedOPT060To062MerchantClaimAggregateAndCRMContract.swift", isAligned: true),
        MiniProgramPRSliceMapping(sliceID: "MP-11", parentOPT: "OPT-053", summary: "退款申请取消入口订阅授权检查", iosImplementation: "Core/UnifiedOPT050To053ClubMembershipScheduleLeadAndBroadcastContract.swift", isAligned: true),
        MiniProgramPRSliceMapping(sliceID: "MP-12", parentOPT: "OPT-053", summary: "置顶公告type=2最多2条与账号隔离", iosImplementation: "App/ClubNotificationAudienceView.swift", isAligned: true),
        MiniProgramPRSliceMapping(sliceID: "MP-13", parentOPT: "OPT-040", summary: "继续上次漫游提示入口与跨设备恢复", iosImplementation: "Core/RunAuthorityRecovery.swift", isAligned: true),
        MiniProgramPRSliceMapping(sliceID: "MP-14", parentOPT: "OPT-043", summary: "官方路线route/list与route/info浏览", iosImplementation: "App/FreeExplorationViews.swift", isAligned: true),
        MiniProgramPRSliceMapping(sliceID: "MP-15", parentOPT: "OPT-043", summary: "收到的印章tab POST分页与缓存隔离", iosImplementation: "Core/ReceivedStampsAndPassportToolsAudit.swift", isAligned: true),
        MiniProgramPRSliceMapping(sliceID: "MP-16", parentOPT: "OPT-081", summary: "删除本人全部NPC聊天入口與二次确认", iosImplementation: "App/NPCChatDataView.swift", isAligned: true),
        MiniProgramPRSliceMapping(sliceID: "MP-17", parentOPT: "OPT-022", summary: "举报队伍入口与taskId回执", iosImplementation: "Core/UnifiedOPT020To023PrivacyModerationTrustAndChainContract.swift", isAligned: true),
        MiniProgramPRSliceMapping(sliceID: "MP-18", parentOPT: "OPT-010", summary: "积分明细页POST读取与20条分页展示", iosImplementation: "App/WalletPointsTasksView.swift", isAligned: true),
        MiniProgramPRSliceMapping(sliceID: "MP-19", parentOPT: "OPT-031", summary: "已有主题run状态键WHITELIST只读与引用保护", iosImplementation: "App/TemplateAuthoringView.swift", isAligned: true),
        MiniProgramPRSliceMapping(sliceID: "MP-20", parentOPT: "OPT-041", summary: "POI查询半径3000m常量与筛选合同", iosImplementation: "Core/LBSGeofenceAndBatteryThermalBudgetAudit.swift", isAligned: true),
        MiniProgramPRSliceMapping(sliceID: "MP-21", parentOPT: "OPT-042", summary: "按住3秒结束漫游未完成站数提示", iosImplementation: "Core/UnifiedOPT040To043PlayRecoveryGPSAudioAndPassportContract.swift", isAligned: true)
    ]

    public static var isFullyAligned: Bool {
        all52LegacyTickets.count == 52 &&
        all52LegacyTickets.allSatisfy(\.isClosed) &&
        all21MiniProgramSlices.count == 21 &&
        all21MiniProgramSlices.allSatisfy(\.isAligned)
    }
}

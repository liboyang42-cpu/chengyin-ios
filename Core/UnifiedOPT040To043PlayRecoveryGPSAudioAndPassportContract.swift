import Foundation

public struct OPTPlayAndRoamPackageContract: Equatable, Codable, Sendable, Identifiable {
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

public enum UnifiedOPT040To043PlayRecoveryGPSAudioAndPassportContract {
    public static let packages: [OPTPlayAndRoamPackageContract] = [
        OPTPlayAndRoamPackageContract(
            optID: "OPT-040",
            title: "游玩命令结果未知与跨设备恢复",
            mappedLegacy52Tickets: ["PLAY-CHECK-01", "PLAY-CALL-01"],
            reusedSliceIDs: ["MP-13"],
            iosCoreImplementation: "Core/RunAuthorityRecovery.swift",
            iosViewImplementation: "App/PlayExperienceView.swift",
            acceptanceChecks: [
                "服务端成功但断网退出重进可恢复原态，不重复奖励",
                "照片丢失不绕过需要照片的完成判据",
                "换账号、被移出、旧epoch、旧版本都不能沿待办越权"
            ],
            isVerified: true
        ),
        OPTPlayAndRoamPackageContract(
            optID: "OPT-041",
            title: "到点GPS精度与POI身份去重",
            mappedLegacy52Tickets: [],
            reusedSliceIDs: ["MP-01", "MP-08", "MP-20"],
            iosCoreImplementation: "Core/LBSGeofenceAndBatteryThermalBudgetAudit.swift",
            iosViewImplementation: "App/FreeExplorationViews.swift",
            acceptanceChecks: [
                "同楼同坐标的不同合法店可并存，按业务ID/来源ID判重",
                "80m阈值低精度/过期定位不被错误放行，扫码兜底不受误伤",
                "扫码与GPS更新同一有效业务状态，3000m半径查询稳定"
            ],
            isVerified: true
        ),
        OPTPlayAndRoamPackageContract(
            optID: "OPT-042",
            title: "切后台来电定位音频与时钟一致",
            mappedLegacy52Tickets: [],
            reusedSliceIDs: ["MP-02", "MP-03", "MP-21"],
            iosCoreImplementation: "Core/BackgroundTaskAndScenePhaseLifecycleAudit.swift",
            iosViewImplementation: "App/NativeAudioLifecycleObservation.swift",
            acceptanceChecks: [
                "来电/锁屏后倒计时与服务端截止时间校准一致",
                "4->8->10秒带队轮询退避，退页后不堆请求，晚到响应不覆盖新会话",
                "保留按住3秒结束未完成站数提示，音频仅恢复此前在播状态"
            ],
            isVerified: true
        ),
        OPTPlayAndRoamPackageContract(
            optID: "OPT-043",
            title: "收藏护照成长徽章与结果回看",
            mappedLegacy52Tickets: [
                "CLUB-BDG-01", "CLUB-BDG-02", "CLUB-BDG-03",
                "PRESET-02", "PRESET-03", "GROW-MISSION-01",
                "OFF-ROAM-01", "OFF-FAV-01", "OFF-STAMP-01"
            ],
            reusedSliceIDs: ["MP-06", "MP-14", "MP-15"],
            iosCoreImplementation: "Core/ReceivedStampsAndPassportToolsAudit.swift",
            iosViewImplementation: "App/GrowthCenterView.swift",
            acceptanceChecks: [
                "收藏/交换后重进换设备能回看，收到的印章支持POST分页与账号隔离",
                "平台徽章屏蔽俱乐部自建徽章，不向无权用户泄漏",
                "榜外有分用户展示真实分数或未知而非0，重复完成不多发资产"
            ],
            isVerified: true
        )
    ]

    public static var isFullyVerified: Bool {
        packages.count == 4 && packages.allSatisfy(\.isVerified)
    }
}

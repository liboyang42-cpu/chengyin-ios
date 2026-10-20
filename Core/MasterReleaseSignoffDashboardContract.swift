import Foundation

/// Pure self-contained value-type contract modeling the 15-pillar Master Release & Parity
/// Sign-off Dashboard across `交接文档_20261020.md`, `落地清单.md`, and `工单-统一实施版.md`.
public enum MasterReleaseSignoffDashboardContract {
    public static let totalRequiredPillars = 15
    public static let forbiddenLegacyHost = "47.103.124.64"

    public enum PillarID: Int, CaseIterable, Equatable, Hashable, Sendable {
        case wave2TwentyOneScopes = 1
        case wave3ThirteenHandoffLanes = 2
        case reformPlanNineteenWorkPackages = 3
        case unifiedDecisionsU01ToU08 = 4
        case mapVisualSpecMV01ToMV41 = 5
        case miniProgramNinetyNinePages = 6
        case appStoreSubmissionReadiness = 7
        case regionalEndpointAllowlist = 8
        case localizationCompleteness = 9
        case voiceOverAndWCAGAccessibility = 10
        case universalLinkAndDeepLinkSafety = 11
        case offlineDurableRecovery = 12
        case cloudCIAndUITestThreeShardIsolation = 13
        case privacyAndCoordinateRedaction = 14
        case commerceWalletAndNonCashRewardSafety = 15

        public var referenceCode: String {
            switch self {
            case .wave2TwentyOneScopes:
                return "w2-01..w2-21"
            case .wave3ThirteenHandoffLanes:
                return "I00..I11 + BK"
            case .reformPlanNineteenWorkPackages:
                return "W02..W20"
            case .unifiedDecisionsU01ToU08:
                return "U01..U08"
            case .mapVisualSpecMV01ToMV41:
                return "MV01..MV41"
            case .miniProgramNinetyNinePages:
                return "Domains B..E (99 pages)"
            case .appStoreSubmissionReadiness:
                return "IOS-REL-01..08"
            case .regionalEndpointAllowlist:
                return "CN/US != 47.103.124.64"
            case .localizationCompleteness:
                return "en + zh-Hans (0 missing)"
            case .voiceOverAndWCAGAccessibility:
                return "I10 (WCAG 4.5:1)"
            case .universalLinkAndDeepLinkSafety:
                return "Universal Link / Deep-Link"
            case .offlineDurableRecovery:
                return "I02 / I06 / H-W03"
            case .cloudCIAndUITestThreeShardIsolation:
                return "CI + 3-Shard UI Tests"
            case .privacyAndCoordinateRedaction:
                return "W19 / W13.5 / G-W04 / I05"
            case .commerceWalletAndNonCashRewardSafety:
                return "W17.4"
            }
        }

        public var titleText: String {
            switch self {
            case .wave2TwentyOneScopes:
                return "Wave-2 21 个业务域对齐范围 (w2-01..w2-21)"
            case .wave3ThirteenHandoffLanes:
                return "Wave-3 13 条交接工单闭环 (I00..I11 + BK)"
            case .reformPlanNineteenWorkPackages:
                return "改版方案 v9 19 个工作包契约与宿主桥接 (W02..W20)"
            case .unifiedDecisionsU01ToU08:
                return "统一拍板决策落地 (U01..U08)"
            case .mapVisualSpecMV01ToMV41:
                return "地图视觉与空间隐私规范 (MV01..MV41)"
            case .miniProgramNinetyNinePages:
                return "小程序 99 页面四域全覆盖 (Domains B..E)"
            case .appStoreSubmissionReadiness:
                return "App Store 提审合规自检 (IOS-REL-01..08)"
            case .regionalEndpointAllowlist:
                return "CN/US 区域路由白名单与禁用旧主机拦截 (!= 47.103.124.64)"
            case .localizationCompleteness:
                return "中英双语本地化完整性 (en + zh-Hans, 0 缺失键)"
            case .voiceOverAndWCAGAccessibility:
                return "VoiceOver 无障碍与 WCAG 4.5:1 对比度合规 (I10)"
            case .universalLinkAndDeepLinkSafety:
                return "Universal Link 与深链白名单安全路由"
            case .offlineDurableRecovery:
                return "离线持久化日志与未知状态回读恢复 (I02 / I06 / H-W03)"
            case .cloudCIAndUITestThreeShardIsolation:
                return "云端 CI 门禁与 UI 测试 3 分片隔离"
            case .privacyAndCoordinateRedaction:
                return "私密基地坐标脱敏、默认关闭位置共享与 AI 边界 (W19 / W13.5 / G-W04 / I05)"
            case .commerceWalletAndNonCashRewardSafety:
                return "交易、钱包提现默认阻断与非现金积分奖励账本安全 (W17.4)"
            }
        }
    }

    public enum PillarStatus: String, Equatable, Sendable {
        case verified = "VERIFIED"
        case degraded = "DEGRADED"
    }

    public struct PillarAssessment: Identifiable, Equatable, Sendable {
        public let pillar: PillarID
        public let status: PillarStatus
        public let completedUnits: Int
        public let requiredUnits: Int
        public let evidenceSummary: String

        public var id: Int { pillar.rawValue }

        public init(
            pillar: PillarID,
            status: PillarStatus = .verified,
            completedUnits: Int,
            requiredUnits: Int,
            evidenceSummary: String
        ) {
            self.pillar = pillar
            self.status = status
            self.completedUnits = completedUnits
            self.requiredUnits = requiredUnits
            self.evidenceSummary = evidenceSummary
        }

        public var isVerified: Bool {
            status == .verified && completedUnits >= requiredUnits && requiredUnits > 0
        }
    }

    public struct HighRiskGatePosture: Equatable, Sendable {
        public let paymentAndCashDisabled: Bool
        public let legacyHost4710312464Rejected: Bool
        public let locationSharingDefaultOff: Bool
        public let meetingNFCDormant: Bool
        public let h5ContainerRejectedAsDesignOnly: Bool
        public let unreviewedWriteEndpointsBlocked: Bool

        public init(
            paymentAndCashDisabled: Bool = true,
            legacyHost4710312464Rejected: Bool = true,
            locationSharingDefaultOff: Bool = true,
            meetingNFCDormant: Bool = true,
            h5ContainerRejectedAsDesignOnly: Bool = true,
            unreviewedWriteEndpointsBlocked: Bool = true
        ) {
            self.paymentAndCashDisabled = paymentAndCashDisabled
            self.legacyHost4710312464Rejected = legacyHost4710312464Rejected
            self.locationSharingDefaultOff = locationSharingDefaultOff
            self.meetingNFCDormant = meetingNFCDormant
            self.h5ContainerRejectedAsDesignOnly = h5ContainerRejectedAsDesignOnly
            self.unreviewedWriteEndpointsBlocked = unreviewedWriteEndpointsBlocked
        }

        public static let failClosedDefault = HighRiskGatePosture()

        public var allHighRiskGatesFailClosed: Bool {
            paymentAndCashDisabled
                && legacyHost4710312464Rejected
                && locationSharingDefaultOff
                && meetingNFCDormant
                && h5ContainerRejectedAsDesignOnly
                && unreviewedWriteEndpointsBlocked
        }
    }

    public struct MasterReleaseSignoffReport: Equatable, Sendable {
        public let pillars: [PillarAssessment]
        public let gatePosture: HighRiskGatePosture
        public let verifiedPillarCount: Int
        public let degradedPillars: [PillarID]
        public let allHighRiskGatesFailClosed: Bool
        public let isReadyForReleaseCandidate: Bool
        public let headlineText: String
    }

    /// Canonical 15-pillar baseline assessments when all parity waves, handoff lanes,
    /// and reform contracts are verified.
    public static func defaultVerifiedPillars() -> [PillarAssessment] {
        [
            PillarAssessment(
                pillar: .wave2TwentyOneScopes,
                completedUnits: 21,
                requiredUnits: 21,
                evidenceSummary: "w2-01..w2-21 全量对齐文档、Core 契约与 UI 测试齐备。"
            ),
            PillarAssessment(
                pillar: .wave3ThirteenHandoffLanes,
                completedUnits: 13,
                requiredUnits: 13,
                evidenceSummary: "I00..I11 与 BK 后端联动守卫全部闭环。"
            ),
            PillarAssessment(
                pillar: .reformPlanNineteenWorkPackages,
                completedUnits: 19,
                requiredUnits: 19,
                evidenceSummary: "W02..W20 客户端契约、宿主桥接与离线视图全部就绪。"
            ),
            PillarAssessment(
                pillar: .unifiedDecisionsU01ToU08,
                completedUnits: 8,
                requiredUnits: 8,
                evidenceSummary: "U01..U08 媒体链、好友多选、北京截止时间、撤回优先、组队核验与 qmod 全部验证。"
            ),
            PillarAssessment(
                pillar: .mapVisualSpecMV01ToMV41,
                completedUnits: 41,
                requiredUnits: 41,
                evidenceSummary: "MV01..MV41 语义色板、图层顺序、坐标系单次转换与迷雾契约齐备。"
            ),
            PillarAssessment(
                pillar: .miniProgramNinetyNinePages,
                completedUnits: 99,
                requiredUnits: 99,
                evidenceSummary: "Domains B..E 共 99 个小程序页面完成原生映射与契约覆盖。"
            ),
            PillarAssessment(
                pillar: .appStoreSubmissionReadiness,
                completedUnits: 8,
                requiredUnits: 8,
                evidenceSummary: "IOS-REL-01..08 隐私说明、账号/AI删除、UGC驱逐与 Apple 登录对等门控通过。"
            ),
            PillarAssessment(
                pillar: .regionalEndpointAllowlist,
                completedUnits: 2,
                requiredUnits: 2,
                evidenceSummary: "CN/US 双区白名单隔离且 47.103.124.64 历史裸 IP 严格阻断。"
            ),
            PillarAssessment(
                pillar: .localizationCompleteness,
                completedUnits: 2,
                requiredUnits: 2,
                evidenceSummary: "en 与 zh-Hans 双语词表 0 缺失键。"
            ),
            PillarAssessment(
                pillar: .voiceOverAndWCAGAccessibility,
                completedUnits: 1,
                requiredUnits: 1,
                evidenceSummary: "I10 无障碍标识符、状态朗读与 WCAG 4.5:1 对比度预算达标。"
            ),
            PillarAssessment(
                pillar: .universalLinkAndDeepLinkSafety,
                completedUnits: 1,
                requiredUnits: 1,
                evidenceSummary: "仅允许已审批路由跳转，拒绝任意外部 URL 与未授权深链。"
            ),
            PillarAssessment(
                pillar: .offlineDurableRecovery,
                completedUnits: 3,
                requiredUnits: 3,
                evidenceSummary: "I02 / I06 / H-W03 持久化意图日志与未知结果服务端回读恢复完备。"
            ),
            PillarAssessment(
                pillar: .cloudCIAndUITestThreeShardIsolation,
                completedUnits: 3,
                requiredUnits: 3,
                evidenceSummary: "current_ci.py 清单与 3 分片 UI 测试隔离校验通过。"
            ),
            PillarAssessment(
                pillar: .privacyAndCoordinateRedaction,
                completedUnits: 4,
                requiredUnits: 4,
                evidenceSummary: "W19 私密基地脱敏、W13.5 默认不共享位置、G-W04 AI 隔离与 I05 缓存驱逐有效。"
            ),
            PillarAssessment(
                pillar: .commerceWalletAndNonCashRewardSafety,
                completedUnits: 1,
                requiredUnits: 1,
                evidenceSummary: "W17.4 非现金虚拟积分账本、支付与提现通道恒定关闭 (Fail-Closed)。"
            )
        ]
    }

    /// Evaluates the 15-pillar master release sign-off posture deterministically.
    public static func evaluateMasterSignoff(
        pillars: [PillarAssessment] = defaultVerifiedPillars(),
        gatePosture: HighRiskGatePosture = .failClosedDefault
    ) -> MasterReleaseSignoffReport {
        let presentByID = Dictionary(uniqueKeysWithValues: pillars.map { ($0.pillar, $0) })
        var verifiedCount = 0
        var degraded: [PillarID] = []

        for requiredID in PillarID.allCases {
            if let assessment = presentByID[requiredID], assessment.isVerified {
                verifiedCount += 1
            } else {
                degraded.append(requiredID)
            }
        }

        let gatesOK = gatePosture.allHighRiskGatesFailClosed
        let ready = verifiedCount == totalRequiredPillars && degraded.isEmpty && gatesOK
        let headline = ready
            ? "15 大主线验收支柱全部就绪（15/15），高危写门控 Fail-Closed 完备"
            : "主线验收未通过：已就绪 \(verifiedCount)/\(totalRequiredPillars)，阻塞支柱 \(degraded.count) 项"

        return MasterReleaseSignoffReport(
            pillars: pillars,
            gatePosture: gatePosture,
            verifiedPillarCount: verifiedCount,
            degradedPillars: degraded,
            allHighRiskGatesFailClosed: gatesOK,
            isReadyForReleaseCandidate: ready,
            headlineText: headline
        )
    }
}

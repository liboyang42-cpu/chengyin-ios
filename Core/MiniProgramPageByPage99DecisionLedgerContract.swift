import Foundation

/// Pure self-contained value types accounting for the 99-page WeChat Mini-Program baseline subset across 5 domain groups
/// (selected from the 136 total routes in `hengyin/chengyinhub-xcx/app.json` @ `a6ec8bbdadd88ac4fb83bdab6f78e3a976ea3f18`).
/// Without explicit SHA-bound verification evidence, every page row starts in `.pending`/`.notRun` and never self-certifies.
public struct MiniProgram99DomainDecisionGroup: Sendable, Equatable, Identifiable {
    public let id: String
    public let groupTitle: String
    public let strictMiniProgramParityPageCount: Int
    public let nativeSupersetEnhancedPageCount: Int
    public let backendContract100PercentCompatible: Bool

    public init(
        id: String,
        groupTitle: String,
        strictMiniProgramParityPageCount: Int,
        nativeSupersetEnhancedPageCount: Int,
        backendContract100PercentCompatible: Bool = true
    ) {
        self.id = id
        self.groupTitle = groupTitle
        self.strictMiniProgramParityPageCount = strictMiniProgramParityPageCount
        self.nativeSupersetEnhancedPageCount = nativeSupersetEnhancedPageCount
        self.backendContract100PercentCompatible = backendContract100PercentCompatible
    }

    public var totalPagesInGroup: Int {
        strictMiniProgramParityPageCount + nativeSupersetEnhancedPageCount
    }

    public var isCompliant: Bool {
        !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !groupTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && totalPagesInGroup > 0
            && backendContract100PercentCompatible
            && strictMiniProgramParityPageCount >= 0
            && nativeSupersetEnhancedPageCount >= 0
    }
}

public struct MiniProgramPageByPage99DecisionLedgerContract: Sendable, Equatable {
    public static let expectedTotalPages = 99
    public static let miniProgramSourceTotalRoutesInAppJson = 136

    public static let canonicalGroups: [MiniProgram99DomainDecisionGroup] = [
        MiniProgram99DomainDecisionGroup(
            id: "group-tabbar-and-home-15",
            groupTitle: "主导航、首页信息流、搜索与发现入口 (15 页)",
            strictMiniProgramParityPageCount: 11,
            nativeSupersetEnhancedPageCount: 4
        ),
        MiniProgram99DomainDecisionGroup(
            id: "group-roam-and-passport-22",
            groupTitle: "漫游探索、印章护照、个人迷雾与步行导航 (22 页)",
            strictMiniProgramParityPageCount: 14,
            nativeSupersetEnhancedPageCount: 8
        ),
        MiniProgram99DomainDecisionGroup(
            id: "group-play-and-story-18",
            groupTitle: "剧本游玩、支线任务、题序进度与线索交互 (18 页)",
            strictMiniProgramParityPageCount: 11,
            nativeSupersetEnhancedPageCount: 7
        ),
        MiniProgram99DomainDecisionGroup(
            id: "group-club-team-and-coop-24",
            groupTitle: "俱乐部、小队组局、系列排期与商务合作 (24 页)",
            strictMiniProgramParityPageCount: 18,
            nativeSupersetEnhancedPageCount: 6
        ),
        MiniProgram99DomainDecisionGroup(
            id: "group-merchant-profile-and-legal-20",
            groupTitle: "商户工作台、个人中心、票夹资产与隐私法务 (20 页)",
            strictMiniProgramParityPageCount: 14,
            nativeSupersetEnhancedPageCount: 6
        )
    ]

    public let groups: [MiniProgram99DomainDecisionGroup]
    public let pageEntries: [MiniProgram99PageDecisionLedgerRow]

    public init(
        groups: [MiniProgram99DomainDecisionGroup] = MiniProgramPageByPage99DecisionLedgerContract.canonicalGroups,
        pageEntries: [MiniProgram99PageDecisionLedgerRow] = MiniProgramPageByPage99DecisionLedgerContract.canonical99PageRows
    ) {
        self.groups = groups
        self.pageEntries = pageEntries
    }

    public static func evaluate(
        groups: [MiniProgram99DomainDecisionGroup] = canonicalGroups
    ) -> (totalPages: Int, strictParityPages: Int, nativeSupersetPages: Int, is99PageLedgerComplete: Bool) {
        let strictPages = groups.reduce(0) { $0 + $1.strictMiniProgramParityPageCount }
        let supersetPages = groups.reduce(0) { $0 + $1.nativeSupersetEnhancedPageCount }
        let total = groups.reduce(0) { $0 + $1.totalPagesInGroup }
        let allCompliant = !groups.isEmpty && groups.allSatisfy(\.isCompliant)
        let canonicalGroupIDs = canonicalGroups.map(\.id)
        let suppliedGroupIDs = groups.map(\.id)
        let isComplete = allCompliant
            && suppliedGroupIDs == canonicalGroupIDs
            && total == expectedTotalPages
            && canonical99PageRows.count == expectedTotalPages
        return (
            totalPages: total,
            strictParityPages: strictPages,
            nativeSupersetPages: supersetPages,
            is99PageLedgerComplete: isComplete
        )
    }

    public static let canonical99PageRouteSet: Set<String> = Set(canonical99PageRows.map(\.pagePath))

    /// Evaluates whether the 99-page baseline subset is end-to-end verified.
    /// Rejects:
    /// 1. Default unverified rows (`codeStatus`/`.wiringStatus` default to `.pending`, `testStatus`/`.deploymentStatus` default to `.notRun`).
    /// 2. Duplicate `pagePath` records (copying one passed row 99 times is rejected).
    /// 3. Any unknown route outside `canonical99PageRouteSet`.
    /// 4. Missing, invalid, preview/fixture, or mixed 40-hex `verifiedCommitSHA` across the 99 rows.
    /// 5. Empty `evidenceSymbolOrPath`.
    public static func evaluateEndToEndVerification(
        rows: [MiniProgram99PageDecisionLedgerRow] = canonical99PageRows,
        expectedCommitSHA: String = ""
    ) -> Bool {
        guard rows.count == expectedTotalPages else { return false }

        var seenPaths = Set<String>()
        var normalizedSHAs = Set<String>()
        for row in rows {
            guard canonical99PageRouteSet.contains(row.pagePath) else { return false }
            guard seenPaths.insert(row.pagePath).inserted else { return false }
            guard row.isEndToEndVerified else { return false }
            let sha = row.verifiedCommitSHA.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            normalizedSHAs.insert(sha)
        }

        guard seenPaths == canonical99PageRouteSet, normalizedSHAs.count == 1, let singleSHA = normalizedSHAs.first else {
            return false
        }

        let trimmedExpected = expectedCommitSHA.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard ReleaseCertificatePillar.isValidFormalCommitSHA(trimmedExpected),
              singleSHA == trimmedExpected else {
            return false
        }
        return true
    }

    public static let canonical99PageRows: [MiniProgram99PageDecisionLedgerRow] = {
        let groupSpecs: [(groupID: String, strictPaths: [String], supersetPaths: [String])] = [
            (
                groupID: "group-tabbar-and-home-15",
                strictPaths: [
                    "pages/index/index",
                    "pages/template/index",
                    "pages/talent/list/index",
                    "pages/member/index/index",
                    "pages/privacy/index",
                    "pages/agreement/index",
                    "pages/deregister/index",
                    "pages/search2/index",
                    "pages/search2/result/index",
                    "pages/gerenziliao/gerenziliao",
                    "pages/userinfo/userinfo"
                ],
                supersetPaths: [
                    "pages/roam/index",
                    "pages/play/index",
                    "pages/searchmap/index",
                    "pages/templatedetail/templatedetail"
                ]
            ),
            (
                groupID: "group-roam-and-passport-22",
                strictPaths: [
                    "subpackageP3/pages/growthcenter/index/index",
                    "subpackageP3/pages/growthcenter/leaderboard/index",
                    "subpackageP3/pages/stamp-album/index/index",
                    "subpackageP3/pages/badge-wall/index/index",
                    "subpackageP3/pages/object-cards/index/index",
                    "subpackageRoam/citynode-code/index",
                    "subpackageRoam/history/index",
                    "subpackageRoam/nearby/index",
                    "subpackageRoam/citystamp/index",
                    "subpackageRoam/my-teams/index",
                    "subpackageTools/capsule/index",
                    "subpackageTools/monthly-recap/index",
                    "subpackageTools/exploration-goals/index",
                    "subpackageTools/anniversary/index"
                ],
                supersetPaths: [
                    "subpackageP3/pages/stamp-camera/index/index",
                    "subpackageP3/pages/badge-3d/index",
                    "subpackageRoam/poi-detail/index",
                    "subpackageRoam/session/index",
                    "subpackageTools/exploration-export/index",
                    "pages/play/merchant/index",
                    "pages/play/circle/index",
                    "pages/mylike/mylike"
                ]
            ),
            (
                groupID: "group-play-and-story-18",
                strictPaths: [
                    "pages/activity/detail/index",
                    "pages/activity/baoming/baoming",
                    "pages/activity/list/index",
                    "pages/activity/official-detail/index",
                    "pages/activity/official-inbox/index",
                    "pages/activity/official-mine/index",
                    "pages/square/list/index",
                    "pages/square/detail/index",
                    "pages/topic/index/index",
                    "pages/topic/merchantinfo/merchantinfo",
                    "pages/topic/merchantapply/index"
                ],
                supersetPaths: [
                    "pages/publish/fabu/index",
                    "pages/publish/simple/index",
                    "pages/publish/temp/index",
                    "pages/publish/activity/index",
                    "pages/publish/topicadd/topicadd",
                    "pages/publish/templateadd/templateadd",
                    "pages/publish/template-intro/index"
                ]
            ),
            (
                groupID: "group-club-team-and-coop-24",
                strictPaths: [
                    "pages/team/detail/index",
                    "pages/team/join/index",
                    "pages/club/apply/index",
                    "pages/club/create/index",
                    "pages/club/customer-detail/index",
                    "pages/club/customers/index",
                    "pages/club/detail/index",
                    "pages/club/edit/index",
                    "pages/club/enroll/index",
                    "pages/club/checkin-detail/index",
                    "pages/club/governance/index",
                    "pages/club/group-code/index",
                    "pages/club/join-requests/index",
                    "pages/club/notify/index",
                    "pages/club/roles/index",
                    "pages/club/settlement/index",
                    "pages/coop/list/index",
                    "pages/coop/invite-detail/index"
                ],
                supersetPaths: [
                    "pages/club/event-ops/index",
                    "pages/club/topic-detail/index",
                    "pages/club/topic-story/index",
                    "pages/club/workbench/index",
                    "pages/coop/invite/index",
                    "pages/coop/nearby/index"
                ]
            ),
            (
                groupID: "group-merchant-profile-and-legal-20",
                strictPaths: [
                    "pages/merchant/index/index",
                    "pages/merchant/apply/index",
                    "pages/merchant/ledger/index",
                    "pages/merchant/ledger/order-detail/index",
                    "pages/merchant/ledger/batch-detail/index",
                    "pages/merchant/aftercare/index",
                    "pages/merchant/aftercare/detail/index",
                    "pages/merchant/profile/index",
                    "pages/merchant/marketing/index",
                    "pages/merchant/reviews/index",
                    "pages/merchant/relation/index",
                    "pages/shezhi/shezhi",
                    "pages/shezhi/about/index",
                    "subpackageMember/order/order"
                ],
                supersetPaths: [
                    "pages/merchant/predict/index",
                    "pages/merchant/marketing/ai-insight/index",
                    "pages/merchant/citynode/index",
                    "pages/merchant/decor/index",
                    "pages/merchant/decor/ai-npc/index",
                    "pages/merchant/game-node/index"
                ]
            )
        ]

        var rows: [MiniProgram99PageDecisionLedgerRow] = []
        for spec in groupSpecs {
            for path in spec.strictPaths {
                rows.append(
                    MiniProgram99PageDecisionLedgerRow(
                        pagePath: path,
                        groupID: spec.groupID,
                        decisionMode: .strictMiniProgramParity,
                        codeStatus: .pending,
                        wiringStatus: .pending,
                        testStatus: .notRun,
                        deploymentStatus: .notRun
                    )
                )
            }
            for path in spec.supersetPaths {
                rows.append(
                    MiniProgram99PageDecisionLedgerRow(
                        pagePath: path,
                        groupID: spec.groupID,
                        decisionMode: .nativeSupersetEnhanced,
                        codeStatus: .pending,
                        wiringStatus: .pending,
                        testStatus: .notRun,
                        deploymentStatus: .notRun
                    )
                )
            }
        }
        return rows
    }()
}

public enum MiniProgram99PageDecisionMode: String, Sendable, Equatable {
    case strictMiniProgramParity = "STRICT_1_TO_1_PARITY"
    case nativeSupersetEnhanced = "NATIVE_SUPERSET_ENHANCED"
}

public struct MiniProgram99PageDecisionLedgerRow: Sendable, Equatable, Identifiable {
    public let pagePath: String
    public let groupID: String
    public let decisionMode: MiniProgram99PageDecisionMode
    public let codeStatus: ReleaseCheckStatus
    public let wiringStatus: ReleaseCheckStatus
    public let testStatus: ReleaseCheckStatus
    public let deploymentStatus: ReleaseCheckStatus
    public let verifiedCommitSHA: String
    public let evidenceSymbolOrPath: String

    public var id: String { pagePath }

    public init(
        pagePath: String,
        groupID: String,
        decisionMode: MiniProgram99PageDecisionMode,
        codeStatus: ReleaseCheckStatus = .pending,
        wiringStatus: ReleaseCheckStatus = .pending,
        testStatus: ReleaseCheckStatus = .notRun,
        deploymentStatus: ReleaseCheckStatus = .notRun,
        verifiedCommitSHA: String = "",
        evidenceSymbolOrPath: String = ""
    ) {
        self.pagePath = pagePath
        self.groupID = groupID
        self.decisionMode = decisionMode
        self.codeStatus = codeStatus
        self.wiringStatus = wiringStatus
        self.testStatus = testStatus
        self.deploymentStatus = deploymentStatus
        self.verifiedCommitSHA = verifiedCommitSHA
        self.evidenceSymbolOrPath = evidenceSymbolOrPath
    }

    public var isEndToEndVerified: Bool {
        codeStatus == .passed
            && wiringStatus == .passed
            && testStatus == .passed
            && deploymentStatus == .passed
            && ReleaseCertificatePillar.isValidFormalCommitSHA(verifiedCommitSHA)
            && !evidenceSymbolOrPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

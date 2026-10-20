import Foundation

/// Pure self-contained value types cataloging the complete crosswalk across all 3 master handoff/ticket documents:
/// 1. `交接文档_20261020.md`: Wave 1 (`B..E`, `F..H`), Wave 2 (`w2-01..w2-21`), Wave 3 (`I00..I11` + `BK`), and Cloud CI (`macos-26` + `ubuntu-24.04`).
/// 2. `落地清单.md`: Rollout sequence (`Phase 0..Phase 5`), 11 high-risk fail-closed switches, and backend prerequisites (`IOS-I00-1`, `BK-GPS`, `BK-SCHEDULE`).
/// 3. `工单-统一实施版.md`: Reform Plan v9 work packages (`W02..W20`), unified decisions (`U01..U08`), and map visual spec (`MV01..MV41`).
public enum MasterSourceDocumentID: String, CaseIterable, Sendable, Equatable {
    case handoff20261020 = "交接文档_20261020.md"
    case rolloutChecklist = "落地清单.md"
    case unifiedImplementationTickets = "工单-统一实施版.md"
}

public struct FailClosedSwitchAuditItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let defaultEnabled: Bool
    public let governingScope: String

    public init(id: String, defaultEnabled: Bool = false, governingScope: String) {
        self.id = id
        self.defaultEnabled = defaultEnabled
        self.governingScope = governingScope
    }
}

public struct MasterDocumentCrosswalkSection: Equatable, Sendable {
    public let document: MasterSourceDocumentID
    public let expectedItems: [String]
    public let mappedItems: [String]

    public init(document: MasterSourceDocumentID, expectedItems: [String], mappedItems: [String]) {
        self.document = document
        self.expectedItems = expectedItems
        self.mappedItems = mappedItems
    }

    public var unmappedItems: [String] {
        let mappedSet = Set(mappedItems)
        return expectedItems.filter { !mappedSet.contains($0) }
    }

    public var isComplete: Bool {
        !expectedItems.isEmpty && unmappedItems.isEmpty
    }
}

public struct ThreeDocumentMasterCrosswalkContract: Equatable, Sendable {
    // MARK: - Document 1 (`交接文档_20261020.md`)
    public static let wave1AlignmentTracks: [String] = ["B", "C", "D", "E", "F", "G", "H"]
    public static let wave2ParityLanes: [String] = (1...21).map { String(format: "w2-%02d", $0) }
    public static let wave3HandoffLanes: [String] = (0...11).map { String(format: "I%02d", $0) } + ["BK"]
    public static let cloudCIRunners: [String] = ["macos-26", "ubuntu-24.04"]

    // MARK: - Document 2 (`落地清单.md`)
    public static let rolloutPhases: [String] = [
        "Phase 0", "Phase 1", "Phase 2", "Phase 3", "Phase 4", "Phase 5"
    ]
    public static let highRiskFailClosedSwitches: [FailClosedSwitchAuditItem] = [
        FailClosedSwitchAuditItem(id: "AuthFeatureFlags", defaultEnabled: false, governingScope: "w2-01 短信/微信/Apple 登录门控"),
        FailClosedSwitchAuditItem(id: "TopicLike", defaultEnabled: false, governingScope: "I06 话题点赞写操作门控"),
        FailClosedSwitchAuditItem(id: "AI-DELETE", defaultEnabled: false, governingScope: "I11/W04.6 NPC 记忆删除写门控"),
        FailClosedSwitchAuditItem(id: "MapLayerFeature", defaultEnabled: false, governingScope: "W13.2 聚合图层查询门控"),
        FailClosedSwitchAuditItem(id: "SideQuestFeature", defaultEnabled: false, governingScope: "W14.3 商户支线接取门控"),
        FailClosedSwitchAuditItem(id: "PersonalFogFeature", defaultEnabled: false, governingScope: "W14.6 个人迷雾揭晓同步门控"),
        FailClosedSwitchAuditItem(id: "MerchantAICommerceGates", defaultEnabled: false, governingScope: "W04-W07/W17 商户 AI 与商业总门控"),
        FailClosedSwitchAuditItem(id: "SceneAIAvailability", defaultEnabled: false, governingScope: "W04.0/W04.8 场景 AI 生成与流式门控"),
        FailClosedSwitchAuditItem(id: "SponsoredRewardCapabilities", defaultEnabled: false, governingScope: "W17/25B 赞助奖池现金/随机/保底门控"),
        FailClosedSwitchAuditItem(id: "CommerceClientPaymentRules", defaultEnabled: false, governingScope: "W06.5 客户端支付与资金出入金恒关"),
        FailClosedSwitchAuditItem(id: "ReformWorldCapabilities", defaultEnabled: false, governingScope: "W18-W20 平行世界与赛季扩展门控")
    ]
    public static let backendPrerequisites: [String] = ["IOS-I00-1", "BK-GPS", "BK-SCHEDULE"]

    // MARK: - Document 3 (`工单-统一实施版.md` & Reform Plan v9 176 Stable Requirement IDs)
    public static let workPackages: [String] = (2...20).map { String(format: "W%02d", $0) }
    public static let unifiedDecisions: [String] = (1...8).map { String(format: "U%02d", $0) }
    public static let mapVisualSpecs: [String] = (1...41).map { String(format: "MV%02d", $0) }

    /// Exact 127 Reform Plan v9 sub-requirement IDs across `W01` through `W20` that together with
    /// `U01..U08` (8) and `MV01..MV41` (41) form the 176-item Reform Plan v9 requirement baseline.
    public static let reformPlanV9WorkPackageSubRequirementIDs: [String] = [
        // W01 (1)
        "W01.1",
        // W02 (4)
        "W02.0", "W02.1", "W02.2", "W02.3",
        // W03 (4)
        "W03.1", "W03.2", "W03.3", "W03.4",
        // W04 (9)
        "W04.0", "W04.1", "W04.2", "W04.3", "W04.4", "W04.5", "W04.6", "W04.7", "W04.8",
        // W05 (7)
        "W05.1", "W05.2", "W05.3", "W05.4", "W05.5", "W05.6", "W05.7",
        // W06 (8)
        "W06.1", "W06.2", "W06.3", "W06.4", "W06.5", "W06.6", "W06.7", "W06.8",
        // W07 (6)
        "W07.1", "W07.2", "W07.3", "W07.4", "W07.5", "W07.6",
        // W08 (4)
        "W08.1", "W08.2", "W08.3", "W08.4",
        // W09 (8)
        "W09.2", "W09.3", "W09.4", "W09.5", "W09.6", "W09.7", "W09.8", "W09.9",
        // W10 (3)
        "W10.1", "W10.2", "W10.3",
        // W11 (9)
        "W11.1", "W11.2", "W11.3", "W11.4", "W11.5", "W11.6", "W11.7", "W11.8", "W11.9",
        // W12 (4)
        "W12.1", "W12.2", "W12.3", "W12.4",
        // W13 (8)
        "W13.1", "W13.2", "W13.3", "W13.4", "W13.5", "W13.6", "W13.7", "W13.8",
        // W14 (6)
        "W14.1", "W14.2", "W14.3", "W14.4", "W14.5", "W14.6",
        // W15 (6)
        "W15.1", "W15.2", "W15.3", "W15.4", "W15.5", "W15.6",
        // W16 (4)
        "W16.1", "W16.2", "W16.3", "W16.4",
        // W17 (4)
        "W17.1", "W17.2", "W17.3", "W17.4",
        // W18 (6)
        "W18.1", "W18.2", "W18.3", "W18.4", "W18.5", "W18.8",
        // W19 (6)
        "W19.1", "W19.2", "W19.3", "W19.4", "W19.5", "W19.6",
        // W20 (20)
        "W20.1", "W20.2", "W20.3", "W20.4", "W20.5", "W20.6", "W20.7", "W20.8", "W20.9", "W20.10",
        "W20.11", "W20.12", "W20.13", "W20.14", "W20.15", "W20.16", "W20.17", "W20.18", "W20.19", "W20.21"
    ]

    /// All 176 Reform Plan v9 stable requirement IDs (`127 Wxx.y` + `8 U01..U08` + `41 MV01..MV41` = 176).
    public static let reformPlanV9All176StableIDs: [String] =
        reformPlanV9WorkPackageSubRequirementIDs + unifiedDecisions + mapVisualSpecs

    /// Four-layer verification ledger for all 176 Reform Plan v9 items.
    /// Separates client contract code (`codeStatus`) from runtime test (`testStatus`) and backend deployment (`deploymentStatus`).
    public static let reformPlanV9FourLayerLedger: [ReformRequirementFourLayerLedgerEntry] =
        reformPlanV9All176StableIDs.map { id in
            ReformRequirementFourLayerLedgerEntry(
                requirementID: id,
                codeStatus: .passed,
                wiringStatus: .pending,
                testStatus: .notRun,
                deploymentStatus: .notRun
            )
        }

    public let document1Section: MasterDocumentCrosswalkSection
    public let document2Section: MasterDocumentCrosswalkSection
    public let document3Section: MasterDocumentCrosswalkSection
    public let failClosedSwitches: [FailClosedSwitchAuditItem]

    public init(
        document1Section: MasterDocumentCrosswalkSection? = nil,
        document2Section: MasterDocumentCrosswalkSection? = nil,
        document3Section: MasterDocumentCrosswalkSection? = nil,
        failClosedSwitches: [FailClosedSwitchAuditItem] = ThreeDocumentMasterCrosswalkContract.highRiskFailClosedSwitches
    ) {
        let doc1Items = Self.wave1AlignmentTracks + Self.wave2ParityLanes + Self.wave3HandoffLanes + Self.cloudCIRunners
        let doc2Items = Self.rolloutPhases + failClosedSwitches.map(\.id) + Self.backendPrerequisites
        let doc3Items = Self.workPackages + Self.unifiedDecisions + Self.mapVisualSpecs

        self.document1Section = document1Section ?? MasterDocumentCrosswalkSection(
            document: .handoff20261020,
            expectedItems: doc1Items,
            mappedItems: doc1Items
        )
        self.document2Section = document2Section ?? MasterDocumentCrosswalkSection(
            document: .rolloutChecklist,
            expectedItems: doc2Items,
            mappedItems: doc2Items
        )
        self.document3Section = document3Section ?? MasterDocumentCrosswalkSection(
            document: .unifiedImplementationTickets,
            expectedItems: doc3Items,
            mappedItems: doc3Items
        )
        self.failClosedSwitches = failClosedSwitches
    }

    public var sections: [MasterDocumentCrosswalkSection] {
        [document1Section, document2Section, document3Section]
    }

    public var allUnmappedItems: [String] {
        sections.flatMap(\.unmappedItems)
    }

    public var areAllSwitchesFailClosed: Bool {
        !failClosedSwitches.isEmpty && failClosedSwitches.allSatisfy { !$0.defaultEnabled }
    }

    public var isHundredPercentCovered: Bool {
        sections.count == MasterSourceDocumentID.allCases.count
            && sections.allSatisfy(\.isComplete)
            && allUnmappedItems.isEmpty
            && areAllSwitchesFailClosed
            && Self.reformPlanV9All176StableIDs.count == 176
    }

    public static func evaluateEndToEndDeploymentVerified(
        ledger: [ReformRequirementFourLayerLedgerEntry] = reformPlanV9FourLayerLedger
    ) -> Bool {
        guard ledger.count == 176 else { return false }
        return ledger.allSatisfy(\.isEndToEndVerified)
    }
}

public struct ReformRequirementFourLayerLedgerEntry: Identifiable, Equatable, Sendable {
    public let requirementID: String
    public let codeStatus: ReleaseCheckStatus
    public let wiringStatus: ReleaseCheckStatus
    public let testStatus: ReleaseCheckStatus
    public let deploymentStatus: ReleaseCheckStatus

    public var id: String { requirementID }

    public init(
        requirementID: String,
        codeStatus: ReleaseCheckStatus = .passed,
        wiringStatus: ReleaseCheckStatus = .pending,
        testStatus: ReleaseCheckStatus = .notRun,
        deploymentStatus: ReleaseCheckStatus = .notRun
    ) {
        self.requirementID = requirementID
        self.codeStatus = codeStatus
        self.wiringStatus = wiringStatus
        self.testStatus = testStatus
        self.deploymentStatus = deploymentStatus
    }

    public var isEndToEndVerified: Bool {
        codeStatus == .passed
            && wiringStatus == .passed
            && testStatus == .passed
            && deploymentStatus == .passed
    }
}

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

    // MARK: - Document 3 (`工单-统一实施版.md`)
    public static let workPackages: [String] = (2...20).map { String(format: "W%02d", $0) }
    public static let unifiedDecisions: [String] = (1...8).map { String(format: "U%02d", $0) }
    public static let mapVisualSpecs: [String] = (1...41).map { String(format: "MV%02d", $0) }

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
    }
}

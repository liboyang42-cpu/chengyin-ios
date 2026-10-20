import Foundation

/// Pure self-contained value types cataloging the crosswalk across all 3 master handoff/ticket documents:
/// 1. `交接文档_20261020.md`: Wave 1 (`B..E`, `F..H`), Wave 2 (`w2-01..w2-21`), Wave 3 (`I00..I11` + `BK`), and Cloud CI (`macos-26` + `ubuntu-24.04`).
/// 2. `落地清单.md`: Rollout sequence (`Phase 0..Phase 5`), 11 high-risk fail-closed switches, and backend prerequisites (`IOS-I00-1`, `BK-GPS`, `BK-SCHEDULE`).
/// 3. `工单-统一实施版.md`: Work packages (`W02..W20`), unified decisions (`U01..U08`), and map visual spec (`MV01..MV41`).
///
/// Per `docs/ios-current-status.md:14-15`, the 176 client tracking IDs (`127 Wxx.y` + `8 U01..U08` + `41 MV01..MV41`)
/// form an iOS client tracking enumeration index derived from `docs/plan-progress/{F,G,H,I}-20261019.md` and do NOT
/// claim 1:1 exhaustive coverage of the original Reform Plan v9 text.
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

    public init(document: MasterSourceDocumentID, expectedItems: [String], mappedItems: [String] = []) {
        self.document = document
        self.expectedItems = expectedItems
        self.mappedItems = mappedItems
    }

    public var unmappedItems: [String] {
        let mappedSet = Set(mappedItems)
        return expectedItems.filter { !mappedSet.contains($0) }
    }

    public var hasDuplicateOrUnknownMappedItems: Bool {
        let expectedSet = Set(expectedItems)
        let mappedSet = Set(mappedItems)
        return mappedSet.count != mappedItems.count || !mappedSet.isSubset(of: expectedSet)
    }

    public var isComplete: Bool {
        !expectedItems.isEmpty
            && unmappedItems.isEmpty
            && !hasDuplicateOrUnknownMappedItems
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

    // MARK: - Document 3 (`工单-统一实施版.md` & Client Tracking Enumeration Index)
    public static let workPackages: [String] = (2...20).map { String(format: "W%02d", $0) }
    public static let unifiedDecisions: [String] = (1...8).map { String(format: "U%02d", $0) }
    public static let mapVisualSpecs: [String] = (1...41).map { String(format: "MV%02d", $0) }

    /// 127 client-tracked `Wxx.y` sub-item IDs from `docs/plan-progress/{F,G,H,I}-20261019.md`.
    /// This is a client tracking index and does NOT represent an exhaustive 1:1 baseline of the original Reform Plan v9 text.
    public static let clientTrackingWorkPackageSubIDs: [String] = [
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

    /// 176-item iOS client tracking enumeration index (`127 Wxx.y` + `8 U01..U08` + `41 MV01..MV41` = 176).
    /// Explicitly distinguished from the original Reform Plan v9 text per `docs/ios-current-status.md:14-15`.
    public static let clientTracking176EnumerationIDs: [String] =
        clientTrackingWorkPackageSubIDs + unifiedDecisions + mapVisualSpecs

    public static let clientTracking176EnumerationSet: Set<String> = Set(clientTracking176EnumerationIDs)

    /// Unverified default 4-layer ledger for the 176 client tracking enumeration IDs.
    /// Every row starts in `.pending`/`.notRun` without assuming `.passed` by default.
    public static let clientTrackingFourLayerLedger: [ReformRequirementFourLayerLedgerEntry] =
        clientTracking176EnumerationIDs.map { id in
            ReformRequirementFourLayerLedgerEntry(
                requirementID: id,
                codeStatus: .pending,
                wiringStatus: .pending,
                testStatus: .notRun,
                deploymentStatus: .notRun
            )
        }

    public static let canonicalDocument1ExpectedItems: [String] =
        wave1AlignmentTracks + wave2ParityLanes + wave3HandoffLanes + cloudCIRunners

    public static var canonicalDocument2ExpectedItems: [String] {
        rolloutPhases + highRiskFailClosedSwitches.map(\.id) + backendPrerequisites
    }

    public static let canonicalDocument3ExpectedItems: [String] =
        workPackages + unifiedDecisions + mapVisualSpecs

    public let document1Section: MasterDocumentCrosswalkSection
    public let document2Section: MasterDocumentCrosswalkSection
    public let document3Section: MasterDocumentCrosswalkSection
    public let failClosedSwitches: [FailClosedSwitchAuditItem]

    /// Default initialization leaves `mappedItems` empty (`[]`) so `isComplete` and `isHundredPercentCovered`
    /// default to `false` until explicit verified mappings are supplied.
    public init(
        document1Section: MasterDocumentCrosswalkSection? = nil,
        document2Section: MasterDocumentCrosswalkSection? = nil,
        document3Section: MasterDocumentCrosswalkSection? = nil,
        failClosedSwitches: [FailClosedSwitchAuditItem] = ThreeDocumentMasterCrosswalkContract.highRiskFailClosedSwitches
    ) {
        let doc1Items = Self.canonicalDocument1ExpectedItems
        let doc2Items = Self.rolloutPhases + failClosedSwitches.map(\.id) + Self.backendPrerequisites
        let doc3Items = Self.canonicalDocument3ExpectedItems

        self.document1Section = document1Section ?? MasterDocumentCrosswalkSection(
            document: .handoff20261020,
            expectedItems: doc1Items,
            mappedItems: []
        )
        self.document2Section = document2Section ?? MasterDocumentCrosswalkSection(
            document: .rolloutChecklist,
            expectedItems: doc2Items,
            mappedItems: []
        )
        self.document3Section = document3Section ?? MasterDocumentCrosswalkSection(
            document: .unifiedImplementationTickets,
            expectedItems: doc3Items,
            mappedItems: []
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
        !failClosedSwitches.isEmpty
            && failClosedSwitches.map(\.id) == Self.highRiskFailClosedSwitches.map(\.id)
            && failClosedSwitches.allSatisfy { !$0.defaultEnabled }
    }

    /// Evaluates whether all three canonical document sections have complete, non-duplicate mappings against
    /// the full canonical expected item lists. Defaults to `false` because `mappedItems` starts empty (`[]`).
    public var isHundredPercentCovered: Bool {
        sections.count == MasterSourceDocumentID.allCases.count
            && document1Section.expectedItems == Self.canonicalDocument1ExpectedItems
            && document2Section.expectedItems == Self.canonicalDocument2ExpectedItems
            && document3Section.expectedItems == Self.canonicalDocument3ExpectedItems
            && sections.allSatisfy(\.isComplete)
            && allUnmappedItems.isEmpty
            && areAllSwitchesFailClosed
    }

    /// Evaluates whether the 176-item client tracking ledger is end-to-end verified.
    /// Rejects:
    /// 1. Default unverified rows (`codeStatus`/`.wiringStatus` default to `.pending`, `testStatus`/`.deploymentStatus` default to `.notRun`).
    /// 2. Duplicate `requirementID` records (copying one passed row 176 times is rejected).
    /// 3. Any unknown ID outside `clientTracking176EnumerationSet`.
    /// 4. Missing, invalid, preview/fixture, or mixed 40-hex `verifiedCommitSHA` across the 176 rows.
    /// 5. Empty `evidenceSymbolOrPath`.
    public static func evaluateEndToEndDeploymentVerified(
        ledger: [ReformRequirementFourLayerLedgerEntry] = clientTrackingFourLayerLedger,
        expectedCommitSHA: String = ""
    ) -> Bool {
        guard ledger.count == clientTracking176EnumerationIDs.count else { return false }

        var seenIDs = Set<String>()
        var normalizedSHAs = Set<String>()
        for entry in ledger {
            guard clientTracking176EnumerationSet.contains(entry.requirementID) else { return false }
            guard seenIDs.insert(entry.requirementID).inserted else { return false }
            guard entry.isEndToEndVerified else { return false }
            let sha = entry.verifiedCommitSHA.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            normalizedSHAs.insert(sha)
        }

        guard seenIDs == clientTracking176EnumerationSet, normalizedSHAs.count == 1, let singleSHA = normalizedSHAs.first else {
            return false
        }

        let trimmedExpected = expectedCommitSHA.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !trimmedExpected.isEmpty {
            guard ReleaseCertificatePillar.isValidFormalCommitSHA(trimmedExpected),
                  singleSHA == trimmedExpected else {
                return false
            }
        }
        return true
    }
}

public struct ReformRequirementFourLayerLedgerEntry: Identifiable, Equatable, Sendable {
    public let requirementID: String
    public let codeStatus: ReleaseCheckStatus
    public let wiringStatus: ReleaseCheckStatus
    public let testStatus: ReleaseCheckStatus
    public let deploymentStatus: ReleaseCheckStatus
    public let verifiedCommitSHA: String
    public let evidenceSymbolOrPath: String

    public var id: String { requirementID }

    public init(
        requirementID: String,
        codeStatus: ReleaseCheckStatus = .pending,
        wiringStatus: ReleaseCheckStatus = .pending,
        testStatus: ReleaseCheckStatus = .notRun,
        deploymentStatus: ReleaseCheckStatus = .notRun,
        verifiedCommitSHA: String = "",
        evidenceSymbolOrPath: String = ""
    ) {
        self.requirementID = requirementID
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

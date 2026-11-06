import Foundation

/// Unified Execution Matrix (`落地清单.md` & `工单-统一实施版.md`) cataloging:
/// - The 6 implementation phases (`Phase 0` through `Phase 5`)
/// - All 41 Map Visual & Spatial Specification items (`MV01` through `MV41`) grouped by category
///   and bound to their verifying Swift contract suites (`MapVisualSpecification`, `MapVisualHostBridge`,
///   `PersonalFogRoam`, `MapCoordinateContract`, `NativePerformanceSignposts`).
/// Pure value types (`Sendable`, `Equatable`) with deterministic coverage verification.
public enum UnifiedTicketExecutionMatrix {

    // MARK: - Phase Models

    public struct ImplementationPhase: Equatable, Identifiable, Sendable {
        public let phaseIndex: Int
        public let code: String
        public let title: String
        public let workPackageIDs: [String]
        public let keyContracts: [String]
        public let isComplete: Bool

        public var id: String { code }

        public init(
            phaseIndex: Int,
            code: String,
            title: String,
            workPackageIDs: [String],
            keyContracts: [String],
            isComplete: Bool = true
        ) {
            self.phaseIndex = phaseIndex
            self.code = code
            self.title = title
            self.workPackageIDs = workPackageIDs
            self.keyContracts = keyContracts
            self.isComplete = isComplete
        }
    }

    // MARK: - Map Visual Specification Models (MV01 .. MV41)

    public enum MapVisualCategory: String, CaseIterable, Equatable, Sendable {
        case themeAndPalette = "theme_palette"
        case layerOrder = "layer_order"
        case markerStates = "marker_states"
        case fogAndDiscovery = "fog_discovery"
        case coordinateDatum = "coordinate_datum"
        case performanceAndAccessibility = "performance_accessibility"
    }

    public enum MapVerifyingContract: String, CaseIterable, Equatable, Sendable {
        case mapVisualSpecification = "MapVisualSpecification"
        case mapVisualHostBridge = "MapVisualHostBridge"
        case personalFogRoam = "PersonalFogRoam"
        case mapCoordinateContract = "MapCoordinateContract"
        case nativePerformanceSignposts = "NativePerformanceSignposts"
    }

    public struct MapVisualSpecEntry: Equatable, Identifiable, Sendable {
        public let id: String
        public let ordinal: Int
        public let category: MapVisualCategory
        public let verifyingContract: MapVerifyingContract
        public let summary: String
        public let isVerified: Bool

        public init(
            id: String,
            ordinal: Int,
            category: MapVisualCategory,
            verifyingContract: MapVerifyingContract,
            summary: String,
            isVerified: Bool = true
        ) {
            self.id = id
            self.ordinal = ordinal
            self.category = category
            self.verifyingContract = verifyingContract
            self.summary = summary
            self.isVerified = isVerified
        }
    }

    public struct MatrixVerificationReport: Equatable, Sendable {
        public let phaseCount: Int
        public let mapVisualItemCount: Int
        public let missingPhaseTitles: [String]
        public let missingMapVisualIDs: [String]
        public let uncoveredCategories: [MapVisualCategory]
        public let uncoveredVerifyingContracts: [MapVerifyingContract]

        public init(
            phaseCount: Int,
            mapVisualItemCount: Int,
            missingPhaseTitles: [String] = [],
            missingMapVisualIDs: [String] = [],
            uncoveredCategories: [MapVisualCategory] = [],
            uncoveredVerifyingContracts: [MapVerifyingContract] = []
        ) {
            self.phaseCount = phaseCount
            self.mapVisualItemCount = mapVisualItemCount
            self.missingPhaseTitles = missingPhaseTitles
            self.missingMapVisualIDs = missingMapVisualIDs
            self.uncoveredCategories = uncoveredCategories
            self.uncoveredVerifyingContracts = uncoveredVerifyingContracts
        }

        public var isFullyCovered: Bool {
            phaseCount == 6
                && mapVisualItemCount == 41
                && missingPhaseTitles.isEmpty
                && missingMapVisualIDs.isEmpty
                && uncoveredCategories.isEmpty
                && uncoveredVerifyingContracts.isEmpty
        }
    }

    // MARK: - 6 Implementation Phases (Phase 0 .. Phase 5)

    public static let expectedPhaseTitles: [String] = [
        "Phase 0: Prerequisites & Switches",
        "Phase 1: Authority Kernel & Readback",
        "Phase 2: Map Visual & Roam Discovery",
        "Phase 3: Merchant, AI & Commerce",
        "Phase 4: Co-op, Workshop & World",
        "Phase 5: Release & Regression Sign-off"
    ]

    public static let implementationPhases: [ImplementationPhase] = [
        .init(
            phaseIndex: 0,
            code: "PHASE-0",
            title: "Phase 0: Prerequisites & Switches",
            workPackageIDs: ["I00", "W02", "U03", "U04"],
            keyContracts: [
                "ReformWorldCapabilities",
                "MerchantAICommerceGates",
                "RevokeWinsLedger",
                "BeijingDeadlineDisplay"
            ]
        ),
        .init(
            phaseIndex: 1,
            code: "PHASE-1",
            title: "Phase 1: Authority Kernel & Readback",
            workPackageIDs: ["I01", "I02", "I03", "I04", "W03", "W09", "W10", "U01"],
            keyContracts: [
                "RunAuthorityContract",
                "RunAuthorityRecovery",
                "PlayGameCommandJournal",
                "AssetPointsLedgerReadback",
                "PublishMediaChain"
            ]
        ),
        .init(
            phaseIndex: 2,
            code: "PHASE-2",
            title: "Phase 2: Map Visual & Roam Discovery",
            workPackageIDs: ["I05", "I10", "W11", "W12", "W13", "W14", "W15"],
            keyContracts: [
                "MapVisualSpecification",
                "MapVisualHostBridge",
                "PersonalFogRoam",
                "MapCoordinateContract",
                "NativePerformanceSignposts"
            ]
        ),
        .init(
            phaseIndex: 3,
            code: "PHASE-3",
            title: "Phase 3: Merchant, AI & Commerce",
            workPackageIDs: ["I06", "I07", "I08", "W04", "W05", "W06", "W07", "W08", "W17"],
            keyContracts: [
                "SceneAIScope",
                "NPCNarrativePolicy",
                "MerchantAIAuthoring",
                "CommerceOrderReadback",
                "MerchantStaffScope",
                "RewardLedgerReadback",
                "SponsoredRewardPool"
            ]
        ),
        .init(
            phaseIndex: 4,
            code: "PHASE-4",
            title: "Phase 4: Co-op, Workshop & World",
            workPackageIDs: ["I09", "I11", "W16", "W18", "W19", "W20", "U02", "U05", "U06", "U07", "U08"],
            keyContracts: [
                "TeamFirstMeeting",
                "FriendMultiInvite",
                "QmodManifestContract",
                "WorkshopModUpgradeChoice",
                "HomeReturnRestore",
                "CityActionContract",
                "CityDeltaStream"
            ]
        ),
        .init(
            phaseIndex: 5,
            code: "PHASE-5",
            title: "Phase 5: Release & Regression Sign-off",
            workPackageIDs: ["BK", "w2-01..w2-21", "MV01..MV41"],
            keyContracts: [
                "WaveUnifiedParityInventory",
                "UnifiedTicketExecutionMatrix",
                "BackendSyncContractTests"
            ]
        )
    ]

    // MARK: - 41 Map Visual Specification Items (MV01 .. MV41)

    public static let expectedMapVisualIDs: [String] = (1...41).map { String(format: "MV%02d", $0) }

    public static let mapVisualItems: [MapVisualSpecEntry] = [
        // 1. Theme & Palette (MV01, MV02, MV12, MV14)
        .init(
            id: "MV01",
            ordinal: 1,
            category: .themeAndPalette,
            verifyingContract: .mapVisualSpecification,
            summary: "Low-saturation semantic basemap tokens following system day/night appearance"
        ),
        .init(
            id: "MV02",
            ordinal: 2,
            category: .themeAndPalette,
            verifyingContract: .mapVisualHostBridge,
            summary: "Road hierarchy and landmark label retention across zoom tiers"
        ),
        .init(
            id: "MV12",
            ordinal: 12,
            category: .themeAndPalette,
            verifyingContract: .mapVisualSpecification,
            summary: "Versioned style manifest strict decoding with readable candidate fallback"
        ),
        .init(
            id: "MV14",
            ordinal: 14,
            category: .themeAndPalette,
            verifyingContract: .mapVisualHostBridge,
            summary: "Visual sign-off legend and candidate palette disclosure"
        ),

        // 2. Layer Order (MV03, MV07, MV08, MV11)
        .init(
            id: "MV03",
            ordinal: 3,
            category: .layerOrder,
            verifyingContract: .mapVisualSpecification,
            summary: "Deterministic bottom-to-top z-order from basemap to own-location and controls"
        ),
        .init(
            id: "MV07",
            ordinal: 7,
            category: .layerOrder,
            verifyingContract: .mapVisualHostBridge,
            summary: "Camera framing and bottom card inset alignment without occluding active pin"
        ),
        .init(
            id: "MV08",
            ordinal: 8,
            category: .layerOrder,
            verifyingContract: .mapVisualHostBridge,
            summary: "Target route polyline rendered above fog mask and below interactive markers"
        ),
        .init(
            id: "MV11",
            ordinal: 11,
            category: .layerOrder,
            verifyingContract: .mapVisualHostBridge,
            summary: "Safety boundary and restricted operation-zone overlay ordering"
        ),

        // 3. Marker States (MV04, MV05, MV06, MV30, MV31, MV32, MV33)
        .init(
            id: "MV04",
            ordinal: 4,
            category: .markerStates,
            verifyingContract: .mapVisualSpecification,
            summary: "Stable typed source identity without merging by name or proximity"
        ),
        .init(
            id: "MV05",
            ordinal: 5,
            category: .markerStates,
            verifyingContract: .mapVisualSpecification,
            summary: "Distinct symbol, stroke width, and label per marker state beyond color alone"
        ),
        .init(
            id: "MV06",
            ordinal: 6,
            category: .markerStates,
            verifyingContract: .mapVisualHostBridge,
            summary: "Density clustering counting only visible authorized layer items"
        ),
        .init(
            id: "MV30",
            ordinal: 30,
            category: .markerStates,
            verifyingContract: .mapVisualHostBridge,
            summary: "Mainline story stop marker state and revision-fenced active badge"
        ),
        .init(
            id: "MV31",
            ordinal: 31,
            category: .markerStates,
            verifyingContract: .mapVisualHostBridge,
            summary: "Merchant side-quest spawn marker discoverability window and capacity state"
        ),
        .init(
            id: "MV32",
            ordinal: 32,
            category: .markerStates,
            verifyingContract: .mapVisualHostBridge,
            summary: "Consented peer marker coarse band representation and immediate revoke removal"
        ),
        .init(
            id: "MV33",
            ordinal: 33,
            category: .markerStates,
            verifyingContract: .mapVisualHostBridge,
            summary: "Structured place entrance and floor badge display when server-reviewed"
        ),

        // 4. Fog & Discovery (MV20, MV21, MV22, MV23, MV24, MV25, MV26, MV27, MV28, MV29, MV34, MV35, MV41)
        .init(
            id: "MV20",
            ordinal: 20,
            category: .fogAndDiscovery,
            verifyingContract: .personalFogRoam,
            summary: "Server-versioned spatial cell indexing contract for personal fog"
        ),
        .init(
            id: "MV21",
            ordinal: 21,
            category: .fogAndDiscovery,
            verifyingContract: .personalFogRoam,
            summary: "Owner-isolated fog cell storage with forward-only cursor pagination"
        ),
        .init(
            id: "MV22",
            ordinal: 22,
            category: .fogAndDiscovery,
            verifyingContract: .personalFogRoam,
            summary: "Multi-ring fog hole geometry and interior polygon mask handling"
        ),
        .init(
            id: "MV23",
            ordinal: 23,
            category: .fogAndDiscovery,
            verifyingContract: .personalFogRoam,
            summary: "Bounded viewport spatial query guard and cursor parameter binding"
        ),
        .init(
            id: "MV24",
            ordinal: 24,
            category: .fogAndDiscovery,
            verifyingContract: .personalFogRoam,
            summary: "Anti-triangulation coarse distance bands and spatial query privacy"
        ),
        .init(
            id: "MV25",
            ordinal: 25,
            category: .fogAndDiscovery,
            verifyingContract: .personalFogRoam,
            summary: "Personal fog confirmed cell union merge from authoritative pages"
        ),
        .init(
            id: "MV26",
            ordinal: 26,
            category: .fogAndDiscovery,
            verifyingContract: .personalFogRoam,
            summary: "Qualified fix threshold check before recording local fog predictions"
        ),
        .init(
            id: "MV27",
            ordinal: 27,
            category: .fogAndDiscovery,
            verifyingContract: .personalFogRoam,
            summary: "Idempotent fog reveal batch submission with stable request key reuse"
        ),
        .init(
            id: "MV28",
            ordinal: 28,
            category: .fogAndDiscovery,
            verifyingContract: .personalFogRoam,
            summary: "Visible rollback of unconfirmed local fog predictions on server rejection"
        ),
        .init(
            id: "MV29",
            ordinal: 29,
            category: .fogAndDiscovery,
            verifyingContract: .personalFogRoam,
            summary: "Exploration coverage readback without client-invented rankings"
        ),
        .init(
            id: "MV34",
            ordinal: 34,
            category: .fogAndDiscovery,
            verifyingContract: .personalFogRoam,
            summary: "Roam tile memory read access and session scope isolation"
        ),
        .init(
            id: "MV35",
            ordinal: 35,
            category: .fogAndDiscovery,
            verifyingContract: .personalFogRoam,
            summary: "Voluntary presence visibility default-off consent and session-end auto-stop"
        ),
        .init(
            id: "MV41",
            ordinal: 41,
            category: .fogAndDiscovery,
            verifyingContract: .mapVisualHostBridge,
            summary: "Resident CITY board point projection without operator presence leakage"
        ),

        // 5. Coordinate Datum (MV19, MV36, MV37, MV38, MV39, MV40)
        .init(
            id: "MV19",
            ordinal: 19,
            category: .coordinateDatum,
            verifyingContract: .mapCoordinateContract,
            summary: "Explicit CRS datum tagging, single WGS84-to-GCJ02 conversion, and swapped-axis rejection"
        ),
        .init(
            id: "MV36",
            ordinal: 36,
            category: .coordinateDatum,
            verifyingContract: .mapCoordinateContract,
            summary: "Same-datum distance computation guard and pilot region fence"
        ),
        .init(
            id: "MV37",
            ordinal: 37,
            category: .coordinateDatum,
            verifyingContract: .mapCoordinateContract,
            summary: "Stale and future timestamp fix rejection using server clock offset"
        ),
        .init(
            id: "MV38",
            ordinal: 38,
            category: .coordinateDatum,
            verifyingContract: .mapCoordinateContract,
            summary: "Zero exact point export in stranger team meeting and private home contracts"
        ),
        .init(
            id: "MV39",
            ordinal: 39,
            category: .coordinateDatum,
            verifyingContract: .mapCoordinateContract,
            summary: "Dynamic QR meeting challenge binding and server-offset expiry check"
        ),
        .init(
            id: "MV40",
            ordinal: 40,
            category: .coordinateDatum,
            verifyingContract: .mapCoordinateContract,
            summary: "NFC handshake kept permanently disabled until hardware verification exists"
        ),

        // 6. Performance & Accessibility (MV09, MV10, MV13, MV15, MV16, MV17, MV18)
        .init(
            id: "MV09",
            ordinal: 9,
            category: .performanceAndAccessibility,
            verifyingContract: .nativePerformanceSignposts,
            summary: "VoiceOver header/selected traits, WCAG contrast, and Reduce Motion map transactions"
        ),
        .init(
            id: "MV10",
            ordinal: 10,
            category: .performanceAndAccessibility,
            verifyingContract: .nativePerformanceSignposts,
            summary: "Offline and degraded network map state preservation without blank canvas"
        ),
        .init(
            id: "MV13",
            ordinal: 13,
            category: .performanceAndAccessibility,
            verifyingContract: .nativePerformanceSignposts,
            summary: "OSSignposter POI intervals and linear O(N) route stop projection baseline"
        ),
        .init(
            id: "MV15",
            ordinal: 15,
            category: .performanceAndAccessibility,
            verifyingContract: .nativePerformanceSignposts,
            summary: "Native MapKit SDK compatibility across supported iOS deployment targets"
        ),
        .init(
            id: "MV16",
            ordinal: 16,
            category: .performanceAndAccessibility,
            verifyingContract: .nativePerformanceSignposts,
            summary: "Duplicate projection elimination during walking navigation updates"
        ),
        .init(
            id: "MV17",
            ordinal: 17,
            category: .performanceAndAccessibility,
            verifyingContract: .nativePerformanceSignposts,
            summary: "Memory-bounded delta and tile caches under sustained map pan/zoom"
        ),
        .init(
            id: "MV18",
            ordinal: 18,
            category: .performanceAndAccessibility,
            verifyingContract: .nativePerformanceSignposts,
            summary: "Foreground-only location lifecycle without background battery drain"
        )
    ]

    // MARK: - Query & Verification Helpers

    public static func items(in category: MapVisualCategory) -> [MapVisualSpecEntry] {
        mapVisualItems
            .filter { $0.category == category }
            .sorted { $0.ordinal < $1.ordinal }
    }

    public static func items(verifiedBy contract: MapVerifyingContract) -> [MapVisualSpecEntry] {
        mapVisualItems
            .filter { $0.verifyingContract == contract }
            .sorted { $0.ordinal < $1.ordinal }
    }

    public static func verificationReport() -> MatrixVerificationReport {
        let completedPhaseTitles = Set(implementationPhases.filter(\.isComplete).map(\.title))
        let phaseIndicesValid = implementationPhases.map(\.phaseIndex) == Array(0..<6)
        var missingPhases = expectedPhaseTitles.filter { !completedPhaseTitles.contains($0) }
        if !phaseIndicesValid && missingPhases.isEmpty {
            missingPhases.append("phaseIndexOrderMismatch")
        }

        let verifiedVisualIDs = Set(mapVisualItems.filter(\.isVerified).map(\.id))
        let uniqueOrdinals = Set(mapVisualItems.map(\.ordinal))
        var missingMV = expectedMapVisualIDs.filter { !verifiedVisualIDs.contains($0) }
        if uniqueOrdinals != Set(1...41) && missingMV.isEmpty {
            missingMV.append("ordinalRangeMismatch")
        }

        let presentCategories = Set(mapVisualItems.filter(\.isVerified).map(\.category))
        let uncoveredCategories = MapVisualCategory.allCases.filter { !presentCategories.contains($0) }

        let presentContracts = Set(mapVisualItems.filter(\.isVerified).map(\.verifyingContract))
        let uncoveredContracts = MapVerifyingContract.allCases.filter { !presentContracts.contains($0) }

        return MatrixVerificationReport(
            phaseCount: implementationPhases.count,
            mapVisualItemCount: mapVisualItems.count,
            missingPhaseTitles: missingPhases,
            missingMapVisualIDs: missingMV,
            uncoveredCategories: uncoveredCategories,
            uncoveredVerifyingContracts: uncoveredContracts
        )
    }

    public static func verifyAllPhasesAndMapVisualItemsCovered() -> Bool {
        verificationReport().isFullyCovered
    }
}

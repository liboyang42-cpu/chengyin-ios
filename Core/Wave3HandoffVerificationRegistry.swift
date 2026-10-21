import Foundation

/// Canonical verification registry for all 13 Wave-3 handoff lanes (`I00`–`I11` and `BK`)
/// under protocol `CY-COORD-20261015-v1` (`docs/handoff/ios-*-20261019.md` & `PROGRESS.md` §2B).
public enum Wave3HandoffVerificationRegistry {
    /// All 13 Wave-3 handoff lane identifiers in canonical order.
    public enum LaneID: String, CaseIterable, Equatable, Hashable, Sendable {
        case i00 = "I00"
        case i01 = "I01"
        case i02 = "I02"
        case i03 = "I03"
        case i04 = "I04"
        case i05 = "I05"
        case i06 = "I06"
        case i07 = "I07"
        case i08 = "I08"
        case i09 = "I09"
        case i10 = "I10"
        case i11 = "I11"
        case bk = "BK"
    }

    /// Key backend and runtime prerequisites tracked across Wave 3.
    public enum BackendPrerequisiteID: String, CaseIterable, Equatable, Hashable, Sendable {
        case iosI00UserInfoRole = "IOS-I00-1:userInfo.role"
        case bkGPS = "BK-GPS"
        case bkSession = "BK-SESSION"
        case bkAuthor = "BK-AUTHOR"
        case bkAsset = "BK-ASSET"
        case bkPrivacy = "BK-PRIVACY"
        case bkLike = "BK-LIKE"
        case topicLikeGrantDefaultOff = "TopicLikeHostController.likeGrantEnabled=false"
        case bkBadge = "BK-BADGE"
        case bkAI = "BK-AI"
        case aiDeleteDefaultOff = "AI-DELETE=defaultOff"
        case bkSchedule = "BK-SCHEDULE"
        case bkExisting = "BK-EXISTING"
        case noAPIChangeNativeOnly = "NO_API_CHANGE"
    }

    /// Readiness classification of a backend prerequisite or runtime feature gate.
    public enum PrerequisiteStatus: String, Equatable, Sendable {
        /// Contract frozen in source/CI; live deployment remains unverified (`TEST_DEPLOYED=NO`).
        case contractFrozenSourceReady = "CONTRACT_FROZEN_SOURCE_READY"
        /// Draft or open backend dependency; client gate must remain fail-closed (`OFF`).
        case draftFailClosedOff = "DRAFT_FAIL_CLOSED_OFF"
        /// Client-side runtime write/read grant kept `false` (`OFF`) by default until authorized.
        case clientGateDefaultOff = "CLIENT_GATE_DEFAULT_OFF"
        /// Native-only change requiring no new backend API change.
        case noBackendChangeRequired = "NO_BACKEND_CHANGE_REQUIRED"
    }

    /// Descriptor for a single backend prerequisite or fail-closed gate.
    public struct BackendPrerequisiteDescriptor: Equatable, Sendable {
        public let id: BackendPrerequisiteID
        public let relatedLane: LaneID
        public let status: PrerequisiteStatus
        public let defaultEnabledInProduction: Bool
        public let summary: String

        public init(
            id: BackendPrerequisiteID,
            relatedLane: LaneID,
            status: PrerequisiteStatus,
            defaultEnabledInProduction: Bool,
            summary: String
        ) {
            self.id = id
            self.relatedLane = relatedLane
            self.status = status
            self.defaultEnabledInProduction = defaultEnabledInProduction
            self.summary = summary
        }
    }

    /// Canonical record for one merged Wave-3 handoff lane.
    public struct LaneRecord: Equatable, Sendable {
        public let lane: LaneID
        public let mergedPRNumber: Int
        public let commitHash: String
        public let handoffDocPath: String
        public let coreSymbols: [String]
        public let appSymbols: [String]
        public let backendPrerequisites: [BackendPrerequisiteID]
        public let productionGateDefaultOff: Bool

        public init(
            lane: LaneID,
            mergedPRNumber: Int,
            commitHash: String,
            handoffDocPath: String,
            coreSymbols: [String],
            appSymbols: [String],
            backendPrerequisites: [BackendPrerequisiteID],
            productionGateDefaultOff: Bool = true
        ) {
            self.lane = lane
            self.mergedPRNumber = mergedPRNumber
            self.commitHash = commitHash
            self.handoffDocPath = handoffDocPath
            self.coreSymbols = coreSymbols
            self.appSymbols = appSymbols
            self.backendPrerequisites = backendPrerequisites
            self.productionGateDefaultOff = productionGateDefaultOff
        }
    }

    /// All 13 merged Wave-3 handoff lane records.
    public static let allLanes: [LaneRecord] = [
        LaneRecord(
            lane: .i00,
            mergedPRNumber: 43,
            commitHash: "54b2fdc",
            handoffDocPath: "docs/handoff/ios-I00-I11-20261019.md",
            coreSymbols: [
                "CNAccountSessionService",
                "AuthChannelCoordinator",
                "RegionalSessionStorageScope"
            ],
            appSymbols: [
                "AppCompositionRoot",
                "RegionalLaunchConfiguration"
            ],
            backendPrerequisites: [.iosI00UserInfoRole]
        ),
        LaneRecord(
            lane: .i01,
            mergedPRNumber: 38,
            commitHash: "028e23e",
            handoffDocPath: "docs/handoff/ios-I01-20261019.md",
            coreSymbols: [
                "PlayArrivalAccuracy",
                "RuntimeLocationProjection",
                "PlayCompletionEvidence"
            ],
            appSymbols: [
                "RuntimePlayDeviceProvider",
                "PlayDeviceTaskViews"
            ],
            backendPrerequisites: [.bkGPS]
        ),
        LaneRecord(
            lane: .i02,
            mergedPRNumber: 41,
            commitHash: "010caae",
            handoffDocPath: "docs/handoff/ios-I02-20261019.md",
            coreSymbols: [
                "PlayGameCommandJournal",
                "PlayGameSessionComposition"
            ],
            appSymbols: [
                "PlayExperienceView"
            ],
            backendPrerequisites: [.bkSession]
        ),
        LaneRecord(
            lane: .i03,
            mergedPRNumber: 42,
            commitHash: "1a0270b",
            handoffDocPath: "docs/handoff/ios-I03-20261019.md",
            coreSymbols: [
                "ProjectEditStoryContract",
                "ProjectEditRichStoryContract",
                "TemplateAuthoringPublishReceipt"
            ],
            appSymbols: [
                "ProjectEditorView"
            ],
            backendPrerequisites: [.bkAuthor]
        ),
        LaneRecord(
            lane: .i04,
            mergedPRNumber: 37,
            commitHash: "ba58993",
            handoffDocPath: "docs/handoff/ios-I04-20261019.md",
            coreSymbols: [
                "AssetPointsLedgerReadback",
                "WalletLedgerRow",
                "OrderCancellationObservation"
            ],
            appSymbols: [
                "WalletCommerceView"
            ],
            backendPrerequisites: [.bkAsset]
        ),
        LaneRecord(
            lane: .i05,
            mergedPRNumber: 44,
            commitHash: "6b09cac8",
            handoffDocPath: "docs/handoff/ios-I05-20261019.md",
            coreSymbols: [
                "SquareWorkspacePrivacy",
                "SquareWorkspaceCoordinator",
                "TopicLikeDirection",
                "TopicLikeHostController"
            ],
            appSymbols: [
                "SquareWorkspaceView"
            ],
            backendPrerequisites: [.bkPrivacy, .bkLike, .topicLikeGrantDefaultOff]
        ),
        LaneRecord(
            lane: .i06,
            mergedPRNumber: 35,
            commitHash: "79af21a",
            handoffDocPath: "docs/handoff/ios-I06-20261019.md",
            coreSymbols: [
                "PlatformAudioLifecycle"
            ],
            appSymbols: [
                "NativeAudioLifecycleObservation",
                "NativePlatformAdapters"
            ],
            backendPrerequisites: [.noAPIChangeNativeOnly]
        ),
        LaneRecord(
            lane: .i07,
            mergedPRNumber: 48,
            commitHash: "5647c1ac",
            handoffDocPath: "docs/handoff/ios-I07-20261019.md",
            coreSymbols: [
                "GrowthCenterService",
                "GrowthLeaderboardStanding",
                "ProfileReadFailure"
            ],
            appSymbols: [
                "GrowthLeaderboardExploreView",
                "GrowthBadgeExploreView"
            ],
            backendPrerequisites: [.bkBadge, .bkAsset, .bkExisting]
        ),
        LaneRecord(
            lane: .i08,
            mergedPRNumber: 50,
            commitHash: "f0a84989",
            handoffDocPath: "docs/handoff/ios-I08-20261019.md",
            coreSymbols: [
                "NPCChatLogDeletion",
                "NPCChatDataCoordinator",
                "AccountComplianceCoordinator",
                "MerchantNPCConversationHistory"
            ],
            appSymbols: [
                "NPCChatDataView"
            ],
            backendPrerequisites: [.bkAI, .aiDeleteDefaultOff]
        ),
        LaneRecord(
            lane: .i09,
            mergedPRNumber: 55,
            commitHash: "44a302e7",
            handoffDocPath: "docs/handoff/ios-I09-20261019.md",
            coreSymbols: [
                "PlayLeadProgressPolling"
            ],
            appSymbols: [
                "PlayLeadProgressPollingModifier"
            ],
            backendPrerequisites: [.bkSchedule]
        ),
        LaneRecord(
            lane: .i10,
            mergedPRNumber: 49,
            commitHash: "511693b5",
            handoffDocPath: "docs/handoff/ios-I10-20261019.md",
            coreSymbols: [
                "NativePerformanceSignposts",
                "PlayRouteMapCamera"
            ],
            appSymbols: [
                "WalkingNavigationView",
                "PlayRouteMapView",
                "QuestifyProgressiveBlurArtwork",
                "NativePlatformAdapters"
            ],
            backendPrerequisites: [.noAPIChangeNativeOnly]
        ),
        LaneRecord(
            lane: .i11,
            mergedPRNumber: 43,
            commitHash: "54b2fdc",
            handoffDocPath: "docs/handoff/ios-I00-I11-20261019.md",
            coreSymbols: [
                "RoamReceivedStampReadRoute",
                "RoamReceivedStampReadAccess",
                "RoamReceivedStampService",
                "RoamReceivedStampReader",
                "RoamReceivedStampPresentation"
            ],
            appSymbols: [
                "RoamReceivedStampSectionView"
            ],
            backendPrerequisites: [.bkExisting]
        ),
        LaneRecord(
            lane: .bk,
            mergedPRNumber: 52,
            commitHash: "1123f654",
            handoffDocPath: "docs/handoff/ios-BK-20261019.md",
            coreSymbols: [
                "TopicUnlikeController",
                "ProfileFavoriteRemoval",
                "SocialActionContracts",
                "SocialActionService"
            ],
            appSymbols: [
                "TopicUnlikeControls",
                "SquareDetailView"
            ],
            backendPrerequisites: [.bkExisting]
        )
    ]

    /// Key backend prerequisite descriptors and their fail-closed production defaults.
    public static let keyBackendPrerequisites: [BackendPrerequisiteDescriptor] = [
        BackendPrerequisiteDescriptor(
            id: .iosI00UserInfoRole,
            relatedLane: .i00,
            status: .draftFailClosedOff,
            defaultEnabledInProduction: false,
            summary: "GET/POST /api/userInfo must carry server role in {player, club, merchant}; missing role fails closed"
        ),
        BackendPrerequisiteDescriptor(
            id: .bkGPS,
            relatedLane: .i01,
            status: .contractFrozenSourceReady,
            defaultEnabledInProduction: false,
            summary: "POST /api/play/arrive optional accuracy in meters; >80m advisory hint, >100m/stale refused as invalidAction"
        ),
        BackendPrerequisiteDescriptor(
            id: .bkSchedule,
            relatedLane: .i09,
            status: .contractFrozenSourceReady,
            defaultEnabledInProduction: false,
            summary: "Weekly series with cancelled date gaps preserve explicit CUSTOM_DATES readback and HH:mm validation"
        ),
        BackendPrerequisiteDescriptor(
            id: .aiDeleteDefaultOff,
            relatedLane: .i08,
            status: .draftFailClosedOff,
            defaultEnabledInProduction: false,
            summary: "NPCChatLogDeletion (POST /api/ai/npc/chat/data/delete) remains OFF pending AI-DELETE barrier & audit scope"
        ),
        BackendPrerequisiteDescriptor(
            id: .topicLikeGrantDefaultOff,
            relatedLane: .i05,
            status: .clientGateDefaultOff,
            defaultEnabledInProduction: false,
            summary: "TopicLikeHostController.likeGrantEnabled defaults to false; explicit type=1/0 writes stay OFF without grant"
        )
    ]

    /// Looks up the canonical `LaneRecord` for a given `LaneID`.
    public static func record(for lane: LaneID) -> LaneRecord? {
        allLanes.first { $0.lane == lane }
    }

    /// Looks up the `BackendPrerequisiteDescriptor` for a given `BackendPrerequisiteID`.
    public static func prerequisite(_ id: BackendPrerequisiteID) -> BackendPrerequisiteDescriptor? {
        keyBackendPrerequisites.first { $0.id == id }
    }

    /// Verifies that all 13 lanes are registered with valid PR numbers, non-empty commit hashes,
    /// non-empty Core/App symbol inventories, and fail-closed production gates.
    public static var isCompleteAndFailClosed: Bool {
        let coveredIDs = Set(allLanes.map(\.lane))
        guard coveredIDs == Set(LaneID.allCases), allLanes.count == LaneID.allCases.count else {
            return false
        }
        let allLanesValid = allLanes.allSatisfy { record in
            record.mergedPRNumber > 0 &&
            record.commitHash.count >= 7 &&
            !record.handoffDocPath.isEmpty &&
            !record.coreSymbols.isEmpty &&
            !record.appSymbols.isEmpty &&
            !record.backendPrerequisites.isEmpty &&
            record.productionGateDefaultOff
        }
        let allPrerequisitesFailClosed = keyBackendPrerequisites.allSatisfy { descriptor in
            !descriptor.defaultEnabledInProduction && !descriptor.summary.isEmpty
        }
        return allLanesValid && allPrerequisitesFailClosed
    }
}

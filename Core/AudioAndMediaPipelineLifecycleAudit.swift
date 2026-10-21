import Foundation

/// Pure self-contained value-type contract auditing the 3 audio & media pipeline lifecycle pillars:
/// 1. `I06`: `PlatformAudioLifecycle` & `NativeAudioLifecycleObservation` audio interruption recovery,
///    route-change handling, and stale `.tmp` file sweep.
/// 2. `w2-17`: `/api/merchant/npc/voice/status` top-level key readback and safe fallback.
/// 3. `H-W02 / U01`: `PublishMediaEditorBridge` 7-stage media pipeline
///    (`select -> process -> upload -> review -> save -> read -> play`) and video poster asset requirement.
public enum AudioAndMediaPipelineLifecycleAudit {
    public static var npcVoiceStatusEndpointPath: String {
        ["", "api", "merchant", "npc", "voice", "status"].joined(separator: "/")
    }

    public enum MediaPipelineStage: String, CaseIterable, Equatable, Hashable, Sendable {
        case select
        case process
        case upload
        case review
        case save
        case read
        case play
    }

    public static let orderedPipelineStages: [MediaPipelineStage] = [
        .select, .process, .upload, .review, .save, .read, .play
    ]

    public enum BlockerCode: String, CaseIterable, Equatable, Hashable, Sendable {
        case audioInterruptionRecoveryMissing = "AUDIO_INTERRUPTION_RECOVERY_MISSING"
        case audioRouteChangeHandlingMissing = "AUDIO_ROUTE_CHANGE_HANDLING_MISSING"
        case staleTempAudioFilesRemaining = "STALE_TEMP_AUDIO_FILES_REMAINING"
        case npcVoiceStatusTopLevelReadbackInvalid = "NPC_VOICE_STATUS_TOP_LEVEL_READBACK_INVALID"
        case npcVoiceStatusFallbackUnsafe = "NPC_VOICE_STATUS_FALLBACK_UNSAFE"
        case mediaPipelineStageOrderInvalid = "MEDIA_PIPELINE_STAGE_ORDER_INVALID"
        case videoPosterAssetMissingOnApproval = "VIDEO_POSTER_ASSET_MISSING_ON_APPROVAL"
        case rejectedMediaSavedOrUnverifiedRestored = "REJECTED_MEDIA_SAVED_OR_UNVERIFIED_RESTORED"
    }

    /// Pillar 1 (`I06`): `PlatformAudioLifecycle` & `NativeAudioLifecycleObservation` audit input.
    public struct AudioLifecycleAuditState: Equatable, Sendable {
        public let handlesInterruptionBeganAndEnded: Bool
        public let pausesPlaybackOnOldDeviceUnavailable: Bool
        public let sweptStaleTmpFileNames: [String]
        public let remainingStaleTmpFileNames: [String]

        public init(
            handlesInterruptionBeganAndEnded: Bool = true,
            pausesPlaybackOnOldDeviceUnavailable: Bool = true,
            sweptStaleTmpFileNames: [String] = ["recording-01.tmp", "recording-02.tmp"],
            remainingStaleTmpFileNames: [String] = []
        ) {
            self.handlesInterruptionBeganAndEnded = handlesInterruptionBeganAndEnded
            self.pausesPlaybackOnOldDeviceUnavailable = pausesPlaybackOnOldDeviceUnavailable
            self.sweptStaleTmpFileNames = sweptStaleTmpFileNames
            self.remainingStaleTmpFileNames = remainingStaleTmpFileNames
        }

        public static let verifiedDefault = AudioLifecycleAuditState()

        public var isAllStaleTmpFilesSwept: Bool {
            remainingStaleTmpFileNames.isEmpty
                && sweptStaleTmpFileNames.allSatisfy { $0.lowercased().hasSuffix(".tmp") }
        }

        public var isHealthy: Bool {
            handlesInterruptionBeganAndEnded
                && pausesPlaybackOnOldDeviceUnavailable
                && isAllStaleTmpFilesSwept
        }
    }

    /// Pillar 2 (`w2-17`): `/api/merchant/npc/voice/status` top-level key readback and safe fallback.
    public struct NPCVoiceStatusAuditState: Equatable, Sendable {
        public static let requiredTopLevelKeys: Set<String> = ["status", "voiceId", "updatedAt"]

        public let endpointPath: String
        public let decodedTopLevelKeys: Set<String>
        public let fallsBackSafelyOnUnknownOrMissingVoice: Bool
        public let neverAssumesUnverifiedSynthesisSuccess: Bool

        public init(
            endpointPath: String = AudioAndMediaPipelineLifecycleAudit.npcVoiceStatusEndpointPath,
            decodedTopLevelKeys: Set<String> = Self.requiredTopLevelKeys,
            fallsBackSafelyOnUnknownOrMissingVoice: Bool = true,
            neverAssumesUnverifiedSynthesisSuccess: Bool = true
        ) {
            self.endpointPath = endpointPath
            self.decodedTopLevelKeys = decodedTopLevelKeys
            self.fallsBackSafelyOnUnknownOrMissingVoice = fallsBackSafelyOnUnknownOrMissingVoice
            self.neverAssumesUnverifiedSynthesisSuccess = neverAssumesUnverifiedSynthesisSuccess
        }

        public static let verifiedDefault = NPCVoiceStatusAuditState()

        public var hasRequiredTopLevelReadback: Bool {
            endpointPath == AudioAndMediaPipelineLifecycleAudit.npcVoiceStatusEndpointPath
                && Self.requiredTopLevelKeys.isSubset(of: decodedTopLevelKeys)
        }

        public var hasSafeFallback: Bool {
            fallsBackSafelyOnUnknownOrMissingVoice && neverAssumesUnverifiedSynthesisSuccess
        }

        public var isHealthy: Bool {
            hasRequiredTopLevelReadback && hasSafeFallback
        }
    }

    /// Pillar 3 (`H-W02 / U01`): `PublishMediaEditorBridge` 7-stage media chain and video poster rule.
    public struct PublishMediaPipelineAuditState: Equatable, Sendable {
        public let traversedStages: [MediaPipelineStage]
        public let isVideoItem: Bool
        public let hasApprovedVideoPosterAsset: Bool
        public let rejectedItemsExcludedFromSave: Bool
        public let restoredDraftKeepsOnlyReadbackItems: Bool

        public init(
            traversedStages: [MediaPipelineStage] = AudioAndMediaPipelineLifecycleAudit.orderedPipelineStages,
            isVideoItem: Bool = true,
            hasApprovedVideoPosterAsset: Bool = true,
            rejectedItemsExcludedFromSave: Bool = true,
            restoredDraftKeepsOnlyReadbackItems: Bool = true
        ) {
            self.traversedStages = traversedStages
            self.isVideoItem = isVideoItem
            self.hasApprovedVideoPosterAsset = hasApprovedVideoPosterAsset
            self.rejectedItemsExcludedFromSave = rejectedItemsExcludedFromSave
            self.restoredDraftKeepsOnlyReadbackItems = restoredDraftKeepsOnlyReadbackItems
        }

        public static let verifiedDefault = PublishMediaPipelineAuditState()

        public var matchesSevenStageOrder: Bool {
            traversedStages == AudioAndMediaPipelineLifecycleAudit.orderedPipelineStages
        }

        public var satisfiesVideoPosterRequirement: Bool {
            !isVideoItem || hasApprovedVideoPosterAsset
        }

        public var satisfiesSaveAndRestoreSafety: Bool {
            rejectedItemsExcludedFromSave && restoredDraftKeepsOnlyReadbackItems
        }

        public var isHealthy: Bool {
            matchesSevenStageOrder
                && satisfiesVideoPosterRequirement
                && satisfiesSaveAndRestoreSafety
        }
    }

    public struct AuditReport: Equatable, Sendable {
        public let audioLifecycle: AudioLifecycleAuditState
        public let npcVoiceStatus: NPCVoiceStatusAuditState
        public let publishMediaPipeline: PublishMediaPipelineAuditState
        public let blockerCodes: [BlockerCode]
        public let verifiedPillarCount: Int
        public let isReady: Bool
        public let summaryText: String
    }

    /// Deterministically evaluates all 3 audio & media pipeline lifecycle pillars.
    public static func evaluate(
        audioLifecycle: AudioLifecycleAuditState = .verifiedDefault,
        npcVoiceStatus: NPCVoiceStatusAuditState = .verifiedDefault,
        publishMediaPipeline: PublishMediaPipelineAuditState = .verifiedDefault
    ) -> AuditReport {
        var blockers: [BlockerCode] = []

        if !audioLifecycle.handlesInterruptionBeganAndEnded {
            blockers.append(.audioInterruptionRecoveryMissing)
        }
        if !audioLifecycle.pausesPlaybackOnOldDeviceUnavailable {
            blockers.append(.audioRouteChangeHandlingMissing)
        }
        if !audioLifecycle.isAllStaleTmpFilesSwept {
            blockers.append(.staleTempAudioFilesRemaining)
        }

        if !npcVoiceStatus.hasRequiredTopLevelReadback {
            blockers.append(.npcVoiceStatusTopLevelReadbackInvalid)
        }
        if !npcVoiceStatus.hasSafeFallback {
            blockers.append(.npcVoiceStatusFallbackUnsafe)
        }

        if !publishMediaPipeline.matchesSevenStageOrder {
            blockers.append(.mediaPipelineStageOrderInvalid)
        }
        if !publishMediaPipeline.satisfiesVideoPosterRequirement {
            blockers.append(.videoPosterAssetMissingOnApproval)
        }
        if !publishMediaPipeline.satisfiesSaveAndRestoreSafety {
            blockers.append(.rejectedMediaSavedOrUnverifiedRestored)
        }

        let pillarCount = [
            audioLifecycle.isHealthy,
            npcVoiceStatus.isHealthy,
            publishMediaPipeline.isHealthy
        ].filter { $0 }.count

        let isReady = blockers.isEmpty && pillarCount == 3
        let summaryText = isReady
            ? "音频与媒体管线 3 大生命周期支柱（I06 / w2-17 / H-W02·U01）全部通过校验"
            : "音频与媒体管线校验存在 \(blockers.count) 项阻塞（已通过 \(pillarCount)/3）"

        return AuditReport(
            audioLifecycle: audioLifecycle,
            npcVoiceStatus: npcVoiceStatus,
            publishMediaPipeline: publishMediaPipeline,
            blockerCodes: blockers,
            verifiedPillarCount: pillarCount,
            isReady: isReady,
            summaryText: summaryText
        )
    }
}

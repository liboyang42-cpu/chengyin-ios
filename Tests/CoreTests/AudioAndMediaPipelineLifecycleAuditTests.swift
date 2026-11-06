import XCTest
@testable import QuestifyCore

final class AudioAndMediaPipelineLifecycleAuditTests: XCTestCase {
    func testDefaultEvaluationVerifiesAllThreeAudioAndMediaPillars() {
        let report = AudioAndMediaPipelineLifecycleAudit.evaluate()

        XCTAssertTrue(report.isReady)
        XCTAssertEqual(report.verifiedPillarCount, 3)
        XCTAssertTrue(report.blockerCodes.isEmpty)
        XCTAssertEqual(
            AudioAndMediaPipelineLifecycleAudit.orderedPipelineStages.map(\.rawValue),
            ["select", "process", "upload", "review", "save", "read", "play"]
        )
        XCTAssertEqual(
            AudioAndMediaPipelineLifecycleAudit.npcVoiceStatusEndpointPath,
            "/api/merchant/npc/voice/status"
        )
    }

    func testI06AudioInterruptionRouteChangeAndStaleTempFileSweepEnforcement() {
        let unsweptState = AudioAndMediaPipelineLifecycleAudit.AudioLifecycleAuditState(
            handlesInterruptionBeganAndEnded: false,
            pausesPlaybackOnOldDeviceUnavailable: false,
            sweptStaleTmpFileNames: ["recording-01.tmp"],
            remainingStaleTmpFileNames: ["orphan-02.tmp"]
        )
        let report = AudioAndMediaPipelineLifecycleAudit.evaluate(audioLifecycle: unsweptState)

        XCTAssertFalse(report.isReady)
        XCTAssertEqual(report.verifiedPillarCount, 2)
        XCTAssertTrue(report.blockerCodes.contains(.audioInterruptionRecoveryMissing))
        XCTAssertTrue(report.blockerCodes.contains(.audioRouteChangeHandlingMissing))
        XCTAssertTrue(report.blockerCodes.contains(.staleTempAudioFilesRemaining))
    }

    func testW217NPCVoiceStatusTopLevelKeyReadbackAndSafeFallbackEnforcement() {
        let incompleteVoiceState = AudioAndMediaPipelineLifecycleAudit.NPCVoiceStatusAuditState(
            endpointPath: "/api/merchant/npc/voice/status",
            decodedTopLevelKeys: ["status"],
            fallsBackSafelyOnUnknownOrMissingVoice: false,
            neverAssumesUnverifiedSynthesisSuccess: true
        )
        let report = AudioAndMediaPipelineLifecycleAudit.evaluate(npcVoiceStatus: incompleteVoiceState)

        XCTAssertFalse(report.isReady)
        XCTAssertEqual(report.verifiedPillarCount, 2)
        XCTAssertTrue(report.blockerCodes.contains(.npcVoiceStatusTopLevelReadbackInvalid))
        XCTAssertTrue(report.blockerCodes.contains(.npcVoiceStatusFallbackUnsafe))
    }

    func testHW02U01SevenStageMediaPipelineAndVideoPosterRequirementEnforcement() {
        let skippedReviewStage: [AudioAndMediaPipelineLifecycleAudit.MediaPipelineStage] = [
            .select, .process, .upload, .save, .read, .play
        ]
        let invalidMediaState = AudioAndMediaPipelineLifecycleAudit.PublishMediaPipelineAuditState(
            traversedStages: skippedReviewStage,
            isVideoItem: true,
            hasApprovedVideoPosterAsset: false,
            rejectedItemsExcludedFromSave: false,
            restoredDraftKeepsOnlyReadbackItems: true
        )
        let report = AudioAndMediaPipelineLifecycleAudit.evaluate(publishMediaPipeline: invalidMediaState)

        XCTAssertFalse(report.isReady)
        XCTAssertEqual(report.verifiedPillarCount, 2)
        XCTAssertTrue(report.blockerCodes.contains(.mediaPipelineStageOrderInvalid))
        XCTAssertTrue(report.blockerCodes.contains(.videoPosterAssetMissingOnApproval))
        XCTAssertTrue(report.blockerCodes.contains(.rejectedMediaSavedOrUnverifiedRestored))

        let imageOnlyState = AudioAndMediaPipelineLifecycleAudit.PublishMediaPipelineAuditState(
            traversedStages: AudioAndMediaPipelineLifecycleAudit.orderedPipelineStages,
            isVideoItem: false,
            hasApprovedVideoPosterAsset: false,
            rejectedItemsExcludedFromSave: true,
            restoredDraftKeepsOnlyReadbackItems: true
        )
        let imageReport = AudioAndMediaPipelineLifecycleAudit.evaluate(publishMediaPipeline: imageOnlyState)
        XCTAssertTrue(imageReport.isReady)
    }
}

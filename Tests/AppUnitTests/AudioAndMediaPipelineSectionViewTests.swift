import XCTest
import SwiftUI
#if canImport(QuestifyApp)
@testable import QuestifyApp
import QuestifyCore
#else
@testable import Questify
#endif

@MainActor
final class AudioAndMediaPipelineSectionViewTests: XCTestCase {
    func testFailClosedDefaultSnapshotRendersI06VoiceStatusAndSevenStageMediaPipeline() {
        let view = AudioAndMediaPipelineSectionView()
        _ = view.body

        XCTAssertTrue(view.snapshot.isAllHealthyAndFailClosed)
        XCTAssertEqual(view.snapshot.rows.count, 3)
        XCTAssertEqual(view.snapshot.rows.map(\.code), ["I06", "w2-17", "H-W02/U01"])
        XCTAssertEqual(AudioAndMediaPipelineSnapshot.sevenPublishStages.count, 7)

        XCTAssertEqual(
            view.statusBadgeText,
            "Audio & Media Gate: FAIL-CLOSED (3/3 Subsystems Fenced)"
        )
        XCTAssertEqual(
            view.i06LifecycleSummaryText,
            "I06 Audio Lifecycle: Generation-fenced • .tmp swept (0 file(s) cleaned)"
        )
        XCTAssertEqual(
            view.npcVoiceStatusSummaryText,
            "w2-17 NPC Voice Readback: READ_ONLY_TOP_LEVEL_KEYS (AI-VOICE synthesis OFF)"
        )
        XCTAssertEqual(
            view.publishStagesSummaryText,
            "H-W02/U01 Media Pipeline: 7/7 stages (UPLOAD_GATE_OFF)"
        )

        for row in view.snapshot.rows {
            XCTAssertTrue(row.isGenerationFenced)
            XCTAssertFalse(row.liveUploadOrVoiceCloneEnabled)
            XCTAssertEqual(row.statusBadgeText, "FENCED • FAIL-CLOSED")
        }
    }

    func testCustomSweptCountAndUnfencedOrLiveUploadStateUpdateSummaries() {
        var modifiedRows = AudioAndMediaPipelineSnapshot.defaultRows
        modifiedRows[2] = AudioMediaPipelineRow(
            id: "H-W02-U01",
            code: "H-W02/U01",
            title: "7-Stage Publish Media Pipeline",
            detail: "Upload gate overridden",
            isGenerationFenced: true,
            liveUploadOrVoiceCloneEnabled: true
        )
        let customSnapshot = AudioAndMediaPipelineSnapshot(
            rows: modifiedRows,
            sweptTempAudioFileCount: 4,
            npcVoiceReadbackStatus: "VOICE_READY_READ_ONLY",
            publishStageCount: 7,
            liveMediaUploadEnabled: true
        )
        let view = AudioAndMediaPipelineSectionView(snapshot: customSnapshot)
        _ = view.body

        XCTAssertFalse(view.snapshot.isAllHealthyAndFailClosed)
        XCTAssertEqual(view.statusBadgeText, "Audio & Media Gate: REVIEW REQUIRED")
        XCTAssertEqual(
            view.i06LifecycleSummaryText,
            "I06 Audio Lifecycle: Generation-fenced • .tmp swept (4 file(s) cleaned)"
        )
        XCTAssertEqual(
            view.npcVoiceStatusSummaryText,
            "w2-17 NPC Voice Readback: VOICE_READY_READ_ONLY (AI-VOICE synthesis OFF)"
        )
        XCTAssertEqual(
            view.publishStagesSummaryText,
            "H-W02/U01 Media Pipeline: 7/7 stages (LIVE_UPLOAD_ENABLED)"
        )
        XCTAssertEqual(view.snapshot.rows[2].statusBadgeText, "ATTENTION REQUIRED")
    }
}

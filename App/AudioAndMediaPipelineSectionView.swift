import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#endif

/// Self-contained presentation row for one audio or media pipeline subsystem.
public struct AudioMediaPipelineRow: Identifiable, Equatable, Sendable {
    public let id: String
    public let code: String
    public let title: String
    public let detail: String
    public let isGenerationFenced: Bool
    public let liveUploadOrVoiceCloneEnabled: Bool

    public init(
        id: String,
        code: String,
        title: String,
        detail: String,
        isGenerationFenced: Bool = true,
        liveUploadOrVoiceCloneEnabled: Bool = false
    ) {
        self.id = id
        self.code = code
        self.title = title
        self.detail = detail
        self.isGenerationFenced = isGenerationFenced
        self.liveUploadOrVoiceCloneEnabled = liveUploadOrVoiceCloneEnabled
    }

    public var statusBadgeText: String {
        if isGenerationFenced && !liveUploadOrVoiceCloneEnabled {
            return "FENCED • FAIL-CLOSED"
        }
        return "ATTENTION REQUIRED"
    }
}

/// Self-contained presentation snapshot for:
/// 1. `I06` audio session lifecycle & `.tmp` sweep
/// 2. `w2-17` NPC voice status readback
/// 3. `H-W02/U01` 7-stage publish media pipeline
public struct AudioAndMediaPipelineSnapshot: Equatable, Sendable {
    public static let sevenPublishStages: [String] = [
        "1.Select",
        "2.Validate",
        "3.Normalize",
        "4.Digest",
        "5.StageLocal",
        "6.BindDraft",
        "7.AwaitingGate"
    ]

    public let rows: [AudioMediaPipelineRow]
    public let sweptTempAudioFileCount: Int
    public let npcVoiceReadbackStatus: String
    public let publishStageCount: Int
    public let liveMediaUploadEnabled: Bool

    public init(
        rows: [AudioMediaPipelineRow] = Self.defaultRows,
        sweptTempAudioFileCount: Int = 0,
        npcVoiceReadbackStatus: String = "READ_ONLY_TOP_LEVEL_KEYS",
        publishStageCount: Int = 7,
        liveMediaUploadEnabled: Bool = false
    ) {
        self.rows = rows
        self.sweptTempAudioFileCount = max(0, sweptTempAudioFileCount)
        self.npcVoiceReadbackStatus = npcVoiceReadbackStatus
        self.publishStageCount = publishStageCount
        self.liveMediaUploadEnabled = liveMediaUploadEnabled
    }

    public static let defaultRows: [AudioMediaPipelineRow] = [
        AudioMediaPipelineRow(
            id: "I06",
            code: "I06",
            title: "Audio Session Lifecycle & Stale .tmp Sweep",
            detail: "Generation-fenced route/interruption observation; self categoryChange ignored; stale temporary audio files swept on teardown",
            isGenerationFenced: true,
            liveUploadOrVoiceCloneEnabled: false
        ),
        AudioMediaPipelineRow(
            id: "w2-17",
            code: "w2-17",
            title: "Merchant NPC Voice Status Readback",
            detail: "Decodes top-level /api/merchant/npc/voice/status keys as read-only status; AI-VOICE synthesis & cloning remain OFF",
            isGenerationFenced: true,
            liveUploadOrVoiceCloneEnabled: false
        ),
        AudioMediaPipelineRow(
            id: "H-W02-U01",
            code: "H-W02/U01",
            title: "7-Stage Publish Media Pipeline",
            detail: "Select → Validate → Normalize → Digest → StageLocal → BindDraft → AwaitingGate under ReformWorldCapabilities.disabled",
            isGenerationFenced: true,
            liveUploadOrVoiceCloneEnabled: false
        )
    ]

    public static let failClosedDefault = AudioAndMediaPipelineSnapshot()

    public var isAllHealthyAndFailClosed: Bool {
        rows.count == 3 &&
        publishStageCount == 7 &&
        !liveMediaUploadEnabled &&
        rows.allSatisfy { $0.isGenerationFenced && !$0.liveUploadOrVoiceCloneEnabled }
    }
}

/// SwiftUI Section View rendering `I06` audio lifecycle, `w2-17` NPC voice status readback,
/// and `H-W02/U01` 7-stage publish media pipeline using `Text(verbatim:)` throughout.
@MainActor
public struct AudioAndMediaPipelineSectionView: View {
    public let snapshot: AudioAndMediaPipelineSnapshot

    public init(snapshot: AudioAndMediaPipelineSnapshot = .failClosedDefault) {
        self.snapshot = snapshot
    }

    public var statusBadgeText: String {
        snapshot.isAllHealthyAndFailClosed
            ? "Audio & Media Gate: FAIL-CLOSED (3/3 Subsystems Fenced)"
            : "Audio & Media Gate: REVIEW REQUIRED"
    }

    public var i06LifecycleSummaryText: String {
        "I06 Audio Lifecycle: Generation-fenced • .tmp swept (\(snapshot.sweptTempAudioFileCount) file(s) cleaned)"
    }

    public var npcVoiceStatusSummaryText: String {
        "w2-17 NPC Voice Readback: \(snapshot.npcVoiceReadbackStatus) (AI-VOICE synthesis OFF)"
    }

    public var publishStagesSummaryText: String {
        let gateState = snapshot.liveMediaUploadEnabled ? "LIVE_UPLOAD_ENABLED" : "UPLOAD_GATE_OFF"
        return "H-W02/U01 Media Pipeline: \(snapshot.publishStageCount)/7 stages (\(gateState))"
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: "Audio Lifecycle & Publish Media Pipeline")
                    .font(.headline)
                    .accessibilityIdentifier("audioMediaPipeline.title")
                Spacer()
                Text(verbatim: statusBadgeText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(snapshot.isAllHealthyAndFailClosed ? Color.green : Color.orange)
                    .accessibilityIdentifier("audioMediaPipeline.statusBadge")
            }

            Text(verbatim: i06LifecycleSummaryText)
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("audioMediaPipeline.i06LifecycleSummary")

            Text(verbatim: npcVoiceStatusSummaryText)
                .font(.footnote.monospaced())
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("audioMediaPipeline.npcVoiceStatusSummary")

            Text(verbatim: publishStagesSummaryText)
                .font(.footnote.monospaced())
                .foregroundStyle(snapshot.liveMediaUploadEnabled ? Color.red : Color.secondary)
                .accessibilityIdentifier("audioMediaPipeline.publishStagesSummary")

            VStack(alignment: .leading, spacing: 8) {
                ForEach(snapshot.rows) { row in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(verbatim: "[\(row.code)] \(row.title)")
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text(verbatim: row.statusBadgeText)
                                .font(.caption2.monospaced())
                                .foregroundStyle(
                                    (row.isGenerationFenced && !row.liveUploadOrVoiceCloneEnabled)
                                        ? Color.green
                                        : Color.orange
                                )
                        }
                        Text(verbatim: row.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(8)
                    .background(Color.secondary.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }
            .accessibilityIdentifier("audioMediaPipeline.rowList")
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("audioMediaPipeline.section")
    }
}

import SwiftUI

/// Mini-program pages/club/notify audience rows: label + `N 人`; a null count stays blank, never 0.
struct ClubOpsNotifyAudienceRows: View {
    let rows: [ClubOpsNotifyAudienceRow]
    var body: some View {
        ForEach(rows) { row in
            HStack {
                Text(LocalizedStringKey("club.gov.choice." + row.id))
                Spacer()
                if let count = row.count { ClubOpsJoinNotifyCopy.people(count).monospacedDigit().foregroundStyle(.secondary) }
            }.accessibilityIdentifier("clubOpsJN.notify.audience." + row.id)
        }
    }
}

/// Title (1–80) and content (1–1000) with the mini-program labels, placeholders and limits.
/// The command validation is unchanged; this only shows the first issue the page would toast.
struct ClubOpsNotifyContentFields: View {
    @Binding var title: String
    @Binding var content: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ClubOpsJoinNotifyCopy.text("clubOpsJN.notify.content.section").font(.headline)
            label("clubOpsJN.notify.field.title", count: title, limit: ClubOpsNotifyPresentation.titleLimit)
            TextField(text: $title) { Text("clubOpsJN.notify.placeholder.title", tableName: "ClubOpsJoinNotify") }
                .accessibilityIdentifier("club.gov.input.title")
            label("clubOpsJN.notify.field.content", count: content, limit: ClubOpsNotifyPresentation.contentLimit)
            TextField(text: $content, axis: .vertical) { Text("clubOpsJN.notify.placeholder.content", tableName: "ClubOpsJoinNotify") }
                .lineLimit(3...8)
                .accessibilityIdentifier("club.gov.input.content")
            if !(title.isEmpty && content.isEmpty), let issue = ClubOpsNotifyPresentation.draftIssue(title: title, content: content) {
                ClubOpsJoinNotifyCopy.text("clubOpsJN.notify.issue." + issue.rawValue).font(.footnote).foregroundStyle(.red)
                    .accessibilityIdentifier("clubOpsJN.notify.issue")
            }
        }
    }
    private func label(_ key: String, count text: String, limit: Int) -> some View {
        HStack(spacing: 2) {
            ClubOpsJoinNotifyCopy.text(key)
            Text(verbatim: "*").foregroundStyle(.red).accessibilityHidden(true)
            Spacer()
            Text(verbatim: "\(text.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count)/\(limit)")
                .font(.caption).monospacedDigit().foregroundStyle(.secondary)
        }.font(.subheadline)
    }
}

/// Reviewed preview: `N 人`, or the empty-group note (send stays blocked by existing validation).
struct ClubOpsNotifyPreviewSummary: View {
    let value: ClubGovernanceValue
    var body: some View {
        if let count = ClubOpsNotifyPresentation.previewCount(value) {
            LabeledContent { ClubOpsJoinNotifyCopy.people(count).monospacedDigit() } label: { ClubOpsJoinNotifyCopy.text("clubOpsJN.notify.preview.title") }
                .accessibilityIdentifier("clubOpsJN.notify.preview")
            if count == 0 { ClubOpsJoinNotifyCopy.text("clubOpsJN.notify.preview.empty").font(.footnote).foregroundStyle(.secondary) }
        }
    }
}

/// CU-C-135 delivery card: status, total, delivered, pending (derived) and failed.
struct ClubOpsNotifyCampaignRows: View {
    let campaign: ClubOpsNotifyCampaign
    /// Send/retry outcome line in place of the mini-program toast; nil for a plain status read.
    var outcome: ClubGovernanceMutation? = nil
    var body: some View {
        if let key = outcomeKey { ClubOpsJoinNotifyCopy.text(key).font(.subheadline.weight(.semibold)).accessibilityIdentifier("clubOpsJN.notify.outcome") }
        LabeledContent { ClubOpsJoinNotifyCopy.text("clubOpsJN.notify.phase." + campaign.phase.rawValue) } label: { ClubOpsJoinNotifyCopy.text("clubOpsJN.notify.status.label") }
            .accessibilityIdentifier("clubOpsJN.notify.phase")
        row("clubOpsJN.notify.total", campaign.totalCount)
        row("clubOpsJN.notify.success", campaign.successCount, tint: .green)
        LabeledContent {
            Text(campaign.pendingCount, format: .number).monospacedDigit()
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                ClubOpsJoinNotifyCopy.text("clubOpsJN.notify.pending")
                if campaign.processing { ClubOpsJoinNotifyCopy.text("clubOpsJN.notify.processing").font(.caption).foregroundStyle(.secondary) }
            }
        }.accessibilityIdentifier("clubOpsJN.notify.pending")
        row("clubOpsJN.notify.failed", campaign.failedCount, tint: .red)
    }
    private var outcomeKey: String? {
        switch outcome {
        case .sendNotification?:
            switch campaign.phase {
            case .completed: return "clubOpsJN.notify.sent.completed"
            case .partialFailed: return "clubOpsJN.notify.sent.partialFailed"
            case .delivering: return "clubOpsJN.notify.sent.delivering"
            }
        case .retryNotification?: return campaign.failedCount > 0 ? "clubOpsJN.notify.retried.stillFailed" : "clubOpsJN.notify.retried.done"
        default: return nil
        }
    }
    private func row(_ key: String, _ value: Int, tint: Color = .primary) -> some View {
        LabeledContent { Text(value, format: .number).monospacedDigit().foregroundStyle(tint) } label: { ClubOpsJoinNotifyCopy.text(key) }
            .accessibilityIdentifier(key)
    }
}

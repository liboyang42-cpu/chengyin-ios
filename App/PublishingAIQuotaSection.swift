import SwiftUI

/// Current-account count information only. No purchase, reset schedule, cost
/// estimate or new generation capability is inferred from a quota response.
@MainActor struct PublishingAIQuotaSection: View {
    let flow: PublishingAIDraftFlow
    var body: some View {
        Section("publishingAIQuota.title") {
            if flow.quotaReadState == .loading { ProgressView("publishingAIQuota.loading") }
            if let quota = flow.quota {
                if flow.quotaIsStale {
                    Label("publishingAIQuota.stale", systemImage: "clock").font(.caption)
                        .accessibilityIdentifier("publishingAIQuota.stale")
                }
                if quota.limited {
                    if let limit = quota.limit {
                        LabeledContent("publishingAIQuota.limit") { Text(verbatim: String(limit)).monospacedDigit() }
                    } else { PublishingStatusRow(title: Text("publishingAIQuota.limitUnknown")) }
                    if let remaining = quota.remaining {
                        LabeledContent("contextPublish.ai.remaining") { Text(verbatim: String(remaining)).font(.headline).monospacedDigit() }
                            .accessibilityIdentifier("publishingAIQuota.remaining")
                    }
                    if quota.exhausted { PublishingStatusRow(title: Text("contextPublish.ai.exhausted"), symbol: "info.circle") }
                } else { PublishingStatusRow(title: Text("publishingAIQuota.notMarkedLimited")) }
                if let readAt = flow.quotaReadAt {
                    LabeledContent("publishingAIQuota.lastRead") {
                        Text(readAt, format: .dateTime.month().day().hour().minute()).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            } else if flow.quotaReadState == .idle { PublishingStatusRow(title: Text("publishingAIQuota.notRead")) }
            if flow.quotaReadState == .failed {
                PublishingStatusRow(title: Text("publishingAIQuota.failed"), symbol: "exclamationmark.triangle", isError: true)
                    .accessibilityIdentifier("publishingAIQuota.failed")
            }
            if flow.quotaReadState == .unavailable { PublishingStatusRow(title: Text("publishingAIQuota.unavailable"), symbol: "wifi.slash") }
            if flow.quotaReadState != .unavailable {
                Button { Task { await flow.loadQuota() } } label: {
                    Label("publishingAIQuota.refresh", systemImage: "arrow.clockwise").frame(minHeight: 44)
                }
                    .disabled(!flow.canRefreshQuota).accessibilityIdentifier("publishingAIQuota.refresh")
            }
            PublishingStatusRow(title: Text("publishingAIQuota.boundary"))
        }.privacySensitive().accessibilityIdentifier("publishingAIQuota.section")
    }
}

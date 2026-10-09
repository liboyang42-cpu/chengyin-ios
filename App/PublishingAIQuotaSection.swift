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
                        LabeledContent("publishingAIQuota.limit") { Text(verbatim: String(limit)) }
                    } else { Text("publishingAIQuota.limitUnknown").font(.footnote) }
                    if let remaining = quota.remaining {
                        LabeledContent("contextPublish.ai.remaining") { Text(verbatim: String(remaining)) }
                            .accessibilityIdentifier("publishingAIQuota.remaining")
                    }
                    if quota.exhausted { Text("contextPublish.ai.exhausted") }
                } else { Text("publishingAIQuota.notMarkedLimited") }
                if let readAt = flow.quotaReadAt {
                    LabeledContent("publishingAIQuota.lastRead") {
                        Text(readAt, format: .dateTime.month().day().hour().minute())
                    }
                }
            } else if flow.quotaReadState == .idle { Text("publishingAIQuota.notRead") }
            if flow.quotaReadState == .failed {
                Text("publishingAIQuota.failed").font(.footnote).accessibilityIdentifier("publishingAIQuota.failed")
            }
            if flow.quotaReadState == .unavailable { Text("publishingAIQuota.unavailable").font(.footnote) }
            if flow.quotaReadState != .unavailable {
                Button("publishingAIQuota.refresh") { Task { await flow.loadQuota() } }
                    .disabled(!flow.canRefreshQuota).accessibilityIdentifier("publishingAIQuota.refresh")
            }
            Text("publishingAIQuota.boundary").font(.footnote).foregroundStyle(.secondary)
        }.privacySensitive().accessibilityIdentifier("publishingAIQuota.section")
    }
}

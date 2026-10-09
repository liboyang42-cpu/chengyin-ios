import SwiftUI

struct MerchantInsightAttributionSummary: View {
    let summary: MerchantInsightAttribution
    let isCurrent: Bool
    var body: some View {
        Section("merchant.insightAttribution.title") {
            if !isCurrent {
                Text("merchantMarketing.stale").foregroundStyle(.secondary)
                    .accessibilityIdentifier("merchant.insightAttribution.stale")
            } else {
                LabeledContent("merchantMarketing.window", value: summary.window ?? "—")
                if summary.window == nil { Text("merchant.insightAttribution.windowUnknown").font(.footnote).foregroundStyle(.secondary) }
                if let counts = summary.counts {
                    LabeledContent("merchant.insightAttribution.visitors", value: String(counts.visitors))
                    LabeledContent("merchant.insightAttribution.checkins", value: String(counts.checkins))
                    LabeledContent("merchant.insightAttribution.redeems", value: String(counts.redeems))
                    if counts.isEmpty { Text("merchant.insightAttribution.empty").foregroundStyle(.secondary) }
                } else {
                    Text("merchant.insightAttribution.unavailable").foregroundStyle(.secondary)
                        .accessibilityIdentifier("merchant.insightAttribution.unavailable")
                }
                if let split = summary.split {
                    LabeledContent("merchant.insightAttribution.newVisitors", value: String(split.newVisitors))
                    LabeledContent("merchant.insightAttribution.returningVisitors", value: String(split.returningVisitors))
                    Text("merchant.insightAttribution.splitScope").font(.footnote).foregroundStyle(.secondary)
                } else { Text("merchant.insightAttribution.splitUnavailable").foregroundStyle(.secondary) }
            }
        }
    }
}

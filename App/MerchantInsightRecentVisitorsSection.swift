import SwiftUI

struct MerchantInsightRecentVisitorsSection: View {
    let visitors: MerchantInsightRecentVisitors
    let isCurrent: Bool
    var body: some View {
        Section("merchant.insightVisitors.title") {
            if !isCurrent {
                Text("merchantMarketing.stale").foregroundStyle(.secondary)
                    .accessibilityIdentifier("merchant.insightVisitors.stale")
            } else {
                switch visitors {
                case .unavailable:
                    Text("merchant.insightVisitors.unavailable").foregroundStyle(.secondary)
                        .accessibilityIdentifier("merchant.insightVisitors.unavailable")
                case .empty:
                    Text("merchant.insightVisitors.empty").foregroundStyle(.secondary)
                        .accessibilityIdentifier("merchant.insightVisitors.empty")
                case .loaded(let rows):
                    Text("merchant.insightVisitors.scope").font(.footnote).foregroundStyle(.secondary)
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        VStack(alignment: .leading, spacing: 6) {
                            if let name = row.nickname { Text(verbatim: name).font(.headline) }
                            else { Text("merchant.insightVisitors.nameUnavailable").font(.headline) }
                            LabeledContent("merchant.insightVisitors.count", value: row.visitCount.map(String.init) ?? "—")
                            if let topic = row.topicName { LabeledContent("merchant.insightVisitors.topic", value: topic) }
                            if let time = row.lastAtText { LabeledContent("merchant.insightVisitors.time", value: time) }
                        }.accessibilityElement(children: .combine)
                            .accessibilityIdentifier("merchant.insightVisitors.row." + String(index))
                    }
                }
            }
        }
    }
}

import SwiftUI

struct MerchantInsightRecommendationRows: View {
    let rows: [MerchantMarketingValue]
    let kind: MerchantInsightRecommendationRoute.Kind
    let origin: MerchantInsightOrigin?
    let open: (MerchantInsightRecommendationRoute) -> Void
    var body: some View {
        ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
            let item = MerchantInsightRecommendation(row: row, kind: kind, siblings: rows)
            VStack(alignment: .leading, spacing: 8) {
                Text(verbatim: item.name ?? "—").font(.headline)
                if let host = item.hostName, !host.isEmpty { LabeledContent("merchant.insightNavigation.host", value: host) }
                if let category = item.category, !category.isEmpty { Text(verbatim: category).font(.subheadline) }
                if let reason = item.reason, !reason.isEmpty { Text(verbatim: reason).font(.subheadline) }
                if let origin, let route = item.route(origin: origin) {
                    Button(LocalizedStringKey(kind == .topic ? "merchant.insightNavigation.topic" : "merchant.insightNavigation.partner")) { open(route) }
                        .accessibilityIdentifier("merchant.insightNavigation." + kind.rawValue + "." + String(route.targetID))
                } else {
                    Text("merchant.insightNavigation.unavailable").font(.footnote).foregroundStyle(.secondary)
                        .accessibilityIdentifier("merchant.insightNavigation.unavailable." + kind.rawValue + "." + String(index))
                }
            }
        }
    }
}

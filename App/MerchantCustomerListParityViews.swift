import SwiftUI

/// Source pages/merchant/customer/index.wxml row: name, tier badge (pending in warning), "备注" badge,
/// "lastAction · relative time" and the latest note. Phone/contact stays in the existing contact entry.
struct MerchantCustomerRowLabel: View {
    let row: MerchantCustomerListParity.Row
    let identifier: String
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(verbatim: row.name ?? MerchantOpsCopy.text("merchantOps.customer.unnamed")).font(.headline)
                if let tier = row.tierKey {
                    Text(verbatim: MerchantOpsCopy.text(tier)).font(.caption.bold())
                        .foregroundStyle(row.tierUrgent ? Color.orange : Color.secondary)
                }
                if row.latestNote != nil { Text(verbatim: MerchantOpsCopy.text("merchantOps.customer.noteBadge")).font(.caption).foregroundStyle(.secondary) }
            }
            let action = [row.lastAction, row.relative.map(Self.relative)].compactMap { $0 }.joined(separator: " · ")
            if !action.isEmpty { Text(verbatim: action).font(.subheadline).foregroundStyle(.secondary) }
            if let note = row.latestNote { Text(verbatim: note).font(.footnote).lineLimit(2) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
    static func relative(_ value: MerchantCustomerListParity.Relative) -> String {
        switch value {
        case .today: return MerchantOpsCopy.text("merchantOps.customer.relative.today")
        case .yesterday: return MerchantOpsCopy.text("merchantOps.customer.relative.yesterday")
        case .days(let n): return MerchantOpsCopy.text("merchantOps.customer.relative.days %lld", n)
        case .months(let n): return MerchantOpsCopy.text("merchantOps.customer.relative.months %lld", n)
        case .years(let n): return MerchantOpsCopy.text("merchantOps.customer.relative.years %lld", n)
        }
    }
}

/// Source customer hero subtitle and list footer.
struct MerchantCustomerListHero: View {
    let summary: MerchantCustomerListParity.Summary?
    var body: some View {
        Group {
            switch summary {
            case .totalWithMonthly(let total, let monthly): Text(verbatim: MerchantOpsCopy.text("merchantOps.customer.summary.monthly %lld %lld", total, monthly))
            case .total(let total): Text(verbatim: MerchantOpsCopy.text("merchantOps.customer.summary.total %lld", total))
            case nil: Text(verbatim: MerchantOpsCopy.text("merchantOps.customer.summary.unavailable"))
            }
        }.font(.subheadline).foregroundStyle(.secondary).accessibilityIdentifier("merchantOps.customer.summary")
    }
}
struct MerchantCustomerListFooter: View {
    let total: Int
    var body: some View {
        Text(verbatim: MerchantOpsCopy.text("merchantOps.customer.footer %lld", total)).font(.footnote).foregroundStyle(.secondary)
            .frame(maxWidth: .infinity).accessibilityIdentifier("merchantOps.customer.footer")
    }
}

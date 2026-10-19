import SwiftUI

/// Source pages/merchant/ledger/index.wxml rows: title, "who · HH:mm", state chip and right-aligned amount.
struct MerchantLedgerRowLabel: View {
    let line: MerchantLedgerParity.Line
    let identifier: String
    private var chipColor: Color {
        switch line.variant { case .warning: return .orange; case .success: return .green; case .danger: return .red; case .neutral: return .secondary }
    }
    private var amountColor: Color {
        switch line.tone { case .positive: return .green; case .negative: return .red; case .muted: return .secondary }
    }
    private func copy(_ text: String?, _ key: String?) -> String? { text ?? key.map { MerchantOpsCopy.text($0) } }
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                if let title = copy(line.title, line.titleKey) { Text(verbatim: title).font(.headline) }
                let detail = [copy(line.subtitle, line.subtitleKey), line.timeText].compactMap { $0 }.joined(separator: " · ")
                if !detail.isEmpty { Text(verbatim: detail).font(.subheadline).foregroundStyle(.secondary) }
                HStack(spacing: 6) {
                    switch line.state {
                    case .key(let key): Text(verbatim: MerchantOpsCopy.text(key))
                    case .server(let text): Text(verbatim: text)
                    }
                    if let extra = line.extraKey { Text(verbatim: MerchantOpsCopy.text(extra)).foregroundStyle(.secondary) }
                }.font(.footnote).foregroundStyle(chipColor)
            }
            Spacer(minLength: 8)
            if let amount = copy(line.amount, line.amountKey) { Text(verbatim: amount).monospacedDigit().foregroundStyle(amountColor) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}

/// Source ledger summary strip: this month's redemptions, pending and arrived, only from server totals.
struct MerchantLedgerSummaryStrip: View {
    let summary: MerchantLedgerParity.Summary
    var body: some View {
        HStack {
            cell("merchantOps.ledger.summary.count", MerchantOpsCopy.text("merchantOps.ledger.summary.countValue %lld", summary.count))
            if let pending = summary.pending { cell("merchantOps.ledger.summary.pending", pending) }
            if let arrived = summary.arrived { cell("merchantOps.ledger.summary.arrived", arrived) }
        }.accessibilityElement(children: .combine).accessibilityIdentifier("merchantOps.ledger.summary")
    }
    private func cell(_ key: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: MerchantOpsCopy.text(key)).font(.caption).foregroundStyle(.secondary)
            Text(verbatim: value).font(.headline).monospacedDigit()
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Source ledger/order-detail hero card.
struct MerchantLedgerRedemptionHero: View {
    let hero: MerchantLedgerParity.RedemptionHero
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            let title = hero.title ?? hero.titleKey.map { MerchantOpsCopy.text($0) } ?? ""
            Text(verbatim: hero.showsIncome ? MerchantOpsCopy.text("merchantOps.ledger.detail.income %@", title) : title).font(.subheadline)
            if hero.showsIncome, let amount = hero.amount ?? hero.amountKey.map({ MerchantOpsCopy.text($0) }) {
                Text(verbatim: amount).font(.largeTitle.bold()).monospacedDigit().foregroundStyle(hero.amount == nil ? .secondary : .primary)
            }
            switch hero.state {
            case .key(let key): Text(verbatim: MerchantOpsCopy.text(key)).font(.footnote.bold())
            case .server(let text): Text(verbatim: text).font(.footnote.bold())
            }
            LabeledContent(MerchantOpsCopy.text("merchantOps.ledger.detail.store"), value: hero.store ?? MerchantOpsCopy.text("merchantOps.ledger.detail.storeMissing"))
            if let accrual = hero.accrual { LabeledContent(MerchantOpsCopy.text("merchantOps.ledger.detail.accrual"), value: accrual) }
            if let refund = hero.refundKey { LabeledContent(MerchantOpsCopy.text("merchantOps.ledger.detail.refund"), value: MerchantOpsCopy.text(refund)) }
        }.accessibilityElement(children: .combine).accessibilityIdentifier("merchantOps.ledger.redemptionHero")
    }
}

/// Source ledger/batch-detail hero card.
struct MerchantLedgerBatchHero: View {
    let hero: MerchantLedgerParity.BatchHero
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: MerchantOpsCopy.text("merchantOps.ledger.batch.net %@", hero.period ?? "")).font(.subheadline)
            Text(verbatim: hero.amount ?? MerchantOpsCopy.text("merchantOps.ledger.amount.pending")).font(.largeTitle.bold()).monospacedDigit()
                .foregroundStyle(hero.amount == nil ? .secondary : .primary)
            HStack {
                Text(verbatim: MerchantOpsCopy.text(hero.stateKey)).font(.footnote.bold())
                Text(verbatim: MerchantOpsCopy.text(hero.invoiceKey)).font(.footnote).foregroundStyle(.secondary)
            }
        }.accessibilityElement(children: .combine).accessibilityIdentifier("merchantOps.ledger.batchHero")
    }
}

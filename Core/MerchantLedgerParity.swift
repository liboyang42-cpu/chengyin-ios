import Foundation

/// Source pages/merchant/ledger/index.js (redemptionRow, entryRow, batchRow, financeStateText,
/// batchStateText, stateVariant, summaryView, dayLabel). Presentation only over rows the existing
/// finance documents already validated; amounts are the server's, never summed client side.
public enum MerchantLedgerParity {
    public enum Tone: String, Equatable { case positive, negative, muted }
    public enum Variant: String, Equatable { case neutral, warning, success, danger }
    /// A state chip is either a catalog key or the server's own no-cash reason text.
    public enum State: Equatable { case key(String), server(String) }

    /// Source money(): finite numbers to two decimals, otherwise unknown.
    public static func money(_ value: MerchantBusinessValue?) -> Decimal? {
        guard let text = value?.numberText, !text.isEmpty,
              let number = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        return number
    }
    public static func yuan(_ value: Decimal, signed: Bool = false) -> String {
        var input = value, rounded = Decimal()
        NSDecimalRound(&rounded, &input, 2, .plain)
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.minimumFractionDigits = 2; formatter.maximumFractionDigits = 2
        formatter.minimumIntegerDigits = 1
        let magnitude = formatter.string(from: NSDecimalNumber(decimal: rounded < 0 ? -rounded : rounded)) ?? "0.00"
        let sign = rounded < 0 ? "-" : (signed ? "+" : "")
        return sign + "¥" + magnitude
    }

    /// Source financeStateText.
    public static func financeState(_ fields: MerchantBusinessObject) -> State {
        let display = fields.mbText("displayState")
        if display == "NO_CASH_SETTLEMENT" {
            if let reason = fields.mbText("noCashReason")?.trimmingCharacters(in: .whitespacesAndNewlines), !reason.isEmpty { return .server(reason) }
            return .key("merchantOps.ledger.state.noCash")
        }
        switch display {
        case "PENDING_SETTLEMENT": return .key(fields.mbText("settlementRoute") == "COOP_ORDER" ? "merchantOps.ledger.state.pendingTheme" : "merchantOps.ledger.state.pending")
        case "SETTLED": return .key(fields.mbText("destination") == "PERSONAL_ACCOUNT" ? "merchantOps.ledger.state.settledPersonal" : "merchantOps.ledger.state.settledPaid")
        case "ADJUSTMENT_PENDING": return .key("merchantOps.ledger.state.adjusting")
        case "ADJUSTED": return .key("merchantOps.ledger.state.adjusted")
        case "REVERSED_BEFORE_SETTLEMENT": return .key("merchantOps.ledger.state.reversed")
        case "LEDGER_ERROR": return .key("merchantOps.ledger.state.ledgerError")
        default: return .key("merchantOps.ledger.state.unknown")
        }
    }
    /// Source stateVariant: 1:1 colour mapping, no business judgement.
    public static func variant(_ displayState: String?) -> Variant {
        switch displayState {
        case "PENDING_SETTLEMENT": return .warning
        case "SETTLED": return .success
        case "ADJUSTMENT_PENDING", "LEDGER_ERROR": return .danger
        default: return .neutral
        }
    }

    public struct Line: Equatable {
        public let title: String?
        public let titleKey: String?
        public let subtitle: String?
        public let subtitleKey: String?
        public let timeText: String?
        public let state: State
        public let variant: Variant
        /// nil hides the amount column entirely (no finance permission).
        public let amount: String?
        public let amountKey: String?
        public let tone: Tone
        public let extraKey: String?
    }

    /// Source redemptionRow. Without finance read the amount column disappears and only fulfilment validity shows.
    public static func redemption(_ fields: MerchantBusinessObject, canReadFinance: Bool) -> Line {
        let parts = [fields.mbText("topicName"), fields.mbText("chapterName")].compactMap { $0 }
        let occurred = fields.mbText("occurredAt")
        let time = occurred.flatMap { $0.count >= 16 ? String($0.dropFirst(11).prefix(5)) : nil }
        let customer = fields.mbText("customerDisplayName")
        guard canReadFinance else {
            let fulfilment = fields.mbText("fulfillmentState")
            return Line(title: parts.isEmpty ? nil : parts.joined(separator: " · "), titleKey: parts.isEmpty ? "merchantOps.ledger.redemptionTitle" : nil,
                        subtitle: customer, subtitleKey: customer == nil ? "merchantOps.ledger.customerProtected" : nil, timeText: time,
                        state: .key(fulfilment == "REVERSED" ? "merchantOps.ledger.fulfilment.reversed" : (fulfilment == "ACTIVE" ? "merchantOps.ledger.fulfilment.active" : "merchantOps.ledger.fulfilment.unknown")),
                        variant: fulfilment == "ACTIVE" ? .success : .neutral, amount: nil, amountKey: nil, tone: .muted, extraKey: nil)
        }
        let value = money(fields["settlementAmount"])
        let amount: String?, amountKey: String?, tone: Tone
        if let value, value != 0 { amount = yuan(value, signed: value >= 0); amountKey = nil; tone = value < 0 ? .negative : .positive }
        else { amount = nil; amountKey = fields.mbText("displayState") == "NO_CASH_SETTLEMENT" ? "merchantOps.ledger.amount.none" : "merchantOps.ledger.amount.pending"; tone = .muted }
        return Line(title: parts.isEmpty ? nil : parts.joined(separator: " · "), titleKey: parts.isEmpty ? "merchantOps.ledger.redemptionTitle" : nil,
                    subtitle: customer, subtitleKey: customer == nil ? "merchantOps.ledger.customerProtected" : nil, timeText: time,
                    state: financeState(fields), variant: variant(fields.mbText("displayState")), amount: amount, amountKey: amountKey, tone: tone, extraKey: nil)
    }

    /// Source entryRow: source name, MM-dd and signed amount.
    public static func entry(_ fields: MerchantBusinessObject) -> Line {
        let source: String
        switch fields.mbText("source") {
        case "REDEMPTION_FEE": source = "merchantOps.ledger.source.redemptionFee"
        case "COOP_SHARE": source = "merchantOps.ledger.source.coopShare"
        case "ACTIVITY_SHARE": source = "merchantOps.ledger.source.activityShare"
        case "MERCHANT_CLAWBACK": source = "merchantOps.ledger.source.clawback"
        default: source = "merchantOps.ledger.source.adjustment"
        }
        let occurred = fields.mbText("occurredAt")
        let value = money(fields["signedAmount"])
        return Line(title: nil, titleKey: source, subtitle: nil, subtitleKey: nil,
                    timeText: occurred.flatMap { $0.count >= 10 ? String($0.dropFirst(5).prefix(5)) : nil },
                    state: financeState(fields), variant: variant(fields.mbText("displayState")),
                    amount: value.map { yuan($0, signed: $0 >= 0) }, amountKey: value == nil ? "merchantOps.ledger.amount.pending" : nil,
                    tone: value.map { $0 < 0 ? .negative : .positive } ?? .muted, extraKey: nil)
    }

    /// Source batchRow/batchStateText.
    public static func batch(_ fields: MerchantBusinessObject) -> Line {
        let display = fields.mbText("displayState"), payment = fields.mbText("paymentState"), direction = fields.mbText("netDirection")
        let stateKey: String
        if display == "LEDGER_ERROR" { stateKey = "merchantOps.ledger.state.ledgerError" }
        else if direction == "ZERO" { stateKey = "merchantOps.ledger.batch.zero" }
        else if direction == "MERCHANT_OWES_PLATFORM" { stateKey = "merchantOps.ledger.batch.owes" }
        else if fields.mbText("holdState") == "FROZEN" { stateKey = "merchantOps.ledger.batch.frozen" }
        else if payment == "PAID" { stateKey = fields.mbText("invoiceState") == "ISSUED" ? "merchantOps.ledger.batch.paidInvoiced" : "merchantOps.ledger.batch.paidNotInvoiced" }
        else if payment == "CONFIRMED" { stateKey = "merchantOps.ledger.batch.confirmed" }
        else { stateKey = "merchantOps.ledger.batch.reconciling" }
        let invoice: String?
        switch fields.mbText("invoiceState") {
        case "NONE": invoice = "merchantOps.ledger.invoice.none"
        case "ISSUED": invoice = "merchantOps.ledger.invoice.issued"
        case "RED": invoice = "merchantOps.ledger.invoice.red"
        default: invoice = nil
        }
        let value = money(fields["amountTotal"])
        return Line(title: fields.mbText("periodYm"), titleKey: nil, subtitle: nil, subtitleKey: "merchantOps.ledger.batch.publicTransfer", timeText: nil,
                    state: .key(stateKey), variant: display == "LEDGER_ERROR" ? .danger : (payment == "PAID" ? .success : .warning),
                    amount: value.map { yuan($0) }, amountKey: value == nil ? "merchantOps.ledger.amount.pending" : nil,
                    tone: value == nil ? .muted : .positive, extraKey: invoice)
    }

    /// Source summaryView: only the server's three numbers; any missing field hides the whole strip.
    public struct Summary: Equatable { public let count: Int; public let pending: String?; public let arrived: String? }
    public static func summary(_ summary: MerchantBusinessObject, canReadFinance: Bool) -> Summary? {
        guard let count = summary["count"]?.integer, count >= 0 else { return nil }
        guard canReadFinance else { return Summary(count: count, pending: nil, arrived: nil) }
        guard let pending = money(summary["pendingAmount"]), let arrived = money(summary["arrivedAmount"]) else { return nil }
        return Summary(count: count, pending: yuan(pending), arrived: yuan(arrived))
    }

    /// Source dayLabel: "MM 月 DD 日" from the server date prefix, without zone conversion.
    public static func dayParts(_ occurredAt: String?) -> (month: String, day: String)? {
        guard let value = occurredAt, value.count >= 10 else { return nil }
        let parts = value.prefix(10).split(separator: "-")
        guard parts.count == 3 else { return nil }
        return (String(parts[1]), String(parts[2]))
    }
}

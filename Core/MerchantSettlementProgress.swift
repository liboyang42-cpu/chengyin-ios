import Foundation

/// Read-only projection of the existing owned public-transfer batch. Payment,
/// invoice, hold and amount direction remain independent server facts.
public struct MerchantSettlementProgress: Equatable {
    public enum StepState: String { case done, current, pending, paused }
    public struct Step: Equatable, Identifiable {
        public let id: String
        public let state: StepState
        public let timestamp: String?
    }
    public let batchID: Int
    public let period: String
    public let amount: MerchantBusinessMoney
    public let netDirection: String
    public let paymentState: String
    public let invoiceState: String
    public let holdState: String
    public let displayState: String?
    public let paidAt: String?
    public let voucher: String?

    public init(record: MerchantBusinessRecord) throws {
        guard record.kind == .batch, let id = Int(record.id), id > 0 else { throw MerchantBusinessFailure.malformed }
        let fields = record.fields
        guard try fields.mbInt("batchId", minimum: 1) == id else { throw MerchantBusinessFailure.malformed }
        batchID = id
        period = try Self.requiredText(fields, "periodYm")
        netDirection = try Self.requiredText(fields, "netDirection")
        paymentState = try Self.requiredText(fields, "paymentState")
        invoiceState = try Self.requiredText(fields, "invoiceState")
        holdState = try Self.requiredText(fields, "holdState")
        displayState = try Self.text(fields, "displayState")
        paidAt = try Self.text(fields, "paidAt")
        voucher = try Self.text(fields, "payVoucherNo")
        amount = try MerchantBusinessMoney(fields["amountTotal"], strictString: true)
    }

    public var hasLedgerError: Bool { displayState == "LEDGER_ERROR" }
    private var positiveAmount: Bool {
        guard let raw = amount.raw, let value = Decimal(string: raw, locale: Locale(identifier: "en_US_POSIX")) else { return false }
        return value > 0
    }
    /// A timestamp or voucher alone is never payment evidence. The backend also
    /// downgrades malformed PAID batches to PENDING + LEDGER_ERROR.
    public var isPaid: Bool {
        netDirection == "PLATFORM_PAYS_MERCHANT" && paymentState == "PAID"
            && !hasLedgerError && positiveAmount && paidAt != nil && voucher != nil
    }
    public var voucherForCopy: String? { isPaid ? voucher : nil }
    public var paymentKey: String {
        if hasLedgerError { return "merchant.settlementProgress.status.ledgerError" }
        switch netDirection {
        case "ZERO": return "merchant.settlementProgress.status.zero"
        case "MERCHANT_OWES_PLATFORM": return "merchant.settlementProgress.status.owes"
        case "PLATFORM_PAYS_MERCHANT":
            if holdState == "FROZEN" { return "merchant.settlementProgress.status.frozen" }
            switch paymentState {
            case "PAID": return isPaid ? "merchant.settlementProgress.status.paid" : "merchant.settlementProgress.status.incomplete"
            case "CONFIRMED": return "merchant.settlementProgress.status.confirmed"
            case "PENDING": return "merchant.settlementProgress.status.pending"
            default: return "merchant.settlementProgress.status.unknown"
            }
        default: return "merchant.settlementProgress.status.unknown"
        }
    }
    public var invoiceKey: String {
        switch invoiceState {
        case "NONE": return "merchant.settlementProgress.invoice.none"
        case "ISSUED": return "merchant.settlementProgress.invoice.issued"
        case "RED": return "merchant.settlementProgress.invoice.red"
        default: return "merchant.settlementProgress.invoice.unknown"
        }
    }
    /// Only the platform-to-merchant direction has this payout flow. Dates are
    /// retained as server facts, never generated ETAs. Display resolves an instant
    /// through paymentTimestamp and the phone zone. No created/confirmed dates exist.
    public var steps: [Step] {
        guard netDirection == "PLATFORM_PAYS_MERCHANT", !hasLedgerError,
              ["PENDING", "CONFIRMED", "PAID"].contains(paymentState),
              ["NORMAL", "FROZEN"].contains(holdState) else { return [] }
        let completed = isPaid ? 3 : paymentState == "CONFIRMED" ? 2 : 1
        let canAdvance = paymentState != "PAID"
        return ["created", "confirmed", "paid"].enumerated().map { index, id in
            let state: StepState
            if index < completed { state = .done }
            else if canAdvance && index == completed { state = holdState == "FROZEN" ? .paused : .current }
            else { state = .pending }
            return .init(id: id, state: state, timestamp: id == "paid" && isPaid ? paidAt : nil)
        }
    }
    /// Presentation-only timestamp adapter. The unannotated Date DTO uses Jackson
    /// ISO output with an explicit offset. The existing bare Shanghai form is also
    /// accepted through the established merchant parser; no device-zone inference.
    /// This never changes isPaid, steps, or voucher-copy authorization.
    public static func paymentTimestamp(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let date = try? MerchantAftercareTime.parse(text) { return date }
        guard text.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(?:\.[0-9]{1,3})?(?:Z|[+-](?:0[0-9]|1[0-3]):[0-5][0-9]|[+-]14:00)$"#, options: .regularExpression) != nil,
              // Reject normalized impossible dates before using the existing ISO parser.
              (try? MerchantAftercareTime.parse(String(text.prefix(19)).replacingOccurrences(of: "T", with: " "))) != nil else { return nil }
        return OrderLifecycleTime.date(text)
    }
    private static func text(_ fields: MerchantBusinessObject, _ key: String) throws -> String? {
        guard let value = fields[key], value != .null else { return nil }
        guard let raw = value.string else { throw MerchantBusinessFailure.malformed }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : raw
    }
    private static func requiredText(_ fields: MerchantBusinessObject, _ key: String) throws -> String {
        guard let value = try text(fields, key) else { throw MerchantBusinessFailure.malformed }
        return value
    }
}

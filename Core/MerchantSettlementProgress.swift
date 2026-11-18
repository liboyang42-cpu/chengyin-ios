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

// MARK: - F11 自由探索结算（参考）
//
// Reference-only amounts: computed by the server for every party to see, settled offline between
// organizer and merchant. They never enter balances, withdrawals or refunds, and the UI must label
// them 「参考」. Missing money displays as ¥0.00 (MC-011 = B).

public enum FeReferenceMoney {
    /// Accepts a JSON number or decimal string. Anything else is treated as no data.
    static func decimal(_ value: CoopFlowJSON) -> Decimal? {
        guard let text = value.text?.trimmingCharacters(in: .whitespacesAndNewlines),
              text.range(of: #"^[+-]?[0-9]+(?:\.[0-9]+)?$"#, options: .regularExpression) != nil,
              let amount = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")), !amount.isNaN else { return nil }
        return amount
    }
    /// CNY, two decimals, plain rounding to the cent. No data shows ¥0.00.
    public static func display(_ amount: Decimal?) -> String {
        var value = amount ?? 0, rounded = Decimal()
        NSDecimalRound(&rounded, &value, 2, .plain)
        let negative = rounded < 0
        if negative { rounded = -rounded }
        var text = NSDecimalNumber(decimal: rounded).stringValue
        if !text.contains(".") { text += ".00" }
        else if text.split(separator: ".", omittingEmptySubsequences: false).last?.count == 1 { text += "0" }
        return (negative ? "-¥" : "¥") + text
    }
}

public enum FeReferenceSettlementStatus: String, CaseIterable {
    case open = "OPEN", settledOffline = "SETTLED_OFFLINE", void = "VOID", disputed = "DISPUTED"
    public func title(zh: Bool) -> String {
        switch self {
        case .open: return zh ? "待线下结款" : "Awaiting offline settlement"
        case .settledOffline: return zh ? "已线下结清" : "Settled offline"
        case .void: return zh ? "已作废" : "Void"
        case .disputed: return zh ? "有异议" : "Disputed"
        }
    }
}
public enum FeReferenceSupplierKind: String { case merchant = "MERCHANT", author = "AUTHOR" }
public enum FeReferenceBasis: String {
    case perkRedeemed = "PERK_REDEEMED", revshareHead = "REVSHARE_HEAD", traffic = "TRAFFIC"
    public func title(zh: Bool) -> String {
        switch self {
        case .perkRedeemed: return zh ? "权益核销" : "Perk redeemed"
        case .revshareHead: return zh ? "按人头计酬" : "Per-head share"
        case .traffic: return zh ? "引流" : "Traffic"
        }
    }
}

public struct FeReferenceSettlementRow: Equatable, Identifiable {
    public let id: Int
    public let chapterName: String?
    public let merchantName: String?
    public let supplierKind: FeReferenceSupplierKind?
    public let basis: FeReferenceBasis?
    public let quantity: Int
    public let unitAmount: Decimal?
    public let amount: Decimal?
    /// Unknown server states stay nil (shown with the server's statusText), never coerced to OPEN.
    public let status: FeReferenceSettlementStatus?
    public let statusText: String?
    public let voucherNo: String?
    public let settledAt: String?
    public init(_ json: CoopFlowJSON) throws {
        guard case .object = json, let id = json["id"].integer, id > 0 else { throw CoopFlowFailure.malformed }
        func text(_ key: String) -> String? {
            guard let raw = json[key].text?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
            return raw
        }
        self.id = id
        chapterName = text("chapterName"); merchantName = text("merchantName")
        supplierKind = text("supplierKind").flatMap(FeReferenceSupplierKind.init(rawValue:))
        basis = text("basis").flatMap(FeReferenceBasis.init(rawValue:))
        quantity = max(json["quantity"].integer ?? 0, 0)
        unitAmount = FeReferenceMoney.decimal(json["unitAmount"]); amount = FeReferenceMoney.decimal(json["amount"])
        status = text("status").flatMap(FeReferenceSettlementStatus.init(rawValue:))
        statusText = text("statusText"); voucherNo = text("voucherNo"); settledAt = text("settledAt")
    }
    public var amountText: String { FeReferenceMoney.display(amount) }
    public var unitAmountText: String { FeReferenceMoney.display(unitAmount) }
    public func statusTitle(zh: Bool) -> String { statusText ?? status?.title(zh: zh) ?? (zh ? "状态未知" : "Unknown status") }
    /// Author self-supply rows are recorded as settled with amount 0 ("作者自营，无需结算").
    public var isAuthorSelfSupply: Bool { supplierKind == .author }
}

public struct FeReferenceSettlementGroup: Equatable, Identifiable {
    public let activityID: Int
    public let activityTitle: String?
    public let payerName: String?
    public let openAmount: Decimal?
    public let settledAmount: Decimal?
    public let rows: [FeReferenceSettlementRow]
    public var id: Int { activityID }
    public init(_ json: CoopFlowJSON) throws {
        guard case .object = json, let activity = json["activityId"].integer, activity > 0 else { throw CoopFlowFailure.malformed }
        activityID = activity
        activityTitle = json["activityTitle"].text; payerName = json["payerName"].text
        openAmount = FeReferenceMoney.decimal(json["openAmount"]); settledAmount = FeReferenceMoney.decimal(json["settledAmount"])
        var seen = Set<Int>()
        // A missing or null rows field is an empty group; a wrong-type field is malformed.
        if json["rows"] == .null { rows = [] }
        else {
            guard let raw = json["rows"].rows else { throw CoopFlowFailure.malformed }
            rows = try raw.map(FeReferenceSettlementRow.init).filter { seen.insert($0.id).inserted }
        }
    }
    public var openAmountText: String { FeReferenceMoney.display(openAmount) }
    public var settledAmountText: String { FeReferenceMoney.display(settledAmount) }
}

/// data of GET api/fe/reference-settlement/merchant and .../payer.
public struct FeReferenceSettlementList: Equatable {
    public let groups: [FeReferenceSettlementGroup]
    public let totalOpenAmount: Decimal?
    public let totalSettledAmount: Decimal?
    public init(groups: [FeReferenceSettlementGroup] = [], totalOpenAmount: Decimal? = nil, totalSettledAmount: Decimal? = nil) {
        self.groups = groups; self.totalOpenAmount = totalOpenAmount; self.totalSettledAmount = totalSettledAmount
    }
    public init(_ data: CoopFlowJSON) throws {
        guard case .object = data else { throw CoopFlowFailure.malformed }
        if data["groups"] == .null { groups = [] }
        else {
            guard let raw = data["groups"].rows else { throw CoopFlowFailure.malformed }
            var seen = Set<Int>()
            groups = try raw.map(FeReferenceSettlementGroup.init).filter { seen.insert($0.activityID).inserted }
        }
        totalOpenAmount = FeReferenceMoney.decimal(data["totalOpenAmount"])
        totalSettledAmount = FeReferenceMoney.decimal(data["totalSettledAmount"])
    }
    public var totalOpenText: String { FeReferenceMoney.display(totalOpenAmount) }
    public var totalSettledText: String { FeReferenceMoney.display(totalSettledAmount) }
    public var isEmpty: Bool { groups.allSatisfy { $0.rows.isEmpty } }
}

/// Merchant-side read query and dispute request.
public enum FeReferenceSettlementRoute {
    public static let merchantPath = "api/fe/reference-settlement/merchant"
    public static let payerPath = "api/fe/reference-settlement/payer"
    public static let settlePath = "api/fe/reference-settlement/settle"
    public static let disputePath = "api/fe/reference-settlement/dispute"
    public static let readPaths: Set<String> = [merchantPath, payerPath]
}
public struct FeReferenceMerchantQuery: Equatable {
    public let status: FeReferenceSettlementStatus?
    public init(status: FeReferenceSettlementStatus? = nil) { self.status = status }
    public var queryItems: [URLQueryItem] { status.map { [URLQueryItem(name: "status", value: $0.rawValue)] } ?? [] }
}
/// POST api/fe/reference-settlement/dispute {id, note}; merchant only, OPEN rows only.
public struct FeReferenceDisputeRequest: Equatable {
    public let id: Int
    public let note: String
    public init(row: FeReferenceSettlementRow, note: String) throws {
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard row.status == .open, !row.isAuthorSelfSupply, !text.isEmpty, text.count <= 200 else { throw CoopFlowFailure.invalid("dispute") }
        id = row.id; self.note = text
    }
    public var body: CoopFlowJSON { .object(["id": .id(id), "note": .string(note)]) }
}

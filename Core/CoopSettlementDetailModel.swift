import Foundation

/// Source `pages/coop/settlement-detail` + `pages/coop/components/settlement-detail/view-model.js`
/// for the `finance` (organizer, `api/coop/finance`) and `ledger` (merchant, `api/coop/mybiz`) sources.
/// The club source is served by the club settlement detail. Every row of the response is validated
/// before any one is shown, and amounts are only ever server facts formatted to cents.
public struct CoopSettlementDetailModel: Equatable {
    public enum Perspective: String, Equatable { case host, merchant }
    public enum Tone: String, Equatable { case success, warning, danger, neutral }
    public enum Status: String, Equatable {
        // merchant (ledger)
        case awaitingCredit, creditedBalance, void, unknown
        // host (finance)
        case unsettled, amountUnknown, noIncomeDue, credited
        public func tone(_ perspective: Perspective) -> Tone {
            switch self {
            case .creditedBalance, .credited: return .success
            case .awaitingCredit, .unsettled: return .warning
            case .void: return .danger
            case .unknown, .amountUnknown, .noIncomeDue: return .neutral
            }
        }
    }
    public enum Value: Equatable {
        case money(Decimal)
        case heads(Int)
        /// Localization key suffix under `cooperation.settlement.value.`
        case key(String)
        case shareRate(Decimal)
        case fixedFee(Decimal)
        case date(String)
        case unavailable
    }
    public struct Line: Equatable {
        /// Localization key suffix under `cooperation.settlement.line.` / `cooperation.settlement.step.`
        public let key: String
        public let value: Value
        public let strong: Bool
        init(_ key: String, _ value: Value, strong: Bool = false) { self.key = key; self.value = value; self.strong = strong }
    }

    public let source: CoopFlowSettlement.Source
    public let recordID: Int
    public let perspective: Perspective
    public let topicID: Int?
    public let topicName: String?
    public let amount: Decimal?
    public let status: Status
    public let lines: [Line]
    public let timeline: [Line]
    public var tone: Tone { status.tone(perspective) }

    /// Validates every row of the source payload, then selects the first row matching `id`.
    public static func resolve(source: CoopFlowSettlement.Source, data: CoopFlowJSON, id: Int) throws -> CoopSettlementDetailModel {
        guard id > 0 else { throw CoopFlowFailure.invalid("settlement") }
        guard case .object = data, let rows = data[source == .finance ? "topics" : "settlements"].rows else { throw CoopFlowFailure.malformed }
        for row in rows { guard source == .finance ? validHost(row) : validMerchant(row) else { throw CoopFlowFailure.malformed } }
        guard let row = rows.first(where: { $0[source == .finance ? "topicId" : "id"].integer == id }) else { throw CoopFlowFailure.unavailable }
        return source == .finance ? host(row, id: id) : merchant(row, id: id)
    }

    // MARK: validation (source settlement-detail/index.js)
    static func number(_ v: CoopFlowJSON) -> Decimal? { if case .number(let n) = v, !n.isNaN { return n }; return nil }
    static func nonNegative(_ v: CoopFlowJSON) -> Bool { (number(v) ?? -1) >= 0 }
    static func positiveInteger(_ v: CoopFlowJSON) -> Bool {
        guard let n = number(v) else { return false }
        return n > 0 && n == n.rounded0 && (v.integer ?? 0) > 0
    }
    static func code(_ v: CoopFlowJSON) -> Int? {
        switch v {
        case .number(let n): return [0, 1, 2].first { Decimal($0) == n }
        case .string(let s): return ["0": 0, "1": 1, "2": 2][s.trimmingCharacters(in: .whitespaces)]
        default: return nil
        }
    }
    static func validMerchant(_ row: CoopFlowJSON) -> Bool {
        guard case .object = row, positiveInteger(row["id"]), nonNegative(row["verifiedSales"]), nonNegative(row["amount"]),
              let heads = number(row["verifiedHeads"]), heads >= 0, heads == heads.rounded0,
              code(row["status"]) != nil, let mode = code(row["shareMode"]) else { return false }
        if mode == 1 { guard let rate = number(row["shareRate"]), rate >= 0, rate <= 100 else { return false } }
        if mode == 2 { guard nonNegative(row["fixedFee"]) else { return false } }
        return true
    }
    static func validHost(_ row: CoopFlowJSON) -> Bool {
        guard case .object = row, positiveInteger(row["topicId"]), let settled = row["settled"].flag, row["myIncomeArrived"].flag != nil,
              ["totalSales", "verifiedSales", "platformAmount", "merchantTotal"].allSatisfy({ nonNegative(row[$0]) }) else { return false }
        return settled ? nonNegative(row["myIncome"]) : row["myIncome"] == .null
    }

    // MARK: view models (source view-model.js)
    static func date(_ v: CoopFlowJSON) -> String? {
        guard let text = v.text, !text.isEmpty else { return nil }
        return String(text.prefix(16)).replacingOccurrences(of: "T", with: " ")
    }
    static func merchant(_ row: CoopFlowJSON, id: Int) -> CoopSettlementDetailModel {
        let status: Status
        switch code(row["status"]) { case 0?: status = .awaitingCredit; case 1?: status = .creditedBalance; case 2?: status = .void; default: status = .unknown }
        let amount = number(row["amount"]).map(CoopFinanceProfit.round)
        var lines: [Line] = []
        switch (row["payeeType"].text ?? "").trimmingCharacters(in: .whitespaces).lowercased() {
        case "club": lines.append(Line("payee", .key("payee.club")))
        case "", "merchant": lines.append(Line("payee", .key("payee.merchant")))
        default: break
        }
        if let sales = number(row["verifiedSales"]) { lines.append(Line("verifiedSales", .money(CoopFinanceProfit.round(sales)))) }
        if let heads = row["verifiedHeads"].integer { lines.append(Line("verifiedHeads", .heads(heads))) }
        switch code(row["shareMode"]) {
        case 0?: lines.append(Line("shareRule", .key("share.traffic")))
        case 1?: lines.append(Line("shareRule", number(row["shareRate"]).map(Value.shareRate) ?? .key("share.rate")))
        case 2?: lines.append(Line("shareRule", number(row["fixedFee"]).map { .fixedFee(CoopFinanceProfit.round($0)) } ?? .key("share.fixed")))
        default: break
        }
        lines.append(Line("income", amount.map(Value.money) ?? .unavailable, strong: true))
        var timeline: [Line] = []
        if let created = date(row["createTime"]) { timeline.append(Line("created", .date(created))) }
        if let settled = date(row["settleTime"]) { timeline.append(Line("settled", .date(settled))) }
        switch status {
        case .awaitingCredit: timeline.append(date(row["payableTime"]).map { Line("payable", .date($0)) } ?? Line("payableWaiting", .key("timeUnknown")))
        case .creditedBalance: timeline.append(Line("paid", date(row["payoutTime"]).map(Value.date) ?? .key("arrivalUnknown")))
        case .void: timeline.append(Line("void", date(row["updateTime"]).map(Value.date) ?? .key("timeUnknown")))
        default: if timeline.isEmpty { timeline.append(Line("unknown", .key("refreshLater"))) }
        }
        let topic = row["topicId"].integer
        return .init(source: .mybiz, recordID: id, perspective: .merchant, topicID: topic, topicName: nonEmpty(row["topicName"].text),
                     amount: amount, status: status, lines: lines, timeline: timeline)
    }
    static func host(_ row: CoopFlowJSON, id: Int) -> CoopSettlementDetailModel {
        let settled = row["settled"].flag
        let income = settled == true ? number(row["myIncome"]).map(CoopFinanceProfit.round) : nil
        let status: Status
        if settled == nil { status = .unknown }
        else if settled == false { status = .unsettled }
        else if let income { status = income == 0 ? .noIncomeDue : row["myIncomeArrived"].flag == true ? .credited : .awaitingCredit }
        else { status = .amountUnknown }
        var lines: [Line] = []
        for (key, field) in [("totalSales", "totalSales"), ("verifiedSales", "verifiedSales"), ("platform", "platformAmount"), ("merchant", "merchantTotal")] {
            if let value = number(row[field]) { lines.append(Line(key, .money(CoopFinanceProfit.round(value)))) }
        }
        lines.append(Line("income", income.map(Value.money) ?? .unavailable, strong: true))
        var timeline = [Line(settled == nil ? "hostSettlementUnknown" : settled == true ? "hostSettled" : "hostUnsettled", .key("currentState"))]
        switch status {
        case .credited: timeline.append(Line("hostCredited", .key("arrived")))
        case .awaitingCredit: timeline.append(Line("hostAwaiting", .key("awaitingArrival")))
        case .noIncomeDue: timeline.append(Line("hostNoIncome", .key("zeroShare")))
        default: break
        }
        if let payable = date(row["merchantPayableTime"]) { timeline.append(Line("merchantPayable", .date(payable))) }
        if let payout = date(row["merchantPayoutTime"]) { timeline.append(Line("merchantPaid", .date(payout))) }
        return .init(source: .finance, recordID: id, perspective: .host, topicID: row["topicId"].integer, topicName: nonEmpty(row["topicName"].text),
                     amount: income, status: status, lines: lines, timeline: timeline)
    }
    private static func nonEmpty(_ text: String?) -> String? { text?.isEmpty == false ? text : nil }

    /// Source permission detection: codes 2/401/403 or the sign-in / organizer-only messages clear the detail.
    public static func isPermission(_ error: Error) -> Bool {
        if error as? APIError == .unauthorized { return true }
        if case CoopFlowFailure.server(let code, let message)? = error as? CoopFlowFailure {
            return [2, 401, 403].contains(code) || message == "请先登录" || message == "仅主理人与联席主理人可查看分润"
        }
        return error as? CoopFlowFailure == .permission
    }
}

private extension Decimal {
    var rounded0: Decimal { var input = self, output = Decimal(); NSDecimalRound(&output, &input, 0, .plain); return output }
}

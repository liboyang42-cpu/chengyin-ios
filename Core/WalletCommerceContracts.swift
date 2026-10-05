import Foundation

/// Missing money never means zero. No currency is inferred from locale, market or endpoint.
public struct WalletAmount: Decodable, Equatable {
    public let value: Decimal
    public init(_ value: Decimal) { self.value = value }
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) {
            let text = s.trimmingCharacters(in: .whitespacesAndNewlines)
            guard text.range(of: #"^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$"#, options: .regularExpression) != nil,
                  let d = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")), !d.isNaN else { throw APIError.malformedResponse }
            value = d
        } else { value = try c.decode(Decimal.self) }
        guard !value.isNaN else { throw APIError.malformedResponse }
    }
    public var text: String { NSDecimalNumber(decimal: value).stringValue }
}
public enum WalletDirection: String { case income, expense, unknown }
public struct WalletLedgerRow: Decodable, Equatable, Identifiable {
    public let id: Int
    public let changeBalance: WalletAmount?
    public let afterBalance: WalletAmount?
    public let changePoints: WalletAmount?
    public let afterPoints: WalletAmount?
    public let changeType: Int?
    public let eventType: Int?
    public let changeReason: String?
    public let createTime: String?
    public let currency: String?
    public var incomeEventKey: String {
        switch eventType {
        case 1: return "wallet.event.topicShare"
        case 2: return "wallet.event.activityShare"
        case 3: return "wallet.event.withdrawalRequest"
        case 4: return "wallet.event.withdrawalRejected"
        case 5: return "wallet.event.merchantReferral"
        default: return "wallet.event.other"
        }
    }
    public var incomeDirection: WalletDirection {
        changeType == 1 ? .income : changeType == 2 ? .expense : .unknown
    }
    /// The legacy asset/points contract falls back to the sign only when type is absent.
    public var assetDirection: WalletDirection {
        if changeType != nil { return incomeDirection }
        guard let amount = changePoints ?? changeBalance else { return .unknown }
        return amount.value < 0 ? .expense : .income
    }
    public func signedText(points: Bool, income: Bool) -> String? {
        guard let amount = points ? changePoints : changeBalance else { return nil }
        let direction = income ? incomeDirection : assetDirection
        let magnitude = NSDecimalNumber(decimal: amount.value < 0 ? -amount.value : amount.value).stringValue
        switch direction { case .income: return "+" + magnitude; case .expense: return "−" + magnitude; case .unknown: return amount.text }
    }
    // No status field: a debit is not a pending payout, and an income row is not payment proof.
}
public struct WalletFundsStages: Decodable, Equatable {
    public struct Period: Decodable, Equatable {
        public let availableDate: String
        public let amount: WalletAmount
    }
    public let pendingSettlement: WalletAmount
    public let disputed: WalletAmount
    public let withdrawable: WalletAmount
    public let complaintPeriod: [Period]
    public let amountsKnown: Bool
    public let currency: String?
    private enum CodingKeys: String, CodingKey { case pendingSettlement, disputed, withdrawable, complaintPeriod, amountsKnown, currency }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pendingSettlement = try c.decode(WalletAmount.self, forKey: .pendingSettlement)
        disputed = try c.decode(WalletAmount.self, forKey: .disputed)
        withdrawable = try c.decode(WalletAmount.self, forKey: .withdrawable)
        let periods = try c.decode([Period].self, forKey: .complaintPeriod)
        guard [pendingSettlement, disputed, withdrawable].allSatisfy({ $0.value >= 0 }),
              periods.allSatisfy({ $0.amount.value >= 0 && Self.validDate($0.availableDate) }) else { throw APIError.malformedResponse }
        complaintPeriod = periods.filter { $0.amount.value > 0 }
        amountsKnown = try c.decodeIfPresent(Bool.self, forKey: .amountsKnown) ?? true
        currency = try c.decodeIfPresent(String.self, forKey: .currency)
    }
    private static func validDate(_ value: String) -> Bool {
        let format = DateFormatter(); format.locale = Locale(identifier: "en_US_POSIX")
        format.calendar = Calendar(identifier: .gregorian); format.timeZone = TimeZone(secondsFromGMT: 0)
        format.dateFormat = "yyyy-MM-dd"; format.isLenient = false
        return value.count == 10 && format.date(from: value).map { format.string(from: $0) == value } == true
    }
}
public struct WalletPage<Row> {
    public let rows: [Row]
    public let total: Int?
    /// nil means the source wrapper offers no paging contract; do not invent load-more.
    public let page: Int?
    public let pageSize: Int?
    public func hasMore(loadedCount: Int) -> Bool {
        guard let pageSize, page != nil else { return false }
        if let total { return loadedCount < total && !rows.isEmpty }
        return rows.count >= pageSize
    }
}
public enum WalletIncomeFilter: String, CaseIterable { case all = "", create = "1", brand = "2" }
public enum WalletLedgerKind: Equatable { case balance, assetPoints, points, income(WalletIncomeFilter) }
public struct WalletProduct: Decodable, Equatable, Identifiable {
    public let id: Int
    public let productName: String?
    public let price: WalletAmount? // Points, NOT currency or minor units.
    public let originalPrice: WalletAmount?
    public let stock: Int?
    public let unit: String?
    public let pic: String?
    public let albumPics: String?
    public let detailHtml: String?
    public let skuList: [WalletProductSKU]?
}
public struct WalletProductSKU: Decodable, Equatable, Identifiable {
    public let id: Int
    public let skuName: String?
    public let price: WalletAmount?
    public let stock: Int?
}
public struct WalletCartItem: Decodable, Equatable, Identifiable {
    public let id: Int
    public let productId: Int
    public let skuId: Int
    public let quantity: Int
    public let productName: String?
    public let skuName: String?
    public let price: WalletAmount?
    public var subtotalPoints: Decimal? { price.map { $0.value * Decimal(quantity) } }
}
/// Deliberately discard names, full phone numbers, street addresses and bank names at decode.
public struct WalletAddressReference: Decodable, Equatable {
    public let id: Int
    public let maskedPhone: String?
    private enum CodingKeys: String, CodingKey { case id, mobilePhone }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        guard id > 0 else { throw APIError.malformedResponse }
        maskedPhone = Self.mask(try c.decodeIfPresent(String.self, forKey: .mobilePhone))
    }
    static func mask(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value.count > 4 ? "•••• " + String(value.suffix(4)) : "••••"
    }
}
public struct WalletCheckoutPreview: Decodable, Equatable {
    public let cartType: Int?
    public let productAmount: WalletAmount?
    public let productQuantity: Int?
    public let productWeight: WalletAmount?
    public let deliveryFee: WalletAmount?
    public let taxFee: WalletAmount?
    public let totalAmount: WalletAmount?
    public let pointBalance: WalletAmount?
    public let productList: [WalletCartItem]?
    public let address: WalletAddressReference?
    public var requiredPoints: Decimal? {
        guard var total = totalAmount?.value, total >= 0 else { return nil }
        var rounded = Decimal(); NSDecimalRound(&rounded, &total, 0, .up); return rounded
    }
    public var hasEnoughPoints: Bool? {
        guard let requiredPoints, let pointBalance else { return nil }
        return pointBalance.value >= requiredPoints
    }
}
public struct WalletWithdrawalRecord: Decodable, Equatable, Identifiable {
    public let id: Int
    public let amount: WalletAmount
    public let status: Int
    public let maskedAccount: String?
    public let createTime: String?
    public let currency: String?
    public var statusKey: String { ["wallet.pendingReview", "wallet.approved", "wallet.rejected", "wallet.paid"][status] }
    private enum CodingKeys: String, CodingKey { case id, withdrawalAmount, amount, status, bankAccount, createTime, currency }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        amount = try c.decodeIfPresent(WalletAmount.self, forKey: .withdrawalAmount) ?? c.decode(WalletAmount.self, forKey: .amount)
        status = try c.decode(Int.self, forKey: .status)
        guard id > 0, amount.value > 0, (0...3).contains(status) else { throw APIError.malformedResponse }
        maskedAccount = WalletAddressReference.mask(try c.decodeIfPresent(String.self, forKey: .bankAccount))
        createTime = try c.decodeIfPresent(String.self, forKey: .createTime)
        currency = try c.decodeIfPresent(String.self, forKey: .currency)
    }
}

/// Existing source rule explanation, not a new reward task or a claim/grant endpoint.
public struct WalletPointsTask: Decodable, Equatable, Identifiable {
    public let id: Int
    public let eventType: Int?
    public let title: String?
    public let description: String?
    public let value: WalletAmount?
    public let pointsNum: Int?
    public let status: Int?
    public var isEarnTask: Bool { status == 1 && eventType != 14 }
}

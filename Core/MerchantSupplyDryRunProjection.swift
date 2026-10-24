import Foundation

/// Exclusive C07 projection: SKU / validity / hours-capacity dry-run.
/// Never writes stock or reservation. Null hours on a bookable SKU are UNKNOWN
/// (do not assume 24h). Asia/Shanghai is the server clock. Blank originalRequestID
/// is Optional.none / JSON null, never an empty-string coercion.
public enum MerchantSupplyDryRunOutcome: String, Equatable, Sendable {
    case accept = "ACCEPT"
    case reject = "REJECT"
    case unknown = "UNKNOWN"
}

public struct MerchantSupplyDryRunFact: Equatable, Sendable {
    public let skuID: Int64?
    public let merchantID: Int64?
    public let stock: Int64?
    public let bookable: Bool
    public let slotMinutes: Int?
    public let capacityPerSlot: Int?
    public let capacityTotal: Int?
    public let capacityReserved: Int?
    public let validStartInclusive: Date?
    public let validEndExclusive: Date?
    public let hoursOpenMinute: Int?
    public let hoursCloseMinute: Int?
    public let originalRequestID: String?
    public init(skuID: Int64?, merchantID: Int64?, stock: Int64?, bookable: Bool,
                slotMinutes: Int?, capacityPerSlot: Int?, capacityTotal: Int?,
                capacityReserved: Int?, validStartInclusive: Date?, validEndExclusive: Date?,
                hoursOpenMinute: Int?, hoursCloseMinute: Int?, originalRequestID: String?) {
        self.skuID = skuID; self.merchantID = merchantID; self.stock = stock
        self.bookable = bookable; self.slotMinutes = slotMinutes
        self.capacityPerSlot = capacityPerSlot; self.capacityTotal = capacityTotal
        self.capacityReserved = capacityReserved
        self.validStartInclusive = validStartInclusive
        self.validEndExclusive = validEndExclusive
        self.hoursOpenMinute = hoursOpenMinute; self.hoursCloseMinute = hoursCloseMinute
        self.originalRequestID = MerchantSupplyDryRunProjection.parse(originalRequestID)
    }
}

public struct MerchantSupplyDryRunDecision: Equatable, Sendable {
    public let outcome: MerchantSupplyDryRunOutcome
    public let originalRequestID: String?
    public let remainingCapacity: Int
    public let writesStock: Bool
    public let writesReservation: Bool
    public let reason: String?
    public var grantsIssue: Bool { outcome == .accept && !writesStock && !writesReservation }
    public func jsonObject() -> [String: Any] {
        [
            "outcome": outcome.rawValue,
            "originalRequestID": originalRequestID.map { $0 as Any } ?? NSNull(),
            "remainingCapacity": remainingCapacity,
            "writesStock": writesStock,
            "writesReservation": writesReservation,
            "reason": reason.map { $0 as Any } ?? NSNull()
        ]
    }
}

public struct MerchantSupplyDryRunProjection: Equatable {
    public static let deskReceipt = "merchantDesk.receipt"
    public struct WaitingSource: Error, Equatable {
        public let capability: String
    }
    public static let shanghaiTimeZone = TimeZone(identifier: "Asia/Shanghai")!
    public private(set) var holdCountByRequestID: [String: Int] = [:]
    public private(set) var originalIntentByRequestID: [String: MerchantSupplyDryRunDecision] = [:]
    public init() {}
    public static func parse(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 64 else { return nil }
        return trimmed
    }
    public static func minuteOfDay(serverNow: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = shanghaiTimeZone
        let parts = calendar.dateComponents([.hour, .minute], from: serverNow)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
    /// Dry-run only. ACCEPT does not write stock. Duplicate originalRequestID does not double-hold.
    public mutating func evaluate(_ fact: MerchantSupplyDryRunFact?, serverNow: Date?,
                                  requestedQty: Int) -> MerchantSupplyDryRunDecision {
        let decision = compute(fact, serverNow: serverNow, requestedQty: requestedQty)
        if let requestID = decision.originalRequestID, decision.outcome != .unknown {
            if originalIntentByRequestID[requestID] == nil {
                originalIntentByRequestID[requestID] = decision
            }
            if decision.outcome == .accept, holdCountByRequestID[requestID] == nil {
                holdCountByRequestID[requestID] = 1
            }
        }
        return decision
    }
    public func holdCount(originalRequestID: String) -> Int {
        guard let requestID = Self.parse(originalRequestID) else { return 0 }
        return holdCountByRequestID[requestID] ?? 0
    }
    /// UNKNOWN recover keeps the original intent and does not mint a new request.
    public func recoverOriginal(originalRequestID: String) -> MerchantSupplyDryRunDecision {
        let requestID = Self.parse(originalRequestID)
        if let requestID, let original = originalIntentByRequestID[requestID] {
            return original
        }
        return Self.unknown(requestID, "original intent unknown")
    }
    /// Read IMerchantDeskService.receipt. A matching NOT_FOUND wire is returned and does not hold.
    /// Does not save a SKU. A numeric ownerMemberId for another member is not this receipt.
    /// The public receipt does not echo ownerMemberId, so a missing owner stays on the wire.
    public indirect enum Wire: Equatable, Sendable {
        case null
        case bool(Bool)
        case int(Int64)
        case string(String)
        case object([String: Wire])
    }
    public enum WireFailure: Error, Equatable {
        case waitingSource(String)
        case transport(String)
        case forbidden(String)
        case notThisRequest
    }
    public func recoverFromDeskReceipt(
        ownerMemberID: Int64?,
        requestID: String?,
        storeID: Int64? = nil,
        expectedSkuID: Int64? = nil,
        receipt: ((Int64, String) async throws -> Wire)?
    ) async throws -> Wire? {
        guard let ownerMemberID, ownerMemberID > 0, let id = Self.parse(requestID) else { return nil }
        if let storeID, storeID <= 0 {
            return nil
        }
        guard let receipt else {
            throw WireFailure.waitingSource(Self.deskReceipt)
        }
        let found = try await receipt(ownerMemberID, id)
        guard case .object(let fields) = found else { throw WireFailure.notThisRequest }
        guard case .string(let request) = fields["requestId"], request == id else {
            throw WireFailure.notThisRequest
        }
        if case .string(let state) = fields["state"], state == "NOT_FOUND" {
            return found
        }
        if case .int(let owner) = fields["ownerMemberId"], owner != ownerMemberID {
            throw WireFailure.notThisRequest
        }
        if case .int(let store) = fields["storeId"], let storeID, store != storeID {
            throw WireFailure.notThisRequest
        }
        guard case .string(let state) = fields["state"], state == "APPLIED",
              case .string(let action) = fields["action"], action == "SKU_SAVE",
              case .string(let targetType) = fields["targetType"], targetType == "pms_sku",
              case .int(let target) = fields["targetId"], target > 0 else {
            throw WireFailure.notThisRequest
        }
        if let expectedSkuID, target != expectedSkuID {
            throw WireFailure.notThisRequest
        }
        return found
    }
    /// The original journal does not keep the form. Restart cannot rebuild the save body.
    public func skuSaveRestartPayload(originalRequestID: String) -> String? {
        _ = Self.parse(originalRequestID)
        return nil
    }

    private func compute(_ fact: MerchantSupplyDryRunFact?, serverNow: Date?,
                         requestedQty: Int) -> MerchantSupplyDryRunDecision {
        guard let serverNow else {
            return Self.unknown(Self.parse(fact?.originalRequestID), "serverNow missing")
        }
        guard let fact else { return Self.unknown(nil, "supply fact missing") }
        let requestID = fact.originalRequestID
        if requestID == nil || fact.skuID == nil || fact.skuID! <= 0
            || fact.merchantID == nil || fact.merchantID! <= 0 {
            return Self.unknown(requestID, "sku or originalRequestID missing")
        }
        if requestedQty < 1 {
            return Self.reject(requestID, 0, "requested qty must be at least 1")
        }
        guard let stock = fact.stock else { return Self.unknown(requestID, "stock missing") }
        if stock < Int64(requestedQty) {
            return Self.reject(requestID, remaining(fact), "stock insufficient")
        }
        guard let start = fact.validStartInclusive, let end = fact.validEndExclusive else {
            return Self.unknown(requestID, "validity window missing")
        }
        if !(start < end) { return Self.unknown(requestID, "validity window not half-open") }
        if serverNow < start || !(serverNow < end) {
            return Self.reject(requestID, remaining(fact), "outside validity window")
        }
        if fact.bookable {
            let booking = evaluateBooking(fact, serverNow: serverNow, requestedQty: requestedQty,
                                          requestID: requestID)
            if booking.outcome != .accept { return booking }
        }
        return Self.accept(requestID, remaining(fact))
    }
    private func evaluateBooking(_ fact: MerchantSupplyDryRunFact, serverNow: Date,
                                 requestedQty: Int, requestID: String?) -> MerchantSupplyDryRunDecision {
        guard let slot = fact.slotMinutes, let perSlot = fact.capacityPerSlot else {
            return Self.unknown(requestID, "booking rule missing")
        }
        if slot < 15 || slot > 480 || slot % 15 != 0 {
            return Self.reject(requestID, remaining(fact), "slot minutes invalid")
        }
        if perSlot < 1 || perSlot > 1000 {
            return Self.reject(requestID, remaining(fact), "bookable capacity per slot must be 1-1000")
        }
        guard let total = fact.capacityTotal, let reserved = fact.capacityReserved else {
            return Self.unknown(requestID, "hours-capacity slot missing")
        }
        if reserved < 0 || total < 0 || reserved > total {
            return Self.unknown(requestID, "capacity slot inconsistent")
        }
        let remainingHours = total - reserved
        if remainingHours < requestedQty {
            return Self.reject(requestID, remainingHours, "hours-capacity exhausted")
        }
        guard let open = fact.hoursOpenMinute, let close = fact.hoursCloseMinute else {
            return Self.unknown(requestID, "business hours missing")
        }
        if open < 0 || close < 0 || open >= close || close > 24 * 60 {
            return Self.unknown(requestID, "business hours not a documented daytime window")
        }
        let minuteOfDay = Self.minuteOfDay(serverNow: serverNow)
        if minuteOfDay < open || minuteOfDay >= close {
            return Self.reject(requestID, remainingHours, "outside business hours")
        }
        return Self.accept(requestID, remainingHours)
    }
    private func remaining(_ fact: MerchantSupplyDryRunFact) -> Int {
        if fact.bookable, let total = fact.capacityTotal, let reserved = fact.capacityReserved {
            return max(0, total - reserved)
        }
        guard let stock = fact.stock, stock <= Int64(Int.max) else { return 0 }
        return Int(stock)
    }
    private static func accept(_ requestID: String?, _ remaining: Int) -> MerchantSupplyDryRunDecision {
        MerchantSupplyDryRunDecision(outcome: .accept, originalRequestID: requestID,
                                     remainingCapacity: remaining, writesStock: false,
                                     writesReservation: false, reason: "dry-run accept")
    }
    private static func reject(_ requestID: String?, _ remaining: Int, _ reason: String)
        -> MerchantSupplyDryRunDecision {
        MerchantSupplyDryRunDecision(outcome: .reject, originalRequestID: requestID,
                                     remainingCapacity: remaining, writesStock: false,
                                     writesReservation: false, reason: reason)
    }
    private static func unknown(_ requestID: String?, _ reason: String) -> MerchantSupplyDryRunDecision {
        MerchantSupplyDryRunDecision(outcome: .unknown, originalRequestID: requestID,
                                     remainingCapacity: 0, writesStock: false,
                                     writesReservation: false, reason: reason)
    }
}

/// Desk product SKU save. `access/me` staff is not the merchant owner.
/// The frozen intent is the save body. A later form is not the restarted request.
public struct MerchantSkuSaveJourney: Equatable, Sendable {
    public struct Intent: Equatable, Sendable {
        public let requestID: String
        public let skuID: Int64
        public let productID: Int64
        public let skuName: String
        public let price: String
        public let stock: Int
        public let originalPrice: String?
        public let pic: String?
        public let bookable: Bool
        public let slotMinutes: Int
        public let capacityPerSlot: Int
        public let ruleVersion: Int?
    }

    public struct Recovery: Equatable, Sendable {
        public let requestID: String
        public let skuID: Int64
        public let payload: String?
        public let outcome: String
    }

    public init() {}

    public func freeze(access: MerchantBusinessAccess, accountID: Int64, productID: Int64,
                       skuID: Int64, requestID: String, skuName: String, price: String, stock: Int,
                       originalPrice: String? = nil, pic: String? = nil, bookable: Bool = false,
                       slotMinutes: Int = 60, capacityPerSlot: Int = 0, ruleVersion: Int? = nil) -> Intent? {
        guard access.role == "MERCHANT_OWNER", accountID > 0,
              productID > 0, skuID > 0, Int(exactly: productID) != nil, Int(exactly: skuID) != nil,
              MerchantSupplyDryRunProjection.parse(requestID) != nil,
              (1...60).contains(skuName.count), (0...1_000_000).contains(stock),
              (15...480).contains(slotMinutes), slotMinutes % 15 == 0,
              (0...1000).contains(capacityPerSlot), !bookable || capacityPerSlot > 0,
              let normalizedPrice = Self.normalizedMoney(price) else { return nil }
        let normalizedOriginal = originalPrice.flatMap(Self.normalizedMoney)
        if let originalPrice, Self.javaTrim(originalPrice).isEmpty == false, normalizedOriginal == nil { return nil }
        let normalizedPic = pic.map(Self.javaTrim).flatMap { $0.isEmpty ? nil : $0 }
        return Intent(requestID: requestID, skuID: skuID, productID: productID,
                      skuName: skuName, price: normalizedPrice, stock: stock,
                      originalPrice: normalizedOriginal, pic: normalizedPic, bookable: bookable,
                      slotMinutes: slotMinutes, capacityPerSlot: capacityPerSlot, ruleVersion: ruleVersion)
    }

    public func detailRequest(productID: Int64) -> MerchantBusinessRequest? {
        guard let product = Int(exactly: productID), product > 0 else { return nil }
        return .json("api/merchant/desk/products/detail", ["productId": .int(product)])
    }

    public func saveRequest(_ intent: Intent, currentFormPrice: String) -> MerchantBusinessRequest? {
        _ = currentFormPrice
        guard let product = Int(exactly: intent.productID), let sku = Int(exactly: intent.skuID) else { return nil }
        var fields: MerchantBusinessObject = [
            "requestId": .string(intent.requestID),
            "productId": .int(product),
            "skuId": .int(sku),
            "skuName": .string(intent.skuName),
            "price": .string(intent.price),
            "stock": .int(intent.stock),
            "bookable": .bool(intent.bookable),
            "slotMinutes": .int(intent.slotMinutes),
            "capacityPerSlot": .int(intent.capacityPerSlot)
        ]
        if let originalPrice = intent.originalPrice { fields["originalPrice"] = .string(originalPrice) }
        if let pic = intent.pic { fields["pic"] = .string(pic) }
        if let ruleVersion = intent.ruleVersion { fields["ruleVersion"] = .int(ruleVersion) }
        return .json("api/merchant/desk/products/sku/save", fields)
    }

    /// Java `String.trim` drops code points <= U+0020 only. The remainder must match end to end.
    public static func normalizedMoney(_ raw: String) -> String? {
        let text = javaTrim(raw)
        guard whole(text, #"^[0-9]+(?:\.[0-9]{1,2})?\z"#),
              let amount = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")),
              let limit = Decimal(string: "10000000", locale: Locale(identifier: "en_US_POSIX")),
              amount <= limit else { return nil }
        return text
    }

    static func javaTrim(_ raw: String) -> String {
        let scalars = raw.unicodeScalars
        var start = scalars.startIndex
        var end = scalars.endIndex
        while start < end, scalars[start].value <= 32 { start = scalars.index(after: start) }
        while end > start {
            let previous = scalars.index(before: end)
            if scalars[previous].value > 32 { break }
            end = previous
        }
        return String(String.UnicodeScalarView(scalars[start..<end]))
    }

    static func whole(_ text: String, _ pattern: String) -> Bool {
        guard let range = text.range(of: pattern, options: .regularExpression) else { return false }
        return range.lowerBound == text.startIndex && range.upperBound == text.endIndex
    }

    public func accessRequest() -> MerchantBusinessRequest {
        .empty("api/merchant/access/me")
    }

    public func receiptRequest(requestID: String) -> MerchantBusinessRequest? {
        guard let id = MerchantSupplyDryRunProjection.parse(requestID) else { return nil }
        return .json("api/merchant/desk/receipt", ["requestId": .string(id)])
    }

    public struct SkuRow: Equatable, Sendable {
        public let skuID: Int64
        public let skuName: String
        public let price: String
        public let stock: Int
    }

    /// `productDetail` nests `skus`. The later form is not a saved row.
    public func readBack(detail: MerchantBusinessValue, intent: Intent, laterFormPrice: String) -> SkuRow? {
        _ = laterFormPrice
        guard let product = detail.object,
              product["productId"]?.integer == Int(exactly: intent.productID),
              let skus = product["skus"]?.array else { return nil }
        for sku in skus {
            guard let row = sku.object,
                  let skuID = row["skuId"]?.integer, Int64(skuID) == intent.skuID,
                  row["skuName"]?.string == intent.skuName,
                  row["stock"]?.integer == intent.stock,
                  let wirePrice = row["price"], sameMoney(wirePrice, intent.price),
                  ruleMatches(row, intent) else { continue }
            return SkuRow(skuID: intent.skuID, skuName: intent.skuName, price: intent.price, stock: intent.stock)
        }
        return nil
    }

    /// Same amount: frozen `88.00` matches JSON number 88. Decimal compare, never Double.
    private func sameMoney(_ wire: MerchantBusinessValue, frozen: String) -> Bool {
        guard let left = money(wire), let right = money(frozen) else { return false }
        return left == right
    }

    private func money(_ value: MerchantBusinessValue) -> Decimal? {
        switch value {
        case .number(let amount): return amount
        case .string(let text): return money(text)
        default: return nil
        }
    }

    private func money(_ text: String) -> Decimal? {
        guard let normalized = Self.normalizedMoney(text) else { return nil }
        return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
    }

    private func ruleMatches(_ row: [String: MerchantBusinessValue], _ intent: Intent) -> Bool {
        guard row["slotMinutes"]?.integer == intent.slotMinutes,
              row["capacityPerSlot"]?.integer == intent.capacityPerSlot,
              sameFlag(row["bookable"], intent.bookable),
              sameOptionalText(row["pic"], intent.pic) else { return false }
        if let original = intent.originalPrice {
            guard let wire = row["originalPrice"], wire != .null, sameMoney(wire, original) else { return false }
        } else if let wire = row["originalPrice"], wire != .null {
            return false
        }
        return versionMatches(row["ruleVersion"], intent.ruleVersion)
    }

    /// Frozen version stays v. A successful CAS read is v or v+1. The same key does not become v+2.
    /// A new rule is inserted at version 1.
    private func versionMatches(_ wire: MerchantBusinessValue?, _ frozen: Int?) -> Bool {
        let shown = wire == nil || wire == .null ? nil : wire?.integer
        if let frozen { return shown == frozen || shown == frozen + 1 }
        return shown == nil || shown == 1
    }

    private func sameFlag(_ wire: MerchantBusinessValue?, _ expected: Bool) -> Bool {
        if wire?.bool == expected { return true }
        return wire?.integer == (expected ? 1 : 0)
    }

    private func sameOptionalText(_ wire: MerchantBusinessValue?, _ expected: String?) -> Bool {
        if let expected { return wire?.string == expected }
        return wire == nil || wire == .null || wire?.string == nil
    }

    public func detailMatches(_ detailSkuID: Int64, intent: Intent) -> Bool {
        detailSkuID == intent.skuID
    }

    public func recover(requestID: String, skuID: Int64, currentForm: String) -> Recovery {
        _ = currentForm
        let id = MerchantSupplyDryRunProjection.parse(requestID) ?? requestID
        return Recovery(requestID: id, skuID: skuID, payload: nil, outcome: "UNKNOWN")
    }

    /// Same request id reads the original receipt. The form is not a new save body.
    public func recover(requestID: String, receipt: MerchantBusinessValue?, currentForm: String) -> Recovery {
        _ = currentForm
        let parsed = MerchantSupplyDryRunProjection.parse(requestID)
        let unknown = Recovery(requestID: parsed ?? requestID, skuID: 0, payload: nil, outcome: "UNKNOWN")
        guard let parsed, let fields = receipt?.object, fields["requestId"]?.string == parsed,
              let state = fields["state"]?.string, state != "NOT_FOUND" else { return unknown }
        guard state == "APPLIED", fields["action"]?.string == "SKU_SAVE",
              fields["targetType"]?.string == "pms_sku",
              let target = fields["targetId"]?.integer, target > 0 else { return unknown }
        return Recovery(requestID: parsed, skuID: Int64(target), payload: nil, outcome: "APPLIED")
    }
}

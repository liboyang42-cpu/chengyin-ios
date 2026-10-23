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

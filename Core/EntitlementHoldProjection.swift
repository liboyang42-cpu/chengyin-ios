import Foundation

/// Exclusive C07 projection: holding a multi-merchant entitlement is not issuance.
/// status 0 occupies capacity; this type never calls reserve / redeem / award.
public enum EntitlementHoldOutcome: String, Equatable, Sendable {
    case held = "HELD"
    case redeemed = "REDEEMED"
    case invalid = "INVALID"
    case unknown = "UNKNOWN"
}

public enum EntitlementHoldStatus {
    public static let held = 0
    public static let redeemed = 1
    public static let invalid = 2
}

public enum EntitlementHoldInvalidReason {
    public static let refund = "REFUND"
    public static let organizerCancel = "ORGANIZER_CANCEL"
    public static let fulfillmentGap = "FULFILLMENT_GAP"
    public static let manual = "MANUAL"
    public static let known: Set<String> = [refund, organizerCancel, fulfillmentGap, manual]
}

public struct EntitlementHoldFact: Equatable, Sendable {
    public let originalRequestID: String?
    public let registrationID: Int64?
    public let chapterID: Int64?
    public let merchantID: Int64?
    public let status: Int?
    public let validEndExclusive: Date?
    public let invalidReason: String?
    public init(originalRequestID: String?, registrationID: Int64?, chapterID: Int64?,
                merchantID: Int64?, status: Int?, validEndExclusive: Date?, invalidReason: String?) {
        self.originalRequestID = EntitlementHoldProjection.parse(originalRequestID)
        self.registrationID = registrationID; self.chapterID = chapterID
        self.merchantID = merchantID; self.status = status
        self.validEndExclusive = validEndExclusive
        let trimmed = invalidReason?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.invalidReason = (trimmed?.isEmpty == false) ? trimmed : nil
    }
}

public struct EntitlementHoldView: Equatable, Sendable {
    public let originalRequestID: String?
    public let outcome: EntitlementHoldOutcome
    public let occupiesCapacity: Bool
    public let executedReserve: Bool
    public let executedRedeem: Bool
    public let executedAward: Bool
    public let holdingIsIssuance: Bool
    public func jsonObject() -> [String: Any] {
        [
            "originalRequestID": originalRequestID.map { $0 as Any } ?? NSNull(),
            "outcome": outcome.rawValue,
            "occupiesCapacity": occupiesCapacity,
            "executedReserve": executedReserve,
            "executedRedeem": executedRedeem,
            "executedAward": executedAward,
            "holdingIsIssuance": holdingIsIssuance
        ]
    }
}

public enum EntitlementHoldFailure: Error, Equatable {
    case waitingSource(capability: String)
}

public struct LedgerEntitlementRow: Equatable, Sendable {
    public let chapterID: Int64
    public let status: Int?
    public let invalidReason: String?
    public init(chapterID: Int64, status: Int?, invalidReason: String?) {
        self.chapterID = chapterID
        self.status = status
        let trimmed = invalidReason?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.invalidReason = (trimmed?.isEmpty == false) ? trimmed : nil
    }
}

public struct EntitlementHoldProjection: Equatable {
    public static let perkList = "perkLedger.listEntitlements"
    public private(set) var occupyCountByRequestID: [String: Int] = [:]
    public private(set) var originalIntentByRequestID: [String: EntitlementHoldView] = [:]
    public init() {}
    public static func parse(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 64 else { return nil }
        return trimmed
    }
    public mutating func project(_ fact: EntitlementHoldFact?, serverNow: Date?) -> EntitlementHoldView {
        if let requestID = Self.parse(fact?.originalRequestID),
           let original = originalIntentByRequestID[requestID] {
            return original
        }
        let view = compute(fact, serverNow: serverNow)
        if let requestID = view.originalRequestID, view.outcome != .unknown {
            originalIntentByRequestID[requestID] = view
            if view.occupiesCapacity, occupyCountByRequestID[requestID] == nil {
                occupyCountByRequestID[requestID] = 1
            }
        }
        return view
    }
    public mutating func requery(_ fact: EntitlementHoldFact?, serverNow: Date?) -> EntitlementHoldView {
        project(fact, serverNow: serverNow)
    }
    public func occupyCount(originalRequestID: String) -> Int {
        guard let requestID = Self.parse(originalRequestID) else { return 0 }
        return occupyCountByRequestID[requestID] ?? 0
    }
    public func recoverOriginal(originalRequestID: String) -> EntitlementHoldView {
        let requestID = Self.parse(originalRequestID)
        if let requestID, let original = originalIntentByRequestID[requestID] {
            return original
        }
        return Self.unknown(requestID)
    }
    public mutating func projectFromLedger(originalRequestID: String?, registrationID: Int64?,
                                           chapterID: Int64?, merchantID: Int64?,
                                           validEndExclusive: Date?, serverNow: Date?,
                                           listEntitlements: ((Int64) -> [LedgerEntitlementRow])?) throws -> EntitlementHoldView {
        guard let listEntitlements else {
            throw EntitlementHoldFailure.waitingSource(capability: Self.perkList)
        }
        guard let registrationID, registrationID > 0 else {
            throw EntitlementHoldFailure.waitingSource(capability: Self.perkList)
        }
        let rows = listEntitlements(registrationID)
        guard let chapterID, let match = rows.first(where: { $0.chapterID == chapterID }) else {
            return recoverOriginal(originalRequestID: originalRequestID ?? "")
        }
        let fact = EntitlementHoldFact(originalRequestID: originalRequestID, registrationID: registrationID,
                                       chapterID: chapterID, merchantID: merchantID, status: match.status,
                                       validEndExclusive: validEndExclusive, invalidReason: match.invalidReason)
        return project(fact, serverNow: serverNow)
    }
    private func compute(_ fact: EntitlementHoldFact?, serverNow: Date?) -> EntitlementHoldView {
        guard let serverNow else { return Self.unknown(Self.parse(fact?.originalRequestID)) }
        guard let fact else { return Self.unknown(nil) }
        let requestID = fact.originalRequestID
        if requestID == nil || fact.registrationID == nil || fact.registrationID! <= 0
            || fact.chapterID == nil || fact.chapterID! <= 0
            || fact.merchantID == nil || fact.merchantID! <= 0 {
            return Self.unknown(requestID)
        }
        guard let status = fact.status else { return Self.unknown(requestID) }
        if status == EntitlementHoldStatus.redeemed {
            return EntitlementHoldView(originalRequestID: requestID, outcome: .redeemed,
                                       occupiesCapacity: false, executedReserve: false,
                                       executedRedeem: false, executedAward: false,
                                       holdingIsIssuance: false)
        }
        if status == EntitlementHoldStatus.invalid {
            return EntitlementHoldView(originalRequestID: requestID, outcome: .invalid,
                                       occupiesCapacity: false, executedReserve: false,
                                       executedRedeem: false, executedAward: false,
                                       holdingIsIssuance: false)
        }
        guard status == EntitlementHoldStatus.held else { return Self.unknown(requestID) }
        guard let end = fact.validEndExclusive else { return Self.unknown(requestID) }
        if !(serverNow < end) {
            return EntitlementHoldView(originalRequestID: requestID, outcome: .invalid,
                                       occupiesCapacity: false, executedReserve: false,
                                       executedRedeem: false, executedAward: false,
                                       holdingIsIssuance: false)
        }
        if let reason = fact.invalidReason, EntitlementHoldInvalidReason.known.contains(reason) {
            return EntitlementHoldView(originalRequestID: requestID, outcome: .invalid,
                                       occupiesCapacity: false, executedReserve: false,
                                       executedRedeem: false, executedAward: false,
                                       holdingIsIssuance: false)
        }
        return EntitlementHoldView(originalRequestID: requestID, outcome: .held,
                                   occupiesCapacity: true, executedReserve: false,
                                   executedRedeem: false, executedAward: false,
                                   holdingIsIssuance: false)
    }
    private static func unknown(_ requestID: String?) -> EntitlementHoldView {
        EntitlementHoldView(originalRequestID: requestID, outcome: .unknown,
                            occupiesCapacity: false, executedReserve: false,
                            executedRedeem: false, executedAward: false,
                            holdingIsIssuance: false)
    }
}

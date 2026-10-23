import Foundation

/// Exclusive C07 projection: reread the four ledgers for an originalRequestID.
/// Current projection is not the original receipt. Missing bill / hash / amount is
/// UNKNOWN, never a new reconcile and never a zero-amount coercion.
public enum FourLedgerDimension: String, Equatable, Sendable, CaseIterable {
    case wechatTrade = "WECHAT_TRADE"
    case registrationOrder = "REGISTRATION_ORDER"
    case memberBalance = "MEMBER_BALANCE"
    case merchantPayable = "MERCHANT_PAYABLE"
}

public enum FourLedgerOutcome: String, Equatable, Sendable {
    case matched = "MATCHED"
    case diverged = "DIVERGED"
    case unknown = "UNKNOWN"
}

public struct FourLedgerBillFact: Equatable, Sendable {
    public let originalRequestID: String?
    public let dimension: FourLedgerDimension?
    public let expectedAmount: Decimal?
    public let actualAmount: Decimal?
    public let billPresent: Bool
    public let sourceHash: String?
    public init(originalRequestID: String?, dimension: FourLedgerDimension?,
                expectedAmount: Decimal?, actualAmount: Decimal?,
                billPresent: Bool, sourceHash: String?) {
        self.originalRequestID = FourLedgerBillRereadProjection.parse(originalRequestID)
        self.dimension = dimension
        self.expectedAmount = expectedAmount
        self.actualAmount = actualAmount
        self.billPresent = billPresent
        self.sourceHash = FourLedgerBillRereadProjection.parse(sourceHash)
    }
}

public struct FourLedgerBillView: Equatable, Sendable {
    public let originalRequestID: String?
    public let outcomes: [FourLedgerDimension: FourLedgerOutcome]
    public let startedNewReconcile: Bool
    public let currentProjectionReplacesOriginal: Bool
    public func outcome(_ dimension: FourLedgerDimension) -> FourLedgerOutcome {
        outcomes[dimension] ?? .unknown
    }
    public func jsonObject() -> [String: Any] {
        var mapped: [String: Any] = [:]
        for dimension in FourLedgerDimension.allCases {
            mapped[dimension.rawValue] = outcome(dimension).rawValue
        }
        return [
            "originalRequestID": originalRequestID.map { $0 as Any } ?? NSNull(),
            "outcomes": mapped,
            "startedNewReconcile": startedNewReconcile,
            "currentProjectionReplacesOriginal": currentProjectionReplacesOriginal
        ]
    }
}

public struct FourLedgerBillRereadProjection: Equatable {
    public static let tolerance = Decimal(string: "0.01")!
    public private(set) var originalByRequestID: [String: FourLedgerBillView] = [:]
    public init() {}
    public static func parse(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 64 else { return nil }
        return trimmed
    }
    public mutating func reread(originalRequestID: String?, facts: [FourLedgerBillFact]?) -> FourLedgerBillView {
        let requestID = Self.parse(originalRequestID)
        let view = compute(requestID: requestID, facts: facts)
        if let requestID, originalByRequestID[requestID] == nil {
            originalByRequestID[requestID] = view
        }
        return view
    }
    public mutating func requery(originalRequestID: String?, facts: [FourLedgerBillFact]?) -> FourLedgerBillView {
        reread(originalRequestID: originalRequestID, facts: facts)
    }
    public func recoverOriginal(originalRequestID: String) -> FourLedgerBillView {
        let requestID = Self.parse(originalRequestID)
        if let requestID, let original = originalByRequestID[requestID] {
            return original
        }
        return Self.emptyUnknown(requestID)
    }
    /// APPLIED+SUCCESS current projection must not rewrite an UNKNOWN original bill.
    public func originalUnknownNotReplacedByProjectionSuccess(_ original: FourLedgerBillView,
                                                              projectionClaimsSuccess: Bool) -> Bool {
        if !projectionClaimsSuccess { return true }
        if original.outcomes.values.contains(.unknown) { return true }
        return !original.currentProjectionReplacesOriginal
    }
    private func compute(requestID: String?, facts: [FourLedgerBillFact]?) -> FourLedgerBillView {
        guard let requestID else { return Self.emptyUnknown(nil) }
        var outcomes = Self.emptyOutcomes()
        guard let facts else {
            return FourLedgerBillView(originalRequestID: requestID, outcomes: outcomes,
                                      startedNewReconcile: false,
                                      currentProjectionReplacesOriginal: false)
        }
        for fact in facts {
            guard let dimension = fact.dimension, fact.originalRequestID == requestID else { continue }
            outcomes[dimension] = outcomeOf(fact)
        }
        return FourLedgerBillView(originalRequestID: requestID, outcomes: outcomes,
                                  startedNewReconcile: false,
                                  currentProjectionReplacesOriginal: false)
    }
    private func outcomeOf(_ fact: FourLedgerBillFact) -> FourLedgerOutcome {
        guard fact.billPresent, fact.sourceHash != nil else { return .unknown }
        guard let expected = fact.expectedAmount, let actual = fact.actualAmount else { return .unknown }
        var delta = actual - expected
        if delta < 0 { delta = -delta }
        if delta > Self.tolerance { return .diverged }
        return .matched
    }
    private static func emptyOutcomes() -> [FourLedgerDimension: FourLedgerOutcome] {
        var outcomes: [FourLedgerDimension: FourLedgerOutcome] = [:]
        for dimension in FourLedgerDimension.allCases { outcomes[dimension] = .unknown }
        return outcomes
    }
    private static func emptyUnknown(_ requestID: String?) -> FourLedgerBillView {
        FourLedgerBillView(originalRequestID: requestID, outcomes: emptyOutcomes(),
                           startedNewReconcile: false, currentProjectionReplacesOriginal: false)
    }
}

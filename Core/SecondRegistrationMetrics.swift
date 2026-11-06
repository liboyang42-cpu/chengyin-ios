import Foundation

// Client side of the second-registration (二报) metric, reform plan v9 §16 / W10.
// Valid registrations, t0, N/D and maturity are server facts. The client only
// renders a published report and keeps droppable exposure events locally.

/// Observation windows defined by W10.1; any other window is rejected, not rounded.
public enum SecondRegistrationWindow: Int, CaseIterable, Decodable, Comparable {
    case days7 = 7, days28 = 28, days56 = 56
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}
public enum SecondRegistrationPricing: String, Decodable { case free = "FREE", paid = "PAID" }

/// One N/D cell. Maturity is supplied by the report; the client never derives it from dates.
public struct SecondRegistrationCell: Decodable, Equatable {
    public let window: SecondRegistrationWindow
    public let mature: Bool
    public let denominator: Int?
    public let numerator: Int?
    public let observedCumulative: Int?
    enum CodingKeys: String, CodingKey { case window = "days", mature, denominator, numerator, observedCumulative }
}
public struct SecondRegistrationTransition: Decodable, Equatable {
    public let from: SecondRegistrationPricing
    public let to: SecondRegistrationPricing
    public let cell: SecondRegistrationCell
    enum CodingKeys: String, CodingKey { case from, to }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        from = try c.decode(SecondRegistrationPricing.self, forKey: .from)
        to = try c.decode(SecondRegistrationPricing.self, forKey: .to)
        cell = try SecondRegistrationCell(from: decoder)
    }
}
/// Published exclusion counts (test, fraud, cancelled, full refund); unknown stays nil.
public struct SecondRegistrationExclusions: Decodable, Equatable {
    public let test: Int?
    public let fraud: Int?
    public let cancelled: Int?
    public let fullRefund: Int?
}
public struct SecondRegistrationReport: Decodable, Equatable {
    public let metricVersion: String
    public let asOf: String
    public let isTest: Bool
    public let windows: [SecondRegistrationCell]
    public let transitions: [SecondRegistrationTransition]
    public let exclusions: SecondRegistrationExclusions?
    /// Sensitivity using the initial-confirmation definition that still counts refunds.
    public let refundSensitivity: SecondRegistrationCell?
    /// Members kept in the funnel without any re-participable second content (W10.3).
    public let supplyGapMembers: Int?
    enum CodingKeys: String, CodingKey { case metricVersion, asOf, isTest, windows, transitions, exclusions, refundSensitivity, supplyGapMembers }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        metricVersion = try c.decode(String.self, forKey: .metricVersion).trimmingCharacters(in: .whitespacesAndNewlines)
        asOf = try c.decode(String.self, forKey: .asOf).trimmingCharacters(in: .whitespacesAndNewlines)
        isTest = try c.decodeIfPresent(Bool.self, forKey: .isTest) ?? false
        windows = try c.decodeIfPresent([SecondRegistrationCell].self, forKey: .windows) ?? []
        transitions = try c.decodeIfPresent([SecondRegistrationTransition].self, forKey: .transitions) ?? []
        exclusions = try c.decodeIfPresent(SecondRegistrationExclusions.self, forKey: .exclusions)
        refundSensitivity = try c.decodeIfPresent(SecondRegistrationCell.self, forKey: .refundSensitivity)
        supplyGapMembers = try c.decodeIfPresent(Int.self, forKey: .supplyGapMembers).flatMap { $0 >= 0 ? $0 : nil }
        // A report without as_of or metric_version cannot be reconciled and is not shown.
        guard !metricVersion.isEmpty, !asOf.isEmpty,
              Set(windows.map(\.window)).count == windows.count else { throw APIError.malformedResponse }
    }
    public var sortedWindows: [SecondRegistrationCell] { windows.sorted { $0.window < $1.window } }
}

/// W10: D = 0 is "no mature sample", never 0%; immature cohorts only show observed totals.
public enum SecondRegistrationRateDisplay: Equatable {
    case rate(numerator: Int, denominator: Int, percent: String)
    case noMatureSample
    case observedOnly(Int)
    case unavailable

    public init(_ cell: SecondRegistrationCell?) {
        guard let cell else { self = .unavailable; return }
        guard cell.mature else {
            if let observed = cell.observedCumulative, observed >= 0 { self = .observedOnly(observed) }
            else { self = .unavailable }
            return
        }
        guard let d = cell.denominator, d >= 0 else { self = .unavailable; return }
        if d == 0 { self = (cell.numerator ?? 0) == 0 ? .noMatureSample : .unavailable; return }
        guard let n = cell.numerator, n >= 0, n <= d else { self = .unavailable; return }
        self = .rate(numerator: n, denominator: d, percent: Self.percentText(numerator: n, denominator: d))
    }
    /// One decimal, half-up, integer arithmetic only.
    static func percentText(numerator: Int, denominator: Int) -> String {
        let (product, overflow) = numerator.multipliedReportingOverflow(by: 1000)
        guard !overflow, denominator > 0 else { return "" }
        let tenths = (product + denominator / 2) / denominator
        return "\(tenths / 10).\(tenths % 10)%"
    }
}

/// Client-captured experience events (§16 "内容与体验"). Exposure can be lost; it is a
/// diagnostic only and never the denominator of the overall second-registration rate.
public struct SecondRegistrationClientEvent: Encodable, Equatable {
    public enum Name: String, Encodable { case offerViewed = "offer_viewed", secondContentExposed = "second_content_exposed" }
    public static let schemaVersion = 1
    public let name: Name
    public let eventID: String
    public let idempotencyKey: String
    public let occurredAt: Date
    public let isTest: Bool
    public let clientVersion: String
    public let trace: String
    public let activityID: Int?
    public let contentFamilyID: String?
    public let reason: String?
    enum CodingKeys: String, CodingKey {
        case name = "event", eventID = "event_id", idempotencyKey = "idempotency_key", occurredAt = "occurred_at"
        case schemaVersion, source, isTest = "is_test", clientVersion = "client_version", trace
        case activityID = "activity_id", contentFamilyID = "content_family_id", reason
    }
    /// One exposure per subject per visit: a re-render of the same visit keeps the same key.
    public init(name: Name, visit: UUID, activityID: Int?, contentFamilyID: String? = nil, reason: String? = nil,
                isTest: Bool, clientVersion: String, occurredAt: Date) throws {
        guard activityID.map({ $0 > 0 }) ?? (contentFamilyID != nil),
              contentFamilyID.map(Self.isFamilyID) ?? true,
              reason.map({ $0.utf8.count <= 64 }) ?? true else { throw APIError.invalidRequest }
        self.name = name; self.activityID = activityID; self.contentFamilyID = contentFamilyID; self.reason = reason
        self.isTest = isTest; self.clientVersion = clientVersion; self.occurredAt = occurredAt
        let subject = activityID.map { "activity-\($0)" } ?? "family-\(contentFamilyID ?? "")"
        trace = visit.uuidString.lowercased()
        idempotencyKey = "\(name.rawValue):\(subject):\(trace)"
        eventID = UUID().uuidString.lowercased()
    }
    static func isFamilyID(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 64 &&
            value.allSatisfy { character in character.isASCII && (character.isLetter || character.isNumber || character == "-" || character == "_") }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name); try c.encode(eventID, forKey: .eventID)
        try c.encode(idempotencyKey, forKey: .idempotencyKey)
        try c.encode(Int64((occurredAt.timeIntervalSince1970 * 1000).rounded(.down)), forKey: .occurredAt)
        try c.encode(Self.schemaVersion, forKey: .schemaVersion); try c.encode("ios", forKey: .source)
        try c.encode(isTest, forKey: .isTest); try c.encode(clientVersion, forKey: .clientVersion)
        try c.encode(trace, forKey: .trace)
        try c.encodeIfPresent(activityID, forKey: .activityID)
        try c.encodeIfPresent(contentFamilyID, forKey: .contentFamilyID)
        try c.encodeIfPresent(reason, forKey: .reason)
    }
}

/// Local, bounded, deduplicated proposal log. It has no transport: W10 capture stays a
/// local proposal until a reviewed ingestion endpoint exists. Account changes clear it.
@MainActor public final class SecondRegistrationExposureLog {
    public static let capacity = 50
    public private(set) var events: [SecondRegistrationClientEvent] = []
    private var keys: Set<String> = []
    public init() {}
    @discardableResult public func record(_ event: SecondRegistrationClientEvent) -> Bool {
        guard keys.insert(event.idempotencyKey).inserted else { return false }
        events.append(event)
        if events.count > Self.capacity { keys.remove(events.removeFirst().idempotencyKey) }
        return true
    }
    public func reset() { events = []; keys = [] }
}

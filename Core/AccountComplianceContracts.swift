import Foundation

public enum ComplianceFailure: Error, Equatable {
    case unavailable, invalidInput, staleSession, busy, unresolved, readbackMismatch, malformed
    case rejected(String)
}
public struct ComplianceSession: Equatable {
    public let accountID: Int
    public let epoch: UInt64
    public let market: String
    public let namespace: String
    public init(accountID: Int, epoch: UInt64, market: String, namespace: String) {
        self.accountID = accountID; self.epoch = epoch; self.market = market; self.namespace = namespace
    }
    public var valid: Bool { accountID > 0 && ["CN", "US"].contains(market) && !namespace.isEmpty }
    // Epoch fences callbacks; durable operations deliberately survive new authentication epochs.
    public var journalScope: String { "\(namespace)|\(market)|\(accountID)" }
}
public enum ComplianceSubject: Equatable {
    case signup, merchantOnsite(authoritativeMerchantID: Int), roamLocation, cancellation
    public var docType: String {
        switch self {
        case .signup: return "activity_host_data_sharing"
        case .merchantOnsite: return "merchant_onsite_data_sharing"
        case .roamLocation: return "privacy_policy"
        case .cancellation: return "account_cancellation_notice"
        }
    }
    public var scene: String {
        switch self {
        case .signup: return "activity_signup"
        case .merchantOnsite: return "merchant_redeem"
        case .roamLocation: return "roam_location"
        case .cancellation: return "account_cancel"
        }
    }
    public var scopeID: Int? { if case .merchantOnsite(let id) = self { return id }; return nil }
    public var scopeType: String? { scopeID == nil ? nil : "MERCHANT" }
    public var operation: String { "consent|\(docType)|\(scene)|\(scopeID.map(String.init) ?? "none")" }
    public func fields() throws -> [String: Any] {
        if let id = scopeID, id <= 0 { throw ComplianceFailure.invalidInput }
        var fields: [String: Any] = ["docType": docType, "scene": scene]
        if let id = scopeID { fields["scopeId"] = id; fields["scopeType"] = "MERCHANT" }
        return fields
    }
}
public enum ComplianceEvent: String { case agree = "AGREE", revoke = "REVOKE" }
public struct ComplianceConsent: Decodable, Equatable {
    public let docType: String
    public let docVersion: String?
    public let scene: String?
    public let scopeType: String?
    public let scopeId: Int?
    public let eventType: String?
    public let occurredAt: String?
    public func matches(_ subject: ComplianceSubject, event: ComplianceEvent) -> Bool {
        docType == subject.docType && scene == subject.scene && scopeType == subject.scopeType && scopeId == subject.scopeID && eventType == event.rawValue
    }
}
public struct ComplianceDeregistration: Decodable, Equatable {
    public let status: String
    public let blockers: [String]
    public let executeAfter: String?
    public var eligible: Bool { status == "ELIGIBLE" }
    public var blocked: Bool { status == "BLOCKED" }
    public var pending: Bool { executeAfter != nil && !["NORMAL", "ELIGIBLE", "BLOCKED"].contains(status) }
    enum CodingKeys: String, CodingKey { case status, blockers, executeAfter }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Missing status is unknown, never guessed NORMAL/eligible.
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "UNKNOWN"
        blockers = try c.decodeIfPresent([String].self, forKey: .blockers) ?? []
        executeAfter = try c.decodeIfPresent(String.self, forKey: .executeAfter)
    }
}
public enum ComplianceMarketingChannel: String, CaseIterable { case inApp = "IN_APP", coupon = "COUPON" }
public struct ComplianceMarketingConsent: Decodable, Equatable, Identifiable {
    public let merchantRowId: Int
    public let merchantOwnerMemberId: Int
    public let merchantName: String?
    public let inAppOptedIn: Bool
    public let couponOptedIn: Bool
    public var id: String { "\(merchantRowId)|\(merchantOwnerMemberId)" }
    public func value(_ channel: ComplianceMarketingChannel) -> Bool { channel == .inApp ? inAppOptedIn : couponOptedIn }
    public var valid: Bool { merchantRowId > 0 && merchantOwnerMemberId > 0 }
}
/// Only operation metadata is stored: never tokens, phone, SMS, legal document text or responses.
public struct CompliancePendingOperation: Codable, Equatable {
    public let scope: String
    public let operation: String
    public let requestID: String
    public let epoch: UInt64
}
@MainActor public protocol ComplianceJournaling: AnyObject {
    func pending(scope: String, operation: String) throws -> CompliancePendingOperation?
    func begin(_ operation: CompliancePendingOperation) throws
    func resolve(scope: String, operation: String) throws
}
/// Atomic durable journal. A corrupt/unreadable file fails closed; never silently resets locks.
@MainActor public final class ComplianceFileJournal: ComplianceJournaling {
    private let url: URL
    public init(url: URL) { self.url = url }
    private func read() throws -> [CompliancePendingOperation] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([CompliancePendingOperation].self, from: Data(contentsOf: url))
    }
    private func write(_ rows: [CompliancePendingOperation]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(rows).write(to: url, options: .atomic)
    }
    public func pending(scope: String, operation: String) throws -> CompliancePendingOperation? { try read().first { $0.scope == scope && $0.operation == operation } }
    public func begin(_ operation: CompliancePendingOperation) throws {
        var rows = try read()
        guard !rows.contains(where: { $0.scope == operation.scope && $0.operation == operation.operation }) else { throw ComplianceFailure.unresolved }
        rows.append(operation); try write(rows)
    }
    public func resolve(scope: String, operation: String) throws { try write(read().filter { !($0.scope == scope && $0.operation == operation) }) }
}

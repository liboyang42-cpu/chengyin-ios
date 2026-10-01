import Foundation

public enum TicketWalletLane: Int, CaseIterable { case route = 1, activity = 2 }
public enum TicketWalletStatus: String { case ready, pending, verified, cancelled, expired, unknown }
public enum TicketWalletAction: String { case detail, paymentUnavailable, cancelled, expired, unknown }
public enum TicketWalletRedemption: String { case notImplemented, unpaid, cancelled, expired, complete, unknown }

/// Narrow read projection of MyRegistration / RegistrationDetail. No code or payment credentials.
public struct TicketWalletTicket: Decodable, Equatable, Identifiable {
    public let id: Int
    public let ownerType: Int?
    public let ownerID: Int?
    public let activityID: Int?
    public let topicID: Int?
    public let registrationNumber: String?
    public let registrationStatus: Int?
    public let verificationStatus: Int?
    public let title: String?
    public let participateDate: String?
    public let productType: Int?
    public let startDate: String?
    public let endDate: String?
    public let addressName: String?
    public let payableAmount: Decimal?
    public let realName: String?
    /// Source detail supplies masked phone text. It is never sent elsewhere or logged.
    public let phone: String?
    public let purchaseKind: String?
    public let entitlements: [TicketWalletEntitlement]
    public let verificationTime: String?

    public var status: TicketWalletStatus {
        // Source wxs precedence: verification takes precedence even for a cancelled row.
        if verificationStatus == 1 { return .verified }
        if registrationStatus == 3 { return .cancelled }
        if registrationStatus == 4 { return .expired }
        if registrationStatus == 2 { return .ready }
        if registrationStatus == 1 { return .pending }
        return .unknown
    }
    /// Opening behavior uses registrationStatus, independently of the displayed verification state.
    public var action: TicketWalletAction {
        switch registrationStatus {
        case 1: return .paymentUnavailable
        case 2: return .detail
        case 3: return .cancelled
        case 4: return .expired
        default: return .unknown
        }
    }
    public var pendingCount: Int { entitlements.filter { $0.status == 0 }.count }
    public var hasUnknownEntitlementStatus: Bool { entitlements.contains { ![0, 1, 2].contains($0.status ?? -1) } }
    /// Read-only explanation of the Flutter detail gate. Never authorizes code issuance.
    public var redemption: TicketWalletRedemption {
        switch registrationStatus {
        case 1: return .unpaid
        case 3: return .cancelled
        case 4: return .expired
        case 2:
            if entitlements.isEmpty { return verificationStatus == 1 ? .complete : .notImplemented }
            if pendingCount > 0 { return .notImplemented }
            return hasUnknownEntitlementStatus ? .unknown : .complete
        default: return .unknown
        }
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: TicketWalletKey.self)
        id = try c.requiredID("id")
        ownerType = try c.integer("ownerType"); ownerID = try c.integer("ownerId")
        activityID = try c.integer("activityId"); topicID = try c.integer("topicId")
        registrationNumber = try c.text("registrationNo")
        registrationStatus = try c.integer("registrationStatus")
        verificationStatus = try c.integer("verificationStatus")
        let activity = try c.decodeIfPresent(TicketWalletOwner.self, forKey: TicketWalletKey("cmsActivity"))
        let topic = try c.decodeIfPresent(TicketWalletOwner.self, forKey: TicketWalletKey("cmsTopic"))
        let owner = activity ?? topic
        title = owner?.name; productType = owner?.productType
        startDate = owner?.startDate; endDate = owner?.endDate; addressName = owner?.addressName
        participateDate = try c.text("participateDate")
        payableAmount = try c.decodeIfPresent(Decimal.self, forKey: TicketWalletKey("payableAmount"))
        realName = try c.text("realName"); phone = try c.text("phone")
        if let raw = try? c.decode(Int.self, forKey: TicketWalletKey("purchaseKind")) {
            purchaseKind = [1: "GUIDED_TICKET", 2: "SELF_PASS", 3: "EXPLORE_PASS"][raw]
        } else { purchaseKind = try c.text("purchaseKind") }
        entitlements = try c.decodeIfPresent([TicketWalletEntitlement].self, forKey: TicketWalletKey("entitlements")) ?? []
        verificationTime = try c.text("verificationTime")
    }
}

public struct TicketWalletEntitlement: Decodable, Equatable, Identifiable {
    public let id: Int
    /// Missing status stays unknown rather than becoming an unredeemed benefit.
    public let status: Int?
    public let chapterID: Int?
    public let chapterName: String?
    public let statusLabel: String?
    public let invalidReason: String?
    public let redeemedAt: String?
    public var statusKey: String {
        switch status { case 0: return "pending"; case 1: return "redeemed"; case 2: return "invalid"; default: return "unknown" }
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: TicketWalletKey.self)
        id = try c.requiredID("id"); status = try c.integer("status")
        chapterID = try c.integer("chapterId"); chapterName = try c.text("chapterName")
        statusLabel = try c.text("statusLabel"); invalidReason = try c.text("invalidReason")
        redeemedAt = try c.text("redeemedAt")
    }
}

public enum TicketWalletReadFailure: Error, Equatable {
    case unavailable
    /// Nil message has fallback provenance; explicit backend prose is never treated as a key.
    case rejected(code: Int, message: String?)
}
public enum TicketWalletIssue: Equatable {
    case login, notConfigured, unavailable, malformed, network, failure
    case server(String)
    public init(_ error: Error) {
        if let failure = error as? TicketWalletReadFailure {
            switch failure {
            case .unavailable: self = .unavailable
            case .rejected(_, let message): self = message.map(Self.server) ?? .failure
            }
        } else if let api = error as? APIError {
            switch api {
            case .unauthorized: self = .login
            case .notConfigured: self = .notConfigured
            case .malformedResponse, .invalidRequest: self = .malformed
            default: self = .failure
            }
        } else if error is URLError { self = .network }
        else { self = .failure }
    }
    public var localizationKey: String {
        switch self {
        case .login: return "ticketWallet.issue.login"
        case .notConfigured: return "ticketWallet.issue.notConfigured"
        case .unavailable: return "ticketWallet.issue.unavailable"
        case .malformed: return "ticketWallet.issue.malformed"
        case .network: return "ticketWallet.issue.network"
        case .failure, .server: return "ticketWallet.issue.failure"
        }
    }
}
public struct TicketWalletLaneFailure: Equatable {
    public let lane: TicketWalletLane
    public let issue: TicketWalletIssue
    public init(lane: TicketWalletLane, issue: TicketWalletIssue) { self.lane = lane; self.issue = issue }
}
public struct TicketWalletSnapshot: Equatable {
    public let tickets: [TicketWalletTicket]
    public let partialFailure: TicketWalletLaneFailure?
    public init(tickets: [TicketWalletTicket], partialFailure: TicketWalletLaneFailure? = nil) {
        self.tickets = tickets; self.partialFailure = partialFailure
    }
}

private struct TicketWalletOwner: Decodable {
    let name: String?
    let productType: Int?
    let startDate: String?
    let endDate: String?
    let addressName: String?
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: TicketWalletKey.self)
        name = try c.text("name"); productType = try c.integer("productType")
        startDate = try c.text("startDate"); endDate = try c.text("endDate"); addressName = try c.text("addressName")
    }
}
private struct TicketWalletKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(_ value: String) { stringValue = value }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}
private extension KeyedDecodingContainer where Key == TicketWalletKey {
    func text(_ key: String) throws -> String? { try decodeIfPresent(String.self, forKey: TicketWalletKey(key)) }
    func integer(_ key: String) throws -> Int? {
        let k = TicketWalletKey(key)
        guard contains(k), try !decodeNil(forKey: k) else { return nil }
        if let value = try? decode(Int.self, forKey: k) { return value }
        if let value = try? decode(String.self, forKey: k), let number = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) { return number }
        throw APIError.malformedResponse
    }
    func requiredID(_ key: String) throws -> Int {
        guard let value = try integer(key), value > 0 else { throw APIError.malformedResponse }
        return value
    }
}

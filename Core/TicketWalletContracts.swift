import Foundation

public enum TicketWalletLane: Int, CaseIterable { case route = 1, activity = 2 }
public enum TicketWalletStatus: String { case ready, pending, verified, cancelled, expired, unknown }
public enum TicketWalletAction: String { case detail, paymentUnavailable, cancelled, expired, unknown }
public enum TicketWalletRedemption: String { case notImplemented, unpaid, cancelled, expired, complete, unknown }
/// Server-computed usable window (Asia/Shanghai). Unknown text stays nil rather than a guess.
public enum TicketWalletUsableState: String { case usable = "USABLE", upcoming = "UPCOMING", expired = "EXPIRED" }
/// Server-computed clear tag. NONE means the product has no clear concept and shows no tag.
public enum TicketWalletClearState: String { case cleared = "CLEARED", notCleared = "NOT_CLEARED", notApplicable = "NONE" }

/// Family-ticket composition snapshot taken at order time. Age only, never a child name.
public struct TicketWalletParty: Decodable, Equatable {
    public let adultCount: Int?
    public let childCount: Int?
    public let childAge: Int?
    public var isFamily: Bool { childCount == 1 }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: TicketWalletKey.self)
        adultCount = c.tolerantInteger("adultCount"); childCount = c.tolerantInteger("childCount")
        childAge = c.tolerantInteger("childAge")
    }
}

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
    /// 0 unpaid, 1 paying, 2 paid, 3 failed, 4 refunded. Missing stays unknown.
    public let paymentStatus: Int?
    /// Additive F13 fields; old servers omit them and decoding stays tolerant.
    public let usableFrom: String?
    public let usableUntil: String?
    public let usableState: TicketWalletUsableState?
    public let clearState: TicketWalletClearState?
    /// Any refund application other than a rejected one (status 2), or a manual refund case.
    public let hasRefundInProgress: Bool
    public let party: TicketWalletParty?

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
        paymentStatus = c.tolerantInteger("paymentStatus")
        usableFrom = c.tolerantText("usableFrom"); usableUntil = c.tolerantText("usableUntil")
        usableState = c.tolerantText("usableState").flatMap(TicketWalletUsableState.init(rawValue:))
        clearState = c.tolerantText("clearState").flatMap(TicketWalletClearState.init(rawValue:))
        let refund = (try? c.decodeIfPresent(TicketWalletRefundApplication.self, forKey: TicketWalletKey("refundApplication"))) ?? nil
        let manualCase = c.tolerantText("manualRefundCaseStatus")
        hasRefundInProgress = (refund.map { $0.status != 2 } ?? false) || (manualCase.map { !$0.isEmpty } ?? false)
        party = (try? c.decodeIfPresent(TicketWalletParty.self, forKey: TicketWalletKey("party"))) ?? nil
    }
}

private struct TicketWalletRefundApplication: Decodable {
    let status: Int?
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: TicketWalletKey.self)
        status = c.tolerantInteger("status")
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

/// Calendar day in Asia/Shanghai, used for the "M月D日开始" tag.
public struct TicketWalletMonthDay: Equatable {
    public let month: Int
    public let day: Int
    public init(month: Int, day: Int) { self.month = month; self.day = day }
}

/// One wallet row. `index` is the exact position in the source snapshot, so row-bound
/// navigation keeps addressing the server row even after filtering and sorting.
public struct TicketWalletListEntry: Equatable {
    public let index: Int
    public let ticket: TicketWalletTicket
    /// Not started yet: shown greyed, never opened, no back-side actions.
    public var isUpcoming: Bool { ticket.usableState == .upcoming }
    /// Clear state is a tag, not a filter. NONE (or an unknown value) shows no tag.
    public var clearTagKey: String? {
        guard !isUpcoming else { return nil }
        switch ticket.clearState {
        case .cleared?: return "ticketWallet.clear.cleared"
        case .notCleared?: return "ticketWallet.clear.notCleared"
        default: return nil
        }
    }
    public var startsOn: TicketWalletMonthDay? {
        guard isUpcoming, let raw = ticket.usableFrom, let date = RegistrationWaitlistStatus.parseDeadline(raw) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        guard let zone = TimeZone(identifier: "Asia/Shanghai") else { return nil }
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.month, .day], from: date)
        guard let month = parts.month, let day = parts.day else { return nil }
        return TicketWalletMonthDay(month: month, day: day)
    }
    public var showsFamilyParty: Bool { ticket.party?.isFamily == true }
}

/// F13 wallet rule shared with the mini program and computed from server fields only:
/// paid and registered, not refunding/refunded, not EXPIRED. Verified (cleared) tickets stay,
/// because replays are unlimited. USABLE rows first by usableUntil ascending (open-ended last),
/// then UPCOMING rows by usableFrom ascending. Ties keep the server order.
public enum TicketWalletListing {
    public static func isListed(_ ticket: TicketWalletTicket) -> Bool {
        ticket.registrationStatus == 2 && ticket.paymentStatus == 2
            && !ticket.hasRefundInProgress && ticket.usableState != .expired
    }
    public static func entries(_ tickets: [TicketWalletTicket]) -> [TicketWalletListEntry] {
        let listed = tickets.enumerated().filter { isListed($0.element) }
            .map { TicketWalletListEntry(index: $0.offset, ticket: $0.element) }
        let usable = listed.filter { !$0.isUpcoming }
            .sorted { precedes($0, $1, key: { $0.ticket.usableUntil }) }
        let upcoming = listed.filter(\.isUpcoming)
            .sorted { precedes($0, $1, key: { $0.ticket.usableFrom }) }
        return usable + upcoming
    }
    private static func precedes(_ a: TicketWalletListEntry, _ b: TicketWalletListEntry,
                                 key: (TicketWalletListEntry) -> String?) -> Bool {
        let left = key(a).flatMap(RegistrationWaitlistStatus.parseDeadline)
        let right = key(b).flatMap(RegistrationWaitlistStatus.parseDeadline)
        switch (left, right) {
        case let (l?, r?) where l != r: return l < r
        case (_?, nil): return true
        case (nil, _?): return false
        default: return a.index < b.index
        }
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
    /// Additive optional fields: wrong types read as absent instead of failing the whole row.
    func tolerantInteger(_ key: String) -> Int? { (try? integer(key)) ?? nil }
    func tolerantText(_ key: String) -> String? {
        guard let value = (try? text(key)) ?? nil else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
    func requiredID(_ key: String) throws -> Int {
        guard let value = try integer(key), value > 0 else { throw APIError.malformedResponse }
        return value
    }
}

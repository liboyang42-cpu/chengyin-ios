import Foundation

/// SmsCoupon definition identity; never pass this to qr-token or redemption APIs.
public struct CouponDefinitionID: Hashable, Codable {
    public let value: Int
    public init(_ value: Int) throws { guard value > 0 else { throw CouponManagementError.invalid }; self.value = value }
    public init(from decoder: Decoder) throws { try self.init(decoder.singleValueContainer().decode(Int.self)) }
    public func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(value) }
}
public enum CouponManagementError: Error, Equatable {
    case invalid, malformed, unavailable, signedOut, changed, forbidden, storage, locked
    case server(String)
    public var messageKey: String {
        switch self {
        case .invalid: return "couponManagement.invalid"
        case .malformed: return "couponManagement.malformed"
        case .unavailable: return "couponManagement.unavailable"
        case .signedOut: return "couponManagement.signIn"
        case .changed: return "couponManagement.changed"
        case .forbidden: return "couponManagement.forbidden"
        case .storage: return "couponManagement.storage"
        case .locked: return "couponManagement.unknownOutcome"
        case .server: return "couponManagement.serverError"
        }
    }
}
public enum CouponDefinitionStatus: Equatable {
    case scheduled, active, ended, invalidated, stopped, unknown
    public init(_ raw: Int?) {
        switch raw { case 0: self = .scheduled; case 1: self = .active; case 2: self = .ended; case 3: self = .invalidated; case 4: self = .stopped; default: self = .unknown }
    }
    public var canStop: Bool { self == .scheduled || self == .active }
    public var key: String {
        switch self { case .scheduled: return "couponManagement.scheduled"; case .active: return "couponManagement.active"; case .ended: return "couponManagement.ended"; case .invalidated: return "couponManagement.invalidated"; case .stopped: return "couponManagement.stopped"; case .unknown: return "couponManagement.unknownStatus" }
    }
}
/// List projection only. No derived claim/redemption eligibility, money defaults or credential fields.
public struct CouponDefinition: Decodable, Equatable, Identifiable {
    public let id: CouponDefinitionID
    public let name: String?
    public let description: String?
    public let status: Int?
    public let couponType: Int?
    public let publishCount: Int?
    public let receiveCount: Int?
    public let useCount: Int?
    public let startTime: String?
    public let endTime: String?
    // Optional passthrough metadata, never emitted in the source publish request.
    public let amount: Decimal?
    public let currency: String?
    public let perLimit: Int?
    private enum CodingKeys: String, CodingKey {
        case id, name, description, status, couponType, publishCount, receiveCount, useCount, startTime, endTime, amount, currency, perLimit
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(CouponDefinitionID.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        status = try c.decodeIfPresent(Int.self, forKey: .status)
        couponType = try c.decodeIfPresent(Int.self, forKey: .couponType)
        publishCount = try c.decodeIfPresent(Int.self, forKey: .publishCount)
        receiveCount = try c.decodeIfPresent(Int.self, forKey: .receiveCount)
        useCount = try c.decodeIfPresent(Int.self, forKey: .useCount)
        startTime = try c.decodeIfPresent(String.self, forKey: .startTime)
        endTime = try c.decodeIfPresent(String.self, forKey: .endTime)
        currency = try c.decodeIfPresent(String.self, forKey: .currency)
        perLimit = try c.decodeIfPresent(Int.self, forKey: .perLimit)
        if !c.contains(.amount) { amount = nil }
        else if try c.decodeNil(forKey: .amount) { amount = nil }
        else if let number = try? c.decode(Decimal.self, forKey: .amount) { amount = number }
        else {
            let string = try c.decode(String.self, forKey: .amount)
            guard string.range(of: #"^-?[0-9]+(?:\.[0-9]+)?$"#, options: .regularExpression) != nil,
                  let number = Decimal(string: string, locale: Locale(identifier: "en_US_POSIX")) else { throw CouponManagementError.malformed }
            amount = number
        }
    }
    public var state: CouponDefinitionStatus { .init(status) }
    public var remaining: Int? {
        guard let published = publishCount, let received = receiveCount, published >= 0, received >= 0 else { return nil }
        return received >= published ? 0 : published - received
    }
    public var typeKey: String { CouponManagementDraft.typeKey(couponType) }
    public static func displayDay(_ raw: String?) -> String? {
        // Display only. The server owns status and precise time eligibility.
        guard let raw else { return nil }
        let day = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(10))
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian); formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
        guard let date = formatter.date(from: day), formatter.string(from: date) == day else { return nil }
        return day.replacingOccurrences(of: "-", with: ".")
    }
}
/// Coupon validity uses the existing merchant contract's China civil time, never the device zone.
public enum CouponValidityTime {
    public static var timeZone: TimeZone { TimeZone(secondsFromGMT: 8 * 3600)! }
    public static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = timeZone
        return value
    }
    private static func formatter(_ pattern: String) -> DateFormatter {
        let value = DateFormatter()
        value.locale = Locale(identifier: "en_US_POSIX")
        value.calendar = calendar
        value.timeZone = timeZone
        value.dateFormat = pattern
        value.isLenient = false
        return value
    }
    public static func wire(_ date: Date) -> String {
        formatter("yyyy-MM-dd HH:mm:ss").string(from: date)
    }
    public static func parse(_ raw: String) -> Date? {
        let value = formatter("yyyy-MM-dd HH:mm:ss")
        guard raw.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$"#, options: .regularExpression) != nil,
              let date = value.date(from: raw), value.string(from: date) == raw else { return nil }
        return date
    }
    public static func display(_ date: Date) -> String {
        formatter("yyyy.MM.dd HH:mm:ss").string(from: date)
    }
    public static func display(_ raw: String?) -> String? {
        guard let raw, let date = parse(raw) else { return nil }
        return display(date)
    }
}
public struct CouponManagementDraft: Codable, Equatable {
    public var name = ""
    public var description = ""
    public var startTime: Date?
    public var endTime: Date?
    public var quantity = ""
    /// nil is the picker placeholder; wire types are exactly 0...3.
    public var couponType: Int?
    public init() {}
    public var dirty: Bool { !name.isEmpty || !description.isEmpty || startTime != nil || endTime != nil || !quantity.isEmpty || couponType != nil }
    public var blocker: String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "couponManagement.nameRequired" }
        guard let start = startTime, let end = endTime else { return "couponManagement.datesRequired" }
        guard let type = couponType, (0...3).contains(type) else { return "couponManagement.typeRequired" }
        guard let count = Int(quantity.trimmingCharacters(in: .whitespacesAndNewlines)), count > 0 else { return "couponManagement.quantityRequired" }
        guard start.timeIntervalSince1970.isFinite, end.timeIntervalSince1970.isFinite,
              let wireStart = CouponValidityTime.parse(CouponValidityTime.wire(start)),
              let wireEnd = CouponValidityTime.parse(CouponValidityTime.wire(end)),
              wireEnd > wireStart else { return "couponManagement.dateOrder" }
        return nil
    }
    public static func typeKey(_ value: Int?) -> String {
        switch value { case 0: return "couponManagement.gift"; case 1: return "couponManagement.tenPercent"; case 2: return "couponManagement.twentyPercent"; case 3: return "couponManagement.experience"; default: return "couponManagement.coupon" }
    }
}
public struct CouponManagementSession: Equatable, Hashable {
    public let accountID: Int
    public let namespace: String
    public let epoch: UInt64
    public let authorizationRevision: String
    public init(accountID: Int, namespace: String, epoch: UInt64, authorizationRevision: String) throws {
        guard accountID > 0, !namespace.isEmpty, !authorizationRevision.isEmpty else { throw CouponManagementError.signedOut }
        self.accountID = accountID; self.namespace = namespace; self.epoch = epoch; self.authorizationRevision = authorizationRevision
    }
    // Durable identity deliberately excludes epoch: logging out cannot clear an uncertain submission.
    public var ownerKey: String { "\(namespace.utf8.count):\(namespace):\(accountID)" }
}
public struct CouponPublisherPermission: Equatable {
    public let revision: String
    public let mayPublish: Bool
    public let merchantID: Int?
    public let ownerMemberID: Int?
    public init(revision: String, mayPublish: Bool, merchantID: Int? = nil, ownerMemberID: Int? = nil) { self.revision = revision; self.mayPublish = mayPublish; self.merchantID = merchantID; self.ownerMemberID = ownerMemberID }
}
/// Host must supply fresh source-backed publisher eligibility, not a cached display role.
@MainActor public protocol CouponPublisherAuthorizing: AnyObject {
    func freshPermission(session: CouponManagementSession) async throws -> CouponPublisherPermission
}
@MainActor public final class CouponPublisherUnavailable: CouponPublisherAuthorizing {
    public init() {}
    public func freshPermission(session: CouponManagementSession) async throws -> CouponPublisherPermission { throw CouponManagementError.unavailable }
}

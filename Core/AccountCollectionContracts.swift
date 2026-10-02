import Foundation

/// Read-only projection of ViewCouponHistory. Redemption credentials (couponCode, qrcodeUrl)
/// are deliberately not decoded or retained. These records are never persisted or logged.
public struct AccountCollectionCoupon: Decodable, Equatable, Identifiable {
    public let id: Int
    public let couponID: Int?
    public let useStatus: Int?
    public let name: String?
    public let description: String?
    public let note: String?
    public let receivedTime: String?
    public let usedTime: String?
    public let startTime: String?
    public let endTime: String?
    public var displayDescription: String? {
        if let description, !description.isEmpty { return description }
        return note
    }
    public var status: AccountCollectionCouponStatus {
        switch useStatus {
        case 0: return .unused
        case 1: return .used
        case 2: return .expired
        case 3: return .invalid
        default: return .unknown
        }
    }
    private enum CodingKeys: String, CodingKey {
        case id, couponId, useStatus, couponName, couponDescription, note, getTime, useTime, startTime, endTime
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        guard id > 0 else { throw APIError.malformedResponse }
        couponID = try c.decodeIfPresent(Int.self, forKey: .couponId)
        useStatus = try c.decodeIfPresent(Int.self, forKey: .useStatus)
        name = try c.decodeIfPresent(String.self, forKey: .couponName)
        description = try c.decodeIfPresent(String.self, forKey: .couponDescription)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        receivedTime = try c.decodeIfPresent(String.self, forKey: .getTime)
        usedTime = try c.decodeIfPresent(String.self, forKey: .useTime)
        startTime = try c.decodeIfPresent(String.self, forKey: .startTime)
        endTime = try c.decodeIfPresent(String.self, forKey: .endTime)
    }
    /// The API supplies a China-calendar date. Preserve its day rather than converting to
    /// the device time zone. Invalid dates remain unknown; never compute expiry locally.
    public static func calendarDay(_ value: String?) -> String? {
        guard let value else { return nil }
        let prefix = String(value.trimmingCharacters(in: .whitespacesAndNewlines).prefix(10))
        let components = prefix.split(separator: "-", omittingEmptySubsequences: false)
        guard components.count == 3, components[0].count == 4, components[1].count == 2, components[2].count == 2,
              components.allSatisfy({ $0.utf8.allSatisfy { (48...57).contains($0) } }),
              let year = Int(components[0]), let month = Int(components[1]), let day = Int(components[2]), year > 0 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let parts = DateComponents(year: year, month: month, day: day)
        guard let date = calendar.date(from: parts) else { return nil }
        let resolved = calendar.dateComponents([.year, .month, .day], from: date)
        guard resolved.year == year, resolved.month == month, resolved.day == day else { return nil }
        return prefix.replacingOccurrences(of: "-", with: ".")
    }
}
public enum AccountCollectionCouponStatus: String, Equatable { case unused, used, expired, invalid, unknown }

/// The source wallet has exactly four filters; invalid/unknown rows remain visible in All.
public enum AccountCollectionCouponFilter: String, CaseIterable, Identifiable {
    case all, unused, used, expired
    public var id: String { rawValue }
    public func includes(_ coupon: AccountCollectionCoupon) -> Bool {
        switch self {
        case .all: return true
        case .unused: return coupon.useStatus == 0
        case .used: return coupon.useStatus == 1
        case .expired: return coupon.useStatus == 2
        }
    }
}

public enum AccountCollectionReadFailure: Error, Equatable {
    case unavailable
    case rejected(code: Int, message: String?)
}
public enum AccountCollectionIssue: Equatable {
    case login, notConfigured, unavailable, network, failure, server(String)
    public init(_ error: Error) {
        switch error {
        case APIError.unauthorized: self = .login
        case APIError.notConfigured: self = .notConfigured
        case AccountCollectionReadFailure.unavailable: self = .unavailable
        case AccountCollectionReadFailure.rejected(_, let message): self = message.map(Self.server) ?? .failure
        case is URLError: self = .network
        default: self = .failure
        }
    }
    public var localizationKey: String {
        switch self {
        case .login: return "accountCollection.signInRequired"
        case .notConfigured: return "accountCollection.notConfigured"
        case .unavailable: return "accountCollection.unavailable"
        case .network: return "accountCollection.network"
        case .failure, .server: return "accountCollection.failed"
        }
    }
}

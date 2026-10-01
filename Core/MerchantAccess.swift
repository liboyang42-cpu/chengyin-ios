import Foundation

/// The only client-side merchant authorization projection is access/me.
/// An entry choice or Account.role/userType must never construct this value.
public struct MerchantAccess: Decodable, Equatable {
    public enum Role: String, Decodable, CaseIterable {
        case owner = "MERCHANT_OWNER", manager = "MERCHANT_MANAGER"
        case checkIn = "MERCHANT_CHECKIN", marketing = "MERCHANT_MARKETING", finance = "MERCHANT_FINANCE"
        public var titleKey: String {
            switch self {
            case .owner: return "merchant.role.owner"
            case .manager: return "merchant.role.manager"
            case .checkIn: return "merchant.role.checkIn"
            case .marketing: return "merchant.role.marketing"
            case .finance: return "merchant.role.finance"
            }
        }
    }
    public enum Permission: String, Decodable {
        case basicRead = "merchant:basic:read"
        case projects = "merchant:project:manage"
        case orders = "merchant:order:read"
        case finance = "merchant:finance:read"
    }
    public let active: Bool
    public let merchantID: Int?
    public let merchantName: String?
    public let role: Role?
    public let permissions: Set<Permission>
    public let application: MerchantApplicationSummary?

    public var isOwner: Bool { active && role == .owner }
    public func allows(_ permission: Permission) -> Bool { active && permissions.contains(permission) }
    public var canReadDashboard: Bool { isOwner && allows(.finance) }

    enum CodingKeys: String, CodingKey { case active, merchant, roleCode, permissions, applicationState }
    private struct Store: Decodable {
        let id: Int?
        let name: String?
        let status: Int?
        let accountStatus: Int?
        enum CodingKeys: String, CodingKey { case id, name, status, accountStatus }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = c.merchantInteger(.id)
            name = try c.decodeIfPresent(String.self, forKey: .name)?.trimmingCharacters(in: .whitespacesAndNewlines)
            status = c.merchantInteger(.status)
            accountStatus = c.merchantInteger(.accountStatus)
        }
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        active = try c.decode(Bool.self, forKey: .active)
        let roleText = try c.decodeIfPresent(String.self, forKey: .roleCode)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if !active {
            // Inactive access never inherits any granted permissions.
            permissions = []
            let store = try? c.decode(Store.self, forKey: .merchant)
            let state = try? c.decode(String.self, forKey: .applicationState)
            if ["PENDING", "REJECTED", "DISABLED"].contains(state ?? ""), roleText == Role.owner.rawValue,
               let store, let id = store.id, id > 0,
               let status = store.status, (0...2).contains(status),
               let accountStatus = store.accountStatus, (0...2).contains(accountStatus) {
                merchantID = id; merchantName = store.name; role = .owner
                application = MerchantApplicationSummary(status: status, accountStatus: accountStatus)
            } else {
                merchantID = nil; merchantName = nil; role = nil; application = nil
            }
            return
        }
        let store = try c.decode(Store.self, forKey: .merchant)
        guard let id = store.id, id > 0, let role = Role(rawValue: roleText ?? "") else {
            throw DecodingError.dataCorruptedError(forKey: .merchant, in: c, debugDescription: "Invalid merchant identity")
        }
        merchantID = id; merchantName = store.name; self.role = role; application = nil
        let permissionNames = try c.decodeIfPresent([String].self, forKey: .permissions) ?? []
        permissions = Set(permissionNames.compactMap(Permission.init(rawValue:)))
    }
}

public struct MerchantApplicationSummary: Equatable {
    public let status: Int
    public let accountStatus: Int
    public var titleKey: String {
        if accountStatus == 2 { return "merchant.access.disabled" }
        if status == 1 && accountStatus == 1 { return "merchant.access.effective" }
        if status == 2 { return "merchant.access.rejected" }
        if status == 1 { return "merchant.access.awaitingActivation" }
        return "merchant.access.pending"
    }
}

extension KeyedDecodingContainer {
    /// IDs can be serialized as strings; fractional and Boolean values fail closed.
    func merchantInteger(_ key: Key) -> Int? {
        if let value = try? decode(Int.self, forKey: key) { return value }
        if let value = try? decode(String.self, forKey: key) {
            return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }
}

public enum MerchantReadError: Error, Equatable {
    case accessDenied
}

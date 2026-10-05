import Foundation

/// Lossless domain JSON. Money strings stay strings; JSON numbers use Decimal, never Double.
public enum MerchantBusinessValue: Codable, Equatable {
    case null, bool(Bool), number(Decimal), string(String), array([MerchantBusinessValue]), object([String: MerchantBusinessValue])
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let value = try? c.decode(Bool.self) { self = .bool(value) }
        else if let value = try? c.decode(String.self) { self = .string(value) }
        else if let value = try? c.decode(Decimal.self) { self = .number(value) }
        else if let value = try? c.decode([Self].self) { self = .array(value) }
        else { self = .object(try c.decode([String: Self].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil(); case .bool(let value): try c.encode(value)
        case .number(let value): try c.encode(value); case .string(let value): try c.encode(value)
        case .array(let value): try c.encode(value); case .object(let value): try c.encode(value)
        }
    }
    public var object: [String: Self]? { if case .object(let value) = self { return value }; return nil }
    public var array: [Self]? { if case .array(let value) = self { return value }; return nil }
    public var string: String? { if case .string(let value) = self { return value }; return nil }
    public var bool: Bool? { if case .bool(let value) = self { return value }; return nil }
    public var integer: Int? {
        switch self {
        case .string(let value): return Int(value)
        case .number(let value): return Int(NSDecimalNumber(decimal: value).stringValue)
        default: return nil
        }
    }
    public var numberText: String? {
        switch self { case .string(let value): return value; case .number(let value): return NSDecimalNumber(decimal: value).stringValue; default: return nil }
    }
    public static func int(_ value: Int) -> Self { .number(Decimal(value)) }
    public static func optional(_ value: String?) -> Self { value.map(Self.string) ?? .null }
    public static func optional(_ value: Int?) -> Self { value.map(Self.int) ?? .null }
}
public typealias MerchantBusinessObject = [String: MerchantBusinessValue]
extension Dictionary where Key == String, Value == MerchantBusinessValue {
    func mbText(_ key: String) -> String? { self[key]?.string.flatMap { $0.isEmpty ? nil : $0 } }
    func mbRequiredText(_ key: String) throws -> String { guard let value = mbText(key) else { throw MerchantBusinessFailure.malformed }; return value }
    func mbInt(_ key: String, minimum: Int = 0) throws -> Int { guard let value = self[key]?.integer, value >= minimum else { throw MerchantBusinessFailure.malformed }; return value }
    func mbBool(_ key: String) throws -> Bool { guard let value = self[key]?.bool else { throw MerchantBusinessFailure.malformed }; return value }
    func mbObject(_ key: String) throws -> Self { guard let value = self[key]?.object else { throw MerchantBusinessFailure.malformed }; return value }
    func mbArray(_ key: String) throws -> [MerchantBusinessValue] { guard let value = self[key]?.array else { throw MerchantBusinessFailure.malformed }; return value }
    func mbObjects(_ key: String) throws -> [Self] { try mbArray(key).map { guard let value = $0.object else { throw MerchantBusinessFailure.malformed }; return value } }
    func mbStrings(_ key: String) throws -> [String] { try mbArray(key).map { guard let value = $0.string else { throw MerchantBusinessFailure.malformed }; return value } }
}
public enum MerchantBusinessFailure: Error, Equatable {
    case invalid, malformed, denied, disabled, stale, conflict, pending, journal, unknown
    case rejected(Int, String?)
    public var key: String {
        switch self {
        case .invalid: return "merchant.business.invalid"; case .malformed: return "merchant.business.malformed"
        case .denied: return "merchant.business.denied"; case .disabled: return "merchant.business.disabled"
        case .stale: return "merchant.business.stale"; case .conflict: return "merchant.business.conflict"
        case .pending, .unknown: return "merchant.business.unknownResult"; case .journal: return "merchant.business.journal"
        case .rejected: return "merchant.business.rejected"
        }
    }
}
/// Distinct branded identifiers prevent customer/member/store/order confusion at call sites.
public struct MerchantBusinessID<Domain>: Hashable, Codable {
    public let rawValue: Int
    public init(_ value: Int) throws { guard value > 0 else { throw MerchantBusinessFailure.invalid }; rawValue = value }
    public init(from decoder: Decoder) throws { try self.init(decoder.singleValueContainer().decode(Int.self)) }
    public func encode(to encoder: Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(rawValue) }
}
public enum MerchantCustomerDomain {}
public enum MerchantRefundDomain {}
public enum MerchantReviewDomain {}
public enum MerchantOperatorDomain {}
public enum MerchantInviteDomain {}
public enum MerchantBatchDomain {}
public enum MerchantChapterDomain {}
public enum MerchantStationRegistrationDomain {}
public typealias MerchantCustomerID = MerchantBusinessID<MerchantCustomerDomain>
public typealias MerchantRefundID = MerchantBusinessID<MerchantRefundDomain>
public typealias MerchantBusinessReviewID = MerchantBusinessID<MerchantReviewDomain>
public typealias MerchantOperatorID = MerchantBusinessID<MerchantOperatorDomain>
public typealias MerchantOperatorInviteID = MerchantBusinessID<MerchantInviteDomain>
public typealias MerchantBatchID = MerchantBusinessID<MerchantBatchDomain>
public typealias MerchantChapterID = MerchantBusinessID<MerchantChapterDomain>
public typealias MerchantStationRegistrationID = MerchantBusinessID<MerchantStationRegistrationDomain>

public struct MerchantBusinessAccess: Equatable {
    public let merchantID: Int
    public let name: String?
    public let role: String
    public let permissions: Set<String>
    public let canManageOperators: Bool
    public static let employeeRoles = ["MERCHANT_MANAGER", "MERCHANT_CHECKIN", "MERCHANT_MARKETING", "MERCHANT_FINANCE"]
    public init(_ object: MerchantBusinessObject) throws {
        guard try object.mbBool("active") else { throw MerchantBusinessFailure.denied }
        let merchant = try object.mbObject("merchant")
        merchantID = try merchant.mbInt("id", minimum: 1); name = merchant.mbText("name")
        role = try object.mbRequiredText("roleCode")
        guard (Self.employeeRoles + ["MERCHANT_OWNER"]).contains(role) else { throw MerchantBusinessFailure.malformed }
        let strings = try object.mbStrings("permissions")
        guard Set(strings).count == strings.count else { throw MerchantBusinessFailure.malformed }
        permissions = Set(strings)
        // Operators have a second explicit server bit. Missing is fail-closed for this surface only.
        canManageOperators = object["canManageOperators"]?.bool == true && permissions.contains("merchant:operator:manage")
        if let flag = object["canManageOperators"]?.bool, flag != permissions.contains("merchant:operator:manage") { throw MerchantBusinessFailure.malformed }
    }
    public func allows(_ permission: String) -> Bool { permissions.contains(permission) }
    public func require(_ permissions: [String]) throws {
        guard permissions.allSatisfy(allows) else { throw MerchantBusinessFailure.denied }
        if permissions.contains("merchant:operator:manage"), !canManageOperators { throw MerchantBusinessFailure.denied }
    }
}
/// No arithmetic or currency inference. Source merchant finance is explicitly CNY.
public struct MerchantBusinessMoney: Equatable {
    public let raw: String?
    public let currency: String
    public init(_ value: MerchantBusinessValue?, currency: String = "CNY", strictString: Bool = false) throws {
        self.currency = currency
        if value == nil || value == .null { raw = nil; return }
        guard let text = strictString ? value?.string : value?.numberText,
              text.range(of: #"^[+-]?[0-9]+(?:\.[0-9]+)?$"#, options: .regularExpression) != nil else { throw MerchantBusinessFailure.malformed }
        raw = text
    }
    public var display: String { raw.map { "\(currency) \($0)" } ?? "—" }
}

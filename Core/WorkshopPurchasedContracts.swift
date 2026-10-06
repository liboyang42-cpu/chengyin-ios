import Foundation

/// NEW purchased-version owner metadata contract; separate from FREE claims and purchase execution.
public enum WorkshopPurchasedIssue: Error, Equatable {
    case unavailable, disabled, unauthorized, forbidden, notFound, malformed, staleSession, staleRead, invalid
}
public struct WorkshopPurchasedItem: Decodable, Equatable, Identifiable {
    public enum Status: String, Decodable { case active = "ACTIVE", suspended = "SUSPENDED", revoked = "REVOKED" }
    public enum Permission: String, Decodable { case allowed = "ALLOWED", prohibited = "PROHIBITED" }
    public enum Adaptation: String, Decodable { case bindResourcesOnly = "BIND_RESOURCES_ONLY", localAdaptation = "LOCAL_ADAPTATION" }
    public struct Limit: Decodable, Equatable {
        public let unlimited: Bool
        public let maximum: Int64
        private enum CodingKeys: String, CodingKey { case unlimited, maximum }
        public init(from decoder: Decoder) throws {
            try WorkshopPurchasedWire.exactKeys(decoder, ["unlimited", "maximum"])
            let c = try decoder.container(keyedBy: CodingKeys.self)
            unlimited = try c.decode(Bool.self, forKey: .unlimited); maximum = try c.decode(Int64.self, forKey: .maximum)
            guard maximum >= 0, !unlimited || maximum == 0 else { throw WorkshopPurchasedIssue.malformed }
        }
    }
    public let licenseId, moduleId, purchasedVersionId, contentHash, acquiredAt, termsVersion, termsHash: String
    public let status: Status
    public let commercialUse, translation: Permission
    public let adaptation: Adaptation
    public let allowedRegions: [String]
    public let themeLimit, merchantLimit, runLimit: Limit
    public var id: String { licenseId }
    public var permitsContentUse: Bool { false }
    public var permitsPurchase: Bool { false }
    private enum CodingKeys: String, CodingKey {
        case licenseId, moduleId, purchasedVersionId, contentHash, acquiredAt, termsVersion, termsHash, status
        case commercialUse, adaptation, translation, allowedRegions, themeLimit, merchantLimit, runLimit
        case acquisition, buyerKind, useDuration, updates, redistribution, contentUseStatus, purchaseActionStatus
    }
    public init(from decoder: Decoder) throws {
        try WorkshopPurchasedWire.exactKeys(decoder, ["licenseId", "moduleId", "purchasedVersionId", "contentHash", "acquiredAt", "termsVersion", "termsHash", "status", "commercialUse", "adaptation", "translation", "allowedRegions", "themeLimit", "merchantLimit", "runLimit", "acquisition", "buyerKind", "useDuration", "updates", "redistribution", "contentUseStatus", "purchaseActionStatus"])
        let c = try decoder.container(keyedBy: CodingKeys.self)
        licenseId = try c.decode(String.self, forKey: .licenseId); moduleId = try c.decode(String.self, forKey: .moduleId)
        purchasedVersionId = try c.decode(String.self, forKey: .purchasedVersionId); contentHash = try c.decode(String.self, forKey: .contentHash)
        acquiredAt = try c.decode(String.self, forKey: .acquiredAt); termsVersion = try c.decode(String.self, forKey: .termsVersion)
        termsHash = try c.decode(String.self, forKey: .termsHash); status = try c.decode(Status.self, forKey: .status)
        commercialUse = try c.decode(Permission.self, forKey: .commercialUse); adaptation = try c.decode(Adaptation.self, forKey: .adaptation)
        translation = try c.decode(Permission.self, forKey: .translation); allowedRegions = try c.decode([String].self, forKey: .allowedRegions)
        themeLimit = try c.decode(Limit.self, forKey: .themeLimit); merchantLimit = try c.decode(Limit.self, forKey: .merchantLimit); runLimit = try c.decode(Limit.self, forKey: .runLimit)
        guard WorkshopPurchasedWire.license(licenseId), [moduleId, purchasedVersionId, termsVersion].allSatisfy({ WorkshopPurchasedWire.bounded($0, 128) }),
              [contentHash, termsHash].allSatisfy(WorkshopPurchasedWire.hash), WorkshopPurchasedWire.timestamp(acquiredAt),
              !allowedRegions.isEmpty, allowedRegions.count <= 32, Set(allowedRegions.map { Data($0.utf8) }).count == allowedRegions.count,
              allowedRegions.allSatisfy({ WorkshopPurchasedWire.bounded($0, 128) }),
              try c.decode(String.self, forKey: .acquisition) == "PAID", try c.decode(String.self, forKey: .buyerKind) == "INDIVIDUAL",
              try c.decode(String.self, forKey: .useDuration) == "PERPETUAL_PURCHASED_VERSION",
              try c.decode(String.self, forKey: .updates) == "EXACT_PURCHASED_VERSION", try c.decode(String.self, forKey: .redistribution) == "PROHIBITED",
              try c.decode(String.self, forKey: .contentUseStatus) == "PAID_INSTALL_AUTHORITY_UNAVAILABLE",
              try c.decode(String.self, forKey: .purchaseActionStatus) == "CHANNEL_APPROVAL_REQUIRED" else { throw WorkshopPurchasedIssue.malformed }
    }
}
public struct WorkshopPurchasedPage: Decodable, Equatable {
    public let items: [WorkshopPurchasedItem]
    public let nextBeforeOrderLineId: Int64?
    public let hasMore: Bool
    public let checkedAt: String
    private enum CodingKeys: String, CodingKey { case items, nextBeforeOrderLineId, hasMore, checkedAt }
    public init(from decoder: Decoder) throws {
        try WorkshopPurchasedWire.exactKeys(decoder, ["schema", "scope", "items", "nextBeforeOrderLineId", "hasMore", "checkedAt"])
        try WorkshopPurchasedWire.metadata(decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        checkedAt = try c.decode(String.self, forKey: .checkedAt); hasMore = try c.decode(Bool.self, forKey: .hasMore)
        nextBeforeOrderLineId = try c.decodeIfPresent(Int64.self, forKey: .nextBeforeOrderLineId)
        var input = try c.nestedUnkeyedContainer(forKey: .items), values: [WorkshopPurchasedItem] = [], seen = Set<String>()
        while !input.isAtEnd { guard values.count < 50 else { throw WorkshopPurchasedIssue.malformed }; let item = try input.decode(WorkshopPurchasedItem.self); guard seen.insert(item.id).inserted else { throw WorkshopPurchasedIssue.malformed }; values.append(item) }
        guard WorkshopPurchasedWire.timestamp(checkedAt), hasMore == (nextBeforeOrderLineId != nil), nextBeforeOrderLineId.map({ $0 > 0 }) != false,
              !hasMore || values.count == 50 else { throw WorkshopPurchasedIssue.malformed }; items = values
    }
}
public struct WorkshopPurchasedDetail: Decodable, Equatable {
    public let item: WorkshopPurchasedItem
    public let checkedAt: String
    private enum CodingKeys: String, CodingKey { case item, checkedAt }
    public init(from decoder: Decoder) throws {
        try WorkshopPurchasedWire.exactKeys(decoder, ["schema", "scope", "item", "checkedAt"]); try WorkshopPurchasedWire.metadata(decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self); item = try c.decode(WorkshopPurchasedItem.self, forKey: .item)
        checkedAt = try c.decode(String.self, forKey: .checkedAt); guard WorkshopPurchasedWire.timestamp(checkedAt) else { throw WorkshopPurchasedIssue.malformed }
    }
}
enum WorkshopPurchasedWire {
    private struct Key: CodingKey { let stringValue: String; let intValue: Int? = nil; init?(stringValue: String) { self.stringValue = stringValue }; init?(intValue: Int) { return nil } }
    static func exactKeys(_ decoder: Decoder, _ expected: Set<String>) throws {
        guard Set(try decoder.container(keyedBy: Key.self).allKeys.map(\.stringValue)) == expected else { throw WorkshopPurchasedIssue.malformed }
    }
    private enum Metadata: String, CodingKey { case schema, scope }
    static func metadata(_ decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Metadata.self)
        guard try c.decode(String.self, forKey: .schema) == "workshop-purchased-owned-v1",
              try c.decode(String.self, forKey: .scope) == "PAID_INDIVIDUAL_PURCHASED_VERSION_METADATA_ONLY" else { throw WorkshopPurchasedIssue.malformed }
    }
    static func bounded(_ s: String, _ max: Int) -> Bool { !s.isEmpty && s.utf8.count <= max }
    static func license(_ s: String) -> Bool {
        guard s.hasPrefix("w18-paid-") else { return false }; let number = String(s.dropFirst(9))
        guard number.range(of: #"\A[1-9][0-9]{0,18}\z"#, options: .regularExpression) != nil, let value = Int64(number), value > 0 else { return false }; return true
    }
    static func hash(_ s: String) -> Bool { s.utf8.count == 64 && s.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) } }
    static func timestamp(_ s: String) -> Bool { WorkshopOwnedWire.timestamp(s) }
}

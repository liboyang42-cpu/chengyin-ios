import Foundation

/// Newly proposed owner-read contract. A free acquisition record is not purchased ownership.
public enum WorkshopOwnedIssue: Error, Equatable {
    case unavailable, disabled, unauthorized, forbidden, notFound, malformed, staleSession, staleRead, invalid
}

public struct WorkshopOwnedItem: Decodable, Equatable, Identifiable {
    public enum StoredStatus: String, Decodable { case active = "ACTIVE", suspended = "SUSPENDED", revoked = "REVOKED", expired = "EXPIRED" }
    public enum Status: String, Decodable { case active = "ACTIVE", suspended = "SUSPENDED", revoked = "REVOKED", expired = "EXPIRED", unavailable = "UNAVAILABLE" }
    public enum PublicationStatus: String, Decodable { case listed = "LISTED", retired = "RETIRED", emergencyBlocked = "EMERGENCY_BLOCKED", unavailable = "UNAVAILABLE" }
    public let claimId: String
    public var id: String { claimId }
    public let acquiredAt: String
    public let validUntil: String
    public let storedStatus: StoredStatus
    public let status: Status
    public let publicationStatus: PublicationStatus
    private enum CodingKeys: String, CodingKey { case claimId, acquisition, buyerKind, acquiredAt, validUntil, storedStatus, status, publicationStatus }
    public init(from decoder: Decoder) throws {
        try WorkshopOwnedWire.exactKeys(decoder, ["claimId", "acquisition", "buyerKind", "acquiredAt", "validUntil", "storedStatus", "status", "publicationStatus"])
        let c = try decoder.container(keyedBy: CodingKeys.self)
        claimId = try c.decode(String.self, forKey: .claimId)
        acquiredAt = try c.decode(String.self, forKey: .acquiredAt)
        validUntil = try c.decode(String.self, forKey: .validUntil)
        storedStatus = try c.decode(StoredStatus.self, forKey: .storedStatus)
        status = try c.decode(Status.self, forKey: .status)
        publicationStatus = try c.decode(PublicationStatus.self, forKey: .publicationStatus)
        guard WorkshopOwnedWire.identifier(claimId), WorkshopOwnedWire.timestamp(acquiredAt), WorkshopOwnedWire.timestamp(validUntil),
              try c.decode(String.self, forKey: .acquisition) == "FREE", try c.decode(String.self, forKey: .buyerKind) == "INDIVIDUAL" else { throw WorkshopOwnedIssue.malformed }
        if publicationStatus == .emergencyBlocked || publicationStatus == .unavailable {
            guard status == .unavailable else { throw WorkshopOwnedIssue.malformed }
        } else {
            switch storedStatus {
            case .active: guard status == .active || status == .expired || status == .unavailable else { throw WorkshopOwnedIssue.malformed }
            case .suspended: guard status == .suspended || status == .unavailable else { throw WorkshopOwnedIssue.malformed }
            case .revoked: guard status == .revoked || status == .unavailable else { throw WorkshopOwnedIssue.malformed }
            case .expired: guard status == .expired || status == .unavailable else { throw WorkshopOwnedIssue.malformed }
            }
        }
    }
}

public struct WorkshopOwnedReadMetadata: Decodable, Equatable {
    public enum Availability: String, Decodable { case freeClaimsOnly = "FREE_CLAIMS_ONLY", notEnabled = "NOT_ENABLED" }
    public let availability: Availability
    public let checkedAt: String
    private enum CodingKeys: String, CodingKey { case schema, scope, availability, purchasedLibraryStatus, contentUseStatus, checkedAt }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        availability = try c.decode(Availability.self, forKey: .availability)
        checkedAt = try c.decode(String.self, forKey: .checkedAt)
        guard try c.decode(String.self, forKey: .schema) == "workshop-owned-v1",
              try c.decode(String.self, forKey: .scope) == "FREE_INDIVIDUAL_ONLY",
              try c.decode(String.self, forKey: .purchasedLibraryStatus) == "NOT_AVAILABLE",
              try c.decode(String.self, forKey: .contentUseStatus) == "UNAVAILABLE",
              WorkshopOwnedWire.timestamp(checkedAt) else { throw WorkshopOwnedIssue.malformed }
    }
}

public struct WorkshopOwnedPage: Decodable, Equatable {
    public let metadata: WorkshopOwnedReadMetadata
    public let items: [WorkshopOwnedItem]
    public let hasMore: Bool
    private enum CodingKeys: String, CodingKey { case items, hasMore }
    public init(from decoder: Decoder) throws {
        try WorkshopOwnedWire.exactKeys(decoder, WorkshopOwnedWire.metadataKeys.union(["items", "hasMore"]))
        metadata = try .init(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hasMore = try c.decode(Bool.self, forKey: .hasMore)
        var sequence = try c.nestedUnkeyedContainer(forKey: .items)
        var rows: [WorkshopOwnedItem] = [], seen = Set<String>()
        while !sequence.isAtEnd {
            guard rows.count < 50 else { throw WorkshopOwnedIssue.malformed }
            let item = try sequence.decode(WorkshopOwnedItem.self)
            guard seen.insert(item.id).inserted else { throw WorkshopOwnedIssue.malformed }
            rows.append(item)
        }
        guard !hasMore || rows.count == 50, metadata.availability == .freeClaimsOnly || (rows.isEmpty && !hasMore) else { throw WorkshopOwnedIssue.malformed }
        items = rows
    }
}

public struct WorkshopOwnedDetail: Decodable, Equatable {
    public let metadata: WorkshopOwnedReadMetadata
    public let item: WorkshopOwnedItem?
    private enum CodingKeys: String, CodingKey { case item }
    public init(from decoder: Decoder) throws {
        try WorkshopOwnedWire.exactKeys(decoder, WorkshopOwnedWire.metadataKeys.union(["item"]))
        metadata = try .init(from: decoder)
        item = try decoder.container(keyedBy: CodingKeys.self).decodeIfPresent(WorkshopOwnedItem.self, forKey: .item)
        guard (metadata.availability == .freeClaimsOnly) == (item != nil) else { throw WorkshopOwnedIssue.malformed }
    }
}

enum WorkshopOwnedWire {
    static let metadataKeys: Set<String> = ["schema", "scope", "availability", "purchasedLibraryStatus", "contentUseStatus", "checkedAt"]
    private struct Key: CodingKey {
        let stringValue: String
        let intValue: Int? = nil
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
    static func exactKeys(_ decoder: Decoder, _ expected: Set<String>) throws {
        guard Set(try decoder.container(keyedBy: Key.self).allKeys.map(\.stringValue)) == expected else { throw WorkshopOwnedIssue.malformed }
    }
    static func identifier(_ value: String) -> Bool {
        (1...128).contains(value.utf8.count) && value.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [58, 95, 45].contains($0)
        }
    }
    static func timestamp(_ value: String) -> Bool {
        // UTC display metadata, not a client clock or missing-expiry-to-perpetual conversion.
        value.utf8.count <= 40 && value.range(of: #"\A[0-9]{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])T([01][0-9]|2[0-3]):[0-5][0-9]:[0-5][0-9](\.[0-9]{1,9})?Z\z"#, options: .regularExpression) != nil
    }
}

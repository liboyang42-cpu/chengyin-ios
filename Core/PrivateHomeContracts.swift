import Foundation

public enum PrivateHomeIssue: String, Error { case disabled, invalid, staleSession, storageUnavailable, unknownOutcome, unavailable, busy }
/// Never route private-home values through public map, NPC, telemetry, or generic logging APIs.
public struct PrivateHomePoint: Codable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public let latitude: Decimal
    public let longitude: Decimal
    public let datum: String
    public init(latitude: Decimal, longitude: Decimal) throws {
        func valid(_ n: Decimal, limit: Decimal) -> Bool {
            var source = n, rounded = Decimal(); NSDecimalRound(&rounded, &source, 6, .plain)
            return !n.isNaN && n >= -limit && n <= limit && rounded == n
        }
        guard valid(latitude, limit: 90), valid(longitude, limit: 180) else { throw PrivateHomeIssue.invalid }
        self.latitude = latitude; self.longitude = longitude; datum = "WGS84"
    }
    public static func parse(latitude: String, longitude: String) throws -> PrivateHomePoint {
        func number(_ text: String) throws -> Decimal {
            guard text.range(of: "\\A[+-]?[0-9]{1,3}(?:\\.[0-9]{1,6})?\\z", options: .regularExpression) != nil,
                  let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) else { throw PrivateHomeIssue.invalid }
            return value
        }
        return try PrivateHomePoint(latitude: number(latitude), longitude: number(longitude))
    }
    public var description: String { "PrivateHome[redacted]" }
    public var debugDescription: String { description }
}
public struct PrivateHomeSnapshot: Decodable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public enum Status: String, Decodable { case active = "ACTIVE", deleted = "DELETED" }
    public let version: Int64
    public let status: Status
    public let changedAt: Int64?
    public let effectiveAt: Int64?
    public let label: String?
    public let latitude: Decimal?
    public let longitude: Decimal?
    public let datum: String?
    public func validate() throws {
        guard version >= 0 else { throw PrivateHomeIssue.invalid }
        if status == .active {
            guard let label, PrivateHomeMutation.validLabel(label), let latitude, let longitude,
                  datum == "WGS84", let changedAt, changedAt >= 0, let effectiveAt, effectiveAt >= changedAt else { throw PrivateHomeIssue.invalid }
            _ = try PrivateHomePoint(latitude: latitude, longitude: longitude)
        } else if label != nil || latitude != nil || longitude != nil || datum != nil { throw PrivateHomeIssue.invalid }
    }
    public var description: String { "PrivateHome[redacted]" }
    public var debugDescription: String { description }
}
/// Encodes only the exact controller body. Owner identity is never caller-supplied.
public struct PrivateHomeMutation: Codable, Equatable, CustomStringConvertible, CustomDebugStringConvertible {
    public let requestId: String
    public let expectedVersion: Int64
    public let label: String?
    public let latitude: Decimal?
    public let longitude: Decimal?
    public let datum: String?
    public var method: String { label == nil ? "DELETE" : "PUT" }
    public init(requestId: String = UUID().uuidString, expectedVersion: Int64, label: String? = nil, point: PrivateHomePoint? = nil) throws {
        self.requestId = requestId; self.expectedVersion = expectedVersion; self.label = label
        latitude = point?.latitude; longitude = point?.longitude; datum = point?.datum
        try validate()
    }
    public func validate() throws {
        guard requestId.range(of: "\\A[A-Za-z0-9._:-]{1,64}\\z", options: .regularExpression) != nil,
              expectedVersion >= 0, expectedVersion < Int64.max else { throw PrivateHomeIssue.invalid }
        if let label {
            guard Self.validLabel(label), let latitude, let longitude, datum == "WGS84" else { throw PrivateHomeIssue.invalid }
            _ = try PrivateHomePoint(latitude: latitude, longitude: longitude)
        } else if latitude != nil || longitude != nil || datum != nil { throw PrivateHomeIssue.invalid }
    }
    static func validLabel(_ value: String) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.utf16.count <= 40 &&
        value.unicodeScalars.allSatisfy { $0.value <= 0xFFFF && !CharacterSet.controlCharacters.contains($0) }
    }
    public var description: String { "PrivateHome[redacted]" }
    public var debugDescription: String { description }
}
public struct PrivateHomeReceipt: Decodable, Equatable {
    public enum Decision: String, Decodable { case saved = "SAVED", deleted = "DELETED", conflict = "VERSION_CONFLICT", cooldown = "HOME_CHANGE_COOLDOWN", forbidden = "PLACE_NOT_ALLOWED" }
    public let requestId: String
    public let decision: Decision
    public let version: Int64
    public func validate(for mutation: PrivateHomeMutation) throws {
        guard requestId == mutation.requestId, version >= 0 else { throw PrivateHomeIssue.invalid }
        switch decision {
        case .saved: guard mutation.method == "PUT", version == mutation.expectedVersion + 1 else { throw PrivateHomeIssue.invalid }
        case .deleted: guard mutation.method == "DELETE", version == mutation.expectedVersion + 1 else { throw PrivateHomeIssue.invalid }
        case .cooldown, .forbidden: guard mutation.method == "PUT", version == mutation.expectedVersion else { throw PrivateHomeIssue.invalid }
        case .conflict: guard version != mutation.expectedVersion else { throw PrivateHomeIssue.invalid }
        }
    }
}
@MainActor public protocol PrivateHomeServing {
    func load() async throws -> PrivateHomeSnapshot
    func mutate(_ mutation: PrivateHomeMutation) async throws -> PrivateHomeReceipt
}
/// Implementations MUST be durable, confidential, atomic and scoped to canonical realm+account.
/// No production implementation is enabled by default. UserDefaults/plain files/in-memory fallbacks are forbidden.
/// Persist exact bytes BEFORE dispatch; retain across process death/logout. Never clear on GET alone.
/// save MUST atomically insert-if-empty (or accept the identical existing mutation), never overwrite
/// a different pending request. clear MUST atomically compare full pending identity before removal.
/// read failure MUST throw, never masquerade as an empty journal; implementations serialize writers.
public struct PrivateHomeJournalScope: Equatable {
    public let namespace: String
    public let accountID: Int
    public init(owner: PlayExperienceSession) { namespace = owner.namespace; accountID = owner.accountID }
}
@MainActor public protocol PrivateHomeSecureJournaling {
    var scope: PrivateHomeJournalScope { get }
    func read() async throws -> PrivateHomeMutation?
    func save(_ mutation: PrivateHomeMutation) async throws
    func clear(matching mutation: PrivateHomeMutation) async throws
}

import Foundation
import CryptoKit

/// Aggregate policy only: no photo, node, coordinate or leaderboard authoring is implied.
public enum NativeProgressPrivacyScope: String, Codable, CaseIterable, Identifiable {
    case onlySelf = "SELF", friend = "FRIEND", team = "TEAM", channel = "CHANNEL", everyone = "PUBLIC"
    public var id: String { rawValue }
    public var label: String {
        switch self { case .onlySelf: return "仅自己"; case .friend: return "好友"; case .team: return "同队成员"; case .channel: return "同频道成员"; case .everyone: return "公开" }
    }
}
public struct NativeProgressPrivacyTarget: Equatable {
    public enum Kind: String, Codable { case user = "USER", channel = "CHANNEL" }
    public let kind: Kind
    public let id: Int64
    public init(kind: Kind, id: Int64) throws { guard id > 0 else { throw NativeProgressPrivacyFailure.invalid }; self.kind = kind; self.id = id }
    public var path: String { kind == .user ? "api/privacy/progress" : "api/channel/\(id)/progress/privacy" }
}
public struct NativeProgressPrivacyApproval: Equatable {
    public let issuanceID: UUID
    public let endpoint: OperationEndpointApproval
    public let target: NativeProgressPrivacyTarget
    public let expiresAt: Date
    public let allowsWrite: Bool
    public static let receiptPath = "api/progress/requests"
    public init(endpoint: OperationEndpointApproval, target: NativeProgressPrivacyTarget, expiresAt: Date,
                allowsWrite: Bool = false, issuanceID: UUID = UUID()) throws {
        guard endpoint.paths == [target.path, Self.receiptPath], expiresAt.timeIntervalSince1970.isFinite,
              target.kind != .user || target.id == Int64(endpoint.accountID) else { throw NativeProgressPrivacyFailure.invalid }
        self.endpoint = endpoint; self.target = target; self.expiresAt = expiresAt; self.allowsWrite = allowsWrite; self.issuanceID = issuanceID
    }
}
public struct NativeProgressPrivacySnapshot: Decodable, Equatable {
    public let actorID: Int64
    public let kind: NativeProgressPrivacyTarget.Kind
    public let scopeID: Int64
    public let aggregate: NativeProgressPrivacyScope
    public let detail: String
    public let photo: String?
    public let leaderboard: String?
    public let boardEnabled: Int?
    public let revision: Int?
    public let updatedAt: String?
    public let verifiedAt: String?
    public let isDefault: Bool
    public let appliesTo: String
    public let editableFields: [String]
    public let canWrite: Bool
    public let aggregateVerified: Bool
    enum CodingKeys: String, CodingKey {
        case actorID = "actor_id", kind = "scope_type", scopeID = "scope_id", aggregate = "aggregate_scope", detail = "detail_scope"
        case photo = "photo_scope", leaderboard = "leaderboard_scope", boardEnabled = "board_enabled", revision
        case updatedAt = "updated_at", verifiedAt = "verified_at", isDefault = "is_default", appliesTo = "applies_to"
        case editableFields = "editable_fields", canWrite = "can_write", aggregateVerified = "aggregate_verified"
    }
    /// Presentation of this original current snapshot only. This is not a global effective permission.
    /// The final original consumer also evaluates viewer/peer and actual activity/channel/session context.
    public enum AggregateReadState: Equatable {
        case confirmedAbsentDefault, configuredConsumerConfirmed, configuredConsumerUnconfirmed
    }
    public var aggregateReadState: AggregateReadState {
        if isDefault { return .confirmedAbsentDefault }
        return aggregateVerified ? .configuredConsumerConfirmed : .configuredConsumerUnconfirmed
    }
    public func validate(actor: Int64, target: NativeProgressPrivacyTarget) throws {
        guard actorID == actor, kind == target.kind, scopeID == target.id, appliesTo == "ALL", editableFields == ["aggregate_scope"],
              ["SELF", "TEAM", "CHANNEL"].contains(detail),
              updatedAt.map(NativeProgressPrivacyValidation.timestamp) ?? isDefault,
              !isDefault || (updatedAt == nil && aggregate == .everyone && !aggregateVerified) else { throw NativeProgressPrivacyFailure.malformed }
        if kind == .user {
            guard revision == nil, boardEnabled == nil, ["SELF", "TEAM", "ADMIN"].contains(photo ?? ""),
                  ["IN", "OUT"].contains(leaderboard ?? ""), verifiedAt.map(NativeProgressPrivacyValidation.timestamp) ?? true else { throw NativeProgressPrivacyFailure.malformed }
        } else {
            guard let revision, revision >= 0, revision <= Int(Int32.max), [0, 1].contains(boardEnabled ?? -1),
                  photo == nil, leaderboard == nil, verifiedAt == nil, !isDefault || revision == 0 else { throw NativeProgressPrivacyFailure.malformed }
        }
    }
}
public struct NativeProgressPrivacyCommand {
    public let requestID: UUID
    public let target: NativeProgressPrivacyTarget
    public let aggregate: NativeProgressPrivacyScope
    public let expectedUpdatedAt: String?
    public let expectedRevision: Int?
    public init(snapshot: NativeProgressPrivacySnapshot, aggregate: NativeProgressPrivacyScope, requestID: UUID = UUID()) throws {
        target = try NativeProgressPrivacyTarget(kind: snapshot.kind, id: snapshot.scopeID)
        guard snapshot.canWrite else { throw NativeProgressPrivacyFailure.closed }
        if target.kind == .channel { guard let revision = snapshot.revision, revision < Int(Int32.max) else { throw NativeProgressPrivacyFailure.closed } }
        self.requestID = requestID; self.aggregate = aggregate; expectedUpdatedAt = snapshot.updatedAt; expectedRevision = snapshot.revision
    }
    public func fields() -> [String: Any] {
        var value: [String: Any] = ["request_id": requestID.uuidString, "aggregate_scope": aggregate.rawValue]
        if target.kind == .user { value["expected_updated_at"] = expectedUpdatedAt.map { $0 as Any } ?? NSNull() }
        else { value["expected_revision"] = expectedRevision }
        return value
    }
    public func body() throws -> Data { try JSONSerialization.data(withJSONObject: fields(), options: [.sortedKeys]) }
    public func fingerprint() throws -> String {
        var fields = fields(); fields["scope_type"] = target.kind.rawValue; fields["scope_id"] = target.id
        var raw = "progress-privacy-v1\n"
        for key in fields.keys.sorted() {
            raw += "\(key.utf8.count):\(key)"
            if fields[key] is NSNull { raw += "N" }
            else if let value = fields[key] as? String { raw += "S\(value.utf8.count):\(value)" }
            else if let value = fields[key] as? NSNumber { raw += "I\(value.int64Value);" }
            else { throw NativeProgressPrivacyFailure.invalid }
        }
        return SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
public struct NativeProgressPrivacyReceipt: Decodable {
    public let actorID: Int64
    public let requestID: String
    public let kind: NativeProgressPrivacyTarget.Kind?
    public let scopeID: Int64?
    public let payloadHash: String?
    public let outcome: String
    public let reason: String?
    public let appliedUpdatedAt: String?
    public let appliedRevision: Int?
    enum CodingKeys: String, CodingKey {
        case actorID = "actor_id", requestID = "request_id", kind = "scope_type", scopeID = "scope_id", payloadHash = "payload_hash", outcome, reason
        case appliedUpdatedAt = "applied_updated_at", appliedRevision = "applied_revision"
    }
}
public enum NativeProgressPrivacyFailure: Error { case invalid, malformed, closed, unknown, server(Int) }
public enum NativeProgressPrivacyValidation {
    public static func timestamp(_ value: String) -> Bool { value.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\\.[0-9]{6}$", options: .regularExpression) != nil }
}
/// Ephemeral, payload-free cache generation only. It is not a policy, permission, remote event or stored counter.
@MainActor public enum NativeProgressPrivacyInvalidation {
    public private(set) static var revision: UInt64 = 0
    private static var unresolved: [String: Set<UUID>] = [:]
    private static var unconfirmedStorage: Set<String> = []
    public static func owner(origin: URL, namespace: String, actor: Int64) -> String {
        let bytes = try? JSONSerialization.data(withJSONObject: [origin.absoluteString, namespace, String(actor)])
        return bytes.map { "progress-privacy:" + $0.base64EncodedString() } ?? "progress-privacy:unconfigured"
    }
    public static func blocked(owner: String) -> Bool { unconfirmedStorage.contains(owner) || !(unresolved[owner] ?? []).isEmpty }
    public static func restore(owner: String, requests: Set<UUID>?) {
        guard let requests else { if unconfirmedStorage.insert(owner).inserted { invalidate() }; return }
        let wasUnconfirmed = unconfirmedStorage.remove(owner) != nil
        let changed = unresolved[owner] != requests || wasUnconfirmed
        unresolved[owner] = requests; if changed { invalidate() }
    }
    public static func pending(owner: String, request: UUID) { unresolved[owner, default: []].insert(request); invalidate() }
    public static func resolved(owner: String, request: UUID) { unresolved[owner]?.remove(request); invalidate() }
    public static func invalidate() { revision &+= 1 }
}

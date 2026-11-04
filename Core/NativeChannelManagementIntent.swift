import Foundation

public struct NativeChannelManagementDraft: Equatable {
    public var name = ""
    public var topic = ""
    public var slowmodeSeconds = 0
    public var visibility = 1
    public var kind = 1
    public var parentID = "0"
    public init() {}
    public init(channel: NativeChannelManagementChannel) {
        name = channel.name; topic = channel.topic ?? ""; slowmodeSeconds = channel.slowmodeSeconds
        visibility = channel.visibility; kind = channel.kind; parentID = channel.parentID
    }
    public func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name.unicodeScalars.count <= 64, !name.contains("/"), !name.contains("#"),
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              topic.unicodeScalars.count <= 120, (0...21600).contains(slowmodeSeconds),
              [1,2].contains(visibility), (0...2).contains(kind),
              parentID == "0" || (try? NativeChannelManagementID(parentID)) != nil,
              kind != 0 || parentID == "0" else { throw NativeChannelManagementError.invalidDraft }
    }
}

/// Owned JSON type. Explicit null is preserved; no shared JSON policy is changed.
public enum NativeChannelManagementJSON: Codable, Equatable {
    case string(String), integer(Int64), null
    public init(from decoder: Decoder) throws {
        let box = try decoder.singleValueContainer()
        if box.decodeNil() { self = .null }
        else if let text = try? box.decode(String.self) { self = .string(text) }
        else { self = .integer(try box.decode(Int64.self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var box = encoder.singleValueContainer()
        switch self { case .string(let text): try box.encode(text); case .integer(let value): try box.encode(value); case .null: try box.encodeNil() }
    }
}

/// Immutable original command: exact request, target, reason, base version and bytes.
/// Epoch/token/authority never enter durable storage. New sessions may query this owner-scoped original.
public struct NativeChannelManagementIntent: Codable, Equatable {
    public enum Operation: String, Codable { case create, edit, archive, unarchive, delete, restore, putOverwrite, deleteOverwrite }
    public let schema: Int
    public let scope: NativeChannelManagementScope
    public let operation: Operation
    public let channelID: NativeChannelManagementID?
    public let requestID: String
    public let expectedVersion: NativeChannelManagementVersion?
    public let permissionVersion: NativeChannelManagementVersion?
    public let targetType: Int?
    public let targetID: String?
    public let reason: String
    public let fields: [String: NativeChannelManagementJSON]
    public var isPermissionChange: Bool { operation == .putOverwrite || operation == .deleteOverwrite }
    /// v1 permission originals keep their historical body and remain lookup-only.
    /// Only newly prepared v2 permissions bind both server CAS versions.
    public var hasPermissionCAS: Bool { isPermissionChange && schema == 2 }
    public var method: String {
        switch operation { case .edit: return "PATCH"; case .delete, .deleteOverwrite: return "DELETE"; case .putOverwrite: return "PUT"; default: return "POST" }
    }
    public var path: String {
        if operation == .create { return "api/guilds/\(scope.guildKind)/\(scope.guildID)/channels" }
        let base = "api/channels/\(channelID?.rawValue ?? "")"
        switch operation {
        case .archive, .unarchive: return base + "/archive"
        case .restore: return base + "/restore"
        case .putOverwrite, .deleteOverwrite: return base + "/permissions/\(targetType ?? -1)/\(targetID ?? "")"
        default: return base
        }
    }
    public var receiptPath: String {
        (isPermissionChange ? "api/channel-platform/governance/requests/" : "api/channel-platform/requests/") + requestID
    }
    public func body() throws -> Data {
        try validate()
        var value = fields
        value["request_id"] = .string(requestID); value["reason"] = .string(reason)
        if let expectedVersion, !isPermissionChange || hasPermissionCAS {
            value["expected_version"] = .string(String(expectedVersion.value))
        }
        if hasPermissionCAS, let permissionVersion {
            value["expected_perm_version"] = .string(String(permissionVersion.value))
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value)
    }
    private init(scope: NativeChannelManagementScope, operation: Operation, channel: NativeChannelManagementChannel?,
                 requestID: String, reason: String, fields: [String: NativeChannelManagementJSON],
                 permissionVersion: NativeChannelManagementVersion? = nil, targetType: Int? = nil, targetID: String? = nil) throws {
        schema = (operation == .putOverwrite || operation == .deleteOverwrite) ? 2 : 1
        self.scope = scope; self.operation = operation; channelID = channel?.id
        self.requestID = requestID; self.reason = reason; self.fields = fields
        expectedVersion = channel?.version; self.permissionVersion = permissionVersion
        self.targetType = targetType; self.targetID = targetID
        try validate()
    }
    public static func create(scope: NativeChannelManagementScope, draft: NativeChannelManagementDraft, reason: String,
                              requestID: String = UUID().uuidString) throws -> Self {
        try draft.validate()
        return try .init(scope: scope, operation: .create, channel: nil, requestID: requestID, reason: reason, fields: [
            "name": .string(draft.name), "topic": draft.topic.isEmpty ? .null : .string(draft.topic),
            "kind": .integer(Int64(draft.kind)), "parent_id": .string(draft.parentID),
            "visibility": .integer(Int64(draft.visibility)), "slowmode_sec": .integer(Int64(draft.slowmodeSeconds))])
    }
    public static func edit(channel: NativeChannelManagementChannel, draft: NativeChannelManagementDraft, reason: String,
                            requestID: String = UUID().uuidString) throws -> Self {
        try draft.validate(); try channel.requireDetail(in: channel.scope)
        guard channel.canManage, channel.status == 0, draft.kind == channel.kind, draft.parentID == channel.parentID else { throw NativeChannelManagementError.forbidden }
        var fields: [String: NativeChannelManagementJSON] = [:]
        if draft.name != channel.name { fields["name"] = .string(draft.name) }
        if draft.topic != (channel.topic ?? "") { fields["topic"] = draft.topic.isEmpty ? .null : .string(draft.topic) }
        if draft.visibility != channel.visibility { fields["visibility"] = .integer(Int64(draft.visibility)) }
        if draft.slowmodeSeconds != channel.slowmodeSeconds { fields["slowmode_sec"] = .integer(Int64(draft.slowmodeSeconds)) }
        guard !fields.isEmpty else { throw NativeChannelManagementError.invalidDraft }
        return try .init(scope: channel.scope, operation: .edit, channel: channel, requestID: requestID, reason: reason, fields: fields)
    }
    public static func lifecycle(_ operation: Operation, channel: NativeChannelManagementChannel, reason: String,
                                 requestID: String = UUID().uuidString) throws -> Self {
        guard [.archive, .unarchive, .delete].contains(operation), channel.canManage else { throw NativeChannelManagementError.forbidden }
        if operation == .delete && !channel.canDelete { throw NativeChannelManagementError.forbidden }
        if operation == .archive && channel.status != 0 { throw NativeChannelManagementError.invalidDraft }
        if operation == .unarchive && (channel.status != 1 || channel.archiveReason != "manual") { throw NativeChannelManagementError.forbidden }
        let fields: [String: NativeChannelManagementJSON] = operation == .archive || operation == .unarchive
            ? ["archived": .integer(operation == .archive ? 1 : 0)] : [:]
        return try .init(scope: channel.scope, operation: operation, channel: channel, requestID: requestID, reason: reason, fields: fields)
    }
    /// Restore is prepared from the real manager endpoint's typed result, not sparse row permissions.
    /// The coordinator checks current identity; execute repeats the manager read and version check.
    public static func restore(channelID: NativeChannelManagementID, inventory: NativeChannelManagementInventory,
                               reason: String, requestID: String = UUID().uuidString) throws -> Self {
        let channel = try inventory.restorableChannel(channelID)
        return try .init(scope: inventory.scope, operation: .restore, channel: channel,
            requestID: requestID, reason: reason, fields: [:])
    }
    public static func overwrite(channel: NativeChannelManagementChannel, permissions: NativeChannelManagementPermissions,
                                 row: NativeChannelManagementOverwrite, remove: Bool, reason: String,
                                 requestID: String = UUID().uuidString) throws -> Self {
        guard channel.canManagePermissions, channel.id == permissions.channelID, channel.version == permissions.version,
              channel.permissionVersion == permissions.permissionVersion else { throw NativeChannelManagementError.versionConflict }
        let masks = try row.masks()
        let owned = NativeChannelManagementCapability.allCases.filter { channel.permissionNames.contains($0.rawValue) }.reduce(UInt64(0)) { $0 | $1.bit }
        guard remove || masks.allow & ~owned == 0 else { throw NativeChannelManagementError.forbidden }
        return try .init(scope: channel.scope, operation: remove ? .deleteOverwrite : .putOverwrite, channel: channel,
            requestID: requestID, reason: reason, fields: remove ? [:] : ["allow_bits": .string(row.allowBits),
                "deny_bits": .string(row.denyBits), "note": row.note.map(NativeChannelManagementJSON.string) ?? .null],
            permissionVersion: permissions.permissionVersion, targetType: row.targetType, targetID: row.targetID)
    }
    public func validate() throws {
        guard schema == 1 || (schema == 2 && isPermissionChange), (1...3).contains(scope.guildKind), requestID.range(of: "^[A-Za-z0-9_.:-]{8,64}$", options: .regularExpression) != nil,
              !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, reason.utf16.count <= 120,
              !reason.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              (operation == .create) == (channelID == nil), (operation == .create) == (expectedVersion == nil) else {
            throw NativeChannelManagementError.invalidDraft
        }
        let allowed: Set<String>
        switch operation {
        case .create: allowed = ["name", "topic", "kind", "parent_id", "visibility", "slowmode_sec"]
        case .edit: allowed = ["name", "topic", "visibility", "slowmode_sec"]
        case .archive, .unarchive: allowed = ["archived"]
        case .putOverwrite: allowed = ["allow_bits", "deny_bits", "note"]
        default: allowed = []
        }
        guard Set(fields.keys).isSubset(of: allowed), ![.create, .edit, .archive, .unarchive, .putOverwrite].contains(operation) || !fields.isEmpty else {
            throw NativeChannelManagementError.invalidDraft
        }
        if isPermissionChange {
            guard permissionVersion != nil, let type = targetType, let target = targetID,
                  (type == 1 && target == "0") || (type == 2 && (try? NativeChannelManagementID(target)) != nil) else { throw NativeChannelManagementError.invalidDraft }
        } else if targetType != nil || targetID != nil || permissionVersion != nil { throw NativeChannelManagementError.invalidDraft }
        func text(_ key: String) throws -> String {
            guard case .some(.string(let value)) = fields[key] else { throw NativeChannelManagementError.invalidDraft }; return value
        }
        func number(_ key: String) throws -> Int64 {
            guard case .some(.integer(let value)) = fields[key] else { throw NativeChannelManagementError.invalidDraft }; return value
        }
        if operation == .create || operation == .edit {
            if operation == .create && Set(fields.keys) != allowed { throw NativeChannelManagementError.invalidDraft }
            if fields["name"] != nil {
                let name = try text("name")
                guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.unicodeScalars.count <= 64,
                      !name.contains("/"), !name.contains("#"), !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
                    throw NativeChannelManagementError.invalidDraft
                }
            }
            if let topic = fields["topic"], topic != .null { guard try text("topic").unicodeScalars.count <= 120 else { throw NativeChannelManagementError.invalidDraft } }
            if fields["visibility"] != nil { guard try [Int64(1),2].contains(number("visibility")) else { throw NativeChannelManagementError.invalidDraft } }
            if fields["slowmode_sec"] != nil { guard try (Int64(0)...21600).contains(number("slowmode_sec")) else { throw NativeChannelManagementError.invalidDraft } }
            if operation == .create {
                let kind = try number("kind"), parent = try text("parent_id")
                guard (0...2).contains(kind), parent == "0" || (try? NativeChannelManagementID(parent)) != nil,
                      kind != 0 || parent == "0" else { throw NativeChannelManagementError.invalidDraft }
            }
        }
        if operation == .archive || operation == .unarchive {
            guard try number("archived") == (operation == .archive ? 1 : 0) else { throw NativeChannelManagementError.invalidDraft }
        }
        if operation == .putOverwrite {
            guard let targetType, let targetID else { throw NativeChannelManagementError.invalidDraft }
            let note: String? = fields["note"] == .null ? nil : try text("note")
            _ = try NativeChannelManagementOverwrite(targetType: targetType, targetID: targetID,
                allowBits: text("allow_bits"), denyBits: text("deny_bits"), note: note)
        }
    }
}

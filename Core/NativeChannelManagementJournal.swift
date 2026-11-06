import Foundation

/// Persistent owner key excludes epoch/token so the original may be recovered after a fresh login.
/// Live UI/transport fences separately bind epoch, viewer, role and deployment approval revision.
public struct NativeChannelManagementOwner: Codable, Equatable {
    public let accountID: Int
    public let namespace: String
    public let baseURL: String
    public init(accountID: Int, namespace: String, baseURL: URL) throws {
        _ = try APIConfiguration(baseURL: baseURL)
        guard accountID > 0, !namespace.isEmpty else { throw NativeChannelManagementError.invalidSource }
        self.accountID = accountID; self.namespace = namespace; self.baseURL = baseURL.absoluteString
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.accountID == rhs.accountID && lhs.namespace.utf8.elementsEqual(rhs.namespace.utf8) && lhs.baseURL.utf8.elementsEqual(rhs.baseURL.utf8)
    }
}

@MainActor public final class NativeChannelManagementJournal {
    public let owner: NativeChannelManagementOwner
    public let scope: NativeChannelManagementScope
    private let storage: any ProjectEditDataStorage
    private static var operations: [String: UUID] = [:]
    private var key: String {
        let fields = [owner.namespace, owner.baseURL, String(owner.accountID), String(scope.guildKind), scope.guildID.rawValue]
        return "native-channel-management.v1." + Data(fields.map { "\($0.utf8.count):\($0)" }.joined().utf8).base64EncodedString()
    }
    private struct Record: Codable { let schema: Int; let owner: NativeChannelManagementOwner; let scope: NativeChannelManagementScope; let intent: NativeChannelManagementIntent }
    public init(owner: NativeChannelManagementOwner, scope: NativeChannelManagementScope, storage: any ProjectEditDataStorage) {
        self.owner = owner; self.scope = scope; self.storage = storage
    }
    public func beginOperation() -> UUID? {
        guard Self.operations[key] == nil else { return nil }; let id = UUID(); Self.operations[key] = id; return id
    }
    public func endOperation(_ id: UUID) { if Self.operations[key] == id { Self.operations[key] = nil } }
    public func restore() throws -> NativeChannelManagementIntent? {
        guard let data = try storage.read(key) else { return nil }
        guard data.count <= 32 * 1024, let row = try? JSONDecoder().decode(Record.self, from: data), row.schema == 1,
              row.owner == owner, row.scope == scope, row.intent.scope == scope,
              preservesRecordIdentity(data) else { throw NativeChannelManagementError.storageUnavailable }
        try row.intent.validate(); return row.intent
    }
    /// Codable ignores unrecognized keys. Do not let that lossy projection authorize
    /// resending or removing an original with an identity this version cannot read.
    /// Check shape only: the original decoder still accepts its documented integer
    /// or decimal-string versions and absent/explicit-null known optional fields.
    /// Neither reading nor accepting an identical original rewrites protected bytes.
    private func preservesRecordIdentity(_ data: Data) -> Bool {
        guard let raw = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              Set(raw.keys) == ["schema", "owner", "scope", "intent"],
              let owner = raw["owner"] as? [String: Any],
              Set(owner.keys) == ["accountID", "namespace", "baseURL"],
              let scope = raw["scope"] as? [String: Any],
              Set(scope.keys) == ["guildKind", "guildID"],
              let intent = raw["intent"] as? [String: Any],
              let intentScope = intent["scope"] as? [String: Any],
              Set(intentScope.keys) == ["guildKind", "guildID"] else { return false }
        let required: Set<String> = ["schema", "scope", "operation", "requestID", "reason", "fields"]
        let optional: Set<String> = ["channelID", "expectedVersion", "permissionVersion", "targetType", "targetID"]
        let keys = Set(intent.keys)
        // Intent.validate separately verifies each known value and the exact
        // operation-specific fields. Unknown fields are not normalized away.
        return required.isSubset(of: keys) && keys.isSubset(of: required.union(optional))
    }
    public func saveBeforeDispatch(_ intent: NativeChannelManagementIntent) throws {
        try intent.validate(); guard intent.scope == scope else { throw NativeChannelManagementError.invalidSource }
        if let original = try restore() {
            guard try original.body() == intent.body(), original == intent else { throw NativeChannelManagementError.pendingOriginal }; return
        }
        try storage.write(JSONEncoder().encode(Record(schema: 1, owner: owner, scope: scope, intent: intent)), key: key)
        guard try restore() == intent else { throw NativeChannelManagementError.storageUnavailable }
    }
    /// Only a proven APPLIED result or an explicit, known domain rejection may settle an original.
    /// NOT_FOUND, logout, cancel, timeout, malformed response and 5xx never call this method.
    public func settle(_ intent: NativeChannelManagementIntent) throws {
        guard let original = try restore() else { return }
        guard original == intent, try original.body() == intent.body() else { throw NativeChannelManagementError.pendingOriginal }
        try storage.remove(key); guard try restore() == nil else { throw NativeChannelManagementError.storageUnavailable }
    }
}

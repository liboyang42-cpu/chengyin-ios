import Foundation

/// Durable identity excludes transient login epochs, but includes the exact deployment,
/// namespace and owner. Contents live only in the host's protected SecureStorage.
public struct NativeChannelTextScope: Codable, Equatable {
    public let accountID: Int
    public let namespace: String
    public let baseURL: String
    public let conversationID: Int
    public init(context: RuntimeDependencyContext, conversationID: Int) throws {
        _ = try APIConfiguration(baseURL: context.baseURL)
        guard context.market == .china, context.session.accountID > 0, conversationID > 0,
              !context.session.namespace.isEmpty else { throw APIError.invalidConfiguration }
        accountID = context.session.accountID; namespace = context.session.namespace
        baseURL = context.baseURL.absoluteString; self.conversationID = conversationID
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.accountID == rhs.accountID && lhs.conversationID == rhs.conversationID
            && lhs.namespace.utf8.elementsEqual(rhs.namespace.utf8) && lhs.baseURL.utf8.elementsEqual(rhs.baseURL.utf8)
    }
    fileprivate var key: String {
        // Length-prefixed fields prevent delimiter collisions. No content or token in keys.
        let owner = [namespace, baseURL, String(accountID), String(conversationID)]
            .map { "\($0.utf8.count):\($0)" }.joined()
        return "native-channel-text.v1." + Data(owner.utf8).base64EncodedString()
    }
}

public enum NativeChannelTextJournalError: Error { case unavailable, incompatible, pendingIntent }

/// A single original MessageTextIntent, not another message/history truth source.
@MainActor public final class NativeChannelTextJournal {
    private static var operations: [String: UUID] = [:]
    private let storage: any ProjectEditDataStorage
    public let scope: NativeChannelTextScope
    public init(storage: any ProjectEditDataStorage, scope: NativeChannelTextScope) {
        self.storage = storage; self.scope = scope
    }
    public func beginOperation() -> UUID? {
        guard Self.operations[scope.key] == nil else { return nil }
        let id = UUID(); Self.operations[scope.key] = id; return id
    }
    public func endOperation(_ id: UUID) {
        if Self.operations[scope.key] == id { Self.operations[scope.key] = nil }
    }
    public static func same(_ lhs: MessageTextIntent?, _ rhs: MessageTextIntent?) -> Bool {
        guard let lhs, let rhs else { return lhs == nil && rhs == nil }
        return lhs.conversationID == rhs.conversationID
            && lhs.clientMessageID.utf8.elementsEqual(rhs.clientMessageID.utf8)
            && lhs.content.utf8.elementsEqual(rhs.content.utf8)
            && NativeChannelMessageTextReference.sameIdentityBytes(lhs.channelReference, rhs.channelReference)
    }
    private struct StoredRecord: Codable {
        let version: Int
        let scope: NativeChannelTextScope
        let content: String
        let clientMessageID: String
        let channelReference: NativeChannelMessageTextReference?
    }
    public func restore() throws -> MessageTextIntent? {
        guard let data = try storage.read(scope.key) else { return nil }
        guard data.count <= 64 * 1024, let row = try? JSONDecoder().decode(StoredRecord.self, from: data),
              (row.version == 1 && row.channelReference == nil || row.version == 2 && row.channelReference != nil),
              row.scope == scope, strictRecord(data, row: row),
              let intent = try? MessageTextIntent(conversationID: scope.conversationID,
                  content: row.content, clientMessageID: row.clientMessageID, channelReference: row.channelReference),
              intent.content.utf8.elementsEqual(row.content.utf8) else { throw NativeChannelTextJournalError.incompatible }
        return intent
    }
    // Do not interpret or erase records with unknown future identity fields. In particular,
    // a lossy Codable projection never authorizes settlement or replacement of an original.
    private func strictRecord(_ data: Data, row: StoredRecord) -> Bool {
        guard let raw = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let scope = raw["scope"] as? [String: Any],
              Set(scope.keys) == ["accountID", "namespace", "baseURL", "conversationID"] else { return false }
        var keys: Set<String> = ["version", "scope", "content", "clientMessageID"]
        if row.version == 2 { keys.insert("channelReference") }
        guard Set(raw.keys) == keys else { return false }
        if let reference = row.channelReference {
            guard let value = raw["channelReference"] as? [String: Any],
                  let binding = value["binding"] as? [String: Any],
                  Set(binding.keys) == ["channelID", "conversationID", "mappingRevision"] else { return false }
            var referenceKeys: Set<String> = ["binding", "memberIDs", "roleIDs", "mentionEveryone"]
            if reference.replyToID != nil { referenceKeys.insert("replyToID") }
            guard Set(value.keys) == referenceKeys else { return false }
        }
        return true
    }
    public func permitsNewOriginalSend() throws -> Bool {
        try !IMExpandedRecoveryJournal(storage: storage, scope: scope).hasPendingSend()
    }
    public func saveBeforeDispatch(_ intent: MessageTextIntent) throws {
        guard intent.conversationID == scope.conversationID, intent.content.utf8.count <= 16 * 1024 else {
            throw APIError.invalidRequest
        }
        if let existing = try restore() {
            guard Self.same(existing, intent) else { throw NativeChannelTextJournalError.pendingIntent }
            return
        }
        guard try permitsNewOriginalSend() else { throw NativeChannelTextJournalError.pendingIntent }
        // Same protected slot and original key: v1 records are read without migration or rewriting.
        let row = StoredRecord(version: intent.channelReference == nil ? 1 : 2, scope: scope, content: intent.content,
                         clientMessageID: intent.clientMessageID, channelReference: intent.channelReference)
        try storage.write(JSONEncoder().encode(row), key: scope.key)
        guard try Self.same(restore(), intent) else { throw NativeChannelTextJournalError.unavailable }
    }
    /// Compare before removal, so a stale completion cannot discard a newer original intent.
    public func settle(_ intent: MessageTextIntent) throws {
        guard let current = try restore() else { return } // another screen already settled this original
        guard Self.same(current, intent) else { throw NativeChannelTextJournalError.pendingIntent }
        try storage.remove(scope.key)
        guard try restore() == nil else { throw NativeChannelTextJournalError.unavailable }
    }
}

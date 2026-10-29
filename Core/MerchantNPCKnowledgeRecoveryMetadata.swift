import Foundation

/// Identity of one accepted knowledge-review request.
/// The four authored strings stay on the original GET. This record does not store them,
/// and it does not use a save-local generation or an npc/save operation id.
public struct MerchantNPCKnowledgeRecoveryMetadata: Codable, Equatable {
    public static let currentVersion = 1
    public let version: Int
    public let requestID: UUID
    public let memberID: Int64
    public let ownerKey: String
    public let merchantRowID: Int

    public init(version: Int = currentVersion, requestID: UUID, memberID: Int64, ownerKey: String, merchantRowID: Int) {
        self.version = version
        self.requestID = requestID
        self.memberID = memberID
        self.ownerKey = ownerKey
        self.merchantRowID = merchantRowID
    }
}

/// Dedicated target on the same defaults the operation journal already uses.
/// The key is not `merchantNPCSave`, so a successful npc/save clear does not remove this row.
/// This type does not send HTTP and does not publish.
@MainActor public final class MerchantNPCKnowledgeRecoveryStore {
    public static let targetKey = "merchant-npc-knowledge-review"
    public let ownerKey: String
    public let merchantRowID: Int
    private let defaults: UserDefaults

    public init?(defaults: UserDefaults, ownerKey: String, merchantRowID: Int) {
        guard !ownerKey.isEmpty, !ownerKey.contains("\n"), merchantRowID > 0 else { return nil }
        self.defaults = defaults
        self.ownerKey = ownerKey
        self.merchantRowID = merchantRowID
    }

    private var storageKey: String {
        let raw = "\(ownerKey.utf8.count):\(ownerKey):\(merchantRowID):\(Self.targetKey)"
        return "questify.operations.knowledge-recovery.v1." + Data(raw.utf8).base64EncodedString()
    }

    /// Write only after the original submit returned this same request id.
    public func saveAccepted(requestID: UUID, memberID: Int64) throws {
        guard memberID > 0 else { throw APIError.invalidRequest }
        let record = MerchantNPCKnowledgeRecoveryMetadata(
            requestID: requestID, memberID: memberID, ownerKey: ownerKey, merchantRowID: merchantRowID)
        let data = try JSONEncoder().encode(record)
        let name = storageKey
        let previous = defaults.data(forKey: name)
        defaults.set(data, forKey: name)
        guard defaults.data(forKey: name) == data else {
            if let previous { defaults.set(previous, forKey: name) } else { defaults.removeObject(forKey: name) }
            throw APIError.malformedResponse
        }
    }

    /// A different owner or merchant stays unread. This does not delete that row.
    public func read() -> MerchantNPCKnowledgeRecoveryMetadata? {
        guard let data = defaults.data(forKey: storageKey),
              let record = try? JSONDecoder().decode(MerchantNPCKnowledgeRecoveryMetadata.self, from: data),
              record.version == MerchantNPCKnowledgeRecoveryMetadata.currentVersion,
              record.ownerKey == ownerKey,
              record.merchantRowID == merchantRowID,
              record.memberID > 0 else { return nil }
        return record
    }
}

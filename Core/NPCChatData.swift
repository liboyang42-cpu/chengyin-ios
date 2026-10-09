import Foundation

public enum NPCChatDataFailure: String, Error, Equatable {
    case unavailable, signedOut, staleSession, malformed, tooLarge, rejected, failed
    public var messageKey: String { "npcData.failure." + rawValue }
}

/// Read-only projection of the authenticated NPC chat-data export. IDs are kept
/// as decimal strings; no merchant/node identity is inferred from a profile ID.
/// There is no encoding, file export, deletion or model-input API in this type.
public struct NPCChatDataRecord: Decodable, Equatable, Identifiable {
    public let id: String
    fileprivate let ownerID: Int64
    public let userMessage: String?
    public let npcReply: String?
    /// Source text or numeric representation, not guessed into a device time zone.
    public let sourceTime: String?
    enum CodingKeys: String, CodingKey {
        case id, userId, userMsg, npcReply, createTime
    }
    public init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        func integer(_ key: CodingKeys, required: Bool = false) throws -> Int64? {
            if !fields.contains(key) {
                if required { throw NPCChatDataFailure.malformed }; return nil
            }
            if try fields.decodeNil(forKey: key) {
                if required { throw NPCChatDataFailure.malformed }; return nil
            }
            if let value = try? fields.decode(Int64.self, forKey: key) { return value }
            if let text = try? fields.decode(String.self, forKey: key), !text.isEmpty,
               text.utf8.allSatisfy({ (48...57).contains($0) }), let value = Int64(text) { return value }
            throw NPCChatDataFailure.malformed
        }
        guard let recordID = try integer(.id, required: true), recordID > 0,
              let owner = try integer(.userId, required: true), owner > 0 else { throw NPCChatDataFailure.malformed }
        id = String(recordID); ownerID = owner
        userMessage = try fields.decodeIfPresent(String.self, forKey: .userMsg)
        npcReply = try fields.decodeIfPresent(String.self, forKey: .npcReply)
        if !fields.contains(.createTime) { sourceTime = nil }
        else if try fields.decodeNil(forKey: .createTime) { sourceTime = nil }
        else if let text = try? fields.decode(String.self, forKey: .createTime) { sourceTime = text }
        else if let number = try? fields.decode(Int64.self, forKey: .createTime) { sourceTime = String(number) }
        else { throw NPCChatDataFailure.malformed }
        guard (userMessage?.utf8.count ?? 0) <= 131_072, (npcReply?.utf8.count ?? 0) <= 131_072,
              (sourceTime?.utf8.count ?? 0) <= 256 else { throw NPCChatDataFailure.tooLarge }
    }
    public func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return query.isEmpty || (userMessage?.localizedStandardContains(query) ?? false) || (npcReply?.localizedStandardContains(query) ?? false)
    }
}

public struct NPCChatData: Equatable {
    public static let path = "api/ai/npc/chat/data/export"
    let ownerAccountID: Int
    public let retentionDays: Int?
    public let retentionPolicy: String?
    public let records: [NPCChatDataRecord]
    public static func decode(_ bytes: Data, expectedAccountID: Int) throws -> NPCChatData {
        guard expectedAccountID > 0 else { throw NPCChatDataFailure.signedOut }
        guard bytes.count <= 8_388_608 else { throw NPCChatDataFailure.tooLarge }
        struct Envelope: Decodable {
            let code: Int
            let data: Payload?
            struct Payload: Decodable {
                let retentionDays: Int?
                let retentionPolicy: String?
                let records: [NPCChatDataRecord]
            }
        }
        do {
            let envelope = try JSONDecoder().decode(Envelope.self, from: bytes)
            guard envelope.code == 200 else { throw NPCChatDataFailure.rejected }
            guard let value = envelope.data else { throw NPCChatDataFailure.malformed }
            guard value.records.count <= 10_000, (value.retentionPolicy?.utf8.count ?? 0) <= 16_384 else { throw NPCChatDataFailure.tooLarge }
            guard value.retentionDays.map({ $0 >= 0 }) ?? true,
                  value.records.allSatisfy({ $0.ownerID == Int64(expectedAccountID) }),
                  Set(value.records.map(\.id)).count == value.records.count else { throw NPCChatDataFailure.malformed }
            return .init(ownerAccountID: expectedAccountID, retentionDays: value.retentionDays, retentionPolicy: value.retentionPolicy, records: value.records)
        } catch let error as NPCChatDataFailure { throw error }
        catch { throw NPCChatDataFailure.malformed }
    }
}

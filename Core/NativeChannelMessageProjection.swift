import Foundation

public enum NativeChannelMessageKind: Int, CaseIterable {
    case unknown = 0, text, image, card, poll, joined, left, renamed, pinned, pollResult
    case voice, video, file, location, chain, redPacket
}

/// Sidecar metadata decoded from the original history/mutation projection, not a second inbox.
public struct NativeChannelMessageSnapshot: Decodable, Equatable {
    public let id: NativeChannelMessageID
    public let conversationID: NativeChannelMessageID
    public let version: Int64
    public let status: Int
    public let kind: NativeChannelMessageKind
    public let senderID: NativeChannelMessageID?
    /// Original wire field only; absent is not evidence of a non-system sender.
    public let senderType: Int?
    public let content: String?
    public let extraJSON: String?
    public let reply: NativeChannelMessageQuote?
    public let editedAt: String?
    public let pinned: Bool?
    public let mentions: [NativeChannelMessageMention]?
    public let mentionEveryone: Bool?
    public let message: MessagingMessage
    enum CodingKeys: String, CodingKey { case id, conversationId, version, status, msgType, senderId, senderType, senderName, senderAvatar, content, extraJson, createTime, replyTo, edited_at, pinned, mentions, mention_everyone }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(NativeChannelMessageID.self, forKey: .id)
        conversationID = try c.decode(NativeChannelMessageID.self, forKey: .conversationId)
        version = try c.decode(Int64.self, forKey: .version)
        status = try c.decode(Int.self, forKey: .status)
        guard version > 0, let legacyID = Int(id.rawValue), let legacyConversation = Int(conversationID.rawValue) else { throw APIError.malformedResponse }
        var legacy: [String: Any] = ["id": legacyID, "conversationId": legacyConversation, "status": status]
        if status == 0 {
            let rawKind = try c.decode(Int.self, forKey: .msgType)
            kind = NativeChannelMessageKind(rawValue: rawKind) ?? .unknown
            legacy["msgType"] = rawKind
            // An unknown kind is an opaque placeholder. None of its payload or
            // action metadata belongs to a schema this client understands. In
            // particular, future mention/flag shapes must not break the whole
            // history page or give an unknown row a sender/action identity.
            guard kind != .unknown else {
                senderType = nil; senderID = nil; content = nil; extraJSON = nil
                reply = nil; editedAt = nil; pinned = nil; mentions = nil; mentionEveryone = nil
                message = try JSONDecoder().decode(MessagingMessage.self,
                    from: JSONSerialization.data(withJSONObject: legacy))
                return
            }
            // sender 0 is the real system producer, never a user identity.
            let rawSender = try c.decodeIfPresent(String.self, forKey: .senderId)
            guard rawSender == nil || rawSender == "0" || rawSender.flatMap(NativeChannelMessageID.init(rawValue:)) != nil else { throw APIError.malformedResponse }
            senderID = rawSender.flatMap(NativeChannelMessageID.init(rawValue:))
            senderType = try c.decodeIfPresent(Int.self, forKey: .senderType)
            content = try c.decodeIfPresent(String.self, forKey: .content)
            extraJSON = try c.decodeIfPresent(String.self, forKey: .extraJson)
            reply = try c.decodeIfPresent(NativeChannelMessageQuote.self, forKey: .replyTo)
            editedAt = try c.decodeIfPresent(String.self, forKey: .edited_at)
            pinned = try c.decodeIfPresent(NativeChannelMessageFlag.self, forKey: .pinned)?.value
            mentions = try c.decodeIfPresent([NativeChannelMessageMention].self, forKey: .mentions)
            mentionEveryone = try c.decodeIfPresent(NativeChannelMessageFlag.self, forKey: .mention_everyone)?.value
            legacy["senderId"] = rawSender.flatMap(Int.init)
            legacy["content"] = content; legacy["extraJson"] = extraJSON
            legacy["senderName"] = try c.decodeIfPresent(String.self, forKey: .senderName)
            legacy["senderAvatar"] = try c.decodeIfPresent(String.self, forKey: .senderAvatar)
            // createTime may be ISO text or the existing original epoch integer.
            if let value = try? c.decode(String.self, forKey: .createTime) { legacy["createTime"] = value }
            else if let value = try? c.decode(Int64.self, forKey: .createTime) { legacy["createTime"] = value }
        } else {
            kind = .unknown; senderType = nil; senderID = nil; content = nil; extraJSON = nil; reply = nil; editedAt = nil; pinned = nil; mentions = nil; mentionEveryone = nil
        }
        message = try JSONDecoder().decode(MessagingMessage.self, from: JSONSerialization.data(withJSONObject: legacy))
    }
}

public struct NativeChannelMessageMention: Decodable, Equatable {
    public let member_id: String
    public let mention_type: String
    enum CodingKeys: CodingKey { case member_id, mention_type }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        member_id = try c.decode(String.self, forKey: .member_id); mention_type = try c.decode(String.self, forKey: .mention_type)
        guard (mention_type == "EVERYONE" && member_id == "0") ||
            (["USER", "ROLE", "REPLY"].contains(mention_type) && NativeChannelMessageID(rawValue: member_id) != nil) else { throw APIError.malformedResponse }
    }
}

private struct NativeChannelMessageFlag: Decodable {
    let value: Bool
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let b = try? c.decode(Bool.self) { value = b }
        else { let n = try c.decode(Int.self); guard n == 0 || n == 1 else { throw APIError.malformedResponse }; value = n == 1 }
    }
}

public struct NativeChannelMessageQuote: Decodable, Equatable {
    public let id: NativeChannelMessageID
    public let state: String
    public let summary: String?
    public let senderId: NativeChannelMessageID?
    enum CodingKeys: CodingKey { case id, state, summary, senderId }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(NativeChannelMessageID.self, forKey: .id); state = try c.decode(String.self, forKey: .state)
        if state == "VISIBLE" { summary = try c.decodeIfPresent(String.self, forKey: .summary); senderId = try c.decodeIfPresent(NativeChannelMessageID.self, forKey: .senderId) }
        else { summary = nil; senderId = nil } // Fixed localized placeholders for BLOCKED/UNAVAILABLE/RECALLED/unknown.
    }
}

public struct NativeChannelMessageMutation: Decodable {
    public let mutation_cursor: String
    public let message_id: NativeChannelMessageID
    public let version: Int64
    public let kind: String
    public let invalidate: Bool?
    public let message: NativeChannelMessageSnapshot?
}

/// Decode alongside the ORIGINAL history read. The host first replaces its visible
/// caches, then passes these same-response fields to coordinator.replacedHistory.
public struct NativeChannelMessageHistorySupplement: Decodable {
    public let list: [NativeChannelMessageSnapshot]
    public let mutation_cursor: String
    public let sync_contract: String
    public let legacy_cache_action: String
}
public struct NativeChannelMessageMutationPage: Decodable {
    public let list: [NativeChannelMessageMutation]
    public let has_more: Bool
    public let next_mutation_cursor: String
    public let sync_contract: String
    public func verify(after: String, binding: NativeChannelMessageBinding) throws {
        guard NativeChannelMessageCursor.valid(after), NativeChannelMessageCursor.valid(next_mutation_cursor),
              sync_contract == "VISIBLE_ORDER_PLUS_MUTATIONS_V1", list.count <= 50,
              let lower = Int64(after), let upper = Int64(next_mutation_cursor), upper >= lower,
              !has_more || (!list.isEmpty && upper > lower) else { throw APIError.malformedResponse }
        var previous = lower
        for change in list {
            guard NativeChannelMessageCursor.valid(change.mutation_cursor), let cursor = Int64(change.mutation_cursor),
                  cursor > previous, cursor <= upper, change.version > 0,
                  ["EDIT", "RECALL", "RESTORE"].contains(change.kind) else { throw APIError.malformedResponse }
            if change.invalidate == true { guard change.message == nil else { throw APIError.malformedResponse } }
            else { guard let row = change.message, row.id == change.message_id, row.version == change.version,
                         row.conversationID == binding.conversationID else { throw APIError.malformedResponse } }
            previous = cursor
            if change.kind == "RECALL", change.invalidate != true { throw APIError.malformedResponse }
        }
        if has_more { guard list.last?.mutation_cursor == next_mutation_cursor else { throw APIError.malformedResponse } }
    }
}

/// ID/version vetoes only. The host keeps its original history and visible_at/id order.
public struct NativeChannelMessageProjection {
    private var expectedBinding: NativeChannelMessageBinding?
    public private(set) var mutationCursor: String?
    public private(set) var withheld: Set<NativeChannelMessageID> = []
    public private(set) var versions: [NativeChannelMessageID: Int64] = [:]
    public init() {}
    /// Must be called only after the host has replaced all visible caches with this same history response.
    public mutating func replacedHistory(mutationCursor: String, syncContract: String, legacyCacheAction: String,
                                         snapshots: [NativeChannelMessageSnapshot], binding: NativeChannelMessageBinding) throws {
        guard syncContract == "VISIBLE_ORDER_PLUS_MUTATIONS_V1", legacyCacheAction == "RELOAD_ON_RESUME",
              NativeChannelMessageCursor.valid(mutationCursor), snapshots.allSatisfy({ $0.conversationID == binding.conversationID }),
              Set(snapshots.map(\.id)).count == snapshots.count else { throw APIError.malformedResponse }
        // A history request may have started before a newer mutation read.
        // Reject its old snapshot atomically, keeping the version/withheld fence
        // that hides recalled or edited content until a current read arrives.
        if expectedBinding == binding {
            guard let incomingCursor = Int64(mutationCursor),
                  let currentCursor = self.mutationCursor.flatMap(Int64.init),
                  incomingCursor >= currentCursor,
                  snapshots.allSatisfy({ $0.version >= versions[$0.id, default: 0] }) else {
                throw APIError.malformedResponse
            }
        }
        expectedBinding = binding; self.mutationCursor = mutationCursor; versions = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.id, $0.version) })
        withheld = Set(snapshots.filter { $0.status != 0 }.map(\.id))
    }
    public mutating func consume(_ page: NativeChannelMessageMutationPage, binding: NativeChannelMessageBinding) throws {
        guard let mutationCursor, expectedBinding == binding else { throw APIError.notConfigured }
        try page.verify(after: mutationCursor, binding: binding)
        for change in page.list where change.version >= versions[change.message_id, default: 0] {
            versions[change.message_id] = change.version
            // Keep payload hidden until the original host has re-read its current projection.
            withheld.insert(change.message_id)
        }
        self.mutationCursor = page.next_mutation_cursor
    }
    public mutating func confirmCurrent(_ row: NativeChannelMessageSnapshot) {
        guard row.conversationID == expectedBinding?.conversationID, row.version >= versions[row.id, default: 0] else { return }
        versions[row.id] = row.version
        if row.status == 0 { withheld.remove(row.id) } else { withheld.insert(row.id) }
    }
    public mutating func retire() { expectedBinding = nil; mutationCursor = nil; withheld.removeAll(); versions.removeAll() }
}

public struct NativeChannelMessageRevision: Decodable, Identifiable {
    public let message_id: NativeChannelMessageID
    public let revision_no: Int64
    public let check_status: Int
    public let content: String?
    public var id: Int64 { revision_no }
    enum CodingKeys: CodingKey { case message_id, revision_no, check_status, content }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        message_id = try c.decode(NativeChannelMessageID.self, forKey: .message_id)
        revision_no = try c.decode(Int64.self, forKey: .revision_no); check_status = try c.decode(Int.self, forKey: .check_status)
        content = check_status == 1 ? try c.decodeIfPresent(String.self, forKey: .content) : nil
    }
}
public struct NativeChannelMessageRevisionPage: Decodable {
    public let list: [NativeChannelMessageRevision]
    public let has_more: Bool
    public let next_cursor: String?
    func verify(messageID: NativeChannelMessageID, before: Int64?) throws {
        guard list.count <= 20, Set(list.map(\.id)).count == list.count,
              list.allSatisfy({ $0.message_id == messageID && $0.revision_no > 0 && (before == nil || $0.revision_no < before!) }),
              zip(list, list.dropFirst()).allSatisfy({ pair in pair.0.revision_no > pair.1.revision_no }),
              has_more ? (!list.isEmpty && next_cursor == list.last.map({ String($0.revision_no) })) : next_cursor == nil else { throw APIError.malformedResponse }
    }
}

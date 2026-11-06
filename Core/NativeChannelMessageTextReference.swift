import Foundation

/// Immutable ORIGINAL text-intent metadata. Codable is the protected LOCAL journal
/// schema, not a claim that these field names are accepted by the public multipart API.
/// Actual channel binding is required separately from a legacy conversation row.
public struct NativeChannelMessageTextReference: Codable, Equatable, Sendable {
    public let binding: NativeChannelMessageBinding
    public let replyToID: NativeChannelMessageID?
    public let memberIDs: [NativeChannelMessageID]
    public let roleIDs: [NativeChannelMessageID]
    public let mentionEveryone: Bool
    public init(binding: NativeChannelMessageBinding, replyToID: NativeChannelMessageID? = nil,
                memberIDs: [NativeChannelMessageID] = [], roleIDs: [NativeChannelMessageID] = [], mentionEveryone: Bool = false) throws {
        self.binding = binding; self.replyToID = replyToID; self.memberIDs = memberIDs
        self.roleIDs = roleIDs; self.mentionEveryone = mentionEveryone
        try validate()
    }
    private enum CodingKeys: CodingKey { case binding, replyToID, memberIDs, roleIDs, mentionEveryone }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        binding = try c.decode(NativeChannelMessageBinding.self, forKey: .binding)
        replyToID = try c.decodeIfPresent(NativeChannelMessageID.self, forKey: .replyToID)
        memberIDs = try c.decode([NativeChannelMessageID].self, forKey: .memberIDs)
        roleIDs = try c.decode([NativeChannelMessageID].self, forKey: .roleIDs)
        mentionEveryone = try c.decode(Bool.self, forKey: .mentionEveryone)
        try validate()
    }
    public func validate() throws {
        guard !binding.mappingRevision.isEmpty, binding.mappingRevision.utf8.count <= 4096,
              memberIDs.count <= 20, roleIDs.count <= 20,
              Set(memberIDs).count == memberIDs.count, Set(roleIDs).count == roleIDs.count,
              replyToID != nil || !memberIDs.isEmpty || !roleIDs.isEmpty || mentionEveryone else { throw APIError.invalidRequest }
    }
    public func matchesConversation(_ id: Int) -> Bool { id > 0 && binding.conversationID.rawValue == String(id) }
    public static func sameIdentityBytes(_ lhs: Self?, _ rhs: Self?) -> Bool {
        guard let lhs, let rhs else { return lhs == nil && rhs == nil }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        guard let a = try? encoder.encode(lhs), let b = try? encoder.encode(rhs) else { return false }
        return a == b // Include original order, every ID, boolean and binding byte.
    }
}

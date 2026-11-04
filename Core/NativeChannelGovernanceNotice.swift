import Foundation
import CoreFoundation

/// Navigation hint only. The destination re-reads this actor's original moderation row.
public struct NativeChannelGovernanceNotice: Codable, Equatable {
    public let messageID: Int
    public let conversationID: Int
    public let recipientID: Int
    public let actionID: String
    public let guildKind: Int
    public let guildID: String
    /// Only a locator from the original lifecycle payload; never state or authority.
    public let appealIDHint: String?
    public init(messageID: Int, conversationID: Int, recipientID: Int, actionID: String,
                guildKind: Int, guildID: String, appealIDHint: String? = nil) {
        self.messageID = messageID; self.conversationID = conversationID; self.recipientID = recipientID
        self.actionID = actionID; self.guildKind = guildKind; self.guildID = guildID
        self.appealIDHint = Self.positive(appealIDHint)
    }
    public static func parse(message: MessagingMessage, conversation: MessagingConversation?, identity: MessagingReadIdentity?) -> Self? {
        guard let identity, conversation?.kind == .system, conversation?.id == message.conversationID,
              message.senderID == 0, message.type == 3, message.isPayloadVisible,
              let text = message.extraJSON, let data = text.data(using: .utf8), data.count <= 32 * 1024,
              let row = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              row["cardType"] as? String == "channel_governance",
              positive(row["recipientMemberId"]) == String(identity.accountID),
              let action = positive(row["actionId"]), let guild = positive(row["guildId"]),
              let kindText = positive(row["guildKind"]), let kind = Int(kindText), [1, 2, 3].contains(kind) else { return nil }
        let lifecycle = row["appealState"] as? [String: Any]
        let hint = positive(lifecycle?["action_id"]) == action && positive(lifecycle?["appellant_member_id"]) == String(identity.accountID)
            ? positive(lifecycle?["appeal_id"]) : nil
        return Self(messageID: message.id, conversationID: message.conversationID, recipientID: identity.accountID,
                    actionID: action, guildKind: kind, guildID: guild, appealIDHint: hint)
    }
    /// Canonical signed integer, rejecting booleans, fractions and padded strings.
    /// Kept local so restoring this journey does not import an unrelated admission domain.
    static func integer(_ value: Any?) -> Int64? {
        if let text = value as? String, let number = Int64(text), String(number) == text { return number }
        if let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
           let number = Int64(value.stringValue), String(number) == value.stringValue { return number }
        return nil
    }
    static func positive(_ value: Any?) -> String? {
        if let text = value as? String, let number = Int64(text), number > 0, String(number) == text { return text }
        if let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
           let number = Int64(value.stringValue), number > 0, String(number) == value.stringValue { return value.stringValue }
        return nil
    }
}

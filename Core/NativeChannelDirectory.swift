import Foundation

/// A view of existing IM-backed spaces, not the future im_channel entity.
/// Only server-authorized, real group rows enter this projection. Filtering is
/// performed on the complete nonpaged conversations response before display limits.
public struct NativeChannelSpace: Identifiable, Equatable {
    public let id: String
    public let kind: Kind
    public let spaceID: Int
    public let name: String
    public let channels: [MessagingConversation]
    public enum Kind: String { case club, team, hangout }

    public static func project(_ conversations: [MessagingConversation]) -> [Self] {
        var order: [String] = []
        var grouped: [String: (Kind, Int, [MessagingConversation])] = [:]
        for row in conversations where row.kind == .group {
            guard let key = row.counterparty?.bizKey,
                  let separator = key.firstIndex(of: "_"),
                  let kind = Kind(rawValue: String(key[..<separator])) else { continue }
            let rawID = String(key[key.index(after: separator)...])
            guard let id = Int(rawID), id > 0, String(id) == rawID else { continue }
            if grouped[key] == nil { order.append(key); grouped[key] = (kind, id, []) }
            grouped[key]?.2.append(row)
        }
        return order.compactMap { key in
            guard let (kind, id, rows) = grouped[key], let first = rows.first else { return nil }
            let name = first.counterparty?.nickname?.trimmingCharacters(in: .whitespacesAndNewlines)
            return Self(id: key, kind: kind, spaceID: id, name: name?.isEmpty == false ? name! : key, channels: rows)
        }
    }
}

public struct NativeChannelReadReceipt: Decodable, Equatable {
    public let conversationId: Int
    public let readTo: Int
    public let lastReadMessageId: Int
    public let unread: Int
}

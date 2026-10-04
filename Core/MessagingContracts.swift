import Foundation
import CoreFoundation

/// Source: retained client lib/data/models/im.dart. Unknown kinds stay unknown.
public enum MessagingConversationKind: Equatable {
    case direct, system, merchant, group, unknown
    public init(rawValue: Int?) {
        switch rawValue {
        case 1: self = .direct
        case 2: self = .system
        case 3: self = .merchant
        case 4: self = .group
        default: self = .unknown
        }
    }
}

public struct MessagingCounterparty: Decodable, Equatable {
    public let id: Int?
    public let nickname: String?
    public let avatar: String?
    public let bizKey: String?
}

public struct MessagingConversation: Decodable, Equatable, Identifiable {
    public let id: Int
    public let type: Int?
    public let counterparty: MessagingCounterparty?
    public let lastMessageType: Int?
    public let lastMessageText: String?
    /// Kept verbatim: the source does not declare the server's timezone.
    public let lastMessageAt: String?
    public let unread: Int?
    /// Only documented 0/1 or "0"/"1" values are accepted; absent/other stays unknown.
    public let muted: Bool?
    public var kind: MessagingConversationKind { .init(rawValue: type) }

    private enum CodingKeys: String, CodingKey {
        case conversationId, type, counterparty, lastMsgType, lastMsgText, lastMsgAt, unread, muted
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .conversationId)
        guard id > 0 else { throw APIError.malformedResponse }
        type = try c.decodeIfPresent(Int.self, forKey: .type)
        counterparty = try c.decodeIfPresent(MessagingCounterparty.self, forKey: .counterparty)
        // The conversation response has no last-message status provenance. It may
        // retain recalled text, so never keep its unverified preview payload.
        lastMessageType = nil
        lastMessageText = nil
        lastMessageAt = try c.decodeIfPresent(MessagingWireText.self, forKey: .lastMsgAt)?.value
        unread = try c.decodeIfPresent(Int.self, forKey: .unread)
        guard unread.map({ $0 >= 0 }) ?? true else { throw APIError.malformedResponse }
        if let value = try? c.decode(Int.self, forKey: .muted), value == 0 || value == 1 {
            muted = value == 1
        } else if let value = try? c.decode(String.self, forKey: .muted), value == "0" || value == "1" {
            muted = value == "1"
        } else { muted = nil }
    }
}

/// Exact server statuses; absent/malformed/future values never imply visibility.
public enum MessagingMessageStatus: Equatable {
    case normal, recalled, blocked, unknown
    public init(wireValue: Int?) {
        switch wireValue {
        case 0: self = .normal
        case 1: self = .recalled
        case 2: self = .blocked
        default: self = .unknown
        }
    }
}

public struct MessagingMessage: Decodable, Equatable, Identifiable {
    public let status: MessagingMessageStatus
    public var isPayloadVisible: Bool { status == .normal }
    public let id: Int
    public let conversationID: Int
    public let senderID: Int?
    public let type: Int?
    public let content: String?
    public let extraJSON: String?
    public let createdAt: String?
    public let senderName: String?
    public let senderAvatar: String?
    public var card: MessagingCard? { isPayloadVisible && type == 3 ? MessagingCard.parse(extraJSON, fallbackTitle: content) : nil }

    private enum CodingKeys: String, CodingKey {
        case id, conversationId, senderId, msgType, content, extraJson, createTime, senderName, senderAvatar, status
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        conversationID = try c.decode(Int.self, forKey: .conversationId)
        guard id > 0, conversationID > 0 else { throw APIError.malformedResponse }
        status = .init(wireValue: try? c.decode(Int.self, forKey: .status))
        createdAt = try c.decodeIfPresent(MessagingWireText.self, forKey: .createTime)?.value
        // Discard withheld payload at the trust boundary, not merely in Text views.
        // This also prevents card parsing, media URLs, poll references, search and
        // accessibility values from retaining content hidden by the server status.
        guard status == .normal else {
            senderID = nil; type = nil; content = nil; extraJSON = nil
            senderName = nil; senderAvatar = nil
            return
        }
        senderID = try c.decodeIfPresent(Int.self, forKey: .senderId)
        guard senderID.map({ $0 >= 0 }) ?? true else { throw APIError.malformedResponse }
        type = try c.decodeIfPresent(Int.self, forKey: .msgType)
        content = try c.decodeIfPresent(String.self, forKey: .content)
        extraJSON = try c.decodeIfPresent(String.self, forKey: .extraJson)
        senderName = try c.decodeIfPresent(String.self, forKey: .senderName)
        senderAvatar = try c.decodeIfPresent(String.self, forKey: .senderAvatar)
    }
}

/// Server list order is already oldest → newest; a cursor is opaque, never an ID calculation.
public struct MessagingPage: Decodable, Equatable {
    public let messages: [MessagingMessage]
    public let nextCursor: Int?
    public let hasMore: Bool
    private enum CodingKeys: String, CodingKey { case list, nextCursor, hasMore }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        messages = try c.decode([MessagingMessage].self, forKey: .list)
        nextCursor = try c.decodeIfPresent(Int.self, forKey: .nextCursor)
        hasMore = try c.decode(Bool.self, forKey: .hasMore)
        guard nextCursor.map({ $0 >= 0 }) ?? true, !hasMore || (nextCursor ?? 0) > 0 else {
            throw APIError.malformedResponse
        }
    }
}

/// Only a display projection. Never dispatch card actions, links, business IDs or buttons.
public struct MessagingCard: Equatable {
    public enum Kind: Equatable { case location, route, signup, generic }
    public let kind: Kind
    public let title: String?
    public let subtitle: String?
    public let meta: String?
    public let topicID: Int?
    public let address: String?
    public let latitude: Double?
    public let longitude: Double?
    public let buttonLabels: [String]
    public let result: MessagingCardResult?

    public static func parse(_ raw: String?, fallbackTitle: String?) -> Self? {
        guard let raw, let data = raw.data(using: .utf8),
              let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        func text(_ value: Any?) -> String? {
            guard let value else { return nil }
            let string: String
            if let s = value as? String { string = s }
            else if let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { string = n.stringValue }
            else { return nil }
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        func number(_ value: Any?) -> Double? { text(value).flatMap(Double.init) }
        let type = text(j["cardType"]) ?? "generic"
        if type == "location" {
            let lat = number(j["lat"]), lng = number(j["lng"])
            let valid = lat.map { $0.isFinite && (-90...90).contains($0) } == true
                && lng.map { $0.isFinite && (-180...180).contains($0) } == true
            guard text(j["name"]) != nil || valid else { return nil }
            return Self(kind: .location, title: text(j["name"]), subtitle: nil, meta: nil,
                        topicID: nil, address: text(j["address"]), latitude: valid ? lat : nil,
                        longitude: valid ? lng : nil, buttonLabels: [], result: nil)
        }
        if type == "route" || type == "signup" {
            let id = text(j["topicId"]).flatMap(Int.init).flatMap { $0 > 0 ? $0 : nil }
            // Some source cards have only an action. Preserve a static placeholder,
            // without interpreting that action as a native route or a network request.
            guard id != nil || text(j["action"]) != nil else { return nil }
            return Self(kind: type == "route" ? .route : .signup, title: nil, subtitle: nil,
                        meta: nil, topicID: id, address: nil, latitude: nil, longitude: nil,
                        buttonLabels: [], result: nil)
        }
        let labels = (j["buttons"] as? [[String: Any]] ?? []).compactMap { text($0["text"]) }
        let result = (j["result"] as? [String: Any]).flatMap { row -> MessagingCardResult? in
            let result = MessagingCardResult(taskID: text(row["taskId"]), businessID: text(row["bizId"]),
                outcome: text(row["outcome"]), reason: text(row["reason"]), followUp: text(row["followUp"]))
            return result.isEmpty ? nil : result
        }
        let title = text(j["title"]) ?? text(fallbackTitle)
        let subtitle = text(j["sub"]), meta = text(j["meta"])
        guard title != nil || subtitle != nil || meta != nil || !labels.isEmpty
                || result != nil || text(j["action"]) != nil else { return nil }
        return Self(kind: .generic, title: title, subtitle: subtitle, meta: meta, topicID: nil,
                    address: nil, latitude: nil, longitude: nil, buttonLabels: labels, result: result)
    }
}

public struct MessagingCardResult: Equatable {
    public let taskID: String?
    public let businessID: String?
    public let outcome: String?
    public let reason: String?
    public let followUp: String?
    public var isEmpty: Bool { [taskID, businessID, outcome, reason, followUp].allSatisfy { $0 == nil } }
}

private struct MessagingWireText: Decodable {
    let value: String
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let text = try? c.decode(String.self) { value = text }
        else if let number = try? c.decode(Int.self) { value = String(number) }
        else { throw APIError.malformedResponse }
    }
}

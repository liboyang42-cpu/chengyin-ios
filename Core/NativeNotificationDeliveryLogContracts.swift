import Foundation

/// Original N-10 query only. No actor/device identity, write fields, URLs or retry instruction.
public struct NativeNotificationDeliveryLogQuery: Equatable {
    public let limit: Int
    public let event: String?
    public let cursor: String?
    public init(limit: Int = 20, event: String? = nil, cursor: String? = nil) throws {
        guard (1...50).contains(limit), event.map(Self.validEvent) ?? true,
              cursor.map(Self.validCursor) ?? true else { throw NativeChannelNotificationError.invalidInput }
        self.limit = limit; self.event = event; self.cursor = cursor
    }
    public var queryItems: [URLQueryItem] {
        var result = [URLQueryItem(name: "limit", value: String(limit))]
        if let event { result.append(URLQueryItem(name: "event", value: event)) }
        if let cursor { result.append(URLQueryItem(name: "cursor", value: cursor)) }
        return result
    }
    public init(queryItems: [URLQueryItem]) throws {
        guard queryItems.count <= 3, Set(queryItems.map(\.name)).count == queryItems.count,
              let first = queryItems.first, first.name == "limit", let text = first.value,
              let limit = Int(text), String(limit) == text else { throw NativeChannelNotificationError.invalidInput }
        try self.init(limit: limit, event: queryItems.first(where: { $0.name == "event" })?.value,
                      cursor: queryItems.first(where: { $0.name == "cursor" })?.value)
        guard self.queryItems == queryItems else { throw NativeChannelNotificationError.invalidInput }
    }
    public static func validEvent(_ text: String) -> Bool { text.range(of: "^[A-Z][A-Z0-9_]{0,39}$", options: .regularExpression) != nil }
    public static func validCursor(_ text: String) -> Bool { !text.isEmpty && text.utf8.count <= 1024 && text.utf8.allSatisfy { (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 } }
}

public struct NativeNotificationDeliveryLogPage: Decodable, Equatable {
    public struct Sources: Decodable, Equatable { public let wx: Bool; public let apns: Bool; public let inapp: Bool }
    public struct Row: Decodable, Equatable, Identifiable {
        public let id: String
        public let event: String?
        public let channel: String
        public let ok: Int?
        public let reason: String?
        public let bizKey: String?
        public let createTime: String
        public let providerState: String?
        public let resultSource: String
        public let sourceConflict: Bool
        enum CodingKeys: String, CodingKey { case id, event, channel, ok, reason, bizKey = "biz_key", createTime = "create_time", providerState = "provider_state", resultSource = "result_source", sourceConflict = "source_conflict" }
        public func validate() throws {
            guard event.map(NativeNotificationDeliveryLogQuery.validEvent) ?? true,
                  reason.map({ $0.utf8.count <= 200 }) ?? true,
                  createTime.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}\\.[0-9]{6}$", options: .regularExpression) != nil else { throw NativeChannelNotificationError.malformedResponse }
            if channel == "wx" {
                let key = String(id.dropFirst(3))
                guard id.hasPrefix("wx:"), let number = Int64(key), number > 0, String(number) == key,
                      event != nil, resultSource == "signed-wx-sent-event", providerState == nil,
                      (sourceConflict ? ok == nil : (ok == 0 || ok == 1)),
                      bizKey.map({ $0.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil }) ?? true else { throw NativeChannelNotificationError.malformedResponse }
            } else if channel == "apns" {
                let key = String(id.dropFirst(5))
                guard id.hasPrefix("apns:"), UUID(uuidString: key)?.uuidString.lowercased() == key,
                      bizKey == key, !sourceConflict, resultSource == "original-apns-attempt",
                      event == nil || event == "MESSAGE_MENTION", let providerState else { throw NativeChannelNotificationError.malformedResponse }
                switch providerState {
                case "PROVIDER_ACCEPTED": guard ok == 1 else { throw NativeChannelNotificationError.malformedResponse }
                case "PROVIDER_REJECTED", "SUPPRESSED", "NOT_ATTEMPTED": guard ok == 0 else { throw NativeChannelNotificationError.malformedResponse }
                case "UNKNOWN": guard ok == nil else { throw NativeChannelNotificationError.malformedResponse }
                default: throw NativeChannelNotificationError.malformedResponse
                }
            } else { throw NativeChannelNotificationError.malformedResponse }
        }
    }
    public let source: String
    public let memberID: String
    public let list: [Row]
    public let nextCursor: String?
    public let hasMore: Bool
    public let sources: Sources
    public let deliveryProven: Bool
    enum CodingKeys: String, CodingKey { case source, memberID = "member_id", list, nextCursor = "next_cursor", hasMore = "has_more", sources, deliveryProven = "delivery_proven" }
    public func validate(account: String, query: NativeNotificationDeliveryLogQuery) throws {
        guard source == "original-notification-results-v1", memberID == account, !deliveryProven,
              sources.wx || sources.apns, !sources.inapp, list.count <= query.limit,
              Set(list.map(\.id)).count == list.count,
              hasMore == (nextCursor != nil), nextCursor.map(NativeNotificationDeliveryLogQuery.validCursor) ?? true,
              nextCursor == nil || nextCursor != query.cursor,
              !hasMore || !list.isEmpty else { throw NativeChannelNotificationError.malformedResponse }
        for row in list {
            try row.validate()
            guard (row.channel == "wx" ? sources.wx : sources.apns),
                  query.event.map({ row.event == $0 }) ?? true else { throw NativeChannelNotificationError.malformedResponse }
        }
    }
}

import Foundation

/// Exact e74 wire. No channel, membership, event catalogue or permission source is defined here.
public struct NativeWebhookID: RawRepresentable, Codable, Hashable, Sendable, Identifiable {
    public let rawValue: String
    public var id: String { rawValue }
    public var requestNumber: Int64 { Int64(rawValue)! }
    public init?(rawValue: String) {
        guard let number = Int64(rawValue), number > 0, String(number) == rawValue else { return nil }
        self.rawValue = rawValue
    }
    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        guard let parsed = Self(rawValue: value) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid decimal response ID"))
        }
        self = parsed
    }
    public func encode(to encoder: Encoder) throws { var value = encoder.singleValueContainer(); try value.encode(rawValue) }
}

public struct NativeWebhookRequestID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String
    public init?(rawValue: String) {
        guard !rawValue.isEmpty, rawValue.utf8.count <= 64,
              rawValue.utf8.allSatisfy({ (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45 || $0 == 95 }) else { return nil }
        self.rawValue = rawValue
    }
    public static func make() -> Self { Self(rawValue: UUID().uuidString.lowercased())! }
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let value = Self(rawValue: raw) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid request ID"))
        }
        self = value
    }
    public func encode(to encoder: Encoder) throws { var value = encoder.singleValueContainer(); try value.encode(rawValue) }
}

public enum NativeWebhookFamily: String, Codable, CaseIterable, Sendable { case subscription, endpoint }
public enum NativeWebhookResourceStatus: Int, Codable, Sendable { case paused = 0, active = 1 }
public enum NativeWebhookDeliveryState: String, Codable, CaseIterable, Sendable {
    case pending = "PENDING", inflight = "INFLIGHT", sent = "SENT", failed = "FAILED"
    case dead = "DEAD", unknown = "UNKNOWN", cancelled = "CANCELLED"
}
public enum NativeWebhookInboundState: String, Codable, CaseIterable, Sendable {
    case received = "RECEIVED", pendingReview = "PENDING_REVIEW", accepted = "ACCEPTED", rejected = "REJECTED"
    case blocked = "BLOCKED", rateLimited = "RATE_LIMITED", unknown = "UNKNOWN"
}

public struct NativeWebhookServerTime: Codable, Hashable, Sendable {
    public let rawValue: String
    public let date: Date
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        guard let zone = TimeZone(identifier: "Asia/Shanghai") else { throw NativeWebhookClientError.invalidWire }
        formatter.timeZone = zone
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        formatter.isLenient = false
        guard raw.utf8.count == 23, let date = formatter.date(from: raw), formatter.string(from: date) == raw else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid Shanghai server timestamp"))
        }
        self.rawValue = raw; self.date = date
    }
    public func encode(to encoder: Encoder) throws { var value = encoder.singleValueContainer(); try value.encode(rawValue) }
}

public enum NativeWebhookJSON: Codable, Equatable, Sendable {
    case object([String: NativeWebhookJSON]), array([NativeWebhookJSON]), string(String), number(Decimal), bool(Bool), null
    public init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let flag = try? value.decode(Bool.self) { self = .bool(flag) }
        else if let text = try? value.decode(String.self) { self = .string(text) }
        else if let number = try? value.decode(Decimal.self) { self = .number(number) }
        else if let list = try? value.decode([Self].self) { self = .array(list) }
        else { self = .object(try value.decode([String: Self].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var value = encoder.singleValueContainer()
        switch self {
        case .object(let object): try value.encode(object)
        case .array(let array): try value.encode(array)
        case .string(let string): try value.encode(string)
        case .number(let number): try value.encode(number)
        case .bool(let bool): try value.encode(bool)
        case .null: try value.encodeNil()
        }
    }
}

public struct NativeWebhookPage<Item: Decodable & Sendable>: Decodable, Sendable {
    public let list: [Item]
    public let hasMore: Bool
    public let nextCursor: String?
    private enum CodingKeys: String, CodingKey { case list, hasMore = "has_more", nextCursor = "next_cursor" }
}

/// Ordinary GET data has no fields for secret, token or complete endpoint URL.
public struct NativeWebhookResource: Decodable, Sendable, Identifiable {
    public let id: NativeWebhookID
    public let channelID: NativeWebhookID
    public let ownerType: String
    public let ownerID: NativeWebhookID
    public let name: String
    public let status: NativeWebhookResourceStatus
    public let deleted: Bool
    public let revision: Int
    public let keyVersion: Int
    public let createdAt: NativeWebhookServerTime?
    public let updatedAt: NativeWebhookServerTime?
    public let urlHost: String?
    public let events: [String]?
    public let eventCount: Int?
    public let failCount: Int64?
    public let lastError: String?
    public let lastDeliveryAt: NativeWebhookServerTime?
    public let avatarURL: String?
    public let tokenPrefix: String?
    public let rateLimitPerMinute: Int?
    public let allowedIPs: [String]?
    public let lastCalledAt: NativeWebhookServerTime?
    private enum CodingKeys: String, CodingKey {
        case id, name, status, deleted, revision, events
        case channelID = "channel_id", ownerType = "owner_type", ownerID = "owner_id", keyVersion = "key_version"
        case createdAt = "created_at", updatedAt = "updated_at", urlHost = "url_host", eventCount = "event_count"
        case failCount = "fail_count", lastError = "last_error", lastDeliveryAt = "last_delivery_at"
        case avatarURL = "avatar_url", tokenPrefix = "token_prefix", rateLimitPerMinute = "rate_limit_per_min"
        case allowedIPs = "allowed_ips", lastCalledAt = "last_called_at"
    }
}

public struct NativeWebhookDelivery: Decodable, Sendable, Identifiable {
    public let id: NativeWebhookID
    public let deliveryID: NativeWebhookID
    public let eventID: String
    public let eventType: String
    public let state: NativeWebhookDeliveryState
    public let attempt: Int
    public let reason: String?
    public let responseSnippet: String?
    public let httpStatus: Int?
    public let latencyMilliseconds: Int64?
    public let nextRetryAt: NativeWebhookServerTime?
    public let createdAt: NativeWebhookServerTime?
    public let payload: NativeWebhookJSON?
    public var offersExplicitRetry: Bool { (state == .failed || state == .unknown) && attempt < 5 }
    private enum CodingKeys: String, CodingKey {
        case id, state, attempt, reason
        case payload = "payload_json"
        case deliveryID = "delivery_id", eventID = "event_id", eventType = "event_type", responseSnippet = "response_snippet"
        case httpStatus = "http_status", latencyMilliseconds = "latency_ms", nextRetryAt = "next_retry_at", createdAt = "created_at"
    }
}

public struct NativeWebhookInboundLog: Decodable, Sendable, Identifiable {
    public let id: NativeWebhookID
    public let result: NativeWebhookInboundState
    public let state: NativeWebhookInboundState
    public let reason: String?
    public let messageID: NativeWebhookID?
    public let createdAt: NativeWebhookServerTime?
    public let createTime: NativeWebhookServerTime?
    public let requestHash: String?
    public let nonce: String?
    public let endpointID: NativeWebhookID?
    public let senderType: Int?
    public let webhookID: NativeWebhookID?
    public let originalMessageStored: Bool?
    private enum CodingKeys: String, CodingKey {
        case id, result, state, reason, nonce
        case messageID = "message_id", createdAt = "created_at", createTime = "create_time", requestHash = "request_hash"
        case endpointID = "endpoint_id", senderType = "sender_type", webhookID = "webhook_id"
        case originalMessageStored = "original_message_stored"
    }
}

/// Long request IDs remain Int64 JSON numbers; response decimal strings are not reused as JSON strings.
public struct NativeWebhookChange: Codable, Equatable, Sendable {
    public var requestID: NativeWebhookRequestID
    public var ownerType: String?
    public var ownerID: Int64?
    public var channelID: Int64?
    public var name: String
    public var url: String?
    public var avatarURL: String?
    public var events: [String]?
    public var allowedIPs: [String]?
    public var rateLimitPerMinute: Int?
    public var status: NativeWebhookResourceStatus?
    public var revision: Int?
    public init(requestID: NativeWebhookRequestID, ownerType: String?, ownerID: Int64?, channelID: Int64?, name: String,
                url: String? = nil, avatarURL: String? = nil, events: [String]? = nil, allowedIPs: [String]? = nil,
                rateLimitPerMinute: Int? = nil, status: NativeWebhookResourceStatus? = nil, revision: Int? = nil) {
        self.requestID = requestID; self.ownerType = ownerType; self.ownerID = ownerID; self.channelID = channelID; self.name = name
        self.url = url; self.avatarURL = avatarURL; self.events = events; self.allowedIPs = allowedIPs
        self.rateLimitPerMinute = rateLimitPerMinute; self.status = status; self.revision = revision
    }
    private enum CodingKeys: String, CodingKey {
        case name, url, events, status, revision
        case requestID = "request_id", ownerType = "owner_type", ownerID = "owner_id", channelID = "channel_id"
        case avatarURL = "avatar_url", allowedIPs = "allowed_ips", rateLimitPerMinute = "rate_limit_per_min"
    }
}

public struct NativeWebhookAction: Codable, Equatable, Sendable {
    public let requestID: NativeWebhookRequestID
    public let revision: Int?
    public let eventType: String?
    public init(requestID: NativeWebhookRequestID, revision: Int?, eventType: String? = nil) {
        self.requestID = requestID; self.revision = revision; self.eventType = eventType
    }
    private enum CodingKeys: String, CodingKey { case requestID = "request_id", revision, eventType = "event_type" }
}

public enum NativeWebhookClientError: Error, Equatable, Sendable {
    case sourceUnavailable(String), scopeChanged, invalidWire, invalidInput(String), originalInputRequired
    case denied(code: String, traceID: String?), conflict(code: String, traceID: String?)
    case rejected(status: Int, code: String, traceID: String?), resultUnknown(traceID: String?), cancelled
}

/// Intentionally not Codable or printable. Never put this object into a persistent journal or normal GET cache.
public struct NativeWebhookOneTimeCredential: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String { "NativeWebhookOneTimeCredential(<redacted>)" }
    public var debugDescription: String { description }
    public var customMirror: Mirror { Mirror(self, children: ["credential": "<redacted>"]) }
    public let requestID: NativeWebhookRequestID
    public let secret: String
    public let endpointURL: String?
    public let oldTokenInvalidAfter: NativeWebhookServerTime?
}

public struct NativeWebhookResourceReceipt: Sendable {
    public let resource: NativeWebhookResource
    public let replayed: Bool
    public let credential: NativeWebhookOneTimeCredential?
    public let credentialWasNotRecovered: Bool
}

public enum NativeWebhookMutationReceipt: Sendable {
    case resource(NativeWebhookResourceReceipt), delivery(NativeWebhookDelivery)
}

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Original r463 source-only successor. These are read projections, never request receipts or permissions.
public enum SupportTicketReadFailure: Error, Equatable { case disabled, stale, denied, malformed, unavailable, oversized }
public enum SupportTicketReadCapability: Hashable { case history, detail, timeline }
public struct SupportTicketReadReference: Decodable, Equatable {
    public let source, domain_type, resource_id, owner_type, owner_member_id: String
    func validate(owner: Int, role: String) throws {
        guard owner_type == "MEMBER", owner_member_id == String(owner),
              let id = Int64(resource_id), id > 0, resource_id == String(id) else { throw SupportTicketReadFailure.malformed }
        switch domain_type {
        case "REGISTRATION": guard source == "cms_registration" else { throw SupportTicketReadFailure.malformed }
        case "MERCHANT": guard source == "mms_merchant", role == "MERCHANT" else { throw SupportTicketReadFailure.malformed }
        case "USER": guard source == "ums_member", role == "CLUB_OWNER", resource_id == String(owner) else { throw SupportTicketReadFailure.malformed }
        default: throw SupportTicketReadFailure.malformed
        }
    }
}
public struct SupportTicketReadTicket: Decodable, Equatable, Identifiable {
    public let ticket_no, requester_role, category, subject, status: String
    public let version: Int64
    public let timezone, locale, sla_state, sla_first_due_at, sla_resolve_due_at, create_time, resolved_at, closed_at: String?
    public let related_reference: SupportTicketReadReference?
    public var id: String { ticket_no }
    public static let states: Set<String> = ["OPEN", "PENDING_MEMBER", "PENDING_AGENT", "RESOLVED", "CLOSED", "REOPENED"]
    func validate(owner: Int) throws {
        guard SupportTicketReadRoute.validNumber(ticket_no), version > 0, Self.states.contains(status),
              ["PLAYER", "MERCHANT", "CLUB_OWNER"].contains(requester_role),
              ["ORDER", "REFUND", "PAYMENT", "ACCOUNT", "CONTENT", "ACTIVITY", "VERIFY", "OTHER"].contains(category),
              !subject.isEmpty, subject.utf8.count <= 16_384,
              [timezone, locale, sla_state, sla_first_due_at, sla_resolve_due_at, create_time, resolved_at, closed_at].allSatisfy({ ($0?.utf8.count ?? 0) <= 256 }) else { throw SupportTicketReadFailure.malformed }
        if requester_role == "CLUB_OWNER" { guard related_reference?.domain_type == "USER" else { throw SupportTicketReadFailure.malformed } }
        if requester_role == "MERCHANT" { guard related_reference?.domain_type == "MERCHANT" else { throw SupportTicketReadFailure.malformed } }
        try related_reference?.validate(owner: owner, role: requester_role)
    }
}
public struct SupportTicketReadMessage: Decodable, Equatable, Identifiable {
    public let id: Int64
    public let sender_type, content, content_type, create_time: String
    public let attachments: [Int64]
    enum CodingKeys: String, CodingKey { case id, sender_type, content, content_type, create_time, attachments, is_internal }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard !c.contains(.is_internal) else { throw SupportTicketReadFailure.malformed }
        id = try c.decode(Int64.self, forKey: .id); sender_type = try c.decode(String.self, forKey: .sender_type)
        content = try c.decode(String.self, forKey: .content); content_type = try c.decode(String.self, forKey: .content_type)
        create_time = try c.decode(String.self, forKey: .create_time); attachments = try c.decode([Int64].self, forKey: .attachments)
        guard id > 0, ["MEMBER", "AGENT", "SYSTEM", "BOT"].contains(sender_type),
              content.utf8.count <= 131_072, content_type.utf8.count <= 128, create_time.utf8.count <= 256,
              attachments.count <= 100, attachments.allSatisfy({ $0 > 0 }), Set(attachments).count == attachments.count else { throw SupportTicketReadFailure.malformed }
    }
}
public struct SupportTicketReadEvent: Decodable, Equatable, Identifiable {
    public let id: Int64
    public let event_type, actor_type, created_at, result_state: String
    public let historical_status, historical_sla_state, reason, request_id: String?
    public let historical_version, message_id: Int64?
    private struct Key: CodingKey { let stringValue: String; let intValue: Int? = nil; init?(stringValue: String) { self.stringValue = stringValue }; init?(intValue: Int) { return nil } }
    public init(from decoder: Decoder) throws {
        let all = try decoder.container(keyedBy: Key.self)
        let allowed: Set<String> = ["id","event_type","actor_type","created_at","result_state","historical_status","historical_sla_state","reason","request_id","historical_version","message_id"]
        guard Set(all.allKeys.map(\.stringValue)).isSubset(of: allowed) else { throw SupportTicketReadFailure.malformed }
        func required<T: Decodable>(_ name: String, _: T.Type) throws -> T { try all.decode(T.self, forKey: Key(stringValue: name)!) }
        func optional<T: Decodable>(_ name: String, _: T.Type) throws -> T? { try all.decodeIfPresent(T.self, forKey: Key(stringValue: name)!) }
        id = try required("id", Int64.self); event_type = try required("event_type", String.self); actor_type = try required("actor_type", String.self)
        created_at = try required("created_at", String.self); result_state = try required("result_state", String.self)
        historical_status = try optional("historical_status", String.self); historical_sla_state = try optional("historical_sla_state", String.self)
        reason = try optional("reason", String.self); request_id = try optional("request_id", String.self)
        historical_version = try optional("historical_version", Int64.self); message_id = try optional("message_id", Int64.self)
        let events: [String: Set<String>] = ["MEMBER": ["CREATED","REPLY","CLOSE","REOPEN","RATE","REPLY_REJECTED","CLOSE_REJECTED","REOPEN_REJECTED","RATE_REJECTED"], "SUPPORT": ["ASSIGN","REPLY","RESOLVE"], "SYSTEM": ["CLOSED","SLA_BREACHED","ESCALATED"]]
        guard id > 0, events[actor_type]?.contains(event_type) == true,
              ["APPLIED","REJECTED","NOT_CAPTURED","UNAVAILABLE"].contains(result_state),
              [created_at, historical_status, historical_sla_state, reason, request_id].allSatisfy({ ($0?.utf8.count ?? 0) <= 256 }),
              historical_version.map({ $0 > 0 }) ?? true, message_id.map({ $0 > 0 }) ?? true,
              request_id == nil || actor_type == "MEMBER" else { throw SupportTicketReadFailure.malformed }
    }
}
public struct SupportTicketReadPage: Decodable {
    public let list: [SupportTicketReadTicket]
    public let has_more: Bool
    public let next_cursor: Int64
}
public struct SupportTicketReadTimeline: Decodable {
    let resource_type, ticket_no, audience, source: String
    public let events: [SupportTicketReadEvent]
    public let has_more: Bool
    public let next_before: Int64
}
public struct SupportTicketReadDetail: Decodable {
    public let ticket: SupportTicketReadTicket
    public let messages: [SupportTicketReadMessage]
    public let has_more: Bool
    public let next_cursor: Int64
    let business_result: String
    public let timeline: SupportTicketReadTimeline?
}
/// r463 uses POST for these read-only projections. No other body or subroute is allowed.
public enum SupportTicketReadRoute: Equatable {
    case history(before: Int64), detail(number: String, after: Int64), timeline(number: String, before: Int64)
    public static let root = "api/support/tickets"
    public static func validNumber(_ value: String) -> Bool { value.hasPrefix("CS") && value.utf8.count <= 24 && value.utf8.count > 2 && value.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 || $0 == 95 } }
    public var capability: SupportTicketReadCapability { switch self { case .history: return .history; case .detail: return .detail; case .timeline: return .timeline } }
    public var path: String { Self.root + (capability == .history ? "/list" : "/detail") }
    public var isValid: Bool { switch self { case .history(let v): return v >= 0; case .detail(let n, let v), .timeline(let n, let v): return Self.validNumber(n) && v >= 0 } }
    func body() throws -> Data {
        let fields: [String: ProjectEditJSON]
        switch self {
        case .history(let v): fields = ["cursor": .number(Decimal(v))]
        case .detail(let n, let v): fields = ["ticket_no": .string(n), "cursor": .number(Decimal(v))]
        case .timeline(let n, let v): fields = ["ticket_no": .string(n), "cursor": .number(0), "event_cursor": .number(Decimal(v))]
        }
        return try JSONEncoder().encode(fields)
    }
    public init?(request: URLRequest, baseURL: URL) {
        guard request.httpMethod == "POST", !request.httpShouldHandleCookies, request.httpBodyStream == nil,
              request.value(forHTTPHeaderField: "Cookie") == nil, request.value(forHTTPHeaderField: "Proxy-Authorization") == nil,
              let url = request.url, let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.query == nil, parts.fragment == nil, parts.user == nil, parts.password == nil,
              let data = request.httpBody, data.count <= 512, let text = String(data: data, encoding: .utf8),
              let parsed = try? ContentDraftJSON.parse(text),
              let object = try? JSONDecoder().decode([String: ProjectEditJSON].self, from: data), let cursor = object["cursor"]?.integer, cursor >= 0 else { return nil }
        if url.absoluteString.utf8.elementsEqual(baseURL.appendingPathComponent(Self.root + "/list").absoluteString.utf8) { self = .history(before: Int64(cursor)) }
        else if url.absoluteString.utf8.elementsEqual(baseURL.appendingPathComponent(Self.root + "/detail").absoluteString.utf8), let no = object["ticket_no"]?.text {
            if let event = object["event_cursor"]?.integer { guard cursor == 0, event >= 0 else { return nil }; self = .timeline(number: no, before: Int64(event)) }
            else { self = .detail(number: no, after: Int64(cursor)) }
        } else { return nil }
        guard isValid, let expected = try? body(), let expectedText = String(data: expected, encoding: .utf8),
              (try? ContentDraftJSON.parse(expectedText)) == parsed else { return nil }
    }
}

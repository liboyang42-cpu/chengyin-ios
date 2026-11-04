import Foundation
import CoreFoundation

/// The retained IM source has no voice message type or websocket authentication contract.
public enum IMCapabilityGap: Error, Equatable { case consentRequired, invalidMedia, staleScope, unknownOutcome }
public struct IMScope: Hashable {
    public let identity: MessagingReadIdentity
    public let conversationID: Int
    public init(identity: MessagingReadIdentity, conversationID: Int) throws {
        guard identity.accountID > 0, conversationID > 0 else { throw APIError.invalidRequest }
        self.identity = identity; self.conversationID = conversationID
    }
}
public enum IMOutgoingPayload: Codable, Equatable {
    case image(URL)
    case voice(IMVoiceReference)
    case file(IMFileReference)
    case video(IMVideoReference)
    case staticLocation(IMStaticLocation)
    case route(topicID: Int)
    case location(name: String, address: String, latitude: Double, longitude: Double)
    public func wireFields(approvedOrigins: Set<String>) throws -> [String: String] {
        switch self {
        case .voice(let reference): return try reference.wireFields()
        case .file(let reference): return try reference.wireFields()
        case .video(let reference): return try reference.wireFields()
        case .staticLocation(let place):
            return try place.wireFields()
        case .image(let url):
            guard let origin = SocialMessageMediaService.origin(url), approvedOrigins.contains(origin),
                  let c = URLComponents(url: url, resolvingAgainstBaseURL: false), c.fragment == nil else { throw SocialMediaFailure.originNotApproved }
            return ["msg_type": "2", "content": url.absoluteString]
        case .route(let id):
            guard id > 0 else { throw APIError.invalidRequest }
            return try card(["cardType": "route", "topicId": id], content: "[路线]")
        case .location(let name, let address, let lat, let lng):
            guard lat.isFinite, lng.isFinite, (-90...90).contains(lat), (-180...180).contains(lng) else { throw APIError.invalidRequest }
            return try card(["cardType": "location", "name": name, "address": address, "lat": lat, "lng": lng], content: "[位置]")
        }
    }
    private func card(_ json: [String: Any], content: String) throws -> [String: String] {
        let data = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
        guard let raw = String(data: data, encoding: .utf8) else { throw APIError.invalidRequest }
        return ["msg_type": "3", "content": content, "extra_json": raw]
    }
}
public struct IMOutgoingIntent: Equatable {
    public let scope: IMScope
    public let payload: IMOutgoingPayload
    public let clientMessageID: String
    public init(scope: IMScope, payload: IMOutgoingPayload, clientMessageID: String = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()) throws {
        // Reuse the established source identifier validation without duplicating it.
        _ = try MessageTextIntent(conversationID: scope.conversationID, content: "validation", clientMessageID: clientMessageID)
        self.scope = scope; self.payload = payload; self.clientMessageID = clientMessageID
    }
}
public enum IMMutation: Equatable {
    case start(targetMemberID: Int)
    case read(conversationID: Int)
    /// Explicit channel ack. The request id stays on this value so a retry does not mint another one.
    case readCursor(conversationID: Int, lastMessageID: Int, requestID: String)
    case mute(conversationID: Int, muted: Bool)
    case send(IMOutgoingIntent)
    public var conversationID: Int? {
        switch self {
        case .start: return nil
        case .read(let id), .readCursor(let id, _, _), .mute(let id, _): return id
        case .send(let intent): return intent.scope.conversationID
        }
    }
}
public enum IMMutationReceipt: Equatable { case started(conversationID: Int), read, muted(Bool), sent(MessagingMessage) }

/// 667a im/chat.fetchTopics: route shares use only the current message projection.
/// Signup's topic detail is a separate contract and cannot recover a private route.
public struct IMRouteCardProjection: Equatable {
    public let topicID: Int
    public let name: String
    public let totalMileage: Double
    public let locationCount: Int
    public let imageURL: String?

    public static func read(_ message: MessagingMessage, current: Bool = true) -> Self? {
        guard current, message.isPayloadVisible, message.type == 3,
              let card = message.card, card.kind == .route, let topicID = card.topicID,
              let content = message.content, content.hasPrefix("[路线]"),
              let bytes = message.extraJSON?.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any] else { return nil }
        let name = String(content.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        func number(_ key: String) -> Double? {
            guard let value = object[key] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
            let result = value.doubleValue
            return result.isFinite && result >= 0 ? result : nil
        }
        let mileage = number("totalMileage") ?? 0
        let count = number("locationCount").flatMap { Int(exactly: $0) } ?? 0
        let image = (object["imgUrl"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return Self(topicID: topicID, name: name, totalMileage: mileage, locationCount: count,
                    imageURL: image.flatMap { $0.isEmpty ? nil : $0 })
    }
}

/// Read tickets belong to one presentation generation. A cancelled older read's
/// cleanup cannot release a newer read or turn its old snapshot into current data.
public struct IMRouteProjectionReadState: Equatable {
    public struct Ticket: Equatable {
        fileprivate let generation: UInt64
        public let id: UUID
    }
    private var generation: UInt64 = 0
    private var inFlight: Ticket?
    private var accepted: MessagingMessage?
    private var acceptedUpstream: MessagingMessage?
    public init() {}
    public mutating func invalidate() {
        generation &+= 1; inFlight = nil; accepted = nil; acceptedUpstream = nil
    }
    public mutating func begin() -> Ticket? {
        guard inFlight == nil else { return nil }
        accepted = nil; acceptedUpstream = nil
        let ticket = Ticket(generation: generation, id: UUID()); inFlight = ticket
        return ticket
    }
    @discardableResult public mutating func complete(_ ticket: Ticket, message: MessagingMessage?, upstream: MessagingMessage?) -> Bool {
        guard inFlight == ticket, ticket.generation == generation else { return false }
        accepted = message; acceptedUpstream = upstream; inFlight = nil
        return true
    }
    public mutating func finish(_ ticket: Ticket) {
        guard inFlight == ticket, ticket.generation == generation else { return }
        inFlight = nil
    }
    public func isReading(_ ticket: Ticket) -> Bool {
        inFlight == ticket && ticket.generation == generation
    }
    public func isCurrent(_ message: MessagingMessage, upstream: MessagingMessage?) -> Bool {
        inFlight == nil && accepted == message && acceptedUpstream == upstream
    }
    /// Even status=normal can carry a now-unavailable route. That newer upstream
    /// projection must win over an older successful detail read of the same ID.
    public static func resolve(verified: MessagingMessage?, upstream: MessagingMessage?, upstreamAtRead: MessagingMessage?) -> MessagingMessage? {
        if let upstream, !upstream.isPayloadVisible { return upstream }
        if upstream != upstreamAtRead { return upstream }
        // A successful read started after this exact upstream projection is newer
        // evidence. This also lets an explicit retry recover a route made public again.
        return verified
    }
}

/// Untrusted card payload is only projected into a typed local destination. No generic
/// URL opening, arbitrary router dispatch, synthetic business mutation or click telemetry.
public enum IMCardDestination: Equatable { case topic(Int), review(MessagingCardResult), unsupported }
public struct IMCardAction: Equatable {
    public let label: String
    public let isReject: Bool
    public let destination: IMCardDestination
    public static func actions(for message: MessagingMessage) -> [Self] {
        guard message.isPayloadVisible, let card = message.card else { return [] }
        if message.senderID == 0, let result = card.result, !result.isEmpty {
            return [Self(label: "im.full.reviewResult", isReject: false, destination: .review(result))]
        }
        if card.kind == .route {
            guard let projection = IMRouteCardProjection.read(message) else { return [] }
            return [Self(label: "im.full.viewTopic", isReject: false, destination: .topic(projection.topicID))]
        }
        if let id = card.topicID { return [Self(label: "im.full.viewTopic", isReject: false, destination: .topic(id))] }
        guard let raw = message.extraJSON?.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any] else { return [] }
        let buttons = json["buttons"] as? [[String: Any]] ?? []
        let rows = buttons.isEmpty ? [["text": "im.full.details", "action": json["action"] ?? ""]] : buttons
        return rows.compactMap { row in
            guard let text = row["text"] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return Self(label: text, isReject: row["type"] as? String == "reject", destination: destination(row["action"] as? String))
        }
    }
    private static func destination(_ action: String?) -> IMCardDestination {
        guard let action, action.hasPrefix("/topic/"), !action.contains("?"), !action.contains("#"), !action.contains("%") else { return .unsupported }
        let tail = String(action.dropFirst(7))
        guard !tail.isEmpty, tail.allSatisfy(\.isNumber), let id = Int(tail), id > 0 else { return .unsupported }
        return .topic(id)
    }
}

/// User-selected static place only. No device fix, background tracking or inferred datum.
/// Legacy .location payload remains byte-compatible with its existing protected UNKNOWN record.
public struct IMStaticLocation: Codable, Equatable {
    public let name: String
    public let address: String
    public let lat: Double
    public let lng: Double
    public let datum: String
    public let source: String
    public init(name: String, address: String, latitude: Double, longitude: Double, datum: String) throws {
        let name=name.trimmingCharacters(in:.whitespacesAndNewlines)
        let address=address.trimmingCharacters(in:.whitespacesAndNewlines)
        guard datum == "WGS84", (1...120).contains(name.utf16.count), address.utf16.count <= 300,
              latitude.isFinite, longitude.isFinite, (-90...90).contains(latitude), (-180...180).contains(longitude),
              !name.unicodeScalars.contains(where: { $0.value < 32 }),
              !address.unicodeScalars.contains(where: { $0.value < 32 }) else { throw APIError.invalidRequest }
        self.name=name;self.address=address;self.datum=datum;self.source="static-location-v1"
        self.lat=Self.coarse(latitude);self.lng=Self.coarse(longitude)
    }
    private static func coarse(_ value: Double) -> Double {
        let result=(value*10000).rounded(.toNearestOrAwayFromZero)/10000
        return result == 0 ? 0 : result
    }
    public func validated() throws -> Self {
        let value=try Self(name:name,address:address,latitude:lat,longitude:lng,datum:datum)
        guard value == self else { throw APIError.invalidRequest };return value
    }
    public func wireFields() throws -> [String:String] {
        _ = try validated()
        let encoder=JSONEncoder();encoder.outputFormatting=[.sortedKeys,.withoutEscapingSlashes]
        guard let extra=String(data:try encoder.encode(self),encoding:.utf8) else { throw APIError.invalidRequest }
        return ["msg_type":"13","content":name,"extra_json":extra]
    }
    public static func read(_ message: MessagingMessage) -> Self? {
        guard message.isPayloadVisible, message.type == 13,
              let bytes=message.extraJSON?.data(using:.utf8),bytes.count <= 4096,
              let value=try? JSONDecoder().decode(Self.self,from:bytes),
              (try? value.validated()) != nil,message.content == value.name else { return nil }
        return value
    }
}

/// A short-lived projection of the original anonymous public-share predicate, not a permission token.
public struct IMRouteShareSource: Decodable, Equatable {
    public let source: String
    public let topicID: Int
    public let name: String
    public let publiclyShareable: Bool
    enum CodingKeys: String,CodingKey { case source,topicID="topic_id",name,publiclyShareable="publicly_shareable" }
    public init(from decoder: Decoder) throws {
        let c=try decoder.container(keyedBy:CodingKeys.self)
        source=try c.decode(String.self,forKey:.source)
        let raw=try c.decode(String.self,forKey:.topicID)
        guard let id=Int(raw),id>0,String(id)==raw else { throw APIError.malformedResponse };topicID=id
        name=try c.decode(String.self,forKey:.name);publiclyShareable=try c.decode(Bool.self,forKey:.publiclyShareable)
        guard source=="original-route-share-v1",publiclyShareable,!name.isEmpty,name.utf16.count<=1000 else { throw APIError.malformedResponse }
    }
}
public extension IMOutgoingIntent {
    /// Viewer-specific title/image fields are deliberately not evidence of the original request.
    func matchesOriginalRouteMessage(_ message: MessagingMessage) -> Bool {
        guard case .route(let topic)=payload,message.conversationID==scope.conversationID,
              message.senderID==scope.identity.accountID,message.isPayloadVisible,message.type==3,
              let card=message.card,card.kind == .route,card.topicID==topic else { return false }
        return true
    }
}

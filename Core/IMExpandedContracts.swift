import Foundation

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
public enum IMOutgoingPayload: Equatable {
    case image(URL)
    case route(topicID: Int)
    case location(name: String, address: String, latitude: Double, longitude: Double)
    public func wireFields(approvedOrigins: Set<String>) throws -> [String: String] {
        switch self {
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
    case mute(conversationID: Int, muted: Bool)
    case send(IMOutgoingIntent)
    public var conversationID: Int? {
        switch self { case .start: return nil; case .read(let id), .mute(let id, _): return id; case .send(let intent): return intent.scope.conversationID }
    }
}
public enum IMMutationReceipt: Equatable { case started(conversationID: Int), read, muted(Bool), sent(MessagingMessage) }

/// Untrusted card payload is only projected into a typed local destination. No generic
/// URL opening, arbitrary router dispatch, synthetic business mutation or click telemetry.
public enum IMCardDestination: Equatable { case topic(Int), review(MessagingCardResult), unsupported }
public struct IMCardAction: Equatable {
    public let label: String
    public let isReject: Bool
    public let destination: IMCardDestination
    public static func actions(for message: MessagingMessage) -> [Self] {
        guard let card = message.card else { return [] }
        if message.senderID == 0, let result = card.result, !result.isEmpty {
            return [Self(label: "im.full.reviewResult", isReject: false, destination: .review(result))]
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

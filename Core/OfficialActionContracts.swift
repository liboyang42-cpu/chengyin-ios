import Foundation

public enum OfficialActionFailure: Error, Equatable {
    case disabled, invalid, forbidden, stale, busy, locked, storage, unknown
    case rejected(Int, String?)
}
public struct OfficialActionIdentity: Equatable, Codable {
    public let accountID: Int
    public let epoch: UUID
    public let namespace: String
    public init(accountID: Int, epoch: UUID, namespace: String) {
        self.accountID = accountID; self.epoch = epoch; self.namespace = namespace
    }
}
public enum OfficialAudience: String, CaseIterable, Codable { case player, club, merchant }
public enum OfficialChannel: String, CaseIterable, Codable { case inapp, subscribe }
public enum OfficialResponseAction: String, CaseIterable { case accept = "ACCEPT", decline = "DECLINE", withdraw = "WITHDRAW" }
public struct OfficialEventDraft: Equatable {
    public var title = "", subtitle = "", city = ""
    public var category = "city_light", metric = "light_count"
    public var start: Date?, end: Date?
    public var collective = false, badge = false
    public var threshold = 0.0, experience = 0.0
    public init() {}
    public func payload() throws -> Data {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              ["city_light", "custom", "festival", "brand", "challenge"].contains(category),
              ["light_count", "complete_count", "signup_count"].contains(metric),
              threshold.isFinite, experience.isFinite, threshold >= 0, experience >= 0 else { throw OfficialActionFailure.invalid }
        let reward = try Self.jsonString(["settleXp": experience, "settleBadge": badge])
        return try JSONSerialization.data(withJSONObject: [
            "title": title.trimmingCharacters(in: .whitespacesAndNewlines),
            "subtitle": subtitle.trimmingCharacters(in: .whitespacesAndNewlines),
            "city": city.trimmingCharacters(in: .whitespacesAndNewlines), "category": category,
            "activityStart": start.map { $0.timeIntervalSince1970 * 1000 } as Any? ?? NSNull(),
            "activityEnd": end.map { $0.timeIntervalSince1970 * 1000 } as Any? ?? NSNull(),
            "settleTime": end.map { $0.timeIntervalSince1970 * 1000 } as Any? ?? NSNull(),
            "collectiveEnabled": collective ? 1 : 0, "collectiveMetric": metric,
            "collectiveThreshold": collective ? threshold : 0, "rewardJson": reward], options: [.sortedKeys])
    }
    static func jsonString(_ object: Any) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self)
    }
}
public struct OfficialCopy: Equatable {
    public var title = "", sub = ""
    public init(title: String = "", sub: String = "") { self.title = title; self.sub = sub }
    var object: [String: String] { ["title": title.trimmingCharacters(in: .whitespacesAndNewlines), "sub": sub.trimmingCharacters(in: .whitespacesAndNewlines)] }
}
public struct OfficialBroadcastDraft: Equatable {
    public var eventID: Int?
    public var city = ""
    public var audience: Set<OfficialAudience> = []
    public var channels: Set<OfficialChannel> = []
    public var split = false
    public var unified = OfficialCopy()
    public var copies: [OfficialAudience: OfficialCopy] = [:]
    public init() {}
    public func payload() throws -> Data {
        guard !audience.isEmpty, !channels.isEmpty, eventID == nil || eventID! > 0 else { throw OfficialActionFailure.invalid }
        let roles = OfficialAudience.allCases.filter { audience.contains($0) }
        let selected = roles.map { copies[$0] ?? OfficialCopy() }
        guard split ? selected.allSatisfy({ !$0.object["title"]!.isEmpty }) : !unified.object["title"]!.isEmpty else { throw OfficialActionFailure.invalid }
        var content: [String: Any] = unified.object
        if split { content = Dictionary(uniqueKeysWithValues: roles.map { ($0.rawValue, (copies[$0] ?? OfficialCopy()).object as Any) }) }
        return try JSONSerialization.data(withJSONObject: [
            "eventId": eventID as Any? ?? NSNull(), "title": split ? "官方通知" : unified.object["title"]!,
            "audience": roles.map(\.rawValue).joined(separator: ","), "copyMode": split ? 2 : 1,
            "contentJson": try OfficialEventDraft.jsonString(content),
            "channels": OfficialChannel.allCases.filter { channels.contains($0) }.map(\.rawValue).joined(separator: ","),
            "city": city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? NSNull() : city.trimmingCharacters(in: .whitespacesAndNewlines) as Any], options: [.sortedKeys])
    }
}
/// Host supplies a fresh real server session and an explicitly approved location sample.
/// No location collection, request-ID generation or session fabrication occurs here.
public struct OfficialArrivalEvidence: Equatable {
    public let identity: OfficialActionIdentity
    public let eventID: Int, sessionID: Int
    public let missionCode: String, requestID: String
    public let latitude: Double, longitude: Double, accuracyM: Double
    public let expiresAt: Date
    public init(identity: OfficialActionIdentity, eventID: Int, sessionID: Int, missionCode: String, requestID: String, latitude: Double, longitude: Double, accuracyM: Double, expiresAt: Date) {
        self.identity = identity; self.eventID = eventID; self.sessionID = sessionID; self.missionCode = missionCode; self.requestID = requestID
        self.latitude = latitude; self.longitude = longitude; self.accuracyM = accuracyM; self.expiresAt = expiresAt
    }
    func payload() throws -> Data {
        guard eventID > 0, sessionID > 0, !missionCode.isEmpty, !requestID.isEmpty,
              latitude.isFinite, longitude.isFinite, accuracyM.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude), accuracyM >= 0 else { throw OfficialActionFailure.invalid }
        return try JSONSerialization.data(withJSONObject: ["missionCode": missionCode, "latitude": latitude, "longitude": longitude,
            "accuracyM": accuracyM, "sessionId": sessionID, "requestId": requestID], options: [.sortedKeys])
    }
}
public enum OfficialActionCommand: Equatable {
    case publish(OfficialEventDraft), broadcast(OfficialBroadcastDraft), inviteMerchants([Int])
    case signup(Int), complete(Int), arrival(OfficialArrivalEvidence)
    case respond(partyID: Int, type: String, action: OfficialResponseAction, reason: String?)
    public var path: String {
        switch self {
        case .publish: return "api/official/publish"
        case .broadcast: return "api/official/broadcast"
        case .inviteMerchants: return "api/official/invites"
        case .signup(let id): return "api/official/events/\(id)/signup"
        case .complete(let id): return "api/official/events/\(id)/complete"
        case .arrival(let e): return "api/official/events/\(e.eventID)/arrivals"
        case let .respond(id, type, action, _):
            return type == "OFFICIAL" ? "api/official/v2/organizer-invites/\(id)/\(action.rawValue.lowercased())" : "api/official/v2/parties/\(id)/\(action.rawValue)"
        }
    }
    public var titleKey: String {
        switch self { case .publish: return "officialAction.publish"; case .broadcast: return "officialAction.broadcast"
        case .inviteMerchants: return "officialAction.invite"; case .signup: return "officialAction.signup"
        case .complete: return "officialAction.complete"; case .arrival: return "officialAction.arrival"
        case .respond(_, _, let action, _): return "officialAction." + action.rawValue.lowercased() }
    }
    public var scope: String {
        switch self {
        case .publish: return "publish"
        case .broadcast: return "broadcast"
        case .inviteMerchants: return "invites"
        case .signup(let id), .complete(let id): return "event:\(id)"
        case .arrival(let e): return "event:\(e.eventID)"
        case .respond(let id, _, _, _): return "party:\(id)"
        }
    }
    public func payload() throws -> Data? {
        switch self {
        case .publish(let d): return try d.payload()
        case .broadcast(let d): return try d.payload()
        case .inviteMerchants(let ids):
            guard !ids.isEmpty, ids.allSatisfy({ $0 > 0 }), Set(ids).count == ids.count else { throw OfficialActionFailure.invalid }
            return try JSONSerialization.data(withJSONObject: ["merchantIds": ids], options: [.sortedKeys])
        case .arrival(let e): return try e.payload()
        case .signup(let id), .complete(let id): guard id > 0 else { throw OfficialActionFailure.invalid }; return nil
        case let .respond(id, type, action, reason):
            guard id > 0, ["OFFICIAL", "MERCHANT", "CLUB"].contains(type), !(type == "OFFICIAL" && action == .withdraw) else { throw OfficialActionFailure.invalid }
            if type == "OFFICIAL" { return nil }
            return try JSONSerialization.data(withJSONObject: reason.map { ["reason": $0] } ?? [:], options: [.sortedKeys])
        }
    }
}
public struct OfficialActionSnapshot: Equatable {
    public let identity: OfficialActionIdentity
    public let publisher: Bool
    public let event: OfficialEvent?
    public let invite: OfficialPartyInvite?
    /// Exact verified merchant selection, read by the host from authorized sources.
    public let merchantIDs: [Int]
    public init(identity: OfficialActionIdentity, publisher: Bool = false, event: OfficialEvent? = nil, invite: OfficialPartyInvite? = nil, merchantIDs: [Int] = []) {
        self.identity = identity; self.publisher = publisher; self.event = event; self.invite = invite; self.merchantIDs = merchantIDs
    }
    public func validate(_ command: OfficialActionCommand, now: Date) throws {
        guard identity.accountID > 0, !identity.namespace.isEmpty else { throw OfficialActionFailure.forbidden }
        _ = try command.payload()
        switch command {
        case .publish: guard publisher else { throw OfficialActionFailure.forbidden }
        case .broadcast(let draft):
            guard publisher else { throw OfficialActionFailure.forbidden }
            if let id = draft.eventID { guard event?.id == id else { throw OfficialActionFailure.forbidden } }
        case .inviteMerchants(let ids): guard publisher, ids == merchantIDs else { throw OfficialActionFailure.forbidden }
        case .signup(let id):
            guard let event, event.id == id, event.signed == false, !event.paused, [2, 3].contains(event.status ?? -1) else { throw OfficialActionFailure.forbidden }
        case .complete(let id):
            guard let event, event.id == id, event.signed == true, !event.paused, event.status == 3, !event.isV2, !event.roamEnabled else { throw OfficialActionFailure.forbidden }
        case .arrival(let evidence):
            guard let event, event.id == evidence.eventID, event.isV2, event.signed == true, event.status == 3, !event.paused,
                  evidence.identity == identity, evidence.expiresAt > now,
                  event.missions.contains(where: { $0.code == evidence.missionCode && $0.canVerifyArrival == true && $0.complete == false }) else { throw OfficialActionFailure.forbidden }
        case let .respond(id, type, action, _):
            guard let invite, invite.id == id, invite.partyType == type else { throw OfficialActionFailure.forbidden }
            if type == "OFFICIAL" { guard publisher, invite.status == "INVITED", action != .withdraw else { throw OfficialActionFailure.forbidden } }
            else { guard action == .withdraw ? ["ACCEPTED", "ACTIVE"].contains(invite.status ?? "") : invite.status == "INVITED" else { throw OfficialActionFailure.forbidden } }
        }
    }
}
public enum OfficialActionReceipt: Equatable {
    case acknowledged, published(Int), broadcastSubmitted(Int), invitesIssued([Int])
    case arrival(accepted: Bool, completed: Bool, reason: String?)
}

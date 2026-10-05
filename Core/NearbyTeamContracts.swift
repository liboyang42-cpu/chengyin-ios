import Foundation

public struct NearbyTeamID: Hashable, Codable { public let rawValue: Int; public init(_ value: Int) { rawValue = value } }
public struct NearbyApplicantID: Hashable, Codable { public let rawValue: Int; public init(_ value: Int) { rawValue = value } }
public enum NearbyViewerStatus: String, Codable { case none = "NONE", pending = "PENDING", joined = "JOINED", leader = "LEADER", rejected = "REJECTED", unknown = "UNKNOWN"
    public var key: String { "nearby.status.\(rawValue.lowercased())" }
}
/// Query context is manually selected/injected. It is never location, ticket, or membership evidence.
public struct NearbyQueryContext: Equatable {
    public static let radii = [1000, 3000, 5000, 10000, 20000]
    public let latitude: Double
    public let longitude: Double
    public let radius: Int
    public init(latitude: Double, longitude: Double, radius: Int = 3000) { self.latitude = latitude; self.longitude = longitude; self.radius = radius }
    public var valid: Bool { latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude) && Self.radii.contains(radius) }
    public func nextRadius() -> Self { .init(latitude: latitude, longitude: longitude, radius: Self.radii[((Self.radii.firstIndex(of: radius) ?? -1) + 1) % Self.radii.count]) }
}
/// Preserve server expiry provenance and representation. Never synthesize now + 24h.
public enum NearbyServerTime: Decodable, Equatable {
    case number(Double), text(String)
    public init(from decoder: Decoder) throws { let c = try decoder.singleValueContainer(); if let n = try? c.decode(Double.self) { self = .number(n) } else { self = .text(try c.decode(String.self)) } }
    public func date(timeZone: TimeZone = .current) -> Date? {
        switch self {
        case .number(let n):
            guard n.isFinite, n != 0, n < Double(Int64.max), n > Double(Int64.min) else { return nil }
            return Date(timeIntervalSince1970: n > 0 && String(Int64(n)).count == 10 ? n : n / 1000)
        case .text(let raw):
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.allSatisfy(\.isNumber), let number = Double(text), number > 0 {
                guard [10, 13].contains(text.count) else { return nil }; return Date(timeIntervalSince1970: text.count == 10 ? number : number / 1000)
            }
            let iso = ISO8601DateFormatter(); iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = iso.date(from: text) { return date }
            iso.formatOptions = [.withInternetDateTime]; if let date = iso.date(from: text) { return date }
            for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm"] {
                let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.timeZone = timeZone; formatter.dateFormat = format; formatter.isLenient = false
                if let date = formatter.date(from: text) { return date }
            }; return nil
        }
    }
    public func remainingMinutes(now: Date) -> Int? { guard let date = date(), date > now else { return nil }; return max(1, Int(date.timeIntervalSince(now) / 60)) }
}
public struct NearbyTeam: Decodable, Equatable, Identifiable {
    public var id: NearbyTeamID { teamID }
    public let teamID: NearbyTeamID
    public let activityID: Int?
    public let topicID: Int?
    public let title: String
    public let activityName: String
    public let leaderName: String
    public let addressName: String
    public let coordSource: String
    public let productType: Int?
    public let distance: Double?
    public let latitude: Double?
    public let longitude: Double?
    public let memberAvatars: [String]
    public let joinedCount: Int
    public let maxMembers: Int
    public let pendingCount: Int
    public private(set) var viewerStatus: NearbyViewerStatus
    public private(set) var viewerHasTicket: Bool
    public private(set) var applyExpireTime: NearbyServerTime?
    enum CodingKeys: String, CodingKey { case teamId, activityId, topicId, title, activityName, leaderName, addressName, coordSource, productType, distance, latitude, longitude, memberAvatars, joinedCount, maxMembers, pendingCount, viewerStatus, viewerHasTicket, applyExpireTime }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = c.nearbyInt(.teamId), id > 0 else { throw NearbyTeamFailure.contract }
        teamID = .init(id); activityID = c.nearbyInt(.activityId); topicID = c.nearbyInt(.topicId)
        title = c.nearbyText(.title); activityName = c.nearbyText(.activityName); leaderName = c.nearbyText(.leaderName); addressName = c.nearbyText(.addressName); coordSource = c.nearbyText(.coordSource)
        productType = c.nearbyInt(.productType); distance = c.nearbyDouble(.distance); latitude = c.nearbyDouble(.latitude); longitude = c.nearbyDouble(.longitude)
        memberAvatars = Array((try c.decodeIfPresent([String].self, forKey: .memberAvatars) ?? []).filter { !$0.isEmpty }.prefix(3))
        joinedCount = max(0, c.nearbyInt(.joinedCount) ?? 0); maxMembers = max(0, c.nearbyInt(.maxMembers) ?? 0); pendingCount = max(0, c.nearbyInt(.pendingCount) ?? 0)
        viewerStatus = NearbyViewerStatus(rawValue: c.nearbyText(.viewerStatus)) ?? .unknown
        viewerHasTicket = (try? c.decode(Bool.self, forKey: .viewerHasTicket)) == true
        applyExpireTime = try c.decodeIfPresent(NearbyServerTime.self, forKey: .applyExpireTime)
    }
    public var mode: String {
        switch viewerStatus { case .leader: return "leader"; case .joined: return "joined"; case .pending: return "pending"; case .rejected: return "rejected"; case .unknown: return "unknown"; case .none: return viewerHasTicket ? "apply" : "buy" }
    }
    mutating func patch(status: NearbyViewerStatus?, ticket: Bool? = nil, expiry: NearbyServerTime? = nil, replaceExpiry: Bool = false) {
        if let status { viewerStatus = status }; if let ticket { viewerHasTicket = ticket }; if replaceExpiry { applyExpireTime = expiry }
    }
}
public struct NearbyApplicant: Decodable, Equatable, Identifiable {
    public var id: NearbyApplicantID { memberID }
    public let memberID: NearbyApplicantID
    public let name: String
    public let avatar: String
    public let message: String
    public let appliedAt: NearbyServerTime?
    public let applyExpireTime: NearbyServerTime?
    enum CodingKeys: String, CodingKey { case memberId, memberName, memberAvatar, applyMessage, appliedAt, applyExpireTime }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = c.nearbyInt(.memberId), id > 0 else { throw NearbyTeamFailure.contract }; memberID = .init(id)
        name = c.nearbyText(.memberName); avatar = c.nearbyText(.memberAvatar); message = c.nearbyText(.applyMessage)
        appliedAt = try c.decodeIfPresent(NearbyServerTime.self, forKey: .appliedAt); applyExpireTime = try c.decodeIfPresent(NearbyServerTime.self, forKey: .applyExpireTime)
    }
}
public struct NearbyMyApplication: Decodable, Equatable, Identifiable {
    public let id: NearbyTeamID
    public let title: String
    public let leaderName: String
    public let status: NearbyViewerStatus
    public let applyExpireTime: NearbyServerTime?
    enum CodingKeys: String, CodingKey { case teamId, title, leaderName, applyStatus, applyExpireTime }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = c.nearbyInt(.teamId), id > 0 else { throw NearbyTeamFailure.contract }; self.id = .init(id)
        title = c.nearbyText(.title); leaderName = c.nearbyText(.leaderName); status = NearbyViewerStatus(rawValue: c.nearbyText(.applyStatus)) ?? .unknown
        applyExpireTime = try c.decodeIfPresent(NearbyServerTime.self, forKey: .applyExpireTime)
    }
}
extension KeyedDecodingContainer {
    func nearbyInt(_ key: Key) -> Int? { if let n = try? decode(Int.self, forKey: key) { return n }; if let s = try? decode(String.self, forKey: key) { return Int(s) }; return nil }
    func nearbyDouble(_ key: Key) -> Double? { let value = (try? decode(Double.self, forKey: key)) ?? (try? decode(String.self, forKey: key)).flatMap(Double.init); return value?.isFinite == true ? value : nil }
    func nearbyText(_ key: Key) -> String { ((try? decode(String.self, forKey: key)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines) }
}
public enum NearbyTeamFailure: Error, Equatable { case unconfigured, invalidRequest, contract, unauthorized, stale, role, rejected(errorCode: String, message: String), transport }
public enum NearbyTeamAction: Equatable {
    case apply(NearbyTeamID), withdraw(NearbyTeamID), handle(team: NearbyTeamID, applicant: NearbyApplicantID, approved: Bool)
    public var teamID: NearbyTeamID { switch self { case .apply(let id), .withdraw(let id): return id; case .handle(let id, _, _): return id } }
    public var operation: String { switch self { case .apply: return "apply"; case .withdraw: return "withdraw"; case .handle: return "handle" } }
    public var key: String { if case .handle(_, _, let approved) = self { return approved ? "nearby.approve" : "nearby.reject" }; return "nearby.\(operation)" }
}
/// The server errorCode alone drives patches; server message is display-only.
public struct NearbyErrorEffect: Equatable {
    public var status: NearbyViewerStatus?
    public var ticket: Bool?
    public var dropTeam = false
    public var dropApplicant = false
    public var refresh = false
    public static func messageKey(operation: String, errorCode: String) -> String {
        let codes: [String: Set<String>] = ["apply": ["TICKET_REQUIRED", "APPLY_REJECTED", "APPLY_PENDING", "ALREADY_JOINED", "TEAM_FULL", "ACTIVITY_STARTED", "TEAM_UNDER_REVIEW", "TEAM_NOT_PUBLIC", "APPLY_BLOCKED"], "withdraw": ["APPLY_NOT_PENDING"], "handle": ["APPLY_NOT_PENDING", "TICKET_REQUIRED", "TEAM_FULL", "APPLY_BLOCKED"]]
        return codes[operation]?.contains(errorCode) == true ? "nearby.error.\(operation).\(errorCode)" : "nearby.actionFailed"
    }
    public static func resolve(operation: String, errorCode: String) -> Self {
        var effect = Self()
        switch (operation, errorCode) {
        case ("apply", "TICKET_REQUIRED"): effect.status = NearbyViewerStatus.none; effect.ticket = false
        case ("apply", "APPLY_REJECTED"): effect.status = .rejected
        case ("apply", "APPLY_PENDING"): effect.status = .pending
        case ("apply", "ALREADY_JOINED"): effect.status = .joined
        case ("apply", "TEAM_FULL"), ("apply", "ACTIVITY_STARTED"), ("apply", "TEAM_UNDER_REVIEW"), ("apply", "TEAM_NOT_PUBLIC"): effect.dropTeam = true
        case ("withdraw", "APPLY_NOT_PENDING"), ("handle", "TEAM_FULL"): effect.refresh = true
        case ("handle", "APPLY_NOT_PENDING"), ("handle", "TICKET_REQUIRED"), ("handle", "APPLY_BLOCKED"): effect.dropApplicant = true
        default: break
        }; return effect
    }
}

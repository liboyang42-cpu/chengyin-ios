import Foundation
import CoreFoundation

// Source: data/models/official_event.dart and data/api/official_api.dart.
// This domain is unrelated to /api/activity/list and its date-derived ActivityBrowser buckets.
private struct OfficialKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }
    init(_ key: String) { stringValue = key }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}
private extension KeyedDecodingContainer where Key == OfficialKey {
    func text(_ key: String) -> String? { try? decode(String.self, forKey: OfficialKey(key)) }
    func integer(_ key: String) -> Int? { try? decode(Int.self, forKey: OfficialKey(key)) }
    func flag(_ key: String) -> Bool? { try? decode(Bool.self, forKey: OfficialKey(key)) }
    func list<T: Decodable>(_ key: String) throws -> [T] {
        try decodeIfPresent([T].self, forKey: OfficialKey(key)) ?? []
    }
}

/// Text dates preserve the supplied timezone/format. Only numeric timestamps become Dates.
/// No implicit operational timezone or invented date is attached to a timezone-less string.
public enum OfficialEventTime: Decodable, Equatable {
    case text(String), milliseconds(Double)
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let number = try? c.decode(Double.self), number.isFinite { self = .milliseconds(number) }
        else if let text = try? c.decode(String.self), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { self = .text(text) }
        else { throw APIError.malformedResponse }
    }
}
public struct OfficialMission: Decodable, Equatable {
    public let code: String
    public let title: String
    public let description: String?
    public let type: String?
    public let complete: Bool?
    public let canVerifyArrival: Bool?
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: OfficialKey.self)
        code = c.text("missionCode") ?? ""; title = c.text("title") ?? ""
        description = c.text("description"); type = c.text("missionType")
        complete = c.flag("complete"); canVerifyArrival = c.flag("canVerifyArrival")
    }
}
public struct OfficialCollectiveProgress: Decodable, Equatable {
    public let enabled: Bool
    public let current: Int?
    public let threshold: Int?
    public let percent: Int?
    public let reached: Bool?
    public var displayFraction: Double? { percent.map { Double(min(100, max(0, $0))) / 100 } }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: OfficialKey.self)
        enabled = c.flag("enabled") == true
        current = c.integer("current"); threshold = c.integer("threshold")
        percent = c.integer("pct"); reached = c.flag("reached")
    }
}
public enum OfficialReward: Equatable {
    case badge, coupon, experience(String), collectiveCoupon
}
public struct OfficialEvent: Decodable, Equatable, Identifiable {
    public let id: Int
    public let title: String
    public let subtitle: String?
    public let coverImage: String?
    public let city: String?
    public let status: Int?
    public let story: String?
    public let rewardJSON: String?
    public let participants: Int?
    public let myProgress: Int?
    public let signed: Bool?
    public let roamEnabled: Bool
    public let paused: Bool
    public let pausedReason: String?
    /// Public-list information only. These facts never grant or deny participation.
    public let recruitmentBlocked: Bool?
    public let recruitmentBlockedReason: String?
    public let eligible: Bool?
    public let contractVersion: Int?
    public let activityStart: OfficialEventTime?
    public let activityEnd: OfficialEventTime?
    public let bannerEnabled: Bool
    public let participantAvatars: [String]
    public let missions: [OfficialMission]
    public let collective: OfficialCollectiveProgress?
    public var isCompleteRecord: Bool { id > 0 && !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    public var isV2: Bool { (contractVersion ?? 1) >= 2 }
    public var completedMissionCount: Int { missions.filter { $0.complete == true }.count }
    public var recruitmentWarningReason: String? {
        guard recruitmentBlocked == true,
              let reason = recruitmentBlockedReason?.trimmingCharacters(in: .whitespacesAndNewlines),
              !reason.isEmpty else { return nil }
        return reason
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: OfficialKey.self)
        id = c.integer("id") ?? 0; title = c.text("title") ?? ""
        subtitle = c.text("subtitle"); coverImage = c.text("coverImg"); city = c.text("city")
        status = c.integer("status"); story = c.text("story"); rewardJSON = c.text("rewardJson")
        participants = c.integer("participants").flatMap { $0 >= 0 ? $0 : nil }
        myProgress = c.integer("myProgress").flatMap { $0 >= 0 ? $0 : nil }
        signed = c.flag("signed"); roamEnabled = c.flag("roamEnabled") == true
        paused = c.flag("paused") == true; pausedReason = c.text("pausedReason")
        recruitmentBlocked = c.flag("recruitmentBlocked")
        recruitmentBlockedReason = c.text("recruitmentBlockedReason")
        eligible = c.flag("eligible"); contractVersion = c.integer("contractVersion")
        activityStart = try? c.decode(OfficialEventTime.self, forKey: OfficialKey("activityStart"))
        activityEnd = try? c.decode(OfficialEventTime.self, forKey: OfficialKey("activityEnd"))
        bannerEnabled = c.flag("bannerEnabled") == true || c.integer("bannerEnabled") == 1 || c.text("bannerEnabled") == "1"
        let avatars: [String] = try c.list("participantAvatars")
        participantAvatars = avatars.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        missions = try c.list("missions")
        collective = try c.decodeIfPresent(OfficialCollectiveProgress.self, forKey: OfficialKey("collective"))
    }
    private var rewardMap: [String: Any] {
        guard let data = rewardJSON?.data(using: .utf8), let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return value
    }
    public var rewards: [OfficialReward] {
        let map = rewardMap
        func present(_ key: String) -> Bool { map[key] != nil && !(map[key] is NSNull) }
        var result: [OfficialReward] = []
        if present("settleBadge") { result.append(.badge) }
        if present("settleCouponId") { result.append(.coupon) }
        if let value = map["settleXp"], !(value is NSNull) { result.append(.experience(String(describing: value))) }
        if present("collectiveCouponId") { result.append(.collectiveCoupon) }
        return result
    }
    public var hasCollectiveReward: Bool {
        if let value = rewardMap["collectiveCouponId"] as? String { return (Int(value) ?? 0) > 0 }
        if let value = rewardMap["collectiveCouponId"] as? NSNumber {
            return CFGetTypeID(value) != CFBooleanGetTypeID() && value.doubleValue > 0
        }
        return false
    }
    public var statusKey: String {
        guard let status else { return "official.status.unknown" }
        if status >= 5 { return "official.status.ended" }
        switch status {
        case 1: return "official.status.upcoming"
        case 2: return "official.status.registration"
        case 3: return "official.status.live"
        case 4: return "official.status.settling"
        default: return "official.status.unknown"
        }
    }
    /// Read-only explanation of the source CTA state machine; never enables a write.
    public var participationKey: String {
        if let status, status >= 5 { return "official.status.ended" }
        if paused { return "official.status.paused" }
        if signed == true {
            if status == 3 && isV2 {
                if missions.contains(where: { $0.canVerifyArrival == true }) { return "official.participation.arrival" }
                if missions.contains(where: { $0.type == "THEME_VERIFIED_FINISH" }) { return "official.participation.themeSync" }
                return "official.participation.waitTasks"
            }
            if status == 3 { return roamEnabled ? "official.participation.roam" : "official.participation.explore" }
            return status == 1 ? "official.participation.signedWaiting" : "official.participation.signed"
        }
        if status == 2 || status == 3 { return "official.participation.registrationDeferred" }
        if status == 1 { return "official.participation.registrationSoon" }
        return "official.participation.unavailable"
    }
}

public enum OfficialEventBucket: String, CaseIterable, Identifiable {
    case live, upcoming, ended, mine
    public var id: String { rawValue }
    public var titleKey: String { "official.bucket." + rawValue }
    public func includes(_ value: OfficialEvent) -> Bool {
        switch self {
        case .live: return value.status == 2 || value.status == 3
        case .upcoming: return value.status == 1
        case .ended: return (value.status ?? -1) >= 5
        case .mine: return true
        }
    }
}
public enum OfficialEventFilter {
    public static func visible(_ rows: [OfficialEvent], bucket: OfficialEventBucket, keyword: String = "") -> [OfficialEvent] {
        let keyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var seen = Set<Int>()
        return rows.filter { row in
            row.isCompleteRecord && seen.insert(row.id).inserted && bucket.includes(row) &&
                (keyword.isEmpty || [row.title, row.subtitle ?? "", row.city ?? ""].contains { $0.lowercased().contains(keyword) })
        }
    }
}
public struct OfficialPartyInvite: Decodable, Equatable, Identifiable {
    public let id: Int
    public let title: String
    public let partyType: String?
    public let eventTitle: String?
    public let status: String?
    public let city: String?
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: OfficialKey.self)
        id = c.integer("partyId") ?? c.integer("id") ?? 0
        title = c.text("title") ?? c.text("partyName") ?? c.text("responsibilitySummary") ?? ""
        partyType = c.text("partyType"); eventTitle = c.text("eventTitle")
        status = c.text("status"); city = c.text("city") // Never read `state`.
    }
    public var statusKey: String {
        switch status {
        case "INVITED": return "official.invite.invited"
        case "ACCEPTED": return "official.invite.accepted"
        case "ACTIVE": return "official.invite.active"
        default: return "official.status.unknown"
        }
    }
}
public struct OfficialBroadcast: Decodable, Equatable, Identifiable {
    public let id: Int
    public let title: String
    public let content: String?
    public let reach: Int?
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: OfficialKey.self)
        id = c.integer("id") ?? 0; title = c.text("title") ?? ""
        content = c.text("content"); reach = c.integer("reach").flatMap { $0 >= 0 ? $0 : nil }
    }
}
public struct OfficialPublished: Decodable, Equatable {
    public let events: [OfficialEvent]
    public let broadcasts: [OfficialBroadcast]
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: OfficialKey.self)
        events = try c.list("events"); broadcasts = try c.list("broadcasts")
    }
    public var isEmpty: Bool { events.isEmpty && broadcasts.isEmpty }
}
public enum OfficialStatisticValue: Decodable, Equatable {
    case text(String), number(Decimal), flag(Bool), unsupported
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let value = try? c.decode(Bool.self) { self = .flag(value) }
        else if let value = try? c.decode(Decimal.self) { self = .number(value) }
        else if let value = try? c.decode(String.self) { self = .text(value) }
        else { self = .unsupported }
    }
}
public struct OfficialStatistic: Equatable, Identifiable {
    public let id: String
    public let value: OfficialStatisticValue
}
public struct OfficialBroadcastStats: Decodable, Equatable {
    public let rows: [OfficialStatistic]
    public init(from decoder: Decoder) throws {
        let values = try [String: OfficialStatisticValue](from: decoder)
        rows = values.keys.sorted().compactMap { key in
            guard let value = values[key], value != .unsupported else { return nil }
            return OfficialStatistic(id: key, value: value)
        }
    }
}

import Foundation

public enum GrowthBoardMetric: String, CaseIterable, Hashable, Decodable, Identifiable {
    case point, exp
    public var id: String { rawValue }
}
public enum GrowthBoardPeriod: String, CaseIterable, Hashable, Decodable, Identifiable {
    case week, total
    public var id: String { rawValue }
}
public struct GrowthBoardQuery: Hashable {
    public var metric: GrowthBoardMetric
    public var period: GrowthBoardPeriod
    public init(metric: GrowthBoardMetric = .point, period: GrowthBoardPeriod = .total) {
        self.metric = metric; self.period = period
    }
}

/// Unknown values remain nil, never invented zeroes. These are memory-only read projections.
public struct GrowthCenterRecord: Decodable, Equatable {
    public let level: Int?
    public let experience: Int?
    public let points: Int?
    public let badges: [GrowthCenterBadge]
    public let missions: [GrowthCenterMission]
    enum CodingKeys: String, CodingKey { case growth, points, badges, missions }
    enum GrowthKeys: String, CodingKey { case levelNo, expValue }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let growth = try c.nestedContainer(keyedBy: GrowthKeys.self, forKey: .growth)
        level = try growth.growthInteger(.levelNo)
        experience = try growth.growthInteger(.expValue)
        points = try c.growthInteger(.points)
        badges = try c.decode([GrowthCenterBadge].self, forKey: .badges)
        missions = try c.decode([GrowthCenterMission].self, forKey: .missions)
    }
}
public struct GrowthCenterBadge: Decodable, Equatable {
    public let name: String?
    public let code: String?
    public let iconURL: String?
    public let obtainedAt: String?
    public var displayName: String? { GrowthCenterFormatting.nonempty(name) ?? GrowthCenterFormatting.nonempty(code) }
    enum CodingKeys: String, CodingKey { case badgeName, badgeCode, iconUrl, obtainTime }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .badgeName)
        code = try c.decodeIfPresent(String.self, forKey: .badgeCode)
        iconURL = try c.decodeIfPresent(String.self, forKey: .iconUrl)
        obtainedAt = try c.decodeIfPresent(String.self, forKey: .obtainTime)
    }
}
public struct GrowthCenterMission: Decodable, Equatable {
    public let name: String?
    public let description: String?
    public let experienceReward: Int?
    enum CodingKeys: String, CodingKey { case missionName, missionDesc, expReward }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .missionName)
        description = try c.decodeIfPresent(String.self, forKey: .missionDesc)
        experienceReward = try c.growthInteger(.expReward)
    }
}
public struct GrowthPlayProgress: Decodable, Equatable {
    public let level: Int?
    public let totalCheckins: Int?
    public let totalMileage: Double?
    public let streakDays: Int?
    enum CodingKeys: String, CodingKey { case level, totalCheckins, totalMileage, streakDays }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        level = try c.growthInteger(.level)
        totalCheckins = try c.growthInteger(.totalCheckins)
        totalMileage = try c.growthDouble(.totalMileage)
        streakDays = try c.growthInteger(.streakDays)
        guard c.contains(.totalMileage) else { throw APIError.malformedResponse }
    }
}
public struct GrowthCompletedActivity: Decodable, Equatable {
    public let activityID: Int?
    public let topicID: Int?
    public let name: String?
    public let cover: String?
    public let total: Int?
    public let doneCount: Int?
    enum CodingKeys: String, CodingKey { case activityId, topicId, name, cover, total, doneCount }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        activityID = try c.growthInteger(.activityId); topicID = try c.growthInteger(.topicId)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        cover = try c.decodeIfPresent(String.self, forKey: .cover)
        total = try c.growthInteger(.total); doneCount = try c.growthInteger(.doneCount)
        guard c.contains(.topicId) else { throw APIError.malformedResponse }
    }
}
public struct GrowthLeaderboardEntry: Decodable, Equatable {
    public let rank: Int?
    public let memberID: Int?
    public let nickname: String?
    public let avatar: String?
    public let score: Int?
    public let rankPercentage: String?
    enum CodingKeys: String, CodingKey { case rank, memberId, nickname, avatar, score, rankPercentage }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rank = try c.growthInteger(.rank); memberID = try c.growthInteger(.memberId)
        nickname = try c.decodeIfPresent(String.self, forKey: .nickname)
        avatar = try c.decodeIfPresent(String.self, forKey: .avatar)
        score = try c.growthInteger(.score)
        rankPercentage = try c.decodeIfPresent(String.self, forKey: .rankPercentage)
    }
}
public struct GrowthLeaderboard: Decodable, Equatable {
    public let metric: GrowthBoardMetric
    public let period: GrowthBoardPeriod
    public let list: [GrowthLeaderboardEntry]
    public let me: GrowthLeaderboardEntry
}
public enum GrowthCenterSection<Value> {
    case content(Value), failure(GrowthCenterIssue)
    public var value: Value? { if case .content(let value) = self { return value }; return nil }
    public var issue: GrowthCenterIssue? { if case .failure(let issue) = self { return issue }; return nil }
}
public struct GrowthCenterOverview {
    public let center: GrowthCenterSection<GrowthCenterRecord>
    public let progress: GrowthCenterSection<GrowthPlayProgress>
    public let completed: GrowthCenterSection<[GrowthCompletedActivity]>
    public let rank: GrowthCenterSection<GrowthLeaderboard>
    public init(center: GrowthCenterSection<GrowthCenterRecord>, progress: GrowthCenterSection<GrowthPlayProgress>,
                completed: GrowthCenterSection<[GrowthCompletedActivity]>, rank: GrowthCenterSection<GrowthLeaderboard>) {
        self.center = center; self.progress = progress; self.completed = completed; self.rank = rank
    }
    public var completedTopicCount: Int? {
        guard let rows = completed.value else { return nil }
        // topicId=0 is the source's absent-ID sentinel, never an extra completed topic.
        return Set(rows.compactMap(\.topicID).filter { $0 > 0 }).count
    }
}
public enum GrowthCenterReadFailure: Error, Equatable { case rejected(code: Int, message: String?) }
public enum GrowthCenterIssue: Equatable {
    case login, notConfigured, unavailable, network, failed, server(String)
    public init(_ error: Error) {
        switch error {
        case APIError.unauthorized: self = .login
        case APIError.notConfigured: self = .notConfigured
        case APIError.httpStatus: self = .unavailable
        case GrowthCenterReadFailure.rejected(_, let text): self = GrowthCenterFormatting.nonempty(text).map(Self.server) ?? .failed
        case is URLError: self = .network
        default: self = .failed
        }
    }
    public var localizationKey: String {
        switch self {
        case .login: return "growth.signInRequired"
        case .notConfigured: return "growth.notConfigured"
        case .unavailable: return "growth.unavailable"
        case .network: return "growth.network"
        case .failed, .server: return "growth.failed"
        }
    }
}
public enum GrowthCenterFormatting {
    public static func nonempty(_ value: String?) -> String? {
        guard let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }
    public static func nonnegative(_ value: Int?) -> Int? { value.flatMap { $0 >= 0 ? $0 : nil } }
    public static func mileage(_ value: Double?) -> Double? { value.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil } }
    /// Backend wall-clock China time. Validate and display as supplied, with no device-zone shift.
    /// Reject offset-bearing/ambiguous values rather than stripping a zone silently.
    public static func badgeMoment(_ value: String?) -> String? {
        guard let value, value.count == 19 else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
        formatter.dateFormat = value.contains("T") ? "yyyy-MM-dd'T'HH:mm:ss" : "yyyy-MM-dd HH:mm:ss"
        formatter.isLenient = false
        guard let date = formatter.date(from: value), formatter.string(from: date) == value else { return nil }
        return String(value.prefix(16)).replacingOccurrences(of: "T", with: " ")
    }
}
private extension KeyedDecodingContainer {
    func growthInteger(_ key: Key) throws -> Int? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        if let value = try? decode(Int.self, forKey: key) { return value }
        if let string = try? decode(String.self, forKey: key), let value = Int(string.trimmingCharacters(in: .whitespacesAndNewlines)) { return value }
        throw APIError.malformedResponse
    }
    func growthDouble(_ key: Key) throws -> Double? {
        guard contains(key), try !decodeNil(forKey: key) else { return nil }
        if let value = try? decode(Double.self, forKey: key), value.isFinite { return value }
        if let string = try? decode(String.self, forKey: key), let value = Double(string), value.isFinite { return value }
        throw APIError.malformedResponse
    }
}

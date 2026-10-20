import Foundation

/// Mini-program subpackageTools/exploration-goals with utils/features/exploration-goals.js.
/// Progress comes only from the server's completed-session aggregate; the client never counts.
public enum RoamGoalMetric: String, CaseIterable, Identifiable {
    case distinctRoutes = "DISTINCT_ROUTES", explorationDays = "EXPLORATION_DAYS"
    public var id: String { rawValue }
}

public enum RoamGoalState: String, Equatable {
    case active = "ACTIVE", scheduled = "SCHEDULED", ended = "ENDED", achieved = "ACHIEVED", cancelled = "CANCELLED"
    /// Only these can still be cancelled (the server sets CANCELLED one way).
    public var isCancellable: Bool { self == .active || self == .scheduled }
}

public struct RoamExplorationGoal: Equatable, Identifiable {
    public let id: String
    public let requestID: String
    public let metric: RoamGoalMetric
    public let target: Int
    public let startDate: String
    public let endDateExclusive: String
    public let progress: Int
    public let state: RoamGoalState
    public let privateCommemoration: Bool
    public let asOfMs: Int64
    public let createdAtMs: Int64
    /// Whole percent capped at 100, as the mini-program bar.
    public var percent: Int { target > 0 ? min(100, Int((Double(progress) / Double(target) * 100).rounded())) : 0 }

    struct Raw: Decodable {
        let id: String; let requestId: String; let metric: String; let target: Int
        let startDate: String; let endDateExclusive: String; let progress: Int64; let state: String
        let privateCommemoration: Bool; let timeZone: String; let countingVersion: String
        let asOfMs: Int64; let createdAtMs: Int64
    }
    /// The client's strict `goal()` projection: any mismatch is "目标响应未确认", never shown partially.
    static func project(_ raw: Raw, confirmedCancelled: Set<String> = []) throws -> RoamExplorationGoal {
        guard RoamPrivateRequestID.isCanonicalID(raw.id), RoamPrivateRequestID.isValid(raw.requestId),
              let metric = RoamGoalMetric(rawValue: raw.metric), (1...100).contains(raw.target),
              let start = RoamShanghaiCalendar.parseDate(raw.startDate), let end = RoamShanghaiCalendar.parseDate(raw.endDateExclusive), start < end,
              raw.progress >= 0, raw.progress <= Int64(Int32.max), let state = RoamGoalState(rawValue: raw.state),
              raw.privateCommemoration == (state == .achieved), state != .achieved || raw.progress >= Int64(raw.target),
              raw.timeZone == "Asia/Shanghai", raw.countingVersion == "COMPLETED_SESSION_AGGREGATE_V1" else { throw APIError.malformedResponse }
        // Cancellation is monotonic: a late create/receipt response never revives a confirmed cancellation.
        let cancelled = confirmedCancelled.contains(raw.id)
        return .init(id: raw.id, requestID: raw.requestId, metric: metric, target: raw.target, startDate: raw.startDate,
                     endDateExclusive: raw.endDateExclusive, progress: Int(raw.progress), state: cancelled ? .cancelled : state,
                     privateCommemoration: cancelled ? false : raw.privateCommemoration, asOfMs: raw.asOfMs, createdAtMs: raw.createdAtMs)
    }
    static func decode(_ envelope: RoamPrivateEnvelope, confirmedCancelled: Set<String> = []) throws -> RoamExplorationGoal {
        try project(envelope.payload(Raw.self), confirmedCancelled: confirmedCancelled)
    }
    func matches(_ draft: RoamGoalDraft) -> Bool {
        requestID == draft.requestID && metric == draft.metric && target == draft.target && startDate == draft.startDate && endDateExclusive == draft.endDateExclusive
    }
}

public struct RoamGoalPage: Equatable {
    public static let limit = 20
    public let items: [RoamExplorationGoal]
    public let hasMore: Bool
    public let nextBeforeID: String?
    static func decode(_ envelope: RoamPrivateEnvelope, confirmedCancelled: Set<String> = []) throws -> RoamGoalPage {
        struct Raw: Decodable { let items: [RoamExplorationGoal.Raw]; let hasMore: Bool; let nextBeforeId: String? }
        let value = try envelope.payload(Raw.self)
        guard value.items.count <= limit else { throw APIError.malformedResponse }
        if value.hasMore {
            guard let next = value.nextBeforeId, RoamPrivateRequestID.isCanonicalID(next), !value.items.isEmpty else { throw APIError.malformedResponse }
        } else { guard value.nextBeforeId == nil else { throw APIError.malformedResponse } }
        let items = try value.items.map { try RoamExplorationGoal.project($0, confirmedCancelled: confirmedCancelled) }
        guard Set(items.map(\.id)).count == items.count, !value.hasMore || value.nextBeforeId == items.last?.id else { throw APIError.malformedResponse }
        return .init(items: items, hasMore: value.hasMore, nextBeforeID: value.nextBeforeId)
    }
}

public struct RoamGoalDraft: Equatable {
    public let requestID: String
    public let metric: RoamGoalMetric
    public let target: Int
    public let startDate: String
    public let endDateExclusive: String
    public init(requestID: String = RoamPrivateRequestID.make(), metric: RoamGoalMetric, target: Int, startDate: String, endDateExclusive: String) {
        self.requestID = requestID; self.metric = metric; self.target = target; self.startDate = startDate; self.endDateExclusive = endDateExclusive
    }
    /// The server only accepts a start of today or later; target 1–100; end strictly after start.
    public func validate(now: Date) throws {
        guard RoamPrivateRequestID.isValid(requestID), (1...100).contains(target),
              let start = RoamShanghaiCalendar.parseDate(startDate), let end = RoamShanghaiCalendar.parseDate(endDateExclusive),
              start < end, start >= RoamShanghaiCalendar.dayNumber(now: now) else { throw RoamPrivateWriteError.invalidDraft }
    }
    var json: Data {
        Data(RoamOrderedJSON.Value.object([("requestId", .string(requestID)), ("metric", .string(metric.rawValue)), ("target", .int(Int64(target))),
                                           ("startDate", .string(startDate)), ("endDateExclusive", .string(endDateExclusive))]).text.utf8)
    }
}

/// 本周 / 本月 / 30 天 presets. Week and month start from today because the server refuses past start days.
public struct RoamGoalPeriod: Equatable, Identifiable {
    public enum Kind: Int, CaseIterable { case week, month, thirtyDays }
    public let kind: Kind
    public let startDate: String
    public let endDateExclusive: String
    public var id: Int { kind.rawValue }
    public static func periods(now: Date) -> [RoamGoalPeriod] {
        let today = RoamShanghaiCalendar.dayNumber(now: now)
        let monday = today - RoamShanghaiCalendar.mondayIndex(dayNumber: today)
        let civil = RoamShanghaiCalendar.civil(dayNumber: today)
        let first = RoamShanghaiCalendar.dayNumber(year: civil.year, month: civil.month, day: 1)
        let nextFirst = civil.month == 12 ? RoamShanghaiCalendar.dayNumber(year: civil.year + 1, month: 1, day: 1)
            : RoamShanghaiCalendar.dayNumber(year: civil.year, month: civil.month + 1, day: 1)
        let ranges: [(Kind, Int64, Int64)] = [(.week, max(monday, today), monday + 7), (.month, max(first, today), nextFirst), (.thirtyDays, today, today + 30)]
        return ranges.map { .init(kind: $0.0, startDate: RoamShanghaiCalendar.dateText(dayNumber: $0.1), endDateExclusive: RoamShanghaiCalendar.dateText(dayNumber: $0.2)) }
    }
}

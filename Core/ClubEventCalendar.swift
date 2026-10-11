import Foundation

/// P045 uses the written date prefix of startDate, not the device's conversion of
/// a timestamp. This matches dateOf(startDate) and club-event-calendar.js.
public struct ClubEventDay: Hashable, Comparable, Identifiable {
    public let year: Int
    public let month: Int
    public let day: Int
    public var id: String { String(format: "%04d-%02d-%02d", year, month, day) }
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
    public init?(source: String) {
        let prefix = String(source.prefix(10))
        let parts = prefix.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              parts.allSatisfy({ $0.allSatisfy({ $0.isASCII && $0.isNumber }) }),
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (100...9999).contains(year), let date = Self.calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
        let actual = Self.calendar.dateComponents([.year, .month, .day], from: date)
        guard actual.year == year, actual.month == month, actual.day == day else { return nil }
        self.year = year; self.month = month; self.day = day
    }
    init(date: Date) {
        let parts = Self.calendar.dateComponents([.year, .month, .day], from: date)
        year = parts.year!; month = parts.month!; day = parts.day!
    }
    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }
}

public struct ClubEventMonth: Hashable {
    public let year: Int
    public let month: Int
    public var key: String { String(format: "%04d-%02d", year, month) }
    public init?(year: Int, month: Int) {
        guard (1970...9999).contains(year), (1...12).contains(month) else { return nil }
        self.year = year; self.month = month
    }
    public init(now: Date = Date(), timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month], from: now)
        year = min(9999, max(1970, parts.year ?? 1970)); month = parts.month ?? 1
    }
    public func shifted(by delta: Int) -> Self? {
        // Only the source's previous/next controls are exposed. Bound arithmetic
        // before adding an arbitrary caller-provided offset.
        guard (-120_000...120_000).contains(delta) else { return nil }
        let ordinal = year * 12 + month - 1 + delta
        return Self(year: ordinal / 12, month: ordinal % 12 + 1)
    }
    public func contains(_ day: ClubEventDay) -> Bool { day.year == year && day.month == month }
    public func cells(events: [ClubCalendarEvent]) -> [ClubEventCalendarCell] {
        let calendar = ClubEventDay.calendar
        guard let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)) else { return [] }
        let mondayOffset = (calendar.component(.weekday, from: first) + 5) % 7
        return (0..<42).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset - mondayOffset, to: first) else { return nil }
            let day = ClubEventDay(date: date)
            return .init(day: day, inMonth: contains(day), events: events.filter { $0.startDay == day })
        }
    }
}

public struct ClubCalendarEvent: Equatable, Identifiable {
    public let id: Int
    public let name: String?
    public let startDay: ClubEventDay?
    public init(id: Int, name: String?, startDay: ClubEventDay?) {
        self.id = id; self.name = name; self.startDay = startDay
    }
}
public struct ClubEventCalendarCell: Equatable, Identifiable {
    public let day: ClubEventDay
    public let inMonth: Bool
    public let events: [ClubCalendarEvent]
    public var id: String { day.id }
}

/// Calendar rows remain projections of one exact authorized topic-list response.
/// A date never grants access, creates an occurrence or invents a schedule.
public struct ClubEventCalendarSnapshot: Equatable {
    public let clubID: Int
    public let events: [ClubCalendarEvent]
    public init(snapshot: ClubGovernanceSnapshot, context: ClubGovernanceReadContext) throws {
        guard context.operation == .topics, context.accepts(snapshot),
              (context.identity?.accountID ?? 0) > 0, let clubID = context.scope.clubID, clubID > 0,
              snapshot.permissions?.allows(nil, scope: context.scope) == true,
              let rows = snapshot.value.array else { throw ClubGovernanceFailure.targetChanged }
        var events: [ClubCalendarEvent] = [], ids = Set<Int>()
        for row in rows {
            guard row.object != nil, let id = ClubCustomerHistoryTopicRoute.positiveID(row["id"]),
                  ids.insert(id).inserted,
                  row["clubId"] == .null || ClubCustomerHistoryTopicRoute.positiveID(row["clubId"]) == clubID else {
                throw ClubGovernanceFailure.malformed
            }
            let name = row["name"].string?.trimmingCharacters(in: .whitespacesAndNewlines)
            events.append(.init(id: id, name: name?.isEmpty == false ? name : nil,
                                startDay: row["startDate"].string.flatMap(ClubEventDay.init(source:))))
        }
        self.clubID = clubID; self.events = events
    }
    public var undated: [ClubCalendarEvent] { events.filter { $0.startDay == nil } }
}

public struct ClubEventTopicRoute: Hashable, Identifiable {
    public let id = UUID()
    public let topicID: Int
    public let context: ClubGovernanceReadContext
    public let snapshotGeneration: UInt64
    public init?(topicID: Int, snapshot: ClubEventCalendarSnapshot, context: ClubGovernanceReadContext, snapshotGeneration: UInt64) {
        guard context.operation == .topics, context.scope.clubID == snapshot.clubID,
              (context.identity?.accountID ?? 0) > 0,
              snapshot.events.filter({ $0.id == topicID }).count == 1 else { return nil }
        self.topicID = topicID; self.context = context; self.snapshotGeneration = snapshotGeneration
    }
    public func isCurrent(snapshot: ClubEventCalendarSnapshot?, context: ClubGovernanceReadContext, snapshotGeneration: UInt64) -> Bool {
        self.context == context && self.snapshotGeneration == snapshotGeneration && snapshot?.clubID == context.scope.clubID &&
        snapshot?.events.filter({ $0.id == topicID }).count == 1
    }
}

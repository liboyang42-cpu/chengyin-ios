import Foundation

public struct ClubSeriesOccurrenceRow: Equatable, Identifiable {
    /// Display identity within one response, never sent as an activity/occurrence ID.
    public let id: Int
    public let occurrenceID: Int?
    public let activityID: Int?
    public let dateText: String?
    public let dateIsParsed: Bool
    public let cancelled: Bool
    public let editable: Bool?
    public let lockReason: String?
    public let signupCount: Int?
    public let refundedCount: Int?
}
public struct ClubSeriesOccurrencePresentation: Equatable {
    public let scope: ClubGovernanceScope
    public let rows: [ClubSeriesOccurrenceRow]
    private let context: ClubGovernanceReadContext
    public init(snapshot: ClubGovernanceSnapshot, context: ClubGovernanceReadContext) throws {
        try context.scope.validate()
        guard context.operation == .occurrences, context.accepts(snapshot),
              (context.scope.clubID ?? 0) > 0, (context.scope.seriesID ?? 0) > 0,
              (context.identity?.accountID ?? 0) > 0 else { throw ClubGovernanceFailure.targetChanged }
        guard snapshot.permissions?.allows(ClubGovernanceRead.occurrences.permission, scope: context.scope) == true else { throw ClubGovernanceFailure.forbidden }
        guard let source = snapshot.value.array else { throw ClubGovernanceFailure.malformed }
        var rows: [ClubSeriesOccurrenceRow] = [], occurrenceIDs = Set<Int>()
        for (index, value) in source.enumerated() {
            guard value.object != nil else { throw ClubGovernanceFailure.malformed }
            for (key, expected) in [("clubId", context.scope.clubID), ("seriesId", context.scope.seriesID), ("topicId", context.scope.topicID)] {
                if value[key] != .null, let expected {
                    guard ClubCustomerHistoryTopicRoute.positiveID(value[key]) == expected else { throw ClubGovernanceFailure.targetChanged }
                }
            }
            let occurrence = try Self.optionalID(value["occurrenceId"]), activity = try Self.optionalID(value["activityId"])
            if let occurrence { guard occurrenceIDs.insert(occurrence).inserted else { throw ClubGovernanceFailure.malformed } }
            let rawDate = value["occurrenceAt"], parsed = ClubOccurrenceClock.display(rawDate)
            let rawText = Self.nonempty(rawDate.text)
            rows.append(.init(id: index, occurrenceID: occurrence, activityID: activity, dateText: parsed ?? rawText,
                              dateIsParsed: parsed != nil, cancelled: value["status"] == .string("CANCELLED"), editable: value["editable"].bool,
                              lockReason: Self.nonempty(value["lockReason"].string), signupCount: try Self.count(value["signupCount"]),
                              refundedCount: try Self.count(value["refundedCount"])))
        }
        scope = context.scope; self.rows = rows; self.context = context
    }
    private static func nonempty(_ raw: String?) -> String? { guard let raw else { return nil }; let value = raw.trimmingCharacters(in: .whitespacesAndNewlines); return value.isEmpty ? nil : value }
    private static func optionalID(_ value: ClubGovernanceValue) throws -> Int? {
        if value == .null { return nil }; guard let id = ClubCustomerHistoryTopicRoute.positiveID(value) else { throw ClubGovernanceFailure.malformed }; return id
    }
    private static func count(_ value: ClubGovernanceValue) throws -> Int? {
        if value == .null { return nil }; guard let number = value.int, number >= 0 else { throw ClubGovernanceFailure.malformed }; return number
    }
    public func route(rowID: Int, context: ClubGovernanceReadContext, snapshotID: UUID) -> ClubSeriesOccurrenceRoute? {
        guard self.context == context, let row = rows.first(where: { $0.id == rowID }), let activityID = row.activityID else { return nil }
        return .init(scope: .init(clubID: scope.clubID, topicID: scope.topicID, activityID: activityID), row: row, context: context, snapshotID: snapshotID)
    }
}
public struct ClubSeriesOccurrenceRoute: Identifiable, Equatable {
    public let id = UUID()
    public let scope: ClubGovernanceScope
    private let row: ClubSeriesOccurrenceRow
    private let context: ClubGovernanceReadContext
    private let snapshotID: UUID
    fileprivate init(scope: ClubGovernanceScope, row: ClubSeriesOccurrenceRow, context: ClubGovernanceReadContext, snapshotID: UUID) {
        self.scope = scope; self.row = row; self.context = context; self.snapshotID = snapshotID
    }
    public func isCurrent(presentation: ClubSeriesOccurrencePresentation?, context: ClubGovernanceReadContext, snapshotID: UUID) -> Bool {
        self.context == context && self.snapshotID == snapshotID && presentation?.scope == context.scope && presentation?.rows.contains(row) == true
    }
}

/// Mini utils/datetime.js uses a fixed +08:00 display clock, not the device zone.
public enum ClubOccurrenceClock {
    public static func display(_ value: ClubGovernanceValue) -> String? {
        guard let date = date(value) else { return nil }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian); formatter.timeZone = TimeZone(secondsFromGMT: 8 * 3600)
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let text = formatter.string(from: date); return text.isEmpty ? nil : text
    }
    /// The same parse as `display`, for callers that format the instant themselves.
    public static func instant(_ value: ClubGovernanceValue) -> Date? { date(value) }
    private static func date(_ value: ClubGovernanceValue) -> Date? {
        switch value {
        case .integer(let number): return epoch(Double(number), numeric: true)
        case .decimal(let number): return epoch(number, numeric: true)
        case .string(let raw):
            let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.range(of: "^[0-9]{10}$", options: .regularExpression) != nil, let number = Double(text) { return epoch(number * 1000, numeric: false) }
            if text.range(of: "^[0-9]{13}$", options: .regularExpression) != nil, let number = Double(text) { return epoch(number, numeric: false) }
            let offsetPattern = "^([0-9]{4})-([0-9]{2})-([0-9]{2})[T ]([0-9]{2}):([0-9]{2})(?::([0-9]{2})(?:\\.[0-9]{1,9})?)?(Z|[+-][0-9]{2}:?[0-9]{2})$"
            if let parts = groups(text, pattern: offsetPattern) {
                let zone = parts[7].uppercased(), seconds: Int
                if zone == "Z" { seconds = 0 }
                else {
                    let digits = zone.dropFirst().replacingOccurrences(of: ":", with: "")
                    guard let hours = Int(digits.prefix(2)), let minutes = Int(digits.suffix(2)), hours < 24, minutes < 60 else { return nil }
                    seconds = (zone.hasPrefix("-") ? -1 : 1) * (hours * 3600 + minutes * 60)
                }
                return wall(parts, offset: seconds)
            }
            let wallPattern = "^([0-9]{4})[-/]([0-9]{1,2})[-/]([0-9]{1,2})(?:[ T]([0-9]{1,2}):([0-9]{1,2})(?::([0-9]{1,2})(?:\\.[0-9]{1,9})?)?)?$"
            return groups(text, pattern: wallPattern).flatMap { wall($0, offset: 8 * 3600) }
        default: return nil
        }
    }
    private static func epoch(_ raw: Double, numeric: Bool) -> Date? {
        guard raw.isFinite, !numeric || raw != 0 else { return nil }
        let ms = numeric && raw.rounded(.towardZero) == raw && raw >= 1_000_000_000 && raw < 10_000_000_000 ? raw * 1000 : raw
        guard abs(ms) <= 8.64e15 else { return nil }; return Date(timeIntervalSince1970: ms / 1000)
    }
    private static func groups(_ text: String, pattern: String) -> [String]? {
        guard let expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.range.length == text.utf16.count else { return nil }
        return (0..<match.numberOfRanges).map { index in Range(match.range(at: index), in: text).map { String(text[$0]) } ?? "" }
    }
    private static func wall(_ parts: [String], offset: Int) -> Date? {
        guard parts.count >= 7, let year = Int(parts[1]), let month = Int(parts[2]), let day = Int(parts[3]), (1...9999).contains(year) else { return nil }
        let hour = Int(parts[4]) ?? 0, minute = Int(parts[5]) ?? 0, second = Int(parts[6]) ?? 0
        guard (0...23).contains(hour), (0...59).contains(minute), (0...59).contains(second) else { return nil }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)) else { return nil }
        let actual = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        guard actual.year == year, actual.month == month, actual.day == day, actual.hour == hour, actual.minute == minute, actual.second == second else { return nil }
        return date.addingTimeInterval(TimeInterval(-offset))
    }
}

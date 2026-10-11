import Foundation

/// Comparison parser for the verified Mini datetime contract: bare server strings
/// mean China time; explicit ISO offsets retain their instant. Device zone is unused.
public enum ClubActivitySourceTime {
    public static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if [10, 13].contains(text.count), text.allSatisfy({ $0.isASCII && $0.isNumber }), let number = Double(text) {
            return Date(timeIntervalSince1970: text.count == 10 ? number : number / 1000)
        }
        let bare = #"^(\d{4})[-/](\d{1,2})[-/](\d{1,2})(?:[ T](\d{1,2}):(\d{1,2})(?::(\d{1,2})(?:\.\d{1,9})?)?)?$"#
        let offset = #"^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::(\d{2})(?:\.(\d{1,9}))?)?([Zz]|[+-]\d{2}:?\d{2})$"#
        if let parts = groups(text, pattern: bare) { return calendarDate(parts, offset: 8 * 3600, milliseconds: 0) }
        guard let parts = groups(text, pattern: offset), let zone = parts.last else { return nil }
        var seconds = 0
        if zone.uppercased() != "Z" {
            let digits = zone.dropFirst().replacingOccurrences(of: ":", with: "")
            guard digits.count == 4, let hours = Int(digits.prefix(2)), let minutes = Int(digits.suffix(2)), hours <= 23, minutes <= 59 else { return nil }
            seconds = (hours * 3600 + minutes * 60) * (zone.first == "-" ? -1 : 1)
        }
        let fraction = parts[6]
        let milliseconds = Int((String(fraction.prefix(3)) + "000").prefix(3)) ?? 0
        return calendarDate(parts, offset: seconds, milliseconds: milliseconds)
    }
    private static func groups(_ text: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<match.numberOfRanges).map { index in
            guard let range = Range(match.range(at: index), in: text) else { return "" }
            return String(text[range])
        }
    }
    private static func calendarDate(_ parts: [String], offset: Int, milliseconds: Int) -> Date? {
        guard parts.count >= 6, let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (0...9999).contains(year), (1...12).contains(month), (1...31).contains(day) else { return nil }
        let hour = Int(parts[3]) ?? 0, minute = Int(parts[4]) ?? 0, second = Int(parts[5]) ?? 0
        guard (0...23).contains(hour), (0...59).contains(minute), (0...59).contains(second) else { return nil }
        let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
        let monthDays = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        guard day <= monthDays[month - 1] else { return nil }
        // Proleptic Gregorian arithmetic also handles source year 0000 without
        // Foundation calendar cutover, locale, era or daylight-saving assumptions.
        let y = year - (month <= 2 ? 1 : 0)
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let monthOfYear = month + (month > 2 ? -3 : 9)
        let dayOfYear = (153 * monthOfYear + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        let days = era * 146097 + dayOfEra - 719468
        let seconds = Double(days) * 86400 + Double(hour * 3600 + minute * 60 + second - offset)
        return Date(timeIntervalSince1970: seconds + Double(milliseconds) / 1000)
    }
}

public struct ClubActivityRow: Equatable, Identifiable {
    public enum Status: String, Equatable { case recruiting, live, ended }
    public enum Category: String, Equatable { case orientation, exploration }
    public let id: Int
    public let name: String?
    public let cover: String?
    public let address: String?
    public let sourceStart: String?
    public let start: Date?
    public let dateOnly: Bool
    public let status: Status
    public let category: Category
    public let signups: Double?
    public let stations: Double?
    public let mileageKM: Double?
    init(value: ClubGovernanceValue, id: Int, now: Date) {
        self.id = id
        name = Self.text(value["name"]); cover = Self.text(value["imgUrl"]); address = Self.text(value["addressName"])
        sourceStart = Self.text(value["startDate"]); start = ClubActivitySourceTime.date(sourceStart)
        dateOnly = sourceStart?.range(of: #"^\d{4}[-/]\d{1,2}[-/]\d{1,2}$"#, options: .regularExpression) != nil
        let end = ClubActivitySourceTime.date(Self.text(value["endDate"]))
        // Mini end is strict (< now), whereas the start boundary is inclusive.
        if let end, end.timeIntervalSince1970 > 0, end < now { status = .ended }
        else if let start, start.timeIntervalSince1970 != 0, start <= now { status = .live }
        else { status = .recruiting }
        let product = value["productType"] == .null ? value["mode"] : value["productType"]
        category = Self.number(product) == 2 ? .exploration : .orientation
        signups = Self.positive(value["signupCount"]); stations = Self.positive(value["locationCount"])
        if let distance = Self.positive(value["totalMileage"]), (distance * 10).isFinite {
            mileageKM = (distance * 10).rounded(.toNearestOrAwayFromZero) / 10
        } else { mileageKM = nil }
    }
    private static func text(_ value: ClubGovernanceValue) -> String? {
        guard let raw = value.text?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }; return raw
    }
    private static func number(_ value: ClubGovernanceValue) -> Double? {
        let number = value.number ?? value.string.flatMap { Double($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        guard let number, number.isFinite else { return nil }; return number
    }
    private static func positive(_ value: ClubGovernanceValue) -> Double? {
        guard let value = number(value), value > 0 else { return nil }; return value
    }
}

/// List and calendar projections are atomically derived from one authorized response.
public struct ClubActivityOverview: Equatable {
    public let calendar: ClubEventCalendarSnapshot
    public let rows: [ClubActivityRow]
    public let observedAt: Date
    public init(snapshot: ClubGovernanceSnapshot, context: ClubGovernanceReadContext, now: Date) throws {
        calendar = try ClubEventCalendarSnapshot(snapshot: snapshot, context: context)
        guard let source = snapshot.value.array, source.count == calendar.events.count else { throw ClubGovernanceFailure.malformed }
        rows = zip(source, calendar.events).map { ClubActivityRow(value: $0.0, id: $0.1.id, now: now) }
        observedAt = now
    }
    public var current: [ClubActivityRow] { rows.filter { $0.status != .ended } }
    public var ended: [ClubActivityRow] { rows.filter { $0.status == .ended } }
}

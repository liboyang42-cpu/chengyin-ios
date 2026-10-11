import Foundation

/// A local copy of the five scheduling fields. It never creates an occurrence or grants write authority.
public struct ClubSeriesScheduleDraft: Equatable {
    public enum Recurrence: String, CaseIterable { case once = "ONCE", weekly = "WEEKLY", custom = "CUSTOM_DATES" }
    public enum Issue: String { case recurrence, date, time, count, past
        public var localizationKey: String { "club.schedule.error." + rawValue }
    }
    public struct CustomDate: Identifiable, Equatable {
        public let id: UUID
        public var day: String
        public init(day: String) { id = UUID(); self.day = day }
    }
    public static let fieldKeys: Set<String> = ["recurrenceType", "startDate", "startTime", "occurrenceCount", "customDates"]
    public var recurrence: String
    public var startDate: String
    public var startTime: String
    public var occurrenceCount: Int
    public var customDates: [CustomDate]

    public init(form: ClubGovernanceFormDraft, now: Date) {
        recurrence = form.text["recurrenceType"] ?? "ONCE"
        let raw = form.text["customDates"] ?? ""
        let dates = raw.isEmpty ? [] : raw.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let unedited = (form.text["startDate"] ?? "").isEmpty
        // Existing seriesDetail provides dates only; 09:00 is the Mini's explicit new-date default.
        startDate = unedited ? (dates.sorted().first ?? Self.day(now)) : (form.text["startDate"] ?? "")
        startTime = form.text["startTime"] ?? "09:00"
        occurrenceCount = unedited && !dates.isEmpty ? dates.count : (Int(form.text["occurrenceCount"] ?? "") ?? 0)
        customDates = (dates.isEmpty ? [startDate] : dates).map { CustomDate(day: $0) }
    }
    public mutating func addDate() {
        guard customDates.count < 64 else { return }
        customDates.append(.init(day: startDate))
    }
    public mutating func removeDate(id: UUID) {
        guard customDates.count > 1 else { return }
        customDates.removeAll { $0.id == id }
    }
    public var uniqueCustomDates: [String] { Array(Set(customDates.map(\.day))).sorted() }
    /// Requested dates only. Server materialization, 90-day horizon and locked occurrences remain authoritative.
    public var requestedDates: [String] {
        guard let kind = Recurrence(rawValue: recurrence) else { return [] }
        if kind == .custom { return uniqueCustomDates }
        guard let start = Self.parseDay(startDate) else { return [] }
        if kind == .once { return [startDate] }
        guard (1...64).contains(occurrenceCount) else { return [] }
        return (0..<occurrenceCount).compactMap { index in
            Self.calendar.date(byAdding: .day, value: index * 7, to: start).map(Self.day)
        }
    }
    public func issue(now: Date) -> Issue? {
        guard let kind = Recurrence(rawValue: recurrence) else { return .recurrence }
        guard Self.parseTime(startTime) != nil else { return .time }
        if kind == .weekly && !(1...64).contains(occurrenceCount) { return .count }
        if kind == .custom && !(1...64).contains(customDates.count) { return .count }
        let days = requestedDates
        guard !days.isEmpty, days.allSatisfy({ Self.parseDay($0) != nil }) else { return .date }
        let today = Self.day(now)
        guard days.allSatisfy({ $0 >= today }) else { return .past }
        // Minute equality is already past, matching Mini assemblyAlreadyPast.
        if days.contains(today), startTime <= Self.time(now) { return .past }
        return nil
    }
    public func applying(to form: ClubGovernanceFormDraft, now: Date) throws -> ClubGovernanceFormDraft {
        guard [.createSeries, .updateSeries].contains(form.operation), issue(now: now) == nil else { throw ClubGovernanceFailure.invalidRequest }
        var result = form
        let custom = recurrence == Recurrence.custom.rawValue
        result.text["recurrenceType"] = recurrence
        result.text["startDate"] = custom ? uniqueCustomDates[0] : startDate
        result.text["startTime"] = startTime
        result.text["occurrenceCount"] = String(recurrence == Recurrence.once.rawValue ? 1 : custom ? uniqueCustomDates.count : occurrenceCount)
        result.text["customDates"] = uniqueCustomDates.joined(separator: ",")
        return result
    }
    public static var timeZone: TimeZone { TimeZone(identifier: "Asia/Shanghai")! }
    public static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian); value.timeZone = timeZone; value.locale = Locale(identifier: "en_US_POSIX"); return value
    }
    public static func day(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
    public static func time(_ date: Date) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
    public static func parseDay(_ value: String) -> Date? {
        guard value.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$", options: .regularExpression) != nil else { return nil }
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, parts[0] > 0,
              let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)), day(date) == value else { return nil }
        return date
    }
    public static func parseTime(_ value: String) -> Date? {
        guard value.range(of: "^([01][0-9]|2[0-3]):[0-5][0-9]$", options: .regularExpression) != nil else { return nil }
        let parts = value.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, let date = calendar.date(from: DateComponents(year: 2000, month: 1, day: 1, hour: parts[0], minute: parts[1])), time(date) == value else { return nil }
        return date
    }
}

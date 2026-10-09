import Foundation

/// A single service date and two wall-clock times, matching the source time-range
/// control. These are civil strings, not instants in a guessed service timezone.
public struct MerchantStationServiceWindow: Equatable {
    public var day: String
    public var startMinutes: Int
    public var endMinutes: Int
    public init(day: String, startMinutes: Int = 0, endMinutes: Int = 0) {
        self.day = day; self.startMinutes = startMinutes; self.endMinutes = endMinutes
    }
    public init?(start: String, end: String) {
        guard MerchantStationCommand.validTime(start), MerchantStationCommand.validTime(end),
              start.prefix(10) == end.prefix(10) else { return nil }
        func minutes(_ value: String) -> Int {
            let clock = value.suffix(5).split(separator: ":").compactMap { Int($0) }
            return clock[0] * 60 + clock[1]
        }
        self.init(day: String(start.prefix(10)), startMinutes: minutes(start), endMinutes: minutes(end))
        guard isValid else { return nil }
    }
    public var isValid: Bool {
        MerchantStationCommand.validTime(day + " 00:00") && (0..<1440).contains(startMinutes) &&
        (0..<1440).contains(endMinutes) && startMinutes < endMinutes
    }
    public func wireValues() throws -> (start: String, end: String) {
        guard isValid else { throw MerchantContentFailure.invalid }
        return (day + " " + MerchantStoreHours.clock(startMinutes), day + " " + MerchantStoreHours.clock(endMinutes))
    }
    /// Five-minute choices for new edits; preserve an existing off-step minute
    /// until the user explicitly changes it rather than silently rounding it.
    public static func minuteChoices(preserving minute: Int) -> [Int] {
        var choices = Array(stride(from: 0, to: 60, by: 5))
        if (0..<60).contains(minute), !choices.contains(minute) { choices.append(minute); choices.sort() }
        return choices
    }
    /// Fixed-zone Date is only the native calendar control's carrier. Reading and
    /// writing its calendar components never converts the source service times.
    public static var pickerCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
    public var pickerDate: Date? {
        guard MerchantStationCommand.validTime(day + " 00:00") else { return nil }
        let pieces = day.split(separator: "-").compactMap { Int($0) }
        return Self.pickerCalendar.date(from: DateComponents(year: pieces[0], month: pieces[1], day: pieces[2], hour: 12))
    }
    public mutating func selectPickerDate(_ value: Date) {
        let parts = Self.pickerCalendar.dateComponents([.year, .month, .day], from: value)
        day = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
    /// Initial proposal only when no representable source pair exists. It is never
    /// applied automatically and does not establish the store's operating timezone.
    public static func proposedDay(now: Date, phoneTimeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = phoneTimeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

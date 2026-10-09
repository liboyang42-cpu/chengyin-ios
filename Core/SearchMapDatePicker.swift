import Foundation

public enum SearchMapDatePickerField: String { case start, end }

/// A nested, disposable wheel draft. Only Confirm copies its date into the filter
/// draft; the containing filter's Apply remains the sole query commit point.
public struct SearchMapDatePickerDraft: Equatable, Identifiable {
    public static let years = 1970...2050
    public let field: SearchMapDatePickerField
    public private(set) var year: Int
    public private(set) var month: Int
    public private(set) var day: Int
    public var id: String { field.rawValue }
    public var days: ClosedRange<Int> { 1...Self.dayCount(year: year, month: month) }

    public init(field: SearchMapDatePickerField, draft: SearchMapDateFilterDraft,
                now: Date = Date(), timeZone: TimeZone = .current) {
        self.field = field
        let current = Self.components(field == .start ? draft.startDate : draft.endDate)
        let fallback = field == .end ? Self.components(draft.startDate) : nil
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let today = calendar.dateComponents([.era, .year, .month, .day], from: now)
        let source = current ?? fallback ?? (
            year: today.era == 1 ? (today.year ?? 1970) : 1970,
            month: today.month ?? 1, day: today.day ?? 1)
        year = min(Self.years.upperBound, max(Self.years.lowerBound, source.year))
        month = min(12, max(1, source.month))
        day = min(Self.dayCount(year: year, month: month), max(1, source.day))
    }

    /// ASCII Gregorian components, never converted to UTC or to a timestamp.
    /// In particular a civil date stays selectable even if a phone time zone
    /// skipped that local day, such as Pacific/Apia on 2011-12-30.
    public var value: String { Self.format(year: year, month: month, day: day) }

    public mutating func selectYear(_ value: Int) {
        year = min(Self.years.upperBound, max(Self.years.lowerBound, value))
        day = min(day, days.upperBound)
    }

    public mutating func selectMonth(_ value: Int) {
        month = min(12, max(1, value))
        day = min(day, days.upperBound)
    }

    public mutating func selectDay(_ value: Int) { day = min(days.upperBound, max(1, value)) }

    /// Check the other valid bound before changing anything. An invalid manual
    /// bound remains visible for correction and is rejected by the existing Apply.
    public func confirming(in draft: SearchMapDateFilterDraft) throws -> SearchMapDateFilterDraft {
        let otherText = field == .start ? draft.endDate : draft.startDate
        if let other = Self.components(otherText) {
            let otherValue = Self.format(year: other.year, month: other.month, day: other.day)
            if (field == .start && value > otherValue) || (field == .end && value < otherValue) {
                throw APIError.invalidRequest
            }
        }
        var result = draft
        if field == .start { result.startDate = value } else { result.endDate = value }
        return result
    }

    private static func dayCount(year: Int, month: Int) -> Int {
        if month == 2 { return year.isMultiple(of: 400) || (year.isMultiple(of: 4) && !year.isMultiple(of: 100)) ? 29 : 28 }
        return [4, 6, 9, 11].contains(month) ? 30 : 31
    }

    private static func format(year: Int, month: Int, day: Int) -> String {
        func padded(_ value: Int, width: Int) -> String {
            let digits = String(value)
            return String(repeating: "0", count: max(0, width - digits.count)) + digits
        }
        return padded(year, width: 4) + "-" + padded(month, width: 2) + "-" + padded(day, width: 2)
    }

    private static func components(_ text: String) -> (year: Int, month: Int, day: Int)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let bytes = Array(trimmed.utf8)
        guard bytes.count == 10, bytes[4] == 45, bytes[7] == 45,
              bytes.enumerated().allSatisfy({ $0.offset == 4 || $0.offset == 7 || (48...57).contains($0.element) }) else { return nil }
        let parts = trimmed.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...9999).contains(parts[0]), (1...12).contains(parts[1]),
              (1...dayCount(year: parts[0], month: parts[1])).contains(parts[2]) else { return nil }
        return (year: parts[0], month: parts[1], day: parts[2])
    }
}

import Foundation

/// Date-only local filter draft. Server date boundaries are never converted into client timestamps.
public struct MerchantCRMDateRange: Equatable {
    public enum Field: Equatable { case start, end }
    public var start: String
    public var end: String
    public init(start: String, end: String) { self.start = start; self.end = end }
    public func text(_ field: Field) -> String { field == .start ? start : end }
    public func hasValue(_ field: Field) -> Bool { !text(field).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    public mutating func clear(_ field: Field) { if field == .start { start = "" } else { end = "" } }
    public mutating func select(_ field: Field, day: String) {
        guard Self.ordinal(day) != nil else { return }
        if field == .start { start = day } else { end = day }
    }
    public var isValid: Bool {
        let first = Self.ordinal(start), last = Self.ordinal(end)
        guard !hasValue(.start) || first != nil, !hasValue(.end) || last != nil else { return false }
        if let first, let last { return (0...366).contains(last - first) }
        return true
    }
    public func pickerDate(_ field: Field) -> Date? {
        let day = text(field).trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.ordinal(day) != nil else { return nil }
        return MerchantStationServiceWindow(day: day).pickerDate
    }
    public mutating func select(_ field: Field, pickerDate: Date) {
        var carrier = MerchantStationServiceWindow(day: "")
        carrier.selectPickerDate(pickerDate); select(field, day: carrier.day)
    }
    /// Pure Gregorian day arithmetic, independent of DST, device timezone and server timezone.
    private static func ordinal(_ raw: String) -> Int? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines), bytes = Array(text.utf8)
        guard bytes.count == 10, bytes[4] == 45, bytes[7] == 45,
              bytes.enumerated().allSatisfy({ $0.offset == 4 || $0.offset == 7 || (48...57).contains($0.element) }) else { return nil }
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, (1...9999).contains(parts[0]), (1...12).contains(parts[1]) else { return nil }
        let year = parts[0], month = parts[1], day = parts[2]
        let leap = year.isMultiple(of: 400) || (year.isMultiple(of: 4) && !year.isMultiple(of: 100))
        let lengths = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        guard (1...lengths[month - 1]).contains(day) else { return nil }
        let previousYear = year - 1
        return 365 * previousYear + previousYear / 4 - previousYear / 100 + previousYear / 400
            + lengths.prefix(month - 1).reduce(0, +) + day
    }
}

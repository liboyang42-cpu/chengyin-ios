import Foundation

/// A local calendar buffer only. Existing template service and dispatch remain unchanged.
public struct MerchantPerkValidityDraft: Equatable {
    public static let timeZone = TimeZone(secondsFromGMT: 8 * 60 * 60)!
    public static var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = timeZone; return c }
    public let original: String
    public private(set) var enabled: Bool
    public private(set) var day: Date
    public private(set) var edited = false
    public init(value: String, now: Date) {
        original = value; let parsed = Self.parse(value)
        enabled = parsed != nil; day = parsed ?? Self.minimum(now: now)
    }
    public static func minimum(now: Date) -> Date {
        calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
    }
    private static func formatter() -> DateFormatter {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.calendar = calendar
        f.timeZone = timeZone; f.dateFormat = "yyyy-MM-dd"; f.isLenient = false; return f
    }
    public static func parse(_ raw: String) -> Date? {
        guard raw.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}$"#, options: .regularExpression) != nil else { return nil }
        let f = formatter(); guard let date = f.date(from: raw), f.string(from: date) == raw else { return nil }; return date
    }
    public static func wire(_ day: Date) -> String { formatter().string(from: day) }
    public mutating func setEnabled(_ enabled: Bool, now: Date) {
        self.enabled = enabled; edited = true
        if enabled, day < Self.minimum(now: now) { day = Self.minimum(now: now) }
    }
    public mutating func choose(_ date: Date) { day = Self.calendar.startOfDay(for: date); enabled = true; edited = true }
    public var isDirty: Bool { edited && (enabled ? Self.wire(day) : "") != original }
    public func preservesExistingValue(now: Date) -> Bool {
        !original.isEmpty && (Self.parse(original) == nil || day < Self.minimum(now: now)) && !edited
    }
    public func value(now: Date) throws -> String {
        guard edited else { return original } // No implicit repair of historical/manual values.
        guard enabled else { return "" }
        let text = Self.wire(day)
        guard day >= Self.minimum(now: now), Self.parse(text) != nil else { throw APIError.invalidRequest }
        return text
    }
}

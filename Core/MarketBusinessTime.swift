import Foundation

/// Server-declared theme/city wall time. A market or the device zone must never
/// supply a missing business zone. This value provides display, never authority.
public enum MarketBusinessTime: Equatable {
    case calendarDay(String)
    case instant(Date)
    case unknown

    public init(_ raw: String?, businessTimeZoneID: String?) {
        guard let zoneID = businessTimeZoneID,
              TimeZone.knownTimeZoneIdentifiers.contains(zoneID) || zoneID == "UTC",
              let zone = TimeZone(identifier: zoneID), let raw else { self = .unknown; return }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if Self.matches(value, #"^[0-9]{4}-[0-9]{2}-[0-9]{2}$"#) {
            let f = Self.formatter("yyyy-MM-dd", zone)
            guard let date = f.date(from: value), f.string(from: date) == value else { self = .unknown; return }
            self = .calendarDay(value); return
        }
        let formats = [
            (#"^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$"#, "yyyy-MM-dd HH:mm:ss"),
            (#"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}$"#, "yyyy-MM-dd'T'HH:mm:ss"),
            (#"^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}$"#, "yyyy-MM-dd HH:mm")
        ]
        for (pattern, format) in formats where Self.matches(value, pattern) {
            let f = Self.formatter(format, zone)
            guard let date = f.date(from: value), f.string(from: date) == value else { self = .unknown; return }
            // A DST fold has two valid instants. Refuse to guess which occurrence
            // the server meant; it must provide an explicit offset on that date.
            let offset = zone.secondsFromGMT(for: date)
            for delta in [-172_800.0, 172_800.0] {
                let otherOffset = zone.secondsFromGMT(for: date.addingTimeInterval(delta))
                let alternative = date.addingTimeInterval(Double(offset - otherOffset))
                if alternative != date && f.string(from: alternative) == value { self = .unknown; return }
            }
            self = .instant(date); return
        }
        guard Self.matches(value, #"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{1,3})?(Z|[+-][0-9]{2}:[0-9]{2})$"#) else { self = .unknown; return }
        let offset: Int
        if value.hasSuffix("Z") { offset = 0 }
        else {
            let suffix = String(value.suffix(6))
            guard let hours = Int(suffix.dropFirst().prefix(2)), let minutes = Int(suffix.suffix(2)),
                  hours <= 14, minutes < 60, hours < 14 || minutes == 0 else { self = .unknown; return }
            offset = (suffix.first == "-" ? -1 : 1) * (hours * 3600 + minutes * 60)
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = value.contains(".") ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
        guard let date = iso.date(from: value), let offsetZone = TimeZone(secondsFromGMT: offset),
              Self.formatter("yyyy-MM-dd'T'HH:mm:ss", offsetZone).string(from: date) == String(value.prefix(19)) else { self = .unknown; return }
        self = .instant(date)
    }

    public func display(businessTimeZoneID: String, phoneTimeZone: TimeZone) -> MarketTimeDisplay? {
        guard let zone = TimeZone(identifier: businessTimeZoneID) else { return nil }
        switch self {
        case .unknown: return nil
        case .calendarDay(let day):
            return MarketTimeDisplay(phone: day, business: nil, businessTimeZoneID: zone.identifier, phoneOffset: nil)
        case .instant(let date):
            let differs = zone.secondsFromGMT(for: date) != phoneTimeZone.secondsFromGMT(for: date)
            return MarketTimeDisplay(phone: Self.formatter("yyyy-MM-dd HH:mm", phoneTimeZone).string(from: date),
                business: differs ? Self.formatter("yyyy-MM-dd HH:mm", zone).string(from: date) : nil,
                businessTimeZoneID: zone.identifier, phoneOffset: differs ? Self.offsetLabel(phoneTimeZone, date) : nil)
        }
    }

    static func offsetLabel(_ zone: TimeZone, _ date: Date) -> String {
        let seconds = zone.secondsFromGMT(for: date)
        let sign = seconds < 0 ? "-" : "+"
        let hours = abs(seconds) / 3600, minutes = abs(seconds) % 3600 / 60
        return minutes == 0 ? "GMT\(sign)\(hours)" : String(format: "GMT%@%d:%02d", sign, hours, minutes)
    }
    private static func matches(_ value: String, _ pattern: String) -> Bool { value.range(of: pattern, options: .regularExpression) != nil }
    private static func formatter(_ format: String, _ zone: TimeZone) -> DateFormatter {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian); f.timeZone = zone
        f.dateFormat = format; f.isLenient = false
        return f
    }
}

public struct MarketTimeDisplay: Equatable {
    public let phone: String
    public let business: String?
    public let businessTimeZoneID: String
    public let phoneOffset: String?
}

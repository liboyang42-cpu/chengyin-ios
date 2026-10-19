import Foundation

/// Reform plan v9 U03: screens follow the phone's time zone, while business
/// deadlines are Beijing (Asia/Shanghai) wall times that only the server decides.
///
/// ApplicationConfig pins Jackson's bare timestamps to Asia/Shanghai, so a bare
/// source string is always Beijing wall time, never device-local or UTC. Strings
/// with an explicit offset keep that offset. Date-only values stay calendar days
/// and never gain a fabricated instant.
public enum BeijingServerTime: Equatable {
    case calendarDay(String)
    case instant(Date)
    case unknown

    public static var beijing: TimeZone { TimeZone(identifier: "Asia/Shanghai")! }

    private static let bareFormats: [(pattern: String, format: String)] = [
        (#"^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}$"#, "yyyy-MM-dd HH:mm:ss"),
        (#"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}$"#, "yyyy-MM-dd'T'HH:mm:ss"),
        (#"^[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}$"#, "yyyy-MM-dd HH:mm")
    ]

    public init(_ raw: String?) {
        guard let raw else { self = .unknown; return }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if Self.matches(value, #"^[0-9]{4}-[0-9]{2}-[0-9]{2}$"#) {
            let formatter = Self.formatter("yyyy-MM-dd", Self.beijing)
            guard let date = formatter.date(from: value), formatter.string(from: date) == value else { self = .unknown; return }
            self = .calendarDay(value); return
        }
        for candidate in Self.bareFormats where Self.matches(value, candidate.pattern) {
            let formatter = Self.formatter(candidate.format, Self.beijing)
            // Round-trip rejects impossible dates such as 02-30 or 24:00 instead of rolling them over.
            guard let date = formatter.date(from: value), formatter.string(from: date) == value else { self = .unknown; return }
            self = .instant(date); return
        }
        if Self.matches(value, #"^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\.[0-9]{1,3})?(Z|[+-][0-9]{2}:[0-9]{2})$"#) {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = value.contains(".") ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]
            guard let date = iso.date(from: value) else { self = .unknown; return }
            self = .instant(date); return
        }
        self = .unknown
    }

    /// Display in the phone's zone. When that zone's offset differs from Beijing at
    /// this instant, the Beijing wall time is returned too so a deadline stays legible.
    public func display(phoneTimeZone: TimeZone) -> BeijingTimeDisplay? {
        switch self {
        case .calendarDay(let day): return BeijingTimeDisplay(phone: day, beijing: nil, phoneZoneAbbreviation: nil)
        case .instant(let date):
            let phone = Self.formatter("yyyy-MM-dd HH:mm", phoneTimeZone).string(from: date)
            let differs = phoneTimeZone.secondsFromGMT(for: date) != Self.beijing.secondsFromGMT(for: date)
            let beijing = differs ? Self.formatter("yyyy-MM-dd HH:mm", Self.beijing).string(from: date) : nil
            return BeijingTimeDisplay(phone: phone, beijing: beijing, phoneZoneAbbreviation: differs ? Self.offsetLabel(phoneTimeZone, date) : nil)
        case .unknown: return nil
        }
    }

    static func offsetLabel(_ zone: TimeZone, _ date: Date) -> String {
        let seconds = zone.secondsFromGMT(for: date)
        let sign = seconds < 0 ? "-" : "+"
        let hours = abs(seconds) / 3600, minutes = abs(seconds) % 3600 / 60
        return minutes == 0 ? "GMT\(sign)\(hours)" : String(format: "GMT%@%d:%02d", sign, hours, minutes)
    }
    private static func matches(_ value: String, _ pattern: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) != nil
    }
    private static func formatter(_ format: String, _ zone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = zone; formatter.dateFormat = format; formatter.isLenient = false
        return formatter
    }
}

/// Words ("北京时间"/"Beijing time") stay in the App's catalog; Core only supplies values.
public struct BeijingTimeDisplay: Equatable {
    public let phone: String
    public let beijing: String?
    public let phoneZoneAbbreviation: String?
}

/// Server time anchored to the monotonic uptime clock when a response arrived.
/// Changing the phone's wall clock does not move it; a reboot (uptime going
/// backwards) invalidates it; each reconnect replaces it with a fresh anchor.
public struct ServerClockAnchor: Equatable {
    public let serverDate: Date
    public let uptime: TimeInterval
    public init(serverDate: Date, uptime: TimeInterval) { self.serverDate = serverDate; self.uptime = uptime }

    public func serverNow(uptime current: TimeInterval) -> Date? {
        guard current >= uptime else { return nil }
        return serverDate.addingTimeInterval(current - uptime)
    }
}

/// A client-side hint only. Opening or closing an action at a deadline is always
/// re-validated by the server; a hint never changes the deadline fact itself.
public enum BusinessDeadlineHint: Equatable {
    /// Strictly before the deadline, by server time.
    case open(remainingSeconds: Int)
    /// At or after the deadline second, by server time. The server still decides.
    case passed
    /// No verified server time, a date-only deadline, or an unparseable value.
    case unverified
}

public struct BusinessDeadline: Equatable {
    public let time: BeijingServerTime
    public init(_ raw: String?) { time = BeijingServerTime(raw) }

    /// The phone's own wall clock is deliberately not an input.
    public func hint(anchor: ServerClockAnchor?, uptime: TimeInterval) -> BusinessDeadlineHint {
        guard case .instant(let deadline) = time, let now = anchor?.serverNow(uptime: uptime) else { return .unverified }
        let remaining = deadline.timeIntervalSince(now)
        // The deadline second itself is already passed; fractions below one second stay open.
        return remaining > 0 ? .open(remainingSeconds: Int(remaining.rounded(.down))) : .passed
    }
}

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

    public init(_ raw: String?) {
        switch MarketBusinessTime(raw, businessTimeZoneID: "Asia/Shanghai") {
        case .calendarDay(let day): self = .calendarDay(day)
        case .instant(let date): self = .instant(date)
        case .unknown: self = .unknown
        }
    }

    public func display(phoneTimeZone: TimeZone) -> BeijingTimeDisplay? {
        let value: MarketBusinessTime
        switch self {
        case .calendarDay(let day): value = .calendarDay(day)
        case .instant(let date): value = .instant(date)
        case .unknown: value = .unknown
        }
        guard let display = value.display(businessTimeZoneID: "Asia/Shanghai", phoneTimeZone: phoneTimeZone) else { return nil }
        return BeijingTimeDisplay(phone: display.phone, beijing: display.business, phoneZoneAbbreviation: display.phoneOffset)
    }

    static func offsetLabel(_ zone: TimeZone, _ date: Date) -> String {
        MarketBusinessTime.offsetLabel(zone, date)
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

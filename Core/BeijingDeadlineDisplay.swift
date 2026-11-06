import Foundation

/// Reform plan v9 decision U03: the UI shows times in the phone's time zone, while
/// business deadlines are defined in Beijing time (Asia/Shanghai) and validated by
/// the server. Changing the device zone or clock changes only how a deadline is
/// displayed, never the deadline instant. The client's "closed" hint is advisory;
/// a submit near the boundary is still sent and the server decides.
public enum BeijingDeadlineIssue: Error, Equatable { case invalid, zoneMismatch }

public struct BeijingDeadline: Equatable, Sendable {
    public static let businessZone = TimeZone(identifier: "Asia/Shanghai")!
    /// Exact instant from the server, epoch milliseconds.
    public let instant: Date
    /// Beijing civil wall time as the server stated it (yyyy-MM-dd'T'HH:mm:ss).
    public let beijingCivil: String

    /// Accepts the server pair and refuses it if the civil text does not denote the same instant in Asia/Shanghai.
    public init(epochMilliseconds: Int64, beijingCivil: String, zone: String = "Asia/Shanghai") throws {
        guard zone == "Asia/Shanghai" else { throw BeijingDeadlineIssue.zoneMismatch }
        guard epochMilliseconds > 0, epochMilliseconds < 32_503_680_000_000, let parsed = Self.civilFormatter.date(from: beijingCivil),
              Self.civilFormatter.string(from: parsed) == beijingCivil else { throw BeijingDeadlineIssue.invalid }
        let instant = Date(timeIntervalSince1970: Double(epochMilliseconds) / 1000)
        // Sub-second precision belongs to the instant; the civil text is second-resolution.
        guard floor(instant.timeIntervalSince1970) == parsed.timeIntervalSince1970 else { throw BeijingDeadlineIssue.zoneMismatch }
        self.instant = instant; self.beijingCivil = beijingCivil
    }

    public enum Hint: Equatable, Sendable {
        case open(remainingSeconds: Int)
        /// Within the uncertainty window: show "closing", still allow submit, server decides.
        case boundary
        case likelyClosed
    }
    /// `serverOffset` = serverNow − deviceNow from the last authoritative response, so
    /// a manually changed phone clock does not move the hint. `uncertainty` covers
    /// network latency and the server's own critical-second handling.
    public func hint(deviceNow: Date, serverOffset: TimeInterval, uncertainty: TimeInterval = 2) -> Hint {
        let estimated = deviceNow.addingTimeInterval(serverOffset)
        let remaining = instant.timeIntervalSince(estimated)
        if abs(remaining) <= max(0, uncertainty) { return .boundary }
        return remaining > 0 ? .open(remainingSeconds: Int(remaining.rounded(.down))) : .likelyClosed
    }

    /// Display pair: the phone-zone time and, when it differs, the Beijing time that governs.
    public func display(phoneZone: TimeZone, locale: Locale) -> (local: String, beijing: String?) {
        let local = Self.formatter(zone: phoneZone, locale: locale).string(from: instant)
        let differs = phoneZone.secondsFromGMT(for: instant) != Self.businessZone.secondsFromGMT(for: instant)
        return (local, differs ? Self.formatter(zone: Self.businessZone, locale: locale).string(from: instant) : nil)
    }

    private static let civilFormatter: DateFormatter = {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = businessZone; f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"; f.isLenient = false
        return f
    }()
    private static func formatter(zone: TimeZone, locale: Locale) -> DateFormatter {
        let f = DateFormatter(); f.calendar = Calendar(identifier: .gregorian); f.locale = locale; f.timeZone = zone
        f.setLocalizedDateFormatFromTemplate("yMMMdjmmz")
        return f
    }
}

import Foundation

/// Server-attested validity for environment, equipment, or status windows.
/// Client `Date` is never an input to success. A lone `expiresAt` without a
/// server `asOf` stays `WAITING_SOURCE` instead of treating local time as live.
public struct EnvironmentExpiryClock: Equatable {
    public let availability: WorldFactAvailability
    public let expired: Bool
    public let serverNow: Int64?
    public let capturedAt: Int64?
    public let expiresAt: Int64?
    public static let waitingSource = EnvironmentExpiryClock(
        availability: .waitingSource, expired: false, serverNow: nil, capturedAt: nil, expiresAt: nil)
    public static let unknown = EnvironmentExpiryClock(
        availability: .unknown, expired: false, serverNow: nil, capturedAt: nil, expiresAt: nil)
    public init(availability: WorldFactAvailability, expired: Bool, serverNow: Int64?, capturedAt: Int64?, expiresAt: Int64?) {
        self.availability = availability; self.expired = expired
        self.serverNow = serverNow; self.capturedAt = capturedAt; self.expiresAt = expiresAt
    }
    /// `clientNow` is accepted only so tests can prove it cannot mint success.
    public static func read(_ raw: PlayWireValue, clientNow: Date? = nil) -> Self {
        _ = clientNow
        if raw == .null { return .waitingSource }
        guard raw.object != nil else { return .unknown }
        let serverNow = instant(present(raw, "serverNow", "asOf", "asOfMs"))
        let capturedAt = instant(present(raw, "capturedAt", "capturedAtMs"))
        let expiresAt = instant(present(raw, "expiresAt", "expiresAtMs", "validUntil"))
        if let text = (raw["status"].text ?? raw["validity"].text)?.trimmingCharacters(in: .whitespacesAndNewlines) {
            switch text {
            case "VALID", "ACTIVE":
                return .init(availability: .ready, expired: false, serverNow: serverNow, capturedAt: capturedAt, expiresAt: expiresAt)
            case "EXPIRED":
                return .init(availability: .unknown, expired: true, serverNow: serverNow, capturedAt: capturedAt, expiresAt: expiresAt)
            case "UNKNOWN":
                return .init(availability: .unknown, expired: false, serverNow: serverNow, capturedAt: capturedAt, expiresAt: expiresAt)
            case "WAITING_SOURCE":
                return .init(availability: .waitingSource, expired: false, serverNow: serverNow, capturedAt: capturedAt, expiresAt: expiresAt)
            default:
                return .init(availability: .unknown, expired: false, serverNow: serverNow, capturedAt: capturedAt, expiresAt: expiresAt)
            }
        }
        if let expired = raw["expired"].bool {
            return .init(availability: expired ? .unknown : .ready, expired: expired,
                         serverNow: serverNow, capturedAt: capturedAt, expiresAt: expiresAt)
        }
        if let serverNow, let expiresAt {
            let expired = serverNow >= expiresAt
            return .init(availability: expired ? .unknown : .ready, expired: expired,
                         serverNow: serverNow, capturedAt: capturedAt, expiresAt: expiresAt)
        }
        if expiresAt != nil || capturedAt != nil || serverNow != nil {
            return .init(availability: .waitingSource, expired: false,
                         serverNow: serverNow, capturedAt: capturedAt, expiresAt: expiresAt)
        }
        return .waitingSource
    }
    public var isValid: Bool { availability == .ready && !expired }
    /// Missing keys are `.null`, not Optional, so `??` cannot select an alias.
    private static func present(_ raw: PlayWireValue, _ keys: String...) -> PlayWireValue {
        for key in keys {
            let value = raw[key]
            if value != .null { return value }
        }
        return .null
    }
    private static func instant(_ value: PlayWireValue) -> Int64? {
        if let number = value.integer, number > 0 { return Int64(number) }
        if case .integer(let raw) = value, raw > 0 { return raw }
        if let number = value.double, number.isFinite, number > 0, number < Double(Int64.max) {
            return Int64(number > 1_000_000_000_000 ? number : number)
        }
        if let text = value.text?.trimmingCharacters(in: .whitespacesAndNewlines),
           let number = Int64(text), number > 0 { return number }
        return nil
    }
}

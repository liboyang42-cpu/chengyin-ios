import Foundation

/// System authorization is information, never a Roam live/background capability grant.
public enum RoamSystemLocationAuthorization: String, CaseIterable, Sendable {
    case notDetermined, denied, restricted, whenInUse, always, unknown
}

public struct RoamLocationSettingsSnapshot: Equatable, Sendable {
    public let authorization: RoamSystemLocationAuthorization
    public let servicesEnabled: Bool
    public init(authorization: RoamSystemLocationAuthorization, servicesEnabled: Bool) {
        self.authorization = authorization; self.servicesEnabled = servicesEnabled
    }
    public var foregroundAuthorized: Bool { authorization == .whenInUse || authorization == .always }
    public var alwaysAuthorized: Bool { authorization == .always }
    // These are OS permission facts only. They do not assert recording, reminders, or live approval.
}

public struct RoamLocationSettingsState: Equatable {
    public enum Phase: Equatable { case idle, loading, loaded(RoamLocationSettingsSnapshot), failed }
    public private(set) var phase: Phase = .idle
    public private(set) var settingsOpenFailed = false
    private var readAttempt: UUID?
    private var settingsAttempt: UUID?
    public var isOpeningSettings: Bool { settingsAttempt != nil }
    public init() {}
    public mutating func beginRead() -> UUID {
        let attempt = UUID(); readAttempt = attempt; phase = .loading
        settingsAttempt = nil; settingsOpenFailed = false
        return attempt
    }
    @discardableResult public mutating func finishRead(_ attempt: UUID, snapshot: RoamLocationSettingsSnapshot?) -> Bool {
        guard readAttempt == attempt else { return false }
        readAttempt = nil
        phase = snapshot.map(Phase.loaded) ?? .failed
        return true
    }
    public mutating func beginSettingsOpen() -> UUID? {
        guard settingsAttempt == nil else { return nil }
        let attempt = UUID(); settingsAttempt = attempt; settingsOpenFailed = false; return attempt
    }
    public func acceptsSettingsOpen(_ attempt: UUID) -> Bool { settingsAttempt == attempt }
    @discardableResult public mutating func finishSettingsOpen(_ attempt: UUID, opened: Bool) -> Bool {
        guard settingsAttempt == attempt else { return false }
        settingsAttempt = nil; settingsOpenFailed = !opened; return true
    }
    public mutating func invalidate() {
        readAttempt = nil; settingsAttempt = nil; phase = .idle; settingsOpenFailed = false
    }
}

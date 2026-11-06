import Foundation

/// Platform-neutral reading of one OS audio lifecycle notification. The App layer maps
/// AVAudioSession/UIApplication notifications here so the decision table stays testable.
public enum PlatformAudioLifecycleSignal: Equatable, Sendable {
    case interruptionBegan
    case interruptionEnded(shouldResume: Bool)
    case routeOldDeviceUnavailable
    case routeNewDeviceAvailable
    case routeCategoryChange
    case routeOther
    case mediaServicesReset
    case enteredBackground
    case unknown
}
public enum PlatformAudioLifecycleAction: Equatable, Sendable { case ignore, stop }
/// Calls, Siri, alarms, recording preemption, headphone unplug, media reset and backgrounding
/// all stop and release. Nothing here ever resumes: an interruption end (even with
/// `shouldResume`) is not a user intent, so only an explicit tap can start audio again.
public enum PlatformAudioLifecyclePolicy {
    /// `ownsConfiguration` is true while the shared session still carries this owner's own
    /// category, so its own setCategory echo or a newly attached output does not stop it.
    public static func action(for signal: PlatformAudioLifecycleSignal, ownsConfiguration: Bool) -> PlatformAudioLifecycleAction {
        switch signal {
        case .interruptionEnded: return .ignore
        case .routeCategoryChange, .routeNewDeviceAvailable: return ownsConfiguration ? .ignore : .stop
        case .interruptionBegan, .routeOldDeviceUnavailable, .routeOther, .mediaServicesReset, .enteredBackground, .unknown:
            return .stop
        }
    }
}

import AVFoundation
import UIKit

extension PlatformAudioLifecycleSignal {
    /// Missing or unrecognised keys read as `.unknown`, which the policy treats as stop.
    init(_ notification: Notification) {
        let info = notification.userInfo
        func number(_ key: String) -> UInt? { (info?[key] as? NSNumber)?.uintValue }
        switch notification.name {
        case AVAudioSession.interruptionNotification:
            switch number(AVAudioSessionInterruptionTypeKey).flatMap(AVAudioSession.InterruptionType.init(rawValue:)) {
            case .began?: self = .interruptionBegan
            case .ended?:
                let options = AVAudioSession.InterruptionOptions(rawValue: number(AVAudioSessionInterruptionOptionKey) ?? 0)
                self = .interruptionEnded(shouldResume: options.contains(.shouldResume))
            default: self = .unknown
            }
        case AVAudioSession.routeChangeNotification:
            switch number(AVAudioSessionRouteChangeReasonKey).flatMap(AVAudioSession.RouteChangeReason.init(rawValue:)) {
            case .oldDeviceUnavailable?: self = .routeOldDeviceUnavailable
            case .newDeviceAvailable?: self = .routeNewDeviceAvailable
            case .categoryChange?: self = .routeCategoryChange
            case nil: self = .unknown
            default: self = .routeOther
            }
        case AVAudioSession.mediaServicesWereResetNotification: self = .mediaServicesReset
        case UIApplication.didEnterBackgroundNotification: self = .enteredBackground
        default: self = .unknown
        }
    }
}

/// One observer set per audio run. Re-observing first removes the previous set, and a
/// notification already queued for an invalidated run is dropped, so an old run's callback
/// can never act on a newer session.
@MainActor final class NativeAudioLifecycleObservation {
    static let names: [Notification.Name] = [
        AVAudioSession.interruptionNotification, AVAudioSession.routeChangeNotification,
        AVAudioSession.mediaServicesWereResetNotification, UIApplication.didEnterBackgroundNotification
    ]
    private let notifications: NotificationCenter
    private let enqueue: @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void
    private var observers: [NSObjectProtocol] = []
    private var generation = 0
    var registrations: Int { observers.count }
    init(notifications: NotificationCenter,
         enqueue: @escaping @Sendable (@escaping @MainActor @Sendable () -> Void) -> Void = { operation in Task { @MainActor in operation() } }) {
        self.notifications = notifications; self.enqueue = enqueue
    }
    func observe(_ handler: @escaping @MainActor @Sendable (PlatformAudioLifecycleSignal) -> Void) {
        invalidate()
        let token = generation, enqueue = enqueue
        for name in Self.names {
            observers.append(notifications.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                let signal = PlatformAudioLifecycleSignal(notification)
                enqueue { [weak self] in
                    guard let self, self.generation == token else { return }
                    handler(signal)
                }
            })
        }
    }
    func invalidate() {
        generation += 1
        observers.forEach(notifications.removeObserver); observers.removeAll()
    }
    deinit { observers.forEach(notifications.removeObserver) }
}

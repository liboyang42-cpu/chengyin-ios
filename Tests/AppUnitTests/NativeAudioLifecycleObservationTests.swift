import XCTest
import AVFoundation
import UIKit
@testable import Questify

/// Synthetic notification center and delivery queue only. No device audio session is touched.
@MainActor final class NativeAudioLifecycleObservationTests: XCTestCase {
    private final class Queue: @unchecked Sendable {
        private let lock = NSLock()
        private var operations: [@MainActor @Sendable () -> Void] = []
        func enqueue(_ operation: @escaping @MainActor @Sendable () -> Void) { lock.lock(); operations.append(operation); lock.unlock() }
        @MainActor func drain() {
            lock.lock(); let pending = operations; operations.removeAll(); lock.unlock()
            pending.forEach { $0() }
        }
    }
    @MainActor private final class Recorder { var signals: [PlatformAudioLifecycleSignal] = [] }
    private func notice(_ name: Notification.Name, _ info: [AnyHashable: Any]? = nil) -> Notification {
        Notification(name: name, object: nil, userInfo: info)
    }
    func testNotificationMappingCoversCallsRoutesResetAndBackground() {
        let interruption = AVAudioSession.interruptionNotification, route = AVAudioSession.routeChangeNotification
        let cases: [(Notification, PlatformAudioLifecycleSignal)] = [
            (notice(interruption, [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue]), .interruptionBegan),
            (notice(interruption, [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue]),
             .interruptionEnded(shouldResume: false)),
            (notice(interruption, [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue,
                                   AVAudioSessionInterruptionOptionKey: AVAudioSession.InterruptionOptions.shouldResume.rawValue]),
             .interruptionEnded(shouldResume: true)),
            (notice(interruption, [AVAudioSessionInterruptionTypeKey: UInt(99)]), .unknown),
            (notice(interruption), .unknown),
            (notice(route, [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue]), .routeOldDeviceUnavailable),
            (notice(route, [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.newDeviceAvailable.rawValue]), .routeNewDeviceAvailable),
            (notice(route, [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.categoryChange.rawValue]), .routeCategoryChange),
            (notice(route, [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.override.rawValue]), .routeOther),
            (notice(route), .unknown),
            (notice(AVAudioSession.mediaServicesWereResetNotification), .mediaServicesReset),
            (notice(UIApplication.didEnterBackgroundNotification), .enteredBackground),
            (notice(Notification.Name("synthetic.unrelated")), .unknown)
        ]
        for (notification, expected) in cases {
            XCTAssertEqual(PlatformAudioLifecycleSignal(notification), expected, "\(notification.name.rawValue)")
        }
    }
    func testReobserveReplacesSetAndQueuedSignalOfOldRunIsDropped() {
        let center = NotificationCenter(), queue = Queue(), first = Recorder(), second = Recorder()
        let observation = NativeAudioLifecycleObservation(notifications: center, enqueue: { [queue] in queue.enqueue($0) })
        observation.observe { first.signals.append($0) }
        XCTAssertEqual(observation.registrations, NativeAudioLifecycleObservation.names.count)
        center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        observation.observe { second.signals.append($0) }
        XCTAssertEqual(observation.registrations, NativeAudioLifecycleObservation.names.count)
        center.post(name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
        queue.drain()
        XCTAssertEqual(first.signals, []) // Queued before re-observe, delivered after: dropped.
        XCTAssertEqual(second.signals, [.mediaServicesReset])
        center.post(name: AVAudioSession.mediaServicesWereResetNotification, object: nil)
        observation.invalidate(); queue.drain()
        XCTAssertEqual(second.signals, [.mediaServicesReset]); XCTAssertEqual(observation.registrations, 0)
        center.post(name: AVAudioSession.mediaServicesWereResetNotification, object: nil); queue.drain()
        XCTAssertEqual(second.signals, [.mediaServicesReset])
    }
}

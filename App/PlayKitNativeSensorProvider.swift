import Foundation
import UIKit
import CoreMotion
import CoreLocation
import AVFoundation

/// Dormant until an explicit user gesture, accepted grant, purpose key and OS
/// authorization all agree. This adapter never stores or uploads microphone data.
@MainActor final class PlayKitNativeSensorProvider: NSObject, PlayKitSensorProviding, PlayKitSensorAuthorizing, CLLocationManagerDelegate {
    let supported: Set<PlayKitSensorKind>
    private let purposeDescriptions: [String: String]
    private var motion: CMMotionManager?
    private var location: CLLocationManager?
    private var headingPermission: CheckedContinuation<Void, Error>?
    private var engine: AVAudioEngine?
    private var audioTapInstalled = false
    private var audioSessionActive = false
    private var previousAudioSession: (AVAudioSession.Category, AVAudioSession.Mode, AVAudioSession.CategoryOptions)?
    private var continuation: AsyncThrowingStream<PlayKitSensorSample, Error>.Continuation?
    private var generation = UUID()
    private var activeKind: PlayKitSensorKind?
    private var observers: [NSObjectProtocol] = []

    init(grants: Set<PlayKitSensorKind> = [], purposeDescriptions: [String: String]? = nil) {
        supported = grants.intersection(Set(PlayKitSensorKind.allCases))
        self.purposeDescriptions = purposeDescriptions ?? Bundle.main.infoDictionary?.compactMapValues { $0 as? String } ?? [:]
        super.init()
    }

    func prepare(_ kind: PlayKitSensorKind) async throws {
        cancel()
        try checkConfiguration(kind)
        guard UIApplication.shared.applicationState == .active else { throw PlayKitSensorError.interrupted }
        let token = generation
        switch kind {
        case .acceleration:
            let manager = CMMotionManager()
            guard manager.isAccelerometerAvailable else { throw PlayKitSensorError.sensorUnavailable }
            guard CMMotionActivityManager.authorizationStatus() != .denied,
                  CMMotionActivityManager.authorizationStatus() != .restricted else { throw PlayKitSensorError.permissionDenied }
            motion = manager
        case .soundPeak:
            let session = AVAudioSession.sharedInstance()
            switch session.recordPermission {
            case .granted: break
            case .denied: throw PlayKitSensorError.permissionDenied
            case .undetermined:
                let allowed: Bool = await withCheckedContinuation { reply in
                    session.requestRecordPermission { reply.resume(returning: $0) }
                }
                guard allowed else { throw PlayKitSensorError.permissionDenied }
            @unknown default: throw PlayKitSensorError.permissionDenied
            }
        case .heading:
            guard CLLocationManager.headingAvailable() else { throw PlayKitSensorError.sensorUnavailable }
            let manager = CLLocationManager(); location = manager; manager.delegate = self
            switch manager.authorizationStatus {
            case .authorizedWhenInUse, .authorizedAlways: break
            case .denied, .restricted: throw PlayKitSensorError.permissionDenied
            case .notDetermined:
                try await withCheckedThrowingContinuation { (reply: CheckedContinuation<Void, Error>) in
                    headingPermission = reply; manager.requestWhenInUseAuthorization()
                }
            @unknown default: throw PlayKitSensorError.permissionDenied
            }
        }
        guard !Task.isCancelled, generation == token, UIApplication.shared.applicationState == .active else { throw PlayKitSensorError.interrupted }
    }

    func samples(_ kind: PlayKitSensorKind) -> AsyncThrowingStream<PlayKitSensorSample, Error> {
        AsyncThrowingStream { stream in
            guard continuation == nil else { stream.finish(throwing: PlayKitSensorError.sensorUnavailable); return }
            do {
                try checkConfiguration(kind)
                guard UIApplication.shared.applicationState == .active else { throw PlayKitSensorError.interrupted }
                let token = generation
                continuation = stream; activeKind = kind
                stream.onTermination = { [weak self] _ in
                    Task { @MainActor in guard self?.generation == token else { return }; self?.cancel() }
                }
                observeInterruptions(token: token)
                switch kind {
                case .acceleration: try startAcceleration(token: token)
                case .soundPeak: try startAudio(token: token)
                case .heading: try startHeading()
                }
            } catch { finish(error) }
        }
    }

    private func checkConfiguration(_ kind: PlayKitSensorKind) throws {
        let purpose: String
        switch kind {
        case .acceleration: purpose = "NSMotionUsageDescription"
        case .soundPeak: purpose = "NSMicrophoneUsageDescription"
        case .heading: purpose = "NSLocationWhenInUseUsageDescription"
        }
        guard supported.contains(kind),
              let value = purposeDescriptions[purpose], !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !value.contains("$(") else { throw PlayKitSensorError.configurationUnavailable }
        // The actual installed bundle must also contain the key. An injected
        // description cannot bypass iOS's mandatory privacy declaration.
        guard let installed = Bundle.main.object(forInfoDictionaryKey: purpose) as? String,
              !installed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !installed.contains("$(") else { throw PlayKitSensorError.configurationUnavailable }
    }

    private func startAcceleration(token: UUID) throws {
        let manager = motion ?? CMMotionManager()
        guard manager.isAccelerometerAvailable else { throw PlayKitSensorError.sensorUnavailable }
        guard CMMotionActivityManager.authorizationStatus() != .denied,
              CMMotionActivityManager.authorizationStatus() != .restricted else { throw PlayKitSensorError.permissionDenied }
        motion = manager; manager.accelerometerUpdateInterval = 0.016
        manager.startAccelerometerUpdates(to: .main) { [weak self] reading, error in
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                guard let reading, error == nil else { self.finish(PlayKitSensorError.sensorUnavailable); return }
                let g = 9.80665
                self.continuation?.yield(.acceleration(x: reading.acceleration.x * g, y: reading.acceleration.y * g,
                    z: reading.acceleration.z * g, timestamp: reading.timestamp))
            }
        }
    }

    private func startAudio(token: UUID) throws {
        let session = AVAudioSession.sharedInstance()
        guard session.recordPermission == .granted else { throw PlayKitSensorError.permissionDenied }
        previousAudioSession = (session.category, session.mode, session.categoryOptions)
        try session.setCategory(.record, mode: .measurement, options: [])
        try session.setActive(true); audioSessionActive = true
        let engine = AVAudioEngine(); self.engine = engine
        let input = engine.inputNode, format = input.outputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else { throw PlayKitSensorError.sensorUnavailable }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            // Inspect in place on the audio callback. Only a scalar peak leaves
            // this scope; no PCM Data, file, upload, speech recognizer or recorder.
            guard buffer.frameLength > 0, let channels = buffer.floatChannelData else { return }
            var peak: Float = 0
            for channel in 0..<Int(buffer.format.channelCount) {
                for frame in 0..<Int(buffer.frameLength) {
                    let value = channels[channel][frame]
                    guard value.isFinite else { return }
                    peak = max(peak, abs(value))
                }
            }
            let amplitude = Double(min(1, peak)), timestamp = ProcessInfo.processInfo.systemUptime
            Task { @MainActor in
                guard let self, self.generation == token else { return }
                self.continuation?.yield(.soundPeak(amplitude, timestamp: timestamp))
            }
        }
        audioTapInstalled = true; engine.prepare(); try engine.start()
    }

    private func startHeading() throws {
        guard CLLocationManager.headingAvailable() else { throw PlayKitSensorError.sensorUnavailable }
        let manager = location ?? CLLocationManager(); location = manager; manager.delegate = self
        guard [.authorizedAlways, .authorizedWhenInUse].contains(manager.authorizationStatus) else { throw PlayKitSensorError.permissionDenied }
        manager.headingFilter = kCLHeadingFilterNone
        // Task orientation is the top of the phone in portrait. No location
        // coordinate stream is requested or submitted for this activity.
        manager.headingOrientation = .portrait; manager.startUpdatingHeading()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager === location else { return }
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            let reply = headingPermission; headingPermission = nil; reply?.resume()
        case .denied, .restricted: finish(PlayKitSensorError.permissionDenied)
        default: break
        }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateHeading heading: CLHeading) {
        guard manager === location, activeKind == .heading,
              UIApplication.shared.applicationState == .active else { return }
        guard heading.headingAccuracy >= 0, heading.magneticHeading.isFinite,
              heading.headingAccuracy.isFinite else { return }
        let age = -heading.timestamp.timeIntervalSinceNow
        guard age >= -0.05, age <= PlayKitSensorContinuity.maximumGap else { return }
        let timestamp = ProcessInfo.processInfo.systemUptime - max(0, age)
        continuation?.yield(.heading(heading.magneticHeading, accuracy: heading.headingAccuracy, timestamp: timestamp))
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard manager === location else { return }; finish(PlayKitSensorError.sensorUnavailable)
    }
    func locationManagerShouldDisplayHeadingCalibration(_ manager: CLLocationManager) -> Bool { false }

    private func observeInterruptions(token: UUID) {
        let names: [Notification.Name] = [UIApplication.willResignActiveNotification, UIApplication.didEnterBackgroundNotification,
            AVAudioSession.interruptionNotification, AVAudioSession.mediaServicesWereResetNotification,
            AVAudioSession.routeChangeNotification]
        observers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                if name == AVAudioSession.routeChangeNotification,
                   let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                   AVAudioSession.RouteChangeReason(rawValue: raw) == .categoryChange { return }
                Task { @MainActor in
                    guard let self, self.generation == token else { return }
                    self.finish(PlayKitSensorError.interrupted)
                }
            }
        }
    }
    func cancel() { finish(CancellationError()) }
    private func finish(_ error: Error) {
        generation = UUID()
        let stream = continuation; continuation = nil; activeKind = nil
        let reply = headingPermission; headingPermission = nil; reply?.resume(throwing: error)
        motion?.stopAccelerometerUpdates(); motion = nil
        location?.stopUpdatingHeading(); location?.delegate = nil; location = nil
        if audioTapInstalled { engine?.inputNode.removeTap(onBus: 0); audioTapInstalled = false }
        engine?.stop(); engine = nil
        observers.forEach { NotificationCenter.default.removeObserver($0) }; observers = []
        if audioSessionActive {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            audioSessionActive = false
        }
        if let previousAudioSession {
            try? AVAudioSession.sharedInstance().setCategory(previousAudioSession.0, mode: previousAudioSession.1, options: previousAudioSession.2)
            self.previousAudioSession = nil
        }
        stream?.finish(throwing: error)
    }
}

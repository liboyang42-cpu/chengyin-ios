import Foundation
import AVFoundation

/// Constructing this provider does not access the microphone/audio session. Defaults off.
/// Permission is requested only by start(), reached through an explicit Record button.
@MainActor final class MerchantNPCAVVoiceDevice: NSObject, MerchantNPCVoiceDevice, AVAudioRecorderDelegate, AVAudioPlayerDelegate {
    private let enabled: () -> Bool
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var file: URL?
    private var configuration: MerchantNPCVoiceConfiguration?
    private var interrupted: (() -> Void)?
    private let lifecycle: NativeAudioLifecycleObservation
    private let temporaryDirectory: URL
    private var generation = 0
    private var sessionActive = false
    var lifecycleRegistrations: Int { lifecycle.registrations }
    init(enabled: @escaping () -> Bool = { false }, notifications: NotificationCenter = .default,
         temporaryDirectory: URL = FileManager.default.temporaryDirectory) {
        self.enabled = enabled; self.temporaryDirectory = temporaryDirectory
        lifecycle = .init(notifications: notifications); super.init()
    }
    func start(configuration: MerchantNPCVoiceConfiguration, interrupted: @escaping () -> Void) async throws {
        guard enabled(), recorder == nil else { throw MerchantNPCFailure.disabled }
        cancel(); let stamp = generation
        MerchantNPCVoiceTemporaryFiles.sweep(in: temporaryDirectory)
        let session = AVAudioSession.sharedInstance()
        let permitted: Bool
        switch session.recordPermission {
        case .granted: permitted = true
        case .denied: permitted = false
        default: permitted = await withCheckedContinuation { continuation in session.requestRecordPermission { continuation.resume(returning: $0) } }
        }
        guard permitted, enabled(), stamp == generation, !Task.isCancelled else { throw MerchantNPCFailure.disabled }
        self.interrupted = interrupted; self.configuration = configuration
        do {
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
            try session.setActive(true); sessionActive = true
            let url = MerchantNPCVoiceTemporaryFiles.make(in: temporaryDirectory)
            file = url
            let value = try AVAudioRecorder(url: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: configuration.sampleRate, AVNumberOfChannelsKey: configuration.channels, AVEncoderBitRateKey: configuration.bitRate])
            recorder = value; value.delegate = self
            observeLifecycle(category: .playAndRecord, stamp: stamp)
            guard value.record(forDuration: configuration.maxDuration) else { throw MerchantNPCFailure.invalid }
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
        } catch { cancel(); throw error }
    }
    func finish() throws -> MerchantNPCVoiceClip? {
        guard enabled(), let recorder, let file, let configuration, recorder.isRecording else { cancel(); return nil }
        let duration = recorder.currentTime
        recorder.delegate = nil; recorder.stop()
        defer { cancel() }
        let size = (try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.intValue ?? 0
        guard size > 0, size <= configuration.maxBytes else { throw MerchantNPCFailure.invalid }
        let clip = MerchantNPCVoiceClip(bytes: try Data(contentsOf: file), duration: duration)
        try configuration.validate(clip); return clip
    }
    func play(_ clip: MerchantNPCVoiceClip) throws {
        guard enabled(), recorder == nil else { throw MerchantNPCFailure.disabled }
        cancel(); let stamp = generation
        do {
            let session = AVAudioSession.sharedInstance(); try session.setCategory(.playback, mode: .spokenAudio); try session.setActive(true); sessionActive = true
            let value = try AVAudioPlayer(data: clip.bytes); player = value; value.delegate = self
            observeLifecycle(category: .playback, stamp: stamp)
            guard value.play() else { throw MerchantNPCFailure.invalid }
        } catch { cancel(); throw error }
    }
    /// Calls, unplugged headphones, another app's recording, media reset and backgrounding end
    /// the take or sample; an interruption end never restarts either.
    private func observeLifecycle(category: AVAudioSession.Category, stamp: Int) {
        lifecycle.observe { [weak self] signal in
            guard let self, self.generation == stamp,
                  PlatformAudioLifecyclePolicy.action(for: signal, ownsConfiguration: AVAudioSession.sharedInstance().category == category) == .stop
            else { return }
            self.abort()
        }
    }
    private func abort() { let callback = interrupted; cancel(); callback?() }
    func cancel() {
        generation += 1
        let usedSession = sessionActive; sessionActive = false
        recorder?.delegate = nil; recorder?.stop(); recorder = nil; player?.delegate = nil; player?.stop(); player = nil
        if let file { try? FileManager.default.removeItem(at: file) }; file = nil; configuration = nil; interrupted = nil
        lifecycle.invalidate()
        if usedSession { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    }
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) { Task { @MainActor [weak self] in guard let self, self.recorder === recorder else { return }; self.abort() } }
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) { Task { @MainActor [weak self] in guard let self, self.recorder === recorder else { return }; self.abort() } }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { Task { @MainActor [weak self] in guard let self, self.player === player else { return }; self.cancel() } }
}
/// Takes live only between start and finish/cancel. A take orphaned by a crash or a killed
/// process is swept before the next recording; anything younger than `age` may still be live.
enum MerchantNPCVoiceTemporaryFiles {
    static let prefix = "merchant-voice-"
    static func make(in directory: URL) -> URL { directory.appendingPathComponent("\(prefix)\(UUID().uuidString).m4a") }
    static func sweep(in directory: URL, now: Date = Date(), age: TimeInterval = 15 * 60, files: FileManager = .default) {
        guard let entries = try? files.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        for url in entries where url.lastPathComponent.hasPrefix(prefix) && url.pathExtension == "m4a" {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if now.timeIntervalSince(modified) >= age { try? files.removeItem(at: url) }
        }
    }
}

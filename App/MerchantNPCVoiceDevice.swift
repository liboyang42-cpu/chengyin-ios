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
    private var observer: NSObjectProtocol?
    private var generation = 0
    private var sessionActive = false
    init(enabled: @escaping () -> Bool = { false }) { self.enabled = enabled; super.init() }
    func start(configuration: MerchantNPCVoiceConfiguration, interrupted: @escaping () -> Void) async throws {
        guard enabled(), recorder == nil else { throw MerchantNPCFailure.disabled }
        cancel(); let stamp = generation
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
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("merchant-voice-\(UUID().uuidString).m4a")
            file = url
            let value = try AVAudioRecorder(url: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: configuration.sampleRate, AVNumberOfChannelsKey: configuration.channels, AVEncoderBitRateKey: configuration.bitRate])
            recorder = value; value.delegate = self
            observer = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { [weak self] _ in
                Task { @MainActor in guard let self, self.generation == stamp else { return }; self.abort() }
            }
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
            observer = NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: session, queue: .main) { [weak self] _ in Task { @MainActor in guard let self, self.generation == stamp else { return }; self.abort() } }
            guard value.play() else { throw MerchantNPCFailure.invalid }
        } catch { cancel(); throw error }
    }
    private func abort() { let callback = interrupted; cancel(); callback?() }
    func cancel() {
        generation += 1
        let usedSession = sessionActive; sessionActive = false
        recorder?.delegate = nil; recorder?.stop(); recorder = nil; player?.delegate = nil; player?.stop(); player = nil
        if let file { try? FileManager.default.removeItem(at: file) }; file = nil; configuration = nil; interrupted = nil
        if let observer { NotificationCenter.default.removeObserver(observer) }; observer = nil
        if usedSession { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    }
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) { Task { @MainActor [weak self] in guard let self, self.recorder === recorder else { return }; self.abort() } }
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) { Task { @MainActor [weak self] in guard let self, self.recorder === recorder else { return }; self.abort() } }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { Task { @MainActor [weak self] in guard let self, self.player === player else { return }; self.cancel() } }
}

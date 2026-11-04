import Foundation
import AVFoundation

/// Constructing this device does not record, play, request permission, or activate audio.
@MainActor final class IMVoiceDevice: NSObject, AVAudioRecorderDelegate, AVAudioPlayerDelegate {
    private let enabled: () -> Bool
    private let lifecycle = NativeAudioLifecycleObservation(notifications: .default)
    private var recorder: AVAudioRecorder?
    private var player: AVAudioPlayer?
    private var url: URL?
    private var meterTask: Task<Void, Never>?
    private var points: [UInt8] = []
    private var generation = 0
    private var active = false
    private var finished: ((Result<IMVoiceClip, Error>) -> Void)?
    private var interrupted: (() -> Void)?
    init(enabled: @escaping () -> Bool = { false }) { self.enabled = enabled; super.init() }

    /// Only an explicit Record action may call this method.
    func record(finished: @escaping (Result<IMVoiceClip, Error>) -> Void, interrupted: @escaping () -> Void) async throws {
        guard enabled(), recorder == nil else { throw IMVoiceFailure.unavailable }
        cancel(); let stamp = generation
        let session = AVAudioSession.sharedInstance()
        let allowed: Bool
        switch session.recordPermission {
        case .granted: allowed = true
        case .denied: allowed = false
        default: allowed = await withCheckedContinuation { continuation in session.requestRecordPermission { continuation.resume(returning: $0) } }
        }
        guard allowed, enabled(), generation == stamp, !Task.isCancelled else { throw IMVoiceFailure.unavailable }
        do {
            try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
            try session.setActive(true); active = true
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("im-voice-takes", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
            // Only our stale transient files, not another producer's media or recovery data.
            for item in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
                if item.pathExtension == "m4a", let modified = try? item.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate,
                   Date().timeIntervalSince(modified) > 86_400 { try? FileManager.default.removeItem(at: item) }
            }
            let target = directory.appendingPathComponent(UUID().uuidString + ".m4a"); url = target
            let value = try AVAudioRecorder(url: target, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 48_000])
            recorder = value; value.delegate = self; value.isMeteringEnabled = true
            self.finished = finished; self.interrupted = interrupted; points = []
            observe(category: .playAndRecord, stamp: stamp)
            guard value.record(forDuration: 60) else { throw IMVoiceFailure.invalid }
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: target.path)
            meterTask = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    guard !Task.isCancelled, let self, self.generation == stamp, let recorder = self.recorder, recorder.isRecording else { return }
                    recorder.updateMeters()
                    let amplitude = min(1, max(0, pow(10, Double(recorder.averagePower(forChannel: 0)) / 20)))
                    self.points.append(UInt8((amplitude * 255).rounded()))
                }
            }
        } catch { cancel(); throw error }
    }
    func finish() {
        guard enabled(), let recorder, let url else { cancel(); return }
        let callback = finished
        recorder.delegate = nil; recorder.stop(); meterTask?.cancel(); meterTask = nil
        do {
            let audio = try AVAudioFile(forReading: url)
            guard audio.fileFormat.sampleRate == 16_000, audio.fileFormat.channelCount == 1 else { throw IMVoiceFailure.invalid }
            let duration = Double(audio.length) / audio.fileFormat.sampleRate
            let count = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
            guard duration > 0, duration <= 60, count > 0, count <= 2 * 1024 * 1024, !points.isEmpty else { throw IMVoiceFailure.invalid }
            let measured = Int((duration * 1000).rounded())
            let waveform = (0..<min(256, points.count)).map { index -> UInt8 in
                let lo = index * points.count / min(256, points.count)
                let hi = (index + 1) * points.count / min(256, points.count)
                return points[lo..<max(lo + 1, hi)].max() ?? 0
            }
            let clip = try IMVoiceClip(bytes: Data(contentsOf: url), waveform: Data(waveform), durationMS: measured)
            cancel(); callback?(.success(clip))
        } catch { cancel(); callback?(.failure(error)) }
    }
    /// Caller supplies bytes only after current original message/asset authorization.
    func play(_ bytes: Data, interrupted: @escaping () -> Void) throws {
        guard enabled(), !bytes.isEmpty, bytes.count <= 2 * 1024 * 1024, recorder == nil else { throw IMVoiceFailure.unavailable }
        cancel(); let stamp = generation
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio); try session.setActive(true); active = true
            let value = try AVAudioPlayer(data: bytes)
            guard value.duration > 0, value.duration <= 60 else { throw IMVoiceFailure.invalid }
            player = value; value.delegate = self; self.interrupted = interrupted
            observe(category: .playback, stamp: stamp)
            guard value.play() else { throw IMVoiceFailure.invalid }
        } catch { cancel(); throw error }
    }
    private func observe(category: AVAudioSession.Category, stamp: Int) {
        lifecycle.observe { [weak self] signal in
            guard let self, self.generation == stamp,
                  PlatformAudioLifecyclePolicy.action(for: signal, ownsConfiguration: AVAudioSession.sharedInstance().category == category) == .stop else { return }
            let callback = self.interrupted; self.cancel(); callback?()
        }
    }
    func cancel() {
        generation += 1; meterTask?.cancel(); meterTask = nil
        recorder?.delegate = nil; recorder?.stop(); recorder = nil
        player?.delegate = nil; player?.stop(); player = nil
        if let url { try? FileManager.default.removeItem(at: url) }; url = nil
        points = []; finished = nil; interrupted = nil; lifecycle.invalidate()
        if active { active = false; try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    }
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.recorder === recorder else { return }
            if flag { self.finish() } else { let callback = self.finished; self.cancel(); callback?(.failure(IMVoiceFailure.invalid)) }
        }
    }
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor [weak self] in
            guard let self, self.recorder === recorder else { return }
            let callback = self.finished; self.cancel(); callback?(.failure(IMVoiceFailure.invalid))
        }
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in guard let self, self.player === player else { return }; self.cancel() }
    }
}

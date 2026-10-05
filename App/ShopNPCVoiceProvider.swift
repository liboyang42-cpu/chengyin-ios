import Foundation
import AVFoundation

@MainActor protocol ShopNPCVoiceCapturing: AnyObject {
    func startAfterExplicitMicrophoneIntent(grants: ShopNPCGrants, onEnded: @escaping () -> Void) throws
    func stopForReview() throws -> ShopNPCVoiceClip
    func cancel()
}
/// Concrete OS seam, never constructed by default. No implicit permission request or upload.
/// The host obtains system permission only after explaining recording, then injects this provider.
@MainActor final class ShopNPCAVCapture: ShopNPCVoiceCapturing {
    private var recorder: AVAudioRecorder?
    private var file: URL?
    private var started: Date?
    private var deadline: Task<Void, Never>?
    private var ended: (() -> Void)?
    func startAfterExplicitMicrophoneIntent(grants: ShopNPCGrants, onEnded: @escaping () -> Void) throws {
        guard grants.voiceAllowed, grants.microphone, recorder == nil,
              AVAudioSession.sharedInstance().recordPermission == .granted else { throw ShopNPCFailure.disabled }
        ended = onEnded
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("shop-npc-\(UUID().uuidString).m4a")
        do {
            try AVAudioSession.sharedInstance().setCategory(.record, mode: .spokenAudio)
            try AVAudioSession.sharedInstance().setActive(true)
            let value = try AVAudioRecorder(url: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 16000, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 32000])
            file = url; recorder = value; started = Date()
            guard value.record(forDuration: 60) else { throw ShopNPCFailure.invalid }
            deadline = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard !Task.isCancelled else { return }
                self?.cancel() // Timed-out audio is discarded, never automatically transmitted.
            }
        } catch { cancel(); throw error }
    }
    func stopForReview() throws -> ShopNPCVoiceClip {
        guard let recorder, let file, let started else { throw ShopNPCFailure.invalid }
        recorder.stop()
        defer { cancel() }
        return try ShopNPCVoiceClip(bytes: Data(contentsOf: file), duration: min(60, Date().timeIntervalSince(started)))
    }
    func cancel() {
        deadline?.cancel(); deadline = nil; recorder?.stop(); recorder = nil; started = nil
        if let file { try? FileManager.default.removeItem(at: file) }; file = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        let callback = ended; ended = nil; callback?()
    }
}
@MainActor protocol ShopNPCPlayback {
    func stop()
    func play(source: ShopNPCAudioSource, grants: ShopNPCGrants) throws
}
/// No source-backed playable response exists; never derive a URL or enable TTS from reply text.
@MainActor struct ShopNPCUnavailablePlayback: ShopNPCPlayback {
    func stop() {}
    func play(source: ShopNPCAudioSource, grants: ShopNPCGrants) throws { throw ShopNPCFailure.disabled }
}

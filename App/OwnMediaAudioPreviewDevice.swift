import Foundation
import AVFoundation
import UIKit

@MainActor protocol OwnMediaAudioMemoryPlaying: AnyObject {
    var delegate: (any AVAudioPlayerDelegate)? { get set }
    var duration: TimeInterval { get }
    var currentTime: TimeInterval { get set }
    var numberOfChannels: Int { get }
    var ownMediaSampleRate: Double { get }
    func prepareToPlay() -> Bool
    func play() -> Bool
    func pause()
    func stop()
}
extension AVAudioPlayer: OwnMediaAudioMemoryPlaying {
    var ownMediaSampleRate: Double { format.sampleRate }
}
@MainActor protocol OwnMediaAudioPreviewPlaying: AnyObject {
    var position: TimeInterval { get }
    func prepare(_ bytes: Data, current: @escaping () -> Bool, event: @escaping (OwnMediaAudioPreviewDeviceEvent) -> Void) throws -> TimeInterval
    func play() throws
    func pause()
    func seek(_ time: TimeInterval) throws
    func stop()
}
enum OwnMediaAudioPreviewDeviceEvent: Equatable { case ended, failed, interrupted }
@MainActor struct OwnMediaAudioPreviewDeviceDependencies {
    let notifications: NotificationCenter
    let makePlayer: (Data) throws -> any OwnMediaAudioMemoryPlaying
    let permitsPlayback: () -> Bool
    static var live: Self {
        .init(notifications: .default, makePlayer: { try AVAudioPlayer(data: $0) }, permitsPlayback: {
            // Read current category only. Never seize/deactivate another producer's session.
            let category = AVAudioSession.sharedInstance().category
            return category == .ambient || category == .soloAmbient || category == .playback
        })
    }
}
/// Private memory bytes only; no URL, recording, session setters, or shared audio driver.
@MainActor final class OwnMediaAudioPreviewDevice: NSObject, OwnMediaAudioPreviewPlaying, AVAudioPlayerDelegate {
    private let dependencies: OwnMediaAudioPreviewDeviceDependencies
    private let lifecycle: NativeAudioLifecycleObservation
    private var player: (any OwnMediaAudioMemoryPlaying)?
    private var current: (() -> Bool)?
    private var event: ((OwnMediaAudioPreviewDeviceEvent) -> Void)?
    private var generation = UUID()
    var position: TimeInterval { player?.currentTime ?? 0 }
    override convenience init() { self.init(dependencies: .live) }
    init(dependencies: OwnMediaAudioPreviewDeviceDependencies) {
        self.dependencies = dependencies
        // NativeAudioLifecycleObservation registers queue .main. Deliver stop synchronously
        // on that queue, including background, instead of waiting for a SwiftUI redraw.
        lifecycle = .init(notifications: dependencies.notifications, enqueue: { operation in
            MainActor.assumeIsolated { operation() }
        })
        super.init()
    }
    func prepare(_ bytes: Data, current: @escaping () -> Bool, event: @escaping (OwnMediaAudioPreviewDeviceEvent) -> Void) throws -> TimeInterval {
        stop(); let stamp = generation
        guard OwnMediaAudioBytes.accepts(bytes), current(), generation == stamp else { throw OwnMediaAudioPreviewFailure.unavailable }
        let candidate = try dependencies.makePlayer(bytes)
        guard candidate.duration.isFinite, candidate.duration > 0, candidate.duration < TimeInterval(Int.max), (1...8).contains(candidate.numberOfChannels),
              candidate.ownMediaSampleRate.isFinite, candidate.ownMediaSampleRate > 0, candidate.ownMediaSampleRate <= 192_000,
              current(), generation == stamp, player == nil else { candidate.stop(); throw OwnMediaAudioPreviewFailure.invalidResponse }
        player = candidate; self.current = current; self.event = event; candidate.delegate = self
        lifecycle.observe { [weak self] signal in
            guard let self, self.generation == stamp else { return }
            // No category belongs to this adapter. Even a category/new-route change stops it.
            guard PlatformAudioLifecyclePolicy.action(for: signal, ownsConfiguration: false) == .stop else { return }
            self.finish(.interrupted)
        }
        return candidate.duration // Preparing a presentation never calls play/prepareToPlay.
    }
    private func retireIfCurrent(_ stamp: UUID, _ candidate: any OwnMediaAudioMemoryPlaying) {
        guard generation == stamp, player === candidate else { return }; stop()
    }
    func play() throws {
        guard let candidate = player else { throw OwnMediaAudioPreviewFailure.unavailable }; let stamp = generation
        guard current?() == true, dependencies.permitsPlayback(), generation == stamp, player === candidate else {
            retireIfCurrent(stamp, candidate); throw OwnMediaAudioPreviewFailure.unavailable
        }
        if candidate.currentTime >= candidate.duration { candidate.currentTime = 0 }
        let prepared = candidate.prepareToPlay()
        guard generation == stamp, player === candidate else { throw OwnMediaAudioPreviewFailure.stale }
        guard prepared, current?() == true, generation == stamp, player === candidate else {
            retireIfCurrent(stamp, candidate); throw OwnMediaAudioPreviewFailure.invalidResponse
        }
        let started = candidate.play()
        guard generation == stamp, player === candidate else { throw OwnMediaAudioPreviewFailure.stale }
        guard started, current?() == true else { retireIfCurrent(stamp, candidate); throw OwnMediaAudioPreviewFailure.invalidResponse }
    }
    func pause() {
        guard let candidate = player else { return }; let stamp = generation
        guard current?() == true, generation == stamp, player === candidate else { retireIfCurrent(stamp, candidate); return }
        candidate.pause()
    }
    func seek(_ time: TimeInterval) throws {
        guard let candidate = player else { throw OwnMediaAudioPreviewFailure.stale }; let stamp = generation
        guard time.isFinite, time >= 0, current?() == true, generation == stamp, player === candidate,
              time <= candidate.duration else { throw OwnMediaAudioPreviewFailure.stale }
        candidate.currentTime = time
    }
    func stop() {
        generation = UUID(); lifecycle.invalidate()
        let old = player; player = nil; current = nil; event = nil; old?.delegate = nil; old?.stop()
    }
    private func finish(_ result: OwnMediaAudioPreviewDeviceEvent) {
        let callback = event; stop(); callback?(result)
    }
    func receiveCompletion(from candidate: any OwnMediaAudioMemoryPlaying, succeeded: Bool) {
        guard player === candidate else { return }; finish(succeeded ? .ended : .failed)
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self, weak player] in
            guard let self, let player else { return }; self.receiveCompletion(from: player, succeeded: flag)
        }
    }
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor [weak self, weak player] in
            guard let self, let player else { return }; self.receiveCompletion(from: player, succeeded: false)
        }
    }
}

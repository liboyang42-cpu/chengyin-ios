import Foundation
import Observation

/// Playback is presentation-only. This module deliberately exposes no gameplay proof or completion callback.
public struct PlatformMediaSource: Equatable, Sendable {
    public let url: URL
    public let scope: UUID
    public init(url: URL, scope: UUID) { self.url = url; self.scope = scope }
}
public struct PlatformMediaPolicy: Sendable {
    public let approvedOrigins: Set<String>
    public init(approvedOrigins: Set<String> = []) { self.approvedOrigins = approvedOrigins }
    public func allows(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased(),
              url.user == nil, url.password == nil, url.fragment == nil else { return false }
        let origin = "https://" + host + (url.port.map { $0 == 443 ? "" : ":\($0)" } ?? "")
        return approvedOrigins.contains(origin)
    }
}
public enum PlatformAudioState: Equatable, Sendable { case gated, idle, loading, playing, paused, ended, failed, disposed }
public enum PlatformAudioEvent: Sendable { case playing, ended, failed, interrupted }
@MainActor public protocol PlatformAudioDriving: AnyObject {
    func start(source: PlatformMediaSource, policy: PlatformMediaPolicy, event: @escaping @MainActor (PlatformAudioEvent) -> Void)
    func pause()
    func resume()
    func stop()
}
@MainActor @Observable public final class PlatformAudioPlayback {
    public private(set) var state: PlatformAudioState = .gated
    public private(set) var source: PlatformMediaSource?
    private let driver: any PlatformAudioDriving
    private let policy: PlatformMediaPolicy
    private let enabled: Bool
    private var generation = 0
    private var consentedSource: PlatformMediaSource?
    public init(driver: any PlatformAudioDriving, policy: PlatformMediaPolicy = .init(), enabled: Bool = false) {
        self.driver = driver; self.policy = policy; self.enabled = enabled
    }
    public func select(_ source: PlatformMediaSource?) {
        guard self.source != source, state != .disposed else { return }
        invalidate(); self.source = source; consentedSource = nil
        state = enabled && source.map { policy.allows($0.url) } == true ? .idle : .gated
    }
    /// Must follow explicit review of this exact URL/origin and session/region scope.
    public func approveSelectedMedia() { if state != .disposed { consentedSource = source } }
    public func toggle() {
        guard state != .disposed, enabled, let source, consentedSource == source, policy.allows(source.url) else { return }
        if state == .loading { return }
        if state == .playing { driver.pause(); state = .paused; return }
        if state == .paused { state = .loading; driver.resume(); return }
        invalidate(); state = .loading
        let token = generation
        driver.start(source: source, policy: policy) { [weak self] event in
            guard let self, self.generation == token, self.source == source, self.state != .disposed else { return }
            switch event {
            case .playing: self.state = .playing
            case .ended: self.invalidate(); self.state = .ended
            case .failed: self.invalidate(); self.state = .failed
            case .interrupted: self.invalidate(); self.state = .idle
            }
        }
    }
    /// Navigation, account/region/source changes and backgrounding invalidate late callbacks and consent.
    public func suspend() {
        guard state != .disposed else { return }
        invalidate(); consentedSource = nil; state = enabled && source.map { policy.allows($0.url) } == true ? .idle : .gated
    }
    public func dispose() { invalidate(); source = nil; consentedSource = nil; state = .disposed }
    private func invalidate() { generation += 1; driver.stop() }
}
@MainActor public final class SyntheticPlatformAudioDriver: PlatformAudioDriving {
    public private(set) var starts = 0
    public private(set) var stops = 0
    public var event: (@MainActor (PlatformAudioEvent) -> Void)?
    public init() {}
    public func start(source: PlatformMediaSource, policy: PlatformMediaPolicy, event: @escaping @MainActor (PlatformAudioEvent) -> Void) { starts += 1; self.event = event }
    public func pause() {}
    public func resume() { event?(.playing) }
    public func stop() { stops += 1; event = nil }
}

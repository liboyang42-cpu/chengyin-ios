import Foundation
import Observation

@MainActor public final class WorkshopPaidInstalledTextAppearance {
    fileprivate var started = false, closed = false
    fileprivate var action: WorkshopPaidInstalledTextAction?
    public init() {}
    fileprivate func begin() -> Bool { guard !started, !closed else { return false }; started = true; return true }
    fileprivate func revoke() { closed = true; action?.revoke(); action = nil }
}
@MainActor fileprivate final class WorkshopPaidInstalledTextAction {
    weak var appearance: WorkshopPaidInstalledTextAppearance?
    private var revoked = false, entered = false
    init(_ appearance: WorkshopPaidInstalledTextAppearance) { self.appearance = appearance }
    var live: Bool { !revoked && appearance?.closed == false && appearance?.action === self }
    func revoke() { revoked = true }
    func claim() -> Bool { guard live, !entered else { return false }; entered = true; return true }
}
/// Protected body exists only for a live read presentation. Closing/replacing clears it; queued
/// callbacks carry a one-use captured offer and cannot ask an old View for a newer permit.
@available(macOS 14.0, *)
@MainActor @Observable public final class WorkshopPaidInstalledTextController {
    public enum Phase: Equatable { case idle, loading, loaded, unavailable, invalidated }
    public typealias Action = @MainActor () async -> Void
    public let reference: WorkshopPaidInstalledTextReference
    public private(set) var phase: Phase = .idle
    public private(set) var content: WorkshopPaidInstalledText?
    public private(set) var issue: WorkshopPaidInstalledTextIssue?
    private let service: any WorkshopPaidInstalledTextReading
    private let lease: ContentDraftSessionLease
    private var appearance: WorkshopPaidInstalledTextAppearance?
    private var lifetime: WorkshopPaidInstalledTextLifetime?
    public init(reference: WorkshopPaidInstalledTextReference, service: any WorkshopPaidInstalledTextReading, lease: ContentDraftSessionLease) {
        self.reference = reference; self.service = service; self.lease = lease
    }
    public func invalidate() {
        guard phase != .invalidated else { return }
        appearance?.revoke(); appearance = nil; lifetime?.revoke(); lifetime = nil; lease.revoke()
        content = nil; phase = .invalidated; issue = .staleSession
    }
    private func current(_ displayed: WorkshopPaidInstalledTextAppearance) -> Bool {
        guard lease.isCurrent else { invalidate(); return false }
        return phase != .invalidated && appearance === displayed && !displayed.closed
    }
    public func appear(_ displayed: WorkshopPaidInstalledTextAppearance) -> Action? {
        guard lease.isCurrent, phase != .invalidated, displayed.begin() else { return nil }
        appearance?.revoke(); lifetime?.revoke(); appearance = displayed
        return offerReload(displayed)
    }
    public func close(_ displayed: WorkshopPaidInstalledTextAppearance) {
        displayed.revoke(); guard appearance === displayed else { return }
        lifetime?.revoke(); lifetime = nil; appearance = nil; content = nil; issue = nil
        if phase != .invalidated { phase = .idle }
    }
    public func offerReload(_ displayed: WorkshopPaidInstalledTextAppearance) -> Action? {
        guard current(displayed) else { return nil }
        displayed.action?.revoke(); lifetime?.revoke()
        let action = WorkshopPaidInstalledTextAction(displayed); displayed.action = action
        let life = WorkshopPaidInstalledTextLifetime { [weak self, weak displayed, weak action] in
            guard let self, let displayed, let action else { return false }
            return action.live && self.current(displayed)
        }
        lifetime = life; content = nil; issue = nil; phase = .loading
        return { [weak self] in
            guard let self, action.claim(), self.current(displayed) else { return }
            do {
                let body = try await self.service.detail(self.reference, lifetime: life)
                try life.check(); guard body.matches(self.reference) else { throw WorkshopPaidInstalledTextIssue.malformed }
                self.content = body; self.phase = .loaded
            } catch {
                guard action.live, self.current(displayed) else { return }
                self.content = nil; self.issue = (error as? WorkshopPaidInstalledTextIssue) ?? .unavailable; self.phase = .unavailable
            }
        }
    }
}

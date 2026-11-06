import Foundation
import Observation

/// Recovers only an already persisted original request. No command creation, POST or retry API.
@available(macOS 14.0, *) @MainActor @Observable public final class CityOrientationOriginalRecoveryHost {
    public enum Phase: Equatable { case idle, loading, approvalRequired, unknown, receipt, settled, unavailable, stale }
    public private(set) var phase: Phase = .idle
    public private(set) var issue: PlayExperienceError?
    private var owner: PlayExperienceSession?
    private var record: CityOrientationTaskPending?
    private var receipt: CityOrientationTaskReceipt?
    private var generation: UInt64 = 0
    private let scope: PlaySessionScope
    private let service: CityOrientationTaskService
    private let journal: CityOrientationTaskJournal
    private let currentSession: () -> PlayExperienceSession?
    private let onUnauthorized: (PlayExperienceSession) -> Void
    public init(scope: PlaySessionScope, service: CityOrientationTaskService, journal: CityOrientationTaskJournal,
                currentSession: @escaping () -> PlayExperienceSession?, onUnauthorized: @escaping (PlayExperienceSession) -> Void = { _ in }) {
        self.scope=scope;self.service=service;self.journal=journal;self.currentSession=currentSession;self.onUnauthorized=onUnauthorized
    }
    public var current: Bool { owner != nil && owner == currentSession() }
    public var visibleReceipt: CityOrientationTaskReceipt? { current ? receipt : nil }
    public var canAcknowledge: Bool { current && phase == .receipt && receipt != nil }
    private func binding(_ session: PlayExperienceSession) -> String {
        service.realm + ":" + PlayRunStorageKey.make(session: session, scope: scope)
    }
    public func invalidate() {
        generation &+= 1;owner=nil;record=nil;receipt=nil;issue=nil;phase = .stale
        // Never remove secure original evidence when an account, approval or view changes.
    }
    public func load() async {
        guard phase != .loading else { return }
        guard let session=currentSession() else { invalidate();return }
        if owner != nil && owner != session { invalidate();return }
        owner=session;generation &+= 1;let issued=generation
        receipt=nil;issue=nil;phase = .loading
        do {
            record=try journal.load(binding(session),owner:.init(session:session))
        } catch { phase = .unavailable;issue = .persistenceUnavailable;return }
        guard let pending=record else { phase = .idle;return }
        guard !pending.settled else { phase = .settled;return }
        guard service.receiptReadsEnabled, service.receiptSessionID == pending.command.sessionId else {
            phase = .approvalRequired;return
        }
        do {
            let original=try await service.original(pending.command,token:session.token)
            guard currentSession()==session, generation==issued else { return }
            guard let original else { phase = .unknown;return }
            var next=pending;next.receipt=original
            try journal.replace(next,expected:pending,binding:binding(session))
            record=next;receipt=original;phase = .receipt
        } catch {
            guard currentSession()==session, generation==issued else { return }
            if let error=error as? PlayExperienceError, error == .unauthorized {
                onUnauthorized(session);invalidate();return
            }
            issue=error as? PlayExperienceError ?? .unknownResult
            phase = .unknown
        }
    }
    /// Explicit local acknowledgment, only after the real original receipt was fetched and persisted.
    public func acknowledge() throws {
        guard canAcknowledge, let session=owner, var next=record, let receipt,
              next.receipt==receipt else { throw PlayExperienceError.staleSession }
        let previous=next;next.settled=true
        do { try journal.replace(next,expected:previous,binding:binding(session)) }
        catch { issue = .persistenceUnavailable;phase = .unavailable;throw error }
        record=next;phase = .settled
    }
}

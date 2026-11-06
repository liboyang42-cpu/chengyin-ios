import Foundation
import Observation

/// Latest user-info request owns its avatar. An old retry cannot repaint a newer refresh.
@MainActor @Observable final class MemberIdentityCardReadOwner {
    struct Run: Equatable { let revision: UUID, scope: UUID, started: ContinuousClock.Instant }
    private var run: Run?
    private var mounted = false, active = false
    func appear(active: Bool) { mounted = true; self.active = active }
    func scene(active: Bool) { self.active = mounted && active; if !self.active { invalidate() } }
    func disappear() { mounted = false; active = false; invalidate() }
    private(set) var observation: MemberIdentityAvatarObservation?
    private let lifetime = MemberIdentityAvatarLifetime()
    func begin(scope: UUID) -> Run? {
        guard mounted, active else { return nil }
        invalidate(); let value = Run(revision: UUID(), scope: scope, started: ContinuousClock().now); run = value; return value
    }
    func accepts(_ value: Run, scope: UUID) -> Bool { mounted && active && run == value && value.scope == scope }
    func publish(_ snapshot: MemberIdentitySnapshot, run value: Run, scope: UUID) {
        guard accepts(value, scope: scope) else { return }
        lifetime.retireAll()
        observation = .init(snapshot: snapshot, scope: scope, readRevision: value.revision, requestStarted: value.started)
    }
    func register(_ reader: MemberIdentityAvatarReader) { lifetime.register(reader) }
    func invalidate() { run = nil; observation = nil; lifetime.retireAll() }
    func invalidate(_ value: Run) { if run == value { invalidate() } }
}

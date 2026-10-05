import Foundation

/// Immutable child-runtime lifetime issued by the authoritative nodes reader.
/// A retained coordinator/service can never be rebound by a later View render.
@MainActor public final class PlayInteractionLifetime {
    public let identity: String
    private let context: PlayInteractionContext
    private let current: () -> PlayInteractionContext?
    private let onRetired: () -> Void
    private var retired = false
    init(context: PlayInteractionContext, current: @escaping () -> PlayInteractionContext?, onRetired: @escaping () -> Void) {
        self.context = context; self.current = current; self.onRetired = onRetired; identity = context.lifetimeIdentity
    }
    public var isCurrent: Bool { !retired && current() == context }
    func checkReturnedMode(_ value: Int?) throws {
        try check()
        guard PlayGameplayMode(serverValue: value) == context.authoritativeMode else {
            // A contradictory child read withdraws the whole issued authority.
            // Throwing alone would leave sibling services bound to a live lease.
            retired = true; onRetired()
            throw PlayExperienceError.staleSession
        }
    }
    public func check() throws {
        guard isCurrent else { throw PlayExperienceError.staleSession }
        try Task.checkCancellation()
    }
}

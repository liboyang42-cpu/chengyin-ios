import Foundation

/// Mini pages/play team-progress polling cadence and stop rule. Polling is a
/// read of the existing GET only; it never grants or replays a leader command.
public enum PlayLeadProgressPolling {
    public static let intervalNanoseconds: UInt64 = 4_000_000_000
    /// Mini stops on exists=false and only starts after a read reported a team.
    public static func continues(lead: PlayLeadProgress?) -> Bool { lead?.exists == true }
    /// A host restarts its poll task whenever the rendered authority or visibility changes.
    public struct Key: Equatable {
        public let context: PlayInteractionContext?
        public let active: Bool
        public init(context: PlayInteractionContext?, lead: PlayLeadProgress?, sceneActive: Bool) {
            self.context = context; active = sceneActive && context != nil && PlayLeadProgressPolling.continues(lead: lead)
        }
    }
}

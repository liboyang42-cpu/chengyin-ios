import Foundation

/// A read-only public-profile reference from the supplied runner memberId.
/// The receipt does not retain the runner's coordinates, distances or statistics,
/// and the destination callback receives only memberID. No social write grant.
public struct RoamPlayerProfileSelection: Identifiable, Hashable {
    public let id = UUID()
    public let memberID: Int
    private let origin: RoamEventNavigationScope
    public init?(player: RoamPlayer, currentPlayer: RoamPlayer?, rendered: RoamEventNavigationScope?, current: RoamEventNavigationScope?) {
        guard player.id > 0, player == currentPlayer, let rendered, rendered == current else { return nil }
        memberID = player.id; origin = rendered
    }
    public func mayRemainOpen(in current: RoamEventNavigationScope?) -> Bool {
        guard let current else { return false }
        return origin.readerID == current.readerID && origin.identity == current.identity && origin.area == current.area
    }
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

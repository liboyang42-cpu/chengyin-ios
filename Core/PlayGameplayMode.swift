import Foundation

/// Only the current authorized nodes response selects gameplay. ACTIVITY/TOPIC
/// entry scope, creator labels and permanent CITY/MAP are separate identities.
public enum PlayGameplayMode: Int, Codable, Equatable, Sendable {
    case cityOrientation = 1
    case freeExploration = 2
    public init?(serverValue: Int?) {
        guard let serverValue, let mode = Self(rawValue: serverValue) else { return nil }
        self = mode
    }
}

/// Store cards retain exact server order and identity. No fixed card count,
/// ordered stop, run clock or local redemption is inferred.
public struct FreeExplorationPresentation: Equatable {
    public let stores: [PlayNode]
    public let redeemed: Int?
    public let total: Int?
    public let isFullyRedeemed: Bool
    public init?(snapshot: PlaySnapshot) {
        guard PlayGameplayMode(serverValue: snapshot.result.mode) == .freeExploration else { return nil }
        stores = snapshot.availability == .registrationRequired ? [] : snapshot.visibleNodes
        if let total = snapshot.result.total, let redeemed = snapshot.displayedDoneCount,
           total > 0, (0...total).contains(redeemed) {
            self.total = total; self.redeemed = redeemed
            isFullyRedeemed = redeemed == total && !stores.isEmpty && stores.allSatisfy(snapshot.isDone)
        } else { self.total = nil; self.redeemed = nil; isFullyRedeemed = false }
    }
    /// Arrival precedes an optional in-store game. Missing game state never
    /// borrows a city-orientation answer/sensor/route-completion command.
    public static func evidenceTask(for node: PlayNode, in snapshot: PlaySnapshot) -> PlayNodeTask? {
        guard snapshot.result.mode == 2, snapshot.availability == .active,
              snapshot.visibleNodes.contains(node), !snapshot.isLocked(node), node.done == false,
              snapshot.route?.isBranch != true else { return nil }
        if node.arrived == false { return .merchantScan }
        if node.arrived == true, node.selfReported == false,
           node.hasGame == false || (node.hasGame == true && node.gameDone == true) { return .merchantPhoto }
        return nil
    }
    public enum StoreState: String, Equatable {
        case unavailable, redeemed, proofRecorded, arrived, available, unknown
        public var titleKey: String { "playFree.store." + rawValue }
    }
    public static func state(of node: PlayNode, in snapshot: PlaySnapshot) -> StoreState {
        guard snapshot.result.mode == 2, snapshot.visibleNodes.contains(node) else { return .unavailable }
        if snapshot.isDone(node) { return .redeemed }
        if snapshot.isLocked(node) { return .unavailable }
        if node.selfReported == true { return .proofRecorded }
        if node.arrived == true { return .arrived }
        return node.done == false ? .available : .unknown
    }
}

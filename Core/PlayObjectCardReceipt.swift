import Foundation

/// Optional, one-shot evidence from advanced/action. A malformed card must never
/// undo the already committed game result. No card is inferred from `passed`.
public enum PlayObjectCardReceiptDecoder {
    public static func decode(_ value: PlayWireValue) -> ObjectCard? {
        guard let fields = value.object,
              let title = fields["title"]?.text, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              title.utf16.count <= 256 else { return nil }
        let id = fields["id"]?.text ?? fields["id"]?.integer.map(String.init) ?? ""
        guard id.range(of: "^[1-9][0-9]{0,18}$", options: .regularExpression) != nil else { return nil }
        for key in ["sourceUrl", "cutoutUrl", "caption", "category", "place", "cardStyle", "genStatus"] {
            if let raw = fields[key], raw != .null {
                guard let text = raw.text, text.utf16.count <= 4096 else { return nil }
            }
        }
        if let raw = fields["frames"], raw != .null {
            guard let frames = raw.array, frames.count <= 72,
                  frames.allSatisfy({ $0.text.map { $0.utf16.count <= 2048 } == true }) else { return nil }
        }
        guard let bytes = try? JSONEncoder().encode(value), bytes.count <= 96 * 1024 else { return nil }
        return try? JSONDecoder().decode(ObjectCard.self, from: bytes)
    }
}

public struct PlayObjectCardReceipt: Equatable {
    public let card: ObjectCard
    public let sessionID: Int; public let nodeID: Int; public let version: Int
    let owner: PlayExperienceSession
}

/// Ephemeral, owner-bound fact cache. A state refresh normally omits the receipt;
/// it may preserve a prior fact, but can never create one or change its identity.
public struct PlayObjectCardReceiptCache {
    public private(set) var receipt: PlayObjectCardReceipt?
    public init() {}
    public mutating func clear() { receipt = nil }
    public mutating func reconcile(_ state: PlayAdvancedState, owner: PlayExperienceSession) {
        guard let prior = receipt else { return }
        guard prior.owner == owner, prior.sessionID == state.sessionID, prior.nodeID == state.nodeID,
              state.version >= prior.version, Self.authorizesCard(state) else { clear(); return }
    }
    public mutating func accept(_ state: PlayAdvancedState, owner: PlayExperienceSession,
                                pending: PlayAdvancedPending, requestedCard: Bool) {
        reconcile(state, owner: owner)
        guard requestedCard, pending.action == "SUBMIT_PHOTO_CHECK", pending.sessionID == state.sessionID,
              state.version > pending.version, Self.authorizesCard(state), let card = state.objectCard else { return }
        // An exact idempotent replay or subsequent refresh must not replace a
        // previously revealed card. A new owner/run needs a fresh cache scope.
        guard receipt == nil else { return }
        receipt = .init(card: card, sessionID: state.sessionID, nodeID: state.nodeID, version: state.version, owner: owner)
    }
    private static func authorizesCard(_ state: PlayAdvancedState) -> Bool {
        let photo = state.playKit["photoCheck"]
        return ["RUNNING", "COMPLETED"].contains(state.status) && photo["mode"].text == "CARD"
            && photo["passed"].bool == true && photo["degraded"].bool != true
    }
}

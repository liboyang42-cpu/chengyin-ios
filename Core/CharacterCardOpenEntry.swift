import Foundation

/// Opens one existing character-card read and reads that same card back.
/// The request id and activity id of this open are returned unchanged.
/// A different activity id, a different request id, or a stale issuance is not this card.
/// The issuance is the caller's existing read issuance. This entry creates no player
/// command, no read grant, and no receipt store.
@available(macOS 14.0, *)
@MainActor public struct CharacterCardOpenEntry {
    public struct Read: Equatable {
        public let requestID: String
        public let activityID: Int
        public let card: CharacterCard
    }

    public let requestID: String
    public let activityID: Int
    public let issuance: UUID
    private let model: CharacterCardReadback

    public init?(model: CharacterCardReadback, requestID: String, activityID: Int, issuance: UUID) {
        guard requestID == requestID.trimmingCharacters(in: .whitespacesAndNewlines), !requestID.isEmpty,
              activityID > 0, model.activityID == activityID else { return nil }
        if let bound = model.originalRequestID, bound != requestID { return nil }
        self.model = model
        self.requestID = requestID
        self.activityID = activityID
        self.issuance = issuance
    }

    /// Loads the existing character card, then reads this open back.
    public func open() async -> Read? {
        await model.load()
        return readBack(requestID: requestID, activityID: activityID, issuance: issuance)
    }

    /// Reads this card back. The stored request id and activity id are returned as stored.
    /// A different activity id or a stale issuance is not this card. This does not reload.
    public func readBack(requestID: String, activityID: Int, issuance: UUID) -> Read? {
        guard issuance == self.issuance else { return nil }
        guard requestID == self.requestID, activityID == self.activityID, model.activityID == self.activityID else { return nil }
        guard let card = model.cardIfCurrent() else { return nil }
        if let bound = card.originalRequestID ?? model.originalRequestID, bound != self.requestID { return nil }
        guard let activity = model.activityID else { return nil }
        return Read(requestID: self.requestID, activityID: activity, card: card)
    }
}

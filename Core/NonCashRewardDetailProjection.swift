import Foundation

/// Read facts remain distinct from qualification, issuance or redemption authority.
public struct NonCashRewardDetailProjection: Equatable, Sendable {
    public enum FactAvailability: Equatable, Sendable { case notProvided }
    public struct Origin: Equatable, Sendable {
        public let contextType: NonCashReward.Context
        public let contextId, releaseId, instanceId, rulesVersion: String
    }
    public let reward: NonCashReward
    public let origin: Origin
    public let qualification: FactAvailability = .notProvided
    public let claimProgress: FactAvailability = .notProvided
    public let allocation: FactAvailability = .notProvided
    public let sourceEvent: FactAvailability = .notProvided
    public init(reward: NonCashReward, previous: NonCashRewardReference) throws {
        let old = previous.snapshot
        guard reward.asOf >= old.asOf, old.state == .awarded || reward.state == old.state,
              reward.awardId == old.awardId, reward.contextType == old.contextType,
              reward.contextId == old.contextId, reward.releaseId == old.releaseId,
              reward.instanceId == old.instanceId, reward.rulesVersion == old.rulesVersion,
              reward.merchantId == old.merchantId, reward.storeId == old.storeId,
              reward.rewardTitle == old.rewardTitle, reward.quantity == old.quantity,
              reward.validFrom == old.validFrom, reward.validUntil == old.validUntil,
              reward.redemptionConditions == old.redemptionConditions, reward.awardedAt == old.awardedAt,
              reward.quantity == 1, reward.validFrom < reward.validUntil,
              reward.validityStatus == (reward.asOf < reward.validFrom ? .upcoming : reward.asOf >= reward.validUntil ? .elapsed : .inWindow)
        else { throw APIError.malformedResponse }
        self.reward = reward
        origin = Origin(contextType: reward.contextType, contextId: reward.contextId,
                        releaseId: reward.releaseId, instanceId: reward.instanceId, rulesVersion: reward.rulesVersion)
    }
}

/// Captured from an accepted row, never rebound to a deferred destination's live reader.
public struct NonCashRewardDetailSelection: Equatable, Identifiable, Sendable {
    public struct Identity: Hashable, Sendable {
        public let ownerScope: UUID
        public let awardId, contextType, contextId, releaseId, instanceId, rulesVersion: String
    }
    public let reference: NonCashRewardReference
    public let ownerScope: UUID
    public var id: Identity {
        Identity(ownerScope: ownerScope, awardId: reference.awardId, contextType: reference.contextType.rawValue,
                 contextId: reference.contextId, releaseId: reference.releaseId,
                 instanceId: reference.instanceId, rulesVersion: reference.snapshot.rulesVersion)
    }
    public init(reference: NonCashRewardReference, ownerScope: UUID) {
        self.reference = reference; self.ownerScope = ownerScope
    }
}

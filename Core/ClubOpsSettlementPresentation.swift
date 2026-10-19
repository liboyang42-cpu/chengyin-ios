import Foundation

/// Mini-program pages/club/settlement summary card. Amount text is server-formatted and never inferred.
public struct ClubOpsSettlementSummary: Equatable {
    /// nil when the server marked the settled total unverified.
    public let settledAmountText: String?
    public let unverifiedSettledCount: Int
    /// Only an explicit server `true` is the owner; anything else is treated as not the owner.
    public let isOwner: Bool
    public let hasTopics: Bool
    public init(value: ClubGovernanceValue, scope: ClubGovernanceScope) throws {
        let accepted = try ClubGovernanceValidation.validate(value, operation: .settlement, scope: scope)
        guard let missing = accepted["unverifiedSettledCount"].int, let topics = accepted["topics"].array else { throw ClubGovernanceFailure.malformed }
        settledAmountText = accepted["settledAmountStatus"] == .string("verified") ? accepted["settledAmountText"].string : nil
        unverifiedSettledCount = missing
        isOwner = accepted["isOwner"] == .bool(true)
        hasTopics = !topics.isEmpty
    }
}

public enum ClubOpsWithdrawHint: String, Equatable {
    case zero, unknown, ownerOnly
    public var localizationKey: String { "clubOps.settlement.withdraw." + rawValue }
    /// Owner availability comes from the existing wallet stages read; non-owners never read it.
    public init?(isOwner: Bool, availability: ClubOwnerFundsAvailability) {
        guard isOwner else { self = .ownerOnly; return }
        switch availability {
        case .zero: self = .zero
        case .unknown: self = .unknown
        case .positive: return nil
        }
    }
}

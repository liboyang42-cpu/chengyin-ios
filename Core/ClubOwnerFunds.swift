import Foundation

/// Current settlement ownership, not ClubRecord.isOwner or a wallet balance,
/// permits mounting the owner's existing wallet reader in this club context.
public struct ClubOwnerFundsTarget: Equatable {
    public let context: ClubGovernanceReadContext
    public let clubID: Int
    public let hasSettlementRows: Bool
    public init?(snapshot: ClubGovernanceSnapshot, context: ClubGovernanceReadContext) {
        guard context.operation == .settlement, context.accepts(snapshot),
              let id = context.scope.clubID, id > 0,
              context.scope == ClubGovernanceScope(clubID: id),
              (context.identity?.accountID ?? 0) > 0,
              snapshot.permissions?.allows(ClubGovernanceRead.settlement.permission, scope: context.scope) == true,
              snapshot.value["isOwner"] == .bool(true),
              (try? ClubGovernanceValidation.validate(snapshot.value, operation: .settlement, scope: context.scope)) != nil else { return nil }
        self.context = context; clubID = id
        hasSettlementRows = !(snapshot.value["topics"].array ?? []).isEmpty
    }
    public func accepts(_ snapshot: ClubGovernanceSnapshot) -> Bool {
        ClubOwnerFundsTarget(snapshot: snapshot, context: context) == self
    }
}

public enum ClubOwnerFundsAvailability: Equatable {
    case unknown, zero, positive
    public init(_ funds: WalletFundsStages?) {
        guard let funds, funds.amountsKnown else { self = .unknown; return }
        self = funds.withdrawable.value > 0 ? .positive : .zero
    }
}

/// Narrow view-facing read seam; it cannot grant a wallet lease or issue a payout.
@MainActor public protocol ClubOwnerFundsReading: AnyObject {
    var scope: WalletCommerceScope? { get }
    var isConfigured: Bool { get }
    func readClubOwnerFunds() async throws -> WalletFundsStages
}
extension WalletCommerceReader: ClubOwnerFundsReading {
    public func readClubOwnerFunds() async throws -> WalletFundsStages {
        try await read { try await $0.stages(token: $1) }
    }
}

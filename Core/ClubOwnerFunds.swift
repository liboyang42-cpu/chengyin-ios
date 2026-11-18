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

// MARK: - F11 自由探索结算（参考）· payer side

/// GET api/fe/reference-settlement/payer?activityId= (activity optional).
public struct FeReferencePayerQuery: Equatable {
    public let activityID: Int?
    public init(activityID: Int? = nil) throws {
        guard activityID == nil || activityID! > 0 else { throw CoopFlowFailure.invalid("activityId") }
        self.activityID = activityID
    }
    public var queryItems: [URLQueryItem] { activityID.map { [URLQueryItem(name: "activityId", value: String($0))] } ?? [] }
}
/// POST api/fe/reference-settlement/settle {ids, voucherNo?, note?}; payer only.
/// 「标记已线下结清」 records that money moved offline; the platform transfers nothing.
public struct FeReferenceSettleRequest: Equatable {
    public let ids: [Int]
    public let voucherNo: String?
    public let note: String?
    public init(rows: [FeReferenceSettlementRow], voucherNo: String? = nil, note: String? = nil) throws {
        let open = rows.filter { $0.status == .open }
        guard !open.isEmpty, open.count == rows.count else { throw CoopFlowFailure.invalid("settleRows") }
        var seen = Set<Int>()
        ids = open.map(\.id).filter { seen.insert($0).inserted }
        func clean(_ value: String?, limit: Int) throws -> String? {
            guard let text = value?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            guard text.count <= limit else { throw CoopFlowFailure.invalid("settleText") }
            return text
        }
        self.voucherNo = try clean(voucherNo, limit: 64); self.note = try clean(note, limit: 200)
    }
    public var body: CoopFlowJSON {
        var b: [String: CoopFlowJSON] = ["ids": .array(ids.map(CoopFlowJSON.id))]
        if let voucherNo { b["voucherNo"] = .string(voucherNo) }
        if let note { b["note"] = .string(note) }
        return .object(b)
    }
}
/// Rows a payer may select for 「标记已线下结清」: OPEN merchant rows only.
public enum FeReferencePayerActions {
    public static func settleable(_ list: FeReferenceSettlementList) -> [FeReferenceSettlementRow] {
        list.groups.flatMap(\.rows).filter { $0.status == .open && !$0.isAuthorSelfSupply }
    }
}

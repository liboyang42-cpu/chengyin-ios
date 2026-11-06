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

/// Mini-program `cy-club-direct-ledger` (`商家计酬`) presentation model.
/// Decodes and presents server-formatted merchant compensation rows without inventing amounts or adding unapproved reads.
public struct ClubDirectMerchantLedgerPresentation: Equatable {
    public static let sectionTitle = "商家计酬"
    public static let emptyCopy = "暂无商家计酬记录"

    public struct Row: Equatable, Identifiable {
        public let id: Int
        public let merchantName: String
        public let amountText: String
        public let statusLabel: String

        public init(id: Int, merchantName: String, amountText: String, statusLabel: String) throws {
            let trimmedName = merchantName.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedAmount = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
            let trimmedStatus = statusLabel.trimmingCharacters(in: .whitespacesAndNewlines)
            guard id > 0, !trimmedName.isEmpty, !trimmedAmount.isEmpty, !trimmedStatus.isEmpty else {
                throw ClubGovernanceFailure.malformed
            }
            self.id = id
            self.merchantName = trimmedName
            self.amountText = trimmedAmount
            self.statusLabel = trimmedStatus
        }

        public init(value: ClubGovernanceValue) throws {
            guard let id = value["id"].int, id > 0 else { throw ClubGovernanceFailure.malformed }
            let rawName = value["merchantName"].string ?? value["name"].string ?? ""
            let rawAmount = value["amountText"].string ?? value["settledAmountText"].string ?? ""
            let resolvedStatus: String
            if let label = value["statusLabel"].string?.trimmingCharacters(in: .whitespacesAndNewlines), !label.isEmpty {
                resolvedStatus = label
            } else if let code = (value["status"].string ?? value["statusCode"].string)?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
                switch code {
                case "SETTLED", "PAID", "CREDITED": resolvedStatus = "已入账"
                case "PENDING", "PROCESSING": resolvedStatus = "待结算"
                case "UNVERIFIED": resolvedStatus = "待核验"
                case "VOID", "CANCELLED": resolvedStatus = "已作废"
                default: throw ClubGovernanceFailure.malformed
                }
            } else {
                throw ClubGovernanceFailure.malformed
            }
            try self.init(id: id, merchantName: rawName, amountText: rawAmount, statusLabel: resolvedStatus)
        }
    }

    public let rows: [Row]
    public var isEmpty: Bool { rows.isEmpty }
    public var emptyText: String? { rows.isEmpty ? Self.emptyCopy : nil }

    public init(rows: [Row]) throws {
        guard Set(rows.map(\.id)).count == rows.count else { throw ClubGovernanceFailure.malformed }
        self.rows = rows
    }

    public init(value: ClubGovernanceValue) throws {
        let rawRows: [ClubGovernanceValue]
        if let array = value.array {
            rawRows = array
        } else if let object = value.object,
                  let array = (object["rows"] ?? object["items"] ?? object["records"] ?? object["data"])?.array {
            rawRows = array
        } else {
            throw ClubGovernanceFailure.malformed
        }
        let decoded = try rawRows.map(Row.init(value:))
        try self.init(rows: decoded)
    }
}

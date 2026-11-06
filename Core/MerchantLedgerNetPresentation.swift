import Foundation

/// P066 overviewRow semantics only. The server's net is not recomputed from other fields.
public struct MerchantLedgerNetPresentation: Equatable {
    public enum Kind: Equatable { case inflow, adjustment, pending }
    public let kind: Kind
    public let amount: String?
    public init(value: MerchantBusinessValue?) {
        guard let money = try? MerchantBusinessMoney(value, strictString: true), let raw = money.raw else {
            kind = .pending; amount = nil; return
        }
        // Validated decimal grammar; lexical sign avoids precision loss/overflow and treats -0 as zero.
        let nonzero = raw.utf8.contains { $0 >= 49 && $0 <= 57 }
        kind = raw.hasPrefix("-") && nonzero ? .adjustment : .inflow
        amount = money.display
    }
    public var titleKey: String {
        switch kind {
        case .inflow: return "merchant.ledgerNet.inflow"
        case .adjustment: return "merchant.ledgerNet.adjustment"
        case .pending: return "merchant.ledgerNet.pending"
        }
    }
}

/// Independent first-page reads. This projection is never a complete ledger or a monetary aggregate.
public struct MerchantLedgerRefundPreview: Equatable {
    public struct Page: Equatable, Identifiable {
        public let bucket: MerchantAftercareBucket
        public let rows: [MerchantBusinessRecord]
        public let hasMore: Bool
        public let failed: Bool
        public var id: String { bucket.rawValue }
        public init(bucket: MerchantAftercareBucket, snapshot: MerchantBusinessSnapshot?, access: MerchantBusinessAccess) throws {
            self.bucket = bucket
            guard let snapshot else { rows = []; hasMore = false; failed = true; return }
            guard snapshot.access == access, access.allows("merchant:aftercare:read"),
                  snapshot.document.query == .aftercare(bucket, page: 1),
                  snapshot.document.rows.allSatisfy({ $0.kind == .refund }) else { throw MerchantBusinessFailure.stale }
            rows = snapshot.document.rows; hasMore = snapshot.document.hasMore; failed = false
        }
        public func rowIdentity(_ row: MerchantBusinessRecord) -> String { "aftercare:" + bucket.rawValue + ":" + row.id }
    }
    public let included: Bool
    public let loading: Bool
    public let pages: [Page]
    public init(included: Bool, loading: Bool = false, pages: [Page] = []) {
        self.included = included; self.loading = loading; self.pages = pages
    }
    public static func buckets(filter: String) -> [MerchantAftercareBucket] {
        switch MerchantRedemptionFilter(rawValue: filter) {
        case .all: return [.pending, .processing, .completed]
        case .pending: return [.pending, .processing]
        case .handled: return [.completed]
        case .noCash, nil: return []
        }
    }
}

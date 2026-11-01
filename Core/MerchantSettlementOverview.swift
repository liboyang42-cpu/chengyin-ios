import Foundation

/// Identity of the account/permission context a settlement read belongs to.
/// Any change clears every section: old finance data is never carried across.
public struct MerchantSettlementOverviewContext: Equatable {
    public let scope: MerchantBusinessScope?
    public let authorizationGeneration: UUID?
    public init(scope: MerchantBusinessScope?, authorizationGeneration: UUID?) {
        self.scope = scope; self.authorizationGeneration = authorizationGeneration
    }
}

public enum MerchantSettlementOverviewSection: String, CaseIterable, Equatable {
    case overview, entries, batches
    public func query(page: Int) -> MerchantBusinessQuery {
        switch self {
        case .overview: return .overview
        case .entries: return .entries(source: "all", page: page)
        case .batches: return .batches(page: page)
        }
    }
    /// Every section reads through the existing finance permission only.
    public var permission: String { "merchant:finance:read" }
}

public struct MerchantSettlementOverviewSectionState: Equatable {
    public enum Phase: Equatable { case notLoaded, loading, loaded, failed }
    public private(set) var phase: Phase = .notLoaded
    public private(set) var snapshot: MerchantBusinessSnapshot?
    public private(set) var failureKey: String?
    public private(set) var page = 1
    public private(set) var generation = 0
    public var isLoading: Bool { phase == .loading }
    public var rows: [MerchantBusinessRecord] { snapshot?.document.rows ?? [] }
    public var hasMore: Bool { snapshot?.document.hasMore ?? false }
    public var total: Int? { snapshot?.document.total }

    fileprivate mutating func begin(page: Int) -> Int {
        generation += 1; self.page = page; phase = .loading; snapshot = nil; failureKey = nil
        return generation
    }
    fileprivate mutating func succeed(_ snapshot: MerchantBusinessSnapshot) {
        phase = .loaded; self.snapshot = snapshot; failureKey = nil
    }
    fileprivate mutating func fail(key: String) {
        phase = .failed; snapshot = nil; failureKey = key
    }
    fileprivate mutating func clear() {
        generation += 1; phase = .notLoaded; snapshot = nil; failureKey = nil; page = 1
    }
}

/// Pure per-section state machine for the single-page settlement read.
/// Sections succeed and fail independently; nothing here sums paged rows,
/// infers arrival from another section, or invents a time or currency.
public struct MerchantSettlementOverviewState: Equatable {
    public private(set) var context: MerchantSettlementOverviewContext?
    public private(set) var merchantID: Int?
    public private(set) var overview = MerchantSettlementOverviewSectionState()
    public private(set) var entries = MerchantSettlementOverviewSectionState()
    public private(set) var batches = MerchantSettlementOverviewSectionState()
    public init() {}

    public func section(_ id: MerchantSettlementOverviewSection) -> MerchantSettlementOverviewSectionState {
        switch id { case .overview: return overview; case .entries: return entries; case .batches: return batches }
    }
    private mutating func update(_ id: MerchantSettlementOverviewSection, _ change: (inout MerchantSettlementOverviewSectionState) -> Void) {
        switch id { case .overview: change(&overview); case .entries: change(&entries); case .batches: change(&batches) }
    }

    /// Binds a read context. A different scope or permission version drops all
    /// previously loaded finance data and returns true.
    @discardableResult public mutating func bind(_ newContext: MerchantSettlementOverviewContext) -> Bool {
        guard context != newContext else { return false }
        context = newContext; merchantID = nil
        overview.clear(); entries.clear(); batches.clear()
        return true
    }

    /// Starts one section load. Returns the generation a completion must match,
    /// or nil when the section is already loading (duplicate taps are safe).
    public mutating func begin(_ id: MerchantSettlementOverviewSection, page: Int = 1,
                               context newContext: MerchantSettlementOverviewContext) -> Int? {
        bind(newContext)
        guard !section(id).isLoading, page >= 1 else { return nil }
        var issued = 0
        update(id) { issued = $0.begin(page: page) }
        return issued
    }

    public mutating func succeed(_ id: MerchantSettlementOverviewSection, generation: Int,
                                 context expected: MerchantSettlementOverviewContext,
                                 snapshot: MerchantBusinessSnapshot) -> Bool {
        guard context == expected, section(id).generation == generation, section(id).isLoading,
              snapshot.document.query == id.query(page: section(id).page),
              snapshot.access.allows(id.permission),
              merchantID == nil || merchantID == snapshot.access.merchantID else { return false }
        merchantID = snapshot.access.merchantID
        update(id) { $0.succeed(snapshot) }
        return true
    }

    @discardableResult public mutating func fail(_ id: MerchantSettlementOverviewSection, generation: Int,
                                                 context expected: MerchantSettlementOverviewContext, key: String) -> Bool {
        guard context == expected, section(id).generation == generation, section(id).isLoading else { return false }
        update(id) { $0.fail(key: key) }
        return true
    }

    /// Closing the page invalidates every in-flight generation.
    public mutating func invalidateAll() {
        merchantID = nil; overview.clear(); entries.clear(); batches.clear()
    }
    public mutating func invalidate(_ id: MerchantSettlementOverviewSection) { update(id) { $0.clear() } }
}

/// 对账单 projection of one owned batch-detail response. The detail contract
/// carries no total/hasMore for its earning/adjustment lines, so completeness
/// is never claimed: only the returned line counts and the server batch
/// total are reported, never a sum recomputed from paged lines.
public struct MerchantSettlementStatement: Equatable {
    public let batchID: Int
    public let period: String?
    public let serverTotalDisplay: String?
    public let returnedEarningsCount: Int
    public let returnedAdjustmentsCount: Int
    public var returnedDetailCount: Int { returnedEarningsCount + returnedAdjustmentsCount }
    /// The batch-detail response has no complete-line contract.
    public var hasCompleteDetailContract: Bool { false }

    public init?(document: MerchantBusinessDocument) {
        guard case .batch(let id) = document.query,
              let batch = document.sections.first(where: { $0.id == "batch" })?.rows.first,
              batch.kind == .batch else { return nil }
        batchID = id.rawValue
        period = batch.fields.mbText("periodYm")
        let money = try? MerchantBusinessMoney(batch.fields["amountTotal"], strictString: true)
        serverTotalDisplay = money?.raw == nil ? nil : money?.display
        returnedEarningsCount = document.sections.first(where: { $0.id == "earnings" })?.rows.count ?? 0
        returnedAdjustmentsCount = document.sections.first(where: { $0.id == "adjustments" })?.rows.count ?? 0
    }
}

import Foundation

/// Account and permission generation a ledger read belongs to.
/// A different value drops every section; finance rows are not carried across.
public struct MerchantLedgerSettlementOwner: Equatable, Hashable {
    public var scope: MerchantBusinessScope?
    public var authorizationGeneration: UUID?
    public init(scope: MerchantBusinessScope?, authorizationGeneration: UUID?) {
        self.scope = scope
        self.authorizationGeneration = authorizationGeneration
    }
}

public enum MerchantLedgerSettlementSection: String, CaseIterable, Equatable, Hashable {
    case overview, entries, batches
    public func query(page: Int) -> MerchantBusinessQuery {
        switch self {
        case .overview: return .overview
        case .entries: return .entries(source: "all", page: page)
        case .batches: return .batches(page: page)
        }
    }
}

public enum MerchantLedgerSettlementWrite: Equatable {
    case stored, rejected(String), ignored
}

/// One section's read ticket. Scope retirement clears loading and the old error
/// in the same step as the generation bump, so the next `begin` is not blocked.
/// `cancel` only finishes the ticket it was given: an older defer cannot clear
/// a newer read after that bump.
public struct MerchantLedgerReadSlot: Equatable {
    public enum Phase: Equatable { case idle, loading, loaded, failed }
    public private(set) var phase: Phase = .idle
    public private(set) var generation = 0
    public private(set) var failureKey: String?
    public private(set) var snapshot: MerchantBusinessSnapshot?
    public private(set) var page = 1
    public var isLoading: Bool { phase == .loading }
    public var hasMore: Bool { snapshot?.document.hasMore ?? false }

    public mutating func interrupt() {
        generation += 1
        phase = .idle
        failureKey = nil
        snapshot = nil
    }
    public mutating func retire() {
        interrupt()
        page = 1
    }
    public mutating func begin(page: Int) -> Int? {
        guard !isLoading, page >= 1 else { return nil }
        generation += 1
        self.page = page
        phase = .loading
        failureKey = nil
        snapshot = nil
        return generation
    }
    @discardableResult public mutating func succeed(_ snapshot: MerchantBusinessSnapshot, generation ticket: Int) -> Bool {
        guard generation == ticket, isLoading else { return false }
        phase = .loaded
        self.snapshot = snapshot
        failureKey = nil
        return true
    }
    @discardableResult public mutating func fail(key: String, generation ticket: Int) -> Bool {
        guard generation == ticket, isLoading else { return false }
        phase = .failed
        failureKey = key
        snapshot = nil
        return true
    }
    public mutating func cancel(generation ticket: Int) {
        guard generation == ticket, isLoading else { return }
        phase = .idle
        failureKey = nil
    }
}

/// One presentation of a batch card. Reopening the same batch id mints a new id,
/// so a late pop of the previous presentation cannot consume the new one.
public struct MerchantLedgerBatchCover: Identifiable, Hashable {
    public let id: UUID
    public let batchID: Int
    public let owner: MerchantLedgerSettlementOwner
    public let epoch: Int
}

/// Overview, entries and batches. One section's failure does not clear the others.
/// Disappearing because a batch cover was pushed does not retire the three sections.
public struct MerchantLedgerSettlementRead: Equatable {
    public private(set) var owner = MerchantLedgerSettlementOwner(scope: nil, authorizationGeneration: nil)
    public private(set) var overview = MerchantLedgerReadSlot()
    public private(set) var entries = MerchantLedgerReadSlot()
    public private(set) var batches = MerchantLedgerReadSlot()
    public private(set) var cover: MerchantLedgerBatchCover?
    private var epoch = 0
    private var refreshedCover: UUID?
    private var merchantID: Int?
    public init() {}

    public func section(_ id: MerchantLedgerSettlementSection) -> MerchantLedgerReadSlot {
        switch id { case .overview: return overview; case .entries: return entries; case .batches: return batches }
    }
    private mutating func update(_ id: MerchantLedgerSettlementSection, _ body: (inout MerchantLedgerReadSlot) -> Void) {
        switch id { case .overview: body(&overview); case .entries: body(&entries); case .batches: body(&batches) }
    }

    @discardableResult public mutating func replaceOwner(_ next: MerchantLedgerSettlementOwner) -> Bool {
        guard owner != next else { return false }
        owner = next
        merchantID = nil
        epoch += 1
        cover = nil
        overview.retire(); entries.retire(); batches.retire()
        return true
    }

    public mutating func begin(_ id: MerchantLedgerSettlementSection, page: Int, owner next: MerchantLedgerSettlementOwner) -> Int? {
        if owner != next { _ = replaceOwner(next) }
        var ticket: Int?
        update(id) { ticket = $0.begin(page: page) }
        return ticket
    }

    public mutating func succeed(_ id: MerchantLedgerSettlementSection, generation ticket: Int,
                                 owner expected: MerchantLedgerSettlementOwner,
                                 snapshot: MerchantBusinessSnapshot) -> MerchantLedgerSettlementWrite {
        let current = section(id)
        guard owner == expected, current.generation == ticket, current.isLoading else { return .ignored }
        let query = id.query(page: current.page)
        if snapshot.document.query != query || (merchantID != nil && merchantID != snapshot.access.merchantID) {
            update(id) { $0.fail(key: "merchant.business.malformed", generation: ticket) }
            return .rejected("merchant.business.malformed")
        }
        // The snapshot's own access is the permission. The read API is not widened.
        if (try? snapshot.access.require(query.permissions)) == nil {
            update(id) { $0.fail(key: "merchant.business.denied", generation: ticket) }
            return .rejected("merchant.business.denied")
        }
        merchantID = snapshot.access.merchantID
        update(id) { $0.succeed(snapshot, generation: ticket) }
        return .stored
    }

    @discardableResult public mutating func fail(_ id: MerchantLedgerSettlementSection, generation ticket: Int,
                                                 owner expected: MerchantLedgerSettlementOwner, key: String) -> Bool {
        guard owner == expected else { return false }
        var wrote = false
        update(id) { wrote = $0.fail(key: key, generation: ticket) }
        return wrote
    }

    public mutating func cancel(_ id: MerchantLedgerSettlementSection, generation ticket: Int) {
        update(id) { $0.cancel(generation: ticket) }
    }

    /// Child-cover disappearance. Does not retire overview, entries or batches.
    public mutating func overviewDisappeared() {}

    public mutating func leave() {
        epoch += 1
        cover = nil
        merchantID = nil
        overview.retire(); entries.retire(); batches.retire()
    }

    public mutating func presentBatch(_ batchID: Int) -> MerchantLedgerBatchCover {
        let cover = MerchantLedgerBatchCover(id: UUID(), batchID: batchID, owner: owner, epoch: epoch)
        self.cover = cover
        return cover
    }

    /// True once, and only for this presentation and owner. Interrupts batches
    /// alone so the return read can start; overview and entries stay put.
    @discardableResult public mutating func consumePop(_ cover: MerchantLedgerBatchCover) -> Bool {
        guard cover.epoch == epoch, cover.owner == owner, refreshedCover != cover.id else { return false }
        guard self.cover == nil || self.cover?.id == cover.id else { return false }
        refreshedCover = cover.id
        if self.cover?.id == cover.id { self.cover = nil }
        batches.interrupt()
        return true
    }
}

/// Batch-detail read. `replaceOwner` retires the in-flight ticket and clears
/// loading, so a new scope is not stuck behind `!loading` while the old defer
/// refuses to clear a generation it no longer owns.
public struct MerchantLedgerBatchDetailRead: Equatable {
    public private(set) var owner: MerchantLedgerSettlementOwner
    public private(set) var slot = MerchantLedgerReadSlot()
    public init(owner: MerchantLedgerSettlementOwner) { self.owner = owner }

    @discardableResult public mutating func replaceOwner(_ next: MerchantLedgerSettlementOwner) -> Bool {
        guard owner != next else { return false }
        owner = next
        slot.retire()
        return true
    }
    public mutating func begin(owner next: MerchantLedgerSettlementOwner) -> Int? {
        if owner != next { _ = replaceOwner(next) }
        return slot.begin(page: 1)
    }
    public mutating func succeed(generation ticket: Int, owner expected: MerchantLedgerSettlementOwner,
                                 batchID: Int, snapshot: MerchantBusinessSnapshot) -> MerchantLedgerSettlementWrite {
        guard owner == expected, slot.generation == ticket, slot.isLoading else { return .ignored }
        guard case .batch(let id) = snapshot.document.query, id.rawValue == batchID else {
            slot.fail(key: "merchant.business.malformed", generation: ticket)
            return .rejected("merchant.business.malformed")
        }
        if (try? snapshot.access.require(MerchantBusinessQuery.batch(id).permissions)) == nil {
            slot.fail(key: "merchant.business.denied", generation: ticket)
            return .rejected("merchant.business.denied")
        }
        slot.succeed(snapshot, generation: ticket)
        return .stored
    }
    @discardableResult public mutating func fail(generation ticket: Int, owner expected: MerchantLedgerSettlementOwner, key: String) -> Bool {
        guard owner == expected else { return false }
        return slot.fail(key: key, generation: ticket)
    }
    public mutating func cancel(generation ticket: Int) { slot.cancel(generation: ticket) }
    public mutating func leave() { slot.retire() }
}

public enum MerchantLedgerSettlementFailure {
    public static func key(_ error: Error) -> String {
        if let failure = error as? MerchantBusinessFailure { return failure.key }
        if let api = error as? APIError {
            if api == .unauthorized { return "auth.expired" }
            if api == .notConfigured { return "auth.notConfigured" }
        }
        return "merchant.business.loadFailed"
    }
}

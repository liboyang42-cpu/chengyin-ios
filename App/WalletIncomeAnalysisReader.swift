import SwiftUI

/// Received records from bounded original offset reads, never an atomic ledger or payout authority.
struct WalletIncomeAnalysisSlice {
    enum Stop: Equatable { case end, budget, interrupted, changed, unverified }
    let rows: [WalletLedgerRow]
    let pagesRead: Int
    let stop: Stop
    var isPartial: Bool { stop == .interrupted || stop == .changed || stop == .unverified }
}

/// The first-party income endpoint is a table; the separate asset balance array is not used here.
struct WalletIncomeAnalysisAccumulator {
    static let pageSize = 20
    static let pageBudget = 10
    private(set) var rows: [WalletLedgerRow] = []
    private(set) var pagesRead = 0
    private var observedTotal: Int?
    enum InvalidPage: Error { case changed }

    mutating func append(_ page: WalletPage<WalletLedgerRow>, requestedPage: Int) throws -> WalletIncomeAnalysisSlice.Stop? {
        guard requestedPage == pagesRead + 1, requestedPage <= Self.pageBudget,
              page.page == requestedPage, page.pageSize == Self.pageSize,
              page.rows.count <= Self.pageSize, page.rows.allSatisfy({ $0.id > 0 }),
              Set(page.rows.map(\.id)).count == page.rows.count,
              zip(page.rows, page.rows.dropFirst()).allSatisfy({ $0.0.id > $0.1.id }),
              rows.last.map({ last in page.rows.first.map { $0.id < last.id } ?? true }) ?? true else {
            throw InvalidPage.changed
        }
        // Without the original total, the received first page can be shown as unverified,
        // but it cannot justify further offset requests or a confirmed empty account.
        guard let total = page.total else {
            if pagesRead == 0 { rows = page.rows; pagesRead = 1 }
            return .unverified
        }
        guard total >= 0, observedTotal.map({ $0 == total }) ?? true else { throw InvalidPage.changed }
        let offset = (requestedPage - 1) * Self.pageSize
        guard total >= offset, page.rows.count == min(Self.pageSize, total - offset) else { throw InvalidPage.changed }
        observedTotal = total
        rows.append(contentsOf: page.rows); pagesRead += 1
        if rows.count >= total { return .end }
        if pagesRead == Self.pageBudget { return .budget }
        return nil
    }
    func slice(_ stop: WalletIncomeAnalysisSlice.Stop) -> WalletIncomeAnalysisSlice {
        .init(rows: rows, pagesRead: pagesRead, stop: stop)
    }
}

/// Reader identity is separate from scope: replacing a same-owner reader retires the old display.
struct WalletIncomeAnalysisReadIdentity: Equatable {
    let reader: ObjectIdentifier
    let scope: WalletCommerceScope?
    @MainActor init(_ value: WalletCommerceReader) { reader = ObjectIdentifier(value); scope = value.scope }
}

@MainActor final class WalletIncomeAnalysisReader: ObservableObject {
    @Published private(set) var loading = false
    @Published private(set) var failed = false
    @Published private(set) var requiresLogin = false
    @Published private(set) var unavailable = false
    @Published private(set) var receivedCount = 0
    @Published private(set) var pagesRead = 0
    @Published private(set) var result: WalletIncomeAnalysisSlice?
    private var identity: WalletIncomeAnalysisReadIdentity?
    private var generation = UUID()
    private var task: Task<Void, Never>?

    func displayedResult(for reader: WalletCommerceReader) -> WalletIncomeAnalysisSlice? {
        guard !loading, reader.isConfigured, reader.scope != nil,
              identity == WalletIncomeAnalysisReadIdentity(reader) else { return nil }
        return result
    }

    /// Close, background and replacement cancel the whole sequence, not just late publication.
    func cancel() {
        generation = UUID(); task?.cancel(); task = nil
        result = nil; identity = nil; receivedCount = 0; pagesRead = 0
        loading = false; failed = false; requiresLogin = false; unavailable = false
    }

    func load(_ reader: WalletCommerceReader) async {
        guard !Task.isCancelled else { return }
        cancel()
        guard reader.isConfigured else { unavailable = true; return }
        guard let scope = reader.scope else { requiresLogin = true; return }
        let stamp = generation
        identity = WalletIncomeAnalysisReadIdentity(reader); loading = true
        let work = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.collect(reader, scope: scope, stamp: stamp)
        }
        task = work
        await withTaskCancellationHandler(operation: { await work.value }, onCancel: { work.cancel() })
        if generation == stamp { task = nil }
    }

    private func checkCurrent(_ reader: WalletCommerceReader, scope: WalletCommerceScope, stamp: UUID) throws {
        try Task.checkCancellation()
        guard generation == stamp, identity == WalletIncomeAnalysisReadIdentity(reader),
              reader.isConfigured, reader.scope == scope else { throw WalletCommerceSafetyError.staleSession }
    }

    private func collect(_ reader: WalletCommerceReader, scope: WalletCommerceScope, stamp: UUID) async {
        var accumulator = WalletIncomeAnalysisAccumulator()
        defer { if generation == stamp { loading = false } }
        do {
            for pageNumber in 1...WalletIncomeAnalysisAccumulator.pageBudget {
                try checkCurrent(reader, scope: scope, stamp: stamp)
                // Each page re-enters the original reader and exact narrow route. No writer,
                // alternate endpoint, new grant, receipt recovery or transaction is involved.
                let page = try await reader.read {
                    try await $0.ledger(.income(.all), page: pageNumber,
                        pageSize: WalletIncomeAnalysisAccumulator.pageSize, token: $1)
                }
                try checkCurrent(reader, scope: scope, stamp: stamp)
                let stop = try accumulator.append(page, requestedPage: pageNumber)
                receivedCount = accumulator.rows.count; pagesRead = accumulator.pagesRead
                if let stop { result = accumulator.slice(stop); return }
            }
        } catch {
            guard generation == stamp else { return }
            if Task.isCancelled || error is CancellationError {
                cancel(); return
            }
            guard identity == WalletIncomeAnalysisReadIdentity(reader), reader.scope == scope,
                  error as? WalletCommerceSafetyError != .staleSession else {
                result = nil; receivedCount = 0; pagesRead = 0; unavailable = true; return
            }
            if error as? APIError == .unauthorized {
                result = nil; receivedCount = 0; pagesRead = 0; requiresLogin = true
            } else if WalletReadFailurePresentation.isUnavailable(error) || WalletReadFailurePresentation.isForbidden(error) {
                result = nil; receivedCount = 0; pagesRead = 0; unavailable = true
            } else if !accumulator.rows.isEmpty {
                let changed = error is WalletIncomeAnalysisAccumulator.InvalidPage || error as? APIError == .malformedResponse
                result = accumulator.slice(changed ? .changed : .interrupted)
            } else { failed = true }
        }
    }
}

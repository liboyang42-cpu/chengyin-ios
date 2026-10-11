import Foundation

/// Exact my-list data object. Missing totals are unknown, never fabricated as zero.
public struct MerchantTemplatePage: Decodable, Equatable {
    public static let pageSize = 10
    public let rows: [MerchantTemplateRecord]
    public let total: Int?
    private enum CodingKeys: String, CodingKey { case rows, total }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rows = try c.decode([MerchantTemplateRecord].self, forKey: .rows)
        if !c.contains(.total) { total = nil }
        else if try c.decodeNil(forKey: .total) { total = nil }
        else if let value = try? c.decode(Int.self, forKey: .total) { total = value }
        else {
            let raw = try c.decode(String.self, forKey: .total)
            guard !raw.isEmpty, raw.utf8.allSatisfy({ (48...57).contains($0) }), let value = Int(raw) else { throw APIError.malformedResponse }
            total = value
        }
        guard rows.allSatisfy({ $0.id > 0 }), Set(rows.map(\.id)).count == rows.count,
              total.map({ $0 >= rows.count }) ?? true else { throw APIError.malformedResponse }
    }
}

/// Access was fetched for this exact read, not decoded from list content.
public struct MerchantTemplatePageRead {
    public let page: MerchantTemplatePage
    public let access: MerchantOperationsAccess
    public init(page: MerchantTemplatePage, access: MerchantOperationsAccess) { self.page = page; self.access = access }
}

/// Read-only, scoped pagination. No edit, publication, deletion, or replay authority.
@MainActor public final class MerchantTemplateBrowser {
    public let reader: any MerchantOperationsReading
    private var sourceRows: [MerchantTemplateRecord] = []
    private var sourceTotal: Int?
    private var access: MerchantOperationsAccess?
    private var loadedScope: UUID?
    private var active = true
    private var generation = 0
    private var request: Task<MerchantTemplatePageRead, Error>?
    public private(set) var page = 0
    public private(set) var loaded = false
    public private(set) var isRefreshing = false
    public private(set) var isLoadingMore = false
    public private(set) var issue: MerchantOperationsIssue?
    public private(set) var loadMoreIssue: MerchantOperationsIssue?
    private var more = false
    public init(reader: any MerchantOperationsReading) { self.reader = reader }
    public var isCurrent: Bool { active && loadedScope == reader.scope && reader.isAuthenticated }
    public var rows: [MerchantTemplateRecord] { isCurrent ? sourceRows : [] }
    public var total: Int? { isCurrent ? sourceTotal : nil }
    public var hasMore: Bool { isCurrent && loaded && more }
    public var isBusy: Bool { isRefreshing || isLoadingMore }
    public var canOpen: Bool { isCurrent && loaded && !isBusy && access?.allows(.templates) == true }
    public var canLoadMore: Bool { canOpen && more && issue == nil && page < Int.max }
    public func refresh() async {
        active = true
        if loadedScope != reader.scope { clearRows() }
        request?.cancel(); generation += 1
        await fetch(page: 1, appending: false, ticket: generation)
    }
    public func loadMore() async {
        guard canLoadMore else { return }
        generation += 1
        await fetch(page: page + 1, appending: true, ticket: generation)
    }
    public func deactivate() {
        active = false; generation += 1; request?.cancel(); request = nil
        isRefreshing = false; isLoadingMore = false
    }
    private func clearRows() {
        sourceRows = []; sourceTotal = nil; access = nil; page = 0; loaded = false; more = false
        issue = nil; loadMoreIssue = nil
    }
    private func fetch(page requestedPage: Int, appending: Bool, ticket: Int) async {
        let scope = reader.scope
        isRefreshing = !appending; isLoadingMore = appending
        if appending { loadMoreIssue = nil } else { issue = nil; loadMoreIssue = nil }
        let reader = reader
        let pending = Task { try await reader.templatePage(page: requestedPage) }; request = pending
        defer {
            if ticket == generation { isRefreshing = false; isLoadingMore = false; request = nil }
        }
        do {
            let result = try await pending.value
            guard !Task.isCancelled, active, ticket == generation, scope == reader.scope, reader.isAuthenticated else { return }
            guard result.access.allows(.templates) else { throw MerchantOperationsFailure.accessDenied }
            if appending && access != result.access {
                clearRows(); loadedScope = scope; issue = .key("merchant.templateBrowser.accessChanged"); return
            }
            let incoming = result.page
            guard incoming.rows.count <= MerchantTemplatePage.pageSize else { throw APIError.malformedResponse }
            let combined = appending ? sourceRows + incoming.rows : incoming.rows
            guard Set(combined.map(\.id)).count == combined.count else { throw APIError.malformedResponse }
            if let total = incoming.total {
                guard total >= combined.count, !incoming.rows.isEmpty || combined.count >= total else { throw APIError.malformedResponse }
            }
            sourceRows = combined; sourceTotal = incoming.total; access = result.access; loadedScope = scope
            page = requestedPage; loaded = true; issue = nil; loadMoreIssue = nil
            more = incoming.total.map { combined.count < $0 } ?? (incoming.rows.count == MerchantTemplatePage.pageSize)
        } catch {
            guard !Task.isCancelled, !(error is CancellationError), active, ticket == generation, scope == reader.scope else { return }
            loadedScope = scope
            if error as? MerchantOperationsFailure == .accessDenied || error as? APIError == .unauthorized {
                clearRows(); issue = .init(error)
            } else if appending { loadMoreIssue = .init(error) }
            else { issue = .init(error) }
        }
    }
}

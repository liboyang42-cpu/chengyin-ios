import Foundation

/// Bounded cursor reads. Refresh clears old data; a failed next page preserves the current page.
@MainActor public final class NonCashRewardCollectionModel {
    public private(set) var rows: [NonCashReward] = []
    public private(set) var nextCursor: String?
    public private(set) var asOf: Date?
    public private(set) var issue: AccountCollectionIssue?
    public private(set) var moreIssue: AccountCollectionIssue?
    public private(set) var loadedScope: UUID?
    public private(set) var isLoading = false
    public private(set) var isLoadingMore = false
    private var generation: UInt64 = 0
    private var consumedCursors = Set<String>()
    public init() {}
    public func visibleRows(scope: UUID) -> [NonCashReward] { loadedScope == scope ? rows : [] }
    public func invalidate() {
        generation &+= 1; rows = []; nextCursor = nil; asOf = nil; issue = nil; moreIssue = nil
        loadedScope = nil; isLoading = false; isLoadingMore = false; consumedCursors = []
    }
    public func cancelPending() { generation &+= 1; isLoading = false; isLoadingMore = false }
    public func refresh(reader: any NonCashRewardReading) async {
        invalidate()
        let captured = generation, scope = reader.scope
        isLoading = true
        defer { if generation == captured { isLoading = false } }
        do {
            let page = try await reader.rewards(cursor: nil)
            guard !Task.isCancelled, captured == generation, reader.scope == scope else { return }
            try accept(page, requestedCursor: nil)
            loadedScope = scope
        } catch {
            guard !Task.isCancelled, !(error is CancellationError), captured == generation, reader.scope == scope else { return }
            issue = AccountCollectionIssue(error); loadedScope = scope
        }
    }
    public func loadMore(reader: any NonCashRewardReading) async {
        let scope = reader.scope
        guard loadedScope == scope, !isLoading, !isLoadingMore, issue == nil, let cursor = nextCursor else { return }
        let captured = generation
        isLoadingMore = true; moreIssue = nil
        defer { if generation == captured { isLoadingMore = false } }
        do {
            let page = try await reader.rewards(cursor: cursor)
            guard !Task.isCancelled, captured == generation, reader.scope == scope else { return }
            try accept(page, requestedCursor: cursor)
        } catch {
            guard !Task.isCancelled, !(error is CancellationError), captured == generation, reader.scope == scope else { return }
            if error as? APIError == .unauthorized { invalidate(); loadedScope = scope; issue = .login }
            else { moreIssue = AccountCollectionIssue(error) }
        }
    }
    private func accept(_ page: NonCashRewardPage, requestedCursor: String?) throws {
        let existing = Set(rows.map(\.id)), incoming = Set(page.items.map(\.id))
        guard incoming.count == page.items.count, existing.isDisjoint(with: incoming),
              page.nextCursor == nil || (!page.items.isEmpty && page.nextCursor == page.items.last?.id),
              page.nextCursor == nil || (page.nextCursor != requestedCursor && !consumedCursors.contains(page.nextCursor!))
        else { throw APIError.malformedResponse }
        if let requestedCursor { consumedCursors.insert(requestedCursor) }
        rows += page.items; nextCursor = page.nextCursor; asOf = page.asOf; moreIssue = nil
    }
}

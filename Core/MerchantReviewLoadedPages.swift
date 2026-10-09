import Foundation

/// Ephemeral presentation only. These rows never replace a coordinator snapshot,
/// establish a mutation baseline, or reserve/complete an operation journal.
public struct MerchantReviewLoadedPages: Equatable {
    public let scope: MerchantBusinessScope
    public let authorizationGeneration: UUID?
    public let access: MerchantBusinessAccess
    public private(set) var page: Int
    public private(set) var hasMore: Bool
    public private(set) var rows: [MerchantBusinessRecord]
    private var sourcePages: [String: Int]

    public init(snapshot: MerchantBusinessSnapshot, scope: MerchantBusinessScope, authorizationGeneration: UUID?) throws {
        guard case .reviews(let page) = snapshot.document.query, page == 1 else { throw MerchantBusinessFailure.stale }
        self.scope = scope; self.authorizationGeneration = authorizationGeneration; access = snapshot.access
        self.page = page; hasMore = snapshot.document.hasMore; rows = snapshot.document.rows
        sourcePages = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, page) })
    }
    public func matches(scope: MerchantBusinessScope?, authorizationGeneration: UUID?, access: MerchantBusinessAccess) -> Bool {
        self.scope == scope && self.authorizationGeneration == authorizationGeneration && self.access == access
    }
    public mutating func append(_ snapshot: MerchantBusinessSnapshot, scope: MerchantBusinessScope, authorizationGeneration: UUID?) throws {
        guard matches(scope: scope, authorizationGeneration: authorizationGeneration, access: snapshot.access),
              case .reviews(let next) = snapshot.document.query, hasMore, next == page + 1 else { throw MerchantBusinessFailure.stale }
        var indices = Dictionary(uniqueKeysWithValues: rows.enumerated().map { ($0.element.id, $0.offset) })
        for row in snapshot.document.rows {
            if let index = indices[row.id] { rows[index] = row }
            else { indices[row.id] = rows.count; rows.append(row) }
            sourcePages[row.id] = next
        }
        page = next; hasMore = snapshot.document.hasMore
    }
    public func sourcePage(for row: MerchantBusinessRecord) -> MerchantReviewSourcePage? {
        guard row.kind == .review, rows.contains(row), let page = sourcePages[row.id] else { return nil }
        return .init(scope: scope, authorizationGeneration: authorizationGeneration, access: access, page: page, reviewID: row.id)
    }
}

/// A read destination, never write authorization. It carries no row/version or
/// capability override. A separate coordinator must fetch the exact page again.
public struct MerchantReviewSourcePage: Equatable, Identifiable {
    public let id = UUID()
    public let scope: MerchantBusinessScope
    public let authorizationGeneration: UUID?
    public let access: MerchantBusinessAccess
    public let page: Int
    public let reviewID: String
    public var query: MerchantBusinessQuery { .reviews(page: page) }
    public func matches(scope: MerchantBusinessScope?, authorizationGeneration: UUID?, snapshot: MerchantBusinessSnapshot) -> Bool {
        self.scope == scope && self.authorizationGeneration == authorizationGeneration
            && self.access == snapshot.access && snapshot.document.query == query
    }
}

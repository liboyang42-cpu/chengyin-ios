import Foundation

/// Memory-only presentation. Session reader scope covers account, epoch and authorization changes.
/// Raw query bytes are deliberate: Swift String equality also accepts canonical equivalents.
public struct GlobalSearchResultContext: Equatable {
    public let readerID: ObjectIdentifier
    public let scope: UUID
    public let isAuthenticated: Bool
    public let isConfigured: Bool
    private let keyword: Data
    private let categoryID: Int?
    private let startDate: Data?
    private let endDate: Data?
    private let minimumPrice: UInt64?
    private let maximumPrice: UInt64?
    public init(readerID: ObjectIdentifier, scope: UUID, isAuthenticated: Bool, isConfigured: Bool,
                query: GlobalSearchQuery) {
        self.readerID = readerID; self.scope = scope
        self.isAuthenticated = isAuthenticated; self.isConfigured = isConfigured
        keyword = Data(query.keyword.utf8); categoryID = query.categoryID
        startDate = query.startDate.map { Data($0.utf8) }; endDate = query.endDate.map { Data($0.utf8) }
        minimumPrice = query.minimumPrice?.bitPattern; maximumPrice = query.maximumPrice?.bitPattern
    }
}

public struct GlobalSearchRetainedResults {
    public struct Ticket: Equatable {
        fileprivate let id: UUID
        fileprivate let context: GlobalSearchResultContext
    }
    public struct Snapshot: Equatable {
        public let results: GlobalSearchResults
        public let retainedKinds: [GlobalSearchKind]
    }
    private var context: GlobalSearchResultContext?
    private var pending: Ticket?
    private var stored: Snapshot?
    public init() {}

    public func snapshot(in current: GlobalSearchResultContext) -> Snapshot? {
        guard current.isConfigured, current == context else { return nil }
        return stored
    }
    public mutating func begin(in current: GlobalSearchResultContext) -> Ticket {
        if context != current { stored = nil }
        context = current
        let ticket = Ticket(id: UUID(), context: current); pending = ticket
        return ticket
    }
    public func accepts(_ ticket: Ticket, in current: GlobalSearchResultContext) -> Bool {
        current.isConfigured && pending == ticket && ticket.context == current && context == current
    }
    @discardableResult public mutating func finish(_ value: GlobalSearchResults, ticket: Ticket,
                                                    in current: GlobalSearchResultContext) -> Bool {
        guard accepts(ticket, in: current) else { return false }
        var rows: [GlobalSearchRow] = [], retained: [GlobalSearchKind] = []
        for kind in GlobalSearchKind.allCases {
            // A login/permission gate wins even if a malformed fixture also marks this lane failed.
            if value.gatedKinds.contains(kind) { continue }
            if value.failedKinds.contains(kind) {
                let previous = stored?.results.rows.filter { $0.kind == kind } ?? []
                rows += previous
                if !previous.isEmpty { retained.append(kind) }
            } else {
                // Successful empty replaces the old lane. Never merge old and new successful rows.
                rows += value.rows.filter { $0.kind == kind }
            }
        }
        stored = Snapshot(results: .init(rows: rows, failedKinds: value.failedKinds, gatedKinds: value.gatedKinds),
                          retainedKinds: retained)
        pending = nil
        return true
    }
    /// Thrown errors have no lane-specific permission evidence, so never retain their old rows.
    @discardableResult public mutating func fail(_ ticket: Ticket, in current: GlobalSearchResultContext) -> Bool {
        guard accepts(ticket, in: current) else { return false }
        stored = nil; pending = nil
        return true
    }
    /// Leaving cancels work, but Back can still show the last accepted same-owner result.
    public mutating func cancelPending() { pending = nil }
    public mutating func invalidate() { context = nil; pending = nil; stored = nil }
}

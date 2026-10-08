import Foundation

/// Same-query, memory-only refresh. Never reuse this snapshot across account, area,
/// filter or view-owner changes. A failed refresh is independent of page continuation.
public struct SearchMapRefresh {
    public struct Ticket: Equatable {
        public let query: CityNodeSearchQuery
        public let scope: UUID
        public let manualAreaRevision: UInt64
        private let id = UUID()
        fileprivate init(query: CityNodeSearchQuery, scope: UUID, manualAreaRevision: UInt64) {
            self.query = query; self.scope = scope; self.manualAreaRevision = manualAreaRevision
        }
    }
    public struct Update {
        public let result: CityNodeSearchResults
        public let pagination: SearchMapPagination
    }
    private struct Pending {
        let ticket: Ticket
        let result: CityNodeSearchResults
        let pagination: SearchMapPagination
    }
    private var pending: Pending?
    public private(set) var retainedActivities = false
    public private(set) var retainedNodes = false
    public var isLoading: Bool { pending != nil }
    public var hasRetainedResults: Bool { retainedActivities || retainedNodes }
    public init() {}

    public mutating func begin(query: CityNodeSearchQuery, scope: UUID, manualAreaRevision: UInt64,
                               result: CityNodeSearchResults, pagination: SearchMapPagination) -> Ticket? {
        guard pending == nil, !pagination.isLoading,
              pagination.matches(query: query, scope: scope, manualAreaRevision: manualAreaRevision) else { return nil }
        let ticket = Ticket(query: query, scope: scope, manualAreaRevision: manualAreaRevision)
        pending = Pending(ticket: ticket, result: result, pagination: pagination)
        return ticket
    }
    public func accepts(_ ticket: Ticket, query: CityNodeSearchQuery?, scope: UUID, manualAreaRevision: UInt64) -> Bool {
        pending?.ticket == ticket && ticket.query == query && ticket.scope == scope &&
            ticket.manualAreaRevision == manualAreaRevision
    }
    /// A successful layer replaces its old data, even when empty. Only transient
    /// unavailable failures may keep previously successful reads, with visible labels.
    /// Unauthorized, unconfigured and invalid layers never retain their old content.
    public mutating func finish(_ ticket: Ticket, result: CityNodeSearchResults,
                                query: CityNodeSearchQuery?, scope: UUID, manualAreaRevision: UInt64) -> Update? {
        guard accepts(ticket, query: query, scope: scope, manualAreaRevision: manualAreaRevision),
              let previous = pending else { return nil }
        retainedActivities = result.activityFailure == .unavailable && previous.result.activityFailure == nil
        retainedNodes = result.nodeFailure == .unavailable && previous.result.nodeFailure == nil
        let merged = CityNodeSearchResults(
            activities: retainedActivities ? previous.result.activities : (result.activityFailure == nil ? result.activities : []),
            nodes: retainedNodes ? previous.result.nodes : (result.nodeFailure == nil ? result.nodes : []),
            activityFailure: retainedActivities ? nil : result.activityFailure,
            nodeFailure: retainedNodes ? nil : result.nodeFailure,
            activityPage: retainedActivities ? previous.result.activityPage : result.activityPage)
        var pages = previous.pagination
        if !retainedActivities {
            // A failed layer must never smuggle old or unsolicited rows through its DTO.
            let safe = CityNodeSearchResults(activities: result.activityFailure == nil ? result.activities : [],
                nodes: [], activityFailure: result.activityFailure, activityPage: result.activityFailure == nil ? result.activityPage : nil)
            pages.reset(query: ticket.query, scope: ticket.scope, manualAreaRevision: ticket.manualAreaRevision, result: safe)
        }
        pending = nil
        return Update(result: merged, pagination: pages)
    }
    /// Dismissal retires the ticket but keeps any already-labelled stale snapshot.
    public mutating func cancel(_ ticket: Ticket) { if pending?.ticket == ticket { pending = nil } }
    public mutating func cancelPending() { pending = nil }
    public mutating func invalidate() { self = SearchMapRefresh() }
}

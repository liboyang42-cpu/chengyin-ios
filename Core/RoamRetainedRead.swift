import Foundation

/// View-memory only. Previous non-player rows may remain readable during a same-
/// scope retry. They are never current pins, selection targets or business facts.
public struct RoamRetainedRead {
    public struct Scope: Hashable {
        public let readerID: ObjectIdentifier
        public let identity: RoamReadIdentity
        public let area: RoamSearchArea
        public let layer: RoamLayer
        public let radius: Int
        public let query: String
        public let placeFilter: RoamPlaceFilter
        public let eventFilter: RoamEventFilter
        public init?(readerID: ObjectIdentifier, identity: RoamReadIdentity?, area: RoamSearchArea?,
                     layer: RoamLayer, radius: Int, query: String, placeFilter: RoamPlaceFilter,
                     eventFilter: RoamEventFilter, isConfigured: Bool) {
            guard isConfigured, let identity, identity.accountID > 0, let area, (1...20000).contains(radius) else { return nil }
            self.readerID = readerID; self.identity = identity; self.area = area; self.layer = layer
            self.radius = radius; self.query = query; self.placeFilter = placeFilter; self.eventFilter = eventFilter
        }
    }
    public struct Ticket: Equatable {
        fileprivate let id = UUID()
        fileprivate let scope: Scope
    }
    public struct Snapshot: Equatable {
        public let items: [RoamMapItem]
        /// Local successful-read receipt time, never the server's update time.
        public let readAt: Date
        public let isRetained: Bool
    }
    private var scope: Scope?
    private var stored: Snapshot?
    private var pending: Ticket?
    public init() {}
    public mutating func clear() { scope = nil; stored = nil; pending = nil }
    public mutating func retainOnly(scope: Scope?) {
        guard let scope, self.scope == scope else { clear(); return }
    }
    public mutating func begin(scope: Scope?) -> Ticket? {
        guard let scope else { clear(); return nil }
        if self.scope != scope || scope.layer == .players { clear() }
        self.scope = scope
        if let stored { self.stored = Snapshot(items: stored.items, readAt: stored.readAt, isRetained: true) }
        let ticket = Ticket(scope: scope); pending = ticket
        return ticket
    }
    @discardableResult public mutating func finish(_ ticket: Ticket, items: [RoamMapItem], readAt: Date) -> Bool {
        guard pending == ticket, scope == ticket.scope else { return false }
        guard readAt.timeIntervalSince1970.isFinite, items.allSatisfy({ Self.matches($0, layer: ticket.scope.layer) }) else { clear(); return false }
        pending = nil
        stored = Snapshot(items: RoamMapItem.unique(items), readAt: readAt, isRetained: false)
        return true
    }
    public mutating func fail(_ ticket: Ticket, error: Error) {
        guard pending == ticket else { return }
        pending = nil
        guard Self.isTransient(error), ticket.scope.layer != .players else { clear(); return }
        // begin already marked this snapshot read-only. A first-read failure has no snapshot.
    }
    public mutating func cancel(_ ticket: Ticket) {
        if pending == ticket { clear() }
    }
    public func snapshot(in scope: Scope?) -> Snapshot? {
        guard let scope, self.scope == scope else { return nil }
        return stored
    }
    private static func matches(_ item: RoamMapItem, layer: RoamLayer) -> Bool {
        switch (item, layer) {
        case (.place, .places), (.route, .routes), (.event, .events), (.player, .players): return true
        default: return false
        }
    }
    public static func isTransient(_ error: Error) -> Bool {
        if let error = error as? APIError {
            switch error {
            case .httpStatus(let status): return status == 408 || status == 429 || (500...599).contains(status)
            case .businessCode(let code): return (500...599).contains(code)
            default: return false
            }
        }
        if let error = error as? URLError {
            return [.timedOut, .cannotFindHost, .cannotConnectToHost, .networkConnectionLost, .dnsLookupFailed, .notConnectedToInternet].contains(error.code)
        }
        return false
    }
}

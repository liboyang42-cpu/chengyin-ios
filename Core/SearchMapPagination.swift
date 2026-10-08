import Foundation

/// Source page metadata is independent of client date/price filtering and ID deduplication.
public struct SearchMapActivityPage: Equatable {
    public static let pageSize = 50
    public let rows: [ActivitySummary]
    public let pageNumber: Int
    public let rawCount: Int
    public let serverTotal: Int?
    public var hasMore: Bool {
        // Empty pages stop even when a moving server total is stale.
        guard rawCount > 0, pageNumber < Int.max / Self.pageSize else { return false }
        if let serverTotal {
            let offset = (pageNumber - 1) * Self.pageSize
            return rawCount < serverTotal && offset < serverTotal - rawCount
        }
        return rawCount >= Self.pageSize
    }
    public static func validPageNumber(_ page: Int) -> Bool { page > 0 && page <= Int.max / pageSize }
    public init(rows: [ActivitySummary], pageNumber: Int, rawCount: Int, serverTotal: Int? = nil) throws {
        guard Self.validPageNumber(pageNumber), rawCount >= rows.count,
              rawCount >= 0, serverTotal.map({ $0 >= 0 }) ?? true else { throw APIError.malformedResponse }
        self.rows = rows; self.pageNumber = pageNumber; self.rawCount = rawCount; self.serverTotal = serverTotal
    }
}

/// Matches the verified TableDataInfo envelope without changing global-search decoding.
struct SearchMapActivityPageEnvelope: Decodable {
    let rows: [ActivitySummary]
    let total: Int?
    private enum CodingKeys: String, CodingKey { case data, total }
    init(from decoder: Decoder) throws {
        rows = try ActivityListResponse(from: decoder).rows
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.data), try !container.decodeNil(forKey: .data) {
            total = try container.nestedContainer(keyedBy: CodingKeys.self, forKey: .data).decodeIfPresent(Int.self, forKey: .total)
        } else {
            total = try container.decodeIfPresent(Int.self, forKey: .total)
        }
        if let total, total < 0 { throw APIError.malformedResponse }
    }
}

/// A single-flight, query/account/area-bound continuation of a displayed city activity read.
/// Failed pages keep rows and the same page number. A reset retires every previous ticket.
public struct SearchMapPagination {
    public struct Ticket: Equatable {
        public let query: CityNodeSearchQuery
        public let scope: UUID
        public let manualAreaRevision: UInt64
        public let page: Int
        fileprivate let id: UUID
    }
    public private(set) var rows: [ActivitySummary] = []
    public private(set) var nextPage: Int?
    public private(set) var failure: SearchMapFailure?
    public private(set) var inFlight: Ticket?
    private var query: CityNodeSearchQuery?
    private var scope: UUID?
    private var manualAreaRevision: UInt64?
    public init() {}
    public var isLoading: Bool { inFlight != nil }
    public func matches(query: CityNodeSearchQuery, scope: UUID, manualAreaRevision: UInt64) -> Bool {
        self.query == query && self.scope == scope && self.manualAreaRevision == manualAreaRevision
    }
    public mutating func reset(query: CityNodeSearchQuery, scope: UUID, manualAreaRevision: UInt64,
                               result: CityNodeSearchResults) {
        self = SearchMapPagination()
        self.query = query; self.scope = scope; self.manualAreaRevision = manualAreaRevision
        var seen = Set<Int>()
        rows = result.activities.filter { seen.insert($0.id).inserted }
        if result.activityFailure == nil, let page = result.activityPage, page.pageNumber == 1,
           page.rows == result.activities, page.hasMore { nextPage = 2 }
    }
    public mutating func invalidate() { self = SearchMapPagination() }
    /// Cancellation on dismissal preserves the already displayed read and permits retry on return.
    public mutating func cancelPending() { inFlight = nil }
    public mutating func cancel(_ ticket: Ticket) { if inFlight == ticket { inFlight = nil } }
    public mutating func begin(query: CityNodeSearchQuery, scope: UUID, manualAreaRevision: UInt64) -> Ticket? {
        guard matches(query: query, scope: scope, manualAreaRevision: manualAreaRevision),
              inFlight == nil, let page = nextPage else { return nil }
        let ticket = Ticket(query: query, scope: scope, manualAreaRevision: manualAreaRevision, page: page, id: UUID())
        inFlight = ticket; failure = nil
        return ticket
    }
    @discardableResult public mutating func finish(_ ticket: Ticket, page: SearchMapActivityPage) -> Bool {
        guard inFlight == ticket else { return false }
        guard page.pageNumber == ticket.page else { return fail(ticket, error: .unavailable) }
        // First accepted occurrence wins; a later duplicate cannot overwrite displayed fields/pins.
        var seen = Set(rows.map(\.id))
        rows.append(contentsOf: page.rows.filter { seen.insert($0.id).inserted })
        nextPage = page.hasMore ? page.pageNumber + 1 : nil
        inFlight = nil; failure = nil
        return true
    }
    @discardableResult public mutating func fail(_ ticket: Ticket, error: SearchMapFailure) -> Bool {
        guard inFlight == ticket else { return false }
        inFlight = nil; failure = error
        return true
    }
}

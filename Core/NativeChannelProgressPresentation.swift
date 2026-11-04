import Foundation

/// Server order and optional rank survive presentation. No local percentage or denominator calculation.
public struct NativeChannelProgressPageBuffer: Equatable {
    public private(set) var query: NativeChannelProgressQuery?
    public private(set) var detail = false
    public private(set) var page: NativeChannelProgressPage?
    public private(set) var rows: [NativeChannelProgressRow] = []
    private var consumed: Set<Data> = []
    public init() {}
    public mutating func replace(_ page: NativeChannelProgressPage, query: NativeChannelProgressQuery, detail: Bool) throws {
        _ = try page.validated()
        self.query = query; self.detail = detail; self.page = page; rows = page.list ?? []; consumed = []
    }
    public mutating func append(_ page: NativeChannelProgressPage, query: NativeChannelProgressQuery, detail: Bool, requestedCursor: String) throws {
        _ = try page.validated()
        guard self.query == query, self.detail == detail, let previous = self.page,
              previous.visible, page.visible, previous.revision.utf8.elementsEqual(page.revision.utf8),
              previous.nextCursor.map({ $0.utf8.elementsEqual(requestedCursor.utf8) }) == true, !consumed.contains(Data(requestedCursor.utf8)),
              page.nextCursor.map({ $0.utf8.elementsEqual(requestedCursor.utf8) }) != true else { throw NativeChannelProgressError.server(status: 409, code: "BOARD_CURSOR_STALE") }
        consumed.insert(Data(requestedCursor.utf8)); rows += page.list ?? []; self.page = page
    }
}
public enum NativeChannelProgressRank: Equatable {
    case known(Int), unranked, unknown
    public init(_ row: NativeChannelProgressRow) {
        if row.state == "UNCONFIRMED" { self = .unknown }
        else if let rank = row.rank, rank > 0, row.rankKnown == true { self = .known(rank) }
        else if row.rank != nil { self = .unknown }
        else { self = .unranked }
    }
}
public enum NativeChannelProgressPrivacyPhase: Equatable {
    case idle, saving, checkingReceipt, unresolved, conflict, applied, persistenceFailed, accessClosed
}

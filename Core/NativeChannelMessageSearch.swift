import Foundation
import Observation

public struct NativeChannelMessageQuery: Equatable {
    public let keyword: String
    public let from: String?
    public let to: String?
    public let authorID: NativeChannelMessageID?
    public init(keyword: String, from: String? = nil, to: String? = nil, authorID: NativeChannelMessageID? = nil) {
        self.keyword = keyword; self.from = from; self.to = to; self.authorID = authorID
    }
    public func validate() throws {
        guard !keyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, keyword.utf16.count <= 100,
              [from, to].compactMap({ $0 }).allSatisfy({ !$0.isEmpty && $0.utf8.count <= 64 }) else { throw APIError.invalidRequest }
    }
    var fields: [String: String] {
        var fields = ["keyword": keyword]; fields["from"] = from; fields["to"] = to; fields["author_id"] = authorID?.rawValue
        return fields
    }
}
public struct NativeChannelMessageSearchPage: Decodable {
    public let list: [NativeChannelMessageSnapshot]
    public let has_more: Bool
    public let next_cursor: String?
    public let degraded: Bool
    public let degraded_reason: String?
    // Original Java Date is encoded by the app's existing Jackson configuration.
    public let oldest_searchable_at: NativeChannelMessageWireDate
    func verify(binding: NativeChannelMessageBinding, requested: String?) throws {
        guard list.count <= 20, Set(list.map(\.id)).count == list.count,
              list.allSatisfy({ $0.conversationID == binding.conversationID && $0.status == 0 && $0.kind == .text }),
              list.allSatisfy({ row in requested.flatMap(Int64.init).map { Int64(row.id.rawValue)! < $0 } ?? true }),
              zip(list, list.dropFirst()).allSatisfy({ pair in Int64(pair.0.id.rawValue)! > Int64(pair.1.id.rawValue)! }),
              !degraded || (degraded_reason?.isEmpty == false),
              has_more ? (next_cursor == list.last?.id.rawValue && next_cursor != requested && !list.isEmpty) : next_cursor == nil,
              next_cursor.map(NativeChannelMessageCursor.valid) ?? true else { throw APIError.malformedResponse }
    }
}
public struct NativeChannelMessageWireDate: Decodable, Equatable {
    public let display: String
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let text = try? c.decode(String.self) { display = text }
        else { display = String(try c.decode(Int64.self)) }
    }
}
@MainActor @Observable public final class NativeChannelMessageSearch {
    public private(set) var rows: [NativeChannelMessageSnapshot] = []
    public private(set) var query: NativeChannelMessageQuery?
    public private(set) var nextCursor: String?
    public private(set) var hasMore = false
    public private(set) var degradedReason: String?
    public private(set) var oldestSearchableAt: String?
    public private(set) var loading = false
    public private(set) var failed = false
    private let client: any NativeChannelMessageAccess
    private let expected: MessagingReadIdentity?
    private var generation = 0
    private var consumed = Set<String>()
    public init(client: any NativeChannelMessageAccess) { self.client = client; expected = client.identity }
    public var isCurrent: Bool { expected != nil && client.identity == expected && client.allows(.search) }
    public var channelID: String { client.binding.channelID.rawValue }
    public func retire() { generation += 1; failed = false; rows = []; query = nil; nextCursor = nil; hasMore = false; degradedReason = nil; oldestSearchableAt = nil; loading = false; consumed = [] }
    public func replace(_ query: NativeChannelMessageQuery) async {
        guard isCurrent, !Task.isCancelled else { return }
        retire(); self.query = query; failed = false
        await load(cursor: nil, run: generation)
    }
    /// A source mutation is a veto, never replacement search text. Drop every cached
    /// page and its in-flight generation before re-reading the same original query.
    public func refreshOriginalQuery() async {
        guard let query else { return }
        retire()
        guard isCurrent, !Task.isCancelled else { return }
        self.query = query
        await load(cursor: nil, run: generation)
    }
    public func more() async {
        guard isCurrent, !Task.isCancelled, hasMore, let cursor = nextCursor, !consumed.contains(cursor), !loading else { return }
        await load(cursor: cursor, run: generation)
    }
    private func load(cursor: String?, run: Int) async {
        guard let query, isCurrent else { return }
        loading = true; failed = false
        defer { if generation == run { loading = false } }
        do {
            let page = try await client.search(query, cursor: cursor)
            guard generation == run, self.query == query, isCurrent, !Task.isCancelled else { return }
            try page.verify(binding: client.binding, requested: cursor)
            guard page.next_cursor.map({ !consumed.contains($0) }) ?? true else { throw APIError.malformedResponse }
            if let cursor { consumed.insert(cursor) }
            let existing = Set(rows.map(\.id)); rows += page.list.filter { !existing.contains($0.id) }
            nextCursor = page.next_cursor; hasMore = page.has_more
            if page.degraded { degradedReason = page.degraded_reason }
            oldestSearchableAt = page.oldest_searchable_at.display
        } catch {
            guard generation == run, self.query == query else { return }
            rows = []; nextCursor = nil; hasMore = false; degradedReason = nil; oldestSearchableAt = nil
            failed = true
            if !isCurrent { retire() }
        }
    }
}

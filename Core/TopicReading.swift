import Foundation

/// Credentials stay private to the reader; never put this value in navigation or analytics.
public struct TopicReadSession: Equatable {
    public let accountID: Int
    public let epoch: UInt64
    fileprivate let token: String
    public init(accountID: Int, epoch: UInt64, token: String) throws {
        guard accountID > 0, AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        self.accountID = accountID; self.epoch = epoch; self.token = token
    }
}
@MainActor public protocol TopicReading: AnyObject {
    var isConfigured: Bool { get }
    var isOfflineExample: Bool { get }
    /// Opaque, credential-free cache identity. Changes for guest/account/epoch/token transitions.
    var scope: UUID { get }
    func topicList(query: TopicQuery, pageNumber: Int) async throws -> TopicPage
    func topicDetail(id: Int) async throws -> TopicDetail
}
@MainActor public final class TopicSessionReader: TopicReading {
    private let service: TopicService?
    private let currentSession: () -> TopicReadSession?
    private let onUnauthorized: (TopicReadSession) -> Void
    private var snapshot: TopicReadSession?
    private var stamp = UUID()
    public var isConfigured: Bool { service != nil }
    public var isOfflineExample: Bool { false }
    public var scope: UUID {
        let current = currentSession()
        if current != snapshot { snapshot = current; stamp = UUID() }
        return stamp
    }
    public init(service: TopicService?, currentSession: @escaping () -> TopicReadSession?,
                onUnauthorized: @escaping (TopicReadSession) -> Void = { _ in }) {
        self.service = service; self.currentSession = currentSession; self.onUnauthorized = onUnauthorized
        snapshot = currentSession()
    }
    public func topicList(query: TopicQuery, pageNumber: Int) async throws -> TopicPage {
        try await read { try await $0.list(query: query, pageNumber: pageNumber, token: $1) }
    }
    public func topicDetail(id: Int) async throws -> TopicDetail {
        try await read { try await $0.detail(id: id, token: $1) }
    }
    private func read<T>(_ operation: (TopicService, String?) async throws -> T) async throws -> T {
        guard let service else { throw APIError.notConfigured }
        let session = currentSession()
        let startedScope = scope
        try Task.checkCancellation()
        do {
            let result = try await operation(service, session?.token)
            try Task.checkCancellation()
            guard currentSession() == session, scope == startedScope else { throw CancellationError() }
            return result
        } catch {
            guard !Task.isCancelled, currentSession() == session, scope == startedScope else { throw CancellationError() }
            if error as? APIError == .unauthorized, let session { onUnauthorized(session) }
            throw error
        }
    }
}

/// Pagination accumulator advances by raw server pages, not by the deduplicated display count.
public struct TopicPagination {
    public private(set) var rows: [TopicSummary] = []
    public private(set) var nextPage = 1
    public private(set) var hasMore = true
    public init() {}
    public mutating func reset() { self = TopicPagination() }
    public mutating func accept(_ page: TopicPage) throws {
        guard page.pageNumber == nextPage, page.pageSize > 0 else { throw APIError.invalidRequest }
        var seen = Set(rows.map(\.id))
        rows += page.rows.filter { $0.id > 0 && seen.insert($0.id).inserted }
        hasMore = page.hasMore && nextPage < Int.max
        if nextPage < Int.max { nextPage += 1 }
    }
}

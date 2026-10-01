import Foundation

public struct HomeFeedSession: Equatable {
    public let accountID: Int
    public let epoch: UInt64
    fileprivate let token: String
    public init(accountID: Int, epoch: UInt64, token: String) throws {
        guard accountID > 0, AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        self.accountID = accountID; self.epoch = epoch; self.token = token
    }
}
@MainActor public protocol HomeFeedReading: AnyObject {
    var isConfigured: Bool { get }
    var isOfflineExample: Bool { get }
    var scope: UUID { get }
    func banners() async throws -> [DiscoveryBanner]
    func categories() async throws -> [DiscoveryCategory]
    func section(_ section: HomeFeedSection) async throws -> [HomeFeedItem]
    func page(query: HomeFeedQuery, number: Int) async throws -> HomeFeedPage
}
@MainActor public final class HomeFeedSessionReader: HomeFeedReading {
    private let service: HomeFeedService?
    private let currentSession: () -> HomeFeedSession?
    private let onUnauthorized: (HomeFeedSession) -> Void
    private var snapshot: HomeFeedSession?
    private var stamp = UUID()
    public var isConfigured: Bool { service != nil }
    public var isOfflineExample: Bool { false }
    public var scope: UUID {
        let current = currentSession()
        if current != snapshot { snapshot = current; stamp = UUID() }
        return stamp
    }
    public init(service: HomeFeedService?, currentSession: @escaping () -> HomeFeedSession?, onUnauthorized: @escaping (HomeFeedSession) -> Void = { _ in }) {
        self.service = service; self.currentSession = currentSession; self.onUnauthorized = onUnauthorized; snapshot = currentSession()
    }
    public func banners() async throws -> [DiscoveryBanner] { try await read { try await $0.banners(token: $1) } }
    public func categories() async throws -> [DiscoveryCategory] { try await read { try await $0.categories(token: $1) } }
    public func section(_ section: HomeFeedSection) async throws -> [HomeFeedItem] { try await read { try await $0.section(section, token: $1) } }
    public func page(query: HomeFeedQuery, number: Int) async throws -> HomeFeedPage { try await read { try await $0.page(query: query, number: number, token: $1) } }
    private func read<T>(_ operation: (HomeFeedService, String?) async throws -> T) async throws -> T {
        guard let service else { throw APIError.notConfigured }
        let session = currentSession(); let startedScope = scope
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

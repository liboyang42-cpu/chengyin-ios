import Foundation
import Observation

/// An explicit selection from a successfully read, current saved-post collection.
/// It is a target/lifetime fence, not an endpoint approval.
@MainActor @Observable public final class ProfileFavoritePostSelection: Identifiable, Hashable {
    public nonisolated let id = UUID()
    public let route: SquareContentRoute
    public let context: RuntimeDependencyContext
    public let viewerRevision: UInt64
    private var confirmedDetailAccess: UUID?
    private let current: () -> Bool
    public private(set) var isRetired = false
    init(route: SquareContentRoute, context: RuntimeDependencyContext, viewerRevision: UInt64, current: @escaping () -> Bool) {
        self.route = route; self.context = context; self.viewerRevision = viewerRevision; self.current = current
    }
    public var isCurrent: Bool {
        guard !isRetired else { return false }
        guard current() else { isRetired = true; return false }
        return true
    }
    public func beginDetailRead() { confirmedDetailAccess = nil }
    public func confirmDetailRead(access: ProfileFavoriteDetailAccess) {
        guard isCurrent, access.matches(context) else { return }
        confirmedDetailAccess = access.revision
    }
    public func permitsComments(access: ProfileFavoriteDetailAccess) -> Bool {
        isCurrent && access.matches(context) && confirmedDetailAccess == access.revision
    }
    public func retire() { isRetired = true; confirmedDetailAccess = nil }
    public nonisolated static func == (lhs: ProfileFavoritePostSelection, rhs: ProfileFavoritePostSelection) -> Bool { lhs.id == rhs.id }
    public nonisolated func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

@MainActor public final class ProfileFavoritesReader: AccountCollectionReading {
    private let service: AccountCollectionService?
    private let current: () -> RuntimeDependencyContext?
    private let viewerRevision: () -> UInt64
    private let selectAccess: (RuntimeDependencyContext) -> ProfileFavoritesReadAccess?
    private let onUnauthorized: (RuntimeDependencyContext) -> Void
    private var observedContext: RuntimeDependencyContext?
    private var observedViewer: UInt64?
    private var observedAccess: UUID?
    private var stamp = UUID()
    private var topicReceipt = UUID()
    private var acceptedTopics = Set<Int>()
    private var postReceipt = UUID()
    private var acceptedPosts = Set<Int>()
    public init(service: AccountCollectionService?, current: @escaping () -> RuntimeDependencyContext?,
                viewerRevision: @escaping () -> UInt64,
                access: @escaping (RuntimeDependencyContext) -> ProfileFavoritesReadAccess?,
                onUnauthorized: @escaping (RuntimeDependencyContext) -> Void = { _ in }) {
        self.service = service; self.current = current; self.viewerRevision = viewerRevision
        selectAccess = access; self.onUnauthorized = onUnauthorized
    }
    public var isAuthenticated: Bool { current() != nil }
    public var isConfigured: Bool { synchronize() != nil && service != nil }
    public var isOfflineExample: Bool { false }
    public var scope: UUID { _ = synchronize(); return stamp }
    private func synchronize() -> ProfileFavoritesReadAccess? {
        let context = current(), viewer = viewerRevision()
        let selected = context.flatMap { value in selectAccess(value).flatMap { $0.matches(value) ? $0 : nil } }
        let same: Bool
        if let context, let old = observedContext { same = ContentDraftContextFence.matches(old, context) }
        else { same = context == nil && observedContext == nil }
        if !same || viewer != observedViewer || selected?.revision != observedAccess {
            observedContext = context; observedViewer = viewer; observedAccess = selected?.revision; stamp = UUID()
            topicReceipt = UUID(); acceptedTopics.removeAll()
            postReceipt = UUID(); acceptedPosts.removeAll()
        }
        return selected
    }
    public func favoriteTopics(pageNumber: Int, pageSize: Int) async throws -> TopicPage {
        guard pageNumber > 0, (1...100).contains(pageSize) else { throw APIError.invalidRequest }
        _ = synchronize()
        if pageNumber == 1 { topicReceipt = UUID(); acceptedTopics.removeAll() }
        let receipt = topicReceipt, capturedScope = scope
        let page = try await read { try await $0.favorites(pageNumber: pageNumber, pageSize: pageSize, token: $1) }
        guard isConfigured, scope == capturedScope, topicReceipt == receipt else { throw CancellationError() }
        acceptedTopics.formUnion(page.rows.map(\.id))
        return page
    }
    public func favoritePosts(pageNumber: Int, pageSize: Int) async throws -> AccountCollectionPostPage {
        guard pageNumber > 0, (1...100).contains(pageSize) else { throw APIError.invalidRequest }
        _ = synchronize()
        if pageNumber == 1 { postReceipt = UUID(); acceptedPosts.removeAll() }
        let receipt = postReceipt, capturedScope = scope
        let page = try await read { try await $0.favoritePosts(pageNumber: pageNumber, pageSize: pageSize, token: $1) }
        guard isConfigured, scope == capturedScope, postReceipt == receipt else { throw CancellationError() }
        acceptedPosts.formUnion(page.rows.map(\.id))
        return page
    }
    public func selectPost(_ route: SquareContentRoute, renderedScope: UUID) -> ProfileFavoritePostSelection? {
        guard isConfigured, scope == renderedScope, route.valid, route.generation == .legacySquare,
              acceptedPosts.contains(route.id), let context = current() else { return nil }
        let receipt = postReceipt, viewer = viewerRevision()
        return ProfileFavoritePostSelection(route: route, context: context, viewerRevision: viewer) { [weak self] in
            guard let self, let fresh = self.current(), ContentDraftContextFence.matches(context, fresh),
                  self.viewerRevision() == viewer, self.isConfigured, self.scope == renderedScope else { return false }
            return self.postReceipt == receipt && self.acceptedPosts.contains(route.id)
        }
    }
    public func selectTopic(_ id: Int, renderedScope: UUID) -> ProfileFavoriteTopicSelection? {
        guard id > 0, isConfigured, scope == renderedScope, acceptedTopics.contains(id),
              let context = current() else { return nil }
        let receipt = topicReceipt, viewer = viewerRevision()
        return ProfileFavoriteTopicSelection(topicID: id, context: context, viewerRevision: viewer) { [weak self] in
            guard let self, let fresh = self.current(), ContentDraftContextFence.matches(context, fresh),
                  self.viewerRevision() == viewer, self.isConfigured, self.scope == renderedScope else { return false }
            return self.topicReceipt == receipt && self.acceptedTopics.contains(id)
        }
    }
    public func ownedCoupons(keyword: String?) async throws -> [AccountCollectionCoupon] { throw APIError.notConfigured }
    public func ownedCoupon(id: Int) async throws -> AccountCollectionCoupon { throw APIError.notConfigured }
    private func read<T>(_ operation: (AccountCollectionService, String) async throws -> T) async throws -> T {
        try Task.checkCancellation()
        guard let context = current() else { throw APIError.unauthorized }
        guard let selected = synchronize(), let service else { throw APIError.notConfigured }
        let capturedScope = stamp, capturedViewer = viewerRevision()
        func valid() -> Bool {
            guard !Task.isCancelled, let fresh = current(), ContentDraftContextFence.matches(context, fresh),
                  viewerRevision() == capturedViewer else { return false }
            return synchronize() === selected && stamp == capturedScope
        }
        guard valid() else { throw CancellationError() }
        do {
            let value = try await operation(service, context.session.token)
            guard valid() else { throw CancellationError() }
            return value
        } catch {
            guard valid() else { throw CancellationError() }
            if error as? APIError == .unauthorized { onUnauthorized(context) }
            throw error
        }
    }
}

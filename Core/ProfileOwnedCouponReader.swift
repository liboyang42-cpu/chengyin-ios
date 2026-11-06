import Foundation

/// Entry-specific metadata reader. Reuses the original service and decoder without
/// widening favorites, rewards or the separately approved coupon-code capability.
@MainActor public final class ProfileOwnedCouponReader: AccountCollectionReading {
    private let service: AccountCollectionService?
    private let current: () -> RuntimeDependencyContext?
    private let viewerRevision: () -> UInt64
    private let selectAccess: (RuntimeDependencyContext) -> ProfileOwnedCouponReadAccess?
    private let onUnauthorized: (RuntimeDependencyContext) -> Void
    private var observedContext: RuntimeDependencyContext?
    private var observedViewer: UInt64?
    private var observedAccess: UUID?
    private var stamp = UUID()
    public init(service: AccountCollectionService?, current: @escaping () -> RuntimeDependencyContext?,
                viewerRevision: @escaping () -> UInt64,
                access: @escaping (RuntimeDependencyContext) -> ProfileOwnedCouponReadAccess?,
                onUnauthorized: @escaping (RuntimeDependencyContext) -> Void = { _ in }) {
        self.service = service; self.current = current; self.viewerRevision = viewerRevision
        selectAccess = access; self.onUnauthorized = onUnauthorized
    }
    public var isAuthenticated: Bool { current() != nil }
    public var isConfigured: Bool { synchronize() != nil && service != nil }
    public var isOfflineExample: Bool { false }
    public var scope: UUID { _ = synchronize(); return stamp }
    private func synchronize() -> ProfileOwnedCouponReadAccess? {
        let context = current(), viewer = viewerRevision()
        let selected = context.flatMap { value in selectAccess(value).flatMap { $0.matches(value) ? $0 : nil } }
        let sameContext: Bool
        if let context, let old = observedContext { sameContext = ContentDraftContextFence.matches(old, context) }
        else { sameContext = context == nil && observedContext == nil }
        if !sameContext || viewer != observedViewer || selected?.revision != observedAccess {
            observedContext = context; observedViewer = viewer; observedAccess = selected?.revision; stamp = UUID()
        }
        return selected
    }
    public func favoriteTopics(pageNumber: Int, pageSize: Int) async throws -> TopicPage { throw APIError.notConfigured }
    public func favoritePosts(pageNumber: Int, pageSize: Int) async throws -> AccountCollectionPostPage { throw APIError.notConfigured }
    public func ownedCoupons(keyword: String?) async throws -> [AccountCollectionCoupon] {
        try await read { try await $0.coupons(keyword: keyword, token: $1) }
    }
    public func ownedCoupon(id: Int) async throws -> AccountCollectionCoupon {
        try await read { try await $0.coupon(id: id, token: $1) }
    }
    public func ownedCoupons(keyword: String?, lifetime: OwnedCouponReadLifetime) async throws -> [AccountCollectionCoupon] {
        try await read(lifetime: lifetime) { try await $0.coupons(keyword: keyword, token: $1) }
    }
    public func ownedCoupon(id: Int, lifetime: OwnedCouponReadLifetime) async throws -> AccountCollectionCoupon {
        try await read(lifetime: lifetime) { try await $0.coupon(id: id, token: $1) }
    }
    /// Additional presentation guard for a retained self-profile route. It only narrows
    /// the existing lease and is checked before any unauthorized-session callback.
    public func ownedCoupons(keyword: String?, lifetime: OwnedCouponReadLifetime? = nil,
                             associationIsCurrent: () -> Bool) async throws -> [AccountCollectionCoupon] {
        try await read(lifetime: lifetime, associationIsCurrent: associationIsCurrent) {
            try await $0.coupons(keyword: keyword, token: $1)
        }
    }
    public func ownedCoupon(id: Int, lifetime: OwnedCouponReadLifetime? = nil,
                            associationIsCurrent: () -> Bool) async throws -> AccountCollectionCoupon {
        try await read(lifetime: lifetime, associationIsCurrent: associationIsCurrent) {
            try await $0.coupon(id: id, token: $1)
        }
    }
    private func read<T>(lifetime: OwnedCouponReadLifetime? = nil,
                         associationIsCurrent: () -> Bool = { true },
                         operation: (AccountCollectionService, String) async throws -> T) async throws -> T {
        try Task.checkCancellation(); try lifetime?.check()
        guard associationIsCurrent() else { throw CancellationError() }
        guard let context = current() else { throw APIError.unauthorized }
        guard let selected = synchronize(), let service else { throw APIError.notConfigured }
        let capturedScope = stamp, capturedViewer = viewerRevision()
        if let expected = lifetime?.ownerScope, expected != capturedScope { throw CancellationError() }
        func valid() -> Bool {
            guard !Task.isCancelled, lifetime?.isActive != false, associationIsCurrent(), let fresh = current(),
                  ContentDraftContextFence.matches(context, fresh), viewerRevision() == capturedViewer else { return false }
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

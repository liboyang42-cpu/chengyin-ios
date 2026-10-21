import Foundation
import Observation

/// Memory-only credentials; the UI sees only a random credential-free scope.
public struct AccountCollectionReadSession: Equatable {
    public let accountID: Int
    public let epoch: UInt64
    fileprivate let token: String
    public init(accountID: Int, epoch: UInt64, token: String) throws {
        guard accountID > 0, AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        self.accountID = accountID; self.epoch = epoch; self.token = token
    }
}
@MainActor public protocol AccountCollectionReading: AnyObject {
    var scope: UUID { get }
    var isConfigured: Bool { get }
    var isAuthenticated: Bool { get }
    var isOfflineExample: Bool { get }
    func favoriteTopics(pageNumber: Int, pageSize: Int) async throws -> TopicPage
    func favoritePosts(pageNumber: Int, pageSize: Int) async throws -> AccountCollectionPostPage
    func ownedCoupons(keyword: String?) async throws -> [AccountCollectionCoupon]
    func ownedCoupon(id: Int) async throws -> AccountCollectionCoupon
    func ownedCoupons(keyword: String?, lifetime: OwnedCouponReadLifetime) async throws -> [AccountCollectionCoupon]
    func ownedCoupon(id: Int, lifetime: OwnedCouponReadLifetime) async throws -> AccountCollectionCoupon
}
/// Existing credential-free fixtures retain compatibility. Real session readers fence callbacks too.
public extension AccountCollectionReading {
    func ownedCoupons(keyword: String?, lifetime: OwnedCouponReadLifetime) async throws -> [AccountCollectionCoupon] {
        try lifetime.check()
        if let expected = lifetime.ownerScope, expected != scope { throw CancellationError() }
        do { let value = try await ownedCoupons(keyword: keyword); try lifetime.check(); if let expected = lifetime.ownerScope, expected != scope { throw CancellationError() }; return value }
        catch { try lifetime.check(); if let expected = lifetime.ownerScope, expected != scope { throw CancellationError() }; throw error }
    }
    func ownedCoupon(id: Int, lifetime: OwnedCouponReadLifetime) async throws -> AccountCollectionCoupon {
        try lifetime.check()
        if let expected = lifetime.ownerScope, expected != scope { throw CancellationError() }
        do { let value = try await ownedCoupon(id: id); try lifetime.check(); if let expected = lifetime.ownerScope, expected != scope { throw CancellationError() }; return value }
        catch { try lifetime.check(); if let expected = lifetime.ownerScope, expected != scope { throw CancellationError() }; throw error }
    }
}
@MainActor public final class AccountCollectionSessionReader: AccountCollectionReading {
    private let service: AccountCollectionService?
    private let currentSession: () -> AccountCollectionReadSession?
    private let onUnauthorized: (AccountCollectionReadSession) -> Void
    private var snapshot: AccountCollectionReadSession?
    private var stamp = UUID()
    public var isConfigured: Bool { service != nil }
    public var isAuthenticated: Bool { currentSession() != nil }
    public var isOfflineExample: Bool { false }
    public var scope: UUID {
        let current = currentSession()
        if snapshot != current { snapshot = current; stamp = UUID() }
        return stamp
    }
    public init(service: AccountCollectionService?, currentSession: @escaping () -> AccountCollectionReadSession?,
                onUnauthorized: @escaping (AccountCollectionReadSession) -> Void = { _ in }) {
        self.service = service; self.currentSession = currentSession; self.onUnauthorized = onUnauthorized
        snapshot = currentSession()
    }
    public func favoriteTopics(pageNumber: Int, pageSize: Int) async throws -> TopicPage {
        try await read { try await $0.favorites(pageNumber: pageNumber, pageSize: pageSize, token: $1) }
    }
    public func favoritePosts(pageNumber: Int, pageSize: Int) async throws -> AccountCollectionPostPage {
        try await read { try await $0.favoritePosts(pageNumber: pageNumber, pageSize: pageSize, token: $1) }
    }
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
    private func read<T>(lifetime: OwnedCouponReadLifetime? = nil,
                         _ operation: (AccountCollectionService, String) async throws -> T) async throws -> T {
        try lifetime?.check()
        guard let session = currentSession() else { throw APIError.unauthorized }
        guard let service else { throw APIError.notConfigured }
        let captured = scope
        if let expected = lifetime?.ownerScope, expected != captured { throw CancellationError() }
        try Task.checkCancellation()
        do {
            let value = try await operation(service, session.token)
            try Task.checkCancellation()
            guard lifetime?.isActive != false, currentSession() == session, scope == captured else { throw CancellationError() }
            return value
        } catch {
            guard !Task.isCancelled, lifetime?.isActive != false, currentSession() == session, scope == captured else { throw CancellationError() }
            if error as? APIError == .unauthorized { onUnauthorized(session) }
            throw error
        }
    }
}

/// Each saved-post destination owns its state. Session changes hide private rows
/// immediately, and failed later reads retry the same numbered page.
@MainActor public final class AccountCollectionPostsModel {
    public private(set) var pagination = AccountCollectionPostPagination()
    public private(set) var issue: AccountCollectionIssue?
    public private(set) var moreIssue: AccountCollectionIssue?
    public private(set) var loadedScope: UUID?
    public private(set) var isLoading = false
    public private(set) var isLoadingMore = false
    private var generation: UInt64 = 0
    public init() {}
    public func visibleRows(scope: UUID) -> [SquarePost] { loadedScope == scope ? pagination.rows : [] }
    public func invalidate() {
        generation &+= 1; pagination = AccountCollectionPostPagination(); issue = nil; moreIssue = nil
        loadedScope = nil; isLoading = false; isLoadingMore = false
    }
    public func cancelPending() { generation &+= 1; isLoading = false; isLoadingMore = false }
    public func refresh(scope: UUID, currentScope: () -> UUID, operation: () async throws -> AccountCollectionPostPage) async {
        invalidate()
        let captured = generation
        isLoading = true
        defer { if captured == generation { isLoading = false } }
        do {
            let page = try await operation()
            guard !Task.isCancelled, captured == generation, currentScope() == scope else { return }
            try pagination.accept(page); loadedScope = scope
        } catch {
            guard !Task.isCancelled, !(error is CancellationError), captured == generation, currentScope() == scope else { return }
            issue = AccountCollectionIssue(error); loadedScope = scope
        }
    }
    public func loadMore(scope: UUID, currentScope: () -> UUID, operation: (Int) async throws -> AccountCollectionPostPage) async {
        guard loadedScope == scope, currentScope() == scope, !isLoading, !isLoadingMore, issue == nil, pagination.hasMore else { return }
        let captured = generation
        let pageNumber = pagination.nextPage
        isLoadingMore = true; moreIssue = nil
        defer { if captured == generation { isLoadingMore = false } }
        do {
            let page = try await operation(pageNumber)
            guard !Task.isCancelled, captured == generation, currentScope() == scope else { return }
            try pagination.accept(page)
        } catch {
            guard !Task.isCancelled, !(error is CancellationError), captured == generation, currentScope() == scope else { return }
            if error as? APIError == .unauthorized {
                pagination = AccountCollectionPostPagination(); issue = .login; moreIssue = nil
            } else { moreIssue = AccountCollectionIssue(error) }
        }
    }
}

/// Framework-independent state for fresh coupon list/detail reads. Each view owns its own
/// instance, so a coupon failure can never replace a successful favorites collection.
@MainActor public final class AccountCollectionReadModel<Value> {
    public private(set) var value: Value?
    public private(set) var issue: AccountCollectionIssue?
    public private(set) var loadedScope: UUID?
    public private(set) var isLoading = false
    private var generation: UInt64 = 0
    public init() {}
    public func visibleValue(scope: UUID) -> Value? { loadedScope == scope ? value : nil }
    public func visibleIssue(scope: UUID) -> AccountCollectionIssue? { loadedScope == scope ? issue : nil }
    public func invalidate() {
        generation &+= 1; value = nil; issue = nil; loadedScope = nil; isLoading = false
    }
    public func cancelPending() { generation &+= 1; isLoading = false }
    public func load(scope: UUID, currentScope: () -> UUID, operation: () async throws -> Value) async {
        invalidate()
        let captured = generation
        isLoading = true
        defer { if generation == captured { isLoading = false } }
        do {
            let result = try await operation()
            guard !Task.isCancelled, generation == captured, currentScope() == scope else { return }
            value = result; loadedScope = scope
        } catch {
            guard !Task.isCancelled, !(error is CancellationError), generation == captured, currentScope() == scope else { return }
            issue = AccountCollectionIssue(error); loadedScope = scope
        }
    }
}

/// Raw page length controls continuation; display rows are de-duplicated by topic ID.
/// A failed later page keeps existing rows and its retry does not advance the page number.
@MainActor public final class AccountCollectionFavoritesModel {
    public private(set) var pagination = TopicPagination()
    public private(set) var issue: AccountCollectionIssue?
    public private(set) var moreIssue: AccountCollectionIssue?
    public private(set) var loadedScope: UUID?
    public private(set) var isLoading = false
    public private(set) var isLoadingMore = false
    private var generation: UInt64 = 0
    public init() {}
    public func visibleRows(scope: UUID) -> [TopicSummary] { loadedScope == scope ? pagination.rows : [] }
    public func invalidate() {
        generation &+= 1; pagination.reset(); issue = nil; moreIssue = nil
        loadedScope = nil; isLoading = false; isLoadingMore = false
    }
    public func cancelPending() { generation &+= 1; isLoading = false; isLoadingMore = false }
    public func refresh(scope: UUID, currentScope: () -> UUID, operation: () async throws -> TopicPage) async {
        invalidate()
        let captured = generation
        isLoading = true
        defer { if generation == captured { isLoading = false } }
        do {
            let page = try await operation()
            guard !Task.isCancelled, captured == generation, currentScope() == scope else { return }
            try pagination.accept(page); loadedScope = scope
        } catch {
            guard !Task.isCancelled, !(error is CancellationError), captured == generation, currentScope() == scope else { return }
            issue = AccountCollectionIssue(error); loadedScope = scope
        }
    }
    public func loadMore(scope: UUID, currentScope: () -> UUID, operation: (Int) async throws -> TopicPage) async {
        guard loadedScope == scope, currentScope() == scope, !isLoading, !isLoadingMore, issue == nil, pagination.hasMore else { return }
        let captured = generation
        let pageNumber = pagination.nextPage
        isLoadingMore = true; moreIssue = nil
        defer { if generation == captured { isLoadingMore = false } }
        do {
            let page = try await operation(pageNumber)
            guard !Task.isCancelled, captured == generation, currentScope() == scope else { return }
            try pagination.accept(page)
        } catch {
            guard !Task.isCancelled, !(error is CancellationError), captured == generation, currentScope() == scope else { return }
            if error as? APIError == .unauthorized {
                pagination.reset(); issue = .login; moreIssue = nil
            } else { moreIssue = AccountCollectionIssue(error) }
        }
    }
}

/// Identity captured with a community-gate attempt. Generation is not part of equality:
/// A→B→A keeps the same fields and still must not revive the earlier attempt.
public struct AccountCollectionCommunityGateIdentity: Equatable {
    public let readerID: ObjectIdentifier?
    public let readerScope: UUID?
    public let gateID: ObjectIdentifier?
    public let gateScope: UUID?
    public let authenticated: Bool
    public let configured: Bool
    public init(readerID: ObjectIdentifier?, readerScope: UUID?, gateID: ObjectIdentifier?, gateScope: UUID?,
                authenticated: Bool, configured: Bool) {
        self.readerID = readerID; self.readerScope = readerScope; self.gateID = gateID; self.gateScope = gateScope
        self.authenticated = authenticated; self.configured = configured
    }
}

/// One in-flight or applied read. Object identity matters: a replacement with the same UUID is a new request.
public struct AccountCollectionCommunityGateBinding: Equatable {
    public let readerID: ObjectIdentifier?
    public let readerScope: UUID?
    public let gateID: ObjectIdentifier
    public let gateScope: UUID
    public let authenticated: Bool
    public let configured: Bool
    public let generation: UInt64
    public var identity: AccountCollectionCommunityGateIdentity {
        .init(readerID: readerID, readerScope: readerScope, gateID: gateID, gateScope: gateScope,
              authenticated: authenticated, configured: configured)
    }
    public init(readerID: ObjectIdentifier?, readerScope: UUID?, gateID: ObjectIdentifier, gateScope: UUID,
                authenticated: Bool, configured: Bool, generation: UInt64) {
        self.readerID = readerID; self.readerScope = readerScope; self.gateID = gateID; self.gateScope = gateScope
        self.authenticated = authenticated; self.configured = configured; self.generation = generation
    }
}

/// Scoped community-feature gate state for Account Favorites (`我的收藏`).
/// Nil, signed-out, unconfigured, pending, denied, and failed all keep posts closed.
/// A failed attempt leaves `resolvedScope == nil` so the same scope can retry.
/// Auto-load and manual retry share `perform`; an older completion cannot overwrite a newer one.
@MainActor @Observable public final class AccountCollectionCommunityGateModel {
    public private(set) var features: SquareCommunityFeatures?
    public private(set) var resolvedScope: UUID?
    public private(set) var failed = false
    public private(set) var isLoading = false
    public private(set) var attempt: AccountCollectionCommunityGateBinding?
    public private(set) var applied: AccountCollectionCommunityGateBinding?
    private var generation: UInt64 = 0

    public init() {}

    /// Missing gate, pending, denial, and failure all stay closed. A nil gate does not pass.
    public func postsAllowed(hasGate: Bool, currentScope: UUID?) -> Bool {
        guard hasGate, let currentScope, !isLoading, !failed else { return false }
        return resolvedScope == currentScope && features?.read == true
    }

    /// Posts open only for the current reader and gate objects, scopes, and auth configuration.
    public func postsAllowed(reader: any AccountCollectionReading, gate: (any SquareCommunityFeatureReading)?) -> Bool {
        guard let gate, reader.isAuthenticated, reader.isConfigured else { return false }
        guard postsAllowed(hasGate: true, currentScope: gate.scope), let applied else { return false }
        return applied.identity == AccountCollectionCommunityGateIdentity(
            readerID: ObjectIdentifier(reader), readerScope: reader.scope,
            gateID: ObjectIdentifier(gate), gateScope: gate.scope, authenticated: true, configured: true)
    }

    public func invalidate() {
        generation &+= 1
        features = nil
        resolvedScope = nil
        failed = false
        isLoading = false
        attempt = nil
        applied = nil
    }

    /// Drops a stored or in-flight result when the live reader, gate, scope, or auth no longer matches.
    public func invalidateIfIdentityChanged(
        reader: @escaping @MainActor () -> (any AccountCollectionReading)?,
        gate: @escaping @MainActor () -> (any SquareCommunityFeatureReading)?
    ) {
        let live = Self.identity(reader: reader(), gate: gate(), authenticated: reader()?.isAuthenticated == true,
                                 configured: reader()?.isConfigured == true)
        if let stored = attempt?.identity ?? applied?.identity, stored != live { invalidate() }
    }

    public func load(
        gate: (any SquareCommunityFeatureReading)?,
        isAuthenticated: Bool,
        isConfigured: Bool,
        forceRetry: Bool = false
    ) async {
        let pinned = gate
        let auth = isAuthenticated
        let config = isConfigured
        await perform(reader: { nil }, gate: { pinned }, authenticated: { auth }, configured: { config },
                      forceRetry: forceRetry, requireReader: false)
    }

    public func load(
        reader: @escaping @MainActor () -> (any AccountCollectionReading)?,
        gate: @escaping @MainActor () -> (any SquareCommunityFeatureReading)?,
        forceRetry: Bool = false
    ) async {
        await perform(reader: reader, gate: gate, authenticated: { reader()?.isAuthenticated == true },
                      configured: { reader()?.isConfigured == true }, forceRetry: forceRetry, requireReader: true)
    }

    private static func identity(reader: (any AccountCollectionReading)?, gate: (any SquareCommunityFeatureReading)?,
                                 authenticated: Bool, configured: Bool) -> AccountCollectionCommunityGateIdentity {
        .init(readerID: reader.map { ObjectIdentifier($0) }, readerScope: reader?.scope,
              gateID: gate.map { ObjectIdentifier($0) }, gateScope: gate?.scope,
              authenticated: authenticated, configured: configured)
    }

    private func perform(
        reader: @escaping @MainActor () -> (any AccountCollectionReading)?,
        gate: @escaping @MainActor () -> (any SquareCommunityFeatureReading)?,
        authenticated: @escaping @MainActor () -> Bool,
        configured: @escaping @MainActor () -> Bool,
        forceRetry: Bool,
        requireReader: Bool
    ) async {
        if requireReader, reader() == nil { invalidate(); return }
        let auth = authenticated()
        let config = configured()
        guard let gateNow = gate(), auth, config else { invalidate(); return }
        let identity = Self.identity(reader: reader(), gate: gateNow, authenticated: auth, configured: config)
        if let applied, applied.identity != identity || (resolvedScope != nil && resolvedScope != identity.gateScope) {
            invalidate()
        }
        if !forceRetry, !failed, !isLoading, resolvedScope == identity.gateScope, applied?.identity == identity { return }
        if isLoading, !forceRetry, attempt?.identity == identity { return }
        guard let gateID = identity.gateID, let gateScope = identity.gateScope else { invalidate(); return }
        generation &+= 1
        let captured = generation
        let binding = AccountCollectionCommunityGateBinding(
            readerID: identity.readerID, readerScope: identity.readerScope, gateID: gateID, gateScope: gateScope,
            authenticated: auth, configured: config, generation: captured)
        attempt = binding
        failed = false
        features = nil
        resolvedScope = nil
        applied = nil
        isLoading = true
        defer { if captured == generation { isLoading = false; if attempt?.generation == captured { attempt = nil } } }
        do {
            let value = try await gateNow.communityFeatures()
            guard accept(captured, binding, reader: reader, gate: gate, authenticated: authenticated, configured: configured) else { return }
            features = value
            resolvedScope = gateScope
            failed = false
            applied = binding
        } catch {
            guard accept(captured, binding, reader: reader, gate: gate, authenticated: authenticated, configured: configured),
                  !(error is CancellationError) else { return }
            features = nil
            resolvedScope = nil
            failed = true
            applied = binding
        }
    }

    private func accept(
        _ captured: UInt64,
        _ binding: AccountCollectionCommunityGateBinding,
        reader: @MainActor () -> (any AccountCollectionReading)?,
        gate: @MainActor () -> (any SquareCommunityFeatureReading)?,
        authenticated: @MainActor () -> Bool,
        configured: @MainActor () -> Bool
    ) -> Bool {
        guard !Task.isCancelled, captured == generation else { return false }
        let auth = authenticated()
        let config = configured()
        guard let gateNow = gate(), auth, config else { return false }
        return Self.identity(reader: reader(), gate: gateNow, authenticated: auth, configured: config) == binding.identity
    }
}

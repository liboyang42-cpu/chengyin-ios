import Foundation
import Observation

/// Externally supplied original bounded query and existing grant provider. Never issues a grant or acquires location.
@MainActor @Observable public final class CityOrderedMapRuntimeSelection {
    public let context: RuntimeDependencyContext
    public let revision: UInt64
    public let scope: CityCurrentSnapshotScope
    public let expiresAt: Date
    public private(set) var isRevoked = false
    private let provider: () -> CityOrderedMapReadGrant?
    @ObservationIgnored private var expiryTask: Task<Void, Never>?
    public init(context: RuntimeDependencyContext, revision: UInt64, query: CityCurrentSnapshotQuery, expiresAt: Date,
                grant: @escaping () -> CityOrderedMapReadGrant? = { nil }) throws {
        let duration = expiresAt.timeIntervalSinceNow
        guard context.market == .china, context.role == context.session.role, !context.role.isEmpty,
              duration.isFinite, duration > 0, duration <= 86400 else { throw APIError.invalidConfiguration }
        self.context = context; self.revision = revision; self.expiresAt = expiresAt; provider = grant
        scope = try .init(market: context.market, baseURL: context.baseURL, namespace: context.session.namespace,
            accountID: context.session.accountID, epoch: context.session.epoch, token: context.session.token, query: query)
        expiryTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000)); try Task.checkCancellation() }
            catch { return }
            self?.revoke()
        }
    }
    deinit { expiryTask?.cancel() }
    public func revoke() { isRevoked = true; expiryTask?.cancel(); expiryTask = nil }
    public func matches(_ current: RuntimeDependencyContext?, revision: UInt64, now: Date = Date()) -> Bool {
        guard !isRevoked, now < expiresAt, self.revision == revision, let current,
              current.role == current.session.role else { return false }
        return ContentDraftContextFence.matches(context, current) && context.session == current.session
    }
    public func issued() -> CityOrderedMapReadGrant? {
        guard !isRevoked, Date() < expiresAt, let grant = provider(), !grant.isRevoked, grant.scope == scope else { return nil }
        return grant
    }
}

/// Independent externally supplied ordered capability; never borrow a current-only read grant.
@MainActor public final class CityOrderedMapReadGrant {
    public let scope: CityCurrentSnapshotScope
    public private(set) var isRevoked = false
    public init(scope: CityCurrentSnapshotScope) { self.scope = scope }
    public func revoke() { isRevoked = true }
}

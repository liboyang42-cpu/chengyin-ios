import Foundation

/// Independently issued local capability for the original owned address contract.
/// Authentication, a role, and an endpoint URL never manufacture this capability.
/// A dynamic selector must revoke the old object before removing/replacing its result.
/// Revocation is terminal; restoring the same object cannot restore its authority.
@MainActor public final class ProfileParticipantAccess {
    public static let readPaths: Set<String> = ["api/user/address/list", "api/user/address/info"]
    public static let writePaths: Set<String> = ["api/user/address/action", "api/user/address/delete"]
    public let context: RuntimeDependencyContext
    public let endpoints: OperationEndpointApproval
    public let permitsWrites: Bool
    public let expiresAt: Date
    public let revision = UUID()
    public private(set) var isRevoked = false
    private var observers: [UUID: () -> Void] = [:]
    private var expiryTask: Task<Void, Never>?

    public init(context: RuntimeDependencyContext, permitsWrites: Bool, expiresAt: Date) throws {
        let duration = expiresAt.timeIntervalSinceNow
        guard context.market == .china, ["player", "club", "merchant"].contains(context.role),
              context.session.role.utf8.elementsEqual(context.role.utf8),
              duration.isFinite, duration > 0, duration <= 86_400 else { throw APIError.invalidConfiguration }
        self.context = context; self.permitsWrites = permitsWrites; self.expiresAt = expiresAt
        endpoints = try OperationEndpointApproval(baseURL: context.baseURL, namespace: context.session.namespace,
            accountID: context.session.accountID,
            paths: permitsWrites ? Self.readPaths.union(Self.writePaths) : Self.readPaths)
        expiryTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(max(0, min(expiresAt.timeIntervalSinceNow, 86_400)) * 1_000_000_000))
                try Task.checkCancellation()
            } catch { return }
            self?.revoke()
        }
    }
    deinit { expiryTask?.cancel() }
    public func matches(_ current: RuntimeDependencyContext, now: Date = Date()) -> Bool {
        !isRevoked && now < expiresAt && ContentDraftContextFence.matches(current, context)
            && current.session.role.utf8.elementsEqual(context.session.role.utf8)
    }
    public func revoke() {
        guard !isRevoked else { return }
        isRevoked = true; expiryTask?.cancel(); expiryTask = nil
        let callbacks = Array(observers.values); observers.removeAll()
        callbacks.forEach { $0() }
    }
    @discardableResult public func observeRevocation(_ action: @escaping () -> Void) -> UUID {
        let id = UUID()
        if isRevoked { action() } else { observers[id] = action }
        return id
    }
    public func removeObserver(_ id: UUID) { observers[id] = nil }
}

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Only the original evidence GET routes. Never forwards a consent writer or caller-selected owner/purpose.
@MainActor public final class UsageConsentReadScopedTransport: HTTPTransport {
    private let context: RuntimeDependencyContext
    private let approval: UsageConsentReadApproval
    private let underlying: any HTTPTransport
    private let current: () -> RuntimeDependencyContext?
    private let stillApproved: () -> Bool
    public init(context: RuntimeDependencyContext, approval: UsageConsentReadApproval, underlying: any HTTPTransport,
                current: @escaping () -> RuntimeDependencyContext?, stillApproved: @escaping () -> Bool) {
        self.context = context; self.approval = approval; self.underlying = underlying
        self.current = current; self.stillApproved = stillApproved
    }
    private var isCurrent: Bool { UsageConsentReadScope.matches(current(), context) && stillApproved() }
    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        try Task.checkCancellation()
        guard isCurrent, let route = UsageConsentReadRoute(request: request, baseURL: context.baseURL),
              approval.allows(context, path: route.path), request.value(forHTTPHeaderField: "Accept") == "application/json",
              request.value(forHTTPHeaderField: "Authorization").map({ Data($0.utf8) }) == Data(context.session.token.utf8) else {
            throw UsageConsentReadFailure.unavailable
        }
        let value = try await underlying.send(request)
        try Task.checkCancellation()
        guard isCurrent else { throw UsageConsentReadFailure.stale }
        return value
    }
}

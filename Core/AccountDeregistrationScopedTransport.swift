import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Dedicated original routes only. The normal host supplies a full viewer-lifetime closure.
@MainActor public final class AccountDeregistrationScopedTransport: HTTPTransport {
    private let context: RuntimeDependencyContext
    private let approval: AccountDeregistrationOriginalApproval
    private let underlying: any HTTPTransport
    private let current: () -> RuntimeDependencyContext?
    private let stillApproved: () -> Bool
    public init(context: RuntimeDependencyContext, approval: AccountDeregistrationOriginalApproval,
                underlying: any HTTPTransport, current: @escaping () -> RuntimeDependencyContext?,
                stillApproved: @escaping () -> Bool) {
        self.context = context; self.approval = approval; self.underlying = underlying
        self.current = current; self.stillApproved = stillApproved
    }
    private var isCurrent: Bool {
        ContentDraftContextFence.matches(current(), context) &&
            current()?.session.role.utf8.elementsEqual(context.session.role.utf8) == true &&
            context.role.utf8.elementsEqual(context.session.role.utf8) && approval.matches(context) && stillApproved()
    }
    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        try Task.checkCancellation()
        guard isCurrent, AccountDeregistrationOriginalClient.accepts(request, context: context, approval: approval) else {
            throw ComplianceFailure.unavailable
        }
        let result = try await underlying.send(request)
        try Task.checkCancellation()
        // Authentication failures do not bypass retirement or expose another lifetime's callback.
        guard isCurrent else { throw ComplianceFailure.staleSession }
        return result
    }
}

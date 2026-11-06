import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor public final class SupportTicketReadScopedTransport: HTTPTransport {
    private let approval: SupportTicketReadApproval
    private let underlying: any HTTPTransport
    private let current: () -> RuntimeDependencyContext?
    private let stillSelected: () -> Bool
    public init(approval: SupportTicketReadApproval, underlying: any HTTPTransport,
                current: @escaping () -> RuntimeDependencyContext?, stillSelected: @escaping () -> Bool) {
        self.approval = approval; self.underlying = underlying; self.current = current; self.stillSelected = stillSelected
    }
    private var isCurrent: Bool { current().map { approval.matches($0) } == true && stillSelected() }
    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        try Task.checkCancellation()
        guard isCurrent, let route = SupportTicketReadRoute(request: request, baseURL: approval.context.baseURL), approval.capabilities.contains(route.capability),
              request.value(forHTTPHeaderField: "Accept") == "application/json", request.value(forHTTPHeaderField: "Content-Type") == "application/json",
              request.value(forHTTPHeaderField: "Cache-Control") == "no-store", request.value(forHTTPHeaderField: "Pragma") == "no-cache",
              request.value(forHTTPHeaderField: "Authorization").map({ Data($0.utf8) }) == Data(approval.context.session.token.utf8) else { throw SupportTicketReadFailure.disabled }
        let value = try await underlying.send(request)
        try Task.checkCancellation(); guard isCurrent else { throw SupportTicketReadFailure.stale }; return value
    }
}

public enum SupportTicketReadScope {
    public static func matches(_ current: RuntimeDependencyContext?, _ captured: RuntimeDependencyContext) -> Bool {
        ContentDraftContextFence.matches(current, captured) && current?.session.role.utf8.elementsEqual(captured.session.role.utf8) == true && captured.role.utf8.elementsEqual(captured.session.role.utf8)
    }
}

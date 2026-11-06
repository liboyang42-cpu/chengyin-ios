import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor public final class NPCChatDataReadScopedTransport: HTTPTransport {
    private let approval: NPCChatDataReadApproval
    private let underlying: any HTTPTransport
    private let current: () -> RuntimeDependencyContext?
    private let stillSelected: () -> Bool
    public init(approval: NPCChatDataReadApproval, underlying: any HTTPTransport,
                current: @escaping () -> RuntimeDependencyContext?, stillSelected: @escaping () -> Bool) {
        self.approval = approval; self.underlying = underlying; self.current = current; self.stillSelected = stillSelected
    }
    private var isCurrent: Bool { current().map { approval.matches($0) } == true && stillSelected() }
    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        try Task.checkCancellation()
        guard isCurrent, NPCChatDataReadRoute.accepts(request, baseURL: approval.context.baseURL),
              request.value(forHTTPHeaderField: "Accept") == "application/json",
              request.value(forHTTPHeaderField: "Cache-Control") == "no-store", request.value(forHTTPHeaderField: "Pragma") == "no-cache",
              request.value(forHTTPHeaderField: "Authorization").map({ Data($0.utf8) }) == Data(approval.context.session.token.utf8) else { throw NPCChatDataFailure.unavailable }
        let value = try await underlying.send(request)
        try Task.checkCancellation(); guard isCurrent else { throw NPCChatDataFailure.staleSession }; return value
    }
}

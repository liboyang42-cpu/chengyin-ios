import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor public final class MemberReportProgressScopedTransport: HTTPTransport {
    private let approval: MemberReportProgressApproval
    private let underlying: any HTTPTransport
    private let current: () -> RuntimeDependencyContext?
    private let stillSelected: () -> Bool
    public init(approval: MemberReportProgressApproval, underlying: any HTTPTransport,
                current: @escaping () -> RuntimeDependencyContext?, stillSelected: @escaping () -> Bool) {
        self.approval = approval; self.underlying = underlying; self.current = current; self.stillSelected = stillSelected
    }
    private var isCurrent: Bool { current().map { approval.matches($0) } == true && stillSelected() }
    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        try Task.checkCancellation()
        guard isCurrent, let route = MemberReportProgressRoute(request: request, baseURL: approval.context.baseURL),
              approval.capabilities.contains(route.capability), request.value(forHTTPHeaderField: "Accept") == "application/json",
              request.value(forHTTPHeaderField: "Authorization").map({ Data($0.utf8) }) == Data(approval.context.session.token.utf8) else { throw MemberReportProgressFailure.disabled }
        let value = try await underlying.send(request)
        try Task.checkCancellation()
        guard isCurrent else { throw MemberReportProgressFailure.stale }
        return value
    }
}

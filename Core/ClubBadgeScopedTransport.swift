import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Exact approved badge requests only. No generic runtime route registration or grant creation.
@MainActor public final class ClubBadgeScopedTransport: HTTPTransport {
    private let context: RuntimeDependencyContext
    private let clubID: Int
    private let issued: ClubBadgeManagementApproval
    private let underlying: any HTTPTransport
    private let current: () -> RuntimeDependencyContext?
    private let approval: () -> ClubBadgeManagementApproval?
    public init(context: RuntimeDependencyContext, clubID: Int, approval: ClubBadgeManagementApproval,
                underlying: any HTTPTransport, current: @escaping () -> RuntimeDependencyContext?,
                currentApproval: @escaping () -> ClubBadgeManagementApproval?) {
        self.context = context; self.clubID = clubID; issued = approval; self.underlying = underlying
        self.current = current; self.approval = currentApproval
    }
    private func check(_ request: URLRequest) throws {
        try Task.checkCancellation()
        guard current() == context, let latest = approval(), latest.revision == issued.revision,
              let route = ClubBadgeManagementRoute(request: request, baseURL: context.baseURL), route.clubID == clubID,
              latest.permits(context, clubID: clubID, writing: route.writing),
              issued.permits(context, clubID: clubID, writing: route.writing),
              request.url?.query == nil, request.url?.fragment == nil,
              !request.httpShouldHandleCookies, request.value(forHTTPHeaderField: "Cookie") == nil,
              request.value(forHTTPHeaderField: "Transfer-Encoding") == nil,
              request.value(forHTTPHeaderField: "Authorization")?.utf8.elementsEqual(context.session.token.utf8) == true,
              request.value(forHTTPHeaderField: "Content-Length") == String(request.httpBody?.count ?? 0),
              request.cachePolicy == .reloadIgnoringLocalCacheData,
              request.value(forHTTPHeaderField: "Cache-Control") == "no-store",
              request.value(forHTTPHeaderField: "Pragma") == "no-cache" else { throw APIError.notConfigured }
    }
    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        try check(request)
        let result: (Data, Int)
        do { result = try await underlying.send(request) }
        catch { try check(request); throw error }
        try check(request)
        guard result.0.count <= 1_048_576 else { throw ClubBadgeManagementFailure.invalid }
        return result
    }
}

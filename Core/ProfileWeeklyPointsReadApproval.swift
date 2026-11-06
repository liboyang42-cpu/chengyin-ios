import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A bounded independently supplied read lease. Authentication never creates one.
/// Revoke the prior lease before removing or replacing its selector result.
@available(macOS 14.0, *)
@MainActor @Observable public final class ProfileWeeklyPointsReadApproval {
    public let context: RuntimeDependencyContext
    public let endpoints: OperationEndpointApproval
    public let expiresAt: Date
    public let revision = UUID()
    public private(set) var isRevoked = false
    @ObservationIgnored private var expiryTask: Task<Void, Never>?
    public init(context: RuntimeDependencyContext, expiresAt: Date) throws {
        let duration = expiresAt.timeIntervalSinceNow
        guard context.market == .china, ["player", "club", "merchant"].contains(context.role),
              context.session.accountID > 0, AuthRequestBuilder.isValidToken(context.session.token),
              duration.isFinite, duration > 0, duration <= 86_400 else { throw APIError.invalidConfiguration }
        self.endpoints = try OperationEndpointApproval(baseURL: context.baseURL,
            namespace: context.session.namespace, accountID: context.session.accountID,
            paths: [ProfileWeeklyPointsReadRoute.path])
        self.context = context; self.expiresAt = expiresAt
        expiryTask = Task { @MainActor [weak self] in
            let remaining = max(0, min(expiresAt.timeIntervalSinceNow, 86_400))
            do {
                if remaining > 0 { try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000)) }
                try Task.checkCancellation()
            } catch { return }
            self?.revoke()
        }
    }
    deinit { expiryTask?.cancel() }
    public func revoke() { isRevoked = true; expiryTask?.cancel(); expiryTask = nil }
    public func matches(_ current: RuntimeDependencyContext, now: Date = Date()) -> Bool {
        !isRevoked && now < expiresAt && ContentDraftContextFence.matches(context, current)
    }
}

public enum ProfileWeeklyPointsReadRoute {
    public static let path = "api/user/points/statistics"
    public static func accepts(_ request: URLRequest, baseURL: URL) -> Bool {
        guard let url = request.url, url.query == nil, url.fragment == nil,
              url.absoluteString.utf8.elementsEqual(baseURL.appendingPathComponent(path).absoluteString.utf8),
              request.httpMethod == "POST", request.httpBody == nil, request.httpBodyStream == nil,
              request.value(forHTTPHeaderField: "Accept") == "application/json",
              request.value(forHTTPHeaderField: "Content-Type") == nil else { return false }
        return true
    }
}

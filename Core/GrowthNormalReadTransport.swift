import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Independently reviewed, memory-only authority for frozen58's three own-growth reads.
/// Authentication, a public profile, and unrelated read grants cannot create this lease.
/// The owner must revoke the previous lease before replacing/removing its selector.
@available(macOS 14.0, *)
@MainActor @Observable public final class GrowthNormalReadApproval {
    public static let authorityCommit = "58f4cc429b0d0e3035ccdf1bd4a9c3dfd76eb9a4"
    public let context: RuntimeDependencyContext
    public let revision = UUID()
    public let expiresAt: Date
    public private(set) var isRevoked = false
    @ObservationIgnored private var expiryTask: Task<Void, Never>?

    public init(context: RuntimeDependencyContext, expiresAt: Date) throws {
        _ = try APIConfiguration(baseURL: context.baseURL)
        let duration = expiresAt.timeIntervalSinceNow
        guard context.market == .china, ["player", "club", "merchant"].contains(context.role),
              context.session.accountID > 0, !context.session.namespace.isEmpty,
              AuthRequestBuilder.isValidToken(context.session.token),
              duration.isFinite, duration > 0, duration <= 86_400 else { throw APIError.invalidConfiguration }
        self.context = context; self.expiresAt = expiresAt
        // Existing native lease bound, not a claim about backend/product expiration.
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
    public func matches(_ context: RuntimeDependencyContext, now: Date = Date()) -> Bool {
        !isRevoked && now < expiresAt && ContentDraftContextFence.matches(self.context, context)
    }
}

/// Exact existing GrowthCenterService wire shape, not an extensible generic allowlist.
/// Anonymous leaderboard has no frozen58 producer and deliberately has no route here.
public enum GrowthNormalReadRoute: String, CaseIterable {
    case center = "api/growth/center"
    case progress = "api/play/growth"
    case completed = "api/play/my-completed"

    public init?(request: URLRequest, baseURL: URL) {
        guard let url = request.url, url.query == nil, url.fragment == nil,
              url.user == nil, url.password == nil,
              request.httpMethod == "POST", request.httpBody == Data("{}".utf8), request.httpBodyStream == nil,
              request.value(forHTTPHeaderField: "Content-Type") == "application/json",
              request.value(forHTTPHeaderField: "Accept") == "application/json",
              let route = Self.allCases.first(where: {
                  url.absoluteString.utf8.elementsEqual(baseURL.appendingPathComponent($0.rawValue).absoluteString.utf8)
              }) else { return nil }
        // No alternate identity, cookie, forwarding header or scope is accepted.
        let expectedHeaders: Set<String> = ["accept", "authorization", "content-type"]
        guard Set((request.allHTTPHeaderFields ?? [:]).keys.map { $0.lowercased() }) == expectedHeaders else { return nil }
        self = route
    }
    @MainActor public static func accepts(_ request: URLRequest, context: RuntimeDependencyContext,
                                         approval: GrowthNormalReadApproval) -> Bool {
        approval.matches(context) && Self(request: request, baseURL: context.baseURL) != nil &&
            request.value(forHTTPHeaderField: "Authorization").map { Data($0.utf8) } == Data(context.session.token.utf8)
    }
}

/// Owns overview work from toolbar, pull-to-refresh and scene lifecycle alike.
/// Cancel reaches the reader, not just the visible generation, so late 401s from
/// a canceled presentation cannot expire a still-current session.
@MainActor public final class GrowthNormalReadTask {
    private var task: Task<Void, Never>?
    public init() {}
    public func cancel() { task?.cancel(); task = nil }
    public func start(_ operation: @escaping @MainActor () async -> Void) { _ = replace(operation) }
    public func run(_ operation: @escaping @MainActor () async -> Void) async {
        let current = replace(operation)
        await withTaskCancellationHandler(operation: { await current.value }, onCancel: { current.cancel() })
    }
    private func replace(_ operation: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        cancel()
        let current = Task { @MainActor in
            guard !Task.isCancelled else { return }
            await operation()
        }
        task = current
        return current
    }
}

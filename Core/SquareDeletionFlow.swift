import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Dormant Square post/comment deletion (mini-program `post-actions` 删除 and comment 删除).
/// Source wire (`utils/community-post-api.js`):
///   DELETE api/v1/community/posts/{id}                   {expectedVersion, requestId}
///   DELETE api/v1/community/posts/{postId}/comments/{id} {expectedVersion, requestId}
/// Nothing dispatches unless an explicit reviewed endpoint approval names the route template
/// for the current deployment, namespace and account. The allowlist is empty today.
public enum SquareDeletionTarget: Equatable, Hashable {
    case post(id: Int, expectedVersion: Int)
    case comment(postID: Int, commentID: Int, expectedVersion: Int)
    public static let postRoute = "api/v1/community/posts/{id}"
    public static let commentRoute = "api/v1/community/posts/{postId}/comments/{id}"
    public var routeTemplate: String { if case .post = self { return Self.postRoute }; return Self.commentRoute }
    public var path: String {
        switch self {
        case .post(let id, _): return "api/v1/community/posts/\(id)"
        case .comment(let postID, let commentID, _): return "api/v1/community/posts/\(postID)/comments/\(commentID)"
        }
    }
    public var expectedVersion: Int {
        switch self { case .post(_, let version), .comment(_, _, let version): return version }
    }
    public var isValid: Bool {
        switch self {
        case .post(let id, let version): return id > 0 && version >= 0
        case .comment(let postID, let commentID, let version): return postID > 0 && commentID > 0 && version >= 0
        }
    }
    /// Only versioned community content can be deleted; legacy rows have no concurrency version.
    public init?(post: SquarePost) {
        guard post.generation == .communityV1, let version = post.version else { return nil }
        self = .post(id: post.id, expectedVersion: version); guard isValid else { return nil }
    }
    public init?(post: SquarePost, comment: SquareComment) {
        guard comment.generation == .communityV1, comment.lifecycle != "DELETED", let version = comment.version,
              comment.communityPostID == nil || comment.communityPostID == post.id else { return nil }
        self = .comment(postID: post.id, commentID: comment.id, expectedVersion: version); guard isValid else { return nil }
    }
}

public enum SquareDeletionOutcome: Equatable {
    case deleted
    case rejected(code: Int, message: String?)
    /// Dispatched but the result is unknown; the same request ID must be reused or read back.
    case unknown
}

public struct SquareDeletionService {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    public init(configuration: APIConfiguration, transport: any HTTPTransport) { self.configuration = configuration; self.transport = transport }
    public func request(_ target: SquareDeletionTarget, requestID: String, token: String) throws -> URLRequest {
        guard target.isValid, SquareDeletionRequestID.isValid(requestID), AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent(target.path))
        request.httpMethod = "DELETE"; request.httpShouldHandleCookies = false
        request.cachePolicy = .reloadIgnoringLocalCacheData; request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["expectedVersion": target.expectedVersion, "requestId": requestID], options: [.sortedKeys])
        return request
    }
    /// Never retries. Transport errors, 5xx, non-JSON bodies and cancellation after dispatch are `.unknown`.
    public func delete(_ target: SquareDeletionTarget, requestID: String, token: String) async throws -> SquareDeletionOutcome {
        let built = try request(target, requestID: requestID, token: token)
        let data: Data, status: Int
        do { (data, status) = try await transport.send(built) } catch { return .unknown }
        if status == 401 { throw APIError.unauthorized }
        guard (200..<500).contains(status),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return .unknown }
        let code = (root["code"] as? Int) ?? (root["code"] as? String).flatMap(Int.init) ?? status
        if code == 401 { throw APIError.unauthorized }
        if (200..<300).contains(status) && code == 200 { return .deleted }
        guard (400..<500).contains(code) || (400..<500).contains(status) else { return .unknown }
        return .rejected(code: code, message: root["msg"] as? String)
    }
}

enum SquareDeletionRequestID {
    static func make() -> String { "sq-delete-" + UUID().uuidString.lowercased() }
    static func isValid(_ value: String) -> Bool {
        (8...80).contains(value.count) && value.utf8.allSatisfy { (48...57).contains($0) || (97...122).contains($0) || $0 == 45 }
    }
}

/// Explicit two-step deletion: `prepare` shows the confirmation, `confirm` dispatches once.
/// The request ID is stable per target until a terminal result; an unknown result can only be
/// resolved by readback (`resolveUnknown`) or an exact same-ID retry.
@MainActor @Observable public final class SquareDeletionCoordinator {
    public enum Phase: Equatable { case idle, confirming(SquareDeletionTarget), sending(SquareDeletionTarget), done(SquareDeletionTarget), rejected(SquareDeletionTarget, String?), unknown(SquareDeletionTarget), disabled }
    public private(set) var phase: Phase = .idle
    private var requestIDs: [SquareDeletionTarget: String] = [:]
    private let service: SquareDeletionService?
    private let approval: OperationEndpointApproval?
    private let configuration: APIConfiguration?
    private let current: () -> (namespace: String, accountID: Int, token: String)?
    private var generation = 0
    public init(service: SquareDeletionService?, configuration: APIConfiguration?, approval: OperationEndpointApproval?,
                current: @escaping () -> (namespace: String, accountID: Int, token: String)?) {
        self.service = service; self.configuration = configuration; self.approval = approval; self.current = current
    }
    /// Disabled coordinator for hosts without a reviewed approval (the default everywhere today).
    public static func disabled() -> SquareDeletionCoordinator { .init(service: nil, configuration: nil, approval: nil, current: { nil }) }
    public func isAllowed(_ target: SquareDeletionTarget) -> Bool {
        guard target.isValid, service != nil, let approval, let configuration, let session = current() else { return false }
        return approval.allows(configuration: configuration, namespace: session.namespace, accountID: session.accountID, path: target.routeTemplate)
    }
    public func requestID(for target: SquareDeletionTarget) -> String? { requestIDs[target] }
    public func prepare(_ target: SquareDeletionTarget) {
        guard !isBusy else { return }
        if case .unknown(let pending) = phase, pending != target { return }  // never start another while one is unresolved
        phase = isAllowed(target) ? .confirming(target) : .disabled
    }
    public func cancel() { if case .confirming = phase { phase = .idle }; if phase == .disabled { phase = .idle } }
    public var isBusy: Bool { if case .sending = phase { return true }; return false }
    public func confirm() async {
        guard case .confirming(let target) = phase, isAllowed(target), let service, let session = current() else { return }
        let id = requestIDs[target] ?? SquareDeletionRequestID.make()
        requestIDs[target] = id
        generation += 1; let operation = generation
        phase = .sending(target)
        let outcome: SquareDeletionOutcome
        do { outcome = try await service.delete(target, requestID: id, token: session.token) }
        catch { outcome = (error as? APIError) == .unauthorized ? .rejected(code: 401, message: nil) : .unknown }
        guard operation == generation else { return }
        switch outcome {
        case .deleted: requestIDs[target] = nil; phase = .done(target)
        case .rejected(_, let message): requestIDs[target] = nil; phase = .rejected(target, message)
        case .unknown: phase = .unknown(target)
        }
    }
    /// Unknown-outcome readback. `stillPresent == false` (detail/comment gone or DELETED) confirms deletion;
    /// `true` allows a confirmation with the same request ID. Read failure keeps the unknown lock.
    public func resolveUnknown(stillPresent: Bool?) {
        guard case .unknown(let target) = phase, let stillPresent else { return }
        if stillPresent { phase = .confirming(target) } else { requestIDs[target] = nil; phase = .done(target) }
    }
    public func acknowledge() {
        switch phase { case .done, .rejected: phase = .idle; default: break }
    }
    /// Account/session change retires everything; an unknown request ID is not carried across accounts.
    public func retire() { generation += 1; requestIDs = [:]; phase = .idle }
}

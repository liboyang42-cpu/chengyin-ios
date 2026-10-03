import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Independent deployment review for exactly two signed-in content projections.
/// Does not authorize runtime, registration, mutation or provider requests.
public enum SignedInContentDetailReadApproval: Equatable { case activityAndTopic }

/// The native contract deliberately accepts fewer shapes than a generic form endpoint.
public enum SignedInContentDetailReadRoute: CaseIterable, Equatable {
    case activity, topic
    public var path: String {
        switch self {
        case .activity: return "api/activity/info"
        case .topic: return "api/topic/info-to-user"
        }
    }
    public init?(url: URL, baseURL: URL) {
        guard url.query == nil, url.fragment == nil,
              let route = Self.allCases.first(where: {
                  url.absoluteString.utf8.elementsEqual(baseURL.appendingPathComponent($0.path).absoluteString.utf8)
              }) else { return nil }
        self = route
    }
    public func accepts(_ request: URLRequest) -> Bool {
        guard request.url?.query == nil, request.url?.fragment == nil,
              request.httpMethod == "POST", request.httpBodyStream == nil,
              let body = request.httpBody, body.count <= 512,
              let text = String(data: body, encoding: .utf8),
              let type = request.value(forHTTPHeaderField: "Content-Type"),
              type.hasPrefix("multipart/form-data; boundary=") else { return false }
        let boundary = String(type.dropFirst("multipart/form-data; boundary=".count))
        let prefix = "--\(boundary)\r\nContent-Disposition: form-data; name=\"id\"\r\n\r\n"
        let suffix = "\r\n--\(boundary)--\r\n"
        guard text.hasPrefix(prefix), text.hasSuffix(suffix), text.count > prefix.count + suffix.count else { return false }
        let value = String(text.dropFirst(prefix.count).dropLast(suffix.count))
        guard let id = Int(value), id > 0, String(id) == value,
              let url = request.url,
              let canonical = try? AuthRequestBuilder.makeFormRequest(url: url,
                fields: ["id": value], token: nil, boundary: boundary) else { return false }
        return canonical.httpBody == body
    }
}

/// A view owns every read task, including retries and review-completion reloads.
/// Cancel the actual reader task before a replacement starts or the view disappears,
/// so its session-expiration side effect observes cancellation as well as its UI result.
@MainActor public final class SignedInContentDetailLoadOwner {
    private var task: Task<Void, Never>?
    private var generation: UInt64 = 0
    public init() {}
    public func cancel() {
        generation &+= 1
        task?.cancel(); task = nil
    }
    @discardableResult
    public func start(_ operation: @escaping @MainActor () async -> Void) -> Task<Void, Never> {
        cancel()
        let captured = generation
        let next = Task { @MainActor [weak self] in
            guard !Task.isCancelled else { return }
            await operation()
            if self?.generation == captured { self?.task = nil }
        }
        task = next
        return next
    }
    public func run(_ operation: @escaping @MainActor () async -> Void) async {
        guard !Task.isCancelled else { return }
        let owned = start(operation)
        // Cancel this task only: an old SwiftUI .task cancellation must not cancel
        // a newer retry owned by the same view.
        await withTaskCancellationHandler {
            await owned.value
        } onCancel: {
            owned.cancel()
        }
    }
}

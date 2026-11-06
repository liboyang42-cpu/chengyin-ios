import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Final-forward consumer of an already issued exact attachment GET. It creates no
/// routes, credentials, session or URLSession and never widens generic composition.
@MainActor public final class NativeChannelAttachmentDescriptorTransport: HTTPTransport {
    private let context: RuntimeDependencyContext
    private let endpoint: URL
    private let routes: Set<BusinessRuntimeRoute>
    private let origins: Set<String>
    private let underlying: any HTTPTransport
    private let runtime: () -> RuntimeDependencyContext?
    private let configuration: () -> BusinessRuntimeConfiguration?
    private let presentation: () -> Bool
    private var retired = false

    public init?(messageID: Int, context: RuntimeDependencyContext,
                 issued: BusinessRuntimeConfiguration, underlying: any HTTPTransport,
                 runtime: @escaping () -> RuntimeDependencyContext?,
                 configuration: @escaping () -> BusinessRuntimeConfiguration?,
                 presentation: @escaping () -> Bool) {
        guard messageID > 0, issued.matches(context), runtime() == context, presentation(),
              let route = try? BusinessRuntimeRoute(method: "GET", path: "api/im/message/\(messageID)/attachment"),
              let issuedRoutes = issued.routes[.imChannelAttachmentPreview], issuedRoutes.contains(route),
              let live = configuration(), live.matches(context),
              live.routes[.imChannelAttachmentPreview] == issuedRoutes,
              live.imMediaOrigins == issued.imMediaOrigins else { return nil }
        self.context = context;endpoint = context.baseURL.appendingPathComponent(route.path)
        routes = issuedRoutes;origins = issued.imMediaOrigins;self.underlying = underlying
        self.runtime = runtime;self.configuration = configuration;self.presentation = presentation
    }
    /// Observing withdrawal retires this exact descriptor capability permanently.
    /// Retained previews must consult this same latch before any shorter-lived gate.
    public var isCurrent: Bool {
        guard !retired, runtime() == context, presentation(),
              let live = configuration(), live.matches(context),
              live.routes[.imChannelAttachmentPreview] == routes, live.imMediaOrigins == origins else {
            retired = true;return false
        }
        return true
    }
    public func send(_ request: URLRequest) async throws -> (Data, Int) {
        try Task.checkCancellation()
        guard isCurrent, request.httpMethod == "GET",
              request.url?.absoluteString.utf8.elementsEqual(endpoint.absoluteString.utf8) == true,
              request.httpBody == nil, request.httpBodyStream == nil, !request.httpShouldHandleCookies,
              request.value(forHTTPHeaderField: "Authorization").map({ Data($0.utf8) }) == Data(context.session.token.utf8),
              request.value(forHTTPHeaderField: "Accept") == "application/json",
              Set((request.allHTTPHeaderFields ?? [:]).keys.map { $0.lowercased() }).isSubset(of: ["accept", "authorization"]) else {
            throw APIError.notConfigured
        }
        do {
            let result = try await underlying.send(request)
            try Task.checkCancellation()
            guard isCurrent else { throw CancellationError() }
            guard result.0.count <= 16_384 else { throw APIError.malformedResponse }
            return result // Flow alone handles a current API 401; stale responses cannot expire a replacement.
        } catch {
            guard !Task.isCancelled, isCurrent else { throw CancellationError() }
            throw error
        }
    }
}

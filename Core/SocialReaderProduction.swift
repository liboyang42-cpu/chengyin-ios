import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Composition-only approvals, never inferred from login, an API hostname, or a URL
/// received in a message. Each read family and the external media origins are separate.
public struct SocialReaderProductionApproval {
    public let market: RegionalMarket
    public let endpoints: OperationEndpointApproval
    public let objectCards: Bool
    public let messageImages: Bool
    public let imageOrigins: Set<String>
    public init(market: RegionalMarket, endpoints: OperationEndpointApproval,
                objectCards: Bool = false, messageImages: Bool = false, imageOrigins: Set<String> = []) {
        self.market = market; self.endpoints = endpoints
        self.objectCards = objectCards; self.messageImages = messageImages; self.imageOrigins = imageOrigins
    }
    public func matches(_ context: RuntimeDependencyContext) -> Bool {
        market == .china && context.market == market && endpoints.baseURL == context.baseURL &&
            endpoints.namespace == context.session.namespace && endpoints.accountID == context.session.accountID
    }
}

/// Constructed per operation by the normal readers. An old pushed view cannot retain
/// a grant across account, token, role, market, namespace, or epoch changes.
@MainActor public struct SocialReaderProductionFactory {
    private let configuration: APIConfiguration?
    private let approval: SocialReaderProductionApproval?
    private let current: () -> RuntimeDependencyContext?
    private let apiTransport: any HTTPTransport
    private let mediaTransport: any HTTPTransport
    public init(configuration: APIConfiguration?, approval: SocialReaderProductionApproval? = nil,
                apiTransport: (any HTTPTransport)? = nil, mediaTransport: (any HTTPTransport)? = nil,
                current: @escaping () -> RuntimeDependencyContext?) {
        self.configuration = configuration; self.approval = approval; self.current = current
        self.apiTransport = apiTransport ?? ResponseLimitedHTTPTransport(enabled: true)
        self.mediaTransport = mediaTransport ?? ResponseLimitedHTTPTransport(enabled: true,
            maximumResponseBytes: SocialMessageMediaService.maximumBytes)
    }
    private func accepted(path: String) -> (APIConfiguration, SocialReaderProductionApproval, RuntimeDependencyContext)? {
        guard let configuration, let approval, let captured = current(), approval.matches(captured),
              configuration.baseURL == captured.baseURL, approval.endpoints.paths.contains(path) else { return nil }
        return (configuration, approval, captured)
    }
    public func objectCards() -> ObjectCardService? {
        guard let (configuration, approval, captured) = accepted(path: "api/object-card/list"), approval.objectCards else { return nil }
        return ObjectCardService(configuration: configuration, transport: SocialReaderApprovedAPITransport(
            path: "api/object-card/list", captured: captured, transport: apiTransport, current: current))
    }
    public func messageMedia() -> SocialMessageMediaService? {
        guard let (configuration, approval, captured) = accepted(path: "api/im/messages"), approval.messageImages,
              !approval.imageOrigins.isEmpty,
              approval.imageOrigins.allSatisfy({ ObjectCardMediaPolicy.origin($0) == $0 }) else { return nil }
        let api = SocialReaderApprovedAPITransport(path: "api/im/messages", captured: captured,
            transport: apiTransport, current: current)
        let readback = SocialMessageMediaReadback(service: .init(configuration: configuration, transport: api),
            captured: captured, current: current)
        let media = SocialReaderApprovedMediaTransport(origins: approval.imageOrigins, captured: captured,
            transport: mediaTransport, current: current)
        return SocialMessageMediaService(approvedOrigins: approval.imageOrigins, transport: media,
            authorize: { try await readback.validate($0) })
    }
}

/// Only the two audited read paths are expressible. POST is the source read contract;
/// approval for this transport does not authorize rename, send, upload, or read receipts.
@MainActor final class SocialReaderApprovedAPITransport: HTTPTransport {
    private let path: String
    private let captured: RuntimeDependencyContext
    private let transport: any HTTPTransport
    private let current: () -> RuntimeDependencyContext?
    init(path: String, captured: RuntimeDependencyContext, transport: any HTTPTransport,
         current: @escaping () -> RuntimeDependencyContext?) {
        self.path = path; self.captured = captured; self.transport = transport; self.current = current
    }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        try Task.checkCancellation()
        guard current() == captured else { throw CancellationError() }
        guard ["api/object-card/list", "api/im/messages"].contains(path),
              request.url == captured.baseURL.appendingPathComponent(path), request.httpMethod == "POST",
              request.httpBodyStream == nil,
              request.value(forHTTPHeaderField: "Authorization") == captured.session.token else { throw APIError.invalidRequest }
        var request = request
        request.httpShouldHandleCookies = false; request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue(nil, forHTTPHeaderField: "Cookie"); request.setValue(nil, forHTTPHeaderField: "Cookie2")
        do {
            let result = try await transport.send(request)
            try Task.checkCancellation()
            guard current() == captured else { throw CancellationError() }
            return result
        } catch {
            guard !Task.isCancelled, current() == captured else { throw CancellationError() }
            throw error
        }
    }
}

/// A message URL is not authorization evidence. Refresh server-enforced membership,
/// group/hangout access and the exact surviving image row before and after media fetch.
/// Source exposes no message-info endpoint. Follow only returned cursors; do not derive
/// one from the message ID. Very deep history fails closed after a bounded readback.
@MainActor final class SocialMessageMediaReadback {
    static let maximumPages = 20
    private let service: MessagingService
    private let captured: RuntimeDependencyContext
    private let current: () -> RuntimeDependencyContext?
    init(service: MessagingService, captured: RuntimeDependencyContext, current: @escaping () -> RuntimeDependencyContext?) {
        self.service = service; self.captured = captured; self.current = current
    }
    func validate(_ media: SocialMessageMedia) async throws {
        var cursor = 0
        var seen: Set<Int> = [0]
        for _ in 0..<Self.maximumPages {
            try Task.checkCancellation()
            guard current() == captured else { throw CancellationError() }
            let page = try await service.messages(conversationID: media.conversationID, cursor: cursor,
                size: 50, token: captured.session.token)
            try Task.checkCancellation()
            guard current() == captured else { throw CancellationError() }
            guard page.messages.count <= 50, Set(page.messages.map(\.id)).count == page.messages.count else { throw APIError.malformedResponse }
            if let row = page.messages.first(where: { $0.id == media.messageID }) {
                guard (try? SocialMessageMedia(message: row)) == media else { throw SocialMediaFailure.unavailable }
                return
            }
            guard page.hasMore, !page.messages.isEmpty, let next = page.nextCursor, next > 0,
                  seen.insert(next).inserted else { throw SocialMediaFailure.unavailable }
            cursor = next
        }
        throw SocialMediaFailure.unavailable
    }
}

@MainActor final class SocialReaderApprovedMediaTransport: HTTPTransport {
    private let origins: Set<String>
    private let captured: RuntimeDependencyContext
    private let transport: any HTTPTransport
    private let current: () -> RuntimeDependencyContext?
    init(origins: Set<String>, captured: RuntimeDependencyContext, transport: any HTTPTransport,
         current: @escaping () -> RuntimeDependencyContext?) {
        self.origins = origins; self.captured = captured; self.transport = transport; self.current = current
    }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        try Task.checkCancellation()
        guard current() == captured else { throw CancellationError() }
        guard let url = request.url, let origin = ObjectCardMediaPolicy.origin(url.absoluteString), origins.contains(origin),
              request.httpMethod == "GET", request.httpBody == nil, request.httpBodyStream == nil,
              request.value(forHTTPHeaderField: "Authorization") == nil,
              request.value(forHTTPHeaderField: "Proxy-Authorization") == nil,
              request.value(forHTTPHeaderField: "Cookie") == nil, request.value(forHTTPHeaderField: "Cookie2") == nil,
              !request.httpShouldHandleCookies else { throw APIError.invalidRequest }
        do {
            let result = try await transport.send(request)
            try Task.checkCancellation()
            guard current() == captured else { throw CancellationError() }
            return result
        } catch {
            guard !Task.isCancelled, current() == captured else { throw CancellationError() }
            throw error
        }
    }
}

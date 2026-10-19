import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// I11 / BK-EXISTING: POST api/roam/stamp/received is the current account's paginated read of
/// stamps already obtained through an exchange. It returns the album's anonymous RoamStampListVO
/// page shape. This grant is independent of the album grant and never authorizes the exchange write.
@MainActor @Observable public final class RoamReceivedStampReadAccess {
    public let context: RuntimeDependencyContext
    public let endpoints: OperationEndpointApproval
    public let revision = UUID()
    public private(set) var isRevoked = false
    public init(context: RuntimeDependencyContext, approval: OperationEndpointApproval) throws {
        guard context.market == .china, ["player", "club", "merchant"].contains(context.role),
              context.session.accountID > 0, AuthRequestBuilder.isValidToken(context.session.token),
              approval.baseURL.absoluteString.utf8.elementsEqual(context.baseURL.absoluteString.utf8),
              approval.namespace.utf8.elementsEqual(context.session.namespace.utf8),
              approval.accountID == context.session.accountID,
              approval.paths == [RoamReceivedStampReadRoute.path] else { throw APIError.invalidConfiguration }
        self.context = context; endpoints = approval
    }
    public func revoke() { isRevoked = true }
    public func matches(_ current: RuntimeDependencyContext) -> Bool {
        !isRevoked && ContentDraftContextFence.matches(context, current)
    }
}

/// Same canonical multipart pagination as the album route, bound to the received path only.
public struct RoamReceivedStampReadRoute: Equatable {
    public static let path = "api/roam/stamp/received"
    private let shape: RoamAlbumMetadataReadRoute
    public var page: Int { shape.page }
    public var pageSize: Int { shape.pageSize }
    public static func valid(page: Int, pageSize: Int) -> Bool { RoamAlbumMetadataReadRoute.valid(page: page, pageSize: pageSize) }
    public init?(request: URLRequest, baseURL: URL) {
        guard let url = request.url,
              url.absoluteString.utf8.elementsEqual(baseURL.appendingPathComponent(Self.path).absoluteString.utf8) else { return nil }
        var canonical = request; canonical.url = baseURL.appendingPathComponent(RoamAlbumMetadataReadRoute.path)
        guard let shape = RoamAlbumMetadataReadRoute(request: canonical, baseURL: baseURL) else { return nil }
        self.shape = shape
    }
    public func validateResponse(_ response: (Data, Int)) throws { try shape.validateResponse(response) }
}

public struct RoamReceivedStampService {
    public let deployment: URL
    private let transport: any HTTPTransport
    public init(configuration: APIConfiguration, transport: any HTTPTransport) {
        deployment = configuration.baseURL; self.transport = transport
    }
    public func page(page: Int = 1, pageSize: Int = 20, token: String) async throws -> RoamAlbumPage {
        guard RoamReceivedStampReadRoute.valid(page: page, pageSize: pageSize), AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        let request = try AuthRequestBuilder.makeFormRequest(url: deployment.appendingPathComponent(RoamReceivedStampReadRoute.path),
            fields: ["pageNum": String(page), "pageSize": String(pageSize)], token: token)
        try Task.checkCancellation()
        let (data, status) = try await transport.send(request)
        try Task.checkCancellation()
        struct Status: Decodable { let code: Int }
        struct Envelope: Decodable { let data: RoamAlbumPage }
        if status == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(status) else { throw APIError.httpStatus(status) }
        guard let header = try? JSONDecoder().decode(Status.self, from: data) else { throw APIError.malformedResponse }
        if header.code == 401 { throw APIError.unauthorized }
        guard header.code == 200 else { throw APIError.businessCode(header.code) }
        guard let value = try? JSONDecoder().decode(Envelope.self, from: data).data,
              value.pageNum == page, value.pageSize == pageSize,
              Set(value.list.map(\.id)).count == value.list.count else { throw APIError.malformedResponse }
        return value
    }
}

/// Pages received stamps through the existing RoamAlbumPager. Every other roam read stays closed.
@MainActor public final class RoamReceivedStampReader: RoamExperienceReading {
    private let service: RoamReceivedStampService?
    private let current: () -> RuntimeDependencyContext?
    private let viewerRevision: () -> UInt64
    private let selectAccess: (RuntimeDependencyContext) -> RoamReceivedStampReadAccess?
    private let onUnauthorized: (RuntimeDependencyContext) -> Void
    public init(service: RoamReceivedStampService?, current: @escaping () -> RuntimeDependencyContext?,
                viewerRevision: @escaping () -> UInt64,
                access: @escaping (RuntimeDependencyContext) -> RoamReceivedStampReadAccess?,
                onUnauthorized: @escaping (RuntimeDependencyContext) -> Void = { _ in }) {
        self.service = service; self.current = current; self.viewerRevision = viewerRevision
        selectAccess = access; self.onUnauthorized = onUnauthorized
    }
    public var identity: RoamExperienceIdentity? {
        guard let context = current(), let scope = try? RoamHistoryScope(market: context.market.rawValue,
            deployment: context.baseURL, accountID: context.session.accountID, namespace: context.session.namespace) else { return nil }
        return .init(scope: scope, epoch: context.session.epoch)
    }
    public var isConfigured: Bool { current().flatMap { select($0) } != nil }
    public var isOfflineExample: Bool { false }
    private func select(_ context: RuntimeDependencyContext) -> RoamReceivedStampReadAccess? {
        guard let service, service.deployment.absoluteString.utf8.elementsEqual(context.baseURL.absoluteString.utf8),
              let access = selectAccess(context), access.matches(context) else { return nil }
        return access
    }
    public func album(page: Int, pageSize: Int) async throws -> RoamAlbumPage {
        guard RoamReceivedStampReadRoute.valid(page: page, pageSize: pageSize) else { throw APIError.invalidRequest }
        try Task.checkCancellation()
        guard let context = current() else { throw APIError.unauthorized }
        guard let selected = select(context), let service else { throw APIError.notConfigured }
        let capturedViewer = viewerRevision()
        func valid() -> Bool {
            guard !Task.isCancelled, let fresh = current(), ContentDraftContextFence.matches(context, fresh),
                  viewerRevision() == capturedViewer else { return false }
            return select(fresh) === selected
        }
        do {
            let result = try await service.page(page: page, pageSize: pageSize, token: context.session.token)
            guard valid() else { throw CancellationError() }
            return result
        } catch {
            guard valid() else { throw CancellationError() }
            if error as? APIError == .unauthorized { onUnauthorized(context) }
            throw error
        }
    }
    public func history() throws -> [RoamHistoryRecord] { throw APIError.notConfigured }
    public func sessionFact(_ query: RoamRecoveryQuery) async throws -> RoamSessionFact { throw APIError.notConfigured }
    public func tilePage(afterID: Int, limit: Int) async throws -> RoamTileMemoryPage { throw APIError.notConfigured }
    public func shopBadge() async throws -> RoamShopBadge? { throw APIError.notConfigured }
}

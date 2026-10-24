import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Independently approved owner-only exploration-memory reads. No location or reveal authority.
@MainActor @Observable public final class RoamTileMemoryReadAccess {
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
              approval.paths == [RoamTileMemoryReadRoute.path] else { throw APIError.invalidConfiguration }
        self.context = context; endpoints = approval
    }
    public func revoke() { isRevoked = true }
    public func matches(_ current: RuntimeDependencyContext) -> Bool {
        !isRevoked && ContentDraftContextFence.matches(context, current)
    }
}

public struct RoamTileMemoryReadRoute: Equatable {
    public static let path = "api/roam/tiles/page"
    public let afterID: Int
    public let limit: Int
    public init?(request: URLRequest, baseURL: URL) {
        guard let url = request.url, request.httpMethod == "GET", request.httpBody == nil,
              request.httpBodyStream == nil, request.value(forHTTPHeaderField: "Accept") == "application/json",
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false), parts.fragment == nil,
              let items = parts.queryItems, items.count == 2,
              items[0].name == "afterId", items[1].name == "limit",
              let cursorText = items[0].value, let cursor = Int(cursorText), cursor >= 0, String(cursor) == cursorText,
              let limitText = items[1].value, let size = Int(limitText), (1...2000).contains(size), String(size) == limitText,
              var canonical = URLComponents(url: baseURL.appendingPathComponent(Self.path), resolvingAgainstBaseURL: false) else { return nil }
        canonical.queryItems = [URLQueryItem(name: "afterId", value: cursorText), URLQueryItem(name: "limit", value: limitText)]
        guard let expected = canonical.url, expected.absoluteString.utf8.elementsEqual(url.absoluteString.utf8) else { return nil }
        afterID = cursor; limit = size
    }
    public func validateResponse(_ response: (Data, Int)) throws {
        guard (200..<300).contains(response.1) else { return }
        struct Status: Decodable { let code: Int }
        struct Page: Decodable { let tiles: [String]; let nextAfterId: Int; let hasMore: Bool }
        struct Envelope: Decodable { let data: Page }
        do {
            guard try JSONDecoder().decode(Status.self, from: response.0).code == 200 else { return }
            let page = try JSONDecoder().decode(Envelope.self, from: response.0).data
            guard page.tiles.count <= limit, page.tiles.allSatisfy(RoamExperienceMath.isValidTile),
                  page.nextAfterId >= afterID, !page.hasMore || page.nextAfterId > afterID else { throw APIError.malformedResponse }
        } catch { throw APIError.malformedResponse }
    }
}

/// Uses the original read service without exposing session recovery, stamps or writes.
@MainActor public final class RoamTileMemoryReader: RoamExperienceReading {
    private let service: RoamExperienceService?
    private let current: () -> RuntimeDependencyContext?
    private let viewerRevision: () -> UInt64
    private let selectAccess: (RuntimeDependencyContext) -> RoamTileMemoryReadAccess?
    private let onUnauthorized: (RuntimeDependencyContext) -> Void
    private var observedContext: RuntimeDependencyContext?
    private var observedViewer: UInt64?
    private var observedAccess: UUID?
    private var stamp = UUID()
    public init(service: RoamExperienceService?, current: @escaping () -> RuntimeDependencyContext?,
                viewerRevision: @escaping () -> UInt64,
                access: @escaping (RuntimeDependencyContext) -> RoamTileMemoryReadAccess?,
                onUnauthorized: @escaping (RuntimeDependencyContext) -> Void = { _ in }) {
        self.service = service; self.current = current; self.viewerRevision = viewerRevision
        selectAccess = access; self.onUnauthorized = onUnauthorized
    }
    public var identity: RoamExperienceIdentity? {
        guard let context = current(), let scope = try? RoamHistoryScope(market: context.market.rawValue,
            deployment: context.baseURL, accountID: context.session.accountID, namespace: context.session.namespace) else { return nil }
        return .init(scope: scope, epoch: context.session.epoch)
    }
    public var isConfigured: Bool { synchronize() != nil && service != nil }
    public var isOfflineExample: Bool { false }
    public var scope: UUID { _ = synchronize(); return stamp }
    private func synchronize() -> RoamTileMemoryReadAccess? {
        let context = current(), viewer = viewerRevision()
        let selected = context.flatMap { value in selectAccess(value).flatMap { $0.matches(value) ? $0 : nil } }
        let same: Bool
        if let context, let old = observedContext { same = ContentDraftContextFence.matches(old, context) }
        else { same = context == nil && observedContext == nil }
        if !same || viewer != observedViewer || selected?.revision != observedAccess {
            observedContext = context; observedViewer = viewer; observedAccess = selected?.revision; stamp = UUID()
        }
        return selected
    }
    public func tilePage(afterID: Int, limit: Int) async throws -> RoamTileMemoryPage {
        try Task.checkCancellation()
        guard let context = current() else { throw APIError.unauthorized }
        guard let selected = synchronize(), let service else { throw APIError.notConfigured }
        let capturedScope = stamp, capturedViewer = viewerRevision()
        func valid() -> Bool {
            guard !Task.isCancelled, let fresh = current(), ContentDraftContextFence.matches(context, fresh),
                  viewerRevision() == capturedViewer else { return false }
            return synchronize() === selected && stamp == capturedScope
        }
        guard valid() else { throw CancellationError() }
        do {
            let result = try await service.tilePage(afterID: afterID, limit: limit, token: context.session.token)
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
    public func album(page: Int, pageSize: Int) async throws -> RoamAlbumPage { throw APIError.notConfigured }
    public func shopBadge() async throws -> RoamShopBadge? { throw APIError.notConfigured }
}

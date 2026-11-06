import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// This approval grants only the current account's stamp metadata, never image retrieval or capture.
@MainActor @Observable public final class RoamAlbumMetadataReadAccess {
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
              approval.paths == [RoamAlbumMetadataReadRoute.path] else { throw APIError.invalidConfiguration }
        self.context = context; endpoints = approval
    }
    public func revoke() { isRevoked = true }
    public func matches(_ current: RuntimeDependencyContext) -> Bool {
        !isRevoked && ContentDraftContextFence.matches(context, current)
    }
}

public struct RoamAlbumMetadataReadRoute: Equatable {
    public static let path = "api/roam/stamp/list"
    public let page: Int
    public let pageSize: Int
    public static func valid(page: Int, pageSize: Int) -> Bool {
        page > 0 && (1...50).contains(pageSize) && page - 1 <= 1_000_000 / pageSize
    }
    public init?(request: URLRequest, baseURL: URL) {
        guard let url = request.url, url.query == nil, url.fragment == nil,
              url.absoluteString.utf8.elementsEqual(baseURL.appendingPathComponent(Self.path).absoluteString.utf8),
              request.httpMethod == "POST", request.httpBodyStream == nil,
              request.value(forHTTPHeaderField: "Accept") == "application/json",
              let type = request.value(forHTTPHeaderField: "Content-Type"), type.hasPrefix("multipart/form-data; boundary="),
              let body = request.httpBody, body.count <= 2048, let text = String(data: body, encoding: .utf8) else { return nil }
        let boundary = String(type.dropFirst("multipart/form-data; boundary=".count))
        guard !boundary.isEmpty, boundary.count <= 70,
              boundary.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else { return nil }
        func number(_ key: String) -> Int? {
            let parts = text.components(separatedBy: "name=\"\(key)\"\r\n\r\n")
            guard parts.count == 2, let value = parts[1].components(separatedBy: "\r\n").first,
                  let number = Int(value), String(number) == value else { return nil }
            return number
        }
        guard let page = number("pageNum"), let pageSize = number("pageSize"), Self.valid(page: page, pageSize: pageSize),
              let expected = try? AuthRequestBuilder.makeFormRequest(url: url,
                fields: ["pageNum": String(page), "pageSize": String(pageSize)], token: nil, boundary: boundary),
              expected.httpBody == body else { return nil }
        self.page = page; self.pageSize = pageSize
    }
    public func validateResponse(_ response: (Data, Int)) throws {
        guard (200..<300).contains(response.1) else { return }
        struct Status: Decodable { let code: Int }
        struct Page: Decodable { let list: [RoamAlbumStamp]; let total: Int; let pageNum: Int; let pageSize: Int }
        struct Envelope: Decodable { let data: Page }
        do {
            guard try JSONDecoder().decode(Status.self, from: response.0).code == 200 else { return }
            let value = try JSONDecoder().decode(Envelope.self, from: response.0).data
            guard value.pageNum == page, value.pageSize == pageSize, value.total >= 0,
                  value.list.count <= pageSize, value.list.count <= value.total,
                  value.list.allSatisfy({ $0.id > 0 }), Set(value.list.map(\.id)).count == value.list.count else { throw APIError.malformedResponse }
        } catch { throw APIError.malformedResponse }
    }
}

@MainActor public final class RoamAlbumMetadataReader: RoamExperienceReading {
    private let service: RoamExperienceService?
    private let current: () -> RuntimeDependencyContext?
    private let viewerRevision: () -> UInt64
    private let selectAccess: (RuntimeDependencyContext) -> RoamAlbumMetadataReadAccess?
    private let onUnauthorized: (RuntimeDependencyContext) -> Void
    private var observedContext: RuntimeDependencyContext?
    private var observedViewer: UInt64?
    private var observedAccess: UUID?
    private var stamp = UUID()
    public init(service: RoamExperienceService?, current: @escaping () -> RuntimeDependencyContext?,
                viewerRevision: @escaping () -> UInt64,
                access: @escaping (RuntimeDependencyContext) -> RoamAlbumMetadataReadAccess?,
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
    private func synchronize() -> RoamAlbumMetadataReadAccess? {
        let context = current(), viewer = viewerRevision()
        let selected = context.flatMap { value in
            guard service?.deployment.absoluteString.utf8.elementsEqual(value.baseURL.absoluteString.utf8) == true else { return nil as RoamAlbumMetadataReadAccess? }
            return selectAccess(value).flatMap { $0.matches(value) ? $0 : nil }
        }
        let same: Bool
        if let context, let old = observedContext { same = ContentDraftContextFence.matches(old, context) }
        else { same = context == nil && observedContext == nil }
        if !same || viewer != observedViewer || selected?.revision != observedAccess {
            observedContext = context; observedViewer = viewer; observedAccess = selected?.revision; stamp = UUID()
        }
        return selected
    }
    public func album(page: Int, pageSize: Int) async throws -> RoamAlbumPage {
        guard RoamAlbumMetadataReadRoute.valid(page: page, pageSize: pageSize) else { throw APIError.invalidRequest }
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
            let result = try await service.album(page: page, pageSize: pageSize, token: context.session.token)
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

import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum OwnMediaApprovedLinkFailure: Error, Equatable { case unavailable, stale, invalidResponse, unauthorized }
/// Independent per-asset authority to read an APPROVED link and explicitly copy it locally.
/// Lease expiry limits new delivery, not the lifetime of an already copied server URL.
@MainActor @Observable public final class OwnMediaApprovedLinkApproval {
    public let revision = UUID(), context: RuntimeDependencyContext, viewerRevision: UInt64, assetID: Int64
    public let approvedOrigins: Set<String>, expiresAt: Date
    public let clientDeadline: ContinuousClock.Instant
    public private(set) var revoked = false
    public init(context: RuntimeDependencyContext, viewerRevision: UInt64, assetID: Int64,
                approvedOrigins: Set<String>, expiresAt: Date) throws {
        _ = try APIConfiguration(baseURL: context.baseURL)
        let duration = expiresAt.timeIntervalSinceNow
        guard context.market == .china, assetID > 0, context.role.utf8.elementsEqual(context.session.role.utf8),
              expiresAt.timeIntervalSince1970.isFinite, duration.isFinite, duration > 0,
              !approvedOrigins.isEmpty, approvedOrigins.allSatisfy(Self.validOrigin) else { throw OwnMediaApprovedLinkFailure.unavailable }
        self.context = context; self.viewerRevision = viewerRevision; self.assetID = assetID
        self.approvedOrigins = approvedOrigins; self.expiresAt = expiresAt
        let seconds = min(duration, TimeInterval(Int64.max / 1_000_000_000))
        clientDeadline = ContinuousClock().now.advanced(by: .nanoseconds(Int64(seconds * 1_000_000_000)))
    }
    public func revoke() { revoked = true }
    public func matches(_ value: RuntimeDependencyContext) -> Bool {
        !revoked && Date() < expiresAt && ContinuousClock().now < clientDeadline
            && ContentDraftContextFence.matches(value, context)
            && value.session.role.utf8.elementsEqual(context.session.role.utf8)
    }
    static func validOrigin(_ text: String) -> Bool {
        guard let c = URLComponents(string: text), c.scheme == "https", let host = c.host, !host.isEmpty,
              c.user == nil, c.password == nil, c.query == nil, c.fragment == nil, c.path.isEmpty,
              c.port.map({ (1...65535).contains($0) }) ?? true else { return false }
        let canonical = "https://" + host.lowercased() + (c.port.map { ":\($0)" } ?? "")
        return text.utf8.elementsEqual(canonical.utf8)
    }
}
public enum OwnMediaApprovedLinkRoute {
    public static func request(baseURL: URL, assetID: Int64, token: String) throws -> URLRequest {
        guard assetID > 0, AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        var request = URLRequest(url: baseURL.appendingPathComponent("api/media/asset/\(assetID)"))
        request.httpMethod = "GET"; request.httpShouldHandleCookies = false; request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(token, forHTTPHeaderField: "Authorization"); return request
    }
    static func decode(_ bytes: Data, status: Int, asset: OwnMediaAsset, origins: Set<String>) throws -> String {
        if status == 401 || status == 403 { throw OwnMediaApprovedLinkFailure.unauthorized }
        guard bytes.count <= 65_536, let text = String(data: bytes, encoding: .utf8) else { throw OwnMediaApprovedLinkFailure.invalidResponse }
        _ = try ContentDraftJSON.parse(text)
        struct Code: Decodable { let code: Int }
        let code = try JSONDecoder().decode(Code.self, from: bytes).code
        if code == 401 || code == 403 || code == 2 { throw OwnMediaApprovedLinkFailure.unauthorized }
        struct Row: Decodable {
            let assetId: Int64, reviewState: String, mediaType: String, url: String
            enum CodingKeys: String, CodingKey { case assetId, reviewState, mediaType, url }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                if let text = try? c.decode(String.self, forKey: .assetId) {
                    guard let id = OwnMediaPage.identifier(text) else { throw OwnMediaApprovedLinkFailure.invalidResponse }; assetId = id
                } else { assetId = try c.decode(Int64.self, forKey: .assetId) }
                reviewState = try c.decode(String.self, forKey: .reviewState)
                mediaType = try c.decode(String.self, forKey: .mediaType); url = try c.decode(String.self, forKey: .url)
            }
        }
        struct Payload: Decodable { let data: Row }
        guard status == 200, code == 200, asset.reviewState == .approved else { throw OwnMediaApprovedLinkFailure.invalidResponse }
        let row = try JSONDecoder().decode(Payload.self, from: bytes).data
        let expectedType: String
        switch asset.mediaType { case .image: expectedType = "IMAGE"; case .audio: expectedType = "AUDIO"; case .model3D: expectedType = "MODEL3D"; case .other: throw OwnMediaApprovedLinkFailure.invalidResponse }
        guard row.assetId > 0, row.assetId == asset.id, row.reviewState == "APPROVED", row.mediaType == expectedType,
              row.url.utf8.count <= 8192, let url = URL(string: row.url), row.url.utf8.elementsEqual(url.absoluteString.utf8),
              RetainedImageOrigin.accepts(url, origins: origins) else { throw OwnMediaApprovedLinkFailure.invalidResponse }
        // No declared TTL/version in the original response. Preserve every signature byte.
        return row.url
    }
}
@MainActor public protocol OwnMediaApprovedLinkDispatching: AnyObject {
    func send(_ request: URLRequest, authorization: OwnMediaApprovedLinkAuthorization) async throws -> (Data, Int)
}
@MainActor public final class OwnMediaApprovedLinkAuthorization {
    private let expected: URLRequest, current: () -> Bool
    private var cancelled = false
    private var cancellation: (() -> Void)?
    public private(set) var didForward = false
    init(request: URLRequest, current: @escaping () -> Bool) { expected = request; self.current = current }
    public var isCurrent: Bool { !cancelled && !Task.isCancelled && current() }
    public func accepts(_ request: URLRequest) -> Bool {
        request.url?.absoluteString.utf8.elementsEqual(expected.url!.absoluteString.utf8) == true
            && request.httpMethod == "GET" && request.httpBody == nil && request.httpBodyStream == nil
            && request.allHTTPHeaderFields == expected.allHTTPHeaderFields && !request.httpShouldHandleCookies
            && request.cachePolicy == .reloadIgnoringLocalCacheData && request.value(forHTTPHeaderField: "Cookie") == nil
            && request.value(forHTTPHeaderField: "Authorization") != nil
    }
    public func forward(_ request: URLRequest, cancel: @escaping () -> Void, dispatch: () throws -> Void) throws {
        guard !didForward, accepts(request), isCurrent else { throw OwnMediaApprovedLinkFailure.stale }
        didForward = true; cancellation = cancel; try dispatch()
    }
    public func invalidate() { cancelled = true; let cancel = cancellation; cancellation = nil; cancel?() }
}
/// Memory-only single delivery. No public URL getter, persistence or server-expiry claim.
@MainActor public final class OwnMediaApprovedLinkDelivery {
    private var text: String?
    private let current: () -> Bool
    fileprivate init(text: String, current: @escaping () -> Bool) { self.text = text; self.current = current }
    public func deliver(to sink: (String) throws -> Void) throws {
        let value = text; text = nil
        guard !Task.isCancelled, current(), let value else { throw OwnMediaApprovedLinkFailure.stale }
        try sink(value) // Same synchronous actor turn as the final identity/APPROVED check.
    }
}
@MainActor @Observable public final class OwnMediaApprovedLinkReader {
    private let approval: OwnMediaApprovedLinkApproval
    private let currentContext: () -> RuntimeDependencyContext?
    private let currentViewerRevision: () -> UInt64?
    private let selected: () -> OwnMediaApprovedLinkApproval?
    private let listReader: any OwnMediaReading
    private let listScope: UUID
    private let transport: any OwnMediaApprovedLinkDispatching
    private var retired = false
    private var active: [UUID: OwnMediaApprovedLinkAuthorization] = [:]
    public init(approval: OwnMediaApprovedLinkApproval, currentContext: @escaping () -> RuntimeDependencyContext?,
                currentViewerRevision: @escaping () -> UInt64?, selected: @escaping () -> OwnMediaApprovedLinkApproval?,
                listReader: any OwnMediaReading, transport: (any OwnMediaApprovedLinkDispatching)? = nil) {
        self.approval = approval; self.currentContext = currentContext; self.currentViewerRevision = currentViewerRevision
        self.selected = selected; self.listReader = listReader; listScope = listReader.scope
        self.transport = transport ?? OwnMediaApprovedLinkTransport()
    }
    public var assetID: Int64 { approval.assetID }
    public var sourceRevision: UUID? { isConfigured ? approval.revision : nil }
    public var isConfigured: Bool {
        guard !retired else { return false }
        guard selected() === approval, let context = currentContext(), approval.matches(context),
              currentViewerRevision() == approval.viewerRevision, listReader.scope == listScope,
              listReader.isSignedIn, listReader.isAvailable else { retire(); return false }; return true
    }
    public func retire() { retired = true; let pending = Array(active.values); active.removeAll(); pending.forEach { $0.invalidate() } }
    public static func sameAsset(_ a: OwnMediaAsset, _ b: OwnMediaAsset) -> Bool {
        a.id == b.id && a.mediaType == b.mediaType && a.reviewState == b.reviewState && a.reviewReason.utf8.elementsEqual(b.reviewReason.utf8)
    }
    public static func canCopy(_ asset: OwnMediaAsset) -> Bool { asset.id > 0 && asset.reviewState == .approved && asset.mediaType != .other }
    public func readForCopy(asset: OwnMediaAsset, currentAsset: @escaping () -> OwnMediaAsset?,
                            actionIsCurrent: @escaping () -> Bool) async throws -> OwnMediaApprovedLinkDelivery {
        let current: () -> Bool = { [weak self] in
            guard let self, self.isConfigured, asset.id == self.approval.assetID, Self.canCopy(asset),
                  actionIsCurrent(), let row = currentAsset(), Self.sameAsset(asset, row) else { return false }; return true
        }
        guard current() else { throw OwnMediaApprovedLinkFailure.unavailable }
        let request = try OwnMediaApprovedLinkRoute.request(baseURL: approval.context.baseURL, assetID: asset.id, token: approval.context.session.token)
        let auth = OwnMediaApprovedLinkAuthorization(request: request, current: current), id = UUID(); active[id] = auth
        defer { active.removeValue(forKey: id); auth.invalidate() }
        do {
            try Task.checkCancellation()
            let (data, status) = try await transport.send(request, authorization: auth)
            guard auth.didForward, auth.isCurrent else { throw OwnMediaApprovedLinkFailure.stale }
            let text = try OwnMediaApprovedLinkRoute.decode(data, status: status, asset: asset, origins: approval.approvedOrigins)
            guard current() else { throw OwnMediaApprovedLinkFailure.stale }
            return .init(text: text, current: current)
        } catch {
            guard current() else { throw OwnMediaApprovedLinkFailure.stale }
            if error as? OwnMediaApprovedLinkFailure == .unauthorized { approval.revoke(); retire() }
            throw error
        }
    }
}

import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum OwnMediaModelPreviewFailure: Error, Equatable { case unavailable, stale, invalidResponse, unauthorized }
/// Independent per-asset owner MODEL3D lease. Existing list/status/profile grants are insufficient.
@MainActor @Observable public final class OwnMediaModelPreviewApproval {
    public let revision = UUID(), context: RuntimeDependencyContext, viewerRevision: UInt64, assetID: Int64
    public let approvedOrigins: Set<String>, expiresAt: Date
    /// Local monotonic cap only, not a server-issued media timestamp.
    public let clientDeadline: ContinuousClock.Instant
    public private(set) var revoked = false
    public init(context: RuntimeDependencyContext, viewerRevision: UInt64, assetID: Int64,
                approvedOrigins: Set<String>, expiresAt: Date) throws {
        _ = try APIConfiguration(baseURL: context.baseURL)
        let now = Date(), duration = expiresAt.timeIntervalSince(now)
        guard context.market == .china, assetID > 0, context.role.utf8.elementsEqual(context.session.role.utf8),
              expiresAt.timeIntervalSince1970.isFinite, duration.isFinite, duration > 0,
              !approvedOrigins.isEmpty, approvedOrigins.allSatisfy(Self.validOrigin) else { throw OwnMediaModelPreviewFailure.unavailable }
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

public enum OwnMediaModelPreviewRoute {
    public static func request(baseURL: URL, assetID: Int64, token: String) throws -> URLRequest {
        guard assetID > 0, AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        var request = URLRequest(url: baseURL.appendingPathComponent("api/media/asset/\(assetID)/preview"))
        request.httpMethod = "GET"; request.httpShouldHandleCookies = false; request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(token, forHTTPHeaderField: "Authorization")
        return request
    }
    static func decode(_ bytes: Data, status: Int, origins: Set<String>) throws -> URL {
        if status == 401 || status == 403 { throw OwnMediaModelPreviewFailure.unauthorized }
        guard bytes.count <= 65_536, let text = String(data: bytes, encoding: .utf8) else { throw OwnMediaModelPreviewFailure.invalidResponse }
        _ = try ContentDraftJSON.parse(text)
        struct Code: Decodable { let code: Int }
        let code = try JSONDecoder().decode(Code.self, from: bytes).code
        if code == 401 || code == 403 || code == 2 { throw OwnMediaModelPreviewFailure.unauthorized }
        struct Payload: Decodable { struct Value: Decodable { let authorPreviewUrl: String }; let data: Value }
        guard status == 200, code == 200 else { throw OwnMediaModelPreviewFailure.invalidResponse }
        let raw = try JSONDecoder().decode(Payload.self, from: bytes).data.authorPreviewUrl
        guard raw.utf8.count <= 8192, let url = URL(string: raw), raw.utf8.elementsEqual(url.absoluteString.utf8),
              RetainedImageOrigin.accepts(url, origins: origins) else { throw OwnMediaModelPreviewFailure.invalidResponse }
        return url
    }
}

@MainActor public protocol OwnMediaModelPreviewMetadataReading: AnyObject {
    func send(_ request: URLRequest, authorization: OwnMediaModelPreviewAuthorization) async throws -> (Data, Int)
}
@MainActor public protocol OwnMediaPrivateModelReading: AnyObject {
    func model(_ request: URLRequest, authorization: OwnMediaModelPreviewAuthorization) async throws -> Data
}
/// Binds either exact metadata GET or exact anonymous resource GET. Never interchangeable.
@MainActor public final class OwnMediaModelPreviewAuthorization {
    public enum Purpose: Equatable { case metadata, model }
    public let purpose: Purpose
    private let expected: URLRequest, current: () -> Bool
    private var cancelled = false
    private var cancellation: (() -> Void)?
    public private(set) var didForward = false
    init(purpose: Purpose, request: URLRequest, current: @escaping () -> Bool) {
        self.purpose = purpose; expected = request; self.current = current
    }
    public var isCurrent: Bool { !cancelled && !Task.isCancelled && current() }
    public func accepts(_ request: URLRequest) -> Bool {
        guard request.url?.absoluteString.utf8.elementsEqual(expected.url!.absoluteString.utf8) == true,
              request.httpMethod == "GET", request.httpBody == nil, request.httpBodyStream == nil,
              request.allHTTPHeaderFields == expected.allHTTPHeaderFields, !request.httpShouldHandleCookies,
              request.cachePolicy == .reloadIgnoringLocalCacheData, request.value(forHTTPHeaderField: "Cookie") == nil else { return false }
        switch purpose {
        case .metadata: return request.value(forHTTPHeaderField: "Authorization") != nil
        case .model: return request.value(forHTTPHeaderField: "Authorization") == nil
        }
    }
    public func forward(_ request: URLRequest, cancel: @escaping () -> Void, dispatch: () throws -> Void) throws {
        guard !didForward, accepts(request), isCurrent else { throw OwnMediaModelPreviewFailure.stale }
        didForward = true; cancellation = cancel; try dispatch()
    }
    public func invalidate() { cancelled = true; let cancel = cancellation; cancellation = nil; cancel?() }
}

/// Returned data is not a receipt: the producer supplied no ID/type/version/time fields.
public struct OwnMediaModelPreviewData {
    public let bytes: Data
    /// Conservative local request-start + 300-second limit, capped by client lease.
    public let displayDeadline: ContinuousClock.Instant
}

@MainActor @Observable public final class OwnMediaModelPreviewReader {
    private let approval: OwnMediaModelPreviewApproval
    private let currentContext: () -> RuntimeDependencyContext?
    private let currentViewerRevision: () -> UInt64?
    private let selected: () -> OwnMediaModelPreviewApproval?
    private let listReader: any OwnMediaReading
    private let listScope: UUID
    private let metadata: any OwnMediaModelPreviewMetadataReading
    private let modelReader: any OwnMediaPrivateModelReading
    @ObservationIgnored public var onRetired: (() -> Void)?
    private var retired = false
    private var active: [UUID: OwnMediaModelPreviewAuthorization] = [:]
    public init(approval: OwnMediaModelPreviewApproval, currentContext: @escaping () -> RuntimeDependencyContext?,
                currentViewerRevision: @escaping () -> UInt64?, selected: @escaping () -> OwnMediaModelPreviewApproval?,
                listReader: any OwnMediaReading, metadata: (any OwnMediaModelPreviewMetadataReading)? = nil,
                modelReader: (any OwnMediaPrivateModelReading)? = nil) {
        self.approval = approval; self.currentContext = currentContext; self.currentViewerRevision = currentViewerRevision
        self.selected = selected; self.listReader = listReader; listScope = listReader.scope
        self.metadata = metadata ?? OwnMediaModelPreviewMetadataTransport(); self.modelReader = modelReader ?? OwnMediaPrivateModelReader()
    }
    public var assetID: Int64 { approval.assetID }
    public var sourceRevision: UUID? { isConfigured ? approval.revision : nil }
    public var isConfigured: Bool {
        guard !retired else { return false }
        guard selected() === approval, let context = currentContext(), approval.matches(context),
              currentViewerRevision() == approval.viewerRevision, listReader.scope == listScope,
              listReader.isSignedIn, listReader.isAvailable else { retire(); return false }
        return true
    }
    public func retire() {
        guard !retired else { return }; retired = true
        let pending = Array(active.values); active.removeAll(); pending.forEach { $0.invalidate() }
        let callback = onRetired; onRetired = nil; callback?()
    }
    public static func sameAsset(_ a: OwnMediaAsset, _ b: OwnMediaAsset) -> Bool {
        a.id == b.id && a.mediaType == b.mediaType && a.reviewState == b.reviewState
            && a.reviewReason.utf8.elementsEqual(b.reviewReason.utf8)
    }
    public func load(asset: OwnMediaAsset, currentAsset: @escaping () -> OwnMediaAsset?,
                     presentationIsCurrent: @escaping () -> Bool) async throws -> OwnMediaModelPreviewData {
        let clock = ContinuousClock()
        let deadline = min(clock.now.advanced(by: .seconds(300)), approval.clientDeadline)
        let current: () -> Bool = { [weak self] in
            guard let self, self.isConfigured, asset.id == self.approval.assetID, asset.mediaType == .model3D,
                  clock.now < deadline, presentationIsCurrent(), let fresh = currentAsset(), Self.sameAsset(asset, fresh) else { return false }
            return true
        }
        guard current() else { throw OwnMediaModelPreviewFailure.unavailable }
        let request = try OwnMediaModelPreviewRoute.request(baseURL: approval.context.baseURL, assetID: asset.id, token: approval.context.session.token)
        let info = OwnMediaModelPreviewAuthorization(purpose: .metadata, request: request, current: current)
        let infoID = UUID(); active[infoID] = info
        defer { active.removeValue(forKey: infoID); info.invalidate() }
        var readingResource = false
        do {
            try Task.checkCancellation()
            let (bytes, status) = try await metadata.send(request, authorization: info)
            guard info.didForward, info.isCurrent else { throw OwnMediaModelPreviewFailure.stale }
            let url = try OwnMediaModelPreviewRoute.decode(bytes, status: status, origins: approval.approvedOrigins)
            guard current() else { throw OwnMediaModelPreviewFailure.stale }
            readingResource = true
            var modelRequest = URLRequest(url: url)
            modelRequest.httpMethod = "GET"; modelRequest.httpShouldHandleCookies = false; modelRequest.cachePolicy = .reloadIgnoringLocalCacheData
            modelRequest.setValue("model/gltf-binary, application/octet-stream", forHTTPHeaderField: "Accept")
            let auth = OwnMediaModelPreviewAuthorization(purpose: .model, request: modelRequest, current: current)
            let id = UUID(); active[id] = auth
            defer { active.removeValue(forKey: id); auth.invalidate() }
            let data = try await modelReader.model(modelRequest, authorization: auth)
            try Task.checkCancellation()
            guard auth.didForward, auth.isCurrent, OwnMediaModelBytes.accepts(data) else { throw OwnMediaModelPreviewFailure.invalidResponse }
            return .init(bytes: data, displayDeadline: deadline)
        } catch {
            guard current() else { throw OwnMediaModelPreviewFailure.stale }
            // A current metadata denial retires only this per-asset preview lease.
            // Resource URL errors do not get classified as account authentication errors.
            if !readingResource, error as? OwnMediaModelPreviewFailure == .unauthorized { approval.revoke(); retire() }
            throw error
        }
    }
}

/// Bounded static GLB only. No animation/skin/extension compatibility is implied.
public enum OwnMediaModelBytes {
    public static let maximumInputBytes = PlayKitGLBPolicy.maximumBytes
    public static func accepts(_ data: Data) -> Bool { (try? PlayKitGLBPolicy.validate(data)) != nil }
}

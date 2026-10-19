import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 设置 → 隐私与定位 → 我的待审媒体 (`GET /api/media/asset/list[?beforeId=]`).
/// Read-only: re-submission (`POST …/retry`) and author preview are not included.
public struct OwnMediaAsset: Equatable, Identifiable {
    public enum ReviewState: String, Equatable { case hold = "HOLD", approved = "APPROVED", rejected = "REJECTED", unavailable = "UNAVAILABLE" }
    public enum MediaType: Equatable { case image, audio, model3D, other }
    public let id: Int64
    public let reviewState: ReviewState
    public let reviewReason: String
    public let mediaType: MediaType
}

public struct OwnMediaPage: Equatable {
    public static let pageSize = 50
    public let rows: [OwnMediaAsset]
    /// The source asks for older rows only after a full page.
    public var hasMore: Bool { rows.count == Self.pageSize }
    public var nextCursor: Int64? { hasMore ? rows.last?.id : nil }

    /// Mirrors the source page validation: at most 50 rows, positive 64-bit IDs,
    /// known review states, strictly descending, and older than the cursor.
    public static func decode(_ data: Data, before cursor: Int64?) throws -> OwnMediaPage {
        guard let status = try? JSONDecoder().decode(Status.self, from: data) else { throw APIError.malformedResponse }
        if status.code == 401 || status.code == 2 { throw APIError.unauthorized }
        guard status.code == 200 else { throw OwnMediaReadFailure.rejected(code: status.code) }
        guard let raw = (try? JSONDecoder().decode(Payload.self, from: data))?.data, raw.count <= pageSize
        else { throw APIError.malformedResponse }
        var rows: [OwnMediaAsset] = []
        for item in raw {
            guard let id = item.assetId, let state = OwnMediaAsset.ReviewState(rawValue: item.reviewState) else { throw APIError.malformedResponse }
            if let previous = rows.last?.id, id >= previous { throw APIError.malformedResponse }
            if let cursor, id >= cursor { throw APIError.malformedResponse }
            let type: OwnMediaAsset.MediaType
            switch item.mediaType {
            case "IMAGE": type = .image
            case "AUDIO": type = .audio
            case "MODEL3D": type = .model3D
            default: type = .other
            }
            let reason = item.reviewReason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            rows.append(.init(id: id, reviewState: state, reviewReason: String(reason.prefix(200)), mediaType: type))
        }
        return .init(rows: rows)
    }
    private struct Status: Decodable { let code: Int }
    private struct Payload: Decodable { let data: [Row] }
    private struct Row: Decodable {
        let assetId: Int64?
        let reviewState: String
        let reviewReason: String?
        let mediaType: String?
        enum CodingKeys: String, CodingKey { case assetId, reviewState, reviewReason, mediaType }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            if let number = try? c.decode(Int64.self, forKey: .assetId) {
                assetId = number > 0 && number <= 9_007_199_254_740_991 ? number : nil
            } else {
                assetId = OwnMediaPage.identifier(try? c.decode(String.self, forKey: .assetId))
            }
            reviewState = try c.decode(String.self, forKey: .reviewState)
            reviewReason = try? c.decodeIfPresent(String.self, forKey: .reviewReason)
            mediaType = try? c.decodeIfPresent(String.self, forKey: .mediaType)
        }
    }
    /// A positive decimal ID string of at most 19 digits (source `validMediaId`).
    static func identifier(_ text: String?) -> Int64? {
        guard let text, text.range(of: "^[1-9][0-9]{0,18}$", options: .regularExpression) != nil else { return nil }
        return Int64(text)
    }
}

public enum OwnMediaReadFailure: Error, Equatable { case rejected(code: Int) }

public enum OwnMediaReadRoute {
    public static let path = "api/media/asset/list"
    /// Exactly GET, no body, the bare list path or one positive `beforeId`.
    public static func accepts(_ request: URLRequest, baseURL: URL) -> Bool {
        guard let url = request.url, url.fragment == nil, request.httpMethod == "GET",
              request.httpBody == nil, request.httpBodyStream == nil,
              request.value(forHTTPHeaderField: "Content-Type") == nil,
              let token = request.value(forHTTPHeaderField: "Authorization"), AuthRequestBuilder.isValidToken(token),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return false }
        let items = components.queryItems
        components.query = nil
        guard let bare = components.url,
              bare.absoluteString.utf8.elementsEqual(baseURL.appendingPathComponent(path).absoluteString.utf8) else { return false }
        guard let items else { return url.query == nil }
        return items.count == 1 && items[0].name == "beforeId" &&
            OwnMediaPage.identifier(items[0].value) != nil
    }
    static func request(baseURL: URL, before cursor: Int64?, token: String) throws -> URLRequest {
        guard AuthRequestBuilder.isValidToken(token), cursor.map({ $0 > 0 }) ?? true,
              var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        else { throw APIError.invalidRequest }
        if let cursor { components.queryItems = [URLQueryItem(name: "beforeId", value: String(cursor))] }
        guard let url = components.url else { throw APIError.invalidRequest }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(token, forHTTPHeaderField: "Authorization")
        return request
    }
}

/// A bounded, independently supplied read lease. Signing in never creates one.
@available(macOS 14.0, *)
@MainActor @Observable public final class OwnMediaReadApproval {
    public let context: RuntimeDependencyContext
    public let expiresAt: Date
    public let revision = UUID()
    public private(set) var isRevoked = false
    public init(context: RuntimeDependencyContext, expiresAt: Date) throws {
        let duration = expiresAt.timeIntervalSinceNow
        guard context.market == .china, context.session.accountID > 0,
              AuthRequestBuilder.isValidToken(context.session.token),
              duration.isFinite, duration > 0, duration <= 86_400 else { throw APIError.invalidConfiguration }
        self.context = context; self.expiresAt = expiresAt
    }
    public func revoke() { isRevoked = true }
    public func matches(_ current: RuntimeDependencyContext, now: Date = Date()) -> Bool {
        !isRevoked && now < expiresAt && ContentDraftContextFence.matches(context, current)
    }
}

public struct OwnMediaService {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport
    public init(configuration: APIConfiguration, transport: any HTTPTransport) {
        self.configuration = configuration; self.transport = transport
    }
    public func page(before cursor: Int64?, token: String) async throws -> OwnMediaPage {
        let request = try OwnMediaReadRoute.request(baseURL: configuration.baseURL, before: cursor, token: token)
        try Task.checkCancellation()
        let (data, status) = try await transport.send(request)
        try Task.checkCancellation()
        if status == 401 { throw APIError.unauthorized }
        if status == 403 { throw OwnMediaReadFailure.rejected(code: 403) }
        guard (200..<300).contains(status) else { throw APIError.httpStatus(status) }
        guard data.count <= 128 * 1024 else { throw APIError.malformedResponse }
        return try OwnMediaPage.decode(data, before: cursor)
    }
}

public struct OwnMediaSession: Equatable {
    public let accountID: Int
    public let epoch: UInt64
    public let approval: UUID?
    let token: String
    public init(accountID: Int, epoch: UInt64, token: String, approval: UUID?) throws {
        guard accountID > 0, AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        self.accountID = accountID; self.epoch = epoch; self.token = token; self.approval = approval
    }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.accountID == rhs.accountID && lhs.epoch == rhs.epoch && lhs.approval == rhs.approval &&
            lhs.token.utf8.elementsEqual(rhs.token.utf8)
    }
}

@MainActor public protocol OwnMediaReading: AnyObject {
    var scope: UUID { get }
    var isSignedIn: Bool { get }
    var isAvailable: Bool { get }
    func page(before cursor: Int64?) async throws -> OwnMediaPage
}

@MainActor public final class OwnMediaSessionReader: OwnMediaReading {
    private let service: OwnMediaService?
    private let currentSession: () -> OwnMediaSession?
    private let onUnauthorized: (OwnMediaSession) -> Void
    private var snapshot: OwnMediaSession?
    private var stamp = UUID()
    public var scope: UUID {
        let current = currentSession()
        if snapshot != current { snapshot = current; stamp = UUID() }
        return stamp
    }
    public var isSignedIn: Bool { currentSession() != nil }
    public var isAvailable: Bool { service != nil && currentSession()?.approval != nil }
    public init(service: OwnMediaService?, currentSession: @escaping () -> OwnMediaSession?,
                onUnauthorized: @escaping (OwnMediaSession) -> Void = { _ in }) {
        self.service = service; self.currentSession = currentSession; self.onUnauthorized = onUnauthorized
        snapshot = currentSession()
    }
    public func page(before cursor: Int64?) async throws -> OwnMediaPage {
        try Task.checkCancellation()
        guard let captured = currentSession() else { throw APIError.unauthorized }
        guard captured.approval != nil, let service else { throw APIError.notConfigured }
        do {
            let value = try await service.page(before: cursor, token: captured.token)
            guard currentSession() == captured else { throw CancellationError() }
            return value
        } catch {
            guard !Task.isCancelled, currentSession() == captured else { throw CancellationError() }
            if error as? APIError == .unauthorized { onUnauthorized(captured) }
            throw error
        }
    }
}

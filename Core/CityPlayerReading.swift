import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum CityReadError: Error, Equatable { case unavailable, participationUnavailable, pointsUnavailable, snapshotChanged, unauthorized, invalidResponse }
public enum CityMembership: String, Decodable, Sendable { case joined = "JOINED", notJoined = "NOT_JOINED", unavailable = "UNAVAILABLE" }
public struct CityReadBoard: Decodable, Equatable, Sendable {
    public let gameId, boardId, regionId, seasonId, rulesReleaseId, rulesHash, lifecycle, title: String
    public let revision: Int64
    var valid: Bool {
        [gameId, boardId, regionId, seasonId, rulesReleaseId].allSatisfy(CityReadRoute.validID) &&
        rulesHash.range(of: "\\A[0-9a-f]{64}\\z", options: .regularExpression) != nil &&
        ["OPEN", "FROZEN", "CLOSED"].contains(lifecycle) && CityReadRoute.validLabel(title) &&
        (0...9_007_199_254_740_991).contains(revision)
    }
}
public struct CityReadPoint: Decodable, Equatable, Identifiable, Sendable {
    public let pointId, title: String
    public let latitude, longitude: Double
    public let mine: Bool
    public var id: String { pointId }
    var valid: Bool { CityReadRoute.validID(pointId) && CityReadRoute.validLabel(title) && latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude) }
}
public struct CityParticipation: Decodable, Equatable, Sendable {
    public let participationId: String
    public let membershipVersion: Int64
    var valid: Bool { CityReadRoute.validID(participationId) && (0...9_007_199_254_740_991).contains(membershipVersion) }
}
public struct CityReadSnapshot: Equatable, Sendable {
    public let board: CityReadBoard
    public let membership: CityMembership
    public let participation: CityParticipation?
    /// nil is unavailable; [] means server-verified complete empty projection.
    public let points: [CityReadPoint]?
}
public enum CityReadState: Equatable, Sendable { case unavailable, loading, notPublished, available(CityReadSnapshot) }

/// Explicit development-only, revocable current-session read authority. Never issued by login or roles.
@available(macOS 14.0, *)
@MainActor @Observable public final class CityPlayerReadApproval {
    public let context: RuntimeDependencyContext
    public let regionID: String
    public let expiresAt: Date
    public let revision = UUID()
    public private(set) var isRevoked = false
    @ObservationIgnored private var expiryTask: Task<Void, Never>?
    public init(context: RuntimeDependencyContext, regionID: String, expiresAt: Date) throws {
        _ = try APIConfiguration(baseURL: context.baseURL)
        let duration = expiresAt.timeIntervalSinceNow
        guard context.market == .china, ["player", "club", "merchant"].contains(context.role), context.session.accountID > 0,
              AuthRequestBuilder.isValidToken(context.session.token), CityReadRoute.validID(regionID), duration.isFinite, duration > 0, duration <= 86_400 else { throw APIError.invalidConfiguration }
        self.context = context; self.regionID = regionID; self.expiresAt = expiresAt
        expiryTask = Task { @MainActor [weak self] in
            let remaining = max(0, min(expiresAt.timeIntervalSinceNow, 86_400))
            do { if remaining > 0 { try await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000)) }; try Task.checkCancellation() } catch { return }
            self?.revoke()
        }
    }
    deinit { expiryTask?.cancel() }
    public func revoke() { isRevoked = true; expiryTask?.cancel(); expiryTask = nil }
    public func matches(_ current: RuntimeDependencyContext, now: Date = Date()) -> Bool {
        !isRevoked && now < expiresAt && ContentDraftContextFence.matches(context, current)
    }
    public func expireIfNeeded(now: Date = Date()) { if now >= expiresAt { revoke() } }
}

public struct CityReadRoute: Equatable {
    public enum View: String { case current, participation, points }
    public let view: View
    public let regionID: String
    private let fields: [String: String]
    public init(view: View, regionID: String, board: CityReadBoard? = nil) throws {
        guard Self.validID(regionID), (view == .current && board == nil) || (view != .current && board?.valid == true && board?.regionId == regionID) else { throw APIError.invalidRequest }
        self.view = view; self.regionID = regionID
        var values = ["regionId": regionID]
        if let board { values.merge(["boardId": board.boardId, "seasonId": board.seasonId, "rulesReleaseId": board.rulesReleaseId, "revision": String(board.revision)]) { _, new in new } }
        fields = values
    }
    public func request(baseURL: URL, token: String) throws -> URLRequest {
        guard AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        let configuration = try APIConfiguration(baseURL: baseURL)
        guard var components = URLComponents(url: configuration.baseURL.appendingPathComponent("api/city-game/" + view.rawValue), resolvingAgainstBaseURL: false) else { throw APIError.invalidConfiguration }
        components.queryItems = fields.keys.sorted().map { URLQueryItem(name: $0, value: fields[$0]) }
        guard let url = components.url else { throw APIError.invalidRequest }
        var request = URLRequest(url: url); request.httpMethod = "GET"; request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept"); request.setValue(token, forHTTPHeaderField: "Authorization")
        return request
    }
    public init?(request: URLRequest, baseURL: URL) {
        guard request.httpMethod == "GET", request.httpBody == nil, request.httpBodyStream == nil,
              request.value(forHTTPHeaderField: "Accept") == "application/json", let url = request.url,
              url.fragment == nil, let components = URLComponents(url: url, resolvingAgainstBaseURL: false), let items = components.queryItems,
              items.count == Set(items.map(\.name)).count else { return nil }
        var values: [String: String] = [:]
        for item in items { guard let value = item.value else { return nil }; values[item.name] = value }
        guard let region = values["regionId"], Self.validID(region), let view = View.all.first(where: { baseURL.appendingPathComponent("api/city-game/" + $0.rawValue).path == url.path }) else { return nil }
        let keys: Set<String> = view == .current ? ["regionId"] : ["regionId", "boardId", "seasonId", "rulesReleaseId", "revision"]
        guard Set(values.keys) == keys else { return nil }
        if view != .current {
            guard ["boardId", "seasonId", "rulesReleaseId"].allSatisfy({ Self.validID(values[$0] ?? "") }), let raw = values["revision"], let revision = Int64(raw), String(revision) == raw, (0...9_007_199_254_740_991).contains(revision) else { return nil }
        }
        self.view = view; regionID = region; fields = values
        guard let canonical = try? self.request(baseURL: baseURL, token: "synthetic-token"), canonical.url?.absoluteString.utf8.elementsEqual(url.absoluteString.utf8) == true else { return nil }
    }
    static func validID(_ value: String) -> Bool { value.range(of: "\\A[A-Za-z0-9][A-Za-z0-9_-]{0,95}\\z", options: .regularExpression) != nil }
    static func validLabel(_ value: String) -> Bool { !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && value.utf16.count <= 160 && !value.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) }
}
private extension CityReadRoute.View { static let all: [Self] = [.current, .participation, .points] }

private struct CityEnvelope: Decodable { let code: Int; let data: CityPayload?; let errorCode: String? }
private struct CityPayload: Decodable {
    let contract, scope, status: String
    let regionId: String?
    let board: CityReadBoard?
    let participationStatus: CityMembership?
    let pointsStatus: String?
    let participation: CityParticipation?
    let points: [CityReadPoint]?
    let complete: Bool?
}

@available(macOS 14.0, *)
@MainActor @Observable public final class CityPlayerReader {
    private var stored: CityReadState = .unavailable
    private let approval: CityPlayerReadApproval?
    private let transport: any HTTPTransport
    private let isCurrent: () -> Bool
    private let onUnauthorized: () -> Void
    private var generation = UUID()
    public var isConfigured: Bool { approval.map { $0.matches($0.context) } == true && isCurrent() }
    public var state: CityReadState { isConfigured ? stored : .unavailable }
    /// Rechecks the existing lease/session fence on every render and tap. This is
    /// a presentation projection only and never grants read or gameplay authority.
    public var pointMapContext: CityPointMapContext? {
        guard case .available(let snapshot) = state else { return nil }
        return CityPointMapContext(readID: generation, snapshot: snapshot)
    }
    public init(approval: CityPlayerReadApproval?, transport: any HTTPTransport, isCurrent: @escaping () -> Bool, onUnauthorized: @escaping () -> Void = {}) { self.approval = approval; self.transport = transport; self.isCurrent = isCurrent; self.onUnauthorized = onUnauthorized }
    public func cancel() { generation = UUID(); stored = .unavailable }
    public func load() async {
        let stamp = UUID(); generation = stamp; stored = .unavailable
        guard isConfigured, let approval else { return }; stored = .loading
        do {
            let current = try await read(.current, board: nil, stamp: stamp)
            if current.status == "NO_CURRENT_BOARD" {
                guard current.regionId == approval.regionID, current.board == nil, current.points == nil, current.participation == nil, current.participationStatus == nil, current.pointsStatus == nil, current.complete == nil else { throw CityReadError.invalidResponse }
                stored = .notPublished; return
            }
            guard current.status == "AVAILABLE", let board = current.board, board.valid, board.regionId == approval.regionID,
                  let advertisedMembership = current.participationStatus, ["AVAILABLE", "UNAVAILABLE"].contains(current.pointsStatus ?? ""),
                  advertisedMembership != .unavailable || current.pointsStatus == "UNAVAILABLE" else { throw CityReadError.invalidResponse }
            var membership = advertisedMembership, participation: CityParticipation?
            if advertisedMembership != .unavailable {
                do {
                    let payload = try await read(.participation, board: board, stamp: stamp)
                    guard let status = payload.participationStatus, status == advertisedMembership,
                          (status == .joined && payload.participation?.valid == true) || (status == .notJoined && payload.participation == nil) else { throw CityReadError.invalidResponse }
                    membership = status; participation = payload.participation
                } catch CityReadError.participationUnavailable { membership = .unavailable }
            }
            var points: [CityReadPoint]?
            if current.pointsStatus == "AVAILABLE", membership != .unavailable {
                do {
                    let payload = try await read(.points, board: board, stamp: stamp)
                    guard payload.complete == true, let values = payload.points, values.count <= 200,
                          Set(values.map(\.pointId)).count == values.count, values.allSatisfy({ $0.valid && (!$0.mine || membership == .joined) }) else { throw CityReadError.invalidResponse }
                    points = values
                } catch CityReadError.pointsUnavailable { points = nil }
            }
            guard isConfigured, generation == stamp, !Task.isCancelled else { throw CancellationError() }
            stored = .available(.init(board: board, membership: membership, participation: participation, points: points))
        } catch { if generation == stamp { stored = .unavailable; if Self.isUnauthorized(error), isConfigured, !Task.isCancelled { onUnauthorized() } } }
    }
    private static func isUnauthorized(_ error: Error) -> Bool {
        error as? CityReadError == .unauthorized || error as? APIError == .unauthorized || error as? APIError == .httpStatus(401)
    }
    private func read(_ view: CityReadRoute.View, board: CityReadBoard?, stamp: UUID) async throws -> CityPayload {
        guard isConfigured, generation == stamp, let approval else { throw CancellationError() }
        try Task.checkCancellation()
        let route = try CityReadRoute(view: view, regionID: approval.regionID, board: board)
        let (data, status) = try await transport.send(route.request(baseURL: approval.context.baseURL, token: approval.context.session.token))
        guard isConfigured, generation == stamp, !Task.isCancelled else { throw CancellationError() }
        // Authentication filters can reject before the CITY controller and omit its envelope.
        if status == 401 { throw CityReadError.unauthorized }
        guard data.count <= 262_144 else { throw CityReadError.invalidResponse }
        let envelope = try JSONDecoder().decode(CityEnvelope.self, from: data)
        if status == 200, envelope.code == 401 { throw CityReadError.unauthorized }
        guard status == 200, envelope.code == 200 else {
            switch (status, envelope.code, envelope.errorCode) {
            case (409, 409, "CITY_SNAPSHOT_CHANGED"): throw CityReadError.snapshotChanged
            case (503, 503, "CITY_PARTICIPATION_UNAVAILABLE") where view == .participation: throw CityReadError.participationUnavailable
            case (503, 503, "CITY_POINTS_UNAVAILABLE") where view == .points: throw CityReadError.pointsUnavailable
            default: throw CityReadError.unavailable
            }
        }
        guard let payload = envelope.data, payload.contract == "CITY_PLAYER_READ_V1", payload.scope == "CITY" else { throw CityReadError.invalidResponse }
        if let board { guard payload.status == "AVAILABLE", payload.board == board else { throw CityReadError.snapshotChanged } }
        return payload
    }
}

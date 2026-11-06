import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Independent approval for coarse nearby-player snapshots; grants no presence publication.
@MainActor @Observable public final class RoamNearbyPlayersReadAccess {
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
              approval.paths == [RoamNearbyPlayersReadRoute.path] else { throw APIError.invalidConfiguration }
        self.context = context; endpoints = approval
    }
    public func revoke() { isRevoked = true }
    public func matches(_ current: RuntimeDependencyContext) -> Bool {
        !isRevoked && ContentDraftContextFence.matches(context, current)
    }
}

/// Exact current manual-center request emitted by the existing read service.
public struct RoamNearbyPlayersReadRoute: Equatable {
    public static let path = "api/roam/nearby-runners"
    public static let maximumRadius = 3000
    public let radius: Int
    public init?(request: URLRequest, baseURL: URL, area: RoamSearchArea) {
        guard let url = request.url, url.query == nil, url.fragment == nil,
              url.absoluteString.utf8.elementsEqual(baseURL.appendingPathComponent(Self.path).absoluteString.utf8),
              request.httpMethod == "POST", request.httpBodyStream == nil,
              request.value(forHTTPHeaderField: "Accept") == "application/json",
              let type = request.value(forHTTPHeaderField: "Content-Type"), type.hasPrefix("multipart/form-data; boundary="),
              let body = request.httpBody, body.count <= 4096, let text = String(data: body, encoding: .utf8) else { return nil }
        let boundary = String(type.dropFirst("multipart/form-data; boundary=".count))
        guard !boundary.isEmpty, boundary.count <= 70,
              boundary.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) else { return nil }
        let parts = text.components(separatedBy: "name=\"radius\"\r\n\r\n")
        guard parts.count == 2, let value = parts[1].components(separatedBy: "\r\n").first,
              let radius = Int(value), (1...Self.maximumRadius).contains(radius), String(radius) == value,
              let canonical = try? AuthRequestBuilder.makeFormRequest(url: url,
                fields: ["lat": String(area.coordinate.latitude), "lng": String(area.coordinate.longitude), "radius": value],
                token: nil, boundary: boundary), canonical.httpBody == body else { return nil }
        self.radius = radius
    }
    public func validateResponse(_ response: (Data, Int)) throws {
        guard (200..<300).contains(response.1) else { return }
        struct Status: Decodable { let code: Int }
        struct Envelope: Decodable { let data: [RoamPlayer] }
        do {
            guard try JSONDecoder().decode(Status.self, from: response.0).code == 200 else { return }
            let rows = try JSONDecoder().decode(Envelope.self, from: response.0).data
            guard rows.count <= 20, rows.allSatisfy(\.isDisplayable), Set(rows.map(\.id)).count == rows.count else { throw APIError.malformedResponse }
        } catch { throw APIError.malformedResponse }
    }
}

/// Reads coarse snapshots only. The manual selection is query context, never an approval.
@MainActor public final class RoamNearbyPlayersReader: RoamReading {
    private let service: RoamService?
    private let deployment: URL?
    private let current: () -> RuntimeDependencyContext?
    private let viewerRevision: () -> UInt64
    private let area: () -> ManualMapAreaSelection.Snapshot?
    private let selectAccess: (RuntimeDependencyContext) -> RoamNearbyPlayersReadAccess?
    private let onUnauthorized: (RuntimeDependencyContext) -> Void
    public init(configuration: APIConfiguration?, transport: any HTTPTransport,
                current: @escaping () -> RuntimeDependencyContext?, viewerRevision: @escaping () -> UInt64,
                area: @escaping () -> ManualMapAreaSelection.Snapshot?,
                access: @escaping (RuntimeDependencyContext) -> RoamNearbyPlayersReadAccess?,
                onUnauthorized: @escaping (RuntimeDependencyContext) -> Void = { _ in }) {
        service = configuration.map { RoamService(configuration: $0, transport: transport) }
        deployment = configuration?.baseURL; self.current = current; self.viewerRevision = viewerRevision
        self.area = area; selectAccess = access; self.onUnauthorized = onUnauthorized
    }
    private var currentAccess: RoamNearbyPlayersReadAccess? {
        guard let context = current(), let access = selectAccess(context), access.matches(context),
              deployment?.absoluteString.utf8.elementsEqual(context.baseURL.absoluteString.utf8) == true else { return nil }
        return access
    }
    public var identity: RoamReadIdentity? {
        guard let context = current() else { return nil }
        return .init(accountID: context.session.accountID, epoch: context.session.epoch, role: context.role,
            viewerRevision: viewerRevision(), areaRevision: area()?.revision ?? 0,
            nearbyPlayersApprovalRevision: currentAccess?.revision)
    }
    public var searchArea: RoamSearchArea? { area()?.area }
    public var isConfigured: Bool { service != nil && currentAccess != nil }
    public var isOfflineExample: Bool { false }
    public func roamPlayers(radiusM: Int) async throws -> [RoamPlayer] {
        guard (1...RoamNearbyPlayersReadRoute.maximumRadius).contains(radiusM) else { throw APIError.invalidRequest }
        try Task.checkCancellation()
        guard let context = current() else { throw APIError.unauthorized }
        guard let selected = currentAccess, let service else { throw APIError.notConfigured }
        guard let snapshot = area() else { throw RoamReadFailure.searchAreaRequired }
        let viewer = viewerRevision()
        func valid() -> Bool {
            guard !Task.isCancelled, let fresh = current(), ContentDraftContextFence.matches(context, fresh),
                  viewerRevision() == viewer, area() == snapshot else { return false }
            return currentAccess === selected
        }
        guard valid() else { throw CancellationError() }
        do {
            let result = try await service.players(area: snapshot.area, radiusM: radiusM, token: context.session.token)
            guard valid() else { throw CancellationError() }
            return result
        } catch {
            guard valid() else { throw CancellationError() }
            if error as? APIError == .unauthorized { onUnauthorized(context) }
            throw error
        }
    }
    public func roamPlaces(radiusM: Int) async throws -> [RoamPlace] { throw APIError.notConfigured }
    public func roamRouteNodes(radiusM: Int) async throws -> [RoamRouteNode] { throw APIError.notConfigured }
    public func roamEvents(radiusM: Int) async throws -> RoamEvents { throw APIError.notConfigured }
    public func roamExploreDay() async throws -> RoamExploreDay? { throw APIError.notConfigured }
    public func roamNodeDetail(id: Int) async throws -> RoamNodeDetail { throw APIError.notConfigured }
    public func roamMerchantDetail(id: Int) async throws -> RoamMerchantDetail { throw APIError.notConfigured }
}

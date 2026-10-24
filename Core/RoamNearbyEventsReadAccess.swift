import Foundation
import Observation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Independent approval for nearby activity and topic reads; grants no membership or write action.
@MainActor @Observable public final class RoamNearbyEventsReadAccess {
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
              approval.paths == [RoamNearbyEventsReadRoute.path] else { throw APIError.invalidConfiguration }
        self.context = context; endpoints = approval
    }
    public func revoke() { isRevoked = true }
    public func matches(_ current: RuntimeDependencyContext) -> Bool {
        !isRevoked && ContentDraftContextFence.matches(context, current)
    }
}

/// Exact current manual-center request emitted by the existing read service.
public struct RoamNearbyEventsReadRoute: Equatable {
    public static let path = "api/roam/hangout/nearby"
    public static let maximumRadius = 20000
    public let radius: Int
    public init?(request: URLRequest, baseURL: URL, area: RoamSearchArea) {
        guard let url = request.url, url.fragment == nil,
              request.httpMethod == "GET", request.httpBody == nil, request.httpBodyStream == nil,
              request.value(forHTTPHeaderField: "Content-Type") == nil,
              request.value(forHTTPHeaderField: "Accept") == "application/json",
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let query = parts.queryItems, query.count == 3 else { return nil }
        var fields: [String: String] = [:]
        for item in query {
            guard fields[item.name] == nil, let value = item.value else { return nil }
            fields[item.name] = value
        }
        guard Set(fields.keys) == ["lat", "lng", "radius"],
              fields["lat"] == String(area.coordinate.latitude), fields["lng"] == String(area.coordinate.longitude),
              let value = fields["radius"], let radius = Int(value),
              (1...Self.maximumRadius).contains(radius), String(radius) == value,
              var expected = URLComponents(url: baseURL.appendingPathComponent(Self.path), resolvingAgainstBaseURL: false) else { return nil }
        expected.queryItems = fields.keys.sorted().map { URLQueryItem(name: $0, value: fields[$0]) }
        guard expected.url?.absoluteString.utf8.elementsEqual(url.absoluteString.utf8) == true else { return nil }
        self.radius = radius
    }
    public func validateResponse(_ response: (Data, Int)) throws {
        guard (200..<300).contains(response.1) else { return }
        struct Status: Decodable { let code: Int }
        struct Items: Decodable { let items: [RoamEvent]; let radius: Int }
        struct Envelope: Decodable { let data: Items }
        do {
            guard try JSONDecoder().decode(Status.self, from: response.0).code == 200 else { return }
            let data = try JSONDecoder().decode(Envelope.self, from: response.0).data
            let visible = data.items.filter(\.isSupported)
            guard data.radius == radius, data.items.count <= 200,
                  Set(visible.map(\.id)).count == visible.count,
                  data.items.allSatisfy({ $0.kind != "activity" && $0.kind != "topic" || $0.sourceID > 0 }) else { throw APIError.malformedResponse }
        } catch { throw APIError.malformedResponse }
    }
}

/// Reads nearby activities and topics only. The manual selection is query context, never an approval.
@MainActor public final class RoamNearbyEventsReader: RoamReading {
    private let service: RoamService?
    private let deployment: URL?
    private let current: () -> RuntimeDependencyContext?
    private let viewerRevision: () -> UInt64
    private let area: () -> ManualMapAreaSelection.Snapshot?
    private let selectAccess: (RuntimeDependencyContext) -> RoamNearbyEventsReadAccess?
    private let onUnauthorized: (RuntimeDependencyContext) -> Void
    public init(configuration: APIConfiguration?, transport: any HTTPTransport,
                current: @escaping () -> RuntimeDependencyContext?, viewerRevision: @escaping () -> UInt64,
                area: @escaping () -> ManualMapAreaSelection.Snapshot?,
                access: @escaping (RuntimeDependencyContext) -> RoamNearbyEventsReadAccess?,
                onUnauthorized: @escaping (RuntimeDependencyContext) -> Void = { _ in }) {
        service = configuration.map { RoamService(configuration: $0, transport: transport) }
        deployment = configuration?.baseURL; self.current = current; self.viewerRevision = viewerRevision
        self.area = area; selectAccess = access; self.onUnauthorized = onUnauthorized
    }
    private var currentAccess: RoamNearbyEventsReadAccess? {
        guard let context = current(), let access = selectAccess(context), access.matches(context),
              deployment?.absoluteString.utf8.elementsEqual(context.baseURL.absoluteString.utf8) == true else { return nil }
        return access
    }
    public var identity: RoamReadIdentity? {
        guard let context = current() else { return nil }
        return .init(accountID: context.session.accountID, epoch: context.session.epoch, role: context.role,
            viewerRevision: viewerRevision(), areaRevision: area()?.revision ?? 0,
            nearbyEventsApprovalRevision: currentAccess?.revision)
    }
    public var searchArea: RoamSearchArea? { area()?.area }
    public var isConfigured: Bool { service != nil && currentAccess != nil }
    public var isOfflineExample: Bool { false }
    public func roamEvents(radiusM: Int) async throws -> RoamEvents {
        guard (1...RoamNearbyEventsReadRoute.maximumRadius).contains(radiusM) else { throw APIError.invalidRequest }
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
            let result = try await service.events(area: snapshot.area, radiusM: radiusM, token: context.session.token)
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
    public func roamPlayers(radiusM: Int) async throws -> [RoamPlayer] { throw APIError.notConfigured }
    public func roamExploreDay() async throws -> RoamExploreDay? { throw APIError.notConfigured }
    public func roamNodeDetail(id: Int) async throws -> RoamNodeDetail { throw APIError.notConfigured }
    public func roamMerchantDetail(id: Int) async throws -> RoamMerchantDetail { throw APIError.notConfigured }
}

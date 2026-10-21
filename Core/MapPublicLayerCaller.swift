import Foundation
import Observation

/// Posts one public-layer page through the search-map reader.
/// The reader already requires manual-map approval and sends `Authorization` as the raw session token.
/// This adds no header and no second grant.
@MainActor public struct MapPublicLayerTransport {
    private let reader: any SearchMapReading
    public init(reader: any SearchMapReading) { self.reader = reader }
    public func post(area: RoamSearchArea, body: Data) async throws -> Data {
        try await reader.publicLayers(area: area, body: body)
    }
}

/// Map-entry caller: open, request, accept, then project through `MapLayerMerge` / `MapVisualHostBridge`.
/// Account and query generations are the caller's own fence, in addition to the adapter token.
@Observable @MainActor public final class MapPublicLayerCaller {
    public enum Detail: Equatable {
        case cityNode(Int), merchant(Int), activity(Int)
    }
    public struct ShownDetail: Equatable {
        public let route: Detail
        public let text: String
    }
    public struct Query: Equatable {
        public var viewerID: Int
        public var minLat, maxLat, minLng, maxLng: String
        public var layers: [String]
        public var limit: Int
    }
    public enum Failure: String, Equatable {
        case viewer, query, rejected, unauthorized, notConfigured, failed
    }
    public static let visibleLayers: Set<MapSourceType> = [.roamPOI, .store, .registrableActivity, .themeNode]

    public private(set) var accountID: Int?
    public private(set) var accountGeneration: UInt64 = 0
    public private(set) var queryGeneration: UInt64 = 0
    public private(set) var session: MapPublicLayerSession?
    public private(set) var ready: [MapLayerItem] = []
    public private(set) var detail: ShownDetail?
    public private(set) var failure: Failure?
    public private(set) var loading = false
    private var detailGeneration: UInt64 = 0
    private var last: Query?
    private let transport: MapPublicLayerTransport
    private let cityNode: @MainActor (Int) async throws -> String
    private let merchant: @MainActor (Int) async throws -> String
    private let activity: @MainActor (Int) async throws -> String

    public init(reader: any SearchMapReading, activity: @escaping @MainActor (Int) async throws -> String) {
        transport = MapPublicLayerTransport(reader: reader)
        cityNode = { (try await reader.cityNode(id: $0)).name }
        merchant = { try await reader.merchant(id: $0).merchant.name ?? "" }
        self.activity = activity
    }

    /// A different account retires the page, the open detail, and every in-flight callback.
    public func noteAccount(_ id: Int?) {
        guard id != accountID else { return }
        accountID = id
        accountGeneration &+= 1
        queryGeneration &+= 1
        detailGeneration &+= 1
        session = nil
        ready = []
        detail = nil
        last = nil
        loading = false
        failure = nil
    }

    /// Leaving the screen. A late page or detail callback must not land.
    public func abandon() {
        queryGeneration &+= 1
        detailGeneration &+= 1
        loading = false
    }

    public func submit(_ query: Query) async {
        guard query.viewerID == accountID, query.viewerID > 0 else { failure = .viewer; return }
        if query != last { session = nil }
        last = query
        queryGeneration &+= 1
        detailGeneration &+= 1
        detail = nil
        await run(restart: true)
    }

    public func nextPage() async {
        guard session?.complete == false else { return }
        await run(restart: false)
    }

    /// Detail return starts a new query generation, then reloads that same box.
    public func returned() async {
        detailGeneration &+= 1
        queryGeneration &+= 1
        detail = nil
        guard last != nil else { return }
        await run(restart: true)
    }

    /// `navigate` is the only store detail. `register` is never a route. Theme and story have none.
    public static func detail(for item: MapLayerItem) -> Detail? {
        guard let id = Int(item.key.id), id > 0, String(id) == item.key.id else { return nil }
        switch item.key.type {
        case .roamPOI: return .cityNode(id)
        case .store: return item.capabilities == [.navigate] ? .merchant(id) : nil
        case .registrableActivity: return .activity(id)
        case .themeNode, .sideQuest, .cityBoardPoint: return nil
        }
    }

    public func openDetail(_ item: MapLayerItem) async {
        guard let route = Self.detail(for: item) else { return }
        let account = accountGeneration, query = queryGeneration, viewer = accountID
        detailGeneration &+= 1
        let ticket = detailGeneration
        do {
            let text: String
            switch route {
            case .cityNode(let id): text = try await cityNode(id)
            case .merchant(let id): text = try await merchant(id)
            case .activity(let id): text = try await activity(id)
            }
            guard accountGeneration == account, queryGeneration == query, detailGeneration == ticket, accountID == viewer else { return }
            detail = ShownDetail(route: route, text: text)
            failure = nil
        } catch {
            guard accountGeneration == account, queryGeneration == query, detailGeneration == ticket, accountID == viewer else { return }
            failure = Self.failure(error)
        }
    }

    public func project(theme: MapVisualHostThemeSnapshot) throws -> [MapAnnotationVisualProjection] {
        guard let session else { return [] }
        return try MapVisualHostBridge.projectAcceptedPublicLayers(session, visibleLayers: Self.visibleLayers, theme: theme)
    }

    private func run(restart: Bool) async {
        guard MapLayerFeature.aggregatedQueryEnabled == false, let query = last, query.viewerID == accountID else {
            failure = MapLayerFeature.aggregatedQueryEnabled ? .rejected : .viewer
            return
        }
        let account = accountGeneration, ticket = queryGeneration, viewer = query.viewerID
        loading = true
        failure = nil
        do {
            let opened: MapPublicLayerSession
            if restart || session == nil {
                if let session {
                    opened = try MapPublicLayerAdapter.replace(session, viewerID: viewer, datum: MapPublicLayerAdapter.datum,
                        minLat: query.minLat, maxLat: query.maxLat, minLng: query.minLng, maxLng: query.maxLng,
                        layers: query.layers, limit: query.limit)
                } else {
                    opened = try MapPublicLayerAdapter.open(viewerID: viewer, datum: MapPublicLayerAdapter.datum,
                        minLat: query.minLat, maxLat: query.maxLat, minLng: query.minLng, maxLng: query.maxLng,
                        layers: query.layers, limit: query.limit)
                }
            } else if let existing = session {
                opened = existing
            } else {
                throw MapPublicAdapterFailure.payloadRejected
            }
            let issued = MapPublicLayerAdapter.request(opened)
            guard !issued.request.body.contains("aggregatedQueryEnabled") else { throw MapPublicAdapterFailure.payloadRejected }
            session = issued.session
            guard let area = Self.area(query) else { throw MapPublicAdapterFailure.bboxRejected }
            let payload = try await transport.post(area: area, body: Data(issued.request.body.utf8))
            guard accountGeneration == account, queryGeneration == ticket, accountID == viewer, let current = session else { loading = false; return }
            switch MapPublicLayerAdapter.accept(current, request: issued.request, json: payload) {
            case .applied(let applied):
                session = applied
                ready = MapPublicLayerAdapter.readyItems(in: applied)
                failure = nil
            case .stale:
                break
            case .rejected:
                failure = .rejected
            }
        } catch is CancellationError {
        } catch {
            guard accountGeneration == account, queryGeneration == ticket, accountID == viewer else { loading = false; return }
            failure = Self.failure(error)
        }
        if accountGeneration == account, queryGeneration == ticket { loading = false }
    }

    /// Center of the box the caller already typed. Not a device fix.
    private static func area(_ query: Query) -> RoamSearchArea? {
        guard let south = Double(query.minLat), let north = Double(query.maxLat),
              let west = Double(query.minLng), let east = Double(query.maxLng),
              let coordinate = RoamCoordinate(latitude: (south + north) / 2, longitude: (west + east) / 2) else { return nil }
        return RoamSearchArea(coordinate: coordinate, label: "")
    }

    private static func failure(_ error: Error) -> Failure {
        if error as? APIError == .unauthorized { return .unauthorized }
        if error as? APIError == .notConfigured { return .notConfigured }
        if error is MapPublicAdapterFailure { return .rejected }
        return .failed
    }
}

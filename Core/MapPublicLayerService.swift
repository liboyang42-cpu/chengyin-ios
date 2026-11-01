import Foundation
import Combine
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Independently reviewed, time-bounded signed-in read grant for `POST /api/map/public-layers`.
/// Never derived from login, device location permission, remote flags, or merchant roles.
public struct MapPublicLayerReadApproval: Equatable {
    public let context: RuntimeDependencyContext
    public let expiresAt: Date
    public let revision: UUID

    public init(context: RuntimeDependencyContext, expiresAt: Date, revision: UUID = UUID()) throws {
        guard context.market == .china,
              context.session.accountID > 0,
              !context.role.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              expiresAt > Date() else {
            throw APIError.invalidConfiguration
        }
        self.context = context
        self.expiresAt = expiresAt
        self.revision = revision
    }

    public func matches(_ current: RuntimeDependencyContext, now: Date = Date()) -> Bool {
        ContentDraftContextFence.matches(context, current) && now < expiresAt
    }
}

/// Canonical GCJ-02 bounding box validated against `MapPublicLayerAdapter` bounds and area cap.
/// Never reads device location or treats display camera coordinates as location authorization.
public struct MapPublicLayerBoundingBox: Equatable, Hashable {
    public let minLat: String
    public let maxLat: String
    public let minLng: String
    public let maxLng: String
    public let datum: WalkingCoordinateDatum

    public init(minLat: String, maxLat: String, minLng: String, maxLng: String, datum: WalkingCoordinateDatum = .gcj02) throws {
        guard datum == .gcj02 else { throw MapPublicAdapterFailure.datumRejected }
        let probe = try MapPublicLayerAdapter.open(
            viewerID: 1,
            datum: MapPublicLayerAdapter.datum,
            minLat: minLat,
            maxLat: maxLat,
            minLng: minLng,
            maxLng: maxLng,
            layers: ["store"],
            limit: 1
        )
        self.minLat = probe.minLat
        self.maxLat = probe.maxLat
        self.minLng = probe.minLng
        self.maxLng = probe.maxLng
        self.datum = .gcj02
    }

    /// Derives a bounded GCJ-02 box around a manually selected `RoamSearchArea` without device location.
    public static func aroundManualArea(
        _ area: RoamSearchArea,
        halfSpanDegrees: Decimal = Decimal(string: "0.02", locale: Locale(identifier: "en_US_POSIX"))!
    ) throws -> MapPublicLayerBoundingBox {
        guard halfSpanDegrees > 0, halfSpanDegrees <= Decimal(string: "0.4", locale: Locale(identifier: "en_US_POSIX"))! else {
            throw MapPublicAdapterFailure.areaRejected
        }
        let latText = String(format: "%.6f", area.coordinate.latitude)
        let lngText = String(format: "%.6f", area.coordinate.longitude)
        guard let centerLat = Decimal(string: latText, locale: Locale(identifier: "en_US_POSIX")),
              let centerLng = Decimal(string: lngText, locale: Locale(identifier: "en_US_POSIX")) else {
            throw MapPublicAdapterFailure.coordinateRejected
        }
        let south = max(Decimal(-90), centerLat - halfSpanDegrees)
        let north = min(Decimal(90), centerLat + halfSpanDegrees)
        let west = max(Decimal(-180), centerLng - halfSpanDegrees)
        let east = min(Decimal(180), centerLng + halfSpanDegrees)
        return try MapPublicLayerBoundingBox(
            minLat: NSDecimalNumber(decimal: south).stringValue,
            maxLat: NSDecimalNumber(decimal: north).stringValue,
            minLng: NSDecimalNumber(decimal: west).stringValue,
            maxLng: NSDecimalNumber(decimal: east).stringValue,
            datum: .gcj02
        )
    }

    /// Derives a GCJ-02 bounding box from an explicitly confirmed GCJ-02 map center and span.
    public static func fromConfirmedCenter(
        _ center: RuntimeLocationProjection.MapCenter,
        latitudeSpan: Double = 0.04,
        longitudeSpan: Double = 0.04
    ) throws -> MapPublicLayerBoundingBox {
        guard center.datum == .gcj02,
              latitudeSpan.isFinite, longitudeSpan.isFinite,
              latitudeSpan > 0, longitudeSpan > 0 else {
            throw MapPublicAdapterFailure.datumRejected
        }
        let halfLat = min(0.4, max(0.005, latitudeSpan / 2.0))
        let halfLng = min(0.4, max(0.005, longitudeSpan / 2.0))
        let south = max(-90.0, center.coordinate.latitude - halfLat)
        let north = min(90.0, center.coordinate.latitude + halfLat)
        let west = max(-180.0, center.coordinate.longitude - halfLng)
        let east = min(180.0, center.coordinate.longitude + halfLng)
        return try MapPublicLayerBoundingBox(
            minLat: String(format: "%.6f", south),
            maxLat: String(format: "%.6f", north),
            minLng: String(format: "%.6f", west),
            maxLng: String(format: "%.6f", east),
            datum: .gcj02
        )
    }
}

/// Distinguishes manual area selection from an explicitly confirmed GCJ-02 viewport.
public enum MapPublicLayerViewportSource: Equatable, Hashable {
    case manualArea(area: RoamSearchArea, boundingBox: MapPublicLayerBoundingBox)
    case authorizedViewport(boundingBox: MapPublicLayerBoundingBox, origin: RoamCoordinate?, label: String?)

    public var boundingBox: MapPublicLayerBoundingBox {
        switch self {
        case .manualArea(_, let box), .authorizedViewport(let box, _, _):
            return box
        }
    }

    public var originCoordinate: RoamCoordinate? {
        switch self {
        case .manualArea(let area, _):
            return area.coordinate
        case .authorizedViewport(_, let origin, _):
            return origin
        }
    }

    public var manualArea: RoamSearchArea? {
        if case .manualArea(let area, _) = self { return area }
        return nil
    }
}

/// Exact composition-root route recognizer for `POST /api/map/public-layers`.
public struct MapPublicLayerReadRoute: Equatable {
    public static let maximumResponseBytes = 1_048_576
    public let boundingBox: MapPublicLayerBoundingBox
    public let limit: Int
    public let layers: [String]
    public let cursor: String?

    private struct WireBody: Decodable {
        let datum: String
        let minLat: Decimal
        let maxLat: Decimal
        let minLng: Decimal
        let maxLng: Decimal
        let limit: Int
        let layers: [String]
        let cursor: String?
    }

    public init?(request: URLRequest, baseURL: URL) {
        guard request.httpMethod == "POST",
              request.httpBodyStream == nil,
              request.value(forHTTPHeaderField: "Cookie") == nil,
              request.value(forHTTPHeaderField: "Content-Type") == "application/json",
              let url = request.url,
              url.query == nil,
              url.fragment == nil,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.user == nil,
              parts.password == nil,
              parts.query == nil,
              parts.fragment == nil,
              url.absoluteString == baseURL.appendingPathComponent("api/map/public-layers").absoluteString,
              let body = request.httpBody,
              !body.isEmpty,
              body.count <= 4096,
              let decoded = try? JSONDecoder().decode(WireBody.self, from: body) else {
            return nil
        }
        let minLatText = NSDecimalNumber(decimal: decoded.minLat).stringValue
        let maxLatText = NSDecimalNumber(decimal: decoded.maxLat).stringValue
        let minLngText = NSDecimalNumber(decimal: decoded.minLng).stringValue
        let maxLngText = NSDecimalNumber(decimal: decoded.maxLng).stringValue
        guard var session = try? MapPublicLayerAdapter.open(
            viewerID: 1,
            datum: decoded.datum,
            minLat: minLatText,
            maxLat: maxLatText,
            minLng: minLngText,
            maxLng: maxLngText,
            layers: decoded.layers,
            limit: decoded.limit
        ),
        let box = try? MapPublicLayerBoundingBox(
            minLat: session.minLat,
            maxLat: session.maxLat,
            minLng: session.minLng,
            maxLng: session.maxLng
        ) else {
            return nil
        }
        if let cursor = decoded.cursor {
            guard !cursor.isEmpty, cursor.count <= 2048 else { return nil }
            session.cursor = cursor
        }
        let expected = MapPublicLayerAdapter.request(session).request
        guard Data(expected.body.utf8) == body else { return nil }
        self.boundingBox = box
        self.limit = decoded.limit
        self.layers = decoded.layers
        self.cursor = decoded.cursor
    }

    public func validateResponse(_ response: (Data, Int)) throws {
        guard response.0.count <= Self.maximumResponseBytes else {
            throw APIError.malformedResponse
        }
    }
}

@MainActor public protocol MapPublicLayerServing {
    func fetchPublicLayers(_ request: MapPublicLayerRequest, token: String) async throws -> Data
}

/// Formal HTTP service for `POST /api/map/public-layers`.
/// Never reads device location or enables `MapLayerFeature.aggregatedQueryEnabled`.
public struct MapPublicLayerService: MapPublicLayerServing {
    private let configuration: APIConfiguration
    private let transport: any HTTPTransport

    public init(configuration: APIConfiguration, transport: any HTTPTransport) {
        self.configuration = configuration
        self.transport = transport
    }

    public func fetchPublicLayers(_ layerRequest: MapPublicLayerRequest, token: String) async throws -> Data {
        guard AuthRequestBuilder.isValidToken(token) else { throw APIError.invalidRequest }
        var request = URLRequest(url: configuration.baseURL.appendingPathComponent("api/map/public-layers"))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: "Authorization")
        request.httpBody = Data(layerRequest.body.utf8)

        try Task.checkCancellation()
        let (data, status) = try await transport.send(request)
        try Task.checkCancellation()

        if status == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(status) else { throw APIError.httpStatus(status) }
        guard data.count <= MapPublicLayerReadRoute.maximumResponseBytes,
              let rawObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.malformedResponse
        }
        if let code = rawObject["code"] as? Int {
            if code == 401 { throw APIError.unauthorized }
            guard code == 200 else { throw APIError.businessCode(code) }
            guard let payloadObject = rawObject["data"] as? [String: Any],
                  JSONSerialization.isValidJSONObject(payloadObject),
                  let payloadData = try? JSONSerialization.data(withJSONObject: payloadObject) else {
                throw APIError.malformedResponse
            }
            return payloadData
        }
        guard rawObject["datum"] != nil, rawObject["layers"] != nil else {
            throw APIError.malformedResponse
        }
        return data
    }
}

/// Validated theme entity destination for `theme` (`MapSourceType.themeNode`).
/// `topicID` belongs to the `cms_topic` ID domain (`> 0`); `anchorNodeID` is the optional first coordinate node (`cms_topic_node.id > 0`).
public struct MapPublicThemeDestination: Equatable, Hashable {
    public let topicID: Int
    public let anchorNodeID: Int?
    public let themeName: String
    public let address: String?
    public let summary: String?

    public init?(topicID: Int, anchorNodeID: Int? = nil, themeName: String, address: String? = nil, summary: String? = nil) {
        let trimmed = themeName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard topicID > 0, !trimmed.isEmpty else { return nil }
        if let anchorNodeID, anchorNodeID <= 0 { return nil }
        self.topicID = topicID
        self.anchorNodeID = anchorNodeID
        self.themeName = trimmed
        self.address = address
        self.summary = summary
    }
}

/// Validated story-node destination for `story_node` (`MapSourceType.storyNode`).
/// `nodeID` (`cms_topic_node.id`), `topicID` (`cms_topic.id`), and `chapterID` (`cms_topic_chapter.id`) belong to separate ID domains.
/// Never falls back to `topicID = nodeID` or `activityID = nodeID`.
public struct MapPublicStoryNodeDestination: Equatable, Hashable {
    public let nodeID: Int
    public let topicID: Int
    public let chapterID: Int
    public let nodeName: String
    public let topicName: String?
    public let chapterTitle: String?
    public let address: String?
    public let summary: String?
    public let coordinate: RoamCoordinate?

    public init?(
        nodeID: Int,
        topicID: Int,
        chapterID: Int,
        nodeName: String,
        topicName: String? = nil,
        chapterTitle: String? = nil,
        address: String? = nil,
        summary: String? = nil,
        coordinate: RoamCoordinate? = nil
    ) {
        let trimmed = nodeName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard nodeID > 0, topicID > 0, chapterID > 0, !trimmed.isEmpty else { return nil }
        self.nodeID = nodeID
        self.topicID = topicID
        self.chapterID = chapterID
        self.nodeName = trimmed
        self.topicName = topicName?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.chapterTitle = chapterTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.address = address?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.summary = summary?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.coordinate = coordinate
    }
}

/// Real detail route for a validated `MapLayerItem`.
/// Routes `store`, `registrableActivity`, `roamPOI`, `themeNode` (`TopicDetailView`), and `storyNode` (`MapPublicStoryNodeDetailView`).
public struct MapPublicLayerDetailRoute: Identifiable, Equatable, Hashable {
    public enum Target: Equatable, Hashable {
        case store(sourceID: Int, title: String, coordinate: RoamCoordinate?, canNavigate: Bool)
        case activity(sourceID: Int, title: String)
        case roamPOI(sourceID: Int, title: String, origin: RoamCoordinate?)
        case theme(MapPublicThemeDestination)
        case storyNode(MapPublicStoryNodeDestination)
    }

    public let id: MapSourceKey
    public let target: Target
    public let viewerID: Int
    public let scope: UUID
    public let sessionFingerprint: String

    public init(id: MapSourceKey, target: Target, viewerID: Int, scope: UUID, sessionFingerprint: String) {
        self.id = id
        self.target = target
        self.viewerID = viewerID
        self.scope = scope
        self.sessionFingerprint = sessionFingerprint
    }
}

/// Runtime coordinator for `POST /api/map/public-layers` inside normal map entry flows.
/// Preserves query, viewport, per-layer status, retry cursor, and detail return state while
/// immediately purging state on account, epoch, or approval changes.
@MainActor public final class MapPublicLayerCoordinator: ObservableObject {
    private let service: (any MapPublicLayerServing)?
    private let currentContext: () -> SearchMapContext
    private let isApprovedSelector: () -> Bool
    private let onUnauthorized: (SearchMapContext) -> Void
    private let manualAreaSelection: ManualMapAreaSelection?
    private let taskOwner = ManualMapReadTaskOwner()

    @Published public private(set) var session: MapPublicLayerSession?
    @Published public private(set) var viewportSource: MapPublicLayerViewportSource?
    @Published public private(set) var selectedLayers: [String] = MapPublicLayerAdapter.knownSources
    @Published public private(set) var pageLimit: Int = 20
    @Published public private(set) var isLoading: Bool = false
    @Published public private(set) var transportFailed: Bool = false
    @Published public private(set) var errorKey: String?
    @Published public private(set) var selectedItemKey: MapSourceKey?
    @Published public private(set) var activeDetailRoute: MapPublicLayerDetailRoute?
    @Published public private(set) var returnScrollAnchorID: String?
    private var capturedContext: SearchMapContext?
    private var activeScope = UUID()

    public init(
        service: (any MapPublicLayerServing)?,
        currentContext: @escaping () -> SearchMapContext,
        isApproved: @escaping () -> Bool = { false },
        onUnauthorized: @escaping (SearchMapContext) -> Void = { _ in },
        manualAreaSelection: ManualMapAreaSelection? = nil
    ) {
        self.service = service
        self.currentContext = currentContext
        self.isApprovedSelector = isApproved
        self.onUnauthorized = onUnauthorized
        self.manualAreaSelection = manualAreaSelection
        self.capturedContext = currentContext()
    }

    public var isConfigured: Bool {
        service != nil && isApprovedSelector()
    }

    public var isAuthenticated: Bool {
        guard let accountID = currentContext().accountID else { return false }
        return accountID > 0 && currentContext().token != nil
    }

    public var scope: UUID {
        synchronizeContext()
        return activeScope
    }

    public var pages: [MapPublicLayerPage] {
        guard let session else { return [] }
        return session.pages
    }

    public var readyItems: [MapLayerItem] {
        guard let session else { return [] }
        return MapPublicLayerAdapter.readyItems(in: session)
    }

    public var visibleReadyItems: [MapLayerItem] {
        let enabledTypes = Set(selectedLayers.compactMap { MapPublicLayerAdapter.clientType(wire: $0) })
        return MapLayerMerge.visible(readyItems, layers: enabledTypes)
    }

    public var withheldItems: [MapPublicWithheldItem] {
        guard let session else { return [] }
        return MapPublicLayerAdapter.withheld(in: session)
    }

    public var hasFailedLayer: Bool {
        transportFailed || pages.contains(where: { $0.status == .failed })
    }

    public var canLoadNextPage: Bool {
        guard let session else { return false }
        return isConfigured && isAuthenticated && !isLoading && !hasFailedLayer && !session.complete && session.cursor != nil
    }

    public var canRetry: Bool {
        guard session != nil else { return false }
        return isConfigured && isAuthenticated && !isLoading && hasFailedLayer
    }

    public var isComplete: Bool {
        guard let session else { return false }
        return session.complete && !hasFailedLayer
    }

    /// Synchronizes with the current signed-in viewer and approval gate.
    /// Any account, role, epoch, or approval loss immediately purges state and retires in-flight reads.
    @discardableResult
    public func synchronizeContext() -> Bool {
        let latest = currentContext()
        let approved = service != nil && isApprovedSelector()
        if capturedContext != latest {
            capturedContext = latest
            activeScope = UUID()
            purgeAllState()
            return false
        }
        if !approved && (session != nil || isLoading || selectedItemKey != nil || activeDetailRoute != nil) {
            purgeAllState()
            return false
        }
        return approved && latest.accountID != nil && latest.token != nil
    }

    public func purgeAllState() {
        taskOwner.cancel()
        session = nil
        viewportSource = nil
        isLoading = false
        transportFailed = false
        errorKey = nil
        selectedItemKey = nil
        activeDetailRoute = nil
        returnScrollAnchorID = nil
    }

    /// Updates the requested public layer sources (1...5 from `MapPublicLayerAdapter.knownSources` in caller order).
    /// If a viewport/manual area is already loaded, replaces the session (retiring any in-flight read) and reloads.
    public func setLayers(_ layers: [String]) throws {
        synchronizeContext()
        guard MapPublicLayerAdapter.layerCount.contains(layers.count) else {
            throw MapPublicAdapterFailure.layersRejected
        }
        var seen: Set<String> = []
        for layer in layers {
            guard MapPublicLayerAdapter.knownSources.contains(layer), seen.insert(layer).inserted else {
                throw MapPublicAdapterFailure.layersRejected
            }
        }
        guard selectedLayers != layers else { return }
        selectedLayers = layers
        let enabledTypes = Set(layers.compactMap { MapPublicLayerAdapter.clientType(wire: $0) })
        if let selectedItemKey, !enabledTypes.contains(selectedItemKey.type) {
            self.selectedItemKey = nil
            self.activeDetailRoute = nil
            self.returnScrollAnchorID = nil
        }
        if let currentViewport = viewportSource {
            try openOrReplaceSession(viewport: currentViewport, layers: layers, limit: pageLimit)
            startCurrentSessionRequest()
        }
    }

    public func toggleLayer(_ source: String) {
        synchronizeContext()
        guard MapPublicLayerAdapter.knownSources.contains(source) else { return }
        var next = selectedLayers
        if let index = next.firstIndex(of: source) {
            guard next.count > 1 else { return }
            next.remove(at: index)
        } else {
            next = MapPublicLayerAdapter.knownSources.filter { $0 == source || next.contains($0) }
        }
        try? setLayers(next)
    }

    /// Loads public layers for a manually selected `RoamSearchArea` (works without device location permission).
    public func loadManualArea(_ area: RoamSearchArea, layers: [String]? = nil, limit: Int? = nil) {
        synchronizeContext()
        manualAreaSelection?.ensureSelected(area)
        do {
            let box = try MapPublicLayerBoundingBox.aroundManualArea(area)
            let source = MapPublicLayerViewportSource.manualArea(area: area, boundingBox: box)
            try beginViewportLoad(source, layers: layers, limit: limit)
        } catch {
            errorKey = "mapPublicLayers.invalidViewport"
        }
    }

    /// Loads public layers for an explicitly confirmed GCJ-02 viewport.
    public func loadAuthorizedViewport(
        _ boundingBox: MapPublicLayerBoundingBox,
        origin: RoamCoordinate? = nil,
        label: String? = nil,
        layers: [String]? = nil,
        limit: Int? = nil
    ) {
        synchronizeContext()
        do {
            let source = MapPublicLayerViewportSource.authorizedViewport(boundingBox: boundingBox, origin: origin, label: label)
            try beginViewportLoad(source, layers: layers, limit: limit)
        } catch {
            errorKey = "mapPublicLayers.invalidViewport"
        }
    }

    private func beginViewportLoad(_ source: MapPublicLayerViewportSource, layers: [String]?, limit: Int?) throws {
        let nextLayers = layers ?? selectedLayers
        let nextLimit = limit ?? pageLimit
        guard let accountID = currentContext().accountID, accountID > 0, currentContext().token != nil else {
            purgeAllState()
            viewportSource = source
            errorKey = "mapPublicLayers.signInRequired"
            return
        }
        guard isConfigured else {
            purgeAllState()
            viewportSource = source
            errorKey = "mapPublicLayers.notConfigured"
            return
        }
        try openOrReplaceSession(viewport: source, layers: nextLayers, limit: nextLimit)
        startCurrentSessionRequest()
    }

    private func openOrReplaceSession(viewport: MapPublicLayerViewportSource, layers: [String], limit: Int) throws {
        guard let accountID = currentContext().accountID, accountID > 0 else {
            throw MapPublicAdapterFailure.viewerRejected
        }
        let box = viewport.boundingBox
        let nextSession: MapPublicLayerSession
        if let existing = session {
            nextSession = try MapPublicLayerAdapter.replace(
                existing,
                viewerID: accountID,
                datum: MapPublicLayerAdapter.datum,
                minLat: box.minLat,
                maxLat: box.maxLat,
                minLng: box.minLng,
                maxLng: box.maxLng,
                layers: layers,
                limit: limit
            )
        } else {
            nextSession = try MapPublicLayerAdapter.open(
                viewerID: accountID,
                datum: MapPublicLayerAdapter.datum,
                minLat: box.minLat,
                maxLat: box.maxLat,
                minLng: box.minLng,
                maxLng: box.maxLng,
                layers: layers,
                limit: limit
            )
        }
        taskOwner.cancel()
        selectedLayers = layers
        pageLimit = limit
        viewportSource = viewport
        session = nextSession
        isLoading = false
        transportFailed = false
        errorKey = nil
        selectedItemKey = nil
        activeDetailRoute = nil
        returnScrollAnchorID = nil
    }

    /// Requests the next page using the server-supplied `nextCursor`.
    public func loadNextPage() {
        synchronizeContext()
        guard canLoadNextPage else { return }
        startCurrentSessionRequest()
    }

    /// Retries a failed page using the exact same cursor without wiping other layers' successful items.
    public func retryFailedPage() {
        synchronizeContext()
        guard canRetry else { return }
        startCurrentSessionRequest()
    }

    private func startCurrentSessionRequest() {
        guard let currentSession = session,
              let service,
              isConfigured,
              let accountID = currentContext().accountID,
              accountID == currentSession.viewerID,
              let token = currentContext().token else {
            isLoading = false
            errorKey = isAuthenticated ? "mapPublicLayers.notConfigured" : "mapPublicLayers.signInRequired"
            return
        }
        if let area = viewportSource?.manualArea {
            manualAreaSelection?.ensureSelected(area)
        }
        let (advancedSession, issuedRequest) = MapPublicLayerAdapter.request(currentSession)
        session = advancedSession
        isLoading = true
        transportFailed = false
        errorKey = nil
        let captured = currentContext()
        let capturedScope = activeScope
        let capturedAreaRevision = manualAreaSelection?.revision ?? 0

        taskOwner.start { [weak self] in
            await self?.performRequest(
                issuedRequest,
                service: service,
                token: token,
                capturedContext: captured,
                capturedScope: capturedScope,
                capturedAreaRevision: capturedAreaRevision
            )
        }
    }

    private func performRequest(
        _ issuedRequest: MapPublicLayerRequest,
        service: any MapPublicLayerServing,
        token: String,
        capturedContext: SearchMapContext,
        capturedScope: UUID,
        capturedAreaRevision: UInt64
    ) async {
        do {
            let rawData = try await service.fetchPublicLayers(issuedRequest, token: token)
            guard !Task.isCancelled else { return }
            guard currentContext() == capturedContext,
                  activeScope == capturedScope,
                  isConfigured,
                  (manualAreaSelection?.revision ?? 0) == capturedAreaRevision,
                  let activeSession = session else {
                _ = synchronizeContext()
                return
            }
            let outcome = MapPublicLayerAdapter.accept(activeSession, request: issuedRequest, json: rawData)
            switch outcome {
            case .applied(let updated):
                session = updated
                isLoading = false
                transportFailed = false
                errorKey = nil
                let currentReadyKeys = Set(MapPublicLayerAdapter.readyItems(in: updated).map(\.key))
                if let selectedItemKey, !currentReadyKeys.contains(selectedItemKey) {
                    self.selectedItemKey = nil
                    self.activeDetailRoute = nil
                    self.returnScrollAnchorID = nil
                }
            case .stale:
                break
            case .rejected:
                guard activeSession.token == issuedRequest.attempt,
                      activeSession.fingerprint == issuedRequest.fingerprint else { return }
                isLoading = false
                transportFailed = true
                errorKey = "mapPublicLayers.payloadRejected"
            }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled,
                  currentContext() == capturedContext,
                  activeScope == capturedScope,
                  (manualAreaSelection?.revision ?? 0) == capturedAreaRevision,
                  let activeSession = session,
                  activeSession.token == issuedRequest.attempt,
                  activeSession.fingerprint == issuedRequest.fingerprint else {
                _ = synchronizeContext()
                return
            }
            if error as? APIError == .unauthorized {
                onUnauthorized(capturedContext)
                purgeAllState()
                errorKey = "mapPublicLayers.signInRequired"
                return
            }
            isLoading = false
            transportFailed = true
            errorKey = Self.issueKey(for: error)
        }
    }

    private static func issueKey(for error: Error) -> String {
        switch error as? APIError {
        case .unauthorized: return "searchMap.unauthorized"
        case .notConfigured, .invalidConfiguration: return "searchMap.notConfigured"
        case .invalidRequest: return "searchMap.invalidInput"
        default: return "searchMap.failed"
        }
    }

    /// Returns the authoritative wire item for a ready `MapSourceKey` so parent theme/chapter metadata can be inspected without guessing IDs.
    public func wireItem(for key: MapSourceKey) -> MapPublicWireItem? {
        guard let currentSession = session,
              let sourceID = Int(key.id),
              sourceID > 0 else { return nil }
        for page in currentSession.pages where page.status == .ok || page.status == .failed {
            guard MapPublicLayerAdapter.clientType(wire: page.source) == key.type else { continue }
            if let match = page.items.first(where: { $0.sourceID == sourceID }) {
                return match
            }
        }
        return nil
    }

    /// Selects or clears an item from the active ready items without resetting the query or viewport.
    public func selectItem(_ key: MapSourceKey?) {
        synchronizeContext()
        guard let key else {
            selectedItemKey = nil
            return
        }
        guard visibleReadyItems.contains(where: { $0.key == key }) else { return }
        selectedItemKey = key
        returnScrollAnchorID = Self.scrollAnchorID(for: key)
    }

    /// Validates and opens the real detail route for a ready item (`store`, `registrableActivity`, `roamPOI`, `themeNode`, `storyNode`).
    /// Never routes unsupported types (`sideQuest`, `cityBoardPoint`), never routes `themeNode`/`storyNode` to `ActivityDetailView`,
    /// and never guesses `topicID = sourceID` for `storyNode`.
    @discardableResult
    public func openDetail(for key: MapSourceKey) -> MapPublicLayerDetailRoute? {
        guard synchronizeContext(),
              let currentSession = session,
              let item = visibleReadyItems.first(where: { $0.key == key }),
              let sourceID = Int(item.key.id),
              sourceID > 0 else {
            return nil
        }
        let coordinate = RoamCoordinate(latitude: item.coordinate.latitude, longitude: item.coordinate.longitude)
        let wire = wireItem(for: item.key)
        let target: MapPublicLayerDetailRoute.Target
        switch item.key.type {
        case .store:
            let canNavigate = item.capabilities.contains(.navigate) && !item.capabilities.contains(.register)
            target = .store(sourceID: sourceID, title: item.title, coordinate: coordinate, canNavigate: canNavigate)
        case .registrableActivity:
            target = .activity(sourceID: sourceID, title: item.title)
        case .roamPOI:
            target = .roamPOI(sourceID: sourceID, title: item.title, origin: viewportSource?.originCoordinate)
        case .themeNode:
            if let explicitTopicID = wire?.topicID, explicitTopicID != sourceID { return nil }
            guard let destination = MapPublicThemeDestination(
                topicID: sourceID,
                anchorNodeID: wire?.nodeID,
                themeName: item.title,
                address: wire?.address,
                summary: wire?.summary
            ) else { return nil }
            target = .theme(destination)
        case .storyNode:
            guard let wire,
                  wire.source == "story_node",
                  wire.sourceID == sourceID,
                  let topicID = wire.topicID,
                  let chapterID = wire.chapterID,
                  let destination = MapPublicStoryNodeDestination(
                      nodeID: sourceID,
                      topicID: topicID,
                      chapterID: chapterID,
                      nodeName: item.title,
                      topicName: wire.topicName,
                      chapterTitle: wire.chapterTitle,
                      address: wire.address,
                      summary: wire.summary,
                      coordinate: coordinate
                  ) else { return nil }
            target = .storyNode(destination)
        case .sideQuest, .cityBoardPoint:
            return nil
        }
        let route = MapPublicLayerDetailRoute(
            id: item.key,
            target: target,
            viewerID: currentSession.viewerID,
            scope: activeScope,
            sessionFingerprint: currentSession.fingerprint
        )
        selectedItemKey = item.key
        returnScrollAnchorID = Self.scrollAnchorID(for: item.key)
        activeDetailRoute = route
        return route
    }

    /// Verifies whether a pushed detail route is still valid for the current viewer and query session.
    public func acceptsDetailRoute(_ route: MapPublicLayerDetailRoute) -> Bool {
        guard synchronizeContext(),
              let currentSession = session,
              currentSession.viewerID == route.viewerID,
              activeScope == route.scope,
              currentSession.fingerprint == route.sessionFingerprint else {
            return false
        }
        return visibleReadyItems.contains(where: { $0.key == route.id })
    }

    /// Returns from detail while preserving the active query, viewport, loaded pages, cursor, and selection.
    public func returnFromDetail() {
        guard synchronizeContext() else { return }
        activeDetailRoute = nil
    }

    public static func pinID(for key: MapSourceKey) -> String {
        "public-\(key.type.rawValue)-\(key.id)"
    }

    public static func parsePinID(_ pinID: String) -> MapSourceKey? {
        let prefix = "public-"
        guard pinID.hasPrefix(prefix) else { return nil }
        let remainder = String(pinID.dropFirst(prefix.count))
        guard let separator = remainder.firstIndex(of: "-") else { return nil }
        let rawType = String(remainder[..<separator])
        let rawID = String(remainder[remainder.index(after: separator)...])
        guard let type = MapSourceType(rawValue: rawType) else { return nil }
        return try? MapSourceKey(type: type, id: rawID)
    }

    public static func scrollAnchorID(for key: MapSourceKey) -> String {
        "public-layer-item-\(key.type.rawValue)-\(key.id)"
    }
}

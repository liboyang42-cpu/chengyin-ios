import Foundation

/// Reform plan v9 §20 / W13.1–W13.4. Client contract only: no aggregated layer endpoint exists
/// or is allowlisted. Existing readers (search map, roam, city nodes) keep their own routes.
public enum MapLayerFeature {
    /// Stays false until a reviewed QueryMapLayers backend contract and endpoint approval exist.
    public static let aggregatedQueryEnabled = false
}

/// Typed source identity. Numeric IDs from different sources are never the same object.
public enum MapSourceType: String, CaseIterable, Codable {
    case themeNode, roamPOI, store, registrableActivity, sideQuest, cityBoardPoint
}

public struct MapSourceKey: Hashable, Codable, Comparable {
    public let type: MapSourceType
    public let id: String
    public init(type: MapSourceType, id: String) throws {
        guard !id.isEmpty, id.count <= 64, id.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || [45, 95].contains($0) }) else {
            throw MapLayerContractFailure.invalidIdentity
        }
        self.type = type; self.id = id
    }
    public static func < (lhs: Self, rhs: Self) -> Bool { (lhs.type.rawValue, lhs.id) < (rhs.type.rawValue, rhs.id) }
}

/// What the server says the caller may do. The client never upgrades a capability locally.
public enum MapItemCapability: String, CaseIterable, Codable {
    case viewDetail, navigate, accept, review, register
}

public struct MapLayerItem: Equatable {
    public let key: MapSourceKey
    /// Stable canonical place (W13.4). Optional: an item without one is never grouped with others.
    public let placeID: String?
    public let visibilityVersion: Int
    public let state: MapMarkerVisualState
    public let coordinate: MapCoordinateObservation
    public let capabilities: Set<MapItemCapability>
    public let sortKey: String
    public let title: String
    public init(key: MapSourceKey, placeID: String?, visibilityVersion: Int, state: MapMarkerVisualState,
                coordinate: MapCoordinateObservation, capabilities: Set<MapItemCapability>, sortKey: String, title: String) throws {
        guard visibilityVersion >= 0, !sortKey.isEmpty, sortKey.count <= 128,
              !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 300,
              placeID.map({ !$0.isEmpty && $0.count <= 64 }) ?? true else { throw MapLayerContractFailure.invalidItem }
        // Locked/unavailable/in-review items cannot advertise primary actions (MV05).
        if !state.allowsPrimaryAction, !capabilities.isDisjoint(with: [.accept, .register]) { throw MapLayerContractFailure.invalidItem }
        self.key = key; self.placeID = placeID; self.visibilityVersion = visibilityVersion; self.state = state
        self.coordinate = coordinate; self.capabilities = capabilities; self.sortKey = sortKey; self.title = title
    }
}

public enum MapLayerContractFailure: Error, Equatable {
    case invalidIdentity, invalidItem, invalidQuery, cursorMismatch, featureDisabled
}

public enum MapLayerMerge {
    /// Same key: keep the highest visibility version (a newer read wins; an older page cannot resurrect).
    /// Different keys are always kept, even with equal numeric IDs or equal coordinates.
    /// Output is ordered by the server's stable sort key, then key, so pages never reorder silently.
    public static func merge(_ existing: [MapLayerItem], _ incoming: [MapLayerItem]) -> [MapLayerItem] {
        var byKey: [MapSourceKey: MapLayerItem] = [:]
        for item in existing + incoming {
            if let current = byKey[item.key], current.visibilityVersion > item.visibilityVersion { continue }
            byKey[item.key] = item
        }
        return byKey.values.sorted { ($0.sortKey, $0.key) < ($1.sortKey, $1.key) }
    }
    /// Groups items that the server bound to the same canonical place, for one place card.
    /// Name or coordinate similarity never groups (MV04 "同名/相近坐标").
    public static func placeGroups(_ items: [MapLayerItem]) -> [[MapLayerItem]] {
        var groups: [String: [MapLayerItem]] = [:]; var singles: [[MapLayerItem]] = []
        for item in items {
            if let place = item.placeID { groups[place, default: []].append(item) } else { singles.append([item]) }
        }
        return (groups.keys.sorted().map { groups[$0]! } + singles)
    }
    /// Removing a visible layer also removes its items from selection and counts (MV06).
    public static func visible(_ items: [MapLayerItem], layers: Set<MapSourceType>) -> [MapLayerItem] {
        items.filter { layers.contains($0.key.type) }
    }
}

/// W13.2 proposed QueryMapLayers request. Limits are client guards, not the server policy.
public struct MapLayerQuery: Equatable {
    public struct Viewport: Equatable {
        public let south: Double, west: Double, north: Double, east: Double
        public init(south: Double, west: Double, north: Double, east: Double) throws {
            guard [south, west, north, east].allSatisfy(\.isFinite), (-90...90).contains(south), (-90...90).contains(north),
                  (-180...180).contains(west), (-180...180).contains(east), north > south, east > west else { throw MapLayerContractFailure.invalidQuery }
            self.south = south; self.west = west; self.north = north; self.east = east
        }
    }
    public static let maxLayers = MapSourceType.allCases.count
    public static let maxSpanDegrees = 0.5
    public static let limitRange = 1...200
    public let viewport: Viewport
    public let datum: WalkingCoordinateDatum
    public let zoom: Int
    public let layers: [MapSourceType]
    public let limit: Int
    public let cursor: String?
    public init(viewport: Viewport, datum: WalkingCoordinateDatum, zoom: Int, layers: Set<MapSourceType>, limit: Int, cursor: String? = nil) throws {
        guard !layers.isEmpty, layers.count <= Self.maxLayers, (0...22).contains(zoom), Self.limitRange.contains(limit),
              viewport.north - viewport.south <= Self.maxSpanDegrees, viewport.east - viewport.west <= Self.maxSpanDegrees,
              cursor.map({ !$0.isEmpty && $0.count <= 512 }) ?? true else { throw MapLayerContractFailure.invalidQuery }
        self.viewport = viewport; self.datum = datum; self.zoom = zoom
        self.layers = layers.sorted { $0.rawValue < $1.rawValue }; self.limit = limit; self.cursor = cursor
    }
    /// Canonical parameters that a cursor is bound to. Changing any of them invalidates the cursor.
    public var parameterFingerprint: String {
        let v = viewport
        return [String(format: "%.6f,%.6f,%.6f,%.6f", v.south, v.west, v.north, v.east), datum.rawValue,
                String(zoom), layers.map(\.rawValue).joined(separator: "+"), String(limit)].joined(separator: "|")
    }
    /// Continue from a page only with identical parameters; otherwise restart without a cursor.
    public func next(cursor: String, issuedFor fingerprint: String) throws -> MapLayerQuery {
        guard fingerprint == parameterFingerprint else { throw MapLayerContractFailure.cursorMismatch }
        return try MapLayerQuery(viewport: viewport, datum: datum, zoom: zoom, layers: Set(layers), limit: limit, cursor: cursor)
    }
}

/// W15.2 structured entrance. Unreviewed or source-less entries are not displayed as fact.
public struct PlaceNavigationEntrance: Equatable {
    public let label: String
    public let floor: String?
    public let approachNote: String?
    public let coordinate: MapCoordinateObservation
    public let source: String
    public let reviewedBy: String?
    public let updatedAt: Date
    public let temporarilyClosed: Bool
    public let accessibleAlternative: String?
    public init(label: String, floor: String?, approachNote: String?, coordinate: MapCoordinateObservation, source: String,
                reviewedBy: String?, updatedAt: Date, temporarilyClosed: Bool, accessibleAlternative: String?) {
        self.label = label; self.floor = floor; self.approachNote = approachNote; self.coordinate = coordinate
        self.source = source; self.reviewedBy = reviewedBy; self.updatedAt = updatedAt
        self.temporarilyClosed = temporarilyClosed; self.accessibleAlternative = accessibleAlternative
    }
    public var isDisplayable: Bool {
        !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !source.isEmpty && !(reviewedBy ?? "").isEmpty
    }
    /// Closed entrances are shown with their alternative but are never navigation destinations.
    public var isNavigable: Bool { isDisplayable && !temporarilyClosed }
}

/// §20 "map as the core entry": what the map hosts and where each entry stands on iOS today.
public enum MapCoreEntry: String, CaseIterable {
    case cityOrienteering, freeExploration, merchantSideQuests, placeInfo, personalFog, sharedLocation, cityOperation
    public enum Availability: Equatable {
        /// An existing native screen serves this entry.
        case existing
        /// Client contract present; disabled until the named backend capability is reviewed.
        case pendingBackend
        /// Waiting on a product/safety decision recorded in the plan.
        case pendingDecision
    }
    public var availability: Availability {
        switch self {
        case .cityOrienteering, .freeExploration, .placeInfo: .existing
        case .merchantSideQuests, .personalFog: .pendingBackend
        case .sharedLocation, .cityOperation: .pendingDecision
        }
    }
    public var symbolName: String {
        switch self {
        case .cityOrienteering: "flag.checkered"
        case .freeExploration: "binoculars"
        case .merchantSideQuests: "storefront"
        case .placeInfo: "info.circle"
        case .personalFog: "cloud.fog"
        case .sharedLocation: "location.circle"
        case .cityOperation: "building.2"
        }
    }
    /// Precise sharing is always off by default, independent of OS location permission (W13.5).
    public static let preciseSharingDefaultEnabled = false
}

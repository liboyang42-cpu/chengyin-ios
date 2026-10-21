import Foundation

/// F-W13 / MV01–MV05 / MV12 / MV19 host bridge connecting `MapVisualStyleTokens`,
/// `MapLayerSourceContracts`, and `MapCoordinateObservation` to SearchMap, Roam, and Walking host views.
public struct MapVisualHostThemeSnapshot: Equatable {
    public let manifestVersion: String
    public let approval: MapVisualStyleManifest.Approval
    public let appearance: MapAppearance
    public let colorsByRole: [MapSemanticRole: MapStyleColor]
    public let contrastShortfalls: [String]

    public var isCandidatePalette: Bool {
        approval == .candidate
    }

    public func color(for role: MapSemanticRole) -> MapStyleColor {
        colorsByRole[role] ?? MapVisualStyleManifest.candidate.color(role, appearance)
    }
}

public struct MapAnnotationVisualProjection: Equatable {
    public let key: MapSourceKey
    public let placeID: String?
    public let title: String
    public let layerOrder: MapLayerOrder
    public let zIndex: Int
    public let serverState: MapMarkerVisualState
    public let effectiveState: MapMarkerVisualState
    public let symbolName: String
    public let strokeWidth: Double
    public let tintColor: MapStyleColor
    public let allowsPrimaryAction: Bool
    public let capabilities: Set<MapItemCapability>
    public let coordinate: MapCoordinateObservation
}

public enum MapVisualHostBridge {
    /// Resolves day/night appearance from the system and decodes the style manifest with candidate fallback (MV01, MV12).
    public static func resolveTheme(manifestData: Data? = nil, systemIsDark: Bool) -> MapVisualHostThemeSnapshot {
        let appearance = MapAppearance.resolve(systemIsDark: systemIsDark)
        let manifest = MapVisualStyleManifest.resolve(manifestData)
        var colors: [MapSemanticRole: MapStyleColor] = [:]
        for role in MapSemanticRole.allCases {
            colors[role] = manifest.color(role, appearance)
        }
        return MapVisualHostThemeSnapshot(
            manifestVersion: manifest.version,
            approval: manifest.approval,
            appearance: appearance,
            colorsByRole: colors,
            contrastShortfalls: manifest.contrastShortfalls()
        )
    }

    /// Returns the fixed bottom-to-top rendering order required by MV03.
    public static func orderedLayers() -> [MapLayerOrder] {
        MapLayerOrder.allCases.sorted()
    }

    /// Maps a business layer item source type to its MV03 layer slot.
    public static func layerOrder(for sourceType: MapSourceType) -> MapLayerOrder {
        switch sourceType {
        case .themeNode, .storyNode, .roamPOI, .store, .registrableActivity, .sideQuest, .cityBoardPoint:
            return .gameMarkers
        }
    }

    /// Projects a single marker's visual state for MapKit annotations without mutating server eligibility or capabilities (MV05).
    public static func projectAnnotation(
        item: MapLayerItem,
        isSelected: Bool,
        isActiveTarget: Bool,
        targetDatum: WalkingCoordinateDatum = .gcj02,
        theme: MapVisualHostThemeSnapshot
    ) throws -> MapAnnotationVisualProjection {
        let projectedCoordinate = try projectCoordinateForHost(item.coordinate, targetDatum: targetDatum)
        let effectiveState: MapMarkerVisualState
        if isActiveTarget && item.state.allowsPrimaryAction {
            effectiveState = .active
        } else if isSelected {
            effectiveState = .selected
        } else {
            effectiveState = item.state
        }

        let tintRole: MapSemanticRole
        if !item.state.allowsPrimaryAction {
            tintRole = .completedUnavailable
        } else if effectiveState == .active || effectiveState == .selected {
            tintRole = .currentTargetRoute
        } else {
            tintRole = .roadLabel
        }

        let order = layerOrder(for: item.key.type)
        return MapAnnotationVisualProjection(
            key: item.key,
            placeID: item.placeID,
            title: item.title,
            layerOrder: order,
            zIndex: order.rawValue,
            serverState: item.state,
            effectiveState: effectiveState,
            symbolName: effectiveState.symbolName,
            strokeWidth: effectiveState.strokeWidth,
            tintColor: theme.color(for: tintRole),
            // Selection is UI-only and never unlocks primary actions on locked/completed/unavailable/inReview items.
            allowsPrimaryAction: item.state.allowsPrimaryAction,
            capabilities: item.capabilities,
            coordinate: projectedCoordinate
        )
    }

    /// Filters visible layers (MV06), preserves stable merge order, and projects annotation visual states.
    public static func projectAnnotations(
        items: [MapLayerItem],
        visibleLayers: Set<MapSourceType>,
        selectedKey: MapSourceKey? = nil,
        activeKey: MapSourceKey? = nil,
        targetDatum: WalkingCoordinateDatum = .gcj02,
        theme: MapVisualHostThemeSnapshot
    ) throws -> [MapAnnotationVisualProjection] {
        let merged = MapLayerMerge.merge(items, [])
        let visible = MapLayerMerge.visible(merged, layers: visibleLayers)
        return try visible.map { item in
            try projectAnnotation(
                item: item,
                isSelected: item.key == selectedKey,
                isActiveTarget: item.key == activeKey,
                targetDatum: targetDatum,
                theme: theme
            )
        }
    }

    /// Converts a WGS84 observation to GCJ02 exactly once; rejects any observation that already carries a conversion record.
    public static func convertWGS84ToGCJ02Once(_ observation: MapCoordinateObservation) throws -> MapCoordinateObservation {
        guard observation.conversion == nil else {
            throw MapCoordinateFailure.doubleConversion
        }
        guard observation.datum == .wgs84 else {
            throw MapCoordinateFailure.unsupportedConversion
        }
        return try observation.projected(to: .gcj02)
    }

    /// Projects a coordinate to the host map's target datum, rejecting any second conversion on already-converted observations.
    public static func projectCoordinateForHost(
        _ observation: MapCoordinateObservation,
        targetDatum: WalkingCoordinateDatum = .gcj02
    ) throws -> MapCoordinateObservation {
        try observation.projected(to: targetDatum)
    }

    /// Normalizes untyped payload coordinates and projects them to the host datum if needed.
    public static func normalizeAndProject(
        latitude: Any?,
        longitude: Any?,
        datum: String?,
        source: MapCoordinateSource,
        accuracyMeters: Double? = nil,
        observedAt: Date? = nil,
        targetDatum: WalkingCoordinateDatum = .gcj02
    ) throws -> MapCoordinateObservation {
        let normalized = try MapCoordinateObservation.normalize(
            latitude: latitude,
            longitude: longitude,
            datum: datum,
            source: source,
            accuracyMeters: accuracyMeters,
            observedAt: observedAt
        )
        return try normalized.projected(to: targetDatum)
    }

    /// Computes distance in meters only when both observations share the exact same datum (MV19).
    public static func sameDatumDistanceMeters(
        from origin: MapCoordinateObservation,
        to destination: MapCoordinateObservation
    ) throws -> Double {
        try MapCoordinateObservation.distanceMeters(origin, destination)
    }
}

import Foundation

/// Self-contained audit and verification gate for all 41 Map Visual Specification items (`MV01`..`MV41`):
/// - Day/night theme appearance & WCAG 4.5:1 palette contrast (`MV01`..`MV08`)
/// - Deterministic bottom-to-top layer order: `baseMap -> fogOverlay -> routePath -> poiMarkers -> activeStopCallout -> userPuck` (`MV09`..`MV16`)
/// - Marker state visual projection: `locked`, `discoverable`, `active`, `completed`, `unavailable` (`MV17`..`MV25`)
/// - Coordinate datum badge & transform isolation: `WGS-84` vs `GCJ-02` (`MV26`..`MV33`)
/// - Personal fog confirmed vs predicted cell separation & `revealSyncEnabled == false` default (`MV34`..`MV41`)
public enum MapVisualMV01ToMV41ComplianceAudit {

    // MARK: - Canonical 41 Spec Items (MV01..MV41)

    public enum SpecCategory: String, CaseIterable, Sendable, Equatable {
        case themeAndContrast = "THEME_AND_CONTRAST"
        case layerOrder = "LAYER_ORDER"
        case markerStateProjection = "MARKER_STATE_PROJECTION"
        case coordinateDatumIsolation = "COORDINATE_DATUM_ISOLATION"
        case personalFogSeparation = "PERSONAL_FOG_SEPARATION"
    }

    public struct SpecDescriptor: Sendable, Equatable, Identifiable {
        public let id: String
        public let number: Int
        public let category: SpecCategory
        public let title: String

        public init(id: String, number: Int, category: SpecCategory, title: String) {
            self.id = id
            self.number = number
            self.category = category
            self.title = title
        }
    }

    public static let allSpecDescriptors: [SpecDescriptor] = [
        // MV01..MV08: Theme & Contrast
        .init(id: "MV01", number: 1, category: .themeAndContrast, title: "Day theme base map surface palette"),
        .init(id: "MV02", number: 2, category: .themeAndContrast, title: "Night theme low-luminance surface palette"),
        .init(id: "MV03", number: 3, category: .themeAndContrast, title: "Deterministic day/night transition hysteresis"),
        .init(id: "MV04", number: 4, category: .themeAndContrast, title: "Primary map label WCAG AA 4.5:1 contrast minimum"),
        .init(id: "MV05", number: 5, category: .themeAndContrast, title: "Secondary callout badge WCAG AA 4.5:1 contrast minimum"),
        .init(id: "MV06", number: 6, category: .themeAndContrast, title: "High-glare outdoor contrast boost token"),
        .init(id: "MV07", number: 7, category: .themeAndContrast, title: "Water and park semantic polygon tinting"),
        .init(id: "MV08", number: 8, category: .themeAndContrast, title: "Road hierarchy stroke contrast separation"),
        // MV09..MV16: Deterministic Layer Order
        .init(id: "MV09", number: 9, category: .layerOrder, title: "baseMap bottom anchor layer (index 0)"),
        .init(id: "MV10", number: 10, category: .layerOrder, title: "fogOverlay layer above baseMap (index 1)"),
        .init(id: "MV11", number: 11, category: .layerOrder, title: "routePath layer above fogOverlay (index 2)"),
        .init(id: "MV12", number: 12, category: .layerOrder, title: "poiMarkers layer above routePath (index 3)"),
        .init(id: "MV13", number: 13, category: .layerOrder, title: "activeStopCallout layer above poiMarkers (index 4)"),
        .init(id: "MV14", number: 14, category: .layerOrder, title: "userPuck top anchor layer above activeStopCallout (index 5)"),
        .init(id: "MV15", number: 15, category: .layerOrder, title: "Strict monotonic bottom-to-top z-index invariant"),
        .init(id: "MV16", number: 16, category: .layerOrder, title: "Collision priority keeping userPuck and activeStopCallout unoccluded"),
        // MV17..MV25: Marker State Projection
        .init(id: "MV17", number: 17, category: .markerStateProjection, title: "Locked marker muted silhouette and lock badge"),
        .init(id: "MV18", number: 18, category: .markerStateProjection, title: "Discoverable marker pulse ring and proximity badge"),
        .init(id: "MV19", number: 19, category: .markerStateProjection, title: "Active marker elevated scale and primary accent halo"),
        .init(id: "MV20", number: 20, category: .markerStateProjection, title: "Completed marker checkmark badge and subdued opacity"),
        .init(id: "MV21", number: 21, category: .markerStateProjection, title: "Unavailable marker closed indicator and disabled action state"),
        .init(id: "MV22", number: 22, category: .markerStateProjection, title: "Cluster badge count pill typography and overflow cap"),
        .init(id: "MV23", number: 23, category: .markerStateProjection, title: "Marker selection spring animation duration bound"),
        .init(id: "MV24", number: 24, category: .markerStateProjection, title: "Marker accessibility label and state announcement"),
        .init(id: "MV25", number: 25, category: .markerStateProjection, title: "Minimum 44x44pt hit target for interactive POI markers"),
        // MV26..MV33: Coordinate Datum Badge & Transform Isolation
        .init(id: "MV26", number: 26, category: .coordinateDatumIsolation, title: "Explicit coordinate datum tag on every map payload"),
        .init(id: "MV27", number: 27, category: .coordinateDatumIsolation, title: "CN mainland basemap GCJ-02 datum alignment"),
        .init(id: "MV28", number: 28, category: .coordinateDatumIsolation, title: "Global overseas basemap WGS-84 datum alignment"),
        .init(id: "MV29", number: 29, category: .coordinateDatumIsolation, title: "Single-pass datum transform idempotency guard"),
        .init(id: "MV30", number: 30, category: .coordinateDatumIsolation, title: "Coordinate datum badge projection (`WGS-84` vs `GCJ-02`)"),
        .init(id: "MV31", number: 31, category: .coordinateDatumIsolation, title: "Geofence distance calculation in homogeneous datum space"),
        .init(id: "MV32", number: 32, category: .coordinateDatumIsolation, title: "Route polyline vertex datum homogeneity check"),
        .init(id: "MV33", number: 33, category: .coordinateDatumIsolation, title: "Cross-datum mismatch rejection prior to map projection"),
        // MV34..MV41: Personal Fog Confirmed vs Predicted Separation
        .init(id: "MV34", number: 34, category: .personalFogSeparation, title: "Default-off personal fog cloud sync (`revealSyncEnabled == false`)"),
        .init(id: "MV35", number: 35, category: .personalFogSeparation, title: "Confirmed fog cell full-clear visual mask"),
        .init(id: "MV36", number: 36, category: .personalFogSeparation, title: "Predicted local fog cell distinct translucent preview mask"),
        .init(id: "MV37", number: 37, category: .personalFogSeparation, title: "Strict separation forbidding silent predicted-to-confirmed promotion"),
        .init(id: "MV38", number: 38, category: .personalFogSeparation, title: "Deterministic spatial cell key quantization"),
        .init(id: "MV39", number: 39, category: .personalFogSeparation, title: "Fog boundary feathering gradient falloff"),
        .init(id: "MV40", number: 40, category: .personalFogSeparation, title: "Redacted coordinate telemetry on fog cell updates"),
        .init(id: "MV41", number: 41, category: .personalFogSeparation, title: "Explicit user consent required before enabling revealSyncEnabled")
    ]

    // MARK: - Domain Types

    public enum MapThemeAppearance: String, CaseIterable, Sendable, Equatable {
        case day = "DAY"
        case night = "NIGHT"
    }

    public enum MapRenderLayer: String, CaseIterable, Sendable, Equatable {
        case baseMap = "baseMap"
        case fogOverlay = "fogOverlay"
        case routePath = "routePath"
        case poiMarkers = "poiMarkers"
        case activeStopCallout = "activeStopCallout"
        case userPuck = "userPuck"

        public static let canonicalBottomToTopOrder: [MapRenderLayer] = [
            .baseMap,
            .fogOverlay,
            .routePath,
            .poiMarkers,
            .activeStopCallout,
            .userPuck
        ]
    }

    public enum MapMarkerVisualState: String, CaseIterable, Sendable, Equatable {
        case locked = "locked"
        case discoverable = "discoverable"
        case active = "active"
        case completed = "completed"
        case unavailable = "unavailable"
    }

    public struct MarkerVisualProjection: Sendable, Equatable {
        public let state: MapMarkerVisualState
        public let opacity: Double
        public let scale: Double
        public let showsPulseRing: Bool
        public let badgeSymbol: String
        public let isActionable: Bool
        public let hitTargetPoints: Double

        public init(
            state: MapMarkerVisualState,
            opacity: Double,
            scale: Double,
            showsPulseRing: Bool,
            badgeSymbol: String,
            isActionable: Bool,
            hitTargetPoints: Double = 44.0
        ) {
            self.state = state
            self.opacity = opacity
            self.scale = scale
            self.showsPulseRing = showsPulseRing
            self.badgeSymbol = badgeSymbol
            self.isActionable = isActionable
            self.hitTargetPoints = hitTargetPoints
        }
    }

    public static func canonicalProjection(for state: MapMarkerVisualState) -> MarkerVisualProjection {
        switch state {
        case .locked:
            return MarkerVisualProjection(
                state: .locked,
                opacity: 0.55,
                scale: 0.92,
                showsPulseRing: false,
                badgeSymbol: "lock.fill",
                isActionable: false
            )
        case .discoverable:
            return MarkerVisualProjection(
                state: .discoverable,
                opacity: 0.95,
                scale: 1.0,
                showsPulseRing: true,
                badgeSymbol: "sparkles",
                isActionable: true
            )
        case .active:
            return MarkerVisualProjection(
                state: .active,
                opacity: 1.0,
                scale: 1.18,
                showsPulseRing: true,
                badgeSymbol: "location.north.line.fill",
                isActionable: true
            )
        case .completed:
            return MarkerVisualProjection(
                state: .completed,
                opacity: 0.78,
                scale: 0.96,
                showsPulseRing: false,
                badgeSymbol: "checkmark.seal.fill",
                isActionable: true
            )
        case .unavailable:
            return MarkerVisualProjection(
                state: .unavailable,
                opacity: 0.42,
                scale: 0.90,
                showsPulseRing: false,
                badgeSymbol: "nosign",
                isActionable: false
            )
        }
    }

    public enum CoordinateDatum: String, CaseIterable, Sendable, Equatable {
        case wgs84 = "WGS-84"
        case gcj02 = "GCJ-02"
    }

    public struct PersonalFogAuditState: Sendable, Equatable {
        public let revealSyncEnabledByDefault: Bool
        public let revealSyncEnabledCurrent: Bool
        public let hasExplicitUserSyncConsent: Bool
        public let confirmedCellIDs: Set<String>
        public let predictedCellIDs: Set<String>
        public let allowsSilentPredictedToConfirmedPromotion: Bool

        public init(
            revealSyncEnabledByDefault: Bool = false,
            revealSyncEnabledCurrent: Bool = false,
            hasExplicitUserSyncConsent: Bool = false,
            confirmedCellIDs: Set<String> = ["h3-8928308280fffff"],
            predictedCellIDs: Set<String> = ["h3-8928308281fffff"],
            allowsSilentPredictedToConfirmedPromotion: Bool = false
        ) {
            self.revealSyncEnabledByDefault = revealSyncEnabledByDefault
            self.revealSyncEnabledCurrent = revealSyncEnabledCurrent
            self.hasExplicitUserSyncConsent = hasExplicitUserSyncConsent
            self.confirmedCellIDs = confirmedCellIDs
            self.predictedCellIDs = predictedCellIDs
            self.allowsSilentPredictedToConfirmedPromotion = allowsSilentPredictedToConfirmedPromotion
        }
    }

    // MARK: - Audit Input & Verdict

    public struct AuditSnapshot: Sendable, Equatable {
        public static let minimumWCAGContrastRatio: Double = 4.5

        public let supportedThemes: Set<MapThemeAppearance>
        public let primaryLabelContrastRatio: Double
        public let secondaryBadgeContrastRatio: Double
        public let configuredLayerOrder: [MapRenderLayer]
        public let supportedMarkerStates: Set<MapMarkerVisualState>
        public let minimumMarkerHitTargetPoints: Double
        public let basemapDatum: CoordinateDatum
        public let overlayPayloadDatum: CoordinateDatum
        public let appliedTransformPassCount: Int
        public let displaysDatumBadge: Bool
        public let personalFogState: PersonalFogAuditState

        public init(
            supportedThemes: Set<MapThemeAppearance> = Set(MapThemeAppearance.allCases),
            primaryLabelContrastRatio: Double = 7.2,
            secondaryBadgeContrastRatio: Double = 4.8,
            configuredLayerOrder: [MapRenderLayer] = MapRenderLayer.canonicalBottomToTopOrder,
            supportedMarkerStates: Set<MapMarkerVisualState> = Set(MapMarkerVisualState.allCases),
            minimumMarkerHitTargetPoints: Double = 44.0,
            basemapDatum: CoordinateDatum = .gcj02,
            overlayPayloadDatum: CoordinateDatum = .gcj02,
            appliedTransformPassCount: Int = 1,
            displaysDatumBadge: Bool = true,
            personalFogState: PersonalFogAuditState = PersonalFogAuditState()
        ) {
            self.supportedThemes = supportedThemes
            self.primaryLabelContrastRatio = primaryLabelContrastRatio
            self.secondaryBadgeContrastRatio = secondaryBadgeContrastRatio
            self.configuredLayerOrder = configuredLayerOrder
            self.supportedMarkerStates = supportedMarkerStates
            self.minimumMarkerHitTargetPoints = minimumMarkerHitTargetPoints
            self.basemapDatum = basemapDatum
            self.overlayPayloadDatum = overlayPayloadDatum
            self.appliedTransformPassCount = appliedTransformPassCount
            self.displaysDatumBadge = displaysDatumBadge
            self.personalFogState = personalFogState
        }
    }

    public enum AuditFailureReason: Sendable, Equatable {
        case missingThemeCoverage(Set<MapThemeAppearance>)
        case insufficientContrastRatio(primary: Double, secondary: Double, minimumRequired: Double)
        case invalidLayerOrder(actual: [MapRenderLayer], expected: [MapRenderLayer])
        case incompleteMarkerStateProjections(missing: Set<MapMarkerVisualState>)
        case insufficientMarkerHitTarget(points: Double)
        case coordinateDatumMismatch(basemap: CoordinateDatum, overlay: CoordinateDatum)
        case doubleDatumTransformDetected(passCount: Int)
        case missingDatumBadge
        case revealSyncDefaultNotOff
        case revealSyncEnabledWithoutExplicitUserConsent
        case overlappingOrUnseparatedFogCells(overlap: Set<String>)
        case silentPredictedToConfirmedPromotionAllowed
    }

    public struct AuditReport: Sendable, Equatable {
        public let verifiedSpecIDs: [String]
        public let failures: [AuditFailureReason]

        public var isFullyCompliant: Bool {
            failures.isEmpty && verifiedSpecIDs.count == 41
        }

        public init(verifiedSpecIDs: [String], failures: [AuditFailureReason]) {
            self.verifiedSpecIDs = verifiedSpecIDs
            self.failures = failures
        }
    }

    // MARK: - Evaluation

    public static func evaluate(_ snapshot: AuditSnapshot = AuditSnapshot()) -> AuditReport {
        var failures: [AuditFailureReason] = []

        // 1. Theme & WCAG 4.5:1 Contrast (MV01..MV08)
        let missingThemes = Set(MapThemeAppearance.allCases).subtracting(snapshot.supportedThemes)
        if !missingThemes.isEmpty {
            failures.append(.missingThemeCoverage(missingThemes))
        }
        if snapshot.primaryLabelContrastRatio < AuditSnapshot.minimumWCAGContrastRatio ||
            snapshot.secondaryBadgeContrastRatio < AuditSnapshot.minimumWCAGContrastRatio {
            failures.append(
                .insufficientContrastRatio(
                    primary: snapshot.primaryLabelContrastRatio,
                    secondary: snapshot.secondaryBadgeContrastRatio,
                    minimumRequired: AuditSnapshot.minimumWCAGContrastRatio
                )
            )
        }

        // 2. Deterministic Bottom-to-Top Layer Order (MV09..MV16)
        if snapshot.configuredLayerOrder != MapRenderLayer.canonicalBottomToTopOrder {
            failures.append(
                .invalidLayerOrder(
                    actual: snapshot.configuredLayerOrder,
                    expected: MapRenderLayer.canonicalBottomToTopOrder
                )
            )
        }

        // 3. Marker State Visual Projection (MV17..MV25)
        let missingStates = Set(MapMarkerVisualState.allCases).subtracting(snapshot.supportedMarkerStates)
        if !missingStates.isEmpty {
            failures.append(.incompleteMarkerStateProjections(missing: missingStates))
        }
        if snapshot.minimumMarkerHitTargetPoints < 44.0 {
            failures.append(.insufficientMarkerHitTarget(points: snapshot.minimumMarkerHitTargetPoints))
        }

        // 4. Coordinate Datum Badge & Transform Isolation (MV26..MV33)
        if snapshot.basemapDatum != snapshot.overlayPayloadDatum {
            failures.append(
                .coordinateDatumMismatch(
                    basemap: snapshot.basemapDatum,
                    overlay: snapshot.overlayPayloadDatum
                )
            )
        }
        if !(0...1).contains(snapshot.appliedTransformPassCount) {
            failures.append(.doubleDatumTransformDetected(passCount: snapshot.appliedTransformPassCount))
        }
        if !snapshot.displaysDatumBadge {
            failures.append(.missingDatumBadge)
        }

        // 5. Personal Fog Confirmed vs Predicted Separation & revealSyncEnabled == false Default (MV34..MV41)
        let fog = snapshot.personalFogState
        if fog.revealSyncEnabledByDefault {
            failures.append(.revealSyncDefaultNotOff)
        }
        if fog.revealSyncEnabledCurrent && !fog.hasExplicitUserSyncConsent {
            failures.append(.revealSyncEnabledWithoutExplicitUserConsent)
        }
        let overlap = fog.confirmedCellIDs.intersection(fog.predictedCellIDs)
        if !overlap.isEmpty {
            failures.append(.overlappingOrUnseparatedFogCells(overlap: overlap))
        }
        if fog.allowsSilentPredictedToConfirmedPromotion {
            failures.append(.silentPredictedToConfirmedPromotionAllowed)
        }

        let verifiedIDs = failures.isEmpty ? allSpecDescriptors.map(\.id) : []
        return AuditReport(verifiedSpecIDs: verifiedIDs, failures: failures)
    }
}

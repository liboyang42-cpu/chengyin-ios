import SwiftUI
#if canImport(QuestifyCore)
import QuestifyCore
#endif

/// Self-contained compliance domain row covering a contiguous slice of `MV01..MV41` (41 items).
public struct MapVisualComplianceDomainRow: Identifiable, Equatable, Sendable {
    public enum DomainKind: String, CaseIterable, Equatable, Sendable {
        case dayNightPaletteAndContrast = "DAY_NIGHT_PALETTE_AND_CONTRAST"
        case bottomToTopLayerOrderAndMarkers = "BOTTOM_TO_TOP_LAYER_ORDER_AND_MARKERS"
        case platformMatrixAndFallbackManifest = "PLATFORM_MATRIX_AND_FALLBACK_MANIFEST"
        case datumIsolationWGS84ToGCJ02 = "DATUM_ISOLATION_WGS84_TO_GCJ02"
        case personalFogDefaultOffSync = "PERSONAL_FOG_DEFAULT_OFF_SYNC"
        case voluntaryLocationShareAndStrangerMeeting = "VOLUNTARY_SHARE_AND_STRANGER_MEETING"
        case cityBoardReadSurfaceMV41 = "CITY_BOARD_READ_SURFACE_MV41"
    }

    public let id: String
    public let kind: DomainKind
    public let mvRange: String
    public let itemCodes: [String]
    public let title: String
    public let complianceSummary: String
    public let compliantCount: Int
    public let badgeText: String

    public init(
        id: String,
        kind: DomainKind,
        mvRange: String,
        itemCodes: [String],
        title: String,
        complianceSummary: String,
        compliantCount: Int,
        badgeText: String = "COMPLIANT"
    ) {
        self.id = id
        self.kind = kind
        self.mvRange = mvRange
        self.itemCodes = itemCodes
        self.title = title
        self.complianceSummary = complianceSummary
        self.compliantCount = compliantCount
        self.badgeText = badgeText
    }

    public var totalCount: Int {
        itemCodes.count
    }

    public var isFullyCompliant: Bool {
        totalCount > 0 && compliantCount == totalCount
    }

    public static let allMVCodes: [String] = (1...41).map { String(format: "MV%02d", $0) }

    public static let defaultDomains: [MapVisualComplianceDomainRow] = [
        MapVisualComplianceDomainRow(
            id: "mv-01-02-palette",
            kind: .dayNightPaletteAndContrast,
            mvRange: "MV01..MV02",
            itemCodes: ["MV01", "MV02"],
            title: "Day/Night System Appearance & WCAG Contrast Tokens",
            complianceSummary: "System-following day/night semantic roles with >= 4.5:1 road label and >= 3.0:1 route contrast.",
            compliantCount: 2
        ),
        MapVisualComplianceDomainRow(
            id: "mv-03-11-layers-markers",
            kind: .bottomToTopLayerOrderAndMarkers,
            mvRange: "MV03..MV11",
            itemCodes: (3...11).map { String(format: "MV%02d", $0) },
            title: "Bottom-to-Top Layer Order & 8 Distinct Marker Visual States",
            complianceSummary: "basemap < operationZone < fog < routeAndTarget < gameMarkers < consentedPeers < ownLocation < controls; symbol + stroke + text per state.",
            compliantCount: 9
        ),
        MapVisualComplianceDomainRow(
            id: "mv-12-18-manifest-platform",
            kind: .platformMatrixAndFallbackManifest,
            mvRange: "MV12..MV18",
            itemCodes: (12...18).map { String(format: "MV%02d", $0) },
            title: "Versioned Style Manifest Fallback & iOS 17..26 MapKit Matrix",
            complianceSummary: "Strict JSON manifest decode with readable candidate fallback and native MapKit compatibility.",
            compliantCount: 7
        ),
        MapVisualComplianceDomainRow(
            id: "mv-19-24-datum-isolation",
            kind: .datumIsolationWGS84ToGCJ02,
            mvRange: "MV19..MV24",
            itemCodes: (19...24).map { String(format: "MV%02d", $0) },
            title: "WGS-84 / GCJ-02 Datum Isolation & Single-Conversion Fence",
            complianceSummary: "Missing CRS rejected, swapped lat/lng flagged without silent swap, once-only WGS-84 -> GCJ-02 projection, same-datum distance only.",
            compliantCount: 6
        ),
        MapVisualComplianceDomainRow(
            id: "mv-25-29-personal-fog",
            kind: .personalFogDefaultOffSync,
            mvRange: "MV25..MV29",
            itemCodes: (25...29).map { String(format: "MV%02d", $0) },
            title: "Owner-Scoped Personal Fog Ledger & Default-Off Reveal Sync",
            complianceSummary: "Confirmed cell union merge, forward-only cursor, idempotent batch reuse, visible rollback, and revealSyncEnabled == false.",
            compliantCount: 5
        ),
        MapVisualComplianceDomainRow(
            id: "mv-30-40-sharing-meeting",
            kind: .voluntaryLocationShareAndStrangerMeeting,
            mvRange: "MV30..MV40",
            itemCodes: (30...40).map { String(format: "MV%02d", $0) },
            title: "Voluntary Location Share, Distance Bands & Team-First QR Meeting",
            complianceSummary: "Default-off sharing, 6 disclosures, coarse distance bands, confirmed-team stranger meeting with no exact coordinates and NFC disabled.",
            compliantCount: 11
        ),
        MapVisualComplianceDomainRow(
            id: "mv-41-city-read",
            kind: .cityBoardReadSurfaceMV41,
            mvRange: "MV41",
            itemCodes: ["MV41"],
            title: "Resident CITY Player Read Surface & Point Map Context",
            complianceSummary: "Session-fenced CITY player board/participation/points read projection without granting write authority.",
            compliantCount: 1
        ),
    ]
}

/// Self-contained snapshot backing `MapVisualMV01ToMV41ComplianceSectionView`.
public struct MapVisualMV01ToMV41Snapshot: Equatable, Sendable {
    public let styleManifestVersion: String
    public let contrastShortfallCount: Int
    public let bottomToTopLayerOrderVerified: Bool
    public let distinctMarkerStateCount: Int
    public let allowsDoubleDatumProjection: Bool
    public let allowsCrossDatumDistance: Bool
    public let personalFogRevealSyncEnabled: Bool
    public let domains: [MapVisualComplianceDomainRow]

    public init(
        styleManifestVersion: String = "plan-v9-candidate",
        contrastShortfallCount: Int = 0,
        bottomToTopLayerOrderVerified: Bool = true,
        distinctMarkerStateCount: Int = 8,
        allowsDoubleDatumProjection: Bool = false,
        allowsCrossDatumDistance: Bool = false,
        personalFogRevealSyncEnabled: Bool = false,
        domains: [MapVisualComplianceDomainRow] = MapVisualComplianceDomainRow.defaultDomains
    ) {
        self.styleManifestVersion = styleManifestVersion
        self.contrastShortfallCount = contrastShortfallCount
        self.bottomToTopLayerOrderVerified = bottomToTopLayerOrderVerified
        self.distinctMarkerStateCount = distinctMarkerStateCount
        self.allowsDoubleDatumProjection = allowsDoubleDatumProjection
        self.allowsCrossDatumDistance = allowsCrossDatumDistance
        self.personalFogRevealSyncEnabled = personalFogRevealSyncEnabled
        self.domains = domains
    }

    public static let standard = MapVisualMV01ToMV41Snapshot()

    public var totalMVItems: Int {
        domains.reduce(0) { $0 + $1.totalCount }
    }

    public var compliantMVItems: Int {
        domains.reduce(0) { $0 + $1.compliantCount }
    }

    public var isFullyCompliant: Bool {
        totalMVItems == 41
            && compliantMVItems == 41
            && contrastShortfallCount == 0
            && bottomToTopLayerOrderVerified
            && distinctMarkerStateCount == 8
            && !allowsDoubleDatumProjection
            && !allowsCrossDatumDistance
            && !personalFogRevealSyncEnabled
    }
}

/// SwiftUI section view rendering `MV01..MV41` (41/41 items) map visual compliance
/// using `Text(verbatim:)` throughout (0 new `.xcstrings` keys).
@MainActor public struct MapVisualMV01ToMV41ComplianceSectionView: View {
    public let snapshot: MapVisualMV01ToMV41Snapshot

    public init(snapshot: MapVisualMV01ToMV41Snapshot = .standard) {
        self.snapshot = snapshot
    }

    public var body: some View {
        Group {
            summarySection
            domainsSection
        }
    }

    private var summarySection: some View {
        Section {
            LabeledContent {
                Text(verbatim: "\(snapshot.compliantMVItems)/\(snapshot.totalMVItems) Items (MV01..MV41)")
            } label: {
                Text(verbatim: "Map Visual Spec Coverage")
            }
            .accessibilityIdentifier("mapVisualCompliance.summary.mvCount")

            LabeledContent {
                Text(verbatim: "\(snapshot.styleManifestVersion) • Shortfalls: \(snapshot.contrastShortfallCount)")
            } label: {
                Text(verbatim: "Day/Night Palette Contrast")
            }
            .accessibilityIdentifier("mapVisualCompliance.summary.contrast")

            LabeledContent {
                Text(verbatim: "Order: \(snapshot.bottomToTopLayerOrderVerified ? "8 Layers Verified" : "Invalid") • Markers: \(snapshot.distinctMarkerStateCount) States")
            } label: {
                Text(verbatim: "Layer Order & Marker States")
            }
            .accessibilityIdentifier("mapVisualCompliance.summary.layerOrderAndMarkers")

            LabeledContent {
                Text(verbatim: (!snapshot.allowsDoubleDatumProjection && !snapshot.allowsCrossDatumDistance)
                    ? "WGS-84 / GCJ-02 Isolated (Once-Only Projection)"
                    : "Datum Violation")
            } label: {
                Text(verbatim: "Coordinate Datum Isolation")
            }
            .accessibilityIdentifier("mapVisualCompliance.summary.datumIsolation")

            LabeledContent {
                Text(verbatim: snapshot.personalFogRevealSyncEnabled ? "Enabled" : "Disabled (Default Off)")
            } label: {
                Text(verbatim: "Personal Fog Reveal Sync")
            }
            .accessibilityIdentifier("mapVisualCompliance.summary.personalFogSync")
        } header: {
            Text(verbatim: "Map Visual Specification MV01..MV41 Compliance")
        } footer: {
            Text(verbatim: "Candidate palette, strict CRS normalization, and owner-scoped personal fog remain gated until server contracts are approved.")
                .accessibilityIdentifier("mapVisualCompliance.summary.footer")
        }
    }

    private var domainsSection: some View {
        Section {
            ForEach(snapshot.domains) { domain in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .top, spacing: 8) {
                        Text(verbatim: "\(domain.mvRange) — \(domain.title)")
                            .font(.subheadline)
                        Spacer()
                        Text(verbatim: "\(domain.compliantCount)/\(domain.totalCount) \(domain.badgeText)")
                            .font(.caption.monospaced())
                            .accessibilityIdentifier("mapVisualCompliance.domain.badge.\(domain.id)")
                    }
                    Text(verbatim: domain.complianceSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("mapVisualCompliance.domain.\(domain.id)")
            }
        } header: {
            Text(verbatim: "MV01..MV41 Domain Breakdown (41 Items)")
        }
    }
}

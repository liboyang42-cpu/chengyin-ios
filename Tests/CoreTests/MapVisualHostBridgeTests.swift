import XCTest
@testable import QuestifyCore

final class MapVisualHostBridgeTests: XCTestCase {
    func testDayAndNightResolutionUsesSystemAppearanceAndCandidateFallback() {
        let dayTheme = MapVisualHostBridge.resolveTheme(manifestData: nil, systemIsDark: false)
        XCTAssertEqual(dayTheme.appearance, .day)
        XCTAssertEqual(dayTheme.manifestVersion, "plan-v9-candidate")
        XCTAssertTrue(dayTheme.isCandidatePalette)
        XCTAssertEqual(dayTheme.color(for: .ground), MapVisualStyleManifest.candidate.color(.ground, .day))
        XCTAssertTrue(dayTheme.contrastShortfalls.isEmpty)

        let nightTheme = MapVisualHostBridge.resolveTheme(manifestData: Data("{\"invalid\":true}".utf8), systemIsDark: true)
        XCTAssertEqual(nightTheme.appearance, .night)
        XCTAssertEqual(nightTheme.manifestVersion, "plan-v9-candidate")
        XCTAssertEqual(nightTheme.color(for: .ground), MapVisualStyleManifest.candidate.color(.ground, .night))
        XCTAssertNotEqual(dayTheme.color(for: .ground), nightTheme.color(for: .ground))
    }

    func testValidCustomManifestResolvesApprovedTokens() throws {
        let json = """
        {
          "version": "2026.10.20-approved",
          "approval": "approved",
          "day": {
            "ground": "#F5F4F0",
            "water": "#D8E5EA",
            "green": "#E0E7DC",
            "majorRoad": "#FFFFFF",
            "roadLabel": "#353A42",
            "currentTargetRoute": "#006C70",
            "completedUnavailable": "#595E66",
            "fogOverlay": "#808080",
            "operationZone": "#808080"
          },
          "night": {
            "ground": "#151922",
            "water": "#233944",
            "green": "#2C3B35",
            "majorRoad": "#9AA7B8",
            "roadLabel": "#E3E7EE",
            "currentTargetRoute": "#63D9D3",
            "completedUnavailable": "#BAC2CD",
            "fogOverlay": "#808080",
            "operationZone": "#808080"
          },
          "opacity": {
            "fogOverlay": 0.35,
            "operationZone": 0.15
          }
        }
        """
        let theme = MapVisualHostBridge.resolveTheme(manifestData: Data(json.utf8), systemIsDark: true)
        XCTAssertEqual(theme.manifestVersion, "2026.10.20-approved")
        XCTAssertEqual(theme.approval, .approved)
        XCTAssertFalse(theme.isCandidatePalette)
        XCTAssertEqual(theme.color(for: .currentTargetRoute), MapStyleColor(hex: "#63D9D3"))
        XCTAssertEqual(theme.color(for: .fogOverlay).opacity, 0.35, accuracy: 0.0001)
    }

    func testLayerOrderAndMarkerSelectionProjectionPreservesServerEligibility() throws {
        let orders = MapVisualHostBridge.orderedLayers()
        XCTAssertEqual(orders, [.basemap, .operationZone, .fog, .routeAndTarget, .gameMarkers, .consentedPeers, .ownLocation, .controls])
        XCTAssertLessThan(MapLayerOrder.fog, MapLayerOrder.routeAndTarget)
        XCTAssertLessThan(MapLayerOrder.gameMarkers, MapLayerOrder.ownLocation)

        let theme = MapVisualHostBridge.resolveTheme(systemIsDark: false)
        let coordinate = try MapCoordinateObservation(
            latitude: 30.2741,
            longitude: 120.1551,
            datum: .gcj02,
            source: .backend
        )
        let interactiveKey = try MapSourceKey(type: .roamPOI, id: "poi-1")
        let lockedKey = try MapSourceKey(type: .sideQuest, id: "quest-2")

        let interactiveItem = try MapLayerItem(
            key: interactiveKey,
            placeID: "place-hz-1",
            visibilityVersion: 1,
            state: .interactive,
            coordinate: coordinate,
            capabilities: [.viewDetail, .navigate],
            sortKey: "001",
            title: "West Lake Checkpoint"
        )
        let lockedItem = try MapLayerItem(
            key: lockedKey,
            placeID: nil,
            visibilityVersion: 1,
            state: .locked,
            coordinate: coordinate,
            capabilities: [.viewDetail],
            sortKey: "002",
            title: "Locked Side Quest"
        )

        let projections = try MapVisualHostBridge.projectAnnotations(
            items: [interactiveItem, lockedItem],
            visibleLayers: [.roamPOI, .sideQuest],
            selectedKey: lockedKey,
            activeKey: interactiveKey,
            targetDatum: .gcj02,
            theme: theme
        )
        XCTAssertEqual(projections.count, 2)

        let activeProjection = projections[0]
        XCTAssertEqual(activeProjection.key, interactiveKey)
        XCTAssertEqual(activeProjection.effectiveState, .active)
        XCTAssertEqual(activeProjection.symbolName, "figure.walk")
        XCTAssertEqual(activeProjection.strokeWidth, 2.5)
        XCTAssertTrue(activeProjection.allowsPrimaryAction)
        XCTAssertEqual(activeProjection.tintColor, theme.color(for: .currentTargetRoute))

        let selectedLockedProjection = projections[1]
        XCTAssertEqual(selectedLockedProjection.key, lockedKey)
        XCTAssertEqual(selectedLockedProjection.serverState, .locked)
        XCTAssertEqual(selectedLockedProjection.effectiveState, .selected)
        XCTAssertEqual(selectedLockedProjection.symbolName, "scope")
        XCTAssertEqual(selectedLockedProjection.strokeWidth, 3.0)
        // UI selection must never unlock primary action on a locked item.
        XCTAssertFalse(selectedLockedProjection.allowsPrimaryAction)
        XCTAssertEqual(selectedLockedProjection.tintColor, theme.color(for: .completedUnavailable))
    }

    func testVisibleLayerFilterRemovesHiddenAnnotations() throws {
        let theme = MapVisualHostBridge.resolveTheme(systemIsDark: false)
        let coordinate = try MapCoordinateObservation(latitude: 31.2304, longitude: 121.4737, datum: .gcj02, source: .backend)
        let poiItem = try MapLayerItem(
            key: MapSourceKey(type: .roamPOI, id: "poi-10"),
            placeID: nil,
            visibilityVersion: 1,
            state: .standard,
            coordinate: coordinate,
            capabilities: [.viewDetail],
            sortKey: "010",
            title: "Bund Node"
        )
        let storeItem = try MapLayerItem(
            key: MapSourceKey(type: .store, id: "store-10"),
            placeID: nil,
            visibilityVersion: 1,
            state: .standard,
            coordinate: coordinate,
            capabilities: [.viewDetail],
            sortKey: "020",
            title: "Store Node"
        )

        let onlyPOI = try MapVisualHostBridge.projectAnnotations(
            items: [poiItem, storeItem],
            visibleLayers: [.roamPOI],
            theme: theme
        )
        XCTAssertEqual(onlyPOI.map(\.key.type), [.roamPOI])
    }

    func testSingleWGS84ToGCJ02ConversionAndDoubleConversionRejection() throws {
        let rawWGS84 = try MapCoordinateObservation(
            latitude: 30.2741,
            longitude: 120.1551,
            datum: .wgs84,
            source: .deviceLocation,
            accuracyMeters: 8.5,
            observedAt: Date(timeIntervalSince1970: 1_760_000_000)
        )
        let converted = try MapVisualHostBridge.convertWGS84ToGCJ02Once(rawWGS84)
        XCTAssertEqual(converted.datum, .gcj02)
        XCTAssertEqual(converted.conversion, "wgs84-gcj02-source-a63e9e9")
        XCTAssertNotEqual(converted.latitude, rawWGS84.latitude)
        XCTAssertNotEqual(converted.longitude, rawWGS84.longitude)

        // Attempting to convert an already-converted coordinate again must fail with .doubleConversion.
        XCTAssertThrowsError(try MapVisualHostBridge.convertWGS84ToGCJ02Once(converted)) { error in
            XCTAssertEqual(error as? MapCoordinateFailure, .doubleConversion)
        }
        XCTAssertThrowsError(try converted.projected(to: .wgs84)) { error in
            XCTAssertEqual(error as? MapCoordinateFailure, .doubleConversion)
        }
    }

    func testSameDatumDistanceHelperAndDatumMismatchRejection() throws {
        let wgsA = try MapCoordinateObservation(latitude: 30.2741, longitude: 120.1551, datum: .wgs84, source: .deviceLocation)
        let gcjB = try MapCoordinateObservation(latitude: 30.2750, longitude: 120.1560, datum: .gcj02, source: .backend)

        XCTAssertThrowsError(try MapVisualHostBridge.sameDatumDistanceMeters(from: wgsA, to: gcjB)) { error in
            XCTAssertEqual(error as? MapCoordinateFailure, .datumMismatch)
        }

        let projectedA = try MapVisualHostBridge.projectCoordinateForHost(wgsA, targetDatum: .gcj02)
        let distance = try MapVisualHostBridge.sameDatumDistanceMeters(from: projectedA, to: gcjB)
        XCTAssertGreaterThan(distance, 50)
        XCTAssertLessThan(distance, 1_000)
    }
}

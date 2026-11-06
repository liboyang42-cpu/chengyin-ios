import XCTest
@testable import QuestifyCore

final class MapVisualMV01ToMV41ComplianceAuditTests: XCTestCase {

    func testAllFortyOneMV01ToMV41SpecDescriptorsAndDefaultCompliance() {
        let descriptors = MapVisualMV01ToMV41ComplianceAudit.allSpecDescriptors
        XCTAssertEqual(descriptors.count, 41)

        let expectedIDs = (1...41).map { String(format: "MV%02d", $0) }
        XCTAssertEqual(descriptors.map(\.id), expectedIDs)

        let report = MapVisualMV01ToMV41ComplianceAudit.evaluate()
        XCTAssertTrue(report.isFullyCompliant)
        XCTAssertEqual(report.verifiedSpecIDs, expectedIDs)
        XCTAssertTrue(report.failures.isEmpty)
    }

    func testDeterministicBottomToTopLayerOrderEnforcement() {
        let canonicalOrder: [MapVisualMV01ToMV41ComplianceAudit.MapRenderLayer] = [
            .baseMap,
            .fogOverlay,
            .routePath,
            .poiMarkers,
            .activeStopCallout,
            .userPuck
        ]
        XCTAssertEqual(
            MapVisualMV01ToMV41ComplianceAudit.MapRenderLayer.canonicalBottomToTopOrder,
            canonicalOrder
        )

        let invertedOrderSnapshot = MapVisualMV01ToMV41ComplianceAudit.AuditSnapshot(
            configuredLayerOrder: [
                .baseMap,
                .routePath,
                .fogOverlay,
                .poiMarkers,
                .userPuck,
                .activeStopCallout
            ]
        )
        let report = MapVisualMV01ToMV41ComplianceAudit.evaluate(invertedOrderSnapshot)
        XCTAssertFalse(report.isFullyCompliant)
        XCTAssertEqual(
            report.failures,
            [
                .invalidLayerOrder(
                    actual: invertedOrderSnapshot.configuredLayerOrder,
                    expected: canonicalOrder
                )
            ]
        )
    }

    func testCoordinateDatumMismatchAndDoubleTransformDetection() {
        let mismatchSnapshot = MapVisualMV01ToMV41ComplianceAudit.AuditSnapshot(
            basemapDatum: .gcj02,
            overlayPayloadDatum: .wgs84,
            appliedTransformPassCount: 2,
            displaysDatumBadge: false
        )
        let report = MapVisualMV01ToMV41ComplianceAudit.evaluate(mismatchSnapshot)
        XCTAssertFalse(report.isFullyCompliant)
        XCTAssertEqual(
            report.failures,
            [
                .coordinateDatumMismatch(basemap: .gcj02, overlay: .wgs84),
                .doubleDatumTransformDetected(passCount: 2),
                .missingDatumBadge
            ]
        )
    }

    func testPersonalFogRevealSyncDefaultOffAndCellSeparationEnforcement() {
        let violatedFogState = MapVisualMV01ToMV41ComplianceAudit.PersonalFogAuditState(
            revealSyncEnabledByDefault: true,
            revealSyncEnabledCurrent: true,
            hasExplicitUserSyncConsent: false,
            confirmedCellIDs: ["h3-cell-01", "h3-cell-02"],
            predictedCellIDs: ["h3-cell-02", "h3-cell-03"],
            allowsSilentPredictedToConfirmedPromotion: true
        )
        let snapshot = MapVisualMV01ToMV41ComplianceAudit.AuditSnapshot(
            personalFogState: violatedFogState
        )
        let report = MapVisualMV01ToMV41ComplianceAudit.evaluate(snapshot)
        XCTAssertFalse(report.isFullyCompliant)
        XCTAssertEqual(
            report.failures,
            [
                .revealSyncDefaultNotOff,
                .revealSyncEnabledWithoutExplicitUserConsent,
                .overlappingOrUnseparatedFogCells(overlap: ["h3-cell-02"]),
                .silentPredictedToConfirmedPromotionAllowed
            ]
        )
    }

    func testMarkerStateVisualProjectionsAndWCAGContrastGuard() {
        let lockedProjection = MapVisualMV01ToMV41ComplianceAudit.canonicalProjection(for: .locked)
        let activeProjection = MapVisualMV01ToMV41ComplianceAudit.canonicalProjection(for: .active)
        let unavailableProjection = MapVisualMV01ToMV41ComplianceAudit.canonicalProjection(for: .unavailable)

        XCTAssertFalse(lockedProjection.isActionable)
        XCTAssertTrue(activeProjection.isActionable)
        XCTAssertTrue(activeProjection.showsPulseRing)
        XCTAssertFalse(unavailableProjection.isActionable)
        XCTAssertGreaterThanOrEqual(activeProjection.hitTargetPoints, 44.0)

        let lowContrastSnapshot = MapVisualMV01ToMV41ComplianceAudit.AuditSnapshot(
            primaryLabelContrastRatio: 3.8,
            secondaryBadgeContrastRatio: 4.1
        )
        let report = MapVisualMV01ToMV41ComplianceAudit.evaluate(lowContrastSnapshot)
        XCTAssertFalse(report.isFullyCompliant)
        XCTAssertEqual(
            report.failures,
            [.insufficientContrastRatio(primary: 3.8, secondary: 4.1, minimumRequired: 4.5)]
        )
    }
}

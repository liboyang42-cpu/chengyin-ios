import SwiftUI
import XCTest
#if canImport(Questify)
@testable import Questify
#elseif canImport(QuestifyApp)
@testable import QuestifyApp
#endif
#if canImport(QuestifyCore)
@testable import QuestifyCore
#endif

@MainActor final class MapVisualMV01ToMV41ComplianceSectionViewTests: XCTestCase {
    func testStandardSnapshotCoversAllFortyOneMVItemsAndEnforcesContrastLayerOrderDatumAndFogGates() {
        let snapshot = MapVisualMV01ToMV41Snapshot.standard
        XCTAssertEqual(snapshot.totalMVItems, 41)
        XCTAssertEqual(snapshot.compliantMVItems, 41)
        XCTAssertTrue(snapshot.isFullyCompliant)
        XCTAssertEqual(snapshot.contrastShortfallCount, 0)
        XCTAssertTrue(snapshot.bottomToTopLayerOrderVerified)
        XCTAssertEqual(snapshot.distinctMarkerStateCount, 8)
        XCTAssertFalse(snapshot.allowsDoubleDatumProjection)
        XCTAssertFalse(snapshot.allowsCrossDatumDistance)
        XCTAssertFalse(snapshot.personalFogRevealSyncEnabled)

        let flattenedCodes = snapshot.domains.flatMap(\.itemCodes)
        XCTAssertEqual(flattenedCodes.count, 41)
        XCTAssertEqual(flattenedCodes, MapVisualComplianceDomainRow.allMVCodes)
        XCTAssertEqual(flattenedCodes.first, "MV01")
        XCTAssertEqual(flattenedCodes.last, "MV41")
        XCTAssertTrue(snapshot.domains.allSatisfy(\.isFullyCompliant))

        let view = MapVisualMV01ToMV41ComplianceSectionView(snapshot: snapshot)
        _ = view.body
    }

    func testNonCompliantSnapshotStatesAreDetectedAndRenderedCleanly() {
        let contrastShortfallSnapshot = MapVisualMV01ToMV41Snapshot(
            contrastShortfallCount: 1
        )
        XCTAssertFalse(contrastShortfallSnapshot.isFullyCompliant)
        _ = MapVisualMV01ToMV41ComplianceSectionView(snapshot: contrastShortfallSnapshot).body

        let datumViolationSnapshot = MapVisualMV01ToMV41Snapshot(
            allowsDoubleDatumProjection: true,
            allowsCrossDatumDistance: true
        )
        XCTAssertFalse(datumViolationSnapshot.isFullyCompliant)
        _ = MapVisualMV01ToMV41ComplianceSectionView(snapshot: datumViolationSnapshot).body

        let fogSyncEnabledSnapshot = MapVisualMV01ToMV41Snapshot(
            personalFogRevealSyncEnabled: true
        )
        XCTAssertFalse(fogSyncEnabledSnapshot.isFullyCompliant)
        _ = MapVisualMV01ToMV41ComplianceSectionView(snapshot: fogSyncEnabledSnapshot).body
    }
}

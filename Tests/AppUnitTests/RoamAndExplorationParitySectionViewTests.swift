#if canImport(QuestifyApp)
@testable import QuestifyApp
#else
@testable import Questify
#endif
#if canImport(QuestifyCore)
import QuestifyCore
#endif
import XCTest

@MainActor
final class RoamAndExplorationParitySectionViewTests: XCTestCase {
    func testDefaultVerifiedSnapshotRendersAllFiveRoamAndExplorationPillars() {
        let view = RoamAndExplorationParitySectionView()
        _ = view.body

        let snapshot = view.snapshot
        XCTAssertEqual(snapshot.pillars.count, 5)
        XCTAssertEqual(
            snapshot.pillars.map(\.id),
            RoamAndExplorationParitySnapshot.canonicalPillarIDs
        )
        XCTAssertEqual(
            snapshot.pillars.map(\.code),
            ["w2-08", "w2-09", "I00+I11", "I01", "F-W14/W15"]
        )
        XCTAssertTrue(snapshot.isAllParityVerified)
        XCTAssertEqual(snapshot.verifiedCount, 5)
        XCTAssertEqual(snapshot.blockedCount, 0)
        XCTAssertEqual(snapshot.gpsMaxHorizontalAccuracyMeters, 50)
        XCTAssertTrue(snapshot.personalFogLocalOnly)
        XCTAssertTrue(snapshot.unmountedWriteRoutesFailClosed)
        XCTAssertEqual(view.summaryBadgeText, "PARITY VERIFIED (5/5)")

        for row in snapshot.pillars {
            XCTAssertEqual(row.rowAccessibilityIdentifier, "roamExplorationAudit.pillar.\(row.id)")
            XCTAssertEqual(row.statusAccessibilityIdentifier, "roamExplorationAudit.status.\(row.id)")
        }
        XCTAssertEqual(snapshot.pillar(id: "w2_09_private_tools")?.status, .guardedReadOnly)
    }

    func testBlockedPillarAndGuardrailViolationSnapshotStates() {
        let degraded = RoamAndExplorationParitySnapshot.withBlockedPillars(
            ["I01", "f_w14_w15_story_walking_personal_fog"],
            gpsMaxHorizontalAccuracyMeters: 120,
            personalFogLocalOnly: false,
            unmountedWriteRoutesFailClosed: false
        )

        var selectedRow: RoamExplorationPillarRow?
        let view = RoamAndExplorationParitySectionView(
            snapshot: degraded,
            onSelectPillar: { selectedRow = $0 }
        )
        _ = view.body

        XCTAssertFalse(degraded.isAllParityVerified)
        XCTAssertEqual(degraded.verifiedCount, 3)
        XCTAssertEqual(degraded.blockedCount, 2)
        XCTAssertEqual(view.summaryBadgeText, "ATTENTION (3/5 READY)")
        XCTAssertEqual(degraded.pillar(id: "i01_gps_arrival_accuracy")?.status, .blocked)
        XCTAssertEqual(degraded.pillar(id: "f_w14_w15_story_walking_personal_fog")?.status, .blocked)

        if let first = degraded.pillars.first {
            view.onSelectPillar?(first)
            XCTAssertEqual(selectedRow, first)
        }
    }
}

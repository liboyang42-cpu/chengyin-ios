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

@MainActor final class WorldAndCityLifecycleSectionViewTests: XCTestCase {
    func testStandardSnapshotCoversAllThreePillarsAndRedactsDescription() {
        let snapshot = WorldAndCityLifecycleSnapshot.standard
        XCTAssertEqual(snapshot.pillars.count, 3)
        XCTAssertEqual(snapshot.verifiedPillarCount, 3)
        XCTAssertTrue(snapshot.allPillarsVerified)
        XCTAssertTrue(snapshot.cityAcceptsNewActions)
        XCTAssertEqual(
            snapshot.pillars.map(\.code),
            ["G-W05.5", "H-W19", "H-W20"]
        )
        XCTAssertEqual(
            snapshot.pillars.map(\.kind),
            [
                .environmentBranchSnapshotIsolation,
                .privateHomeReturnRestore,
                .cityActionAndDeltaStream,
            ]
        )
        XCTAssertEqual(String(describing: snapshot), "WorldAndCityLifecycleSnapshot[redacted]")
        XCTAssertEqual(String(reflecting: snapshot), "WorldAndCityLifecycleSnapshot[redacted]")

        let view = WorldAndCityLifecycleSectionView(snapshot: snapshot)
        _ = view.body
    }

    func testCustomSnapshotStatesReflectBranchLeakageFrozenBoardAndInFlightOrDeltaGapLocks() {
        let frozenSnapshot = WorldAndCityLifecycleSnapshot(
            environmentBranchID: "env-branch-staging-v2",
            snapshotPinnedRevision: 19,
            crossBranchLeakageDetected: true,
            homeReturnScopeLabel: "RUN:run-9:stamina",
            homeReturnRetryableNow: true,
            cityBoardLifecycleCode: "FROZEN",
            cityDeltaSequence: 40,
            cityNeedsSnapshotReload: false,
            citySingleInFlightLocked: false
        )
        XCTAssertFalse(frozenSnapshot.allPillarsVerified)
        XCTAssertFalse(frozenSnapshot.cityAcceptsNewActions)
        _ = WorldAndCityLifecycleSectionView(snapshot: frozenSnapshot).body

        let reloadLockedSnapshot = WorldAndCityLifecycleSnapshot(
            cityBoardLifecycleCode: "OPEN",
            cityDeltaSequence: 41,
            cityNeedsSnapshotReload: true,
            citySingleInFlightLocked: true
        )
        XCTAssertTrue(reloadLockedSnapshot.allPillarsVerified)
        XCTAssertFalse(reloadLockedSnapshot.cityAcceptsNewActions)
        _ = WorldAndCityLifecycleSectionView(snapshot: reloadLockedSnapshot).body
    }
}

import XCTest
@testable import QuestifyCore

final class MapCoreEntryHostRouterTests: XCTestCase {
    func testExistingEntriesRouteToHostDestinations() {
        XCTAssertEqual(MapCoreEntryHostRouter.resolve(.placeInfo), .searchMap)
        XCTAssertEqual(MapCoreEntryHostRouter.resolve(.freeExploration), .roam)
        XCTAssertEqual(MapCoreEntryHostRouter.resolve(.cityOrienteering), .walkingNavigation)

        XCTAssertTrue(MapCoreEntryHostRouter.isEnabled(.placeInfo))
        XCTAssertTrue(MapCoreEntryHostRouter.isEnabled(.freeExploration))
        XCTAssertTrue(MapCoreEntryHostRouter.isEnabled(.cityOrienteering))

        XCTAssertNil(MapCoreEntryHostRouter.blockedReason(for: .placeInfo))
        XCTAssertNil(MapCoreEntryHostRouter.blockedReason(for: .freeExploration))
        XCTAssertNil(MapCoreEntryHostRouter.blockedReason(for: .cityOrienteering))
    }

    func testPendingEntriesRemainBlockedWithExplicitReasonCopy() {
        let pendingEntries: [MapCoreEntry] = [
            .merchantSideQuests,
            .personalFog,
            .sharedLocation,
            .cityOperation
        ]

        for entry in pendingEntries {
            XCTAssertNotEqual(entry.availability, .existing)
            XCTAssertFalse(MapCoreEntryHostRouter.isEnabled(entry))

            let destination = MapCoreEntryHostRouter.resolve(entry)
            XCTAssertTrue(destination.isBlocked)

            let reason = MapCoreEntryHostRouter.blockedReason(for: entry)
            XCTAssertNotNil(reason)
            XCTAssertFalse((reason ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            XCTAssertEqual(destination, .blockedWithReason(reason ?? ""))
        }

        XCTAssertTrue(MapCoreEntryHostRouter.blockedReason(for: .merchantSideQuests)?.contains("W14") == true)
        XCTAssertTrue(MapCoreEntryHostRouter.blockedReason(for: .personalFog)?.contains("W14.6") == true)
        XCTAssertTrue(MapCoreEntryHostRouter.blockedReason(for: .sharedLocation)?.contains("W13.5") == true)
        XCTAssertTrue(MapCoreEntryHostRouter.blockedReason(for: .cityOperation)?.contains("W20") == true)
    }

    func testRouterSelectionAndResetTrackHostState() {
        var router = MapCoreEntryHostRouter()
        XCTAssertNil(router.lastSelectedEntry)
        XCTAssertNil(router.activeDestination)

        let roamDestination = router.select(.freeExploration)
        XCTAssertEqual(roamDestination, .roam)
        XCTAssertEqual(router.lastSelectedEntry, .freeExploration)
        XCTAssertEqual(router.activeDestination, .roam)
        XCTAssertFalse(roamDestination.isBlocked)

        let cityDestination = router.select(.cityOperation)
        XCTAssertTrue(cityDestination.isBlocked)
        XCTAssertEqual(router.lastSelectedEntry, .cityOperation)
        XCTAssertEqual(router.activeDestination, cityDestination)

        router.reset()
        XCTAssertNil(router.lastSelectedEntry)
        XCTAssertNil(router.activeDestination)
    }

    func testAllMapCoreEntriesAreCoveredDeterministically() {
        for entry in MapCoreEntry.allCases {
            let destination = MapCoreEntryHostRouter.resolve(entry)
            switch entry.availability {
            case .existing:
                XCTAssertFalse(destination.isBlocked)
                XCTAssertTrue(MapCoreEntryHostRouter.isEnabled(entry))
            case .pendingBackend, .pendingDecision:
                XCTAssertTrue(destination.isBlocked)
                XCTAssertFalse(MapCoreEntryHostRouter.isEnabled(entry))
            }
        }
    }
}

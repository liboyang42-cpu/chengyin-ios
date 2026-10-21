import XCTest
@testable import QuestifyCore

final class DeviceOrientationAndSplitViewAdaptationAuditTests: XCTestCase {
    func testCanonicalScreenGroupsPassLayoutAdaptationAudit() {
        let checks = DeviceOrientationAndSplitViewAdaptationAudit.canonicalChecks
        XCTAssertEqual(checks.count, 4)
        XCTAssertTrue(checks.allSatisfy(\.isCompliant))
        XCTAssertEqual(
            checks.map(\.screenGroup),
            [
                "map-and-roam-hud-overlay",
                "npc-and-im-chat-input-bars",
                "publish-and-shop-apply-forms",
                "profile-and-workbench-split-containers"
            ]
        )

        let result = DeviceOrientationAndSplitViewAdaptationAudit.evaluate()
        XCTAssertEqual(result.totalGroups, 4)
        XCTAssertEqual(result.compliantGroups, 4)
        XCTAssertTrue(result.isLayoutAdaptationReady)
    }

    func testSafeAreaClippingInDynamicIslandOrHomeIndicatorFailsAudit() {
        var checks = DeviceOrientationAndSplitViewAdaptationAudit.canonicalChecks
        checks[0] = DeviceLayoutAdaptationCheck(
            id: "map-and-roam-hud-overlay",
            screenGroup: "map-and-roam-hud-overlay",
            preservesDynamicIslandAndHomeIndicatorSafeArea: false,
            avoidsKeyboardOverlapInInputBars: true,
            adaptsCompactAndRegularWidthCleanly: true
        )

        XCTAssertFalse(checks[0].isCompliant)
        let result = DeviceOrientationAndSplitViewAdaptationAudit.evaluate(checks: checks)
        XCTAssertEqual(result.totalGroups, 4)
        XCTAssertEqual(result.compliantGroups, 3)
        XCTAssertFalse(result.isLayoutAdaptationReady)
    }

    func testKeyboardOverlapInChatOrFormInputBarsFailsAudit() {
        var checks = DeviceOrientationAndSplitViewAdaptationAudit.canonicalChecks
        checks[1] = DeviceLayoutAdaptationCheck(
            id: "npc-and-im-chat-input-bars",
            screenGroup: "npc-and-im-chat-input-bars",
            preservesDynamicIslandAndHomeIndicatorSafeArea: true,
            avoidsKeyboardOverlapInInputBars: false,
            adaptsCompactAndRegularWidthCleanly: true
        )

        XCTAssertFalse(checks[1].isCompliant)
        let result = DeviceOrientationAndSplitViewAdaptationAudit.evaluate(checks: checks)
        XCTAssertEqual(result.totalGroups, 4)
        XCTAssertEqual(result.compliantGroups, 3)
        XCTAssertFalse(result.isLayoutAdaptationReady)
    }

    func testCompactAndRegularWidthAdaptationFailureIsDetected() {
        var checks = DeviceOrientationAndSplitViewAdaptationAudit.canonicalChecks
        checks[3] = DeviceLayoutAdaptationCheck(
            id: "profile-and-workbench-split-containers",
            screenGroup: "profile-and-workbench-split-containers",
            preservesDynamicIslandAndHomeIndicatorSafeArea: true,
            avoidsKeyboardOverlapInInputBars: true,
            adaptsCompactAndRegularWidthCleanly: false
        )

        XCTAssertFalse(checks[3].isCompliant)
        let result = DeviceOrientationAndSplitViewAdaptationAudit.evaluate(checks: checks)
        XCTAssertEqual(result.totalGroups, 4)
        XCTAssertEqual(result.compliantGroups, 3)
        XCTAssertFalse(result.isLayoutAdaptationReady)
    }
}

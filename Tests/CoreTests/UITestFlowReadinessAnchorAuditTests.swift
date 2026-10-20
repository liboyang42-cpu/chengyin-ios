import XCTest
@testable import QuestifyCore

final class UITestFlowReadinessAnchorAuditTests: XCTestCase {
    func testAllFiveFlowSurfacesArePresentAndReadyByDefault() {
        let audit = UITestFlowReadinessAnchorAudit()
        XCTAssertTrue(audit.isAllReady)
        XCTAssertTrue(audit.missingSurfaces.isEmpty)
        XCTAssertTrue(audit.invalidSurfaces.isEmpty)
        XCTAssertEqual(audit.anchors.map(\.surface), [
            .projectEditor,
            .profileSelfEdit,
            .roamFinishedHistory,
            .couponRuntimeJourney,
            .mapCoreEntry
        ])
    }

    func testProjectEditorRequiresOffScreenRevealHelperContract() throws {
        let audit = UITestFlowReadinessAnchorAudit()
        let projectEditor = try XCTUnwrap(audit.anchor(for: .projectEditor))
        XCTAssertTrue(projectEditor.requiresFormRevealBeforeTyping)
        XCTAssertEqual(projectEditor.offScreenRevealHelper, "revealProjectEditorNameInForm")
        XCTAssertTrue(projectEditor.isAnchorValid)

        let missingHelperRecord = UITestFlowReadinessAnchorRecord(
            surface: .projectEditor,
            readinessAnchorIdentifier: "projectEdit.form.name",
            launchArgument: "--uitesting-project-editor",
            offScreenRevealHelper: nil,
            requiresFormRevealBeforeTyping: true
        )
        XCTAssertFalse(missingHelperRecord.isAnchorValid)
    }

    func testMapCoreEntryAndOtherSurfacesHaveDeterministicLaunchFlagsAndIdentifiers() throws {
        let audit = UITestFlowReadinessAnchorAudit()
        let mapCore = try XCTUnwrap(audit.anchor(for: .mapCoreEntry))
        XCTAssertEqual(mapCore.launchArgument, "--uitesting-map-core-entry")
        XCTAssertEqual(mapCore.readinessAnchorIdentifier, "mapCore.entry.cityOrienteering")

        let profileSelfEdit = try XCTUnwrap(audit.anchor(for: .profileSelfEdit))
        XCTAssertFalse(profileSelfEdit.readinessAnchorIdentifier.isEmpty)
        XCTAssertFalse(profileSelfEdit.requiresFormRevealBeforeTyping)

        let roamHistory = try XCTUnwrap(audit.anchor(for: .roamFinishedHistory))
        XCTAssertFalse(roamHistory.readinessAnchorIdentifier.isEmpty)

        let couponJourney = try XCTUnwrap(audit.anchor(for: .couponRuntimeJourney))
        XCTAssertFalse(couponJourney.readinessAnchorIdentifier.isEmpty)
    }

    func testMissingOrEmptyAnchorIsDetectedByAudit() {
        let droppedLast = UITestFlowReadinessAnchorAudit(
            anchors: Array(UITestFlowReadinessAnchorAudit.defaultAnchors.dropLast())
        )
        XCTAssertFalse(droppedLast.isAllReady)
        XCTAssertEqual(droppedLast.missingSurfaces, [.mapCoreEntry])

        var corrupted = UITestFlowReadinessAnchorAudit.defaultAnchors
        corrupted[1] = UITestFlowReadinessAnchorRecord(
            surface: .profileSelfEdit,
            readinessAnchorIdentifier: "   ",
            launchArgument: "--uitesting-profile-self-edit"
        )
        let corruptedAudit = UITestFlowReadinessAnchorAudit(anchors: corrupted)
        XCTAssertFalse(corruptedAudit.isAllReady)
        XCTAssertEqual(corruptedAudit.invalidSurfaces, [.profileSelfEdit])
    }
}

import XCTest
import SwiftUI
#if canImport(QuestifyApp)
@testable import QuestifyApp
#if canImport(QuestifyCore)
import QuestifyCore
#elseif canImport(Core)
import Core
#endif
#else
@testable import Questify
#endif

@MainActor
final class DeviceOrientationAndSplitViewAdaptationSectionViewTests: XCTestCase {
    func testDefaultReadySnapshotVerifiesSafeAreaKeyboardAndSizeClassAdaptation() {
        let snapshot = DeviceLayoutAdaptationSnapshot.defaultReady
        XCTAssertTrue(snapshot.isAllAdapted)
        XCTAssertEqual(snapshot.rows.count, 3)
        XCTAssertEqual(snapshot.rows.map(\.groupCode), ["LAYOUT-01", "LAYOUT-02", "LAYOUT-03"])
        XCTAssertTrue(snapshot.safeAreaInsetsPreserved)
        XCTAssertTrue(snapshot.keyboardAvoidanceVerified)
        XCTAssertTrue(snapshot.compactAndRegularAdapted)

        for row in snapshot.rows {
            XCTAssertTrue(row.isCompliant)
            XCTAssertEqual(row.statusBadgeText, "ADAPTED • VERIFIED")
        }
    }

    func testSafeAreaOrKeyboardOverlapWarningStateSurfacesNonCompliantStrings() {
        var modifiedRows = DeviceLayoutAdaptationSnapshot.defaultRows
        modifiedRows[1] = DeviceLayoutGroupRow(
            id: "layout-02-keyboard-avoidance",
            groupCode: "LAYOUT-02",
            title: "Form & Composer Keyboard Avoidance",
            adaptationSummary: "Keyboard overlaps review button",
            isCompliant: false
        )
        let warningSnapshot = DeviceLayoutAdaptationSnapshot(
            rows: modifiedRows,
            safeAreaInsetsPreserved: false,
            keyboardAvoidanceVerified: false,
            compactAndRegularAdapted: false
        )
        let view = DeviceOrientationAndSplitViewAdaptationSectionView(snapshot: warningSnapshot)

        XCTAssertFalse(view.snapshot.isAllAdapted)
        XCTAssertEqual(
            view.statusBadgeText,
            "Device Layout Gate: WARNING (Safe Area / Keyboard Overlap)"
        )
        XCTAssertEqual(
            view.safeAreaSummaryText,
            "Safe Area Preservation: WARNING — interactive control clipped by system inset"
        )
        XCTAssertEqual(
            view.keyboardAvoidanceSummaryText,
            "Keyboard Avoidance: WARNING — primary input or review CTA obscured by keyboard"
        )
        XCTAssertEqual(
            view.sizeClassSummaryText,
            "Size Class & Split View: WARNING — regular-width popover/split layout mismatch"
        )
        XCTAssertEqual(view.snapshot.rows[1].statusBadgeText, "OVERLAP • REVIEW REQUIRED")
    }

    func testMainActorViewBodyInstantiationAndDefaultPresentationStrings() {
        let view = DeviceOrientationAndSplitViewAdaptationSectionView()
        _ = view.body

        XCTAssertEqual(
            view.statusBadgeText,
            "Device Layout Gate: READY (3/3 Groups Adapted)"
        )
        XCTAssertEqual(
            view.safeAreaSummaryText,
            "Safe Area Preservation: Verified (Dynamic Island & Home Indicator insets respected)"
        )
        XCTAssertEqual(
            view.keyboardAvoidanceSummaryText,
            "Keyboard Avoidance: Verified (Unobscured Form rows & bounded off-screen reveal)"
        )
        XCTAssertEqual(
            view.sizeClassSummaryText,
            "Size Class & Split View: Compact/Regular iPhone & iPad orientations adapted"
        )
    }
}

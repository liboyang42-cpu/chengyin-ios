import XCTest
import SwiftUI
#if canImport(QuestifyApp)
@testable import QuestifyApp
import QuestifyCore
#else
@testable import Questify
#endif

@MainActor
final class TestFlightInternalAndExternalSmokeSectionViewTests: XCTestCase {
    func testDefaultReadySnapshotVerifiesAllSixDayFiveTestFlightSmokeJourneys() {
        let snapshot = TestFlightSmokeMatrixSnapshot.defaultReady
        XCTAssertTrue(snapshot.isAllSmokePassed)
        XCTAssertEqual(snapshot.rows.count, 6)
        XCTAssertEqual(snapshot.passedJourneyCount, 6)
        XCTAssertEqual(
            snapshot.rows.map(\.journeyCode),
            ["TF-01", "TF-02", "TF-03", "TF-04", "TF-05", "TF-06"]
        )
        XCTAssertTrue(snapshot.internalTrackCleared)
        XCTAssertTrue(snapshot.externalBetaReviewReady)

        for row in snapshot.rows {
            XCTAssertTrue(row.isSmokePassed)
            XCTAssertTrue(row.isFailClosedVerified)
            XCTAssertEqual(row.statusBadgeText, "PASSED • FAIL-CLOSED")
        }
    }

    func testFailedSmokeJourneySnapshotSurfacesHoldPromotionWarningState() {
        var modifiedRows = TestFlightSmokeMatrixSnapshot.defaultRows
        modifiedRows[3] = TestFlightSmokeJourneyRow(
            id: "tf-smoke-04-play-scanner-audio",
            journeyCode: "TF-04",
            title: "Play Session, GCJ-02 Arrival, VisionKit Scanner & Audio",
            verificationSteps: "Audio interruption did not resume",
            isSmokePassed: false,
            isFailClosedVerified: true
        )
        let failedSnapshot = TestFlightSmokeMatrixSnapshot(
            rows: modifiedRows,
            internalTrackCleared: false,
            externalBetaReviewReady: false
        )
        let view = TestFlightInternalAndExternalSmokeSectionView(snapshot: failedSnapshot)

        XCTAssertFalse(view.snapshot.isAllSmokePassed)
        XCTAssertEqual(view.snapshot.passedJourneyCount, 5)
        XCTAssertEqual(
            view.statusBadgeText,
            "TestFlight Smoke Gate: WARNING (5/6 Journeys Passed)"
        )
        XCTAssertEqual(
            view.trackSummaryText,
            "Internal Track: BLOCKED • External Beta Review: HOLD"
        )
        XCTAssertEqual(
            view.deviceCoverageBannerText,
            "Day-5 Real-Device Smoke Matrix: HOLD PROMOTION — Failed Smoke Journey Detected"
        )
        XCTAssertEqual(view.snapshot.rows[3].statusBadgeText, "FAILED • HOLD EXTERNAL")
    }

    func testMainActorViewBodyInstantiationAndDefaultPresentationStrings() {
        let view = TestFlightInternalAndExternalSmokeSectionView()
        _ = view.body

        XCTAssertEqual(
            view.statusBadgeText,
            "TestFlight Smoke Gate: READY (6/6 Journeys Passed)"
        )
        XCTAssertEqual(
            view.trackSummaryText,
            "Internal Track: CLEARED • External Beta Review: READY"
        )
        XCTAssertEqual(
            view.deviceCoverageBannerText,
            "Day-5 Real-Device Smoke Matrix: All 6 Journeys Verified & Fail-Closed"
        )
    }
}

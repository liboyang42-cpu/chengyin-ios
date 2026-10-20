import XCTest
import SwiftUI
#if canImport(QuestifyApp)
@testable import QuestifyApp
import QuestifyCore
#else
@testable import Questify
#endif

@MainActor
final class EndToEndReleaseCandidateGateSectionViewTests: XCTestCase {
    func testFailClosedDefaultSnapshotRendersAllSixRCGatesGreen() {
        let view = EndToEndReleaseCandidateGateSectionView()
        _ = view.body

        XCTAssertTrue(view.snapshot.isAllGatesGreen)
        XCTAssertEqual(view.snapshot.gates.count, 6)
        XCTAssertEqual(view.snapshot.passedGateCount, 6)
        XCTAssertEqual(
            view.snapshot.gates.map(\.gateCode),
            ["RC-GATE-01", "RC-GATE-02", "RC-GATE-03", "RC-GATE-04", "RC-GATE-05", "RC-GATE-06"]
        )

        XCTAssertEqual(view.summaryBadgeText, "RC Gates: 6/6 PASS")
        XCTAssertEqual(view.archiveModeBannerText, "Profile: CN • Mode: CI_SAFE_UNSIGNED_DEFAULT")
        XCTAssertEqual(
            view.failClosedBannerText,
            "End-to-End RC Gate Status: ALL 6 GATES VERIFIED & FAIL-CLOSED"
        )

        for gate in view.snapshot.gates {
            XCTAssertTrue(gate.isPassed)
            XCTAssertTrue(gate.isFailClosed)
            XCTAssertEqual(gate.statusBadgeText, "PASS • FAIL-CLOSED")
        }
    }

    func testBlockedGateInSnapshotMarksArchiveOnHoldAndReportsExactPassCount() {
        var modifiedGates = EndToEndReleaseCandidateSnapshot.defaultGates
        modifiedGates[2] = ReleaseCandidateGateRow(
            id: "RC-GATE-03",
            gateCode: "RC-GATE-03",
            title: "Approved HTTPS API Base URL",
            requirementSummary: "Unapproved host detected",
            isPassed: false,
            isFailClosed: true
        )
        let blockedSnapshot = EndToEndReleaseCandidateSnapshot(
            gates: modifiedGates,
            candidateMarket: "US",
            isSafeCIDefaultProfile: false
        )
        let view = EndToEndReleaseCandidateGateSectionView(snapshot: blockedSnapshot)
        _ = view.body

        XCTAssertFalse(view.snapshot.isAllGatesGreen)
        XCTAssertEqual(view.snapshot.passedGateCount, 5)
        XCTAssertEqual(view.summaryBadgeText, "RC Gates: 5/6 PASS (BLOCKED)")
        XCTAssertEqual(view.archiveModeBannerText, "Profile: US • Mode: ARCHIVE_CANDIDATE_OVERRIDE")
        XCTAssertEqual(
            view.failClosedBannerText,
            "End-to-End RC Gate Status: HOLD ARCHIVE — UNRESOLVED GATE VIOLATION"
        )
        XCTAssertEqual(view.snapshot.gates[2].statusBadgeText, "BLOCKED • ACTION REQUIRED")
    }
}

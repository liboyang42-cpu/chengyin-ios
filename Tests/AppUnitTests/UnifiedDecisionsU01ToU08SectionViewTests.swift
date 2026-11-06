import XCTest
import SwiftUI
@testable import Questify
#if canImport(QuestifyCore)
@testable import QuestifyCore
#endif

@MainActor
final class UnifiedDecisionsU01ToU08SectionViewTests: XCTestCase {

    func testDefaultInstantiationAndEightVerifiedUnifiedDecisions() {
        let view = UnifiedDecisionsU01ToU08SectionView()
        _ = view.body

        XCTAssertEqual(view.snapshot.decisions.count, 8)
        XCTAssertEqual(view.snapshot.verifiedDecisionCount, 8)
        XCTAssertFalse(view.snapshot.nfcHandshakeEnabled)
        XCTAssertFalse(view.snapshot.h5RuntimeEnabled)
        XCTAssertTrue(view.snapshot.allDecisionsVerified)

        XCTAssertEqual(view.decisionCodesText, "U01, U02, U03, U04, U05, U06, U07, U08")
        XCTAssertEqual(view.headerBadgeText, "U01–U08 DECISIONS VERIFIED (8/8)")
        XCTAssertEqual(
            view.overallSummaryText,
            "Unified Decisions (U01–U08): 8/8 VERIFIED · NFC: OFF · H5: DESIGN-ONLY (OFF)"
        )
    }

    func testAllEightDecisionTitlesAndFailClosedGates() {
        let view = UnifiedDecisionsU01ToU08SectionView()
        let codes = view.snapshot.decisions.map(\.code)
        XCTAssertEqual(codes, (1...8).map { String(format: "U%02d", $0) })

        for decision in view.snapshot.decisions {
            XCTAssertEqual(decision.statusBadgeText, "VERIFIED · FAIL-CLOSED")
            XCTAssertTrue(decision.summaryLineText.hasPrefix(decision.code))
            XCTAssertFalse(decision.invariantSummary.isEmpty)
            XCTAssertFalse(decision.failClosedGateSummary.isEmpty)
        }
    }

    func testDriftSnapshotWhenDecisionUnverifiedOrNFCOrH5Enabled() {
        var customDecisions = UnifiedDecisionsU01ToU08Snapshot.defaultDecisions
        customDecisions[6] = UnifiedDecisionAuditRow(
            id: "U07-dynamic-qr-nfc-disabled",
            code: "U07",
            title: "U07 Dynamic QR Handshake with NFC Permanently Disabled",
            invariantSummary: "NFC capability unexpectedly toggled",
            failClosedGateSummary: "VIOLATION: meetingNFC must stay OFF",
            isVerified: false
        )
        let snapshot = UnifiedDecisionsU01ToU08Snapshot(
            decisions: customDecisions,
            nfcHandshakeEnabled: true,
            h5RuntimeEnabled: true
        )
        let view = UnifiedDecisionsU01ToU08SectionView(snapshot: snapshot)
        _ = view.body

        XCTAssertFalse(view.snapshot.allDecisionsVerified)
        XCTAssertEqual(view.headerBadgeText, "DECISION DRIFT (7/8)")
        XCTAssertEqual(
            view.overallSummaryText,
            "Unified Decisions (U01–U08): 7/8 VERIFIED · NFC: ON (UNSAFE) · H5: ON (UNSAFE)"
        )
        XCTAssertEqual(view.snapshot.decisions[6].statusBadgeText, "VIOLATION")
    }
}

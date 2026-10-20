import XCTest
import SwiftUI
@testable import Questify
#if canImport(QuestifyCore)
@testable import QuestifyCore
#endif

@MainActor
final class BackendSyncAndContractGateSectionViewTests: XCTestCase {

    func testDefaultInstantiationAndFourContractGatePillars() {
        let view = BackendSyncAndContractGateSectionView()
        _ = view.body

        XCTAssertEqual(view.snapshot.pillars.count, 4)
        XCTAssertEqual(view.snapshot.passingPillarCount, 4)
        XCTAssertEqual(view.snapshot.contractCheckSuiteCount, 8)
        XCTAssertEqual(view.snapshot.bkSyncItemCount, 8)
        XCTAssertEqual(view.snapshot.ciLedgerVerdict, "PASS_CURRENT_SOURCE_LEDGER")
        XCTAssertTrue(view.snapshot.allGatesPassing)

        XCTAssertEqual(view.pillarScopeCodesText, "BK, w2-21, ContractChecks, CI-Manifest")
        XCTAssertEqual(view.headerBadgeText, "CONTRACT GATES GREEN (4/4)")
        XCTAssertEqual(
            view.overallSummaryText,
            "Backend & Contract Gates: 4/4 · BK Items: 8 · ContractChecks: 8/8 · Ledger: PASS_CURRENT_SOURCE_LEDGER"
        )
    }

    func testFourPillarTitlesAndEvidenceSummaries() {
        let view = BackendSyncAndContractGateSectionView()
        let titles = view.snapshot.pillars.map(\.title)
        XCTAssertEqual(
            titles,
            [
                "BK Backend Sync Contracts (8 E-Series Items)",
                "w2-21 Map Core Entry Router & Availability Catalog",
                "8 Tests/ContractChecks Source Gate Suites",
                "current_ci.py check Manifest & Scaffold Integrity"
            ]
        )

        for pillar in view.snapshot.pillars {
            XCTAssertEqual(pillar.statusBadgeText, "PASS · FAIL-CLOSED")
            XCTAssertTrue(pillar.summaryLineText.contains(pillar.scopeCode))
            XCTAssertFalse(pillar.contractRuleSummary.isEmpty)
            XCTAssertFalse(pillar.evidenceSummary.isEmpty)
        }
    }

    func testViolationSnapshotWhenPillarOrCILedgerFails() {
        var pillars = BackendSyncAndContractGateSnapshot.defaultPillars
        pillars[3] = BackendContractGatePillarRow(
            id: "CI-current-ci-manifest",
            scopeCode: "CI-Manifest",
            title: "current_ci.py check Manifest & Scaffold Integrity",
            contractRuleSummary: "Manifest drift detected",
            evidenceSummary: "STALE_MANIFEST",
            isPassing: false
        )
        let snapshot = BackendSyncAndContractGateSnapshot(
            pillars: pillars,
            contractCheckSuiteCount: 8,
            bkSyncItemCount: 8,
            ciLedgerVerdict: "STALE_MANIFEST"
        )
        let view = BackendSyncAndContractGateSectionView(snapshot: snapshot)
        _ = view.body

        XCTAssertFalse(view.snapshot.allGatesPassing)
        XCTAssertEqual(view.headerBadgeText, "CONTRACT GATE VIOLATION (3/4)")
        XCTAssertEqual(
            view.overallSummaryText,
            "Backend & Contract Gates: 3/4 · BK Items: 8 · ContractChecks: 8/8 · Ledger: STALE_MANIFEST"
        )
        XCTAssertEqual(view.snapshot.pillars[3].statusBadgeText, "GATE FAILED")
    }
}

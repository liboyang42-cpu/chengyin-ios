import XCTest
import SwiftUI
@testable import Questify
#if canImport(QuestifyCore)
@testable import QuestifyCore
#endif

@MainActor
final class UnifiedReleaseAuditHubViewTests: XCTestCase {

    func testDefaultInstantiationAndMasterReleaseAuditTotals() {
        let view = UnifiedReleaseAuditHubView()
        _ = view.body

        XCTAssertEqual(view.snapshot.batchCount, 12)
        XCTAssertEqual(view.snapshot.parallelLaneCount, 136)
        XCTAssertEqual(view.snapshot.masterDocuments, ["交接文档_20261020.md", "落地清单.md", "工单-统一实施版.md"])
        XCTAssertEqual(view.snapshot.miniProgramPageCount, 99)
        XCTAssertEqual(view.snapshot.wave2ScopeCount, 21)
        XCTAssertEqual(view.snapshot.wave3LaneCount, 13)
        XCTAssertEqual(view.snapshot.reformPackageCount, 19)
        XCTAssertEqual(view.snapshot.unifiedDecisionCount, 8)
        XCTAssertEqual(view.snapshot.mapVisualItemCount, 41)
        XCTAssertTrue(view.snapshot.isAllGreen)

        XCTAssertEqual(view.headerBadgeText, "UNIFIED RELEASE AUDIT READY (136 LANES)")
        XCTAssertEqual(
            view.overallSummaryText,
            "Batches: 12 (136 Parallel Lanes) · Pages: 99 · Wave-2: 21 · Wave-3: 13 · Reform: 19 · Decisions: 8 · MV: 41"
        )
        XCTAssertEqual(
            view.masterDocumentsSummaryText,
            "Master Docs (3): 交接文档_20261020.md, 落地清单.md, 工单-统一实施版.md"
        )
    }

    func testFiveDomainCardsCoverAllGovernancePillars() {
        let view = UnifiedReleaseAuditHubView()
        XCTAssertEqual(view.snapshot.domainCards.count, 5)
        XCTAssertEqual(view.snapshot.verifiedCardCount, 5)

        for card in view.snapshot.domainCards {
            XCTAssertEqual(card.statusBadgeText, "VERIFIED · FAIL-CLOSED")
            XCTAssertTrue(card.summaryLineText.contains(card.title))
            XCTAssertFalse(card.metricSummary.isEmpty)
            XCTAssertFalse(card.invariantSummary.isEmpty)
        }
    }

    func testDriftSnapshotUpdatesBadgeAndVerificationState() {
        var customCards = UnifiedReleaseAuditHubSnapshot.defaultDomainCards
        customCards[4] = ReleaseAuditHubDomainCard(
            id: "map-visual-spec",
            title: "Map Visual & Privacy Spec (MV01–MV41)",
            metricSummary: "Map Visual Items: 40/41",
            invariantSummary: "Pending contrast check",
            isVerified: false
        )
        let snapshot = UnifiedReleaseAuditHubSnapshot(
            domainCards: customCards
        )
        let view = UnifiedReleaseAuditHubView(snapshot: snapshot)
        _ = view.body

        XCTAssertFalse(view.snapshot.isAllGreen)
        XCTAssertEqual(view.headerBadgeText, "RELEASE AUDIT ATTENTION (4/5)")
        XCTAssertEqual(view.snapshot.domainCards[4].statusBadgeText, "DRIFT DETECTED")
    }
}

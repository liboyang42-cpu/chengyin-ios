import XCTest
import SwiftUI
@testable import Questify
#if canImport(QuestifyCore)
@testable import QuestifyCore
#endif

@MainActor
final class MerchantAndPublishAuthoringSectionViewTests: XCTestCase {

    func testDefaultInstantiationAndFiveAuthoringPillars() {
        let view = MerchantAndPublishAuthoringSectionView()
        _ = view.body

        XCTAssertEqual(view.snapshot.pillars.count, 5)
        XCTAssertEqual(view.snapshot.verifiedPillarCount, 5)
        XCTAssertEqual(view.snapshot.publishMediaStageCount, 7)
        XCTAssertFalse(view.snapshot.merchantPublishGateEnabled)
        XCTAssertTrue(view.snapshot.isAuditReady)

        XCTAssertEqual(view.pillarScopeCodesText, "I03, w2-17..19, G-W05, H-W02/U01, H-W18")
        XCTAssertEqual(view.headerBadgeText, "AUTHORING AUDIT READY (5/5)")
        XCTAssertEqual(
            view.overallSummaryText,
            "Merchant & Publish Pillars: 5/5 · Media Stages: 7 · Write Gate: FAIL-CLOSED (OFF)"
        )
    }

    func testFivePillarTitlesAndGateSummaries() {
        let view = MerchantAndPublishAuthoringSectionView()
        let titles = view.snapshot.pillars.map(\.title)
        XCTAssertEqual(
            titles,
            [
                "I03 Boolean Fallback & Strict Type Guard",
                "w2-17..19 Merchant Store, Marketing & Ledger Parity",
                "G-W05 In-Store Game Authoring & Two-Domain Approval",
                "H-W02/U01 7-Stage Publish Media Chain & Ownership",
                "H-W18 Workshop Mod Upgrade & Pinned Release Isolation"
            ]
        )

        for pillar in view.snapshot.pillars {
            XCTAssertEqual(pillar.statusBadgeText, "VERIFIED · FAIL-CLOSED")
            XCTAssertTrue(pillar.summaryLineText.contains(pillar.scopeCode))
            XCTAssertFalse(pillar.invariantSummary.isEmpty)
            XCTAssertFalse(pillar.gateSummary.isEmpty)
        }
    }

    func testBlockedSnapshotWhenGateOpenOrPillarUnverified() {
        var pillars = MerchantAndPublishAuthoringSnapshot.defaultPillars
        pillars[2] = MerchantPublishPillarRow(
            id: "G-W05-instore-game",
            scopeCode: "G-W05",
            title: "G-W05 In-Store Game Authoring & Two-Domain Approval",
            invariantSummary: "Self-approval detected",
            gateSummary: "Blocked by two-domain approval rule",
            isVerified: false
        )
        let snapshot = MerchantAndPublishAuthoringSnapshot(
            pillars: pillars,
            publishMediaStageCount: 7,
            merchantPublishGateEnabled: true
        )
        let view = MerchantAndPublishAuthoringSectionView(snapshot: snapshot)
        _ = view.body

        XCTAssertFalse(view.snapshot.isAuditReady)
        XCTAssertEqual(view.headerBadgeText, "AUDIT BLOCKED (4/5)")
        XCTAssertEqual(
            view.overallSummaryText,
            "Merchant & Publish Pillars: 4/5 · Media Stages: 7 · Write Gate: OPEN (UNSAFE)"
        )
        XCTAssertEqual(view.snapshot.pillars[2].statusBadgeText, "BLOCKED")
    }
}

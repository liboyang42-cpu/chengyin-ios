import XCTest
import SwiftUI
@testable import Questify
#if canImport(QuestifyCore)
@testable import QuestifyCore
#endif

@MainActor
final class OfflineDurableRecoverySectionViewTests: XCTestCase {

    func testDefaultInstantiationAndThreeDurableRecoveryPillars() {
        let view = OfflineDurableRecoverySectionView()
        _ = view.body

        XCTAssertEqual(view.snapshot.pillars.count, 3)
        XCTAssertEqual(view.snapshot.verifiedPillarCount, 3)
        XCTAssertTrue(view.snapshot.allPillarsVerified)
        XCTAssertEqual(view.pillarScopeCodesText, "I02, I06, H-W03")
        XCTAssertEqual(view.headerBadgeText, "DURABLE RECOVERY READY (3/3)")
        XCTAssertEqual(
            view.overallSummaryText,
            "Durable Recovery Pillars: 3/3 VERIFIED · AAD: <key>:game · Swept .tmp: 0"
        )
    }

    func testPillarTitlesAndSummariesCoverI02I06AndHW03() {
        let view = OfflineDurableRecoverySectionView()
        let titles = view.snapshot.pillars.map(\.title)
        XCTAssertEqual(
            titles,
            [
                "I02 AES.GCM <key>:game Command Journal",
                "I06 Audio Session Interruption & .tmp Sweep",
                "H-W03 CAS stateVersion Conflict Recovery"
            ]
        )

        for pillar in view.snapshot.pillars {
            XCTAssertEqual(pillar.statusBadgeText, "VERIFIED · FAIL-CLOSED")
            XCTAssertTrue(pillar.summaryLineText.contains(pillar.scopeCode))
            XCTAssertFalse(pillar.guaranteeSummary.isEmpty)
            XCTAssertFalse(pillar.recoveryRuleSummary.isEmpty)
        }
    }

    func testDegradedSnapshotUpdatesBadgeAndSummaryCounts() {
        var customPillars = OfflineDurableRecoverySnapshot.defaultPillars
        customPillars[1] = DurableRecoveryPillarRow(
            id: "I06-audio-tmp-sweep",
            scopeCode: "I06",
            title: "I06 Audio Session Interruption & .tmp Sweep",
            guaranteeSummary: "Pending .tmp cleanup",
            recoveryRuleSummary: "Orphan .tmp sweep queued",
            pendingEntryCount: 2,
            isVerified: false
        )
        let snapshot = OfflineDurableRecoverySnapshot(
            pillars: customPillars,
            tempArtifactsSweptCount: 4,
            journalAADFormat: "<key>:game"
        )
        let view = OfflineDurableRecoverySectionView(snapshot: snapshot)
        _ = view.body

        XCTAssertFalse(view.snapshot.allPillarsVerified)
        XCTAssertEqual(view.headerBadgeText, "RECOVERY DEGRADED (2/3)")
        XCTAssertEqual(
            view.overallSummaryText,
            "Durable Recovery Pillars: 2/3 VERIFIED · AAD: <key>:game · Swept .tmp: 4"
        )
        XCTAssertEqual(view.snapshot.pillars[1].statusBadgeText, "ATTENTION REQUIRED")
    }
}

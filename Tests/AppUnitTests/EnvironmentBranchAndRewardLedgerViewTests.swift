import SwiftUI
import XCTest
import QuestifyCore
@testable import QuestifyApp

@MainActor
final class EnvironmentBranchAndRewardLedgerViewTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private var sampleBranches: [ApprovedBranch] {
        let activeWindow = DateInterval(start: t0.addingTimeInterval(-1800), duration: 3600)
        return [
            ApprovedBranch(
                branchID: "branch-outdoor",
                window: activeWindow,
                indoor: false,
                requiresOpenStore: true,
                requiredPlaceIDs: ["place-1"],
                isDeterministicFallback: false
            ),
            ApprovedBranch(
                branchID: "branch-indoor-fallback",
                window: nil,
                indoor: true,
                requiresOpenStore: false,
                requiredPlaceIDs: [],
                isDeterministicFallback: true
            )
        ]
    }

    func testEnvironmentBranchHostSectionViewPinnedSnapshotAndClosedWindowFallback() {
        let validSnapshot = EnvironmentSnapshot(
            snapshotID: "snap-pinned-1",
            source: "server",
            observedAt: t0.addingTimeInterval(-60),
            expiresAt: t0.addingTimeInterval(600),
            runTimeZoneID: "Asia/Shanghai",
            weather: .clear,
            storeOpen: true,
            reachablePlaceIDs: ["place-1"]
        )
        let activeView = EnvironmentBranchHostSectionView(
            proposedBranchID: "branch-outdoor",
            branches: sampleBranches,
            snapshot: validSnapshot,
            serverNow: t0
        )
        _ = activeView.body
        XCTAssertEqual(activeView.presentation.mode, .activeBranch)
        XCTAssertEqual(activeView.presentation.activeBranchID, "branch-outdoor")
        XCTAssertEqual(activeView.presentation.snapshotID, "snap-pinned-1")
        XCTAssertTrue(activeView.presentation.allowsProgression)
        XCTAssertFalse(activeView.presentation.requiresSafeExitAction)

        // Past the branch window end -> deterministic fallback
        let afterWindowView = EnvironmentBranchHostSectionView(
            proposedBranchID: "branch-outdoor",
            branches: sampleBranches,
            snapshot: EnvironmentSnapshot(
                snapshotID: "snap-pinned-2",
                source: "server",
                observedAt: t0,
                expiresAt: t0.addingTimeInterval(7200),
                runTimeZoneID: "Asia/Shanghai",
                weather: .clear,
                storeOpen: true,
                reachablePlaceIDs: ["place-1"]
            ),
            serverNow: t0.addingTimeInterval(3600)
        )
        _ = afterWindowView.body
        XCTAssertEqual(afterWindowView.presentation.mode, .deterministicFallback)
        XCTAssertEqual(afterWindowView.presentation.activeBranchID, "branch-indoor-fallback")
        XCTAssertEqual(afterWindowView.presentation.fallbackReason, .proposalConditionsUnmet)
    }

    func testEnvironmentBranchHostSectionViewSafeExitAndDisabledGateNoBranch() {
        let severeSnapshot = EnvironmentSnapshot(
            snapshotID: "snap-severe",
            source: "server",
            observedAt: t0.addingTimeInterval(-30),
            expiresAt: t0.addingTimeInterval(600),
            runTimeZoneID: "Asia/Shanghai",
            weather: .severe,
            storeOpen: true,
            reachablePlaceIDs: ["place-1"]
        )
        let pausedView = EnvironmentBranchHostSectionView(
            proposedBranchID: "branch-outdoor",
            branches: sampleBranches,
            snapshot: severeSnapshot,
            serverNow: t0
        )
        _ = pausedView.body
        XCTAssertEqual(pausedView.presentation.mode, .pausedForSafety)
        XCTAssertNil(pausedView.presentation.activeBranchID)
        XCTAssertFalse(pausedView.presentation.allowsProgression)
        XCTAssertTrue(pausedView.presentation.requiresSafeExitAction)

        let noBranchView = EnvironmentBranchHostSectionView(
            proposedBranchID: "unapproved-branch",
            branches: [sampleBranches[0]],
            snapshot: nil,
            serverNow: t0
        )
        _ = noBranchView.body
        XCTAssertEqual(noBranchView.presentation.mode, .noBranchAvailable)
        XCTAssertFalse(noBranchView.presentation.allowsProgression)
        XCTAssertFalse(MerchantAICommerceGates.disabled.rewardLedgerReadback)
    }

    func testRewardLedgerHostSectionViewPermanentVsSeasonRebuildableAndReversalPairing() throws {
        let entries: [RewardLedgerEntry] = [
            RewardLedgerEntry(
                entryID: "e-1",
                beneficiaryID: "player-1",
                rewardType: .points,
                amount: 40,
                sourceEventID: "evt-1",
                ruleVersion: "v1",
                seasonID: "season-1",
                reversalOf: nil,
                recordedAt: t0
            ),
            RewardLedgerEntry(
                entryID: "e-2",
                beneficiaryID: "player-1",
                rewardType: .points,
                amount: -40,
                sourceEventID: "evt-1",
                ruleVersion: "v1",
                seasonID: "season-1",
                reversalOf: "e-1",
                recordedAt: t0.addingTimeInterval(30)
            ),
            RewardLedgerEntry(
                entryID: "e-3",
                beneficiaryID: "player-1",
                rewardType: .points,
                amount: 60,
                sourceEventID: "evt-2",
                ruleVersion: "v1",
                seasonID: "season-1",
                reversalOf: nil,
                recordedAt: t0.addingTimeInterval(60)
            ),
            RewardLedgerEntry(
                entryID: "e-4",
                beneficiaryID: "player-1",
                rewardType: .points,
                amount: 90,
                sourceEventID: "evt-3",
                ruleVersion: "v1",
                seasonID: "season-2",
                reversalOf: nil,
                recordedAt: t0.addingTimeInterval(90)
            )
        ]

        let season1View = RewardLedgerHostSectionView(
            entries: entries,
            beneficiaryID: "player-1",
            rewardType: .points,
            activeSeasonID: "season-1"
        )
        _ = season1View.body

        guard case .valid(let snapshotS1) = season1View.outcome else {
            return XCTFail("Expected valid ledger outcome")
        }
        XCTAssertEqual(snapshotS1.permanentNetBalance, 150)
        XCTAssertEqual(snapshotS1.activeSeasonBalance, 60)
        XCTAssertEqual(snapshotS1.seasonProjections["season-1"], 60)
        XCTAssertEqual(snapshotS1.seasonProjections["season-2"], 90)
        XCTAssertEqual(snapshotS1.reversalPairs.count, 1)
        XCTAssertEqual(snapshotS1.reversalPairs.first?.originalEntryID, "e-1")
        XCTAssertEqual(snapshotS1.reversalPairs.first?.reversalEntryID, "e-2")

        let season2View = RewardLedgerHostSectionView(
            entries: entries,
            beneficiaryID: "player-1",
            rewardType: .points,
            activeSeasonID: "season-2"
        )
        _ = season2View.body
        guard case .valid(let snapshotS2) = season2View.outcome else {
            return XCTFail("Expected valid ledger outcome for season 2")
        }
        XCTAssertEqual(snapshotS2.permanentNetBalance, 150)
        XCTAssertEqual(snapshotS2.activeSeasonBalance, 90)
    }

    func testRewardLedgerHostSectionViewNonCashPolicyAndInvalidOutcome() {
        let defaultView = RewardLedgerHostSectionView()
        _ = defaultView.body
        XCTAssertFalse(RewardLedgerHostPresentation.supportsCashInLedger)
        XCTAssertFalse(RewardLedgerHostPresentation.canBridgePointsToCash)
        XCTAssertFalse(RewardLedgerHostPresentation.acceptsRawRewardType("CASH"))

        let invalidView = RewardLedgerHostSectionView(outcome: .invalid(.duplicateBusinessKey))
        _ = invalidView.body
        XCTAssertEqual(invalidView.outcome, .invalid(.duplicateBusinessKey))
    }
}

import XCTest
@testable import QuestifyCore

final class RewardLedgerHostPresentationTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeEntry(
        id: String,
        beneficiary: String = "player-1",
        type: RewardLedgerEntry.RewardType = .points,
        amount: Int = 25,
        event: String = "evt-1",
        rule: String = "rule-v1",
        season: String? = "season-2026-s1",
        reversalOf: String? = nil,
        offset: TimeInterval = 0
    ) -> RewardLedgerEntry {
        RewardLedgerEntry(
            entryID: id,
            beneficiaryID: beneficiary,
            rewardType: type,
            amount: amount,
            sourceEventID: event,
            ruleVersion: rule,
            seasonID: season,
            reversalOf: reversalOf,
            recordedAt: t0.addingTimeInterval(offset)
        )
    }

    func testReversalPairingDisplayKeepsBothEntriesAndNetsToZero() {
        let award = makeEntry(id: "e-1", amount: 30, event: "evt-1", season: "s1")
        let reversal = makeEntry(id: "e-2", amount: -30, event: "evt-1", season: "s1", reversalOf: "e-1", offset: 60)
        let secondAward = makeEntry(id: "e-3", amount: 50, event: "evt-2", season: "s1", offset: 120)

        let outcome = RewardLedgerHostPresentation.evaluate(
            entries: [award, reversal, secondAward],
            beneficiaryID: "player-1",
            rewardType: .points,
            activeSeasonID: "s1"
        )
        guard case .valid(let snapshot) = outcome else {
            return XCTFail("Expected valid ledger snapshot")
        }

        XCTAssertEqual(snapshot.rows.count, 3)
        XCTAssertTrue(snapshot.rows[0].isReversedOriginal)
        XCTAssertEqual(snapshot.rows[0].pairedReversalEntryID, "e-2")
        XCTAssertTrue(snapshot.rows[1].isReversal)
        XCTAssertEqual(snapshot.rows[1].reversalOf, "e-1")
        XCTAssertFalse(snapshot.rows[2].isReversedOriginal)

        XCTAssertEqual(snapshot.reversalPairs, [
            RewardLedgerReversalPair(
                originalEntryID: "e-1",
                reversalEntryID: "e-2",
                sourceEventID: "evt-1",
                rewardType: .points,
                cancelledAmount: 30
            )
        ])
        XCTAssertEqual(snapshot.permanentNetBalance, 50)
        XCTAssertEqual(snapshot.activeSeasonBalance, 50)
    }

    func testBusinessKeyUniquenessAndReversalValidationSurfaceExactErrors() {
        let first = makeEntry(id: "e-1", amount: 25, event: "evt-dup")
        let duplicateKey = makeEntry(id: "e-2", amount: 25, event: "evt-dup")
        XCTAssertEqual(
            RewardLedgerHostPresentation.evaluate(entries: [first, duplicateKey], beneficiaryID: "player-1", rewardType: .points),
            .invalid(.duplicateBusinessKey)
        )

        let zero = makeEntry(id: "e-zero", amount: 0, event: "evt-zero")
        XCTAssertEqual(
            RewardLedgerHostPresentation.evaluate(entries: [zero], beneficiaryID: "player-1", rewardType: .points),
            .invalid(.zeroAmount)
        )

        let orphanReversal = makeEntry(id: "e-rev", amount: -25, event: "evt-1", reversalOf: "missing")
        XCTAssertEqual(
            RewardLedgerHostPresentation.evaluate(entries: [orphanReversal], beneficiaryID: "player-1", rewardType: .points),
            .invalid(.reversalWithoutOriginal)
        )

        let wrongAmountReversal = makeEntry(id: "e-rev-bad", amount: -10, event: "evt-dup", reversalOf: "e-1")
        XCTAssertEqual(
            RewardLedgerHostPresentation.evaluate(entries: [first, wrongAmountReversal], beneficiaryID: "player-1", rewardType: .points),
            .invalid(.reversalMismatch)
        )
    }

    func testSeasonProjectionIsRebuildableWithoutClearingPermanentHistory() throws {
        let s1Entry = makeEntry(id: "e-1", amount: 40, event: "evt-1", season: "season-1")
        let s2Entry = makeEntry(id: "e-2", amount: 60, event: "evt-2", season: "season-2", offset: 30)
        let timelessEntry = makeEntry(id: "e-3", amount: 15, event: "evt-3", season: nil, offset: 60)

        let readback = try RewardLedgerReadback(validating: [s1Entry, s2Entry, timelessEntry])
        let season1View = RewardLedgerHostPresentation.project(
            readback,
            beneficiaryID: "player-1",
            rewardType: .points,
            activeSeasonID: "season-1"
        )
        let season2View = RewardLedgerHostPresentation.project(
            readback,
            beneficiaryID: "player-1",
            rewardType: .points,
            activeSeasonID: "season-2"
        )

        XCTAssertEqual(season1View.permanentNetBalance, 115)
        XCTAssertEqual(season2View.permanentNetBalance, 115)
        XCTAssertEqual(season1View.activeSeasonBalance, 40)
        XCTAssertEqual(season2View.activeSeasonBalance, 60)
        XCTAssertEqual(season1View.seasonProjections, ["season-1": 40, "season-2": 60])
        XCTAssertEqual(season1View.rows.count, 3)
    }

    func testAppendOnlyTransitionRejectsRemovedOrRewrittenHistory() throws {
        let e1 = makeEntry(id: "e-1", amount: 20, event: "evt-1")
        let e2 = makeEntry(id: "e-2", amount: 35, event: "evt-2")
        let initial = try RewardLedgerReadback(validating: [e1, e2])

        let appended = try RewardLedgerReadback(validating: [
            e1,
            e2,
            makeEntry(id: "e-3", amount: -20, event: "evt-1", reversalOf: "e-1")
        ])
        XCTAssertNil(RewardLedgerHostPresentation.validateAppendOnlyTransition(old: initial, new: appended))

        let removed = try RewardLedgerReadback(validating: [e1])
        XCTAssertEqual(
            RewardLedgerHostPresentation.validateAppendOnlyTransition(old: initial, new: removed),
            .entryRemoved
        )

        let rewritten = try RewardLedgerReadback(validating: [
            makeEntry(id: "e-1", amount: 99, event: "evt-1"),
            e2
        ])
        XCTAssertEqual(
            RewardLedgerHostPresentation.validateAppendOnlyTransition(old: initial, new: rewritten),
            .historyRewritten
        )
    }

    func testNonCashEnforcementRejectsCashAndPointsToCashBridge() {
        XCTAssertFalse(RewardLedgerHostPresentation.supportsCashInLedger)
        XCTAssertFalse(RewardLedgerHostPresentation.canBridgePointsToCash)
        XCTAssertFalse(RewardLedgerHostPresentation.acceptsRawRewardType("CASH"))
        XCTAssertFalse(RewardLedgerHostPresentation.acceptsRawRewardType(" cash "))
        XCTAssertTrue(RewardLedgerHostPresentation.acceptsRawRewardType("POINTS"))
        XCTAssertTrue(RewardLedgerHostPresentation.acceptsRawRewardType("BADGE"))
        XCTAssertTrue(RewardLedgerHostPresentation.acceptsRawRewardType("COUPON"))
        XCTAssertTrue(RewardLedgerHostPresentation.acceptsRawRewardType("ITEM"))
    }
}

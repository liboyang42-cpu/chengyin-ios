import XCTest
@testable import QuestifyCore

final class AssetPointsAndOrderCancellationAuditTests: XCTestCase {
    func testWalletLedgerRowCurrentPointsAndEventIDReadbackValidation() {
        let rows = [
            AssetPointsLedgerRowSnapshot(eventId: "evt-points-101", deltaPoints: 50, currentPoints: 150),
            AssetPointsLedgerRowSnapshot(eventId: "evt-points-102", deltaPoints: -30, currentPoints: 120)
        ]
        let audit = AssetPointsAndOrderCancellationAudit(ledgerRows: rows)
        XCTAssertTrue(audit.hasUniqueValidEventIDs)
        XCTAssertTrue(audit.isAllCompliant)

        let duplicateRows = [
            AssetPointsLedgerRowSnapshot(eventId: "evt-points-101", deltaPoints: 50, currentPoints: 150),
            AssetPointsLedgerRowSnapshot(eventId: "evt-points-101", deltaPoints: 10, currentPoints: 160)
        ]
        XCTAssertFalse(AssetPointsAndOrderCancellationAudit(ledgerRows: duplicateRows).isAllCompliant)

        let blankEventRow = [
            AssetPointsLedgerRowSnapshot(eventId: "   ", deltaPoints: 20, currentPoints: 20)
        ]
        XCTAssertFalse(AssetPointsAndOrderCancellationAudit(ledgerRows: blankEventRow).isAllCompliant)
    }

    func testOrderCancellationPointsConservationAcceptsValidFullAndPartialReturns() {
        XCTAssertEqual(
            AssetPointsAndOrderCancellationAudit.evaluateCancellationConservation(pointsUsed: 100, pointsReturned: 100),
            .conserved(pointsUsed: 100, pointsReturned: 100, unreturnedPoints: 0)
        )
        XCTAssertEqual(
            AssetPointsAndOrderCancellationAudit.evaluateCancellationConservation(pointsUsed: 100, pointsReturned: 40),
            .conserved(pointsUsed: 100, pointsReturned: 40, unreturnedPoints: 60)
        )
        XCTAssertEqual(
            AssetPointsAndOrderCancellationAudit.evaluateCancellationConservation(pointsUsed: 0, pointsReturned: 0),
            .conserved(pointsUsed: 0, pointsReturned: 0, unreturnedPoints: 0)
        )
    }

    func testOrderCancellationDetectsOverRefundAndNegativeValues() {
        XCTAssertEqual(
            AssetPointsAndOrderCancellationAudit.evaluateCancellationConservation(pointsUsed: 80, pointsReturned: 120),
            .overRefundDetected(pointsUsed: 80, pointsReturned: 120)
        )
        XCTAssertEqual(
            AssetPointsAndOrderCancellationAudit.evaluateCancellationConservation(pointsUsed: -10, pointsReturned: 0),
            .negativePointsInvalid
        )
        XCTAssertEqual(
            AssetPointsAndOrderCancellationAudit.evaluateCancellationConservation(pointsUsed: 50, pointsReturned: -5),
            .negativePointsInvalid
        )
    }

    func testNonCashPointsNeverBridgeToCashWalletBalances() {
        XCTAssertFalse(AssetPointsAndOrderCancellationAudit.cashBridgeAllowed)
        XCTAssertFalse(
            AssetPointsAndOrderCancellationAudit.canBridge(from: .nonCashPoints, to: .cashWalletBalance)
        )
        XCTAssertFalse(
            AssetPointsAndOrderCancellationAudit.canBridge(from: .cashWalletBalance, to: .nonCashPoints)
        )
        XCTAssertTrue(
            AssetPointsAndOrderCancellationAudit.canBridge(from: .nonCashPoints, to: .nonCashPoints)
        )
    }
}

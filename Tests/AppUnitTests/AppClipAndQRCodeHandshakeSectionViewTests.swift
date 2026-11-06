import SwiftUI
import XCTest
@testable import Questify

@MainActor
final class AppClipAndQRCodeHandshakeSectionViewTests: XCTestCase {
    func testDefaultReadySnapshotCoversAllFourQRPayloadKindsWithinTTLAndNonceRules() {
        let snapshot = QRHandshakeParitySnapshot.defaultReady
        XCTAssertEqual(snapshot.totalCount, 4)
        XCTAssertEqual(snapshot.compliantCount, 4)
        XCTAssertTrue(snapshot.coversAllPayloadKinds)
        XCTAssertTrue(snapshot.isAllCompliant)
        XCTAssertEqual(snapshot.overallStatusBadgeText, "READY · 4/4 QR PAYLOADS GUARDED")

        let kinds = Set(snapshot.rows.map(\.payloadKind))
        XCTAssertEqual(
            kinds,
            Set([
                .teamMeetingHandshake,
                .merchantStoreStampScan,
                .clubCheckInCode,
                .passportFriendCardQR,
            ])
        )
        XCTAssertTrue(snapshot.rows.allSatisfy { $0.ttlSeconds <= 300 && $0.requiresSingleUseReplayNonce })
    }

    func testExpiredOrUnverifiedQRPayloadTriggersWarningState() {
        var rows = QRHandshakeCheckRow.defaultRows
        rows[0] = QRHandshakeCheckRow(
            id: QRHandshakeCheckRow.PayloadKind.teamMeetingHandshake.rawValue,
            payloadKind: .teamMeetingHandshake,
            title: "Team Meeting Handshake (teamMeetingHandshake)",
            ttlSeconds: 600,
            requiresSingleUseReplayNonce: false,
            validatesCryptographicSignature: false
        )

        let warningSnapshot = QRHandshakeParitySnapshot(rows: rows)
        XCTAssertFalse(rows[0].isWithinTTLWindow)
        XCTAssertFalse(rows[0].isCompliant)
        XCTAssertEqual(rows[0].statusBadgeText, "WARNING · UNVERIFIED / EXPIRED")
        XCTAssertEqual(warningSnapshot.compliantCount, 3)
        XCTAssertFalse(warningSnapshot.isAllCompliant)
        XCTAssertEqual(warningSnapshot.overallStatusBadgeText, "WARNING · HANDSHAKE DRIFT")
    }

    func testMainActorSectionViewInstantiatesBodyForReadyAndWarningSnapshots() {
        let readyView = AppClipAndQRCodeHandshakeSectionView(snapshot: .defaultReady)
        XCTAssertTrue(readyView.snapshot.isAllCompliant)
        _ = readyView.body

        var degradedRows = QRHandshakeCheckRow.defaultRows
        degradedRows[1] = QRHandshakeCheckRow(
            payloadKind: .merchantStoreStampScan,
            title: "Merchant Store Stamp Scan",
            ttlSeconds: 450,
            requiresSingleUseReplayNonce: true,
            validatesCryptographicSignature: false
        )
        let warningView = AppClipAndQRCodeHandshakeSectionView(
            snapshot: QRHandshakeParitySnapshot(rows: degradedRows)
        )
        XCTAssertFalse(warningView.snapshot.isAllCompliant)
        _ = warningView.body
    }
}

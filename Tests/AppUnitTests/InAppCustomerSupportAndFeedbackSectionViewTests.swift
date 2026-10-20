import SwiftUI
import XCTest
@testable import Questify

@MainActor
final class InAppCustomerSupportAndFeedbackSectionViewTests: XCTestCase {
    func testDefaultReadySnapshotCoversAllFourCustomerSupportChannels() {
        let snapshot = CustomerSupportParitySnapshot.defaultReady
        XCTAssertEqual(snapshot.totalCount, 4)
        XCTAssertEqual(snapshot.compliantCount, 4)
        XCTAssertTrue(snapshot.coversAllChannels)
        XCTAssertTrue(snapshot.isAllCompliant)
        XCTAssertEqual(snapshot.overallStatusBadgeText, "READY · 4/4 SUPPORT CHANNELS")

        let kinds = Set(snapshot.rows.map(\.channelKind))
        XCTAssertEqual(
            kinds,
            Set([
                .generalFeedbackSubmission,
                .orderAfterSalesDispute,
                .ugcReportFollowUp,
                .merchantClubSettlementSupport,
            ])
        )
    }

    func testNonCompliantSupportChannelTriggersWarningState() {
        var rows = CustomerSupportChannelRow.defaultRows
        rows[1] = CustomerSupportChannelRow(
            id: CustomerSupportChannelRow.ChannelKind.orderAfterSalesDispute.rawValue,
            channelKind: .orderAfterSalesDispute,
            title: "Order & Registration After-Sales Support",
            attachesRedactedDiagnosticContext: false,
            supportsOfflineDraftPreservation: true,
            providesTicketReadbackStatus: false
        )

        let warningSnapshot = CustomerSupportParitySnapshot(rows: rows)
        XCTAssertFalse(rows[1].isCompliant)
        XCTAssertEqual(rows[1].statusBadgeText, "WARNING · CHANNEL NON-COMPLIANT")
        XCTAssertEqual(warningSnapshot.compliantCount, 3)
        XCTAssertFalse(warningSnapshot.isAllCompliant)
        XCTAssertEqual(warningSnapshot.overallStatusBadgeText, "WARNING · SUPPORT CHANNEL DRIFT")
    }

    func testMainActorSectionViewInstantiatesBodyForReadyAndWarningSnapshots() {
        let readyView = InAppCustomerSupportAndFeedbackSectionView(snapshot: .defaultReady)
        XCTAssertTrue(readyView.snapshot.isAllCompliant)
        _ = readyView.body

        var degradedRows = CustomerSupportChannelRow.defaultRows
        degradedRows[2] = CustomerSupportChannelRow(
            channelKind: .ugcReportFollowUp,
            title: "UGC Moderation & Abuse Report Follow-Up",
            attachesRedactedDiagnosticContext: true,
            supportsOfflineDraftPreservation: false,
            providesTicketReadbackStatus: false
        )
        let warningView = InAppCustomerSupportAndFeedbackSectionView(
            snapshot: CustomerSupportParitySnapshot(rows: degradedRows)
        )
        XCTAssertFalse(warningView.snapshot.isAllCompliant)
        _ = warningView.body
    }
}

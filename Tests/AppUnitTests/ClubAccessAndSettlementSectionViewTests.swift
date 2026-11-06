import XCTest
import SwiftUI
#if canImport(QuestifyApp)
@testable import QuestifyApp
#if canImport(QuestifyCore)
import QuestifyCore
#elseif canImport(Core)
import Core
#endif
#else
@testable import Questify
#endif

@MainActor
final class ClubAccessAndSettlementSectionViewTests: XCTestCase {
    func testFailClosedDefaultSnapshotRendersAccessMeGovernanceEnrollmentAndSettlementParity() {
        let view = ClubAccessAndSettlementSectionView()
        _ = view.body

        XCTAssertTrue(view.snapshot.isAllScopedAndFailClosed)
        XCTAssertEqual(view.snapshot.rows.count, 4)
        XCTAssertEqual(
            view.snapshot.rows.map(\.code),
            [
                "POST /api/club/access/me",
                "ClubGovernanceCoordinator",
                "ClubEnrollmentReader",
                "w2-16"
            ]
        )

        XCTAssertEqual(
            view.statusBadgeText,
            "Club Access & Settlement Gate: FAIL-CLOSED (4/4 Scoped)"
        )
        XCTAssertEqual(
            view.accessMeRouteSummaryText,
            "Access Route: POST /api/club/access/me (Form-Encoded • Session-Scoped)"
        )
        XCTAssertEqual(
            view.governanceSummaryText,
            "ClubGovernanceCoordinator: Fresh server role & baseline checks active; live writes OFF"
        )
        XCTAssertEqual(
            view.settlementParitySummaryText,
            "w2-16 Settlement & ClubEnrollmentReader: Read-only parity • Payouts OFF"
        )

        for row in view.snapshot.rows {
            XCTAssertTrue(row.isPermissionScoped)
            XCTAssertFalse(row.liveMutationOrPayoutEnabled)
            XCTAssertEqual(row.statusBadgeText, "SCOPED • FAIL-CLOSED")
        }
    }

    func testUnscopedOrLivePayoutSnapshotSurfacesReviewRequiredBanners() {
        var modifiedRows = ClubAccessAndSettlementSnapshot.defaultRows
        modifiedRows[3] = ClubAccessSettlementRow(
            id: "w2-16-settlement-parity",
            code: "w2-16",
            title: "Club Settlement & Revenue Read Parity",
            contractDetail: "Live payout overridden",
            isPermissionScoped: false,
            liveMutationOrPayoutEnabled: true
        )
        let violatingSnapshot = ClubAccessAndSettlementSnapshot(
            rows: modifiedRows,
            accessMeUsesPOSTForm: false,
            governanceRoleVerified: false,
            liveSettlementPayoutEnabled: true
        )
        let view = ClubAccessAndSettlementSectionView(snapshot: violatingSnapshot)
        _ = view.body

        XCTAssertFalse(view.snapshot.isAllScopedAndFailClosed)
        XCTAssertEqual(view.statusBadgeText, "Club Access & Settlement Gate: REVIEW REQUIRED")
        XCTAssertEqual(
            view.accessMeRouteSummaryText,
            "Access Route: MISMATCH (Expected POST Form-Encoded /api/club/access/me)"
        )
        XCTAssertEqual(
            view.governanceSummaryText,
            "ClubGovernanceCoordinator: Unverified role fallback detected"
        )
        XCTAssertEqual(
            view.settlementParitySummaryText,
            "w2-16 Settlement & ClubEnrollmentReader: VIOLATION — live payout enabled"
        )
        XCTAssertEqual(view.snapshot.rows[3].statusBadgeText, "ATTENTION REQUIRED")
    }
}

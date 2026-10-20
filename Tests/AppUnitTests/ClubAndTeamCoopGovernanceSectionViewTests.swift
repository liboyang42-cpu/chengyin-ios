@testable import QuestifyApp
import QuestifyCore
import XCTest

@MainActor
final class ClubAndTeamCoopGovernanceSectionViewTests: XCTestCase {
    func testDefaultSnapshotRendersAllFourGovernancePillarsHealthy() {
        let snapshot = ClubAndTeamCoopGovernanceSnapshot()

        XCTAssertEqual(snapshot.rows.count, 4)
        XCTAssertTrue(snapshot.allPillarsHealthy)
        XCTAssertEqual(snapshot.healthyCount, 4)

        let w212 = snapshot.row(for: .teamAndClubTabs)
        XCTAssertEqual(w212?.referenceBadge, "w2-12")
        XCTAssertEqual(w212?.status, .parityVerified)

        let w214 = snapshot.row(for: .clubOpsAndGovernance)
        XCTAssertEqual(w214?.referenceBadge, "w2-14..16")
        XCTAssertEqual(w214?.status, .parityVerified)

        let i09 = snapshot.row(for: .coopScheduleAndLeadPolling)
        XCTAssertEqual(i09?.referenceBadge, "I09")
        XCTAssertEqual(i09?.status, .parityVerified)

        let hw16 = snapshot.row(for: .teamFirstMeetingAndMultiInvite)
        XCTAssertEqual(hw16?.referenceBadge, "H-W16 · U02–U07")
        XCTAssertEqual(hw16?.status, .contractAndOfflineUIReady)
        XCTAssertEqual(hw16?.summaryText.contains("NFC 禁用"), true)
        XCTAssertEqual(hw16?.summaryText.contains("北京时间"), true)
    }

    func testSnapshotDetectsActionRequiredWhenAnyPillarIsUnverified() {
        let rows = ClubAndTeamCoopGovernanceSnapshot.defaultPillars(
            teamAndClubTabsVerified: true,
            clubOpsGovernanceVerified: false,
            coopSchedulePollingVerified: true,
            teamMeetingAndInviteReady: false
        )
        let snapshot = ClubAndTeamCoopGovernanceSnapshot(rows: rows)

        XCTAssertFalse(snapshot.allPillarsHealthy)
        XCTAssertEqual(snapshot.healthyCount, 2)
        XCTAssertEqual(snapshot.row(for: .clubOpsAndGovernance)?.status, .actionRequired)
        XCTAssertEqual(snapshot.row(for: .teamFirstMeetingAndMultiInvite)?.status, .actionRequired)
    }

    func testSectionViewInstantiationAndPillarSelectionCallback() throws {
        let snapshot = ClubAndTeamCoopGovernanceSnapshot()
        var selectedPillar: ClubCoopGovernancePillarRow?

        let view = ClubAndTeamCoopGovernanceSectionView(
            snapshot: snapshot,
            onSelectPillar: { row in
                selectedPillar = row
            }
        )

        XCTAssertEqual(view.snapshot, snapshot)
        _ = view.body

        let targetRow = try XCTUnwrap(snapshot.row(for: .teamFirstMeetingAndMultiInvite))
        view.onSelectPillar?(targetRow)
        XCTAssertEqual(selectedPillar, targetRow)
    }
}

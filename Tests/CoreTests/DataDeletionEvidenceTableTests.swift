import XCTest
@testable import QuestifyCore

final class DataDeletionEvidenceTableTests: XCTestCase {
    func testFirstJourneyAccountDeregisterRemovedVersusRetainedRecoverOriginal() {
        XCTAssertEqual(DataDeletionEvidenceTable.require("member_identity")?.removed, true)
        XCTAssertEqual(DataDeletionEvidenceTable.require("member_address")?.removed, true)
        XCTAssertEqual(DataDeletionEvidenceTable.require("app_session")?.removed, true)
        XCTAssertEqual(DataDeletionEvidenceTable.require("ums_member")?.retained, true)
        XCTAssertEqual(DataDeletionEvidenceTable.require("oms_order")?.retained, true)
        XCTAssertEqual(
            DataDeletionEvidenceTable.require("oms_order")?.disposition, .anonymizedRetained)
        XCTAssertEqual(
            DataDeletionEvidenceTable.require("business_audit_event")?.disposition, .retainedLegal)
        XCTAssertEqual(
            DataDeletionEvidenceTable.require("club_edition_compensation_terms")?.disposition,
            .retainedLegal)

        var sawRemoved = false
        var sawRetained = false
        for row in DataDeletionEvidenceTable.byRequestKind("ACCOUNT_DEREGISTER") {
            if row.removed { sawRemoved = true }
            if row.retained { sawRetained = true }
        }
        XCTAssertTrue(sawRemoved)
        XCTAssertTrue(sawRetained)
        XCTAssertFalse(DataDeletionEvidenceTable.removed.isEmpty)
        XCTAssertFalse(DataDeletionEvidenceTable.retained.isEmpty)
        XCTAssertFalse(DataDeletionEvidenceTable.executesCleanup)
        XCTAssertFalse(DataDeletionEvidenceTable.writesDDL)
        XCTAssertFalse(DataDeletionEvidenceTable.emptyCurrentProjectionIsNeverExisted)
        XCTAssertEqual(DataDeletionEvidenceTable.require("member_identity")?.disposition, .removed)
    }

    func testRetentionWindowsMatchExistingCleanupDefaultsRecoverOriginal() {
        XCTAssertEqual(DataDeletionEvidenceTable.browseDays, 180)
        XCTAssertEqual(DataDeletionEvidenceTable.eventDays, 365)
        XCTAssertEqual(DataDeletionEvidenceTable.npcChatDays, 90)
        XCTAssertEqual(DataDeletionEvidenceTable.npcChatRequestHours, 48)
        XCTAssertEqual(DataDeletionEvidenceTable.roamLocationDays, 30)
        XCTAssertEqual(DataDeletionEvidenceTable.require("tms_browse_record")?.retentionDays, 180)
        XCTAssertEqual(DataDeletionEvidenceTable.require("npc_chat_request")?.retentionHours, 48)
        XCTAssertEqual(DataDeletionEvidenceTable.require("roam_location")?.existingWriter, "cleanRoamLocations")
        XCTAssertEqual(DataDeletionEvidenceTable.require("biz_event_log")?.retentionDays, 365)
        XCTAssertEqual(DataDeletionEvidenceTable.require("npc_chat_log")?.retentionDays, 90)
    }
}

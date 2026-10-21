import XCTest
@testable import QuestifyCore

/// Second-pass mini-program copy for signup toasts and complaint load failures. Display only.
final class W204P2MemberToolsTests: XCTestCase {
    private func ticket(_ fields: String) throws -> TicketWalletTicket {
        try JSONDecoder().decode(TicketWalletTicket.self, from: Data(("{\"id\":7," + fields + "}").utf8))
    }

    func testNonOpeningRowsUseSourceToastCopy() throws {
        XCTAssertEqual(try ticket(#""registrationStatus":3"#).sourceNoticeKey, "ticketWallet.p2.notice.cancelled")
        XCTAssertEqual(try ticket(#""registrationStatus":4"#).sourceNoticeKey, "ticketWallet.p2.notice.expired")
        XCTAssertEqual(try ticket(#""registrationStatus":9"#).sourceNoticeKey, "ticketWallet.p2.notice.unknown")
        XCTAssertEqual(try ticket("\"ownerType\":1").sourceNoticeKey, "ticketWallet.p2.notice.unknown")
    }

    func testPaymentAndDetailKeepNativeNotices() throws {
        XCTAssertEqual(try ticket(#""registrationStatus":1"#).sourceNoticeKey, "ticketWallet.action.paymentUnavailable")
        XCTAssertEqual(try ticket(#""registrationStatus":2"#).sourceNoticeKey, "ticketWallet.action.detail")
    }

    func testScheduleSyncOnlyForPaidRowsWithoutOwner() throws {
        XCTAssertTrue(try ticket(#""registrationStatus":2"#).needsScheduleSync)
        XCTAssertTrue(try ticket(#""registrationStatus":2,"ownerId":0"#).needsScheduleSync)
        XCTAssertFalse(try ticket(#""registrationStatus":2,"ownerId":91"#).needsScheduleSync)
        for status in [1, 3, 4] { XCTAssertFalse(try ticket(#""registrationStatus":\#(status)"#).needsScheduleSync, "status \(status)") }
    }

    func testNoticeNeverChangesOpeningAction() throws {
        let paid = try ticket(#""registrationStatus":2"#)
        XCTAssertEqual(paid.action, .detail)
        XCTAssertEqual(try ticket(#""registrationStatus":3"#).action, .cancelled)
    }

    func testComplaintLoadFailureCopyFollowsSource() {
        XCTAssertEqual(ProfileComplaintReadIssue.failed.sourceTitleKey, "profile.complaintP2.loadFailed.title")
        XCTAssertEqual(ProfileComplaintReadIssue.signIn.sourceTitleKey, "profile.complaintP2.loadFailed.title")
        XCTAssertEqual(ProfileComplaintReadIssue.failed.sourceDetailKey, "profile.complaintP2.loadFailed.generic")
        XCTAssertEqual(ProfileComplaintReadIssue.signIn.sourceDetailKey, "profile.complaintP2.loadFailed.signIn")
        XCTAssertEqual(ProfileComplaintReadIssue.unavailable.sourceDetailKey, ProfileComplaintReadIssue.unavailable.titleKey)
    }
}

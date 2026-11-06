import XCTest
@testable import QuestifyCore

final class ProfileInviteHistoryIssueTests: XCTestCase {
    func testSignedOutAndDeniedAreDistinctFromOrdinaryFailure() {
        XCTAssertEqual(ProfileInviteHistoryIssueKind(APIError.unauthorized), .signIn)
        XCTAssertEqual(ProfileInviteHistoryIssueKind(SocialAccountFailure.rejected(code: 401, message: nil)), .signIn)
        XCTAssertEqual(ProfileInviteHistoryIssueKind(APIError.httpStatus(403)), .denied)
        XCTAssertEqual(ProfileInviteHistoryIssueKind(SocialAccountFailure.rejected(code: 403, message: "x")), .denied)
        XCTAssertEqual(ProfileInviteHistoryIssueKind(APIError.httpStatus(500)), .failed)
        XCTAssertEqual(ProfileInviteHistoryIssueKind(APIError.malformedResponse), .failed)
        XCTAssertEqual(ProfileInviteHistoryIssueKind(APIError.notConfigured), .unavailable)
    }
    func testOnlyOrdinaryFailureRetriesWithSourceCopy() {
        XCTAssertTrue(ProfileInviteHistoryIssueKind.failed.canRetry)
        XCTAssertFalse(ProfileInviteHistoryIssueKind.signIn.canRetry)
        XCTAssertFalse(ProfileInviteHistoryIssueKind.denied.canRetry)
        XCTAssertEqual(ProfileInviteHistoryIssueKind.failed.titleKey, "profile.inviteHistory.failed")
        XCTAssertEqual(ProfileInviteHistoryIssueKind.denied.detailKey, "profile.inviteHistory.deniedHint")
        XCTAssertNil(ProfileInviteHistoryIssueKind.unavailable.detailKey)
    }
}

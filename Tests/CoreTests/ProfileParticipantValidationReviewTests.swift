import XCTest
@testable import QuestifyCore

final class ProfileParticipantValidationReviewTests: XCTestCase {
    private func draft(_ name: String = "", _ phone: String = "") -> ParticipantFormDraft {
        var d = ParticipantFormDraft(); d.fullName = name; d.mobilePhone = phone; return d
    }
    func testInitialEmptyFormDoesNotAnnounceErrors() { XCTAssertNil(ProfileParticipantValidationReview().issue(in: draft())) }
    func testReviewStartsWithMissingName() { var r = ProfileParticipantValidationReview(); XCTAssertEqual(r.request(in: draft()), .name); XCTAssertTrue(r.hasRequestedReview) }
    func testWhitespaceNameRemainsRequired() { var r = ProfileParticipantValidationReview(); XCTAssertEqual(r.request(in: draft(" \n", "13800000000")), .name) }
    func testPhoneIsNextAfterFixingName() { var r = ProfileParticipantValidationReview(); _ = r.request(in: draft()); XCTAssertEqual(r.issue(in: draft("Fixture")), .phone) }
    func testEmptyPhoneReceivesExplicitFeedback() { var r = ProfileParticipantValidationReview(); XCTAssertEqual(r.request(in: draft("Fixture")), .phone) }
    func testExistingPhoneHintStillAppearsBeforeReview() { XCTAssertEqual(ProfileParticipantValidationReview().issue(in: draft("Fixture", "123")), .phone) }
    func testValidCorrectionClearsIssueWithoutAnotherAction() { var r = ProfileParticipantValidationReview(); _ = r.request(in: draft()); XCTAssertNil(r.issue(in: draft("Fixture", "13800000000"))) }
    func testFurtherInvalidEditShowsCurrentField() { var r = ProfileParticipantValidationReview(); _ = r.request(in: draft("Fixture", "13800000000")); XCTAssertEqual(r.issue(in: draft("", "13800000000")), .name) }
    func testSourcePhoneRulesAreUsedWithoutNormalizationOrGuessing() { for phone in ["138****0000", "+8613800000000", "1３８００００００００", "12000000000", ""] { var r = ProfileParticipantValidationReview(); XCTAssertEqual(r.request(in: draft("Fixture", phone)), .phone) } }
    func testValidTrimmedSourceInputIsNotRewritten() { let d = draft(" Fixture\n", " 13800000000 "); let original = d; var r = ProfileParticipantValidationReview(); XCTAssertNil(r.request(in: d)); XCTAssertEqual(d, original) }
    func testRepeatedReviewIsIdempotentAndStoresNoDraft() { var r = ProfileParticipantValidationReview(); _ = r.request(in: draft()); let once = r; _ = r.request(in: draft()); XCTAssertEqual(r, once); XCTAssertEqual(Mirror(reflecting: r).children.count, 1) }
    func testNewReviewResetsDisclosure() { var r = ProfileParticipantValidationReview(); _ = r.request(in: draft()); r = ProfileParticipantValidationReview(); XCTAssertFalse(r.hasRequestedReview); XCTAssertNil(r.issue(in: draft())) }
}

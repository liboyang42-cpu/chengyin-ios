import XCTest
import SwiftUI
@testable import Questify

@MainActor final class ProfileInviteRewardReviewAppTests: XCTestCase {
    func testOrdinaryModelDataBuildsFullCumulativeAndLoadedMonth() async throws {let r=ProfileInviteRewardReviewFixtureReader();let value=try await r.invitationHistory(page:1);let review=ProfileInviteRewardReview(scan:value.rewardScan);XCTAssertEqual(review.cumulativePoints,11);XCTAssertEqual(review.month(members:value.page.members).earnedPoints,Decimal(string:"7.75"))}
    func testRetryUsesExistingInvitationModelAndSameReader() async {
        let reader=ProfileInviteRewardReviewFixtureReader("partial"),model=SocialInviteHistoryModel()
        let first=model.appear(reader);await first?.value;XCTAssertNil(ProfileInviteRewardReview(scan:model.scan).cumulativePoints)
        let retry=model.start(reader,permit:model.permit(reader),reset:true);await retry?.value
        XCTAssertEqual(reader.reads,2);XCTAssertEqual(ProfileInviteRewardReview(scan:model.scan).cumulativePoints,11)
    }
    func testOldCapturedPermitCannotDispatchAfterIdentityChange() async {
        let reader=ProfileInviteRewardReviewFixtureReader(),model=SocialInviteHistoryModel();await model.appear(reader)?.value
        let permit=model.permit(reader);reader.identity = .init(accountID:82,epoch:2);reader.presentationRevision += 1
        XCTAssertNil(model.start(reader,permit:permit,reset:true));XCTAssertEqual(reader.reads,1)
    }
    func testDetachedReviewCannotStartRetry() async {
        let reader=ProfileInviteRewardReviewFixtureReader(),model=SocialInviteHistoryModel();await model.appear(reader)?.value
        let permit=model.permit(reader);model.suspend();XCTAssertNil(model.start(reader,permit:permit,reset:true));XCTAssertEqual(reader.reads,1)
    }
    func testLoadMoreUpdatesMonthMembersWithoutShrinkingGlobalRewardTotal() async {
        let reader=ProfileInviteRewardReviewFixtureReader(),model=SocialInviteHistoryModel();await model.appear(reader)?.value
        await model.start(reader,permit:model.permit(reader),reset:false)?.value
        XCTAssertEqual(model.pagination.members.count,3);XCTAssertEqual(ProfileInviteRewardReview(scan:model.scan).cumulativePoints,11)
    }
    func testUnknownLedgerCanRecoverThroughSameRead() async throws {let r=ProfileInviteRewardReviewFixtureReader("unavailable");let a=try await r.invitationHistory(page:1);let b=try await r.invitationHistory(page:1);XCTAssertNil(ProfileInviteRewardReview(scan:a.rewardScan).cumulativePoints);XCTAssertEqual(ProfileInviteRewardReview(scan:b.rewardScan).cumulativePoints,11)}
    func testHostBuildsOnlySyntheticDependencies() {let host=UIHostingController(rootView:ProfileInviteRewardReviewFixtureHost());host.loadViewIfNeeded();XCTAssertNotNil(host.view)}
}

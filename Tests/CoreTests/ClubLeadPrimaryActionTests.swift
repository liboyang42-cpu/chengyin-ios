import XCTest
@testable import QuestifyCore

final class ClubLeadPrimaryActionTests: XCTestCase {
    func testPublishSelectsExistingProjectLaunch() { XCTAssertEqual(ClubLeadPrimaryAction(stage: .publish), .publish) }
    func testInviteSelectsMerchantDiscoveryNotInvitationSubmission() { XCTAssertEqual(ClubLeadPrimaryAction(stage: .invite), .merchants) }
    func testPendingSelectsSentInvitations() { XCTAssertEqual(ClubLeadPrimaryAction(stage: .pending), .sentInvitations) }
    func testMerchantAcceptedSelectsExistingTopics() { XCTAssertEqual(ClubLeadPrimaryAction(stage: .accepted), .topics) }
    func testExecutionAcceptedSelectsExistingEventOperations() { XCTAssertEqual(ClubLeadPrimaryAction(stage: .executionAccepted), .events) }
    func testIncompleteProjectsNeverProduceAnAction() { XCTAssertNil(ClubLeadPrimaryAction(stage: .partial)) }
    func testActionsHaveUniqueBilingualLookupKeys() {
        let keys = ClubLeadPrimaryAction.allCases.map(\.titleKey)
        XCTAssertEqual(Set(keys).count, 5); XCTAssertTrue(keys.allSatisfy { $0.hasPrefix("club.leadPrimary.") })
    }
}

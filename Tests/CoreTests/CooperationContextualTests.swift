import XCTest
@testable import QuestifyCore

final class CooperationContextualTests: XCTestCase {
    func testDirectoryIDsNeverCrossMerchantMemberAndClubDomains() throws {
        let merchant = try XCTUnwrap(CoopFlowTargetCandidate(kind: .merchant, row: .object(["id": .id(99), "memberId": .id(4), "name": .string("Store")])))
        XCTAssertEqual(merchant.recipient, try .init(.member, 4))
        XCTAssertNil(CoopFlowTargetCandidate(kind: .merchant, row: .object(["id": .id(99), "name": .string("Store")])))
        let club = try XCTUnwrap(CoopFlowTargetCandidate(kind: .club, row: .object(["id": .id(99), "memberId": .id(4), "name": .string("Club")])))
        XCTAssertEqual(club.recipient, try .init(.club, 99))
    }
    func testTargetDirectoryAndOwnedTopicContracts() throws {
        XCTAssertEqual(CoopFlowRead.merchants(name: "Store").path, "api/club/merchants")
        XCTAssertEqual(try CoopFlowRead.merchants(name: "Store").body(), .object(["name": .string("Store")]))
        XCTAssertTrue(CoopFlowRead.merchants(name: nil).expectsArray)
        let fields = try CoopFlowRead.ownedTopics(kind: .merchant, scope: "MERCHANT", page: 2).body()
        XCTAssertEqual(fields["is_my"].text, "1"); XCTAssertEqual(fields["invite_target"].text, "merchant")
        XCTAssertEqual(fields["scope"].text, "MERCHANT"); XCTAssertEqual(fields["pageNum"].text, "2")
        XCTAssertThrowsError(try CoopFlowRead.ownedTopics(kind: .club, scope: "invented", page: 1).body())
    }
    func testNewInvitationRequiresCurrentSessionAndOpenWindow() throws {
        let session = try CoopFlowSession(accountID: 1, epoch: 1, token: "fixture")
        let candidate = try XCTUnwrap(CoopFlowTargetCandidate(kind: .merchant, row: .object(["memberId": .id(4), "name": .string("Store")])))
        let open = try XCTUnwrap(CoopFlowOwnedTopic(row: .object(["id": .id(7), "name": .string("Topic"), "inviteWindowOpen": .bool(true)])))
        let context = try XCTUnwrap(CoopFlowInvitationContext(candidate: candidate, topic: open, scope: nil, session: session))
        let invitation = try context.invitation(message: "Hello", compensation: .traffic, currentSession: session)
        let fields = try CoopFlowMutation.invite(invitation).body()
        XCTAssertEqual(fields["toId"].integer, 4); XCTAssertEqual(fields["toType"].text, "merchant")
        XCTAssertEqual(fields["originApplyId"], .null)
        XCTAssertThrowsError(try context.invitation(message: "Hello", compensation: .traffic, currentSession: nil))
        let closed = try XCTUnwrap(CoopFlowOwnedTopic(row: .object(["id": .id(7), "name": .string("Topic"), "inviteWindowOpen": .bool(false)])))
        XCTAssertNil(CoopFlowInvitationContext(candidate: candidate, topic: closed, scope: nil, session: session))
    }
    func testPeerCreditNeverTreatsClubIDsOrMissingTypeAsMembers() {
        XCTAssertEqual(CoopPeerMember(direction: .sent, fromType: "club", fromID: 9, toType: "merchant", toID: 4)?.memberID, 4)
        XCTAssertNil(CoopPeerMember(direction: .sent, fromType: "merchant", fromID: 4, toType: "club", toID: 9))
        XCTAssertEqual(CoopPeerMember(direction: .received, fromType: "talent", fromID: 4, toType: "club", toID: 9)?.memberID, 4)
        XCTAssertNil(CoopPeerMember(direction: .received, fromType: "club", fromID: 9, toType: "merchant", toID: 4))
        XCTAssertNil(CoopPeerMember(direction: .received, fromType: nil, fromID: 9, toType: "merchant", toID: 4))
    }
}

import XCTest
@testable import QuestifyCore

final class CooperationInvitePresentationTests: XCTestCase {
    private func invite(_ fields: String) throws -> CooperationInvite {
        try JSONDecoder().decode(CooperationInvite.self, from: Data(("{\"id\":5," + fields + "}").utf8))
    }

    func testPartiesPreferSideTypesAndFallBackToInviteType() throws {
        let typed = CooperationInvitePresentation(invite: try invite(#""fromType":"talent","toType":"merchant","inviteType":0"#), direction: .received)
        XCTAssertEqual(typed.partyKeys?.from, "cooperation.party.talent"); XCTAssertEqual(typed.partyKeys?.to, "cooperation.party.merchant")
        let unknownSide = CooperationInvitePresentation(invite: try invite(#""fromType":"robot""#), direction: .sent)
        XCTAssertEqual(unknownSide.partyKeys?.from, "cooperation.party.from"); XCTAssertEqual(unknownSide.partyKeys?.to, "cooperation.party.to")
        let legacy = CooperationInvitePresentation(invite: try invite(#""inviteType":1"#), direction: .sent)
        XCTAssertNil(legacy.partyKeys); XCTAssertEqual(legacy.inviteTypeKey, "cooperation.inviteType.1")
    }

    func testTermsDepositAndContactStates() throws {
        let pending = CooperationInvitePresentation(invite: try invite(#""status":0,"shareMode":2,"fixedFee":15"#), direction: .received)
        XCTAssertEqual(pending.terms, .fixed(fee: 15)); XCTAssertEqual(pending.contact, .afterAcceptReceived)
        XCTAssertEqual(pending.input, .reply); XCTAssertEqual(pending.footer, .decide)
        let owed = CooperationInvitePresentation(invite: try invite(#""status":1,"depositOwed":true,"partner":{"leaderName":"Lin","phone":" "}"#), direction: .sent)
        XCTAssertEqual(owed.deposit, .owed(amount: nil)); XCTAssertEqual(owed.footer, .deposit)
        XCTAssertEqual(owed.contact, .visible("Lin"))
        let ended = CooperationInvitePresentation(invite: try invite(#""status":3"#), direction: .sent)
        XCTAssertEqual(ended.contact, .ended); XCTAssertEqual(ended.footer, .inactive); XCTAssertTrue(ended.handleReasonIsOurs)
    }

    func testLegacyInvitesExposeNoActions() throws {
        let legacy = CooperationInvitePresentation(invite: try invite(#""status":1,"inviteType":2,"depositOwed":true,"topicId":3,"toType":"merchant""#), direction: .received)
        XCTAssertEqual(legacy.footer, .legacy); XCTAssertEqual(legacy.deposit, .notRequired)
        XCTAssertFalse(legacy.showsContactPartner); XCTAssertFalse(legacy.showsPerkDeclaration); XCTAssertNil(legacy.projectScope)
    }

    func testAcceptedActionsFollowDirectionAndPartyRules() throws {
        let received = CooperationInvitePresentation(invite: try invite(#""status":1,"inviteType":0,"topicId":3,"fromId":8,"toId":9,"toType":"merchant","termsFrozen":true"#), direction: .received)
        XCTAssertEqual(received.projectScope, .merchant); XCTAssertTrue(received.showsPerkDeclaration)
        XCTAssertTrue(received.showsReview); XCTAssertEqual(received.revieweeID, 8); XCTAssertTrue(received.cancelLocked)
        XCTAssertEqual(received.footer, .ongoing(frozen: true))
        let clubSent = CooperationInvitePresentation(invite: try invite(#""status":1,"inviteType":1,"topicId":3,"fromType":"club","toType":"club","toId":4"#), direction: .sent)
        XCTAssertEqual(clubSent.projectScope, .club); XCTAssertFalse(clubSent.showsPerkDeclaration); XCTAssertFalse(clubSent.showsReview)
    }

    func testOwnRatingComesOnlyFromMatchingTopic() throws {
        let summary = try JSONDecoder().decode(CoopFlowJSON.self, from: Data(#"{"reviews":[{"fromId":2,"topicId":4,"rating":3},{"fromId":1,"topicId":9,"rating":6},{"fromId":1,"topicId":4,"rating":4}]}"#.utf8))
        XCTAssertEqual(CooperationInvitePresentation.myRating(summary: summary, me: 1, topicID: 4), 4)
        XCTAssertNil(CooperationInvitePresentation.myRating(summary: summary, me: 1, topicID: 9))
        XCTAssertNil(CooperationInvitePresentation.myRating(summary: summary, me: 1, topicID: nil))
    }

    func testDisplayJoinsAreTolerant() throws {
        let row = try invite(#""topicName":"  ","viewerPartyName":"North club","topicStartDate":{"bad":true}"#)
        XCTAssertNil(row.topicName); XCTAssertEqual(row.viewerPartyName, "North club"); XCTAssertNil(row.topicStartDate)
    }
}

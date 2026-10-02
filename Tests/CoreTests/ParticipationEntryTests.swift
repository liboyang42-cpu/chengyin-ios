import XCTest
@testable import QuestifyCore

final class ParticipationEntryTests: XCTestCase {
    func testPlayEntryPreservesRegistrationIDSeparatelyFromActivityOrTopic() throws {
        let activity = try XCTUnwrap(ParticipationPlayEntry(registrationID: 71, scope: .activity(91)))
        let topic = try XCTUnwrap(ParticipationPlayEntry(registrationID: 72, scope: .topic(92)))
        XCTAssertEqual(activity.registrationID, 71); XCTAssertEqual(activity.scope, .activity(91))
        XCTAssertEqual(topic.registrationID, 72); XCTAssertEqual(topic.scope, .topic(92))
        XCTAssertNotEqual(activity, topic)
    }
    func testPlayEntryRejectsMissingTicketOrMissingOwner() {
        XCTAssertNil(ParticipationPlayEntry(registrationID: 0, scope: .activity(91)))
        XCTAssertNil(ParticipationPlayEntry(registrationID: 71, scope: .topic(0)))
    }
    func testSourceOwnerFallbackDoesNotLoseRegistrationID() throws {
        let record = try JSONDecoder().decode(ParticipationRecord.self, from: Data(#"{"id":71,"ownerType":1,"cmsTopic":{"id":91}}"#.utf8))
        XCTAssertEqual(record.playEntry?.registrationID, 71)
        XCTAssertEqual(record.playEntry?.scope, .topic(91))
    }
}

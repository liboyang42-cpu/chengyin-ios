import XCTest
@testable import QuestifyCore

final class ActivityPeopleTests: XCTestCase {
    private func decode(_ fields: String = "") throws -> ActivityDetail {
        try JSONDecoder().decode(ActivityDetail.self, from: Data("{\"id\":17,\"name\":\"Fixture\"\(fields)}".utf8))
    }

    func testReadsDesignatedHostAndPartialPublicRosterWithoutInferringTotal() throws {
        let detail = try decode(#", "memberId":99,"collaboratorsList":[{"id":401,"memberId":21,"memberRealName":" Host "},{"memberId":22,"memberRealName":"Other"}],"registrationList":[{"id":501,"memberId":31,"nickname":" Player "},{"id":502,"memberId":31,"nickname":"Second registration"}],"registrationCount":12"#)
        XCTAssertEqual(detail.hostMemberID, 99)
        XCTAssertEqual(detail.people.host?.memberID, 21)
        XCTAssertEqual(detail.people.host?.name, "Host")
        XCTAssertEqual(detail.people.participants.map(\.memberID), [31, 31])
        XCTAssertEqual(detail.people.participants.first?.name, "Player")
        XCTAssertEqual(detail.people.registrationCount, 12)
        XCTAssertFalse(detail.people.contains(memberID: 99))
        XCTAssertFalse(detail.people.contains(memberID: 401))
        XCTAssertFalse(detail.people.contains(memberID: 501))
    }

    func testMissingAndNullPeopleFieldsStayEmptyAndCountUnknown() throws {
        for fields in ["", #", "collaboratorsList":null,"registrationList":null,"registrationCount":null"#] {
            let people = try decode(fields).people
            XCTAssertNil(people.host)
            XCTAssertTrue(people.participants.isEmpty)
            XCTAssertNil(people.registrationCount)
        }
        let people = try decode(#", "registrationList":[{"memberId":31}],"registrationCount":-1"#).people
        XCTAssertNil(people.registrationCount, "A preview does not establish a total")
        XCTAssertNil(people.participants.first?.name)
        XCTAssertEqual(try decode(#", "registrationCount":0"#).people.registrationCount, 0)
    }

    func testFirstCollaboratorIsNotReplacedByOwnerOrLaterNamedCollaborator() throws {
        let people = try decode(#", "memberId":99,"collaboratorsList":[{"memberRealName":" "},{"memberId":22,"memberRealName":"Other"}]"#).people
        XCTAssertNil(people.host?.memberID)
        XCTAssertNil(people.host?.name)
        XCTAssertFalse(people.contains(memberID: 22))
        XCTAssertFalse(people.contains(memberID: 99))
    }

    func testOnlyPositiveSafeMemberIdentifiersBecomeDestinations() throws {
        for raw in ["1", "\"31\"", "9007199254740991"] {
            let people = try decode(",\"registrationList\":[{\"memberId\":\(raw)}]").people
            XCTAssertNotNil(people.participants.first?.memberID)
        }
        for raw in ["null", "0", "-1", "1.5", "true", "{}", "[]", "\"bad\"", "\"31?token=x\"", "9007199254740992"] {
            let people = try decode(",\"registrationList\":[{\"id\":90,\"memberId\":\(raw),\"nickname\":\"Person\"}]").people
            XCTAssertNil(people.participants.first?.memberID)
            XCTAssertEqual(people.participants.first?.name, "Person")
            XCTAssertFalse(people.contains(memberID: 90))
        }
    }

    func testPublicParticipantPreviewRejectsMoreThanFiveRows() throws {
        let person = #"{"memberId":31,"nickname":"Person"}"#
        let five = Array(repeating: person, count: 5).joined(separator: ",")
        XCTAssertEqual(try decode(",\"registrationList\":[\(five)]").people.participants.count, 5)
        XCTAssertThrowsError(try decode(",\"registrationList\":[\(five),\(person)]"))
    }

    func testMalformedPublicListsDoNotBecomeEmptySuccess() {
        for field in ["collaboratorsList", "registrationList"] {
            for raw in ["{}", "true", "1", "\"bad\"", "[null]", "[1]"] {
                XCTAssertThrowsError(try decode(",\"\(field)\":\(raw)"))
            }
        }
        XCTAssertThrowsError(try decode(#", "collaboratorsList":[{"memberRealName":42}]"#))
        XCTAssertThrowsError(try decode(#", "registrationList":[{"nickname":[]}]"#))
    }

    func testClubGateNeverDecodesHiddenPeople() throws {
        let gate = try JSONDecoder().decode(ActivityDetailAccess.self, from: Data(#"{"gate":true,"clubId":9,"collaboratorsList":"hidden","registrationList":"hidden"}"#.utf8))
        XCTAssertEqual(gate, .clubRequired(clubID: 9, message: nil))
    }

    func testProfileSelectionIsBoundToExactActivityPeopleAndViewer() throws {
        let people = try decode(#", "registrationList":[{"memberId":31}]"#).people
        let viewer = SocialAccountIdentity(accountID: 81, epoch: 4, role: "player")
        let snapshotID = UUID()
        let selection = try XCTUnwrap(ActivityPersonProfileSelection(activityID: 17, memberID: 31, people: people, identity: viewer, snapshotID: snapshotID))
        XCTAssertTrue(selection.matches(activityID: 17, people: people, identity: viewer, snapshotID: snapshotID))
        XCTAssertFalse(selection.matches(activityID: 17, people: people, identity: viewer, snapshotID: UUID()),
                       "A new detail snapshot expires the old selection even if its member is still present")
        XCTAssertFalse(selection.matches(activityID: 18, people: people, identity: viewer, snapshotID: snapshotID))
        XCTAssertFalse(selection.matches(activityID: 17, people: try decode().people, identity: viewer, snapshotID: snapshotID))
        for other in [SocialAccountIdentity(accountID: 82, epoch: 4, role: "player"),
                      .init(accountID: 81, epoch: 5, role: "player"),
                      .init(accountID: 81, epoch: 4, role: "merchant"),
                      .init(accountID: nil, epoch: 4)] {
            XCTAssertFalse(selection.matches(activityID: 17, people: people, identity: other, snapshotID: snapshotID))
        }
        XCTAssertNil(ActivityPersonProfileSelection(activityID: 0, memberID: 31, people: people, identity: viewer, snapshotID: snapshotID))
        XCTAssertNil(ActivityPersonProfileSelection(activityID: 17, memberID: 32, people: people, identity: viewer, snapshotID: snapshotID))
        XCTAssertNil(ActivityPersonProfileSelection(activityID: 17, memberID: 31, people: people, identity: .init(accountID: nil, epoch: 4), snapshotID: snapshotID))
    }
}

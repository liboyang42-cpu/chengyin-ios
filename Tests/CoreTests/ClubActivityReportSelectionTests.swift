import XCTest
@testable import QuestifyCore

final class ClubActivityReportSelectionTests: XCTestCase {
    private func club(joined: Bool = true, id: Int = 81) throws -> ClubRecord {
        try JSONDecoder().decode(ClubRecord.self, from: JSONSerialization.data(withJSONObject: ["id": id, "isJoined": joined]))
    }
    private func context(account: Int? = 701, clubID: Int = 81) -> ClubGovernanceReadContext {
        .init(operation: .topics, scope: .init(clubID: clubID), identity: .init(accountID: account, epoch: 2), viewerRevision: 5, authorizationGeneration: nil)
    }
    private func snapshot(_ op: ClubGovernanceRead, _ scope: ClubGovernanceScope, _ value: ClubGovernanceValue) throws -> ClubGovernanceSnapshot {
        let permissions = try ClubGovernancePermissions(value: .object(["active": .bool(true), "club": .object(["id": .integer(scope.clubID ?? 81)]), "roleCodes": .array([.string("CLUB_MEMBER")]), "permissions": .array([])]), scope: scope)
        return .init(operation: op, scope: scope, permissions: permissions, value: value)
    }
    private func topics(author: ClubGovernanceValue = .integer(702), duplicate: Bool = false) throws -> ClubGovernanceSnapshot {
        let row = ClubGovernanceValue.object(["id": .integer(91), "memberId": author, "clubId": .integer(81)])
        return try snapshot(.topics, .init(clubID: 81), .array(duplicate ? [row, row] : [row]))
    }
    private func source() throws -> ClubActivityReportSource {
        try XCTUnwrap(ClubActivityReportSource(topicID: 91, club: club(), snapshot: topics(), context: context(), generation: 7))
    }
    private func activity(_ id: Int, topic: Int = 91, club: Int = 81) -> ClubGovernanceValue {
        .object(["id": .integer(id), "topicId": .integer(topic), "clubId": .integer(club), "name": .string("  Evening\n session  "), "startDate": .string("2026-11-01 19:00")])
    }
    private func overview(_ rows: [ClubGovernanceValue], author: Int = 702) throws -> ClubGovernanceSnapshot {
        try snapshot(.topicOverview, .init(clubID: 81, topicID: 91), .object(["id": .integer(91), "name": .string("Topic"), "memberId": .integer(author), "activityList": .array(rows)]))
    }
    func testSourceRequiresAcceptedNonselfMemberTopic() throws {
        let s = try source(); XCTAssertEqual(s.topicID, 91); XCTAssertEqual(s.authorID, 702); XCTAssertEqual(s.generation, 7)
        XCTAssertNil(ClubActivityReportSource(topicID: 92, club: try club(), snapshot: try topics(), context: context(), generation: 7))
    }
    func testGuestNonmemberSelfUnknownAuthorAndDuplicatesClosed() throws {
        let value = try topics()
        XCTAssertNil(ClubActivityReportSource(topicID: 91, club: try club(), snapshot: value, context: context(account: nil), generation: 7))
        XCTAssertNil(ClubActivityReportSource(topicID: 91, club: try club(joined: false), snapshot: value, context: context(), generation: 7))
        for author in [ClubGovernanceValue.integer(701), .integer(0), .null] {
            XCTAssertNil(ClubActivityReportSource(topicID: 91, club: try club(), snapshot: try topics(author: author), context: context(), generation: 7))
        }
        XCTAssertNil(ClubActivityReportSource(topicID: 91, club: try club(), snapshot: try topics(duplicate: true), context: context(), generation: 7))
    }
    func testWrongClubContextRejected() throws {
        XCTAssertNil(ClubActivityReportSource(topicID: 91, club: try club(id: 82), snapshot: try topics(), context: context(), generation: 7))
        XCTAssertNil(ClubActivityReportSource(topicID: 91, club: try club(), snapshot: try topics(), context: context(clubID: 82), generation: 7))
    }
    func testActivitiesPreserveExactIDsOrderAndDisplayLabels() throws {
        let rows = try source().activities(overview([activity(42), activity(41)]))
        XCTAssertEqual(rows.map(\.id), [42, 41]); XCTAssertEqual(rows[0].name, "Evening session")
        XCTAssertEqual(rows[0].startDate, "2026-11-01 19:00")
    }
    func testNoActivitiesRemainsEmpty() throws {
        XCTAssertTrue(try source().activities(overview([])).isEmpty)
    }
    func testDuplicateInvalidForeignActivityRejected() throws {
        for rows in [[activity(41), activity(41)], [activity(0)], [activity(41, topic: 92)], [activity(41, club: 82)]] {
            XCTAssertThrowsError(try source().activities(overview(rows)))
        }
    }
    func testFreshAuthorCannotSwitchOrBecomeSelf() throws {
        let s = try source(); XCTAssertFalse(try s.matches(club: club(), snapshot: topics(author: .integer(703))))
        XCTAssertThrowsError(try s.activities(overview([activity(41)], author: 701)))
    }
    func testTargetCannotBeForgedFromUnlistedChoice() throws {
        let s = try source(), rows = try s.activities(overview([activity(41)]))
        XCTAssertNil(ClubActivityReportTarget(source: s, choice: rows[0], choices: []))
        XCTAssertNil(ClubActivityReportTarget(source: s, choice: rows[0], choices: rows + rows))
    }
    func testExactActivitySeedNeverTopicAndTargetIsImmutable() throws {
        let s = try source(), rows = try s.activities(overview([activity(41)]))
        let t = try XCTUnwrap(ClubActivityReportTarget(source: s, choice: rows[0], choices: rows))
        XCTAssertEqual(t.scope, .init(clubID: 81)); XCTAssertEqual(t.seed, ["targetType": .string("ACTIVITY"), "targetId": .integer(41)])
        var draft = ClubGovernanceFormDraft(operation: .report, scope: t.scope, seed: t.seed)
        XCTAssertEqual(Set(draft.text.keys), ["reason"]); draft.text["reason"] = "Specific facts"
        let command = try draft.command(); XCTAssertEqual(command.fields["targetId"], .integer(41)); XCTAssertNil(command.fields["topicId"])
        draft.text["targetId"] = "91"; XCTAssertThrowsError(try draft.command())
    }
    func testMissingOverviewPermissionCannotCreateChoices() throws {
        let value = try overview([activity(41)])
        XCTAssertThrowsError(try source().activities(.init(operation: value.operation, scope: value.scope, permissions: nil, value: value.value)))
    }
}

import XCTest
@testable import QuestifyCore

final class ClubEnrollmentTests: XCTestCase {
    private let scope = ClubGovernanceScope(clubID: 81, topicID: 91)
    private func raw(_ text: String) -> ClubGovernanceValue { ClubGovernanceFixtures.json(text) }
    private func roster(_ ticketFields: String) -> ClubGovernanceValue {
        raw("{\"clubId\":81,\"topicId\":91,\"canRefund\":false,\"omsTicketList\":[{\"id\":921," + ticketFields + "}]}")
    }
    func testEnrollmentReadBodiesReuseExactExistingJSONScopes() throws {
        XCTAssertEqual(try ClubGovernanceRead.topics.fields(scope: scope), ["id": .integer(81)])
        XCTAssertEqual(try ClubGovernanceRead.registrations.fields(scope: scope), ["clubId": .integer(81), "topicId": .integer(91)])
        XCTAssertEqual(ClubGovernanceRead.registrations.path, "api/club/topic-registrations")
    }
    func testMissingCountsAndVerificationAreUnknownNotZeroOrPending() throws {
        let team = try ClubEnrollmentTeam.list(raw("[{\"id\":91}]"), clubID: 81)[0]
        XCTAssertNil(team.signupCount)
        let value = try ClubEnrollmentRoster(value: roster(#""cmsRegistrationList":[{"id":121,"paymentStatus":2}]"#), scope: scope)
        XCTAssertEqual(value.tickets[0].registrants[0].checkin, .unknown)
        XCTAssertNil(value.refundableCount); XCTAssertNil(value.teamStatus)
    }
    func testSourceIntegerModeCapacityDeadlineAndCounts() throws {
        let value = try ClubEnrollmentRoster(value: roster(#""mode":1,"totalInventory":8,"signupDeadline":"2026-10-10T12:30:00","teamStatus":1,"cmsRegistrationList":[{"id":121,"paymentStatus":2,"verificationStatus":0},{"id":122,"paymentStatus":2,"verificationStatus":1}]"#), scope: scope)
        XCTAssertEqual(value.tickets[0].mode, 1); XCTAssertEqual(value.tickets[0].capacity, 8)
        XCTAssertEqual(value.deadline, "2026-10-10 12:30"); XCTAssertEqual(value.teamStatus, 1)
        XCTAssertEqual(value.paidCount, 2); XCTAssertEqual(value.refundableCount, 1)
        XCTAssertEqual(value.tickets[0].registrants[1].checkin, .done)
        XCTAssertFalse(value.canRefund)
    }
    func testCrossScopeAndMissingRootIdentityReject() {
        for fields in [#""clubId":82,"topicId":91,"canRefund":false"#, #""clubId":81,"topicId":92,"canRefund":false"#, #""canRefund":false"#] {
            XCTAssertThrowsError(try ClubEnrollmentRoster(value: raw("{" + fields + ",\"omsTicketList\":[]}"), scope: scope))
        }
    }
    func testMissingRefundPermissionCannotBeAssumed() {
        XCTAssertThrowsError(try ClubEnrollmentRoster(value: raw(#"{"clubId":81,"topicId":91,"omsTicketList":[]}"#), scope: scope))
    }
    func testMalformedNestedListsCannotMasqueradeAsEmpty() {
        for nested in [#""cmsRegistrationList":{}"#, #""cmsRegistrationList":[null]"#, #""cmsRegistrationList":[{"id":0}]"#, #""cmsRegistrationList":[{"id":1,"memberId":0}]"#] {
            XCTAssertThrowsError(try ClubEnrollmentRoster(value: roster(nested), scope: scope))
        }
    }
    func testSourceNullRegistrationListIsAnEmptyList() throws {
        let value = try ClubEnrollmentRoster(value: roster(#""cmsRegistrationList":null"#), scope: scope)
        XCTAssertEqual(value.paidCount, 0); XCTAssertEqual(value.refundableCount, 0)
    }
    func testDuplicateRegistrationAndTicketIDsReject() {
        XCTAssertThrowsError(try ClubEnrollmentRoster(value: roster(#""cmsRegistrationList":[{"id":121},{"id":121}]"#), scope: scope))
        let duplicateTickets = raw(#"{"clubId":81,"topicId":91,"canRefund":false,"omsTicketList":[{"id":1},{"id":1}]}"#)
        XCTAssertThrowsError(try ClubEnrollmentRoster(value: duplicateTickets, scope: scope))
        let duplicateAcrossTickets = raw(#"{"clubId":81,"topicId":91,"canRefund":false,"omsTicketList":[{"id":1,"cmsRegistrationList":[{"id":121}]},{"id":2,"cmsRegistrationList":[{"id":121}]}]}"#)
        XCTAssertThrowsError(try ClubEnrollmentRoster(value: duplicateAcrossTickets, scope: scope))
    }
    func testNegativeOrMalformedCountsReject() {
        for count in ["-1", "true", "{}", "1.5"] {
            XCTAssertThrowsError(try ClubEnrollmentTeam.list(raw("[{\"id\":91,\"signupCount\":" + count + "}]"), clubID: 81))
        }
        XCTAssertThrowsError(try ClubEnrollmentRoster(value: roster(#""totalInventory":-1"#), scope: scope))
    }
    func testTeamDuplicatesAndCrossClubReject() {
        XCTAssertThrowsError(try ClubEnrollmentTeam.list(raw("[{\"id\":91},{\"id\":91}]"), clubID: 81))
        XCTAssertThrowsError(try ClubEnrollmentTeam.list(raw("[{\"id\":91,\"clubId\":82}]"), clubID: 81))
    }
    func testGlobalGovernanceValidationUsesNestedRosterContract() {
        XCTAssertThrowsError(try ClubGovernanceValidation.validate(roster(#""cmsRegistrationList":{}"#), operation: .registrations, scope: scope))
    }
    @MainActor func testFocusExpandsRequestedTeamWithoutFilteringOthers() async {
        let access = ClubGovernanceFixtureAccess()
        access.overrideValue[.topics] = raw(#"[{"id":91,"name":"First"},{"id":92,"name":"Second"}]"#)
        let reader = ClubEnrollmentReader(clubID: 81, focusTopicID: 91, access: access)
        await reader.activate(identity: access.identity)
        XCTAssertEqual(reader.teams.map(\.id), [91, 92]); XCTAssertEqual(reader.expanded, [91])
        XCTAssertNotNil(reader.rosters[91]); XCTAssertNil(reader.rosters[92]); XCTAssertTrue(access.sent.isEmpty)
    }
    @MainActor func testDetailIsLazyAndRepeatExpandUsesAcceptedSnapshot() async {
        let access = ClubGovernanceFixtureAccess(); var reads = 0; access.onRead = { reads += 1 }
        let reader = ClubEnrollmentReader(clubID: 81, access: access)
        await reader.activate(identity: access.identity); XCTAssertEqual(reads, 1); XCTAssertTrue(reader.rosters.isEmpty)
        await reader.toggle(topicID: 91); XCTAssertEqual(reads, 2)
        await reader.toggle(topicID: 91); await reader.toggle(topicID: 91); XCTAssertEqual(reads, 2)
    }
    @MainActor func testReturnRefreshReloadsExpandedDetailsAndDropsCollapsedCaches() async {
        let access = ClubGovernanceFixtureAccess(); let reader = ClubEnrollmentReader(clubID: 81, focusTopicID: 91, access: access)
        await reader.activate(identity: access.identity); XCTAssertEqual(reader.rosters[91]?.paidCount, 1)
        access.overrideValue[.registrations] = raw(#"{"clubId":81,"topicId":91,"canRefund":false,"omsTicketList":[]}"#)
        await reader.refresh(); XCTAssertEqual(reader.rosters[91]?.paidCount, 0)
        await reader.toggle(topicID: 91); await reader.refresh(); XCTAssertNil(reader.rosters[91])
    }
    @MainActor func testOrdinaryRefreshFailurePreservesVisibleStaleSnapshot() async {
        let access = ClubGovernanceFixtureAccess(); let reader = ClubEnrollmentReader(clubID: 81, access: access)
        await reader.activate(identity: access.identity); access.readFailure = .rejected(code: 503, message: nil)
        await reader.refresh(); XCTAssertTrue(reader.hasLoaded); XCTAssertEqual(reader.teams.count, 1); XCTAssertNotNil(reader.failure)
    }
    @MainActor func testPermissionLossClearsAllRosterData() async {
        let access = ClubGovernanceFixtureAccess(); let reader = ClubEnrollmentReader(clubID: 81, focusTopicID: 91, access: access)
        await reader.activate(identity: access.identity); access.readFailure = .forbidden; await reader.refresh()
        XCTAssertTrue(reader.teams.isEmpty); XCTAssertTrue(reader.rosters.isEmpty); XCTAssertFalse(reader.hasLoaded)
        XCTAssertEqual(reader.failure, .forbidden)
    }
    @MainActor func testPublicTopicsDoNotGrantRosterPermission() async {
        let access = ClubGovernanceFixtureAccess()
        access.permissionValue = raw(#"{"active":true,"club":{"id":81},"roleCodes":["CLUB_MEMBER"],"permissions":[],"canManageRoles":false}"#)
        let reader = ClubEnrollmentReader(clubID: 81, access: access); await reader.activate(identity: access.identity)
        XCTAssertEqual(reader.failure, .forbidden); XCTAssertTrue(reader.teams.isEmpty)
    }
    @MainActor func testSessionChangeDropsOldResultsAndSameAccountEpochClearsPII() async {
        let access = ClubGovernanceFixtureAccess(); let old = access.identity
        let reader = ClubEnrollmentReader(clubID: 81, focusTopicID: 91, access: access)
        access.onRead = { access.identity = .init(accountID: 701, epoch: 2) }
        await reader.activate(identity: old); XCTAssertFalse(reader.hasLoaded); XCTAssertTrue(reader.rosters.isEmpty)
        access.onRead = nil; await reader.activate(identity: access.identity); XCTAssertEqual(reader.rosters[91]?.paidCount, 1)
        access.identity = nil; await reader.activate(identity: nil)
        XCTAssertTrue(reader.teams.isEmpty); XCTAssertTrue(reader.rosters.isEmpty); XCTAssertEqual(reader.failure, .signedOut)
    }
}

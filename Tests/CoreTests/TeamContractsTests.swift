import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class TeamContractsTests: XCTestCase {
    private func detail(_ json: String = TeamSyntheticFixtures.detailJSON) throws -> TeamDetail { try JSONDecoder().decode(TeamDetail.self, from: Data(json.utf8)) }
    func testAllFiveStatusesAndUnknownRemainDistinct() throws {
        for (raw, expected) in [(0, TeamStatus.recruiting), (1, .full), (2, .inProgress), (3, .ended), (4, .disbanded), (88, .unknown)] {
            XCTAssertEqual(try detail(TeamSyntheticFixtures.detailJSON.replacingOccurrences(of: "\"status\":0", with: "\"status\":\(raw)")).team.status, expected)
        }
    }
    func testMissingStatusCannotBecomeRecruiting() throws {
        let value = try detail(TeamSyntheticFixtures.detailJSON.replacingOccurrences(of: "\"status\":0,", with: ""))
        XCTAssertEqual(value.team.status, .unknown); XCTAssertFalse(TeamAction.leave(teamID: 4101).isAllowed(detail: value))
    }
    func testMissingMembershipFactsDoNotGrantPermission() throws {
        let value = try detail(TeamSyntheticFixtures.detailJSON.replacingOccurrences(of: "\"joined\":true,\"leader\":true,", with: ""))
        XCTAssertNil(value.joined); XCTAssertNil(value.leader)
        XCTAssertFalse(TeamAction.leave(teamID: 4101).isAllowed(detail: value))
        XCTAssertFalse(TeamAction.join(teamID: 4101, inviteCode: "SYNTHETIC-TEAM").isAllowed(detail: value))
        XCTAssertFalse(TeamAction.remove(teamID: 4101, memberID: 902).isAllowed(detail: value))
    }
    func testContradictoryLeadershipFailsClosed() {
        XCTAssertThrowsError(try detail(TeamSyntheticFixtures.detailJSON.replacingOccurrences(of: "\"joined\":true", with: "\"joined\":false")))
    }
    func testUnknownMemberRoleAndCaptainCannotBeRemoved() throws {
        let value = try detail(); XCTAssertFalse(TeamAction.remove(teamID: 4101, memberID: 901).isAllowed(detail: value))
        let unknown = try detail(TeamSyntheticFixtures.detailJSON.replacingOccurrences(of: ",\"role\":0", with: ""))
        XCTAssertFalse(TeamAction.remove(teamID: 4101, memberID: 902).isAllowed(detail: unknown))
        XCTAssertTrue(TeamAction.remove(teamID: 4101, memberID: 902).isAllowed(detail: value))
        let unmapped = try detail(TeamSyntheticFixtures.detailJSON.replacingOccurrences(of: "\"role\":0", with: "\"role\":99"))
        XCTAssertFalse(TeamAction.remove(teamID: 4101, memberID: 902).isAllowed(detail: unmapped))
    }
    func testInProgressDoesNotUseRecruitingActions() throws {
        let value = try detail(TeamSyntheticFixtures.detailJSON.replacingOccurrences(of: "\"status\":0", with: "\"status\":2"))
        XCTAssertEqual(value.team.status, .inProgress)
        XCTAssertFalse(TeamAction.leave(teamID: 4101).isAllowed(detail: value))
        XCTAssertFalse(TeamAction.disband(teamID: 4101).isAllowed(detail: value))
        XCTAssertTrue(value.team.walletEligible)
    }
    func testServerCountAndExpireTimeAreNotInferredFromMembersOrStartTime() throws {
        let value = try detail(TeamSyntheticFixtures.detailJSON.replacingOccurrences(of: "\"joinedCount\":2", with: "\"joinedCount\":3").replacingOccurrences(of: "2030-05-02 10:00:00", with: "source-specific-time"))
        XCTAssertEqual(value.team.joinedCount, 3); XCTAssertEqual(value.members.count, 2)
        XCTAssertEqual(value.team.expireTime, "source-specific-time")
    }
    func testFlatInvitationAndStringIDsAreSourceSupported() throws {
        let flat = #"{"teamId":"12","title":"Invitation","status":0,"joined":false,"leader":false}"#
        XCTAssertEqual(try detail(flat).team.id, 12)
        XCTAssertTrue(TeamAction.join(teamID: 12, inviteCode: "CODE").isAllowed(detail: try detail(flat)))
    }
    func testConflictingIDsAndFractionalIDsAreRejected() {
        XCTAssertThrowsError(try detail(#"{"team":{"id":12,"teamId":13}}"#))
        XCTAssertThrowsError(try detail(#"{"team":{"id":12.5}}"#))
    }
    func testDuplicateMembersAreRejected() {
        XCTAssertThrowsError(try detail(TeamSyntheticFixtures.detailJSON.replacingOccurrences(of: "\"memberId\":902", with: "\"memberId\":901")))
    }
    func testWalletOwnerTypeAndOwnerIDStaySeparateFromTeamID() throws {
        let team = try detail().team
        XCTAssertEqual(team.ownerKey, TeamOwnerKey(type: 2, id: 5101)); XCTAssertEqual(team.id, 4101)
        let ended = try detail(TeamSyntheticFixtures.detailJSON.replacingOccurrences(of: "\"status\":0", with: "\"status\":3"))
        XCTAssertFalse(ended.team.walletEligible)
    }
    func testCreationSizeOptionsMatchSourceClamp() {
        for (cap, expected) in [(1, [2]), (2, [2]), (3, [2,3]), (4, [2,3,4]), (9, [2,3,4])] {
            XCTAssertEqual(TeamCreationContext(ownerID: 1, title: "", registrationStatus: 2, teamMode: 2, maxMembers: cap).sizes, expected)
        }
    }
    func testCreationRequiresConfirmedRegistrationAndTeamMode() {
        XCTAssertFalse(TeamCreationContext(ownerID: 1, title: "", registrationStatus: 1, teamMode: 2, maxMembers: 4).eligible)
        XCTAssertFalse(TeamCreationContext(ownerID: 1, title: "", registrationStatus: 2, teamMode: 1, maxMembers: 4).eligible)
    }
    func testPublicCreationOmitsJoinModeAndPrivateSendsOne() throws {
        let context = TeamSyntheticFixtures.creation
        let publicBody = try TeamWriteContract(.create(context: context, size: 3, inviteOnly: false))
        XCTAssertEqual(publicBody.path, "/api/team/create")
        XCTAssertEqual(publicBody.fields, ["ownerType": .integer(2), "ownerId": .integer(5101), "maxMembers": .integer(3)])
        XCTAssertEqual(try TeamWriteContract(.create(context: context, size: 3, inviteOnly: true)).fields["joinMode"], .integer(1))
    }
    func testInviteJoinSendsOnlyInviteCodeAndNeverTeamID() throws {
        let body = try TeamWriteContract(.join(teamID: 4101, inviteCode: " CODE "))
        XCTAssertEqual(body.path, "/api/team/join"); XCTAssertEqual(body.fields, ["inviteCode": .text("CODE")])
    }
    func testMutationContractsAreExactSourceAllowlist() throws {
        XCTAssertEqual(try TeamWriteContract(.leave(teamID: 5)).path, "/api/team/quit")
        XCTAssertEqual(try TeamWriteContract(.disband(teamID: 5)).path, "/api/team/disband")
        XCTAssertEqual(try TeamWriteContract(.remove(teamID: 5, memberID: 7)).fields, ["teamId": .integer(5), "memberId": .integer(7)])
        XCTAssertThrowsError(try TeamWriteContract(.leave(teamID: 0)))
    }
    func testMissingInviteAndControlCharactersAreRejected() {
        XCTAssertFalse(TeamLookup.invitation(" ").isValid); XCTAssertFalse(TeamLookup.invitation("code\nheader").isValid)
        XCTAssertFalse(TeamLookup.id(0).isValid)
    }
    func testPendingRecordContainsNoInviteOrCredentials() throws {
        let record = TeamPendingRecord(operationID: UUID(), ownerKey: "CN-901", targetKey: "team-4101")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any])
        XCTAssertEqual(Set(object.keys), Set(["operationID", "ownerKey", "targetKey"]))
    }
}

private final class TeamCaptureTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var response: Data
    var status = 200
    init(_ response: String) { self.response = Data(response.utf8) }
    func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); return (response, status) }
}
@MainActor final class TeamServiceTests: XCTestCase {
    private func service(_ transport: TeamCaptureTransport) throws -> TeamReadOnlyService {
        TeamReadOnlyService(configuration: try APIConfiguration(baseURL: XCTUnwrap(URL(string: "https://example.com/"))), transport: transport)
    }
    func testMyTeamsReadUsesPOSTJSONEmptyObjectAndAuth() async throws {
        let transport = TeamCaptureTransport(#"{"code":200,"data":[]}"#)
        let rows = try await service(transport).myTeams(session: TeamSyntheticFixtures.session())
        XCTAssertEqual(rows, [])
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/api/team/my"); XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic-team-token")
        let body = try XCTUnwrap(request.httpBody); XCTAssertEqual(String(data: body, encoding: .utf8), "{}")
    }
    func testInfoLookupPreservesInvitationBodyAndHasNoQueryString() async throws {
        let transport = TeamCaptureTransport("{\"code\":200,\"data\":" + TeamSyntheticFixtures.detailJSON + "}")
        _ = try await service(transport).detail(.invitation("SYNTHETIC-TEAM"), session: TeamSyntheticFixtures.session())
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.url?.path, "/api/team/info"); XCTAssertNil(request.url?.query)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: String])
        XCTAssertEqual(json, ["inviteCode": "SYNTHETIC-TEAM"])
    }
    func testWrongDetailIDFailsClosed() async throws {
        let transport = TeamCaptureTransport("{\"code\":200,\"data\":" + TeamSyntheticFixtures.detailJSON + "}")
        do { _ = try await service(transport).detail(.id(999), session: TeamSyntheticFixtures.session()); XCTFail("wrong target") }
        catch { XCTAssertEqual(error as? TeamFailure, .invalidContract) }
    }
    func testLiveMutationAndReceiptNeverCallTransport() async throws {
        let transport = TeamCaptureTransport("{}"), instance = try service(transport), session = try TeamSyntheticFixtures.session()
        let result = await instance.submit(.leave(teamID: 4101), operationID: UUID(), session: session)
        XCTAssertEqual(result, .notSent)
        let receipt = try await instance.receipt(operationID: UUID(), session: session); XCTAssertNil(receipt)
        XCTAssertTrue(transport.requests.isEmpty)
    }
    func testUnauthorizedBusinessCodeIsNotDataOrRawMessage() async throws {
        let transport = TeamCaptureTransport(#"{"code":401,"msg":"secret server text","data":[]}"#)
        do { _ = try await service(transport).myTeams(session: TeamSyntheticFixtures.session()); XCTFail("unauthorized") }
        catch { XCTAssertEqual(error as? TeamFailure, .unauthorized) }
    }
    func testUnconfiguredReadAndCreationPreflightNeverInventEndpoints() async throws {
        let instance = TeamReadOnlyService(), session = try TeamSyntheticFixtures.session()
        do { _ = try await instance.myTeams(session: session); XCTFail("not configured") }
        catch { XCTAssertEqual(error as? TeamFailure, .notConfigured) }
        do { _ = try await instance.creationContext(ownerID: 5101, session: session); XCTFail("no invented route") }
        catch { XCTAssertEqual(error as? TeamFailure, .notConfigured) }
    }
}

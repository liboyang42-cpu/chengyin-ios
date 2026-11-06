import Foundation
import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class PublicRosterContractTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var denied = false
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        if request.url?.lastPathComponent == "detail" {
            return (Data(#"{"code":200,"data":{"id":10,"name":"Club","joinPolicy":0}}"#.utf8), 200)
        }
        if denied { return (Data(#"{"code":403,"msg":"denied"}"#.utf8), 200) }
        return (Data(#"{"code":200,"data":[{"memberId":5,"clubId":10,"nickname":"Member"}]}"#.utf8), 200)
    }
}
final class ClubPublicRosterCurrentContractTests: XCTestCase {
    func testExplicitPublicPolicyDoesNotBecomeMembershipOrGovernance() throws {
        for raw in [#"{"id":10,"joinPolicy":0}"#, #"{"id":10}"#, #"{"id":10,"joinPolicy":1}"#, #"{"id":10,"joinPolicy":0,"viewerIdentityUnavailable":true}"#] {
            let club = try JSONDecoder().decode(ClubRecord.self, from: Data(raw.utf8))
            XCTAssertFalse(club.canSeeMembers); XCTAssertFalse(club.canGovern)
            XCTAssertEqual(ClubPublicRosterEligibility.mayRequest(club, identity: .init(accountID: 5, epoch: 1)), raw == #"{"id":10,"joinPolicy":0}"#)
            XCTAssertFalse(ClubPublicRosterEligibility.mayRequest(club, identity: .init(accountID: nil, epoch: 1)))
        }
    }
    @MainActor
    func testDedicatedApprovalAbsentMakesNoRequestsAndCurrentServerStillDecides() async throws {
        let base = URL(string: "https://fixture.test")!, transport = PublicRosterContractTransport()
        let session = try ClubPublicRosterSession(accountID: 5, epoch: 1, token: "fixture-token")
        var approval: ClubPublicRosterApproval?
        let reader = ClubPublicRosterReader(configuration: try APIConfiguration(baseURL: base), transport: transport,
            currentSession: { session }, approval: { approval })
        do { _ = try await reader.read(clubID: 10, mode: .members, isCurrent: { true }); XCTFail("missing approval") } catch {}
        XCTAssertTrue(transport.requests.isEmpty)
        approval = .init(identity: session.identity, baseURL: base, revision: UUID())
        let snapshot = try await reader.read(clubID: 10, mode: .members, isCurrent: { true })
        XCTAssertEqual(snapshot.memberIDs, [5]); XCTAssertFalse(snapshot.club.canGovern)
        XCTAssertEqual(transport.requests.map { $0.url!.lastPathComponent }, ["detail", "members", "detail"])
        approval = nil; XCTAssertFalse(reader.isCurrent(snapshot))
        approval = .init(identity: session.identity, baseURL: base, revision: UUID()); transport.denied = true
        do { _ = try await reader.read(clubID: 10, mode: .members, isCurrent: { true }); XCTFail("server denial") }
        catch { XCTAssertEqual(error as? ClubReadFailure, .forbidden(message: "denied")) }
    }
}

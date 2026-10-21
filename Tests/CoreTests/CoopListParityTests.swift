import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class CoopListParityTests: XCTestCase {
    private func json(_ text: String) throws -> CoopFlowJSON { try JSONDecoder().decode(CoopFlowJSON.self, from: Data(text.utf8)) }

    func testOfficialInviteStagesRewardsAndDeadlines() throws {
        let rows = CoopOfficialInvite.rows(try json("""
        [{"inviteId":1,"title":"Night run","status":0,"shareMode":1,"shareRate":12,"expireTime":"2026-11-02 18:00:00"},
         {"inviteId":2,"title":"Market","status":1,"auditStatus":2,"shareMode":2},
         {"inviteId":3,"title":"Expo","status":1,"shareMode":0,"expireTime":"soon"},
         {"inviteId":4,"title":"  "},{"title":"No id"}]
        """))
        XCTAssertEqual(rows.map(\.id), [1, 2, 3])
        XCTAssertEqual(rows[0].stage, .awaitingYou); XCTAssertTrue(rows[0].actionable)
        XCTAssertEqual(rows[0].reward, .share(rate: "12")); XCTAssertEqual(rows[0].deadline, .monthDay(month: 11, day: 2))
        XCTAssertEqual(rows[1].stage, .notWon); XCTAssertEqual(rows[1].reward, .unconfirmed); XCTAssertEqual(rows[1].deadline, .unconfirmed)
        XCTAssertEqual(rows[2].stage, .awaitingReview); XCTAssertEqual(rows[2].reward, .resources); XCTAssertEqual(rows[2].deadline, .verbatim("soon"))
    }

    func testChapterApplicationStatusesAndDirections() throws {
        let owner = try CoopChapterApplication.rows(json("""
        [{"id":1,"status":0,"source":0},{"id":2,"status":1,"source":1,"offerActive":true},
         {"id":3,"status":1,"offerState":"WITHDRAWN"},{"id":4,"status":1,"replacementOfOfferId":9,"offerId":5,"offerState":"INACTIVE"}]
        """), leg: .owner)
        XCTAssertEqual(owner.map(\.status), [.pendingReview, .offerActive, .offerWithdrawn, .offerPendingReview])
        XCTAssertEqual(owner.map(\.direction), [.received, .sent, .received, .received])
        XCTAssertEqual(owner[2].action, .viewWithdrawal); XCTAssertEqual(owner[0].action, .viewOwned)
        let mine = try CoopChapterApplication.rows(json(#"[{"id":7,"status":1,"source":1}]"#), leg: .mine)
        XCTAssertEqual(mine[0].direction, .received); XCTAssertEqual(mine[0].status, .approvedAwaitingSupply); XCTAssertEqual(mine[0].action, .viewAndSupply)
        XCTAssertThrowsError(try CoopChapterApplication.rows(json(#"[{"status":1}]"#), leg: .mine))
        XCTAssertThrowsError(try CoopChapterApplication.rows(json(#"{"rows":[]}"#), leg: .owner))
    }

    func testInviteTargetMetaFollowsKind() throws {
        let club = CoopFlowTargetCandidate(kind: .club, row: try json(#"{"id":3,"name":"North","memberCount":12,"city":"Hangzhou","address":"ignored"}"#))
        XCTAssertEqual(club?.memberCount, 12); XCTAssertEqual(club?.city, "Hangzhou"); XCTAssertNil(club?.merchantMeta)
        let merchant = CoopFlowTargetCandidate(kind: .merchant, row: try json(#"{"memberId":4,"name":"Cafe","suitActivityTypes":" ","address":"Lake Rd"}"#))
        XCTAssertEqual(merchant?.merchantMeta, "Lake Rd"); XCTAssertNil(merchant?.memberCount)
    }

    func testPermissionClassificationForMerchantOnlyLeg() {
        XCTAssertTrue(CoopListReadFailure.isPermission(CoopFlowFailure.inactiveMerchant(403, nil)))
        XCTAssertTrue(CoopListReadFailure.isPermission(CoopFlowFailure.server(500, "仅商家可查看")))
        XCTAssertFalse(CoopListReadFailure.isPermission(CoopFlowFailure.server(500, "busy")))
        XCTAssertFalse(CoopListReadFailure.isPermission(CoopFlowFailure.malformed))
    }

    func testTopicFilterSeedAndClear() {
        var seed = CoopTopicFilterSeed(rawTopicID: "42", rawTopicName: " 城市漫游 ")
        XCTAssertTrue(seed.isActive)
        XCTAssertEqual(seed.topicID, 42)
        XCTAssertEqual(seed.topicName, "城市漫游")
        XCTAssertEqual(seed.displayLabel, "城市漫游 (#42)")
        XCTAssertEqual(seed.filter([10, 42, 99], topic: { $0 }), [42])
        seed.clear()
        XCTAssertFalse(seed.isActive)
        XCTAssertNil(seed.displayLabel)
        XCTAssertEqual(seed.filter([10, 42, 99], topic: { $0 }), [10, 42, 99])
    }
}

private final class CoopListFakeTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var response = Data(#"{"code":200,"data":[]}"#.utf8)
    var status = 200
    func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); return (response, status) }
}

@MainActor final class CoopListParityServiceTests: XCTestCase {
    func testOfficialInvitesUseGetAndInactiveMerchantIsEmpty() async throws {
        let transport = CoopListFakeTransport()
        let service = CoopFlowService(configuration: try APIConfiguration(baseURL: URL(string: "https://example.com")!), transport: transport)
        let session = try CoopFlowSession(accountID: 2, epoch: 1, token: "fixture-token")
        _ = try await service.read(.officialMerchantInvites, session: session)
        XCTAssertEqual(transport.requests[0].httpMethod, "GET"); XCTAssertNil(transport.requests[0].httpBody)
        XCTAssertTrue(transport.requests[0].url!.path.hasSuffix("api/official/merchant-invites"))
        transport.response = Data(#"{"code":403,"msg":"not merchant","errorCode":"NOT_ACTIVE_MERCHANT"}"#.utf8); transport.status = 403
        let empty = try await service.read(.officialMerchantInvites, session: session)
        XCTAssertEqual(empty, .array([]))
        do { _ = try await service.read(.chapterApplicationsMine, session: session); XCTFail("Inactive merchant accepted") }
        catch { XCTAssertEqual(error as? CoopFlowFailure, .server(403, "not merchant")) }
    }

    func testChapterOwnerLegSendsScope() async throws {
        let transport = CoopListFakeTransport()
        let service = CoopFlowService(configuration: try APIConfiguration(baseURL: URL(string: "https://example.com")!), transport: transport)
        let session = try CoopFlowSession(accountID: 2, epoch: 1, token: "fixture-token")
        _ = try await service.read(.chapterApplicationsOwned(scope: nil), session: session)
        XCTAssertEqual(try JSONDecoder().decode(CoopFlowJSON.self, from: transport.requests[0].httpBody!), .object(["scope": .string("")]))
        XCTAssertThrowsError(try CoopFlowRead.chapterApplicationsOwned(scope: "CLUB").body())
    }
}

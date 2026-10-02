import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class SocialReadTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var operation: @MainActor (URLRequest) async throws -> (Data, Int)
    init(_ operation: @escaping @MainActor (URLRequest) async throws -> (Data, Int)) { self.operation = operation }
    func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); return try await operation(request) }
}
@MainActor final class SocialAccountTests: XCTestCase {
    private func service(_ transport: any HTTPTransport) throws -> SocialAccountService {
        .init(configuration: try .init(baseURL: URL(string: "https://example.com/fixture/")!), transport: transport)
    }
    private func response(_ body: String, code: Int = 200) -> (Data, Int) { (Data("{\"code\":\(code),\"data\":\(body)}".utf8), 200) }
    private func session(_ epoch: UInt64 = 1, token: String = "synthetic-token", role: String = "player") throws -> SocialAccountSession {
        try .init(accountID: 81, epoch: epoch, role: role, token: token)
    }
    private func body(_ request: URLRequest) -> String { String(data: request.httpBody ?? Data(), encoding: .utf8) ?? "" }
    func testPublicProfileUsesPublicRouteAndNoGuestToken() async throws {
        let t = SocialReadTransport { _ in self.response(SocialAccountSyntheticFixtures.profileJSON) }
        let result = try await service(t).profile(memberID: 82, token: nil)
        XCTAssertEqual(result.id, 82); XCTAssertEqual(result.interests.first?.name, "Example walking interest")
        XCTAssertEqual(t.requests[0].url?.path, "/fixture/api/user/public-info")
        XCTAssertNil(t.requests[0].value(forHTTPHeaderField: "Authorization"))
        XCTAssertTrue(body(t.requests[0]).contains("name=\"member_id\"\r\n\r\n82"))
        XCTAssertFalse(body(t.requests[0]).contains("balance"))
    }
    func testPublicProfileUnknownRelationshipAndMissingCountsStayUnknown() throws {
        let p = try JSONDecoder().decode(SocialPublicProfile.self, from: Data(#"{"id":9,"balance":100000,"wechat":"must-not-retain"}"#.utf8))
        XCTAssertNil(p.isFollowed); XCTAssertNil(p.published); XCTAssertNil(p.followers)
        XCTAssertTrue(p.interests.isEmpty)
    }
    func testProfileWrongIDAndInvalidInputCannotBeShown() async throws {
        let t = SocialReadTransport { _ in self.response(SocialAccountSyntheticFixtures.profileJSON) }
        do { _ = try await service(t).profile(memberID: 0, token: nil); XCTFail() } catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        XCTAssertTrue(t.requests.isEmpty)
        do { _ = try await service(t).profile(memberID: 99, token: nil); XCTFail() } catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
    }
    func testGuideUsabilityKeepsMeaningfulNumericTitleAndFiltersUnreadableRows() throws {
        let rows = try SocialAccountSyntheticFixtures.information()
        XCTAssertEqual(rows.filter(\.isUsable).map(\.id), [91, 92]); XCTAssertNil(rows[2].summary)
        let removed = try JSONDecoder().decode(SocialInformation.self, from: Data("{}".utf8))
        XCTAssertTrue(removed.isRemoved); XCTAssertFalse(removed.isUsable)
    }
    func testGuideListAndDetailUseSourceMisspellingAndBodyShapes() async throws {
        let t = SocialReadTransport { request in
            if request.url?.path.hasSuffix("infomation_list") == true { return self.response(SocialAccountSyntheticFixtures.informationJSON) }
            return self.response(#"{"id":91,"title":"Example","contents":"Body"}"#)
        }
        let api = try service(t)
        let rows = try await api.informationList(); XCTAssertEqual(rows.count, 2)
        _ = try await api.information(id: 91)
        XCTAssertEqual(t.requests[0].httpMethod, "POST"); XCTAssertNil(t.requests[0].httpBody)
        XCTAssertEqual(t.requests[1].url?.path, "/fixture/api/common/infomation_detail")
        XCTAssertTrue(body(t.requests[1]).contains("name=\"id\"\r\n\r\n91"))
    }
    func testDeletedInformationIsDistinctFromMalformedAndWrongID() async throws {
        let t = SocialReadTransport { _ in self.response("{}") }
        let result = try await service(t).information(id: 91); XCTAssertTrue(result.isRemoved)
        t.operation = { _ in self.response(#"{"id":92,"title":"Other"}"#) }
        do { _ = try await service(t).information(id: 91); XCTFail() } catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
    }
    func testRewardNormalizationAggregationAndPartialLedger() throws {
        let scan = try SocialAccountSyntheticFixtures.rewards()
        XCTAssertEqual(scan.rewards["7"]?.points, Decimal(15)); XCTAssertNil(scan.rewards["8"]); XCTAssertNil(scan.rewards["9"])
        XCTAssertEqual(scan.fetchedCount, 4); XCTAssertTrue(scan.isComplete)
        XCTAssertFalse(try SocialAccountSyntheticFixtures.rewards(partial: true).isComplete)
        for bad in ["0", "000", "7.0", "-7", "+7", "7x", "٧"] { XCTAssertNil(SocialText.normalizedID(bad)) }
        XCTAssertEqual(SocialText.normalizedID(" 0007 "), "7")
    }
    func testRewardsHaveThreeDifferentKnownAndUnknownStates() throws {
        let members = try SocialAccountSyntheticFixtures.members()
        let page = SocialInvitePage(members: members, total: 4, pageNumber: 1, pageSize: 100)
        let complete = try SocialInviteHistory(page: page, rewardScan: SocialAccountSyntheticFixtures.rewards())
        if case .earned(let reward) = complete.status(for: members[0]) { XCTAssertEqual(reward.points, 15) } else { XCTFail() }
        XCTAssertEqual(complete.status(for: members[1]), .pendingFirstPurchase)
        let partial = try SocialInviteHistory(page: page, rewardScan: SocialAccountSyntheticFixtures.rewards(partial: true))
        XCTAssertEqual(partial.status(for: members[1]), .notSynchronized)
        XCTAssertEqual(SocialInviteHistory(page: page, rewardScan: nil).status(for: members[0]), .notSynchronized)
    }
    func testInviteHistoryKeepsInvitesWhenLedgerFailsButPropagates401() async throws {
        let t = SocialReadTransport { request in
            if request.url?.path.hasSuffix("invite_list") == true { return self.response("{\"rows\":\(SocialAccountSyntheticFixtures.membersJSON),\"total\":4}") }
            throw URLError(.timedOut)
        }
        let api = try service(t), value = try await api.invitationHistory(page: 1, token: "synthetic-token")
        XCTAssertEqual(value.page.members.count, 4); XCTAssertNil(value.rewardScan)
        XCTAssertTrue(body(t.requests[0]).contains("name=\"pageSize\"\r\n\r\n100"))
        XCTAssertTrue(body(t.requests[1]).contains("name=\"pageSize\"\r\n\r\n200"))
        t.operation = { request in
            if request.url?.path.hasSuffix("invite_list") == true { return self.response("{\"rows\":[],\"total\":0}") }
            return (Data(#"{"code":401}"#.utf8), 401)
        }
        do { _ = try await api.invitationHistory(page: 1, token: "synthetic-token"); XCTFail() } catch { XCTAssertEqual(error as? APIError, .unauthorized) }
    }
    func testPaginationUsesReportedTotalAndDeduplicates() throws {
        let members = try SocialAccountSyntheticFixtures.members()
        var p = SocialInvitePagination()
        try p.accept(.init(members: Array(members.prefix(2)), total: 4, pageNumber: 1, pageSize: 2))
        XCTAssertTrue(p.hasMore); XCTAssertEqual(p.total, 4)
        try p.accept(.init(members: [members[1], members[2]], total: 4, pageNumber: 2, pageSize: 2))
        XCTAssertEqual(p.members.map(\.id), [7, 8, 9]); XCTAssertTrue(p.hasMore)
    }
    func testRepeatedPageCannotLoopForever() throws {
        let members = try SocialAccountSyntheticFixtures.members()
        var p = SocialInvitePagination()
        try p.accept(.init(members: members, total: 400, pageNumber: 1, pageSize: 4))
        try p.accept(.init(members: members, total: 400, pageNumber: 2, pageSize: 4))
        XCTAssertTrue(p.continuationInvalid); XCTAssertFalse(p.hasMore)
    }
    func testGuestInvitesNeverSendAndPublicProfileStillLoads() async throws {
        let t = SocialReadTransport { _ in self.response(SocialAccountSyntheticFixtures.profileJSON) }
        let reader = SocialAccountSessionReader(service: try service(t), currentSession: { .init(guestEpoch: 1) })
        do { _ = try await reader.invitationHistory(page: 1); XCTFail() } catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        XCTAssertTrue(t.requests.isEmpty)
        _ = try await reader.publicProfile(memberID: 82); XCTAssertEqual(t.requests.count, 1)
    }
    func testReloginAndRoleChangeDiscardStaleReads() async throws {
        for replacement in [try session(2), try session(1, role: "merchant"), try session(1, token: "replacement") ] {
            var current = try session()
            let t = SocialReadTransport { _ in current = replacement; return self.response(SocialAccountSyntheticFixtures.profileJSON) }
            let reader = SocialAccountSessionReader(service: try service(t), currentSession: { current })
            do { _ = try await reader.publicProfile(memberID: 82); XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        }
    }
    func testStale401DoesNotExpireNewSession() async throws {
        var current = try session(); let next = try session(2); var expirations = 0
        let t = SocialReadTransport { _ in current = next; return (Data(#"{"code":401}"#.utf8), 401) }
        let reader = SocialAccountSessionReader(service: try service(t), currentSession: { current }, onUnauthorized: { _ in expirations += 1 })
        do { _ = try await reader.publicProfile(memberID: 82); XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(expirations, 0)
    }
    func testMalformedCollectionsDoNotBecomeSuccessfulEmptyScreens() async throws {
        for payload in ["null", "{}", "{\"rows\":null}"] {
            let t = SocialReadTransport { _ in self.response(payload) }
            do { _ = try await service(t).informationList(); XCTFail() } catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
        }
    }
    func testDecimalStringTotalCannotHidePartialRewardsAndMalformedTotalFails() throws {
        let json = SocialAccountSyntheticFixtures.rewardsJSON.replacingOccurrences(of: "\"total\":4", with: "\"total\":\"240.0\"")
        let scan = try JSONDecoder().decode(SocialRewardScan.self, from: Data(json.utf8))
        XCTAssertEqual(scan.total, 240); XCTAssertFalse(scan.isComplete)
        for absent in ["{\"rows\":[]}", "{\"rows\":[],\"total\":null}"] {
            let unknown = try JSONDecoder().decode(SocialRewardScan.self, from: Data(absent.utf8))
            XCTAssertFalse(unknown.isComplete)
        }
        for total in ["\"invalid\"", "240.5", "{}", "true", "-1"] {
            let malformed = SocialAccountSyntheticFixtures.rewardsJSON.replacingOccurrences(of: "\"total\":4", with: "\"total\":\(total)")
            XCTAssertThrowsError(try JSONDecoder().decode(SocialRewardScan.self, from: Data(malformed.utf8)))
        }
    }
    func testGuideDestinationsAreActualSourceTabs() {
        XCTAssertEqual(SocialGuideMode.classic.destination, .home); XCTAssertEqual(SocialGuideMode.free.destination, .home); XCTAssertEqual(SocialGuideMode.roam.destination, .roam)
    }
}

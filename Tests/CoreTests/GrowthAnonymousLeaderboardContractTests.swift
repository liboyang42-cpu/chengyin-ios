import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class GrowthAnonymousLeaderboardContractTests: XCTestCase {
    private func object(rank: Any = 1, score: Any = 700) -> [String: Any] {
        let row: [String: Any] = ["rank": rank, "score": score, "nickname": "本人", "avatar": NSNull(), "rankPercentage": "TOP20%", "self": true]
        return ["metric": "point", "period": "total", "list": [row], "me": row]
    }
    private func snapshot(_ object: [String: Any]) throws -> GrowthAnonymousLeaderboardSnapshot {
        try JSONDecoder().decode(GrowthAnonymousLeaderboardSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
    }
    func testValidSnapshotDropsAllIdentityFieldsIncludingSelf() throws {
        let board = try snapshot(object()).projection(query: .init(), limit: 50)
        XCTAssertEqual(board.me.rank, 1); XCTAssertEqual(board.me.score, 700)
        for row in board.list + [board.me] {
            XCTAssertNil(row.memberID); XCTAssertNil(row.nickname); XCTAssertNil(row.avatar)
        }
    }
    func testLegacyMemberIdentifierEvenNullIsRejected() {
        for key in ["memberId", "memberID", "userId", "principal", "profileUrl"] {
            var value = object(), me = value["me"] as! [String: Any]
            me[key] = NSNull(); value["me"] = me
            XCTAssertThrowsError(try snapshot(value), key)
        }
    }
    func testExtraSnapshotSourceObjectIsRejected() {
        var value = object(); value["source"] = ["memberId": 7]
        XCTAssertThrowsError(try snapshot(value))
    }
    func testMissingStringOrFalseSelfCannotIdentifyViewer() {
        for flag in [NSNull(), "true", false, 1] as [Any] {
            var value = object(), me = value["me"] as! [String: Any]
            me["self"] = flag; value["me"] = me
            XCTAssertThrowsError(try snapshot(value))
        }
    }
    func testOtherPlayerNameOrAvatarIsRejected() {
        for field in ["nickname", "avatar"] {
            var value = object(), row = (value["list"] as! [[String: Any]])[0]
            row["self"] = false; row["nickname"] = "匿名玩家"; row[field] = "private"
            value["list"] = [row]
            XCTAssertThrowsError(try snapshot(value))
        }
    }
    func testAnonymousOtherRowIsAcceptedWithoutReidentification() throws {
        var value = object(), row = (value["list"] as! [[String: Any]])[0]
        row["self"] = false; row["nickname"] = "匿名玩家"
        value["list"] = [row]
        var me = value["me"] as! [String: Any]; me["rank"] = 2; value["me"] = me
        let board = try snapshot(value).projection(query: .init(), limit: 50)
        XCTAssertNil(board.list[0].nickname); XCTAssertNil(board.list[0].memberID)
    }
    func testEmptyUnrankedIsSuccessButPlaceholderValuesDisappear() throws {
        var value = object(rank: NSNull(), score: 0); value["list"] = [[String: Any]]()
        let board = try snapshot(value).projection(query: .init(), limit: 50)
        XCTAssertTrue(board.list.isEmpty); XCTAssertNil(board.me.rank)
        XCTAssertNil(board.me.score); XCTAssertNil(board.me.rankPercentage)
    }
    func testQueryMismatchAndOverLimitAreErrors() throws {
        let value = try snapshot(object())
        XCTAssertThrowsError(try value.projection(query: .init(metric: .exp), limit: 50))
        XCTAssertThrowsError(try value.projection(query: .init(period: .week), limit: 50))
        XCTAssertThrowsError(try value.projection(query: .init(), limit: 0))
    }
    func testStringAndFractionScoresAreRejected() {
        for score in ["700", 0.5, true] as [Any] { XCTAssertThrowsError(try snapshot(object(score: score))) }
    }
    func testInt64ScoreDoesNotRoundThroughDouble() throws {
        let value = try snapshot(object(score: Int64.max)).projection(query: .init(), limit: 50)
        XCTAssertEqual(value.me.score, Int(exactly: Int64.max))
    }
    func testInvalidRankOrderAndInconsistentSelfAreRejected() {
        XCTAssertThrowsError(try snapshot(object(rank: 0)))
        var value = object(), me = value["me"] as! [String: Any]
        me["score"] = 701; value["me"] = me
        XCTAssertThrowsError(try snapshot(value))
    }
    func testAnonymousServiceUsesOriginalFormAndNoLegacyRetry() async throws {
        let wire = Wire(data: try JSONSerialization.data(withJSONObject: ["code": 200, "data": object()]), status: 200)
        let service = GrowthCenterService(configuration: try APIConfiguration(baseURL: URL(string: "https://example.test/native")!),
            transport: wire, leaderboardContract: .anonymous)
        let board = try await service.leaderboard(query: .init(), token: "synthetic-7")
        XCTAssertEqual(board.me.score, 700)
        let requests = await wire.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].url?.path, "/native/api/growth/leaderboard/anonymous")
        XCTAssertEqual(requests[0].httpMethod, "POST")
        XCTAssertEqual(requests[0].value(forHTTPHeaderField: "Authorization"), "synthetic-7")
        let body = String(decoding: try XCTUnwrap(requests[0].httpBody), as: UTF8.self)
        XCTAssertEqual(Set(body.split(separator: "&").map(String.init)), ["metric=point", "period=total", "limit=50"])
    }
    func testAnonymousErrorsNeverBecomeEmptySuccessOrLegacyRetry() async throws {
        for (status, code) in [(401, 401), (200, 401), (403, 403), (200, 500)] {
            let wire = Wire(data: Data("{\"code\":\(code),\"msg\":\"synthetic\"}".utf8), status: status)
            let service = GrowthCenterService(configuration: try APIConfiguration(baseURL: URL(string: "https://example.test/native")!),
                transport: wire, leaderboardContract: .anonymous)
            do { _ = try await service.leaderboard(query: .init(), token: "synthetic-7"); XCTFail() }
            catch {
                if code == 401 { XCTAssertEqual(error as? APIError, .unauthorized) }
            }
            let requests = await wire.requests
            XCTAssertEqual(requests.count, 1)
            XCTAssertTrue(requests.allSatisfy { $0.url?.path.hasSuffix("/leaderboard/anonymous") == true })
        }
    }
    private actor Wire: HTTPTransport {
        let data: Data
        let status: Int
        var requests: [URLRequest] = []
        init(data: Data, status: Int) { self.data = data; self.status = status }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request); return (data, status)
        }
    }
}

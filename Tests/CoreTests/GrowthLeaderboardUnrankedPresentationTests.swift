import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Exercises the original public service and its presentation projection only.
/// No endpoint, transport authority, decoder or identity behavior is changed.
final class GrowthLeaderboardUnrankedPresentationTests: XCTestCase {
    private let base = URL(string: "https://example.test/growth-projection")!
    private func payload(rank: String?, query: GrowthBoardQuery = .init()) -> String {
        let rankField = rank.map { "\"rank\":\($0)," } ?? ""
        return """
        {"code":200,"data":{"metric":"\(query.metric.rawValue)","period":"\(query.period.rawValue)",
         "list":[{"rank":2,"memberId":22,"nickname":"Second","score":0},
                 {"rank":1,"memberId":11,"nickname":"First","score":10},
                 {"rank":0,"memberId":33,"nickname":"Original row","score":3}],
         "me":{\(rankField)"memberId":41,"nickname":"Synthetic viewer","avatar":"opaque-avatar",
               "score":0,"rankPercentage":"TOP100%"}}}
        """
    }
    private struct Envelope: Decodable { let data: GrowthLeaderboard }
    private func raw(_ rank: String?, query: GrowthBoardQuery = .init()) throws -> GrowthLeaderboard {
        try JSONDecoder().decode(Envelope.self, from: Data(payload(rank: rank, query: query).utf8)).data
    }
    func testRawDecoderKeepsOriginalZeroNegativeAndPositiveRank() throws {
        for value in [Int.min, -1, 0, 1, 87, Int.max] {
            XCTAssertEqual(try raw(String(value)).me.rank, value)
        }
        XCTAssertNil(try raw(nil).me.rank)
        XCTAssertNil(try raw("null").me.rank)
    }
    func testEveryUnrankedSentinelOmitsPersonalRankWithoutChangingOtherFieldsOrList() throws {
        for rank: String? in [nil, "null", "0", "-1", String(Int.min), "\"0\"", "\"-1\""] {
            let original = try raw(rank), projected = original.withoutUnrankedPlaceholders()
            XCTAssertNil(projected.me.rank)
            XCTAssertNil(projected.me.score)
            XCTAssertNil(projected.me.rankPercentage)
            XCTAssertEqual(projected.me.memberID, original.me.memberID)
            XCTAssertEqual(projected.me.nickname, original.me.nickname)
            XCTAssertEqual(projected.me.avatar, original.me.avatar)
            XCTAssertEqual(projected.metric, original.metric)
            XCTAssertEqual(projected.period, original.period)
            XCTAssertEqual(projected.list, original.list)
            XCTAssertEqual(projected.list.compactMap(\.rank), [2, 1, 0])
            XCTAssertEqual(projected.standing, .unknown)
            XCTAssertNil(GrowthLeaderboardPodium(board: projected).me)
        }
    }
    func testPositiveRankAndRealZeroScoreRemainExactlyUnchanged() throws {
        for rank in [1, 3, 50, 87, Int.max] {
            let original = try raw(String(rank)), projected = original.withoutUnrankedPlaceholders()
            XCTAssertEqual(projected, original)
            XCTAssertEqual(projected.me.rank, rank)
            XCTAssertEqual(projected.me.score, 0)
            XCTAssertEqual(projected.me.rankPercentage, "TOP100%")
            XCTAssertEqual(GrowthLeaderboardPodium(board: projected).me, original.me)
        }
    }
    func testProjectionIsIdempotentAcrossAllRankStates() throws {
        for rank: String? in [nil, "null", "0", "-1", String(Int.min), "1", "87"] {
            let once = try raw(rank).withoutUnrankedPlaceholders()
            XCTAssertEqual(once.withoutUnrankedPlaceholders(), once)
        }
    }
    func testOriginalServiceNormalizesUnrankedForEachExistingMetricAndPeriod() async throws {
        for metric in GrowthBoardMetric.allCases {
            for period in GrowthBoardPeriod.allCases {
                let query = GrowthBoardQuery(metric: metric, period: period)
                let wire = Wire(board: payload(rank: "0", query: query))
                let service = GrowthCenterService(configuration: try APIConfiguration(baseURL: base), transport: wire)
                let board = try await service.leaderboard(query: query, token: "synthetic-token")
                XCTAssertNil(board.me.rank)
                XCTAssertEqual(board.standing, .unknown)
                XCTAssertEqual(board.list, try raw("0", query: query).list)
                XCTAssertEqual(board.metric, metric); XCTAssertEqual(board.period, period)
                let requests = await wire.requests
                XCTAssertEqual(requests.count, 1)
                XCTAssertEqual(requests.first?.url, base.appendingPathComponent("api/growth/leaderboard"))
                XCTAssertEqual(requests.first?.httpMethod, "POST")
                XCTAssertEqual(requests.first?.value(forHTTPHeaderField: "Authorization"), "synthetic-token")
            }
        }
    }
    @MainActor func testSameOwnerRefreshFromRankedToUnrankedClearsCenterAndBoardRank() async throws {
        let wire = Wire(board: payload(rank: "87"))
        let service = GrowthCenterService(configuration: try APIConfiguration(baseURL: base), transport: wire)
        let session = try GrowthCenterReadSession(accountID: 41, epoch: 1, token: "synthetic-token")
        let reader = GrowthCenterSessionReader(service: service, currentSession: { session })
        let model = GrowthCenterReadModel<GrowthCenterOverview>()
        let key = GrowthCenterLoadKey(scope: reader.scope)
        await model.load(key: key, currentKey: { key }) { try await reader.overview() }
        XCTAssertEqual(model.visibleValue(key: key)?.rank.value?.me.rank, 87)
        await wire.replaceBoard(payload(rank: "0"))
        await model.load(key: key, currentKey: { key }) { try await reader.overview() }
        let overview = try XCTUnwrap(model.visibleValue(key: key))
        XCTAssertNil(overview.rank.value?.me.rank)
        XCTAssertEqual(overview.rank.value?.standing, .unknown)
        XCTAssertEqual(overview.center.value?.points, 17)
        XCTAssertEqual(overview.progress.value?.totalCheckins, 2)
        XCTAssertEqual(overview.completedTopicCount, 0)
        XCTAssertEqual(reader.scope, key.scope)
        let board = try await reader.leaderboard(query: .init())
        XCTAssertNil(board.me.rank)
        XCTAssertEqual(board.list, overview.rank.value?.list)
    }
    @MainActor func testSessionReplacementStillRejectsLateUnrankedResultAndUnauthorized() async throws {
        for status in [200, 401] {
            let wire = Wire(board: payload(rank: "0"))
            await wire.pauseBoard()
            let service = GrowthCenterService(configuration: try APIConfiguration(baseURL: base), transport: wire)
            var current: GrowthCenterReadSession? = try .init(accountID: 41, epoch: 1, token: "synthetic-token")
            var expirations = 0
            let reader = GrowthCenterSessionReader(service: service, currentSession: { current }, onUnauthorized: { _ in expirations += 1 })
            let oldScope = reader.scope
            let task = Task { try await reader.leaderboard(query: .init()) }
            guard await wire.waitUntilPaused() else {
                task.cancel()
                await wire.finishBoard(status: status)
                XCTFail("Leaderboard request did not reach the test wire within the bounded wait")
                return
            }
            current = try .init(accountID: 42, epoch: 2, token: "synthetic-next")
            await wire.finishBoard(status: status)
            do { _ = try await task.value; XCTFail("Retired unranked result must not enter the next account") }
            catch { XCTAssertTrue(error is CancellationError) }
            XCTAssertNotEqual(reader.scope, oldScope)
            XCTAssertEqual(expirations, 0)
        }
    }
    private actor Wire: HTTPTransport {
        private var board: String
        private var paused = false
        private var pending: CheckedContinuation<(Data, Int), Error>?
        private(set) var requests: [URLRequest] = []
        init(board: String) { self.board = board }
        func replaceBoard(_ value: String) { board = value }
        func pauseBoard() { paused = true }
        // About five seconds maximum, with cancellation and an explicit caller failure.
        // A contract mismatch must fail this test instead of hanging a later XCTest run.
        func waitUntilPaused() async -> Bool {
            for _ in 0..<500 {
                if pending != nil { return true }
                guard !Task.isCancelled else { return false }
                do { try await Task.sleep(nanoseconds: 10_000_000) }
                catch { return false }
            }
            return pending != nil
        }
        func finishBoard(status: Int) {
            paused = false
            let value = pending; pending = nil
            value?.resume(returning: (Data(board.utf8), status))
        }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            if request.url?.path.hasSuffix("/leaderboard") == true {
                if paused { return try await withCheckedThrowingContinuation { pending = $0 } }
                return (Data(board.utf8), 200)
            }
            if request.url?.path.hasSuffix("/growth/center") == true {
                return (Data(#"{"code":200,"data":{"growth":{"levelNo":1,"expValue":3},"points":17,"badges":[],"missions":[]}}"#.utf8), 200)
            }
            if request.url?.path.hasSuffix("/play/growth") == true {
                return (Data(#"{"code":200,"data":{"level":1,"totalCheckins":2,"totalMileage":0,"streakDays":1}}"#.utf8), 200)
            }
            return (Data(#"{"code":200,"data":[]}"#.utf8), 200)
        }
    }
}

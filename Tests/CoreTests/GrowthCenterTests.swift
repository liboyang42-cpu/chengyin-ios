import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private actor GrowthTestTransport: HTTPTransport {
    struct Reply { let json: String; var status = 200 }
    let replies: [String: Reply]
    private(set) var requests: [URLRequest] = []
    init(_ replies: [String: Reply] = [:]) { self.replies = replies }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        let reply = replies[request.url!.path] ?? .init(json: #"{"code":500}"#)
        return (Data(reply.json.utf8), reply.status)
    }
}
private actor GrowthSuspendedTransport: HTTPTransport {
    private var continuation: CheckedContinuation<(Data, Int), Error>?
    func send(_ request: URLRequest) async throws -> (Data, Int) { try await withCheckedThrowingContinuation { continuation = $0 } }
    func waitUntilReading() async { while continuation == nil { await Task.yield() } }
    func finish(status: Int) { continuation?.resume(returning: (Data(GrowthCenterSyntheticFixtures.boardJSON.utf8), status)); continuation = nil }
}
private actor GrowthLatch<Value> {
    private var continuation: CheckedContinuation<Value, Error>?
    func read() async throws -> Value { try await withCheckedThrowingContinuation { continuation = $0 } }
    func waitUntilReading() async { while continuation == nil { await Task.yield() } }
    func finish(_ value: Value) { continuation?.resume(returning: value); continuation = nil }
    func fail(_ error: Error) { continuation?.resume(throwing: error); continuation = nil }
}
final class GrowthCenterTests: XCTestCase {
    private let centerPath = "/test/api/growth/center"
    private let progressPath = "/test/api/play/growth"
    private let completedPath = "/test/api/play/my-completed"
    private let boardPath = "/test/api/growth/leaderboard"
    private func api(_ transport: any HTTPTransport) throws -> GrowthCenterService {
        try GrowthCenterService(configuration: APIConfiguration(baseURL: URL(string: "https://example.com/test/")!), transport: transport)
    }
    private func replies() -> [String: GrowthTestTransport.Reply] {
        [centerPath: .init(json: GrowthCenterSyntheticFixtures.centerJSON), progressPath: .init(json: GrowthCenterSyntheticFixtures.progressJSON),
         completedPath: .init(json: GrowthCenterSyntheticFixtures.completedJSON), boardPath: .init(json: GrowthCenterSyntheticFixtures.boardJSON)]
    }
    private struct Payload<T: Decodable>: Decodable { let data: T }
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(Payload<T>.self, from: Data(json.utf8)).data
    }
    func testFourExactReadContractsAndRawAuthorizationJSON() async throws {
        let transport = GrowthTestTransport(replies())
        let result = try await api(transport).overview(token: "synthetic-token")
        XCTAssertEqual(result.center.value?.experience, 2450)
        XCTAssertEqual(result.completedTopicCount, 2)
        XCTAssertEqual(result.rank.value?.me.score, 640, "Source score card uses me.score, not center.points")
        let requests = await transport.requests
        XCTAssertEqual(Set(requests.compactMap { $0.url?.path }), Set([centerPath, progressPath, completedPath, boardPath]))
        for request in requests {
            XCTAssertEqual(request.httpMethod, "POST"); XCTAssertNil(request.url?.query)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic-token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            XCTAssertEqual(request.cachePolicy, .reloadIgnoringLocalCacheData)
            let body = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(request.httpBody)) as? [String: Any])
            if request.url?.path == boardPath {
                XCTAssertEqual(Set(body.keys), Set(["metric", "period", "limit"]))
                XCTAssertEqual(body["metric"] as? String, "point"); XCTAssertEqual(body["period"] as? String, "total")
                XCTAssertEqual(body["limit"] as? Int, 1)
            } else { XCTAssertTrue(body.isEmpty) }
        }
    }
    func testEveryMetricPeriodCombinationAndFullListLimit() async throws {
        for metric in GrowthBoardMetric.allCases {
            for period in GrowthBoardPeriod.allCases {
                let json = GrowthCenterSyntheticFixtures.boardJSON.replacingOccurrences(of: #""metric":"point""#, with: "\"metric\":\"\(metric.rawValue)\"").replacingOccurrences(of: #""period":"total""#, with: "\"period\":\"\(period.rawValue)\"")
                let transport = GrowthTestTransport([boardPath: .init(json: json)])
                let board = try await api(transport).leaderboard(query: .init(metric: metric, period: period), token: "synthetic-token")
                XCTAssertEqual(board.metric, metric); XCTAssertEqual(board.period, period); XCTAssertEqual(board.list.count, 4)
                let requests = await transport.requests
                let fields = try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(requests.first?.httpBody)) as? [String: Any])
                XCTAssertEqual(fields["limit"] as? Int, 50)
            }
        }
    }
    func testMismatchedResponseQueryCannotDisplayUnderNewFilter() async throws {
        let transport = GrowthTestTransport(replies())
        do { _ = try await api(transport).leaderboard(query: .init(metric: .exp), token: "synthetic-token"); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
    }
    func testEachPartialFailurePreservesOtherSourcesWithoutFakeZeroes() async throws {
        for path in [centerPath, progressPath, completedPath, boardPath] {
            var fixtures = replies(); fixtures[path] = .init(json: "bad", status: 503)
            let result = try await api(GrowthTestTransport(fixtures)).overview(token: "synthetic-token")
            XCTAssertEqual(result.center.value == nil, path == centerPath)
            XCTAssertEqual(result.progress.value == nil, path == progressPath)
            XCTAssertEqual(result.completed.value == nil, path == completedPath)
            XCTAssertEqual(result.rank.value == nil, path == boardPath)
            XCTAssertEqual(result.completedTopicCount, path == completedPath ? nil : 2)
        }
    }
    func testAnyUnauthorizedSiblingRejectsEntireSnapshot() async throws {
        for path in [centerPath, progressPath, completedPath, boardPath] {
            for reply in [GrowthTestTransport.Reply(json: "broken", status: 401), .init(json: #"{"code":401,"msg":{},"data":[]}"#)] {
                var fixtures = replies(); fixtures[path] = reply
                do { _ = try await api(GrowthTestTransport(fixtures)).overview(token: "synthetic-token"); XCTFail() }
                catch { XCTAssertEqual(error as? APIError, .unauthorized) }
            }
        }
    }
    func testEmptyAndMissingCollectionsAreDifferent() async throws {
        var fixtures = replies()
        fixtures[centerPath] = .init(json: GrowthCenterSyntheticFixtures.emptyCenterJSON)
        fixtures[completedPath] = .init(json: #"{"code":200,"data":[]}"#)
        fixtures[boardPath] = .init(json: GrowthCenterSyntheticFixtures.emptyBoardJSON)
        let result = try await api(GrowthTestTransport(fixtures)).overview(token: "synthetic-token")
        XCTAssertEqual(result.center.value?.experience, 0); XCTAssertEqual(result.center.value?.badges.count, 0)
        XCTAssertEqual(result.completedTopicCount, 0); XCTAssertNil(result.rank.value?.me.rank)
        XCTAssertEqual(result.rank.value?.me.score, 0)
        for json in [#"{"code":200}"#, #"{"code":200,"data":null}"#, #"{"code":200,"data":{}}"#] {
            let service = try api(GrowthTestTransport([centerPath: .init(json: json), completedPath: .init(json: json), boardPath: .init(json: json)]))
            do { _ = try await service.center(token: "synthetic-token"); XCTFail() } catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
            do { _ = try await service.completed(token: "synthetic-token"); XCTFail() } catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
            do { _ = try await service.leaderboard(query: .init(), token: "synthetic-token"); XCTFail() } catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
        }
    }
    func testNumericStringsAreAcceptedButBooleanFractionAndBadShapeRejected() throws {
        let record = try decode(GrowthCenterRecord.self, #"{"data":{"growth":{"levelNo":"2","expValue":"1250"},"points":"12","badges":[],"missions":[]}}"#)
        XCTAssertEqual(record.experience, 1250); XCTAssertEqual(record.level, 2)
        let absent = try decode(GrowthCenterRecord.self, #"{"data":{"growth":{},"badges":[],"missions":[]}}"#)
        XCTAssertNil(absent.level); XCTAssertNil(absent.experience); XCTAssertNil(absent.points)
        for value in ["true", "1.5", "\"invalid\"", "{}"] {
            XCTAssertThrowsError(try decode(GrowthCenterRecord.self, "{\"data\":{\"growth\":{\"levelNo\":\(value)},\"badges\":[],\"missions\":[]}}"))
        }
        XCTAssertThrowsError(try decode(GrowthCenterRecord.self, #"{"data":{"growth":{},"badges":[true],"missions":[]}}"#))
        XCTAssertThrowsError(try decode([GrowthCompletedActivity].self, #"{"data":[{}]}"#))
    }
    func testNullableRankNeverBecomesZeroAndDatesNeverShiftZones() throws {
        let board = try decode(GrowthLeaderboard.self, GrowthCenterSyntheticFixtures.emptyBoardJSON)
        XCTAssertNil(board.me.rank)
        let zero = try decode(GrowthLeaderboard.self, GrowthCenterSyntheticFixtures.emptyBoardJSON.replacingOccurrences(of: #""rank":null"#, with: #""rank":0"#))
        XCTAssertEqual(zero.me.rank, 0)
        XCTAssertEqual(GrowthCenterFormatting.badgeMoment("2026-09-01 00:15:00"), "2026-09-01 00:15")
        XCTAssertEqual(GrowthCenterFormatting.badgeMoment("2024-02-29T23:59:59"), "2024-02-29 23:59")
        for value: String? in [nil, "", "2026-02-29 12:00:00", "2026-13-01 12:00:00", "2026-09-01 24:00:00", "2026-09-01 00:00:60", "2026-09-01T00:00:00Z"] { XCTAssertNil(GrowthCenterFormatting.badgeMoment(value)) }
        XCTAssertNil(GrowthCenterFormatting.nonnegative(-1)); XCTAssertEqual(GrowthCenterFormatting.nonnegative(0), 0)
        XCTAssertNil(GrowthCenterFormatting.mileage(.infinity)); XCTAssertNil(GrowthCenterFormatting.mileage(-1))
    }
    func testBusinessFailureLiteralTextAndHTTPNoticeRemainDistinct() async throws {
        let service = try api(GrowthTestTransport([boardPath: .init(json: #"{"code":503,"msg":"Synthetic maintenance notice"}"#)]))
        do { _ = try await service.leaderboard(query: .init(), token: "synthetic-token"); XCTFail() }
        catch { XCTAssertEqual(GrowthCenterIssue(error), .server("Synthetic maintenance notice")) }
        XCTAssertEqual(GrowthCenterIssue(APIError.httpStatus(503)), .unavailable)
        XCTAssertEqual(GrowthCenterIssue(URLError(.notConnectedToInternet)), .network)
    }
    func testInvalidInputNeverDispatches() async throws {
        let transport = GrowthTestTransport(replies()); let service = try api(transport)
        for token in ["", " ", "bad\nheader"] {
            do { _ = try await service.center(token: token); XCTFail() } catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        }
        for limit in [0, -1, 51] {
            do { _ = try await service.leaderboard(query: .init(), limit: limit, token: "synthetic-token"); XCTFail() } catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        }
        let requests = await transport.requests; XCTAssertTrue(requests.isEmpty)
    }
    @MainActor func testGuestAndUnconfiguredReaderNeverDispatch() async throws {
        let transport = GrowthTestTransport(replies())
        let guest = GrowthCenterSessionReader(service: try api(transport), currentSession: { nil })
        do { _ = try await guest.overview(); XCTFail() } catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        let session = try GrowthCenterReadSession(accountID: 1, epoch: 1, token: "synthetic-token")
        let reader = GrowthCenterSessionReader(service: nil, currentSession: { session })
        do { _ = try await reader.overview(); XCTFail() } catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        let requests = await transport.requests; XCTAssertTrue(requests.isEmpty)
    }
    @MainActor func testStaleSuccessAnd401RejectedAcrossLogoutAccountEpochAndTokenChange() async throws {
        let original = try GrowthCenterReadSession(accountID: 1, epoch: 1, token: "synthetic-first")
        let replacements: [GrowthCenterReadSession?] = [nil,
            try GrowthCenterReadSession(accountID: 2, epoch: 1, token: "synthetic-first"),
            try GrowthCenterReadSession(accountID: 1, epoch: 2, token: "synthetic-first"),
            try GrowthCenterReadSession(accountID: 1, epoch: 1, token: "synthetic-second")]
        for replacement in replacements {
            for status in [200, 401] {
                var current: GrowthCenterReadSession? = original; var unauthorized = 0
                let transport = GrowthSuspendedTransport()
                let reader = GrowthCenterSessionReader(service: try api(transport), currentSession: { current }, onUnauthorized: { _ in unauthorized += 1 })
                let scope = reader.scope
                let task = Task { try await reader.leaderboard(query: .init()) }
                await transport.waitUntilReading(); current = replacement
                XCTAssertNotEqual(reader.scope, scope)
                await transport.finish(status: status)
                do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
                XCTAssertEqual(unauthorized, 0)
            }
        }
    }
    @MainActor func testCurrentUnauthorizedIsForwardedExactlyOnceForCombinedRead() async throws {
        var fixtures = replies(); fixtures[centerPath] = .init(json: #"{"code":401}"#); fixtures[boardPath] = .init(json: #"{"code":401}"#)
        let session = try GrowthCenterReadSession(accountID: 1, epoch: 2, token: "synthetic-token")
        var calls: [GrowthCenterReadSession] = []
        let reader = GrowthCenterSessionReader(service: try api(GrowthTestTransport(fixtures)), currentSession: { session }, onUnauthorized: { calls.append($0) })
        do { _ = try await reader.overview(); XCTFail() } catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        XCTAssertEqual(calls, [session])
    }
    @MainActor func testNewestRefreshAndFilterOwnResultAndOldIssueCannotReplaceIt() async {
        let scope = UUID(); let oldKey = GrowthCenterLoadKey(scope: scope, query: .init())
        let newKey = GrowthCenterLoadKey(scope: scope, query: .init(metric: .exp, period: .week))
        var key = oldKey; let model = GrowthCenterReadModel<String>(); let latch = GrowthLatch<String>()
        let old = Task { await model.load(key: oldKey, currentKey: { key }) { try await latch.read() } }
        await latch.waitUntilReading(); key = newKey
        await model.load(key: newKey, currentKey: { key }) { "new query" }
        await latch.fail(APIError.httpStatus(503)); await old.value
        XCTAssertEqual(model.visibleValue(key: newKey), "new query"); XCTAssertNil(model.visibleValue(key: oldKey)); XCTAssertNil(model.visibleIssue(key: newKey))
        XCTAssertNil(model.visibleValue(key: GrowthCenterLoadKey(scope: UUID(), query: newKey.query)))
    }
    @MainActor func testCancellationNavigationAndScopeChangesDiscardDelayedResults() async {
        for action in 0..<3 {
            let original = GrowthCenterLoadKey(scope: UUID()); var key = original
            let model = GrowthCenterReadModel<String>(); let latch = GrowthLatch<String>()
            let task = Task { await model.load(key: original, currentKey: { key }) { try await latch.read() } }
            await latch.waitUntilReading()
            if action == 0 { task.cancel() } else if action == 1 { model.cancelPending() } else { key = GrowthCenterLoadKey(scope: UUID()) }
            await latch.finish("stale"); await task.value
            XCTAssertNil(model.visibleValue(key: original)); XCTAssertNil(model.visibleIssue(key: original))
        }
    }
    @MainActor func testSameQueryRefreshWinsOverLateSuccess() async {
        let key = GrowthCenterLoadKey(scope: UUID(), query: .init())
        let model = GrowthCenterReadModel<String>(); let slow = GrowthLatch<String>()
        let first = Task { await model.load(key: key, currentKey: { key }) { try await slow.read() } }
        await slow.waitUntilReading()
        await model.load(key: key, currentKey: { key }) { "refreshed" }
        await slow.finish("old"); await first.value
        XCTAssertEqual(model.visibleValue(key: key), "refreshed")
    }
    @MainActor func testCanceledReaderDoesNotForwardLateUnauthorized() async throws {
        let session = try GrowthCenterReadSession(accountID: 1, epoch: 1, token: "synthetic-token")
        let transport = GrowthSuspendedTransport(); var unauthorized = 0
        let reader = GrowthCenterSessionReader(service: try api(transport), currentSession: { session }, onUnauthorized: { _ in unauthorized += 1 })
        let task = Task { try await reader.leaderboard(query: .init()) }
        await transport.waitUntilReading(); task.cancel(); await transport.finish(status: 401)
        do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(unauthorized, 0)
    }

}

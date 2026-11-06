import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum NativeChannelProgressFixtures {
    static func decode<T: Decodable>(_ text: String, as: T.Type = T.self) throws -> T {
        let decoder = JSONDecoder(); decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: Data(text.utf8))
    }
    static let boardJSON = #"{"board_key":"completion","title":"Completion","metric":"PERCENT","period":"ALL","scope":"CHANNEL","subject_type":"MEMBER","team_rollup":null,"row_limit":30,"visible":true,"revision":2,"topic_id":17,"activity_id":23,"filter_schema_json":{"completed":"boolean","team_id":"int"}}"#
    static func board() throws -> NativeChannelProgressBoard { try decode(boardJSON) }
    static func identity(epoch: String = "7", actorID: Int64 = 101) throws -> NativeChannelProgressIdentity {
        try .init(actorID: actorID, namespace: "CN", origin: URL(string: "https://progress.example.org")!, sessionEpoch: epoch)
    }
    static func authority() throws -> NativeChannelProgressAuthoritySnapshot {
        try .init(identity: identity(), channelID: 5, authorizationVersion: "verified-policy-9", metadataVersion: 2, permissionVersion: 3,
            endpointApprovalRevision: UUID(), viewerRevision: 4, operations: [.definitions,.overview,.top,.detail,.best,.recent,.version,.meter,.privacy,.savePrivacy,.receipt])
    }
    static func privacy(revision: Int64 = 0) throws -> NativeChannelProgressPrivacy {
        try decode("""
        {"aggregate_scope":"PUBLIC","detail_scope":"TEAM","photo_scope":"TEAM","leaderboard_scope":"IN","revision":\(revision),"updated_at":null,"verified_at":null,"applies_to":"CHANNEL_PROGRESS","effective":{"aggregate_scope":"CHANNEL","detail_scope":"TEAM"}}
        """)
    }
    static func values() throws -> NativeChannelProgressPrivacyValues { try .init(aggregateScope: .onlyMe, detailScope: .onlyMe, photoScope: .onlyMe, leaderboardScope: .out) }
    static func command(id: String = "original_request_0001") throws -> NativeChannelProgressPrivacyCommand { try .init(values: values(), revision: 0, updatedAt: nil, requestID: id) }
    static func receipt(_ command: NativeChannelProgressPrivacyCommand, revision: Int64 = 1) throws -> NativeChannelProgressPrivacy {
        try decode("""
        {"aggregate_scope":"\(command.aggregateScope.rawValue)","detail_scope":"\(command.detailScope.rawValue)","photo_scope":"\(command.photoScope.rawValue)","leaderboard_scope":"\(command.leaderboardScope.rawValue)","revision":\(revision),"updated_at":"2026-10-23T16:00:00Z","verified_at":null,"applies_to":"CHANNEL_PROGRESS","request_id":"\(command.requestId)","status":"APPLIED","replayed":true}
        """)
    }
}
final class NativeChannelProgressMemoryStorage: NativeChannelProgressJournalStorage {
    var rows: [String:Data] = [:]
    var failWrites = false
    var failRemoves = false
    func read(_ key: String) throws -> Data? { rows[key] }
    func write(_ data: Data, key: String) throws { if failWrites { throw NativeChannelProgressError.persistence }; rows[key] = data }
    func remove(_ key: String) throws { if failRemoves { throw NativeChannelProgressError.persistence }; rows[key] = nil }
}
final class NativeChannelProgressRecordingTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var responses: [(Data,Int)] = []
    func send(_ request: URLRequest) async throws -> (Data,Int) {
        requests.append(request); return responses.removeFirst()
    }
}
final class NativeChannelProgressTests: XCTestCase {
    func testHiddenAndVisibleEmptyRemainDifferent() throws {
        let hidden: NativeChannelProgressPage = try NativeChannelProgressFixtures.decode(#"{"visible":false,"revision":"r1","me":{"rank":null,"rank_known":false,"state":"UNCONFIRMED"}}"#)
        let empty: NativeChannelProgressPage = try NativeChannelProgressFixtures.decode(#"{"visible":true,"revision":"r1","list":[],"has_more":false,"next_cursor":null}"#)
        XCTAssertNil(try hidden.validated().list); XCTAssertEqual(try empty.validated().list, [])
        let leaking: NativeChannelProgressPage = try NativeChannelProgressFixtures.decode(#"{"visible":false,"revision":"r1","list":[]}"#)
        XCTAssertThrowsError(try leaking.validated())
    }
    func testNullRankAndUnknownFactsNeverBecomeZero() throws {
        let unknown: NativeChannelProgressRow = try NativeChannelProgressFixtures.decode(#"{"rank":null,"rank_known":false,"state":"UNCONFIRMED","reason":"FACT_SOURCE_UNAVAILABLE"}"#)
        XCTAssertEqual(NativeChannelProgressRank(unknown), .unknown); XCTAssertNil(unknown.percent); XCTAssertNil(unknown.done)
        let best: NativeChannelProgressRow = try NativeChannelProgressFixtures.decode(#"{"visible":true,"rank":null,"rank_known":false,"state":"NO_COMPLETED_EFFORT"}"#)
        XCTAssertEqual(NativeChannelProgressRank(best), .unranked); XCTAssertNil(best.rank)
    }
    func testCursorCannotCrossRevisionQueryOrReadKind() throws {
        let board = try NativeChannelProgressFixtures.board(), query = try NativeChannelProgressQuery(board: board, period: "ALL")
        let first: NativeChannelProgressPage = try NativeChannelProgressFixtures.decode(#"{"visible":true,"revision":"r1","list":[],"has_more":true,"next_cursor":"opaque1"}"#)
        let second: NativeChannelProgressPage = try NativeChannelProgressFixtures.decode(#"{"visible":true,"revision":"r2","list":[],"has_more":false}"#)
        var buffer = NativeChannelProgressPageBuffer(); try buffer.replace(first, query: query, detail: false)
        XCTAssertThrowsError(try buffer.append(second, query: query, detail: false, requestedCursor: "opaque1"))
        XCTAssertThrowsError(try buffer.append(first, query: query, detail: true, requestedCursor: "opaque1"))
        let other = try NativeChannelProgressQuery(board: board, period: "TOPIC")
        XCTAssertThrowsError(try buffer.append(first, query: other, detail: false, requestedCursor: "opaque1"))
        let changedLimit = try NativeChannelProgressQuery(board: board, period: "ALL", limit: 10)
        XCTAssertThrowsError(try buffer.append(first, query: changedLimit, detail: false, requestedCursor: "opaque1"))
        XCTAssertEqual(buffer.page, first)
    }
    @MainActor func testJournalRetainsOriginalAcrossEpochButNotActor() throws {
        let storage = NativeChannelProgressMemoryStorage(), command = try NativeChannelProgressFixtures.command()
        let first = try NativeChannelProgressPrivacyJournal(identity: NativeChannelProgressFixtures.identity(), storage: storage)
        try first.saveBeforeDispatch(command)
        let relogin = try NativeChannelProgressPrivacyJournal(identity: NativeChannelProgressFixtures.identity(epoch: "8"), storage: storage)
        XCTAssertEqual(try relogin.restore(), command)
        let other = try NativeChannelProgressPrivacyJournal(identity: NativeChannelProgressFixtures.identity(actorID: 102), storage: storage)
        XCTAssertNil(try other.restore())
        XCTAssertThrowsError(try relogin.saveBeforeDispatch(NativeChannelProgressFixtures.command(id: "replacement_request_02")))
        XCTAssertEqual(try first.restore(), command)
        try relogin.settle(command); XCTAssertNil(try first.restore())
    }
    @MainActor func testWriteFailureCannotCreateDispatchableCommand() throws {
        let storage = NativeChannelProgressMemoryStorage(); storage.failWrites = true
        let journal = try NativeChannelProgressPrivacyJournal(identity: NativeChannelProgressFixtures.identity(), storage: storage)
        XCTAssertThrowsError(try journal.saveBeforeDispatch(NativeChannelProgressFixtures.command())); XCTAssertNil(try journal.restore())
    }
    func testRequestBodyUsesOriginalFourIndependentScopesAndCAS() throws {
        let command = try NativeChannelProgressFixtures.command()
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: command.wireBody()) as? [String:Any])
        XCTAssertEqual(object["aggregate_scope"] as? String, "SELF"); XCTAssertEqual(object["photo_scope"] as? String, "SELF")
        XCTAssertEqual(object["leaderboard_scope"] as? String, "OUT"); XCTAssertEqual(object["expected_revision"] as? Int, 0)
        XCTAssertEqual(object["request_id"] as? String, command.requestId); XCTAssertNil(object["channel_id"])
        XCTAssertThrowsError(try NativeChannelProgressPrivacyValues(aggregateScope: .publicAccess, detailScope: .publicAccess, photoScope: .team, leaderboardScope: .included))
    }
    func testFourRealReadRoutesAndFilteringDoNotCreateNewURLs() async throws {
        let transport = NativeChannelProgressRecordingTransport()
        let page = Data(#"{"code":200,"data":{"visible":true,"revision":"r","list":[],"has_more":false}}"#.utf8)
        let best = Data(#"{"code":200,"data":{"visible":true,"rank":null,"rank_known":false,"state":"NO_COMPLETED_EFFORT"}}"#.utf8)
        transport.responses = [(page,200),(page,200),(best,200),(page,200)]
        let service = NativeChannelProgressService(configuration: try APIConfiguration(baseURL: NativeChannelProgressFixtures.identity().origin), transport: transport)
        let query = try NativeChannelProgressQuery(board: NativeChannelProgressFixtures.board(), period: "ALL", completed: true, teamID: 8)
        _ = try await service.page(channelID: 5, query: query, detail: false, cursor: nil, token: "test-token")
        _ = try await service.page(channelID: 5, query: query, detail: true, cursor: nil, token: "test-token")
        _ = try await service.best(channelID: 5, query: query, token: "test-token")
        _ = try await service.recent(channelID: 5, query: query, cursor: nil, token: "test-token")
        XCTAssertEqual(transport.requests.map { $0.url!.path }, ["/api/channel/5/board/completion/top","/api/channel/5/board/completion/detail","/api/channel/5/board/completion/me/best","/api/channel/5/board/completion/me/recent"])
        let filter = URLComponents(url: transport.requests[1].url!, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(filter.first { $0.name == "filter[team_id]" }?.value, "8")
        XCTAssertTrue(transport.requests.allSatisfy { $0.httpMethod == "GET" && !$0.httpShouldHandleCookies })
    }
    func testUnknownOuterEnvelopeCannotBecomeApplied() async throws {
        let transport = NativeChannelProgressRecordingTransport()
        transport.responses = [(Data(#"{"code":200,"outcome_known":false,"data":{"aggregate_scope":"SELF","detail_scope":"SELF","photo_scope":"SELF","leaderboard_scope":"OUT","revision":1,"updated_at":"2026-10-23T16:00:00Z","applies_to":"CHANNEL_PROGRESS","request_id":"original_request_0001","status":"APPLIED"}}"#.utf8),200)]
        let service = NativeChannelProgressService(configuration: try APIConfiguration(baseURL: NativeChannelProgressFixtures.identity().origin), transport: transport)
        do { _ = try await service.save(NativeChannelProgressFixtures.command(), token: "test-token"); XCTFail("Unknown outer result became applied") }
        catch { XCTAssertEqual(error as? NativeChannelProgressError, .server(status: 500, code: "OUTCOME_UNKNOWN")) }
        XCTAssertEqual(transport.requests.count, 1)
    }
}

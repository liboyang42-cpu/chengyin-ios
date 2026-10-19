import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class ThemeRecordsHTTP: HTTPTransport {
    var requests: [URLRequest] = []
    var body = #"{"code":200,"data":[]}"#
    func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); return (Data(body.utf8), 200) }
}

@MainActor private final class RecordsReader: PlayThemeRecordsReading {
    var pages: [[PlayWireValue]] = []
    var befores: [Int?] = []
    var cardResult: Result<PlayWireValue, Error> = .success(.null)
    var cardCalls = 0
    func history(topicID: Int, beforeSessionID: Int?) async throws -> [PlayWireValue] { befores.append(beforeSessionID); return pages.isEmpty ? [] : pages.removeFirst() }
    func card(sessionID: Int) async throws -> PlayWireValue { cardCalls += 1; return try cardResult.get() }
}

@MainActor final class PlayThemeRecordsTests: XCTestCase {
    private func wire(_ json: String) throws -> PlayWireValue { try JSONDecoder().decode(PlayWireValue.self, from: Data(json.utf8)) }

    func testHistoryRowAndCardMirrorMiniProgramFallbacks() throws {
        XCTAssertEqual(PlayThemeHistoryRow(try wire(#"{"sessionId":5,"result":{"title":" T "}}"#))?.outcome, .titled("T"))
        XCTAssertEqual(PlayThemeHistoryRow(try wire(#"{"sessionId":5,"result":{"success":true}}"#))?.outcome, .completed)
        XCTAssertEqual(PlayThemeHistoryRow(try wire(#"{"sessionId":5,"result":{"reason":"HP"}}"#))?.outcome, .ended)
        let open = try XCTUnwrap(PlayThemeHistoryRow(try wire(#"{"sessionId":"6","scope":"TEAM"}"#)))
        XCTAssertEqual(open.outcome, .inProgress); XCTAssertFalse(open.hasCard); XCTAssertTrue(open.isTeam)
        XCTAssertNil(PlayThemeHistoryRow(try wire(#"{"sessionId":0}"#)))
        let card = PlayThemeResultCard(try wire(#"{"hp":7,"luck":2.5,"luckName":"Fortune","actions":3,"rescues":0,"items":[{"name":"Key","quantity":1},{"name":"","quantity":2}],"unlocks":{"known":[{"title":"Dawn"}]},"nextScene":{"name":"Market"}}"#),
                                       sessionID: 5, view: try wire(#"{"hpName":"Stamina","actionName":"Moves"}"#))
        XCTAssertNil(card.title)
        XCTAssertEqual(card.values, [.init(name: .server("Stamina"), value: "7"), .init(name: .server("Fortune"), value: "2.5"),
                                     .init(name: .server("Moves"), value: "3"), .init(name: .rescues, value: "0")])
        XCTAssertEqual(card.items, [.init(name: "Key", quantity: 1)])
        XCTAssertEqual(card.knownEndings, ["Dawn"]); XCTAssertEqual(card.nextScene, "Market")
        XCTAssertEqual(PlayThemeResultCard(try wire(#"{"hp":"7"}"#), sessionID: 5).values, [], "only numeric values, like typeof === 'number'")
    }

    func testServiceQueriesExactly() async throws {
        let http = ThemeRecordsHTTP()
        let api = PlayExperienceService(configuration: try .init(baseURL: URL(string: "https://fixture.example/root/")!), transport: http, enabled: [.reads])
        _ = try await api.themeHistory(topicID: 71, beforeSessionID: 881, token: "fixture-token")
        let first = try XCTUnwrap(http.requests.first)
        XCTAssertEqual(first.httpMethod, "GET"); XCTAssertEqual(first.url?.path, "/root/api/play/theme/history")
        XCTAssertEqual(first.url?.query, "beforeSessionId=881&limit=20&topicId=71")
        http.body = #"{"code":200,"data":{"title":"x"}}"#
        _ = try await api.themeCard(sessionID: 9, token: "fixture-token")
        XCTAssertEqual(http.requests.last?.url?.query, "sessionId=9")
        http.body = #"{"code":200,"data":{"rows":[]}}"#
        do { _ = try await api.themeHistory(topicID: 71, beforeSessionID: nil, token: "fixture-token"); XCTFail("non-array accepted") }
        catch { XCTAssertEqual(error as? PlayExperienceError, .malformed) }
    }

    func testPagingDedupesAndCardsLoadOnlyWithResults() async throws {
        let reader = RecordsReader()
        let first = try (0..<20).map { index -> PlayWireValue in
            let result = index == 0 ? ",\"result\":{\"success\":true}" : ""
            return try wire("{\"sessionId\":\(100 - index)\(result)}")
        }
        reader.pages = [first,
                        [try wire(#"{"sessionId":81}"#), try wire(#"{"sessionId":70}"#)]]
        let model = PlayThemeRecordsCoordinator(topicID: 71, reader: reader)
        await model.open()
        XCTAssertEqual(model.rows.count, 20); XCTAssertTrue(model.hasMore)
        await model.loadMore()
        XCTAssertEqual(reader.befores, [nil, 81])
        XCTAssertEqual(Array(model.rows.map(\.sessionID).suffix(2)), [81, 70])
        XCTAssertEqual(model.rows.count, 21, "duplicate 81 dropped")
        XCTAssertFalse(model.hasMore)
        await model.openCard(sessionID: 99)
        XCTAssertEqual(reader.cardCalls, 0, "no result, no card read"); XCTAssertNil(model.cardSessionID)
        reader.cardResult = .failure(PlayExperienceError.unknownResult)
        await model.openCard(sessionID: 100)
        XCTAssertEqual(model.issue, .cardFailed)
        reader.cardResult = .success(try wire(#"{"title":"Done"}"#))
        await model.openCard(sessionID: 100)
        XCTAssertEqual(model.card?.title, "Done"); XCTAssertNil(model.issue)
        model.closeCard(); XCTAssertNil(model.card)
        reader.cardResult = .failure(PlayExperienceError.rejected(403, nil))
        await model.openCard(sessionID: 100)
        XCTAssertEqual(model.issue, .refused)
    }
}

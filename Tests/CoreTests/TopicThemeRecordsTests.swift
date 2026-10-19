import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class RecordsTransport: HTTPTransport {
    var requests: [URLRequest] = []
    let reply: (URLRequest) -> (Data, Int)
    init(_ reply: @escaping (URLRequest) -> (Data, Int)) { self.reply = reply }
    func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); return reply(request) }
}

/// w2-07: topic "我的游玩记录" reads (`api/play/theme/history`, `api/play/theme/card`).
final class TopicThemeRecordsTests: XCTestCase {
    private func service(_ transport: RecordsTransport) throws -> TopicService {
        TopicService(configuration: try APIConfiguration(baseURL: URL(string: "https://api.example.invalid")!), transport: transport)
    }

    func testHistoryRequestAndTitleFallbacks() async throws {
        let body = #"{"code":200,"data":[{"sessionId":9,"topicId":31,"result":{"title":"Synthetic finale"}},{"sessionId":8,"topicId":31,"result":{"success":true}},{"sessionId":7,"result":{"reason":"timeout"}},{"sessionId":6,"result":{}}]}"#
        let transport = RecordsTransport { _ in (Data(body.utf8), 200) }
        let page = try await service(transport).themeHistory(topicID: 31, beforeSessionID: 10, token: "synthetic-token")
        let request = try XCTUnwrap(transport.requests.first)
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(request.url?.path, "/api/play/theme/history")
        let items = URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") }), ["topicId": "31", "limit": "20", "beforeSessionId": "10"])
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic-token")
        XCTAssertEqual(page.rows.map(\.title), [.server("Synthetic finale"), .completed, .ended, .playing])
        XCTAssertFalse(page.hasMore); XCTAssertNil(page.nextBefore)
    }

    func testFullPageAllowsMoreAndForeignTopicIsRejected() async throws {
        let full = "{\"code\":200,\"data\":[" + (1...20).map { "{\"sessionId\":\($0),\"result\":{}}" }.joined(separator: ",") + "]}"
        let page = try await service(RecordsTransport { _ in (Data(full.utf8), 200) }).themeHistory(topicID: 31, token: "synthetic-token")
        XCTAssertTrue(page.hasMore); XCTAssertEqual(page.nextBefore, 20)
        let foreign = #"{"code":200,"data":[{"sessionId":1,"topicId":99,"result":{}}]}"#
        do { _ = try await service(RecordsTransport { _ in (Data(foreign.utf8), 200) }).themeHistory(topicID: 31, token: "synthetic-token"); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
    }

    func testCardDecodesValuesItemsAndUnauthorizedIsSurfaced() async throws {
        let card = #"{"code":200,"data":{"title":"Run","hp":3,"hpName":"Stamina","luck":2,"items":[{"name":"Key","quantity":2}],"medals":[{"name":"Star"}],"epilogues":[{"name":"Dawn","line":"Synthetic line"}],"nextScene":{"name":"Harbor"}}}"#
        let value = try await service(RecordsTransport { _ in (Data(card.utf8), 200) }).themeCard(sessionID: 9, token: "synthetic-token")
        XCTAssertEqual(value.values.map { $0.kind }, ["hp", "luck"])
        XCTAssertEqual(value.values.first?.label, "Stamina")
        XCTAssertEqual(value.items, [.init(name: "Key", quantity: 2)])
        XCTAssertEqual(value.nextScene, "Harbor")
        do { _ = try await service(RecordsTransport { _ in (Data(#"{"code":401}"#.utf8), 200) }).themeCard(sessionID: 9, token: "synthetic-token"); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .unauthorized) }
    }
}

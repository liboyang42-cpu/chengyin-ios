import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private actor ObjectCardTestTransport: HTTPTransport {
    let json: String
    let status: Int
    private(set) var requests: [URLRequest] = []
    init(json: String, status: Int = 200) { self.json = json; self.status = status }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); return (Data(json.utf8), status)
    }
}
private actor ObjectCardPendingTransport: HTTPTransport {
    private var pending: CheckedContinuation<(Data, Int), Error>?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        try await withCheckedThrowingContinuation { pending = $0 }
    }
    func waitForRequest() async { while pending == nil { await Task.yield() } }
    func finish(code: Int) {
        let data = code == 200 ? ",\"data\":\(ObjectCardSyntheticFixtures.collectionJSON)" : ""
        pending?.resume(returning: (Data("{\"code\":\(code)\(data)}".utf8), 200)); pending = nil
    }
}
final class ObjectCardTests: XCTestCase {
    private func service(_ transport: any HTTPTransport) throws -> ObjectCardService {
        try ObjectCardService(configuration: APIConfiguration(baseURL: URL(string: "https://example.com/")!), transport: transport)
    }
    func testSourceFormAndStringStatus() async throws {
        let transport = ObjectCardTestTransport(json: "{\"code\":\"200\",\"data\":\(ObjectCardSyntheticFixtures.collectionJSON)}")
        let value = try await service(transport).list(category: .books, token: "synthetic-token")
        XCTAssertEqual(value.total, 52); XCTAssertEqual(value.cards.count, 2); XCTAssertTrue(value.isTruncated)
        let requests = await transport.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.httpMethod, "POST"); XCTAssertEqual(request.url?.path, "/api/object-card/list")
        XCTAssertNil(request.url?.query)
        let body = try XCTUnwrap(String(data: request.httpBody ?? Data(), encoding: .utf8))
        XCTAssertTrue(body.contains("pageNum=1")); XCTAssertTrue(body.contains("pageSize=40"))
        XCTAssertTrue(body.contains("category=")); XCTAssertFalse(body.contains("userId"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded")
    }
    func testFramesFallbackAndStatus() throws {
        let cards = try ObjectCardSyntheticFixtures.collection().cards
        XCTAssertTrue(cards[0].generating); XCTAssertEqual(cards[0].frame(at: -1), cards[0].frames[1])
        XCTAssertFalse(cards[1].generating); XCTAssertEqual(cards[1].frame(at: 99), "")
        let row = #"{"id":"x","title":"Synthetic","sourceUrl":"https://fixtures.invalid/a.png","cutoutUrl":"https://fixtures.invalid/c.png","frames":[null,7,"",{"url":"ignored"}],"cutoutBox":[0.1,0.2,0.4,0.5]}"#
        let card = try JSONDecoder().decode(ObjectCard.self, from: Data(row.utf8))
        XCTAssertEqual(card.frames, [card.sourceURL]); XCTAssertEqual(card.thumbnail, card.cutoutURL)
        XCTAssertEqual(card.cutoutBox, [0.1,0.2,0.4,0.5]); XCTAssertEqual(card.cardStyle, "foil")
    }
    func testMalformedRowsAndTotalsFailClosed() {
        for raw in [#"{"list":[],"total":-1}"#, #"{"list":[],"total":1.5}"#, #"{"list":[{"id":1}],"total":1}"#, #"{"list":[{"title":"x"}],"total":1}"#] {
            XCTAssertThrowsError(try JSONDecoder().decode(ObjectCardCollection.self, from: Data(raw.utf8)))
        }
    }
    func testInvalidBoxIsIgnored() throws {
        for box in ["[0,0,2,1]", "[-1,0,1,1]", "[0,0,0,1]", "[0,0,1]", "[0,0,\"1\",1]"] {
            let json = "{\"id\":1,\"title\":\"Synthetic\",\"cutoutBox\":\(box)}"
            XCTAssertNil(try JSONDecoder().decode(ObjectCard.self, from: Data(json.utf8)).cutoutBox)
        }
    }
    func testExactCategoriesAndBadgeRouteNormalization() {
        XCTAssertEqual(ObjectCardCategory.allCases.map(\.rawValue), ["", "电子产品", "服饰", "鞋包", "食物饮料", "书籍文具", "玩具摆件", "日用杂物", "其他"])
        let p = ObjectBadgeDetailParameters(query: ["rarity":"99", "style":"unknown", "img":"javascript:bad", "name":" "], fallbackName: "Badge")
        XCTAssertEqual(p.rarity, 4); XCTAssertEqual(p.style, "enamel"); XCTAssertEqual(p.image, ""); XCTAssertEqual(p.name, "Badge")
        XCTAssertEqual(ObjectBadgeDetailParameters(query: ["rarity":"-1", "style":"glow"], fallbackName: "Badge").rarity, 0)
    }
    func testMediaPolicyRejectsUnsafeAndUnapprovedURLs() throws {
        let policy = ObjectCardMediaPolicy(approvedOrigins: ["https://media.example.com"])
        XCTAssertNoThrow(try policy.validate("https://media.example.com/image.png?signature=synthetic"))
        for raw in ["http://media.example.com/a.png", "https://evil.example.com/a.png", "https://media.example.com:444/a.png", "https://u:p@media.example.com/a.png", "https://localhost/a.png", "https://127.0.0.1/a.png", "https://media.example.com/a.png#fragment"] {
            XCTAssertThrowsError(try policy.validate(raw))
        }
    }
    func testBadgeTracksAndChinaDates() {
        for category in ["CO_CREATE", "CO-CREATE", "COCREATE"] { XCTAssertEqual(ObjectBadgePresentation.track(category: category), 4) }
        XCTAssertEqual(ObjectBadgePresentation.track(category: "unknown"), 0)
        XCTAssertEqual(ObjectBadgePresentation.date("2026-10-01 23:20:00"), "2026-10-01")
        XCTAssertEqual(ObjectBadgePresentation.date("2026-10-01T23:20:00Z"), "2026-10-02")
        XCTAssertEqual(ObjectBadgePresentation.date("2024-02-29"), "2024-02-29")
        for raw in ["2026-02-29", "2026-13-01", "2026-10-01 25:00:00", "2026-10-01T00:00:00+25:00", "garbage"] { XCTAssertNil(ObjectBadgePresentation.date(raw)) }
    }
    @MainActor func testFailedFilterKeepsPriorSelectionAndScopeResetClears() async throws {
        let reader = ObjectCardFixtureReader(), model = ObjectCardCollectionModel()
        await model.load(category: .all, reader: reader)
        reader.failNext = true
        await model.load(category: .books, reader: reader)
        XCTAssertTrue(model.failed); XCTAssertEqual(model.category, .all); XCTAssertEqual(model.collection?.total, 52)
        reader.rotateScope(); reader.failNext = true
        await model.load(category: .food, reader: reader)
        XCTAssertNil(model.collection); XCTAssertTrue(model.failed)
    }
    @MainActor func testStaleUnauthorizedCannotExpireNewSession() async throws {
        let transport = ObjectCardPendingTransport()
        var session: ObjectCardSession? = try .init(accountID: 1, epoch: 1, token: "synthetic-a")
        var unauthorized = 0
        let reader = ObjectCardSessionReader(service: try service(transport), currentSession: { session }, onUnauthorized: { _ in unauthorized += 1 })
        let prior = reader.scope
        let task = Task { try await reader.list(category: .all) }
        await transport.waitForRequest()
        session = try .init(accountID: 1, epoch: 2, token: "synthetic-b")
        XCTAssertNotEqual(reader.scope, prior)
        await transport.finish(code: 401)
        do { _ = try await task.value; XCTFail("stale response accepted") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(unauthorized, 0)
    }
    @MainActor func testStaleSuccessCannotRevealPreviousOwnerCards() async throws {
        let transport = ObjectCardPendingTransport()
        var session: ObjectCardSession? = try .init(accountID: 1, epoch: 1, token: "synthetic-a")
        let reader = ObjectCardSessionReader(service: try service(transport), currentSession: { session })
        let model = ObjectCardCollectionModel()
        let task = Task { await model.load(category: .all, reader: reader) }
        await transport.waitForRequest()
        session = try .init(accountID: 2, epoch: 2, token: "synthetic-b")
        model.invalidate()
        await transport.finish(code: 200); await task.value
        XCTAssertNil(model.collection); XCTAssertNil(model.loadedScope); XCTAssertFalse(model.loading)
    }
    @MainActor func testCancelledReadCannotPublishCards() async throws {
        let transport = ObjectCardPendingTransport()
        let session: ObjectCardSession = try .init(accountID: 1, epoch: 1, token: "synthetic-a")
        let reader = ObjectCardSessionReader(service: try service(transport), currentSession: { session })
        let model = ObjectCardCollectionModel()
        let task = Task { await model.load(category: .all, reader: reader) }
        await transport.waitForRequest(); task.cancel()
        await transport.finish(code: 200); await task.value
        XCTAssertNil(model.collection); XCTAssertFalse(model.loading)
    }
    @MainActor func testUnconfiguredDoesNotRequest() async throws {
        let reader = ObjectCardSessionReader(service: nil, currentSession: { try? .init(accountID: 1, epoch: 1, token: "synthetic") })
        do { _ = try await reader.list(category: .all); XCTFail("not gated") } catch { XCTAssertEqual(error as? APIError, .notConfigured) }
    }
}

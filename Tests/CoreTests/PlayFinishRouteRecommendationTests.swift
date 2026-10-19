import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class FinishRouteHTTP: HTTPTransport {
    var requests: [URLRequest] = []
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        return (Data(#"{"code":200,"data":{"rows":[{"id":5,"name":"A"},{"id":0},{"id":6,"distance":"820.4"}]}}"#.utf8), 200)
    }
}

@MainActor private final class FinishReader: PlayFinishRouteReading {
    var rows: [PlayFinishRouteRow] = []
    var calls = 0
    var hold: CheckedContinuation<Void, Never>?
    var holds = false
    func rows(origin: PlayFinishOrigin) async throws -> [PlayFinishRouteRow] {
        calls += 1
        if holds { await withCheckedContinuation { hold = $0 } }
        return rows
    }
}

@MainActor final class PlayFinishRouteRecommendationTests: XCTestCase {
    private func rows(_ json: String) throws -> [PlayFinishRouteRow] { try JSONDecoder().decode([PlayFinishRouteRow].self, from: Data(json.utf8)) }

    func testPickSkipsCurrentActivityAndTopicAndFormatsLikeMiniProgram() throws {
        let page = try rows(#"[{"id":41,"topicId":2},{"id":42,"topicId":9},{"id":43,"name":" ","topicId":10,"distance":1250,"address":"Pier","minAmout":"0","imgUrl":",b.jpg"}]"#)
        let card = try XCTUnwrap(PlayFinishRouteCard.pick(page, currentActivityID: 41, currentTopicID: 9))
        XCTAssertEqual(card.activityID, 43)
        XCTAssertNil(card.title, "blank name falls back to 附近路线")
        XCTAssertNil(card.coverURL, "first comma part only, empty means no cover")
        XCTAssertEqual(card.price, .free)
        XCTAssertEqual(card.address, "Pier")
        XCTAssertEqual(PlayFinishRouteCard.distanceParts(1250).value, "1.3")
        XCTAssertTrue(PlayFinishRouteCard.distanceParts(1250).kilometres)
        XCTAssertEqual(PlayFinishRouteCard.distanceParts(820.4).value, "820")
        let priced = try XCTUnwrap(PlayFinishRouteCard.pick(try rows(#"[{"id":7,"minAmout":39.5}]"#), currentActivityID: nil, currentTopicID: nil))
        XCTAssertEqual(priced.price, .from(Decimal(string: "39.5")!))
        XCTAssertNil(PlayFinishRouteCard.pick(try rows(#"[{"id":7}]"#), currentActivityID: nil, currentTopicID: nil)?.price, "missing price is not free")
        XCTAssertNil(PlayFinishRouteCard.pick(try rows(#"[{"id":41}]"#), currentActivityID: 41, currentTopicID: nil))
    }

    func testOriginComesOnlyFromCompletedServerNodes() {
        XCTAssertNil(PlayFinishOrigin.resolve([(done: false, latitude: 31, longitude: 121, doneAt: nil)]))
        XCTAssertNil(PlayFinishOrigin.resolve([(done: true, latitude: nil, longitude: 121, doneAt: nil)]))
        let origin = PlayFinishOrigin.resolve([(done: true, latitude: 30, longitude: 120, doneAt: 1),
                                               (done: true, latitude: 31, longitude: 121, doneAt: 5),
                                               (done: true, latitude: 32, longitude: 122, doneAt: nil)])
        XCTAssertEqual(origin, PlayFinishOrigin(latitude: 31, longitude: 121))
        XCTAssertEqual(PlayFinishOrigin.resolve([(done: true, latitude: 30, longitude: 120, doneAt: nil), (done: true, latitude: 31, longitude: 121, doneAt: nil)]),
                       PlayFinishOrigin(latitude: 30, longitude: 120), "ties keep server order")
        XCTAssertNil(PlayFinishOrigin(latitude: 95, longitude: 1))
    }

    func testServiceSendsExactPageAndSkipsMalformedRows() async throws {
        let http = FinishRouteHTTP()
        let api = PlayExperienceService(configuration: try .init(baseURL: URL(string: "https://fixture.example/root/")!), transport: http, enabled: [.reads])
        let result = try await api.finishRouteRows(origin: PlayFinishOrigin(latitude: 31.5, longitude: 121.25)!, token: "fixture-token")
        XCTAssertEqual(result.map(\.id), [5, 6])
        XCTAssertEqual(result[1].distance, 820.4)
        let request = try XCTUnwrap(http.requests.first)
        XCTAssertEqual(request.url?.path, "/root/api/activity/list")
        XCTAssertEqual(request.httpMethod, "POST")
        let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
        for field in ["is_my", "sort_type", "pageNum", "pageSize", "longitude", "latitude"] { XCTAssertTrue(body.contains(field), field) }
        XCTAssertTrue(body.contains("121.25")); XCTAssertTrue(body.contains("31.5"))
    }

    func testFlagPreviewAndHiddenSheetSuppressTheCard() async throws {
        let reader = FinishReader(); reader.rows = try rows(#"[{"id":43}]"#)
        let origin = PlayFinishOrigin(latitude: 31, longitude: 121)
        let off = PlayFinishRouteRecommendationCoordinator(featureEnabled: false, reader: reader, currentActivityID: 1, currentTopicID: nil)
        await off.show(origin: origin)
        XCTAssertNil(off.card); XCTAssertEqual(reader.calls, 0)
        let on = PlayFinishRouteRecommendationCoordinator(featureEnabled: true, reader: reader, currentActivityID: 1, currentTopicID: nil)
        await on.show(origin: origin, isPreview: true)
        XCTAssertEqual(reader.calls, 0)
        await on.show(origin: nil)
        XCTAssertEqual(reader.calls, 0)
        await on.show(origin: origin)
        XCTAssertEqual(on.card?.activityID, 43)
        reader.holds = true
        let pending = Task { await on.show(origin: origin) }
        while reader.hold == nil { await Task.yield() }
        on.hide()
        reader.hold?.resume(); await pending.value
        XCTAssertNil(on.card, "late page after the sheet closed is dropped")
    }
}

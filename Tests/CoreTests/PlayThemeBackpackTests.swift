import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class BackpackHTTP: HTTPTransport {
    var requests: [URLRequest] = []
    func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); return (Data(#"{"code":200,"data":{"sessionId":1}}"#.utf8), 200) }
}

@MainActor private final class BackpackReader: PlayThemeBackpackReading {
    var result: Result<PlayWireValue, Error>
    init(_ result: Result<PlayWireValue, Error>) { self.result = result }
    func state() async throws -> PlayWireValue { try result.get() }
}

@MainActor final class PlayThemeBackpackTests: XCTestCase {
    private func wire(_ json: String) throws -> PlayWireValue { try JSONDecoder().decode(PlayWireValue.self, from: Data(json.utf8)) }

    func testProjectionMirrorsPresent() throws {
        let bag = try PlayThemeBackpack(wire(#"{"sessionId":61,"used":3,"capacity":6,"hpEnabled":true,"hp":0,"hpMax":10,"awaitingChallenge":true,"luckEnabled":false,"luck":9,"actionLimit":12,"actions":4,"actionName":"Moves","attributes":[{"key":"rep","label":"Rep","value":3},{"key":"sys.x","label":"X","value":1},{"key":"h","label":"H","value":1,"visible":false}],"contents":[{"kind":"ITEM","id":"tea","stat":"sys.hp","delta":2,"quantity":2},{"kind":"ITEM","id":"map"},{"kind":"ITEM","id":"counter.k"},{"kind":"NOTE","id":"n1","content":"Pier"}],"events":[{"id":"e1","name":"Bell"}],"clues":[{"id":"c1","scope":"PUBLIC","sources":[{"title":"P3","blocks":[{"text":"Fog","images":["a",""]}]}]},{"id":"c2"}],"pending":{"r1":{"quantity":1}},"itemCatalog":[{"id":"map","name":"Old map"}],"zeroHp":{"phase":"RECOVERING","policy":"STEPS","progress":1,"required":3}}"#))
        XCTAssertEqual(bag.values.map(\.key), ["hp", "actions", "rep"])
        XCTAssertTrue(bag.values[0].zero); XCTAssertEqual(bag.values[0].name, .hp); XCTAssertEqual(bag.values[0].max, "10")
        XCTAssertEqual(bag.values[1].name, .server("Moves"))
        XCTAssertEqual(bag.items.map(\.name), [.genericSupply, .server("Old map"), .genericNumber])
        XCTAssertEqual(bag.items[0].effect, .stat(name: .hp, delta: 2))
        XCTAssertEqual(bag.items[1].effect, .carried)
        XCTAssertEqual(bag.clues.map(\.scope), [.none, .none, .publicAll, .team])
        XCTAssertEqual(bag.clues[2].blocks, [.init(source: "P3", text: "Fog", imageCount: 1)])
        XCTAssertEqual(bag.pending.first?.id, "r1"); XCTAssertNil(bag.pending.first?.name)
        XCTAssertEqual(bag.zeroHP?.policy, "STEPS"); XCTAssertEqual(bag.zeroHP?.required, 3)
        XCTAssertFalse(bag.claimOnly)
        XCTAssertTrue(try PlayThemeBackpack(wire(#"{"status":"COMPLETED"}"#)).claimOnly)
        XCTAssertNil(try PlayThemeBackpack(wire(#"{"zeroHp":{"phase":"HEALTHY"}}"#)).zeroHP)
        XCTAssertEqual(try PlayThemeBackpack(wire("{}")).capacity, 6)
        XCTAssertThrowsError(try PlayThemeBackpack(wire("[]")))
    }

    func testServiceQueryAndCoordinatorStates() async throws {
        let http = BackpackHTTP()
        let api = PlayExperienceService(configuration: try .init(baseURL: URL(string: "https://fixture.example/root/")!), transport: http, enabled: [.reads])
        _ = try await api.themeState(scope: .activity(12), topicID: 3, token: "fixture-token")
        XCTAssertEqual(http.requests.first?.httpMethod, "GET")
        XCTAssertEqual(http.requests.first?.url?.query, "activityId=12&topicId=3")
        XCTAssertEqual(PlayThemeBackpackCoordinator(reader: nil).phase, .unavailable)
        let reader = BackpackReader(.failure(PlayExperienceError.rejected(500, "背包暂未加载")))
        let model = PlayThemeBackpackCoordinator(reader: reader)
        await model.refresh()
        XCTAssertEqual(model.phase, .failed(message: "背包暂未加载"))
        reader.result = .success(try wire(#"{"sessionId":61,"used":1}"#))
        await model.refresh()
        XCTAssertEqual(model.phase, .ready); XCTAssertEqual(model.backpack?.used, 1)
    }
}

import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class JourneyFakeHTTP: HTTPTransport {
    var requests: [URLRequest] = []
    var responses: [(String, Int)] = []
    var fail = false
    var beforeResponse: (() -> Void)?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); beforeResponse?()
        if fail { throw URLError(.networkConnectionLost) }
        guard !responses.isEmpty else { throw URLError(.badServerResponse) }
        let item = responses.removeFirst(); return (Data(item.0.utf8), item.1)
    }
}
@MainActor final class JourneyContentTests: XCTestCase {
    private let encounter = #"{"code":200,"data":{"allowedActions":["check"],"check":{"checkId":"c&1","skill":"Observe","tier":"hard","mods":[{"label":"Torch","value":0,"held":true}]}}}"#
    private let rolled = #"{"code":200,"data":{"settled":false,"rerolled":false,"dice":[4,19],"kept":19,"total":21,"success":true,"luck":2,"hp":8,"text":"must be hidden","failCostLabel":"hidden"}}"#
    private let settled = #"{"code":200,"data":{"settled":true,"rerolled":false,"dice":[19],"kept":19,"total":21,"success":true,"text":"Server ending","failCostLabel":"Server cost"}}"#
    private func session(_ epoch: UInt64 = 1) throws -> PlayExperienceSession {
        try PlayExperienceSession(accountID: 7, epoch: epoch, namespace: "CN.fixture", token: "fixture-token")
    }
    private func api(_ http: JourneyFakeHTTP, enabled: Bool = true) throws -> JourneyContentService {
        JourneyContentService(configuration: try APIConfiguration(baseURL: URL(string: "https://fixture.example")!), transport: http,
                              readsEnabled: enabled, checksEnabled: enabled, collectEnabled: enabled)
    }
    func testDormantServiceNeverInvokesHTTP() async throws {
        let http = JourneyFakeHTTP()
        let service = try api(http, enabled: false)
        do { _ = try await service.encounter(topicID: 2, nodeID: 3, token: "fixture-token"); XCTFail() } catch {}
        XCTAssertTrue(http.requests.isEmpty)
    }
    func testAllowedActionsAndReceiptTruth() throws {
        let raw = try JSONDecoder().decode(PlayWireValue.self, from: Data(encounter.utf8))["data"]
        XCTAssertEqual(JourneyCheckProblem(encounter: raw)?.mods.first?.value, 0)
        XCTAssertNil(JourneyCheckProblem(encounter: .object(["check": raw["check"]])))
        let receipt = try JourneyCheckReceipt(JSONDecoder().decode(PlayWireValue.self, from: Data(rolled.utf8))["data"])
        XCTAssertTrue(receipt.canReroll); XCTAssertEqual(receipt.text, ""); XCTAssertEqual(receipt.failCostLabel, "")
        let missing = try JourneyCheckReceipt(.object(["settled": .bool(false), "rerolled": .bool(false)]))
        XCTAssertNil(missing.luck); XCTAssertFalse(missing.canReroll); XCTAssertNil(missing.success)
    }
    func testExactGETAndMultipartActions() async throws {
        let http = JourneyFakeHTTP(); http.responses = [(encounter, 200), (rolled, 200), (rolled, 200), (settled, 200)]
        let service = try api(http)
        _ = try await service.encounter(topicID: 12, nodeID: 34, token: "fixture-token")
        let request = http.requests[0]
        XCTAssertEqual(request.httpMethod, "GET"); XCTAssertEqual(request.url?.path, "/api/play/encounter")
        XCTAssertEqual(Set(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!.map(\.name)), ["topicId", "nodeId"])
        for action in JourneyCheckAction.allCases {
            _ = try await service.act(JourneyCheckReview(session: session(), topicID: 12, nodeID: 34, checkID: "c&1", action: action, receipt: nil))
            let req = http.requests.last!, body = String(data: http.requests.last!.httpBody!, encoding: .utf8)!
            XCTAssertEqual(req.url?.path, "/api/play/check/" + action.rawValue)
            XCTAssertTrue(req.value(forHTTPHeaderField: "Content-Type")!.contains("multipart/form-data"))
            for key in ["topicId", "nodeId", "checkId"] { XCTAssertTrue(body.contains("name=\"\(key)\"")) }
            XCTAssertFalse(body.contains("activityId")); XCTAssertFalse(body.contains("outcome")); XCTAssertTrue(body.contains("c&1"))
        }
    }
    func testProbeFailureSilentOneAttempt() async throws {
        let http = JourneyFakeHTTP(); http.fail = true
        let owner = try session(), model = JourneyCheckCoordinator(scope: .topic(12), topicID: 12, nodeID: 34, service: try api(http), currentSession: { owner })
        await model.probe(nodeDone: false); await model.probe(nodeDone: false)
        XCTAssertEqual(http.requests.count, 1); XCTAssertFalse(model.visible); XCTAssertNil(model.issue)
    }
    func testReviewCancellationAndSettledRecovery() async throws {
        let http = JourneyFakeHTTP(); http.responses = [(encounter, 200), (#"{"code":409,"msg":"这次检定已经结算过了"}"#, 200), (settled, 200)]
        let owner = try session(), model = JourneyCheckCoordinator(scope: .activity(5), topicID: 12, nodeID: 34, service: try api(http), currentSession: { owner })
        await model.probe(nodeDone: false); try model.prepare(.roll); model.cancelReview()
        XCTAssertEqual(http.requests.count, 1)
        try model.prepare(.roll); await model.confirm(model.review!)
        XCTAssertTrue(model.receipt?.settled == true); XCTAssertEqual(http.requests.last?.url?.path, "/api/play/check/settle")
        XCTAssertEqual(http.requests.count, 3)
    }
    func testUnknownOutcomeLocksRollAndSurvivesClose() async throws {
        let http = JourneyFakeHTTP(); http.responses = [(encounter, 200)]
        let owner = try session(), model = JourneyCheckCoordinator(scope: .topic(12), topicID: 12, nodeID: 34, service: try api(http), currentSession: { owner })
        await model.probe(nodeDone: false); try model.prepare(.roll); http.fail = true; await model.confirm(model.review!)
        model.close(); model.reopen(); XCTAssertTrue(model.unknown)
        XCTAssertThrowsError(try model.prepare(.roll)); XCTAssertNotNil(model.pending)
        http.fail = false; http.responses = [(settled, 200)]
        try model.prepare(.settle, recoverUnknown: true); await model.confirm(model.review!)
        XCTAssertFalse(model.unknown); XCTAssertTrue(model.receipt?.settled == true)
    }
    func testSessionChangeInvalidatesImmutableReview() async throws {
        let http = JourneyFakeHTTP(); http.responses = [(encounter, 200)]
        var owner: PlayExperienceSession? = try session()
        let model = JourneyCheckCoordinator(scope: .topic(12), topicID: 12, nodeID: 34, service: try api(http), currentSession: { owner })
        await model.probe(nodeDone: false); try model.prepare(.roll); let review = model.review!
        owner = try session(2); await model.confirm(review)
        XCTAssertEqual(http.requests.count, 1); XCTAssertNil(model.problem); XCTAssertNil(model.review)
    }
    func testCompanionScopeAndEggPayloadNoRewards() async throws {
        let http = JourneyFakeHTTP(); http.responses = [(#"{"code":200,"data":{"line":"  Hello  "}}"#, 200), (#"{"code":200,"data":null}"#, 200)]
        let service = try api(http)
        let line = try await service.companion(scope: .activity(5), token: "fixture-token")
        XCTAssertEqual(line, "Hello"); XCTAssertEqual(http.requests[0].url?.query, "activityId=5")
        let egg = JourneyEgg(raw: .object(["id": .integer(1), "lat": .number(31), "lng": .number(121), "text": .string("Egg")]))!
        try await service.collect(topicID: nil, egg: egg, token: "fixture-token")
        let body = String(data: http.requests[1].httpBody!, encoding: .utf8)!
        XCTAssertFalse(body.contains("topicId")); XCTAssertFalse(body.contains("latitude")); XCTAssertFalse(body.contains("reward"))
        XCTAssertTrue(body.contains("name=\"eggId\"")); XCTAssertTrue(body.contains("name=\"content\""))
    }
    func testEggCooldownSeenScopeAndNoLiveCollection() async throws {
        let http = JourneyFakeHTTP(), store = JourneyMemoryEggSeenStorage()
        let owner = try session(), model = JourneyAmbientCoordinator(scope: .topic(12), service: try api(http, enabled: false), store: store, currentSession: { owner })
        let raw: PlayWireValue = .object(["id": .integer(1), "lat": .number(31), "lng": .number(121), "radius": .integer(9999), "text": .string("Egg")])
        let egg = JourneyEgg(raw: raw)!
        XCTAssertEqual(egg.radius, 1000)
        model.project(eggs: [egg], topicID: 12)
        let now = Date(timeIntervalSince1970: 1000)
        await model.accept(position: JourneyAmbientPosition(latitude: 31, longitude: 121), now: now)
        XCTAssertEqual(model.eggBubble?.id, 1); XCTAssertTrue(model.collected.isEmpty); XCTAssertTrue(http.requests.isEmpty)
        model.tick(now: now.addingTimeInterval(7)); XCTAssertNil(model.eggBubble)
        await model.accept(position: JourneyAmbientPosition(latitude: 31, longitude: 121), now: now.addingTimeInterval(181))
        XCTAssertNil(model.eggBubble)
        XCTAssertEqual(try store.seen(in: JourneyAmbientScope(accountID: 7, region: "CN.fixture", session: .topic(12))), [1])
        XCTAssertTrue(try store.seen(in: JourneyAmbientScope(accountID: 7, region: "US.fixture", session: .topic(12))).isEmpty)
        XCTAssertTrue(try store.seen(in: JourneyAmbientScope(accountID: 7, region: "CN.fixture", session: .activity(12))).isEmpty)
    }
    func testInFlightOldAccountResultIsDropped() async throws {
        let http = JourneyFakeHTTP(); http.responses = [(encounter, 200), (rolled, 200)]
        var owner: PlayExperienceSession? = try session()
        let model = JourneyCheckCoordinator(scope: .topic(12), topicID: 12, nodeID: 34, service: try api(http), currentSession: { owner })
        await model.probe(nodeDone: false); try model.prepare(.roll)
        http.beforeResponse = { owner = nil }
        await model.confirm(model.review!)
        XCTAssertNil(model.receipt); XCTAssertNil(model.problem); XCTAssertFalse(model.visible)
    }
    func testPersistentUnknownRestoresAndFencesDifferentCheck() async throws {
        let journal = JourneyMemoryCheckJournal(), owner = try session()
        try journal.save(checkID: "other-check", session: owner, scope: .topic(12), topicID: 12, nodeID: 34)
        let http = JourneyFakeHTTP(); http.responses = [(encounter, 200)]
        let model = JourneyCheckCoordinator(scope: .topic(12), topicID: 12, nodeID: 34, service: try api(http), journal: journal, currentSession: { owner })
        await model.probe(nodeDone: false)
        XCTAssertTrue(model.unknown); XCTAssertFalse(model.canRecover)
        XCTAssertThrowsError(try model.prepare(.roll))
        XCTAssertEqual(try journal.pending(session: owner, scope: .topic(12), topicID: 12, nodeID: 34), "other-check")
        XCTAssertNil(try journal.pending(session: owner, scope: .activity(12), topicID: 12, nodeID: 34))
    }
    func testBusinessFailurePreservesServerText() async throws {
        let http = JourneyFakeHTTP(); http.responses = [(encounter, 200), (#"{"code":403,"msg":"Server says no luck"}"#, 200)]
        let owner = try session(), model = JourneyCheckCoordinator(scope: .topic(12), topicID: 12, nodeID: 34, service: try api(http), currentSession: { owner })
        await model.probe(nodeDone: false); try model.prepare(.roll); await model.confirm(model.review!)
        XCTAssertEqual(model.issue, "Server says no luck"); XCTAssertFalse(model.unknown); XCTAssertNil(model.receipt)
    }

    func testOldAccountCannotTriggerSettledRecoveryRequest() async throws {
        let http = JourneyFakeHTTP(); http.responses = [(encounter, 200), (#"{"code":409,"msg":"已结算"}"#, 200)]
        var owner: PlayExperienceSession? = try session()
        let model = JourneyCheckCoordinator(scope: .topic(12), topicID: 12, nodeID: 34, service: try api(http), currentSession: { owner })
        await model.probe(nodeDone: false); try model.prepare(.roll)
        http.beforeResponse = { owner = nil }; await model.confirm(model.review!)
        XCTAssertEqual(http.requests.count, 2); XCTAssertNil(model.receipt)
    }

}

import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class OpeningHTTP: HTTPTransport {
    var requests: [URLRequest] = []
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        return (Data(#"{"code":200,"data":null}"#.utf8), 200)
    }
}

@MainActor private final class OpeningClient: PlayOpeningCompleting {
    var ready = true, completed = false, submissions = 0
    var failure: Error?
    var completesDespiteFailure = false
    func route() async throws -> PlayRouteState {
        let json = #"{"version":\#(completed ? 8 : 7),"currentNodeId":31,"opening":{"chapterId":5,"ready":\#(ready),"complete":\#(completed)}}"#
        return try JSONDecoder().decode(PlayRouteState.self, from: Data(json.utf8))
    }
    func complete(chapterID: Int, expectedVersion: Int) async throws {
        submissions += 1
        XCTAssertEqual(chapterID, 5); XCTAssertEqual(expectedVersion, 7)
        if completesDespiteFailure { completed = true }
        if let failure { throw failure }
        completed = true
    }
}

@MainActor final class PlayJourneyOpeningTests: XCTestCase {
    private func route(_ json: String) throws -> PlayRouteState { try JSONDecoder().decode(PlayRouteState.self, from: Data(json.utf8)) }

    func testRouteDecodesOpeningAndGateMatchesContinueChapterStory() throws {
        let pending = try route(#"{"version":3,"currentNodeId":9,"opening":{"chapterId":"4","ready":false,"complete":false}}"#)
        XCTAssertEqual(pending.opening, PlayJourneyOpening(chapterID: 4, ready: false, complete: false))
        XCTAssertEqual(PlayOpeningGate.evaluate(route: pending, chapterIsOpening: true, isPreview: false), .finishOpeningPlayFirst(currentNodeID: 9))
        XCTAssertEqual(PlayOpeningGate.evaluate(route: pending, chapterIsOpening: false, isPreview: false), .notOpening)
        XCTAssertEqual(PlayOpeningGate.evaluate(route: pending, chapterIsOpening: true, isPreview: true), .notOpening)
        XCTAssertTrue(PlayOpeningGate.suppressesCompletion(pending))
        let ready = try route(#"{"version":3,"opening":{"chapterId":4,"ready":true,"complete":false}}"#)
        XCTAssertEqual(PlayOpeningGate.evaluate(route: ready, chapterIsOpening: true, isPreview: false), .readyToDepart(chapterID: 4, expectedVersion: 3))
        let noVersion = try route(#"{"opening":{"chapterId":4,"ready":true}}"#)
        XCTAssertEqual(PlayOpeningGate.evaluate(route: noVersion, chapterIsOpening: true, isPreview: false), .versionUnavailable)
        let done = try route(#"{"version":4,"opening":{"chapterId":4,"ready":true,"complete":true}}"#)
        XCTAssertEqual(PlayOpeningGate.evaluate(route: done, chapterIsOpening: true, isPreview: false), .notOpening)
        XCTAssertNil(try route(#"{"version":4,"opening":"yes"}"#).opening, "non-record opening is ignored, as in the mini-program")
    }

    func testServiceSendsExactJSONOnlyWithItsOwnCapability() async throws {
        let http = OpeningHTTP()
        let disabled = PlayExperienceService(configuration: try .init(baseURL: URL(string: "https://fixture.example/root/")!), transport: http)
        do { try await disabled.completeOpening(scope: .activity(12), topicID: 3, chapterID: 5, expectedVersion: 7, token: "fixture-token"); XCTFail("dispatched while disabled") }
        catch { XCTAssertEqual(error as? PlayExperienceError, .disabled) }
        let wrong = PlayExperienceService(configuration: try .init(baseURL: URL(string: "https://fixture.example/root/")!), transport: http, enabled: [.journeyAsks, .reads])
        do { _ = try await wrong.request("api/play/journey/opening/complete", json: [:], capability: .journeyAsks, token: "fixture-token"); XCTFail("wrong capability") }
        catch { XCTAssertEqual(error as? PlayExperienceError, .persistenceUnavailable) }
        XCTAssertTrue(http.requests.isEmpty)
        let api = PlayExperienceService(configuration: try .init(baseURL: URL(string: "https://fixture.example/root/")!), transport: http, enabled: [.journeyOpening])
        try await api.completeOpening(scope: .activity(12), topicID: 3, chapterID: 5, expectedVersion: 7, token: "fixture-token")
        XCTAssertEqual(http.requests.count, 1)
        XCTAssertEqual(http.requests[0].url?.path, "/root/api/play/journey/opening/complete")
        XCTAssertEqual(http.requests[0].httpMethod, "POST")
        XCTAssertEqual(String(decoding: http.requests[0].httpBody ?? Data(), as: UTF8.self), #"{"activityId":12,"chapterId":5,"expectedVersion":7,"topicId":3}"#)
    }

    func testReviewThenConfirmDepartsFromServerReadback() async throws {
        let client = OpeningClient(); client.ready = false
        let model = PlayOpeningCompletionCoordinator(client: client)
        await model.load()
        model.depart(chapterIsOpening: true)
        XCTAssertEqual(model.phase, .finishPlayFirst(currentNodeID: 31))
        client.ready = true; await model.load()
        model.depart(chapterIsOpening: true)
        XCTAssertEqual(model.phase, .reviewing(chapterID: 5, expectedVersion: 7))
        XCTAssertEqual(client.submissions, 0, "review sends nothing")
        await model.confirm()
        XCTAssertEqual(model.phase, .departed)
        XCTAssertEqual(client.submissions, 1)
    }

    func testUnknownResultIsSettledByReadBackNeverResubmitted() async throws {
        let client = OpeningClient(); client.failure = PlayExperienceError.unknownResult; client.completesDespiteFailure = false
        let model = PlayOpeningCompletionCoordinator(client: client)
        await model.load(); model.depart(chapterIsOpening: true); await model.confirm()
        XCTAssertEqual(model.phase, .unknown)
        model.depart(chapterIsOpening: true)
        XCTAssertEqual(model.phase, .unknown, "no second 出发 while unknown")
        client.completed = true
        await model.readBack()
        XCTAssertEqual(model.phase, .departed)
        XCTAssertEqual(client.submissions, 1)
    }

    func testConflictReReadsRouteAndKeepsRefusalVisible() async throws {
        let client = OpeningClient(); client.failure = PlayExperienceError.rejected(500, "路线已更新，请刷新后重试")
        let model = PlayOpeningCompletionCoordinator(client: client)
        await model.load(); model.depart(chapterIsOpening: true); await model.confirm()
        XCTAssertEqual(model.phase, .rejected(message: "路线已更新，请刷新后重试", conflict: true))
        XCTAssertTrue(PlayOpeningCompletionCoordinator.isRouteConflict(code: 409, message: nil))
        XCTAssertFalse(PlayOpeningCompletionCoordinator.isRouteConflict(code: 500, message: "保存失败"))
        XCTAssertEqual(PlayOpeningCompletionCoordinator(client: nil).phase, .disabled)
    }
}

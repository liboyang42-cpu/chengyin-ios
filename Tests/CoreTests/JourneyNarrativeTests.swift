import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class NarrativeHTTP: HTTPTransport {
    var requests: [URLRequest] = []
    var responses: [String] = []
    var failAt: Int?
    var afterRequest: ((Int) -> Void)?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); afterRequest?(requests.count)
        if failAt == requests.count { throw URLError(.networkConnectionLost) }
        guard !responses.isEmpty else { throw URLError(.badServerResponse) }
        return (Data(responses.removeFirst().utf8), 200)
    }
}
@MainActor final class JourneyNarrativeTests: XCTestCase {
    private var store: [String: Data] = [:]
    private func journal() -> JourneyStoredNarrativeJournal { .init(read: { self.store[$0] }, write: { self.store[$1] = $0 }) }
    private func owner(_ epoch: UInt64 = 1) throws -> PlayExperienceSession { try .init(accountID: 8, epoch: epoch, namespace: "CN.narrative.fixture", token: "fixture-token") }
    private func target(_ scope: PlaySessionScope = .activity(55)) throws -> JourneyNarrativeScope { try .init(scope: scope, topicID: 12) }
    private func service(_ http: NarrativeHTTP, enabled: Bool = true) throws -> JourneyNarrativeService {
        .init(configuration: try .init(baseURL: URL(string: "https://fixture.example")!), transport: http, readsEnabled: enabled, asksEnabled: enabled)
    }
    private func questions(version: Int = 1, asked: Bool = false, arrived: Bool = true, locked: Bool = false, node: Int = 34, run: Int = 9) -> String {
        #"{"code":200,"data":{"nodeId":\#(node),"runId":\#(run),"stateVersion":\#(version),"arrived":\#(arrived),"locked":\#(locked),"enter":{"opener":"Hello","questions":[{"id":"q1","q":"Who?","asked":\#(asked),"a":"Server answer"}]}}}"#
    }
    private let receipt = #"{"code":200,"data":{"nodeId":34,"questionId":"q1","q":"Who?","a":"Server answer","stateVersion":2}}"#
    func testTopicScopeAlwaysExplicitZeroAndRejectsCrossTopic() throws {
        XCTAssertEqual(try target(.topic(12)).query, ["topicId": "12", "activityId": "0"])
        XCTAssertEqual(try target().query, ["topicId": "12", "activityId": "55"])
        XCTAssertThrowsError(try target(.topic(99)))
        XCTAssertThrowsError(try JourneyNarrativeQuery.stage(chapterID: 0).fields(target()))
    }
    func testAllFourReadRoutesKeepExactActivityAndChapterScope() async throws {
        let http = NarrativeHTTP()
        http.responses = [
            #"{"code":200,"data":{"facts":[],"costs":[],"relations":[],"log":[],"found":0,"total":2}}"#,
            #"{"code":200,"data":{"nodes":[{"nodeId":34,"reward":"Token","status":"pending"}]}}"#,
            #"{"code":200,"data":{"changed":["A clue"],"open":"Next","costs":[],"hp":2,"luck":1,"stateVersion":3}}"#,
            #"{"code":200,"data":{"title":"End","summary":"Server story","epilogues":[],"exhibits":[],"costs":[],"badge":null,"found":0,"total":2}}"#]
        let api = try service(http), scope = try target()
        for query in [JourneyNarrativeQuery.casebook, .backpack, .stage(chapterID: 7), .ending] { _ = try await api.read(query, scope: scope, token: "fixture-token") }
        XCTAssertEqual(http.requests.map { $0.url!.path }, ["/api/play/journey/casebook", "/api/play/journey/backpack", "/api/play/journey/stage-end", "/api/play/journey/ending"])
        for request in http.requests {
            XCTAssertEqual(request.httpMethod, "GET")
            let fields = Dictionary(uniqueKeysWithValues: URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value!) })
            XCTAssertEqual(fields["activityId"], "55"); XCTAssertEqual(fields["topicId"], "12")
        }
        XCTAssertTrue(http.requests[2].url!.absoluteString.contains("chapterId=7"))
    }
    func testDisabledReadsAndActionsNeverDispatch() async throws {
        let http = NarrativeHTTP(), api = try service(http, enabled: false), scope = try target()
        do { _ = try await api.read(.casebook, scope: scope, token: "fixture-token"); XCTFail() } catch {}
        do { _ = try await api.ask(scope: scope, nodeID: 34, questionID: "q1", token: "fixture-token"); XCTFail() } catch {}
        XCTAssertTrue(http.requests.isEmpty)
    }
    func testUnaskedAnswersAreNotExposedAndMismatchedNodeRejected() throws {
        let raw = try JSONDecoder().decode(PlayWireValue.self, from: Data(questions().utf8))["data"]
        let projection = try JourneyQuestionsDocument(raw, expectedNodeID: 34)
        XCTAssertNil(projection.questions.first?.answer)
        XCTAssertTrue(projection.allowsAsking)
        XCTAssertThrowsError(try JourneyQuestionsDocument(raw, expectedNodeID: 35))
        XCTAssertFalse(JourneyQuestion.validID(String(repeating: "a", count: 33)))
        XCTAssertFalse(JourneyQuestion.validID("../q"))
    }
    func testMalformedRewardDoesNotBecomeClaimed() throws {
        let raw: PlayWireValue = .object(["nodes": .array([.object(["nodeId": .int(34), "status": .string("success")])])])
        XCTAssertThrowsError(try JourneyNarrativeDocument(raw, query: .backpack))
    }
    func testCancelReviewPerformsNoWrite() async throws {
        let http = NarrativeHTTP(); http.responses = [questions()]
        let owner = try owner(), model = JourneyNarrativeCoordinator(scope: try target(), query: .questions(nodeID: 34), service: try service(http), journal: journal(), currentSession: { owner })
        await model.load(); model.prepare("q1"); let review = try XCTUnwrap(model.review)
        model.cancelReview(); await model.confirm(review)
        XCTAssertEqual(http.requests.count, 1); XCTAssertTrue(store.isEmpty)
    }
    func testReviewedAskUsesJSONScopeAndReadsBack() async throws {
        let http = NarrativeHTTP(); http.responses = [questions(), questions(), receipt, questions(version: 2, asked: true)]
        let owner = try owner(), model = JourneyNarrativeCoordinator(scope: try target(), query: .questions(nodeID: 34), service: try service(http), journal: journal(), currentSession: { owner })
        await model.load(); model.prepare("q1"); await model.confirm(try XCTUnwrap(model.review))
        XCTAssertEqual(http.requests.count, 4)
        let request = http.requests[2]
        XCTAssertEqual(request.url!.path, "/api/play/journey/ask"); XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try JSONDecoder().decode(PlayWireValue.self, from: XCTUnwrap(request.httpBody))
        XCTAssertEqual(body.object?.keys.sorted(), ["activityId", "nodeId", "questionId", "topicId"])
        XCTAssertEqual(body["activityId"].integer, 55); XCTAssertEqual(body["nodeId"].integer, 34)
        XCTAssertEqual(model.receipt?.answer, "Server answer"); XCTAssertEqual(model.acknowledgedRevision, 1)
        XCTAssertTrue(model.pending.isEmpty); XCTAssertNil(model.review)
        XCTAssertFalse(model.canAsk && model.document == nil)
    }
    func testUnarrivedOrLockedProjectionCannotMintReview() async throws {
        for pair in [(false, false), (true, true)] {
            let http = NarrativeHTTP(); http.responses = [questions(arrived: pair.0, locked: pair.1)]
            let owner = try owner(), model = JourneyNarrativeCoordinator(scope: try target(), query: .questions(nodeID: 34), service: try service(http), journal: journal(), currentSession: { owner })
            await model.load(); model.prepare("q1"); XCTAssertNil(model.review); XCTAssertFalse(model.canAsk)
        }
    }
    func testVersionChangeDuringPreflightDoesNotDispatch() async throws {
        let http = NarrativeHTTP(); http.responses = [questions(), questions(version: 2)]
        let owner = try owner(), model = JourneyNarrativeCoordinator(scope: try target(), query: .questions(nodeID: 34), service: try service(http), journal: journal(), currentSession: { owner })
        await model.load(); model.prepare("q1"); await model.confirm(try XCTUnwrap(model.review))
        XCTAssertEqual(http.requests.count, 2); XCTAssertTrue(store.isEmpty); XCTAssertEqual(model.issue, "journey.record.stale")
    }
    func testSessionSwitchDuringPreflightDoesNotDispatch() async throws {
        let http = NarrativeHTTP(); http.responses = [questions(), questions()]
        var current: PlayExperienceSession? = try owner()
        let replacement = try owner(2)
        let model = JourneyNarrativeCoordinator(scope: try target(), query: .questions(nodeID: 34), service: try service(http), journal: journal(), currentSession: { current })
        await model.load(); model.prepare("q1")
        http.afterRequest = { if $0 == 2 { current = replacement } }
        await model.confirm(try XCTUnwrap(model.review))
        XCTAssertEqual(http.requests.count, 2); XCTAssertTrue(store.isEmpty); XCTAssertNil(model.document); XCTAssertNil(model.review)
    }
    func testUnknownWritePersistsUntilAuthoritativeAskedReadback() async throws {
        let http = NarrativeHTTP(); http.responses = [questions(), questions()]; http.failAt = 3
        let owner = try owner(), scope = try target(), journal = journal()
        let model = JourneyNarrativeCoordinator(scope: scope, query: .questions(nodeID: 34), service: try service(http), journal: journal, currentSession: { owner })
        await model.load(); model.prepare("q1"); await model.confirm(try XCTUnwrap(model.review))
        XCTAssertEqual(model.issue, "journey.record.unknown"); XCTAssertEqual(try journal.pending(owner: owner, scope: scope, realm: "https://fixture.example", runID: 9, nodeID: 34), ["q1"])
        let next = NarrativeHTTP(); next.responses = [questions(), questions(version: 2, asked: true)]
        let reloaded = JourneyNarrativeCoordinator(scope: scope, query: .questions(nodeID: 34), service: try service(next), journal: journal, currentSession: { owner })
        await reloaded.load(); reloaded.prepare("q1"); XCTAssertNil(reloaded.review); XCTAssertEqual(reloaded.pending, ["q1"])
        await reloaded.load(); XCTAssertTrue(reloaded.pending.isEmpty)
        XCTAssertEqual(next.requests.count, 2); XCTAssertTrue(next.requests.allSatisfy { $0.httpMethod == "GET" })
    }
    func testMissingDurableJournalKeepsActionsOff() async throws {
        let http = NarrativeHTTP(); http.responses = [questions()]
        let owner = try owner(), model = JourneyNarrativeCoordinator(scope: try target(), query: .questions(nodeID: 34), service: try service(http), currentSession: { owner })
        await model.load(); model.prepare("q1"); XCTAssertFalse(model.canAsk); XCTAssertNil(model.review)
    }
    func testTopicCustomerFiltersHaveDistinctWireValues() throws {
        let scope = ClubGovernanceScope(clubID: 10, topicID: 20)
        XCTAssertEqual(ClubTopicCustomerFilter.allCases.map(\.rawValue), ["", "pending", "contacted", "verified"])
        for filter in ClubTopicCustomerFilter.allCases {
            let fields = try ClubGovernanceRead.topicCustomers.fields(scope: scope, options: filter.options)
            XCTAssertEqual(fields["clubId"]?.int, 10); XCTAssertEqual(fields["topicId"]?.int, 20); XCTAssertEqual(fields["filter"]?.string, filter.rawValue)
        }
        XCTAssertThrowsError(try ClubGovernanceRead.topicCustomers.fields(scope: scope, options: ["filter": .string("repeat")]))
    }
    func testJournalReadAccountChangeCannotResurrectProjection() async throws {
        let http = NarrativeHTTP(); http.responses = [questions()]
        var current: PlayExperienceSession? = try owner()
        let journal = JourneyStoredNarrativeJournal(read: { _ in current = nil; return nil }, write: { _, _ in XCTFail("No write expected") })
        let model = JourneyNarrativeCoordinator(scope: try target(), query: .questions(nodeID: 34), service: try service(http), journal: journal, currentSession: { current })
        await model.load()
        XCTAssertNil(model.document); XCTAssertNil(model.receipt); XCTAssertTrue(model.pending.isEmpty)
        XCTAssertEqual(http.requests.count, 1)
    }
    func testReservationCallbackDismissalCannotDispatchOrRestorePendingUI() async throws {
        let http = NarrativeHTTP(); http.responses = [questions(), questions()]
        let captured = try owner(), scope = try target()
        var model: JourneyNarrativeCoordinator!
        let journal = JourneyStoredNarrativeJournal(read: { self.store[$0] }, write: { data, key in
            self.store[key] = data; model.dismiss()
        })
        model = JourneyNarrativeCoordinator(scope: scope, query: .questions(nodeID: 34), service: try service(http), journal: journal, currentSession: { captured })
        await model.load(); model.prepare("q1"); await model.confirm(try XCTUnwrap(model.review))
        XCTAssertEqual(http.requests.count, 2); XCTAssertNil(model.document); XCTAssertNil(model.receipt); XCTAssertTrue(model.pending.isEmpty)
        XCTAssertEqual(try journal.pending(owner: captured, scope: scope, realm: "https://fixture.example", runID: 9, nodeID: 34), ["q1"])
    }
    func testReservationCallbackAccountSwitchPreservesUnknownOldRun() async throws {
        let http = NarrativeHTTP(); http.responses = [questions(), questions()]
        let captured = try owner(), scope = try target()
        var current: PlayExperienceSession? = captured
        let journal = JourneyStoredNarrativeJournal(read: { self.store[$0] }, write: { data, key in
            self.store[key] = data; current = nil
        })
        let model = JourneyNarrativeCoordinator(scope: scope, query: .questions(nodeID: 34), service: try service(http), journal: journal, currentSession: { current })
        await model.load(); model.prepare("q1"); await model.confirm(try XCTUnwrap(model.review))
        XCTAssertEqual(http.requests.count, 2); XCTAssertNil(model.document); XCTAssertNil(model.receipt); XCTAssertTrue(model.pending.isEmpty)
        XCTAssertEqual(try journal.pending(owner: captured, scope: scope, realm: "https://fixture.example", runID: 9, nodeID: 34), ["q1"])
    }
    func testReceiptJournalCallbackCannotResurrectAnswerAfterAccountSwitch() async throws {
        let http = NarrativeHTTP(); http.responses = [questions(), questions(), receipt]
        let captured = try owner(), scope = try target()
        var current: PlayExperienceSession? = captured; var writes = 0
        let journal = JourneyStoredNarrativeJournal(read: { self.store[$0] }, write: { data, key in
            self.store[key] = data; writes += 1; if writes == 2 { current = nil }
        })
        let model = JourneyNarrativeCoordinator(scope: scope, query: .questions(nodeID: 34), service: try service(http), journal: journal, currentSession: { current })
        await model.load(); model.prepare("q1"); await model.confirm(try XCTUnwrap(model.review))
        XCTAssertEqual(http.requests.count, 3); XCTAssertNil(model.receipt); XCTAssertEqual(model.acknowledgedRevision, 0)
        XCTAssertNil(model.document); XCTAssertTrue(model.pending.isEmpty)
    }
    func testReadbackJournalCallbackDismissalCannotResurrectDocument() async throws {
        let captured = try owner(), scope = try target(), seed = journal()
        try seed.save(["q1"], owner: captured, scope: scope, realm: "https://fixture.example", runID: 9, nodeID: 34)
        let http = NarrativeHTTP(); http.responses = [questions(version: 2, asked: true)]
        var model: JourneyNarrativeCoordinator!
        let callback = JourneyStoredNarrativeJournal(read: { self.store[$0] }, write: { data, key in self.store[key] = data; model.dismiss() })
        model = JourneyNarrativeCoordinator(scope: scope, query: .questions(nodeID: 34), service: try service(http), journal: callback, currentSession: { captured })
        await model.load()
        XCTAssertNil(model.document); XCTAssertNil(model.receipt); XCTAssertTrue(model.pending.isEmpty)
    }
    func testNewRunAndOtherOriginCannotResolvePriorRunUnknown() async throws {
        let captured = try owner(), scope = try target(), journal = journal()
        try journal.save(["q1"], owner: captured, scope: scope, realm: "https://fixture.example", runID: 9, nodeID: 34)
        let http = NarrativeHTTP(); http.responses = [questions(version: 2, asked: true, run: 10)]
        let model = JourneyNarrativeCoordinator(scope: scope, query: .questions(nodeID: 34), service: try service(http), journal: journal, currentSession: { captured })
        await model.load(); XCTAssertTrue(model.pending.isEmpty)
        XCTAssertEqual(try journal.pending(owner: captured, scope: scope, realm: "https://fixture.example", runID: 9, nodeID: 34), ["q1"])
        XCTAssertTrue(try journal.pending(owner: captured, scope: scope, realm: "https://other.example", runID: 9, nodeID: 34).isEmpty)
        try journal.save([], owner: captured, scope: scope, realm: "https://other.example", runID: 9, nodeID: 34)
        XCTAssertEqual(try journal.pending(owner: captured, scope: scope, realm: "https://fixture.example", runID: 9, nodeID: 34), ["q1"])
    }

}

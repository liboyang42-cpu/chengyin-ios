import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

private let compareQuestionJSON = #"{"prompt":"Mark the changed entries","maxAttempts":0,"attempts":0,"finished":false,"passed":false,"lastCorrect":false,"lastMarked":[],"left":{"label":"Earlier","items":[{"id":"z-left","time":"09:00","text":"Gate opened"},{"id":"a-left","time":"10:00","text":"Bell rang"}]},"right":{"label":"Later","items":[{"id":"b-right","time":"09:00","text":"Gate closed"},{"id":"a-right","time":"10:00","text":"Bell rang"}]}}"#

final class PlayCompareTests: XCTestCase {
    private func wire(_ raw: String = compareQuestionJSON) throws -> PlayWireValue { try JSONDecoder().decode(PlayWireValue.self, from: Data(raw.utf8)) }
    func testProjectionKeepsBothTimelineOrdersAndNeverReadsAnswer() throws {
        var raw = try wire().object!; raw["answer"] = .array([.string("secret")])
        let question = try PlayCompareQuestion(.object(raw))
        XCTAssertEqual(question.left.items.map(\.id), ["z-left", "a-left"])
        XCTAssertEqual(question.right.items.map(\.id), ["b-right", "a-right"])
        XCTAssertEqual(question, try PlayCompareQuestion(wire()))
        XCTAssertNil(question.remainingAttempts)
    }
    func testCrossSideDuplicateIDsAreMalformedRatherThanSilentlyDropped() throws {
        XCTAssertThrowsError(try PlayCompareQuestion(wire(compareQuestionJSON.replacingOccurrences(of: "b-right", with: "z-left"))))
    }
    func testMissingSideTimeOrWrongTypeIsMalformed() throws {
        for raw in [compareQuestionJSON.replacingOccurrences(of: "\"time\":\"09:00\"", with: "\"time\":null"), compareQuestionJSON.replacingOccurrences(of: "\"id\":\"b-right\"", with: "\"id\":9")] {
            XCTAssertThrowsError(try PlayCompareQuestion(wire(raw)))
        }
    }
    func testPayloadSupportsEmptyAndBothSidesWithoutSortingIDs() throws {
        let question = try PlayCompareQuestion(wire())
        XCTAssertEqual(try question.payload(marked: []), ["marked": .array([])])
        XCTAssertEqual(try question.payload(marked: ["b-right", "z-left"]), ["marked": .array([.string("b-right"), .string("z-left")])])
    }
    func testPayloadRejectsDuplicatesUnknownNonStringMissingAndExtraFields() throws {
        let question = try PlayCompareQuestion(wire())
        for payload: [String: PlayWireValue] in [[:], ["marked": .null], ["marked": .array([.int(1)])], ["marked": .array([.string("missing")])], ["marked": .array([.string("z-left"), .string("z-left")])], ["marked": .array([]), "passed": .bool(true)]] {
            XCTAssertThrowsError(try question.validate(payload))
        }
    }
    func testInputBoundaryRequiresExactBackendAction() throws {
        let segment = try wire()
        try PlayKitInputContract.validate(kind: "compare", action: "SUBMIT_COMPARE", payload: ["marked": .array([])], segment: segment)
        XCTAssertThrowsError(try PlayKitInputContract.validate(kind: "compare", action: "SUBMIT_MATCH", payload: ["marked": .array([])], segment: segment))
        XCTAssertEqual(PlayKitActionCatalog.actions["compare"], ["SUBMIT_COMPARE"])
    }
    func testFinishedUnpassedReceiptEndsTaskWithoutLocalPass() throws {
        var raw = try wire().object!
        raw["finished"] = .bool(true); raw["maxAttempts"] = .int(1); raw["attempts"] = .int(1); raw["remainingAttempts"] = .int(0)
        let question = try PlayCompareQuestion(.object(raw))
        XCTAssertTrue(question.finished); XCTAssertFalse(question.passed)
        XCTAssertThrowsError(try question.payload(marked: []))
        let projection = PlayKitScreenProjection(kind: .compare, segment: .object(raw))
        XCTAssertTrue(projection.complete); XCTAssertEqual(projection.reportedPass, false)
    }
    func testCapIsNotAnAttemptAndRemainingMustMatchServerProjection() throws {
        var raw = try wire().object!; raw["maxAttempts"] = .int(2); raw["remainingAttempts"] = .int(2)
        XCTAssertNil(PlayKitScreenProjection(kind: .compare, segment: .object(raw)).reportedPass)
        XCTAssertEqual(try PlayCompareQuestion(.object(raw)).remainingAttempts, 2)
        raw["remainingAttempts"] = .int(1); XCTAssertThrowsError(try PlayCompareQuestion(.object(raw)))
    }
    func testRestoredSelectionPreservesReceiptAndCanonicalSourceOrder() throws {
        var raw = try wire().object!; raw["lastMarked"] = .array([.string("b-right")]); raw["attempts"] = .int(1)
        let question = try PlayCompareQuestion(.object(raw)); var selection = PlayCompareSelection()
        selection.restore(question, revision: "1:1"); selection.toggle("z-left", question: question, revision: "1:1")
        XCTAssertEqual(try selection.payload(question, revision: "1:1"), ["marked": .array([.string("z-left"), .string("b-right")])])
    }
    func testVersionOrSessionChangeNeverSilentlyRebasesDraft() throws {
        let question = try PlayCompareQuestion(wire()); var selection = PlayCompareSelection()
        selection.restore(question, revision: "1:1"); selection.toggle("z-left", question: question, revision: "1:1")
        for revision in ["1:2", "2:1"] {
            selection.toggle("b-right", question: question, revision: revision)
            XCTAssertEqual(selection.marked, ["z-left"])
            XCTAssertThrowsError(try selection.payload(question, revision: revision))
        }
        selection.restore(question, revision: "1:2"); XCTAssertEqual(selection.marked, [])
    }
    func testNormalAndInlineHostSelectionRecognizesCompareBeforeAmbientProgress() throws {
        let state = try makeCompareState(version: 1)
        XCTAssertEqual(PlayKitScreenKind.present(in: state), [.compare])
        XCTAssertEqual(ChapterInlineKitSelection.preferred(in: state), .compare)
        XCTAssertFalse(state.readyForBase)
    }
}

private func makeCompareState(version: Int) throws -> PlayAdvancedState {
    let segment = try JSONDecoder().decode(PlayWireValue.self, from: Data(compareQuestionJSON.utf8))
    return try .init(.object(["sessionId": .int(1), "activityId": .int(41), "topicId": .int(71), "nodeId": .int(701), "version": .int(version), "status": .string("RUNNING"), "readyForBase": .bool(false), "playKit": .object(["compare": segment])]))
}
@MainActor final class PlayCompareReviewTests: XCTestCase {
    private func response(_ version: Int) throws -> Data {
        let segment = try JSONDecoder().decode(PlayWireValue.self, from: Data(compareQuestionJSON.utf8))
        let state: PlayWireValue = .object(["sessionId": .int(1), "activityId": .int(41), "topicId": .int(71), "nodeId": .int(701), "version": .int(version), "status": .string("RUNNING"), "readyForBase": .bool(false), "playKit": .object(["compare": segment])])
        return try JSONEncoder().encode(PlayWireValue.object(["code": .int(200), "data": state]))
    }
    private func owner(_ epoch: UInt64 = 1) throws -> PlayExperienceSession { try .init(accountID: 1, epoch: epoch, namespace: "synthetic", token: "synthetic-token") }
    private func model(_ transport: CompareTestTransport, owner: @escaping () -> PlayExperienceSession?) throws -> PlayAdvancedCoordinator {
        .init(activityID: 41, topicID: 71, nodeID: 701, service: .init(configuration: try APIConfiguration(baseURL: URL(string: "https://example.com")!), transport: transport, enabled: [.reads, .advanced]), currentSession: owner)
    }
    func testReviewCapturesReadableQuestionAndRejectsFreshVersion() async throws {
        let owner = try owner(); var version = 1
        let transport = CompareTestTransport { _ in (try self.response(version), 200) }
        let model = try model(transport, owner: { owner }); await model.start()
        let review = try model.review(kind: "compare", action: "SUBMIT_COMPARE", detail: ["marked": .array([.string("z-left")])])
        XCTAssertEqual(review.compareQuestion?.left.items[0].text, "Gate opened")
        version = 2; await model.refreshAuthoritative()
        let sent = await model.submit(review); XCTAssertFalse(sent)
        XCTAssertEqual(transport.requests.count, 2)
    }
    func testOwnerChangeAndDoubleConfirmCannotDispatch() async throws {
        var owner: PlayExperienceSession? = try owner()
        let transport = CompareTestTransport { _ in (try self.response(1), 200) }
        let model = try model(transport, owner: { owner }); await model.start()
        let review = try model.review(kind: "compare", action: "SUBMIT_COMPARE", detail: ["marked": .array([])])
        owner = try self.owner(2)
        let first = await model.submit(review), second = await model.submit(review)
        XCTAssertFalse(first); XCTAssertFalse(second); XCTAssertEqual(transport.requests.count, 1)
    }
    func testUnknownRetainsExactComparePayloadAndKeyAfterReadback() async throws {
        let owner = try owner(); var writes = 0
        let transport = CompareTestTransport { request in
            if request.url?.path.hasSuffix("/action") == true { writes += 1; throw URLError(.timedOut) }
            return (try self.response(writes == 0 ? 1 : 3), 200)
        }
        let model = try model(transport, owner: { owner }); await model.start()
        let review = try model.review(kind: "compare", action: "SUBMIT_COMPARE", detail: ["marked": .array([.string("b-right"), .string("z-left")])])
        _ = await model.submit(review); let frozen = try XCTUnwrap(model.pending)
        XCTAssertEqual(model.phase, "unknown")
        _ = await model.submit(review); XCTAssertEqual(writes, 1)
        await model.recover(); XCTAssertEqual(model.phase, "retryable"); XCTAssertEqual(model.pending, frozen)
        XCTAssertThrowsError(try model.review(kind: "compare", action: "SUBMIT_COMPARE", detail: ["marked": .array([])]))
        await model.retryExact()
        let requests = transport.requests.filter { $0.url?.path.hasSuffix("/action") == true }
        XCTAssertEqual(requests.count, 2); XCTAssertEqual(requests[0].httpBody, requests[1].httpBody)
        let body = try JSONDecoder().decode(PlayWireValue.self, from: XCTUnwrap(requests[0].httpBody))
        XCTAssertEqual(body["payload"], .object(["marked": .array([.string("b-right"), .string("z-left")])]))
        XCTAssertEqual(body["version"], .int(1)); XCTAssertEqual(body["action"], .string("SUBMIT_COMPARE"))
        XCTAssertFalse(model.state?.readyForBase ?? true)
    }
}
private final class CompareTestTransport: HTTPTransport {
    var requests: [URLRequest] = []
    let response: @MainActor (URLRequest) async throws -> (Data, Int)
    init(_ response: @escaping @MainActor (URLRequest) async throws -> (Data, Int)) { self.response = response }
    func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); return try await response(request) }
}

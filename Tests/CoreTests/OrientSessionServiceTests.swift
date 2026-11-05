import XCTest
import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

// All responses below are synthetic contract examples. No live backend is called.
@MainActor final class OrientTestTransport: HTTPTransport {
    var replies: [Result<(Data, Int), Error>] = []
    var requests: [URLRequest] = []
    var beforeReply: ((URLRequest) -> Void)?
    func append(_ data: String, code: Int = 200, err: String? = nil, errorCode: String? = nil, status: Int = 200) {
        let extra = (err.map { ",\"err\":\"\($0)\"" } ?? "") + (errorCode.map { ",\"errorCode\":\"\($0)\"" } ?? "")
        replies.append(.success((Data("{\"code\":\(code)\(extra),\"data\":\(data)}".utf8), status)))
    }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request); beforeReply?(request)
        guard !replies.isEmpty else { throw URLError(.badServerResponse) }
        return try replies.removeFirst().get()
    }
}

@MainActor func orientTestService(_ transport: any HTTPTransport) throws -> OrientSessionService {
    try .init(configuration: APIConfiguration(baseURL: URL(string: "https://example.test")!), transport: transport)
}
func orientTestScope(activity: Int = 0) throws -> OrientSessionScope { try .init(topicID: 3, activityID: activity, productType: 1) }
func orientTestOwner(account: Int = 1, namespace: String = "synthetic-cn-realm", role: String = "player") throws -> OrientSessionRecoveryOwner {
    try .init(namespace: namespace, accountID: account, role: role)
}
func orientTestPending(_ operation: OrientSessionOperation, activity: Int = 0, key: String = "test-key-01") throws -> OrientSessionPending {
    try .init(owner: orientTestOwner(), scope: orientTestScope(activity: activity), key: key, operation: operation)
}
func orientTestView(id: Int = 9, topic: Int = 3, activity: Int = 0, phase: String = "RUNNING", status: Int = 0, elapsed: Int = 400) -> String {
    let clock = phase == "PREPARED" ? "\"startedAt\":null,\"elapsedMs\":null" : "\"startedAt\":100,\"elapsedMs\":\(elapsed)"
    return "{\"sessionId\":\(id),\"topicId\":\(topic),\"activityId\":\(activity),\"phase\":\"\(phase)\",\"status\":\(status),\"configVersion\":7,\(clock),\"serverNow\":900}"
}
let orientTestSafety = "{\"allowed\":true,\"blockers\":[],\"night\":false,\"insuranceRequired\":false,\"sosAvailable\":true}"
let orientTestSettlement = "{\"state\":\"SETTLED\",\"sessionId\":9,\"settlementId\":70,\"totalCenti\":1700,\"pointsAwarded\":17,\"xpAwarded\":4,\"idempotencyKey\":\"original-settle-key\"}"
func orientTestScore(settlement: String = "null") -> String {
    "{\"sessionId\":9,\"topicId\":3,\"activityId\":0,\"status\":1,\"totalCenti\":1700,\"byDimension\":{\"TASK\":2000,\"PUZZLE\":0,\"BONUS\":0,\"PENALTY\":-300,\"ADJUSTMENT\":0},\"timeline\":[],\"settlement\":\(settlement),\"appeals\":[],\"disputes\":[]}"
}
func orientTestAlternative(outcome: String = "PENDING_REVIEW", type: String = "PHOTO", completed: Bool = false) -> String {
    "{\"attemptId\":71,\"taskId\":12,\"alternativeTaskType\":\"\(type)\",\"outcome\":\"\(outcome)\",\"completed\":\(completed),\"completedVia\":\(completed ? "\"\(type)\"" : "null"),\"replay\":false}"
}

@MainActor final class OrientSessionServiceTests: XCTestCase {
    func testPrepareIncludesRealTopicAndActivityAndStableKeyAsForm() async throws {
        let t = OrientTestTransport(); t.append(orientTestView(activity: 21, phase: "PREPARED"))
        let pending = try orientTestPending(.prepare, activity: 21)
        guard case .session(let row) = try await orientTestService(t).write(pending, token: "synthetic-token") else { return XCTFail() }
        XCTAssertEqual(row.scope.activityID, 21)
        let request = try XCTUnwrap(t.requests.first)
        XCTAssertEqual(request.url?.path, "/api/play/orient/session/prepare")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic-token")
        XCTAssertEqual(String(data: request.httpBody!, encoding: .utf8), "activityId=21&idempotencyKey=test-key-01&topicId=3")
        XCTAssertTrue(request.value(forHTTPHeaderField: "Content-Type")!.hasPrefix("application/x-www-form-urlencoded"))
    }
    func testLifecyclePathsAndVersionAreExact() async throws {
        let t = OrientTestTransport(); let service = try orientTestService(t)
        t.append(orientTestView()); _ = try await service.write(orientTestPending(.start(sessionID: 9, ackConfigVersion: 7)), token: "synthetic-token")
        t.append(orientTestView(phase: "ABANDONED", status: 2)); _ = try await service.write(orientTestPending(.abandon(sessionID: 9)), token: "synthetic-token")
        XCTAssertEqual(t.requests.map { $0.url!.path }, ["/api/play/orient/session/start", "/api/play/orient/session/abandon"])
        XCTAssertEqual(String(data: t.requests[0].httpBody!, encoding: .utf8), "ackConfigVersion=7&idempotencyKey=test-key-01&sessionId=9")
        XCTAssertFalse(t.requests.contains { $0.url!.absoluteString.contains("finish") || $0.url!.absoluteString.contains("resume") })
    }
    func testWrongScopeAndWrongSessionCannotBecomeFacts() async throws {
        let t = OrientTestTransport(); t.append(orientTestView(topic: 4)); t.append(orientTestView(id: 10))
        let service = try orientTestService(t)
        for _ in 0..<2 {
            do { _ = try await service.view(sessionID: 9, scope: orientTestScope(), token: "synthetic-token"); XCTFail() }
            catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
        }
    }
    func testSafetyJSONAndOwnerTypeMapping() async throws {
        let t = OrientTestTransport(); let service = try orientTestService(t)
        t.append(orientTestSafety); _ = try await service.safety(scope: orientTestScope(activity: 21), token: "synthetic-token")
        t.append("[]"); _ = try await service.lobby(scope: orientTestScope(), token: "synthetic-token")
        t.append("[]"); _ = try await service.ranking(scope: orientTestScope(activity: 21), token: "synthetic-token")
        XCTAssertEqual(t.requests[0].value(forHTTPHeaderField: "Content-Type"), "application/json")
        let fields = try JSONSerialization.jsonObject(with: t.requests[0].httpBody!) as! [String: String]
        XCTAssertEqual(fields, ["topicId": "3", "activityId": "21"])
        XCTAssertEqual(t.requests[1].url?.query, "ownerId=3&ownerType=1")
        XCTAssertEqual(t.requests[2].url?.query, "ownerId=21&ownerType=2")
    }
    func testSafetyContradictionIsMalformed() async throws {
        let t = OrientTestTransport(); t.append(orientTestSafety.replacingOccurrences(of: "\"allowed\":true", with: "\"allowed\":false"))
        do { _ = try await orientTestService(t).safety(scope: orientTestScope(), token: "synthetic-token"); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
    }
    func testTeamDetailAndTaskStateMatchIDs() async throws {
        let t = OrientTestTransport(); let service = try orientTestService(t)
        t.append("{\"team\":{\"teamId\":88},\"tasks\":[],\"members\":[],\"summary\":{}}")
        _ = try await service.teamDetail(teamID: 88, token: "synthetic-token")
        t.append("{\"taskId\":12,\"completed\":false,\"completedVia\":null,\"photoPendingReview\":true,\"alternatives\":[{\"alternativeTaskType\":\"PHOTO\",\"promptText\":\"证据\"}]}")
        let state = try await service.taskState(scope: orientTestScope(), taskID: 12, playInstanceID: "route:real-from-read", token: "synthetic-token")
        XCTAssertFalse(state.completed); XCTAssertTrue(state.photoPendingReview)
        XCTAssertEqual(t.requests.last?.url?.path, "/api/orient/task/state")
    }
    func testPhotoPendingIsNotCompletionAndUsesOwnedURLOnly() async throws {
        let t = OrientTestTransport(); t.append(orientTestAlternative())
        let pending = try orientTestPending(.alternative(sessionID: 9, taskID: 12, playInstanceID: nil, evidence: .photo(picURL: "owned-media-path")))
        guard case .alternative(let receipt) = try await orientTestService(t).write(pending, token: "synthetic-token") else { return XCTFail() }
        XCTAssertFalse(receipt.completed); XCTAssertEqual(receipt.outcome, "PENDING_REVIEW")
        let fields = try JSONSerialization.jsonObject(with: t.requests[0].httpBody!) as! [String: String]
        XCTAssertEqual(fields["alternativeTaskType"], "PHOTO"); XCTAssertEqual(fields["picUrl"], "owned-media-path")
        for key in ["sessionId", "lng", "lat", "coordSys", "playInstanceId", "completed", "outcome"] { XCTAssertNil(fields[key]) }
    }
    func testRejectedQuizStillReturnsRecordedAttempt() async throws {
        let t = OrientTestTransport(); t.append(orientTestAlternative(outcome: "REJECTED", type: "QUIZ"), code: 500, errorCode: "ORIENT_ALT_VERIFY_FAILED")
        let op = try orientTestPending(.alternative(sessionID: 9, taskID: 12, playInstanceID: nil, evidence: .quiz(answer: "输入&+=中文")))
        guard case .alternative(let receipt) = try await orientTestService(t).write(op, token: "synthetic-token") else { return XCTFail() }
        XCTAssertFalse(receipt.completed); XCTAssertEqual(receipt.outcome, "REJECTED")
        XCTAssertEqual((try JSONSerialization.jsonObject(with: t.requests[0].httpBody!) as! [String: String])["answer"], "输入&+=中文")
    }
    func testTaskAlreadyCompletedRequiresMatchingServerReceipt() async throws {
        let t = OrientTestTransport()
        let receipt = "{\"sessionId\":9,\"taskId\":12,\"alternativeTaskType\":null,\"receiptId\":\"orient:task:12\",\"completedAt\":500,\"elapsedMs\":400,\"phase\":\"RUNNING\"}"
        t.append(receipt, code: 409, err: "ORIENT_TASK_ALREADY_COMPLETED")
        _ = try await orientTestService(t).write(orientTestPending(.task(sessionID: 9, taskID: 12, alternative: nil)), token: "synthetic-token")
        t.append(receipt.replacingOccurrences(of: "orient:task:12", with: "guessed"), code: 409, err: "ORIENT_TASK_ALREADY_COMPLETED")
        do { _ = try await orientTestService(t).write(orientTestPending(.task(sessionID: 9, taskID: 12, alternative: nil)), token: "synthetic-token"); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
    }
    func testSettlementAndReadbackNeverCalculateRewards() async throws {
        let t = OrientTestTransport(); let service = try orientTestService(t)
        t.append(orientTestSettlement)
        guard case .settlement(let result) = try await service.write(orientTestPending(.settle(sessionID: 9)), token: "synthetic-token") else { return XCTFail() }
        XCTAssertEqual(result.pointsAwarded, 17); XCTAssertEqual(result.idempotencyKey, "original-settle-key")
        t.append(orientTestView(phase: "FINISHED", status: 1)); t.append(orientTestSettlement)
        _ = try await service.receipt(orientTestPending(.settle(sessionID: 9)), token: "synthetic-token")
        XCTAssertEqual(t.requests.last?.url?.path, "/api/orient/scoring/receipt")
        XCTAssertEqual(t.requests.last?.url?.query, "idempotencyKey=test-key-01&kind=SETTLE&sessionId=9")
        t.append(orientTestScore()); let score = try await service.score(sessionID: 9, scope: orientTestScope(), token: "synthetic-token")
        XCTAssertNil(score.settlement); XCTAssertEqual(score.totalCenti, 1700)
    }
    func testFrozenSyncUsesNoKeyAndNoReceiptClaim() async throws {
        let t = OrientTestTransport(); t.append("{\"sessionId\":9,\"added\":0,\"totalCenti\":1700}")
        _ = try await orientTestService(t).syncScore(sessionID: 9, token: "synthetic-token")
        XCTAssertEqual(t.requests.first?.url?.path, "/api/orient/scoring/session/9/sync")
        XCTAssertEqual(t.requests.first?.httpBody, Data())
    }
    func testPrepareRecoveryCannotGuessAnID() async throws {
        let t = OrientTestTransport()
        do { _ = try await orientTestService(t).receipt(orientTestPending(.prepare), token: "synthetic-token"); XCTFail() }
        catch { XCTAssertEqual(error as? OrientSessionFlowError, .sessionRequired) }
        XCTAssertTrue(t.requests.isEmpty)
    }
    func testFailureKeepsBothMachineCodeFamiliesAndHTTPBoundary() async throws {
        let t = OrientTestTransport(); let service = try orientTestService(t)
        t.append("null", code: 409, err: "ORIENT_ACK_REQUIRED", errorCode: "ORIENT_DISABLED")
        do { _ = try await service.view(sessionID: 9, scope: orientTestScope(), token: "synthetic-token"); XCTFail() }
        catch let error as OrientSessionFailure {
            XCTAssertEqual(error.err, "ORIENT_ACK_REQUIRED"); XCTAssertEqual(error.errorCode, "ORIENT_DISABLED"); XCTAssertTrue(error.rejectedWithoutWrite)
        }
        t.append("null", code: 401, status: 503)
        do { _ = try await service.view(sessionID: 9, scope: orientTestScope(), token: "synthetic-token"); XCTFail() }
        catch let error as OrientSessionFailure { XCTAssertEqual(error.httpStatus, 503); XCTAssertFalse(error.rejectedWithoutWrite) }
    }
    func testProductTypesAndInvalidKeysStopBeforeNetwork() async throws {
        XCTAssertThrowsError(try OrientSessionScope(topicID: 3, productType: 2))
        XCTAssertThrowsError(try OrientSessionScope(topicID: 3, productType: 0))
        XCTAssertThrowsError(try orientTestPending(.prepare, key: "short"))
        let t = OrientTestTransport()
        do { _ = try await orientTestService(t).view(sessionID: 9, scope: orientTestScope(), token: "bad\nheader"); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        XCTAssertTrue(t.requests.isEmpty)
    }
    func testLargeIDsRemainExactAndUnknownPhaseFails() async throws {
        let id = 9_007_199_254_740_993
        let row = try JSONDecoder().decode(OrientSessionView.self, from: Data(orientTestView(id: id).utf8))
        XCTAssertEqual(row.sessionID, id)
        XCTAssertThrowsError(try JSONDecoder().decode(OrientSessionView.self, from: Data(orientTestView(phase: "RPG").utf8)))
    }
}

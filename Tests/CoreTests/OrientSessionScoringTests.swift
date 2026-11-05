import XCTest
import Foundation
@testable import QuestifyCore

// Executed synthetic contract examples of public hengyin c6 scoring, not live data.
@MainActor private func orientScoringService(_ t: any HTTPTransport) throws -> OrientSessionService {
    try .init(configuration: APIConfiguration(baseURL: URL(string: "https://example.test")!), transport: t, contract: .currentC6)
}
private func syncReceipt(session: Int = 9, member: Int = 1, key: String = "score-key-01", total: String = "1700") -> String {
    "{\"state\":\"SYNCED\",\"kind\":\"SYNC\",\"sessionId\":\"\(session)\",\"memberId\":\"\(member)\",\"idempotencyKey\":\"\(key)\",\"added\":2,\"totalCenti\":\"\(total)\"}"
}
private func reviewRecord(id: Int = 72, session: Int = 9, member: Int = 1, entry: Int? = 30, node: Int? = nil,
                          reason: String = "申请复核", status: Int = 0, key: String = "score-key-01") -> String {
    let fields: [String: Any] = ["id": String(id), "sessionId": String(session), "memberId": String(member),
        "entryId": entry.map(String.init) as Any? ?? NSNull(), "nodeId": node.map(String.init) as Any? ?? NSNull(),
        "reason": reason, "status": status, "idempotencyKey": key, "resolutionEntryId": NSNull(),
        "resolutionNote": status == 0 ? NSNull() : "平台处理结果", "windowDeadline": NSNull(),
        "handledBy": "synthetic-staff", "requestFingerprint": "synthetic-fingerprint"]
    return String(data: try! JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]), encoding: .utf8)!
}
private func reviewReceipt(_ record: String, kind: String = "APPEAL", state: String = "PENDING", key: String = "score-key-01") -> String {
    "{\"state\":\"\(state)\",\"kind\":\"\(kind)\",\"idempotencyKey\":\"\(key)\",\"record\":\(record)}"
}
private func reviewScore(appeals: [String] = [], disputes: [String] = [], status: Int = 0, total: Int = 1700) -> String {
    orientTestScore().replacingOccurrences(of: "\"status\":1", with: "\"status\":\(status)")
        .replacingOccurrences(of: "\"appeals\":[]", with: "\"appeals\":[" + appeals.joined(separator: ",") + "]")
        .replacingOccurrences(of: "\"disputes\":[]", with: "\"disputes\":[" + disputes.joined(separator: ",") + "]")
        .replacingOccurrences(of: "\"totalCenti\":1700", with: "\"totalCenti\":\(total)")
}
private func boardRow(key: Int = 1, rank: Int = 1, score: String = "9007199254740993", mine: Bool = false, elapsed: String = "null") -> String {
    "{\"rowKey\":\"\(key)\",\"rank\":\"\(rank)\",\"scoreCenti\":\"\(score)\",\"elapsedMs\":\(elapsed),\"mine\":\(mine),\"reachedEnding\":true}"
}
private func board(rows: [String], me: String = "null", mode: String = "SCORE", session: Int = 9) -> String {
    "{\"sessionId\":\"\(session)\",\"mode\":\"\(mode)\",\"list\":[" + rows.joined(separator: ",") + "],\"me\":\(me)}"
}

@MainActor final class OrientSessionScoringTests: XCTestCase {
    private func make(_ t: OrientTestTransport, _ store: any OrientSessionRecovery, _ box: OrientTestIdentityBox) throws -> OrientSessionCoordinator {
        try .init(scope: orientTestScope(), service: orientScoringService(t), recovery: store, currentIdentity: { box.value })
    }
    func testKeyedSyncPersistsBeforeFormWriteAndReadsFreshScore() async throws {
        let t = OrientTestTransport(); let store = OrientTestRecovery(); let box = try OrientTestIdentityBox(); let c = try make(t, store, box)
        t.append(orientTestView()); try await c.resume(sessionID: 9)
        t.beforeReply = { request in
            if request.httpMethod == "POST" { XCTAssertEqual(store.value?.operation, .sync(sessionID: 9)); XCTAssertEqual(store.value?.key, "score-key-01") }
        }
        t.append(syncReceipt()); t.append(orientTestView()); t.append(reviewScore(total: 2400))
        try await c.synchronizeScore(key: "score-key-01")
        XCTAssertEqual(t.requests[1].url?.path, "/api/orient/scoring/session/9/sync")
        XCTAssertEqual(String(data: t.requests[1].httpBody!, encoding: .utf8), "idempotencyKey=score-key-01")
        XCTAssertTrue(t.requests[1].value(forHTTPHeaderField: "Content-Type")!.hasPrefix("application/x-www-form-urlencoded"))
        XCTAssertEqual(c.score?.totalCenti, 2400) // may differ from the earlier receipt; never recomputed locally
        guard case .sync(let receipt) = c.lastReceipt else { return XCTFail() }
        XCTAssertEqual(receipt.totalCenti, 1700); XCTAssertNil(store.value)
    }
    func testSyncReceiptRequiresExactOwnerSessionAndOriginalKey() async throws {
        let t = OrientTestTransport(); let service = try orientScoringService(t); let pending = try orientTestPending(.sync(sessionID: 9), key: "score-key-01")
        for data in [syncReceipt(member: 2), syncReceipt(session: 10), syncReceipt(key: "different-key")] {
            t.append(data)
            do { _ = try await service.write(pending, token: "synthetic-token"); XCTFail() }
            catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
        }
    }
    func testSyncTimeoutSurvivesFileRestartAndRecoversWithOnlyReads() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("orient-score-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("pending.json"); let store = try OrientSessionFileRecovery(fileURL: file)
        let t = OrientTestTransport(); let box = try OrientTestIdentityBox(); let c = try make(t, store, box)
        t.append(orientTestView()); try await c.resume(sessionID: 9)
        t.replies.append(.failure(URLError(.timedOut)))
        do { try await c.synchronizeScore(key: "permanent-sync-key"); XCTFail() } catch {}
        XCTAssertEqual(try store.read()?.operation, .sync(sessionID: 9))
        let restartedStore = try OrientSessionFileRecovery(fileURL: file)
        let newBox = try OrientTestIdentityBox(epoch: 2, token: "new-synthetic-token")
        let restarted = try make(t, restartedStore, newBox)
        t.append(orientTestView()); t.append(syncReceipt(key: "permanent-sync-key")); t.append(orientTestView()); t.append(reviewScore())
        let before = t.requests.count; try await restarted.recoverPending()
        XCTAssertTrue(t.requests.dropFirst(before).allSatisfy { $0.httpMethod == "GET" })
        XCTAssertEqual(t.requests[before + 1].url?.query, "idempotencyKey=permanent-sync-key&kind=SYNC&sessionId=9")
        XCTAssertNil(try restartedStore.read()); XCTAssertEqual(restarted.score?.totalCenti, 1700)
    }
    func testNotFoundSyncReceiptKeepsOriginalAndBlocksReplacementWrite() async throws {
        let t = OrientTestTransport(); let store = OrientTestRecovery(); let box = try OrientTestIdentityBox()
        let original = try orientTestPending(.sync(sessionID: 9)); store.value = original; let c = try make(t, store, box)
        t.append(orientTestView()); t.append("{\"state\":\"NOT_FOUND\",\"kind\":\"SYNC\",\"idempotencyKey\":\"test-key-01\"}")
        do { try await c.recoverPending(); XCTFail() } catch { XCTAssertEqual(error as? OrientSessionFlowError, .receiptUnresolved) }
        XCTAssertEqual(store.value, original)
        t.append(orientTestView()); try await c.resume(sessionID: 9)
        let count = t.requests.count
        do { try await c.synchronizeScore(key: "replacement-key"); XCTFail() } catch { XCTAssertEqual(error as? OrientSessionFlowError, .pendingOperation) }
        XCTAssertEqual(t.requests.count, count); XCTAssertEqual(store.value, original)
    }
    func testAppealSendsCanonicalReasonAndWaitsForAuthoritativeReviewList() async throws {
        let t = OrientTestTransport(); let store = OrientTestRecovery(); let box = try OrientTestIdentityBox(); let c = try make(t, store, box)
        t.append(orientTestView()); try await c.resume(sessionID: 9)
        let reason = "申请&+=复核"; let original = reviewRecord(reason: reason)
        t.append(original); t.append(orientTestView()); t.append(reviewScore(appeals: [reviewRecord(reason: reason, status: 1)]))
        try await c.appeal(confirmed: true, entryID: 30, reason: " \n" + reason + "\r ", key: "score-key-01")
        let form = String(data: t.requests[1].httpBody!, encoding: .utf8)!
        XCTAssertEqual(t.requests[1].url?.path, "/api/orient/scoring/appeal")
        XCTAssertTrue(form.contains("entryId=30")); XCTAssertTrue(form.contains("sessionId=9"))
        XCTAssertTrue(form.contains("%26%2B%3D")); XCTAssertFalse(form.contains("nodeId="))
        guard case .review(let submitted) = c.lastReceipt else { return XCTFail() }
        XCTAssertEqual(submitted.record.status, 0) // submission itself is not acceptance
        XCTAssertEqual(c.score?.appealRecords.first?.status, 1) // separate server read
        XCTAssertNil(store.value)
        let exposed = Mirror(reflecting: submitted.record).children.compactMap(\.label)
        XCTAssertFalse(exposed.contains("handledBy")); XCTAssertFalse(exposed.contains("requestFingerprint"))
    }
    func testAppealTimeoutRetryRetainsExactPayloadAndKey() async throws {
        let t = OrientTestTransport(); let store = OrientTestRecovery(); let box = try OrientTestIdentityBox(); let c = try make(t, store, box)
        t.append(orientTestView()); try await c.resume(sessionID: 9)
        t.replies.append(.failure(URLError(.networkConnectionLost)))
        do { try await c.appeal(confirmed: true, nodeID: 12, reason: "漏记任务", key: "original-appeal-key"); XCTFail() } catch {}
        let first = t.requests.last!; let original = store.value
        do { try await c.appeal(confirmed: true, nodeID: 13, reason: "改写理由", key: "replacement-key"); XCTFail() }
        catch { XCTAssertEqual(error as? OrientSessionFlowError, .pendingOperation) }
        XCTAssertEqual(store.value, original)
        let record = reviewRecord(entry: nil, node: 12, reason: "漏记任务", key: "original-appeal-key")
        t.append(record); t.append(orientTestView()); t.append(reviewScore(appeals: [record]))
        try await c.retryPending()
        XCTAssertEqual(t.requests[t.requests.count - 3].httpBody, first.httpBody)
        XCTAssertEqual(t.requests[t.requests.count - 3].url, first.url); XCTAssertNil(store.value)
    }
    func testAppealReadbackValidatesWrapperAndOriginalImmutableFields() async throws {
        let t = OrientTestTransport(); let service = try orientScoringService(t)
        let pending = try orientTestPending(.appeal(sessionID: 9, entryID: 30, nodeID: nil, reason: "申请复核"), key: "score-key-01")
        let bad = [reviewReceipt(reviewRecord(member: 2)), reviewReceipt(reviewRecord(session: 10)),
                   reviewReceipt(reviewRecord(reason: "其他理由")), reviewReceipt(reviewRecord(entry: 31)),
                   reviewReceipt(reviewRecord(), kind: "DISPUTE"), reviewReceipt(reviewRecord(status: 1), state: "PENDING"),
                   reviewReceipt(reviewRecord(), key: "other-key"), reviewRecord()]
        for value in bad {
            t.append(orientTestView()); t.append(value)
            do { _ = try await service.receipt(pending, token: "synthetic-token"); XCTFail() }
            catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
        }
        t.append(orientTestView()); t.append(reviewReceipt(reviewRecord(status: 2), state: "REJECTED"))
        guard case .review(let value) = try await service.receipt(pending, token: "synthetic-token") else { return XCTFail() }
        XCTAssertEqual(value.record.status, 2); XCTAssertEqual(value.kind, .appeal)
        XCTAssertEqual(t.requests.last?.url?.query, "idempotencyKey=score-key-01&kind=APPEAL&sessionId=9")
    }
    func testReviewNotFoundNeverBecomesRejectionOrNewRequest() async throws {
        let t = OrientTestTransport(); let store = OrientTestRecovery(); let box = try OrientTestIdentityBox()
        let original = try orientTestPending(.appeal(sessionID: 9, entryID: 30, nodeID: nil, reason: "申请复核"), key: "score-key-01")
        store.value = original; let c = try make(t, store, box)
        t.append(orientTestView()); t.append("{\"state\":\"NOT_FOUND\",\"kind\":\"APPEAL\",\"idempotencyKey\":\"score-key-01\"}")
        do { try await c.recoverPending(); XCTFail() } catch { XCTAssertEqual(error as? OrientSessionFlowError, .receiptUnresolved) }
        XCTAssertEqual(store.value, original); XCTAssertNil(c.lastReceipt)
        XCTAssertTrue(t.requests.allSatisfy { $0.httpMethod == "GET" })
    }
    func testDisputeRequiresTerminalSessionAndUsesSeparateKind() async throws {
        let t = OrientTestTransport(); let store = OrientTestRecovery(); let box = try OrientTestIdentityBox(); let c = try make(t, store, box)
        t.append(orientTestView()); try await c.resume(sessionID: 9)
        do { try await c.dispute(confirmed: true, reason: "成绩异议", key: "test-key-02"); XCTFail() }
        catch { XCTAssertEqual(error as? OrientSessionFlowError, .notFinished) }
        XCTAssertEqual(t.requests.count, 1)
        t.append(orientTestView(phase: "FINISHED", status: 1)); try await c.resume(sessionID: 9)
        let record = reviewRecord(entry: nil, reason: "成绩异议", key: "test-key-02")
        t.append(record); t.append(orientTestView(phase: "FINISHED", status: 1)); t.append(reviewScore(disputes: [record], status: 1))
        try await c.dispute(confirmed: true, reason: "成绩异议", key: "test-key-02")
        XCTAssertEqual(t.requests[2].url?.path, "/api/orient/scoring/dispute")
        XCTAssertEqual(c.score?.disputeRecords.count, 1); XCTAssertTrue(c.score!.appealRecords.isEmpty)
        let form = String(data: t.requests[2].httpBody!, encoding: .utf8)!
        XCTAssertFalse(form.contains("entryId=")); XCTAssertFalse(form.contains("nodeId="))
    }
    func testDisputeRecoveryUsesOriginalKeyAndAcceptedWrapper() async throws {
        let t = OrientTestTransport(); let store = OrientTestRecovery(); let box = try OrientTestIdentityBox()
        let original = try orientTestPending(.dispute(sessionID: 9, reason: "成绩异议"), key: "test-key-02")
        store.value = original; let c = try make(t, store, box)
        let accepted = reviewRecord(entry: nil, reason: "成绩异议", status: 1, key: "test-key-02")
        t.append(orientTestView(phase: "FINISHED", status: 1)); t.append(reviewReceipt(accepted, kind: "DISPUTE", state: "ACCEPTED", key: "test-key-02"))
        t.append(orientTestView(phase: "FINISHED", status: 1)); t.append(reviewScore(disputes: [accepted], status: 1))
        try await c.recoverPending()
        XCTAssertNil(store.value); XCTAssertEqual(c.score?.disputeRecords.first?.state, "ACCEPTED")
        XCTAssertEqual(t.requests[1].url?.query, "idempotencyKey=test-key-02&kind=DISPUTE&sessionId=9")
        XCTAssertTrue(t.requests.allSatisfy { $0.httpMethod == "GET" })
    }
    func testReasonValidationConfirmationAndBackendUTF16Limit() async throws {
        let t = OrientTestTransport(); let store = OrientTestRecovery(); let box = try OrientTestIdentityBox(); let c = try make(t, store, box)
        t.append(orientTestView()); try await c.resume(sessionID: 9)
        do { try await c.appeal(confirmed: false, entryID: 30, reason: "理由", key: "score-key-01"); XCTFail() }
        catch { XCTAssertEqual(error as? OrientSessionFlowError, .confirmationRequired) }
        for text in [" \n\r\t", String(repeating: "😀", count: 251)] {
            do { try await c.appeal(confirmed: true, entryID: 30, reason: text, key: "score-key-01"); XCTFail() }
            catch { XCTAssertEqual(error as? APIError, .invalidRequest) }
        }
        XCTAssertThrowsError(try orientTestPending(.appeal(sessionID: 9, entryID: nil, nodeID: nil, reason: "理由")))
        XCTAssertThrowsError(try orientTestPending(.appeal(sessionID: 9, entryID: 0, nodeID: nil, reason: "理由")))
        XCTAssertEqual(try OrientSessionScoreReason.normalized(" \n理由\r "), "理由")
        XCTAssertNoThrow(try orientTestPending(.appeal(sessionID: 9, entryID: nil, nodeID: 12, reason: String(repeating: "😀", count: 250))))
        XCTAssertEqual(t.requests.count, 1); XCTAssertNil(store.value)
    }
    func testScoringKeyContractAndFrozenGate() async throws {
        XCTAssertNoThrow(try orientTestPending(.sync(sessionID: 9), key: "a"))
        XCTAssertNoThrow(try orientTestPending(.sync(sessionID: 9), key: String(repeating: "a", count: 96)))
        XCTAssertThrowsError(try orientTestPending(.sync(sessionID: 9), key: String(repeating: "a", count: 97)))
        let t = OrientTestTransport(); let frozen = try orientTestService(t)
        do { _ = try await frozen.write(orientTestPending(.sync(sessionID: 9)), token: "synthetic-token"); XCTFail() }
        catch { XCTAssertEqual(error as? OrientSessionFlowError, .unsupportedContract) }
        do { _ = try await frozen.leaderboard(sessionID: 9, token: "synthetic-token"); XCTFail() }
        catch { XCTAssertEqual(error as? OrientSessionFlowError, .unsupportedContract) }
        XCTAssertTrue(t.requests.isEmpty)
    }
    func testReviewReceiptWithoutFreshListEvidenceKeepsPending() async throws {
        let t = OrientTestTransport(); let store = OrientTestRecovery(); let box = try OrientTestIdentityBox(); let c = try make(t, store, box)
        t.append(orientTestView()); try await c.resume(sessionID: 9)
        t.append(reviewRecord()); t.append(orientTestView()); t.append(reviewScore())
        do { try await c.appeal(confirmed: true, entryID: 30, reason: "申请复核", key: "score-key-01"); XCTFail() }
        catch { XCTAssertEqual(error as? OrientSessionFlowError, .receiptUnresolved) }
        XCTAssertNotNil(store.value); XCTAssertNil(c.lastReceipt)
    }
    func testConflictAndClosedWindowDoNotEraseOriginalScoreOperation() async throws {
        for code in ["ORIENT_IDEMPOTENCY_CONFLICT", "ORIENT_WINDOW_CLOSED"] {
            let t = OrientTestTransport(); let store = OrientTestRecovery(); let box = try OrientTestIdentityBox(); let c = try make(t, store, box)
            t.append(orientTestView()); try await c.resume(sessionID: 9)
            t.append("null", code: 500, errorCode: code)
            do { try await c.appeal(confirmed: true, entryID: 30, reason: "申请复核", key: "score-key-01"); XCTFail() }
            catch let error as OrientSessionFailure { XCTAssertEqual(error.errorCode, code) }
            XCTAssertEqual(store.value?.key, "score-key-01")
        }
    }
    func testLeaderboardKeepsServerTiesExactScoresAndOutsideMe() async throws {
        let t = OrientTestTransport(); let service = try orientScoringService(t)
        let outside = boardRow(key: 99, rank: 100, score: "-300", mine: true, elapsed: "\"9007199254740993\"")
        t.append(board(rows: [boardRow(), boardRow(key: 2)], me: outside, mode: "ROUTE"))
        let result = try await service.leaderboard(sessionID: 9, token: "synthetic-token")
        XCTAssertEqual(result.list.map(\.rank), [1, 1]); XCTAssertEqual(result.list[0].scoreCenti, 9_007_199_254_740_993)
        XCTAssertEqual(result.me?.rank, 100); XCTAssertEqual(result.me?.elapsedMs, 9_007_199_254_740_993)
        XCTAssertEqual(result.me?.scoreCenti, -300); XCTAssertEqual(result.list.count, 2)
        XCTAssertEqual(t.requests.first?.url?.path, "/api/orient/scoring/session/9/leaderboard")
        XCTAssertEqual(t.requests.first?.httpMethod, "GET")
        let fields = Mirror(reflecting: result.list[0]).children.compactMap(\.label)
        XCTAssertFalse(fields.contains("memberID")); XCTAssertFalse(fields.contains("sessionID"))
    }
    func testLeaderboardRejectsDuplicateKeysWrongMeAndWrongSession() async throws {
        let t = OrientTestTransport(); let service = try orientScoringService(t)
        let duplicate = board(rows: [boardRow(), boardRow()])
        let falseMe = board(rows: [], me: boardRow(mine: false))
        let missingMe = board(rows: [boardRow(mine: true)])
        let wrongSession = board(rows: [], session: 10)
        for data in [duplicate, falseMe, missingMe, wrongSession, board(rows: Array(repeating: boardRow(), count: 51))] {
            t.append(data)
            do { _ = try await service.leaderboard(sessionID: 9, token: "synthetic-token"); XCTFail() }
            catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
        }
    }
    func testLeaderboardForbiddenHasNoLocalFallbackOrSecondRequest() async throws {
        let t = OrientTestTransport(); t.append("null", code: 500, errorCode: "ORIENT_FORBIDDEN")
        do { _ = try await orientScoringService(t).leaderboard(sessionID: 9, token: "synthetic-token"); XCTFail() }
        catch let error as OrientSessionFailure { XCTAssertEqual(error.errorCode, "ORIENT_FORBIDDEN") }
        XCTAssertEqual(t.requests.count, 1)
    }
    func testRevokedLeaderboardReadClearsPriorProjection() async throws {
        let t = OrientTestTransport(); let store = OrientTestRecovery(); let box = try OrientTestIdentityBox(); let c = try make(t, store, box)
        t.append(orientTestView()); try await c.resume(sessionID: 9)
        t.append(board(rows: [boardRow()])); try await c.loadPersonalLeaderboard()
        XCTAssertNotNil(c.personalLeaderboard)
        t.append("null", code: 500, errorCode: "ORIENT_FORBIDDEN")
        do { try await c.loadPersonalLeaderboard(); XCTFail() } catch {}
        XCTAssertNil(c.personalLeaderboard)
    }
    func testLateLeaderboardReplyCannotPopulateChangedIdentity() async throws {
        let t = OrientTestTransport(); let store = OrientTestRecovery(); let box = try OrientTestIdentityBox(); let c = try make(t, store, box)
        t.append(orientTestView()); try await c.resume(sessionID: 9)
        t.append(board(rows: [])); t.beforeReply = { request in if request.url!.path.hasSuffix("/leaderboard") { box.value = nil } }
        do { try await c.loadPersonalLeaderboard(); XCTFail() } catch { XCTAssertEqual(error as? OrientSessionFlowError, .staleIdentity) }
        XCTAssertNil(c.personalLeaderboard)
    }
    func testC6FinishReadsPersonalBoardAndNeverPostsFinish() async throws {
        let t = OrientTestTransport(); let store = OrientTestRecovery(); let box = try OrientTestIdentityBox(); let c = try make(t, store, box)
        t.append(orientTestView()); try await c.resume(sessionID: 9)
        t.append(orientTestView(phase: "FINISHED", status: 1)); t.append(reviewScore(status: 1)); t.append("[]"); t.append(board(rows: []))
        try await c.observeFinish()
        XCTAssertEqual(c.view?.phase, .finished); XCTAssertNotNil(c.personalLeaderboard)
        XCTAssertTrue(t.requests.allSatisfy { $0.httpMethod == "GET" }); c.leave(); XCTAssertNil(c.personalLeaderboard)
    }
    func testCancelledSyncKeepsPersistedOriginalForReadback() async throws {
        let t = OrientTestTransport(); let store = OrientTestRecovery(); let box = try OrientTestIdentityBox(); let c = try make(t, store, box)
        t.append(orientTestView()); try await c.resume(sessionID: 9)
        t.append(syncReceipt()); var task: Task<Void, Error>!
        t.beforeReply = { request in if request.httpMethod == "POST" { task.cancel() } }
        task = Task { try await c.synchronizeScore(key: "score-key-01") }
        do { try await task.value; XCTFail() } catch is CancellationError {}
        XCTAssertEqual(store.value?.operation, .sync(sessionID: 9)); XCTAssertEqual(store.value?.key, "score-key-01")
        XCTAssertNil(c.lastReceipt)
    }
    func testCanonicallyEquivalentReasonIsNotTheOriginalServerPayload() async throws {
        let originalReason = "cafe\u{0301}"; let differentBytes = "caf\u{00E9}"
        let t = OrientTestTransport(); let service = try orientScoringService(t)
        let pending = try orientTestPending(.appeal(sessionID: 9, entryID: 30, nodeID: nil, reason: originalReason), key: "score-key-01")
        t.append(reviewRecord(reason: differentBytes))
        do { _ = try await service.write(pending, token: "synthetic-token"); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
    }
    func testJournalClearRequiresOriginalReasonBytes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("orient-score-bytes-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try OrientSessionFileRecovery(fileURL: root.appendingPathComponent("pending.json"))
        let original = try orientTestPending(.appeal(sessionID: 9, entryID: 30, nodeID: nil, reason: "cafe\u{0301}"))
        let differentBytes = try orientTestPending(.appeal(sessionID: 9, entryID: 30, nodeID: nil, reason: "caf\u{00E9}"))
        try store.prepare(original)
        XCTAssertNotEqual(original, differentBytes)
        XCTAssertThrowsError(try store.clear(matching: differentBytes))
        XCTAssertEqual(try store.read(), original)
    }
}

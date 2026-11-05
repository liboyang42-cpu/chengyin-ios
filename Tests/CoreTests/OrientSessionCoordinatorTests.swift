import XCTest
import Foundation
@testable import QuestifyCore

@MainActor final class OrientTestRecovery: OrientSessionRecovery {
    var value: OrientSessionPending?
    var failPrepare = false
    var failClear = false
    func read() throws -> OrientSessionPending? { value }
    func prepare(_ pending: OrientSessionPending) throws {
        guard !failPrepare else { throw OrientSessionFlowError.storageUnavailable }
        guard value == nil else { throw OrientSessionFlowError.pendingOperation }; value = pending
    }
    func clear(matching pending: OrientSessionPending) throws {
        guard !failClear, value == pending else { throw OrientSessionFlowError.storageUnavailable }; value = nil
    }
}
@MainActor final class OrientTestIdentityBox {
    var value: OrientSessionIdentity?
    init(account: Int = 1, epoch: UInt64 = 1, token: String = "synthetic-token") throws {
        value = try .init(owner: orientTestOwner(account: account), epoch: epoch, token: token)
    }
}
@MainActor final class OrientSessionCoordinatorTests: XCTestCase {
    private func make(_ t: OrientTestTransport, _ store: any OrientSessionRecovery, _ box: OrientTestIdentityBox,
                      unauthorized: @escaping (OrientSessionIdentity) -> Void = { _ in }) throws -> OrientSessionCoordinator {
        try .init(scope: orientTestScope(), service: orientTestService(t), recovery: store,
            currentIdentity: { box.value }, onUnauthorized: unauthorized)
    }
    func testPrepareStartLeaveResumeFinishAndSettlementReadServerFacts() async throws {
        let t = OrientTestTransport(); let store = OrientTestRecovery(); let box = try OrientTestIdentityBox(); let c = try make(t, store, box)
        t.append(orientTestSafety); t.append(orientTestView(phase: "PREPARED")); t.append(orientTestView(phase: "PREPARED"))
        try await c.prepare(key: "prepare-key-01")
        XCTAssertEqual(c.view?.phase, .prepared); XCTAssertNil(store.value)
        t.append(orientTestSafety); t.append(orientTestView()); t.append(orientTestView(elapsed: 450))
        try await c.start(acknowledgedConfigVersion: 7, key: "start-key-01")
        XCTAssertEqual(c.view?.elapsedMs, 450)
        c.leave(); XCTAssertNil(c.view)
        let beforeResume = t.requests.count; t.append(orientTestView(elapsed: 800))
        try await c.resume(sessionID: 9)
        XCTAssertEqual(t.requests.count, beforeResume + 1); XCTAssertEqual(t.requests.last?.httpMethod, "GET")
        XCTAssertEqual(c.view?.startedAt, 100); XCTAssertEqual(c.view?.elapsedMs, 800)
        t.append(orientTestView(phase: "FINISHED", status: 1, elapsed: 1200)); t.append(orientTestScore()); t.append("[]")
        try await c.observeFinish()
        XCTAssertEqual(c.view?.phase, .finished); XCTAssertNil(c.score?.settlement)
        t.append(orientTestSettlement); t.append(orientTestView(phase: "FINISHED", status: 1)); t.append(orientTestScore(settlement: orientTestSettlement))
        try await c.settle(confirmed: true, key: "settle-key-01")
        XCTAssertEqual(c.score?.settlement?.pointsAwarded, 17); XCTAssertNil(c.pending)
        XCTAssertFalse(t.requests.contains { $0.url!.path.hasSuffix("/finish") || $0.url!.path.hasSuffix("/current") })
    }
    func testUnknownWriteSurvivesRestartAndReadsOriginalReceiptBeforeFreshView() async throws {
        let t = OrientTestTransport(); let store = OrientTestRecovery(); let box = try OrientTestIdentityBox()
        let c = try make(t, store, box)
        t.append(orientTestView(phase: "PREPARED")); try await c.resume(sessionID: 9)
        t.append(orientTestSafety); t.replies.append(.failure(URLError(.timedOut)))
        do { try await c.start(acknowledgedConfigVersion: 7, key: "stable-start-key"); XCTFail() } catch {}
        let original = try XCTUnwrap(store.value)
        XCTAssertEqual(original.key, "stable-start-key")
        let restarted = try make(t, store, box)
        t.append(orientTestView(phase: "FINISHED", status: 1)); t.append(orientTestView()); t.append(orientTestView(phase: "FINISHED", status: 1, elapsed: 1400))
        try await restarted.recoverPending()
        XCTAssertEqual(restarted.view?.phase, .finished); XCTAssertEqual(restarted.view?.elapsedMs, 1400)
        XCTAssertNil(store.value)
        XCTAssertEqual(t.requests.suffix(3).map { $0.httpMethod! }, ["GET", "GET", "GET"])
        XCTAssertTrue(t.requests[t.requests.count - 2].url!.query!.contains("idempotencyKey=stable-start-key"))
    }
    func testPrepareUnknownRequiresRealCandidateAndPreservesOriginalKey() async throws {
        let t = OrientTestTransport(); let store = OrientTestRecovery(); let box = try OrientTestIdentityBox(); let c = try make(t, store, box)
        t.append(orientTestSafety); t.replies.append(.failure(URLError(.timedOut)))
        do { try await c.prepare(key: "prepare-key-01"); XCTFail() } catch {}
        let count = t.requests.count
        do { try await c.recoverPending(); XCTFail() } catch { XCTAssertEqual(error as? OrientSessionFlowError, .sessionRequired) }
        XCTAssertEqual(t.requests.count, count); XCTAssertNotNil(store.value)
        t.append(orientTestView()); t.append(orientTestView(phase: "PREPARED")); t.append(orientTestView(elapsed: 1000))
        try await c.recoverPending(prepareSessionID: 9)
        XCTAssertNil(store.value); XCTAssertEqual(c.view?.phase, .running)
    }
    func testNotFoundReceiptNeverClearsOrCreatesReplacementKey() async throws {
        let t = OrientTestTransport(); let store = OrientTestRecovery(); let box = try OrientTestIdentityBox()
        store.value = try orientTestPending(.settle(sessionID: 9))
        let original = store.value; let c = try make(t, store, box)
        t.append(orientTestView(phase: "FINISHED", status: 1)); t.append("{\"state\":\"NOT_FOUND\",\"kind\":\"SETTLE\",\"idempotencyKey\":\"test-key-01\"}")
        do { try await c.recoverPending(); XCTFail() } catch {}
        XCTAssertEqual(store.value, original)
        do { try await c.prepare(key: "replacement-key"); XCTFail() } catch { XCTAssertEqual(error as? OrientSessionFlowError, .pendingOperation) }
        XCTAssertEqual(t.requests.count, 2)
    }
    func testSafetyBlockPreventsPersistenceAndWrite() async throws {
        let t = OrientTestTransport(); let store = OrientTestRecovery(); let box = try OrientTestIdentityBox(); let c = try make(t, store, box)
        t.append("{\"allowed\":false,\"blockers\":[{\"code\":\"WEATHER_BLOCKED\",\"message\":\"停玩\"}],\"night\":false,\"insuranceRequired\":false,\"sosAvailable\":true}")
        do { try await c.prepare(key: "prepare-key-01"); XCTFail() } catch { XCTAssertEqual(error as? OrientSessionFlowError, .safetyBlocked) }
        XCTAssertNil(store.value); XCTAssertEqual(t.requests.count, 1); XCTAssertTrue(c.safety?.sosAvailable == true)
    }
    func testStorageFailureStopsWriteAndClearFailureKeepsPending() async throws {
        let t = OrientTestTransport(); let store = OrientTestRecovery(); let box = try OrientTestIdentityBox(); let c = try make(t, store, box)
        store.failPrepare = true; t.append(orientTestSafety)
        do { try await c.prepare(key: "prepare-key-01"); XCTFail() } catch { XCTAssertEqual(error as? OrientSessionFlowError, .storageUnavailable) }
        XCTAssertEqual(t.requests.count, 1)
        store.failPrepare = false; store.failClear = true
        t.append(orientTestSafety); t.append(orientTestView(phase: "PREPARED")); t.append(orientTestView(phase: "PREPARED"))
        do { try await c.prepare(key: "prepare-key-01"); XCTFail() } catch { XCTAssertEqual(error as? OrientSessionFlowError, .storageUnavailable) }
        XCTAssertNotNil(store.value); XCTAssertNil(c.lastReceipt)
    }
    func testIdentitySwitchRejectsLateReplyAndKeepsOldOwnerPending() async throws {
        let t = OrientTestTransport(); let store = OrientTestRecovery(); let box = try OrientTestIdentityBox(); let c = try make(t, store, box)
        t.append(orientTestSafety); t.append(orientTestView(phase: "PREPARED"))
        t.beforeReply = { request in if request.url!.path.hasSuffix("/prepare") { box.value = nil } }
        do { try await c.prepare(key: "prepare-key-01"); XCTFail() } catch { XCTAssertEqual(error as? OrientSessionFlowError, .staleIdentity) }
        XCTAssertNil(c.view); XCTAssertEqual(store.value?.owner.accountID, 1)
        let other = try OrientTestIdentityBox(account: 2)
        XCTAssertThrowsError(try make(t, store, other))
    }
    func testTokenAndEpochChangeBeforeSendRejectsWithoutNetwork() async throws {
        let t = OrientTestTransport(); let store = OrientTestRecovery(); let box = try OrientTestIdentityBox(); let c = try make(t, store, box)
        box.value = try .init(owner: orientTestOwner(), epoch: 2, token: "new-synthetic-token")
        do { try await c.loadLobby(); XCTFail() } catch { XCTAssertEqual(error as? OrientSessionFlowError, .staleIdentity) }
        XCTAssertTrue(t.requests.isEmpty)
    }
    func testLeavingDuringReadCannotRepopulateOldPage() async throws {
        let t = OrientTestTransport(); let store = OrientTestRecovery(); let box = try OrientTestIdentityBox(); let c = try make(t, store, box)
        t.append(orientTestView()); t.beforeReply = { _ in c.leave() }
        do { try await c.resume(sessionID: 9); XCTFail() } catch { XCTAssertEqual(error as? OrientSessionFlowError, .staleIdentity) }
        XCTAssertNil(c.view); XCTAssertFalse(c.isVisible)
    }
    func testExplicitRetryReusesExactBodyAndKey() async throws {
        let t = OrientTestTransport(); let store = OrientTestRecovery(); let box = try OrientTestIdentityBox(); let c = try make(t, store, box)
        t.append(orientTestSafety); t.replies.append(.failure(URLError(.networkConnectionLost)))
        do { try await c.prepare(key: "stable-prepare-key"); XCTFail() } catch {}
        let originalRequest = t.requests.last!
        t.append(orientTestView(phase: "PREPARED")); t.append(orientTestView(phase: "PREPARED"))
        try await c.retryPending()
        XCTAssertEqual(t.requests[2].httpBody, originalRequest.httpBody); XCTAssertEqual(t.requests[2].url, originalRequest.url)
        XCTAssertNil(store.value)
    }
    func testExplicitPreconditionRejectClearsButConflictStaysUnknown() async throws {
        let t = OrientTestTransport(); let store = OrientTestRecovery(); let box = try OrientTestIdentityBox(); let c = try make(t, store, box)
        t.append(orientTestSafety); t.append("null", code: 409, err: "ORIENT_ACK_REQUIRED")
        do { try await c.prepare(key: "prepare-key-01"); XCTFail() } catch {}
        XCTAssertNil(store.value)
        t.append(orientTestSafety); t.append("null", code: 409, err: "ORIENT_IDEMPOTENCY_CONFLICT")
        do { try await c.prepare(key: "prepare-key-02"); XCTFail() } catch {}
        XCTAssertEqual(store.value?.key, "prepare-key-02")
    }
    func testFollowupReadRejectionDoesNotEraseAlreadyExecutedWrite() async throws {
        let t = OrientTestTransport(); let store = OrientTestRecovery(); let box = try OrientTestIdentityBox(); let c = try make(t, store, box)
        t.append(orientTestSafety); t.append(orientTestView(phase: "PREPARED")); t.append("null", code: 409, err: "ORIENT_SESSION_DISABLED")
        do { try await c.prepare(key: "prepare-key-01"); XCTFail() } catch {}
        XCTAssertNotNil(store.value)
    }
    func testAbandonIsConfirmedTerminalWriteAndResumeDoesNotRestartIt() async throws {
        let t = OrientTestTransport(); let store = OrientTestRecovery(); let box = try OrientTestIdentityBox(); let c = try make(t, store, box)
        t.append(orientTestView()); try await c.resume(sessionID: 9)
        do { try await c.abandon(confirmed: false, key: "abandon-key-01"); XCTFail() } catch { XCTAssertEqual(error as? OrientSessionFlowError, .confirmationRequired) }
        t.append(orientTestView(phase: "ABANDONED", status: 2)); t.append(orientTestView(phase: "ABANDONED", status: 2))
        try await c.abandon(confirmed: true, key: "abandon-key-01")
        c.leave(); t.append(orientTestView(phase: "ABANDONED", status: 2)); try await c.resume(sessionID: 9)
        do { try await c.start(acknowledgedConfigVersion: 7, key: "new-start-key"); XCTFail() } catch { XCTAssertEqual(error as? OrientSessionFlowError, .confirmationRequired) }
        XCTAssertEqual(c.view?.phase, .abandoned)
    }
    func testPhotoPendingDoesNotMarkRouteCompleteAndReplaysOriginalEvidence() async throws {
        let t = OrientTestTransport(); let store = OrientTestRecovery(); let box = try OrientTestIdentityBox(); let c = try make(t, store, box)
        t.append(orientTestView()); try await c.resume(sessionID: 9)
        t.append(orientTestSafety); t.replies.append(.failure(URLError(.timedOut)))
        do { try await c.submitAlternative(taskID: 12, evidence: .photo(picURL: "owned-photo"), key: "photo-key-01"); XCTFail() } catch {}
        let originalRequest = t.requests.last!
        do { try await c.recoverPending(); XCTFail() } catch { XCTAssertEqual(error as? OrientSessionFlowError, .receiptUnresolved) }
        t.append(orientTestAlternative()); t.append(orientTestView()); t.append("{\"taskId\":12,\"completed\":false,\"completedVia\":null,\"photoPendingReview\":true,\"alternatives\":[]}")
        try await c.retryPending()
        XCTAssertEqual(t.requests[t.requests.count - 3].httpBody, originalRequest.httpBody)
        XCTAssertFalse(c.taskState!.completed); XCTAssertEqual(c.view?.phase, .running); XCTAssertNil(store.value)
    }
    func testMatchingUnauthorizedCallbackDoesNotDeleteRecovery() async throws {
        let t = OrientTestTransport(); let store = OrientTestRecovery(); let box = try OrientTestIdentityBox(); var expirations = 0
        let c = try make(t, store, box, unauthorized: { _ in expirations += 1 })
        t.append(orientTestSafety); t.append("null", code: 401, err: "ORIENT_LOGIN_REQUIRED")
        do { try await c.prepare(key: "prepare-key-01"); XCTFail() } catch {}
        XCTAssertEqual(expirations, 1); XCTAssertNotNil(store.value)
    }
}

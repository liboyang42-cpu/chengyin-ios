import XCTest
@testable import Questify

@MainActor final class MerchantNPCRecoveryPresentationTests: XCTestCase {
    func testNoPendingRequestHasNoRecovery() {
        let h = Harness()
        XCTAssertNil(h.flow.retryRecovery())
        XCTAssertTrue(h.wire.requests.isEmpty)
    }
    func testServerDeadlineUsesCeilingAndDoesNotResetOrSend() async throws {
        let h = Harness(); h.wire.unknown = false; h.wire.delay = 60
        await h.flow.send("Original")
        let deadline = try XCTUnwrap(h.flow.retryAt)
        let id = h.flow.requestID
        XCTAssertEqual(h.flow.retryRecovery(at: deadline.addingTimeInterval(-1.01))?.state, .cooldown(seconds: 2))
        XCTAssertEqual(h.flow.retryRecovery(at: deadline.addingTimeInterval(-0.01))?.state, .cooldown(seconds: 1))
        XCTAssertEqual(h.flow.retryRecovery(at: deadline)?.state, .retryAvailable)
        XCTAssertEqual(h.flow.retryRecovery(at: deadline.addingTimeInterval(10))?.state, .retryAvailable)
        XCTAssertEqual(h.flow.retryAt, deadline); XCTAssertEqual(h.flow.requestID, id)
        XCTAssertEqual(h.wire.requests.count, 1)
    }
    func testClockRollbackIsBoundedWithoutMutatingAbsoluteDeadline() async throws {
        let h = Harness(); h.wire.unknown = false; h.wire.delay = 86_400
        await h.flow.send("Original"); let deadline = try XCTUnwrap(h.flow.retryAt)
        XCTAssertEqual(h.flow.retryRecovery(at: deadline.addingTimeInterval(-200_000))?.state, .cooldown(seconds: 86_400))
        XCTAssertEqual(h.flow.retryAt, deadline); XCTAssertEqual(h.wire.requests.count, 1)
    }
    func testUnknownOutcomeExplainsSameRequestWithoutSending() async throws {
        let h = Harness(); await h.flow.send("\u{00a0}Cafe\u{301} 🧭\n")
        let value = try XCTUnwrap(h.flow.retryRecovery())
        XCTAssertTrue(value.outcomeUnknown); XCTAssertEqual(value.state, .retryAvailable)
        XCTAssertTrue(value.canAbandon); XCTAssertEqual(value.attemptCount, 1)
        XCTAssertEqual(h.flow.message, "\u{00a0}Cafe\u{301} 🧭")
        XCTAssertEqual(h.wire.requests.count, 1)
    }
    func testExistingThreeAttemptCapAndOriginalBytesArePreserved() async throws {
        let h = Harness(); await h.flow.send("Original 🧭")
        let id = try XCTUnwrap(h.flow.requestID)
        await h.flow.retry(requestID: id); await h.flow.retry(requestID: id)
        let value = try XCTUnwrap(h.flow.retryRecovery())
        XCTAssertEqual(value.state, .attemptLimitReached); XCTAssertEqual(value.attemptCount, 3)
        XCTAssertFalse(h.flow.canRetry); XCTAssertEqual(h.flow.requestID, id)
        await h.flow.retry(requestID: id)
        XCTAssertEqual(h.wire.requests.count, 3)
        XCTAssertTrue(h.wire.requests.allSatisfy { $0.body == h.wire.requests[0].body })
    }
    func testNewAppearanceNeverRestartsDeadlineOrRetries() async throws {
        let h = Harness(); h.wire.unknown = false; h.wire.delay = 60
        await h.flow.send("Original"); let deadline = h.flow.retryAt
        var p = MerchantNPCRecoveryPresentation(); p.appear(active: true); p.disappear(); p.appear(active: true)
        XCTAssertEqual(h.flow.retryAt, deadline); XCTAssertEqual(h.wire.requests.count, 1)
    }
    func testScopeAndGrantLossHideRecoveryImmediately() async {
        let h = Harness(); await h.flow.send("Original")
        h.current = nil; XCTAssertNil(h.flow.retryRecovery())
        h.current = h.scope; h.grants.legal = false; XCTAssertNil(h.flow.retryRecovery())
        XCTAssertEqual(h.wire.requests.count, 1)
    }
    func testWaitingAndStoppingCannotBeAbandonedBeforeTransportSettles() async throws {
        let h = Harness(); h.wire.hold = true
        let task = Task { await h.flow.send("Original") }
        for _ in 0..<100 where h.wire.continuation == nil { await Task.yield() }
        guard h.wire.continuation != nil else { task.cancel(); XCTFail("Transport did not start"); return }
        XCTAssertEqual(h.flow.retryRecovery()?.state, .waitingForReply)
        XCTAssertFalse(h.flow.retryRecovery()?.canAbandon ?? true)
        h.flow.stopWaiting()
        XCTAssertEqual(h.flow.retryRecovery()?.state, .stoppingLocalWait)
        var p = MerchantNPCRecoveryPresentation(); p.appear(active: true)
        p.requestAbandon(h.flow.retryRecovery()!, coordinator: h.flow, revision: h.revision, sceneActive: true)
        XCTAssertNil(p.confirmation)
        h.wire.release(); _ = await task.value
        XCTAssertEqual(h.flow.retryRecovery()?.state, .retryAvailable)
        XCTAssertEqual(h.flow.failure, .unknownOutcome)
    }
    func testTerminalSuccessHasNoRecoveryPanel() async {
        let h = Harness(); h.wire.unknown = false; h.wire.success = true
        await h.flow.send("Original")
        XCTAssertNil(h.flow.retryRecovery()); XCTAssertNil(h.flow.requestID)
        XCTAssertEqual(h.flow.conversationHistory.turns.count, 1)
    }
    func testCancelChangesNeitherRequestNorDraftNorDispatchCount() async throws {
        let h = Harness(); await h.flow.send("Original")
        let id = h.flow.requestID; let body = h.wire.requests[0].body
        let draft = "Later edit 🧭"; var p = pending(h)
        XCTAssertNotNil(p.confirmation); p.cancel()
        XCTAssertNil(p.confirmation); XCTAssertEqual(h.flow.requestID, id)
        XCTAssertEqual(h.flow.message, "Original"); XCTAssertEqual(draft, "Later edit 🧭")
        XCTAssertEqual(h.wire.requests.count, 1); XCTAssertEqual(h.wire.requests[0].body, body)
    }
    func testConfirmedAbandonIsOneUseAndNeverSendsOrClearsComposer() async throws {
        let h = Harness(); await h.flow.send("Original")
        let draft = "Newer typed question"; var p = pending(h); let token = try XCTUnwrap(p.confirmation)
        XCTAssertTrue(p.confirm(token, coordinator: h.flow, revision: h.revision, sceneActive: true))
        XCTAssertNil(h.flow.requestID); XCTAssertTrue(h.flow.canSend)
        XCTAssertFalse(p.confirm(token, coordinator: h.flow, revision: h.revision, sceneActive: true))
        XCTAssertEqual(draft, "Newer typed question"); XCTAssertEqual(h.wire.requests.count, 1)
    }
    func testOldConfirmationCannotAbandonNewRequest() async throws {
        let h = Harness(); await h.flow.send("First"); var p = pending(h); let token = try XCTUnwrap(p.confirmation)
        h.flow.abandon(); await h.flow.send("Second"); let newerID = h.flow.requestID
        XCTAssertFalse(p.confirm(token, coordinator: h.flow, revision: h.revision, sceneActive: true))
        XCTAssertEqual(h.flow.requestID, newerID); XCTAssertEqual(h.flow.message, "Second")
        XCTAssertEqual(h.wire.requests.count, 2)
    }
    func testSameRequestNewAttemptInvalidatesConfirmationEvenWithOldViewRevision() async throws {
        let h = Harness(); await h.flow.send("Original"); var p = pending(h); let token = try XCTUnwrap(p.confirmation)
        let oldRevision = h.revision; await h.flow.retry()
        XCTAssertFalse(p.confirm(token, coordinator: h.flow, revision: oldRevision, sceneActive: true))
        XCTAssertNotNil(h.flow.requestID); XCTAssertEqual(h.wire.requests.count, 2)
    }
    func testNewModelRevisionRejectsConfirmationBeforeRender() async throws {
        let h = Harness(); await h.flow.send("Original"); var p = pending(h); let token = try XCTUnwrap(p.confirmation)
        h.revision += 1
        XCTAssertFalse(p.confirm(token, coordinator: h.flow, revision: h.revision, sceneActive: true))
        XCTAssertNotNil(h.flow.requestID); XCTAssertEqual(h.wire.requests.count, 1)
    }
    func testStaleAbandonTapCannotOpenConfirmationForNewerRequest() async throws {
        let h = Harness(); await h.flow.send("First")
        let old = try XCTUnwrap(h.flow.retryRecovery())
        h.flow.abandon(); await h.flow.send("Second")
        var p = MerchantNPCRecoveryPresentation(); p.appear(active: true)
        p.requestAbandon(old, coordinator: h.flow, revision: h.revision, sceneActive: true)
        XCTAssertNil(p.confirmation); XCTAssertEqual(h.flow.message, "Second")
    }
    func testStaleAbandonTapCannotAdoptLaterAttemptOfSameRequest() async throws {
        let h = Harness(); await h.flow.send("Original")
        let old = try XCTUnwrap(h.flow.retryRecovery()); await h.flow.retry()
        var p = MerchantNPCRecoveryPresentation(); p.appear(active: true)
        p.requestAbandon(old, coordinator: h.flow, revision: h.revision, sceneActive: true)
        XCTAssertNil(p.confirmation); XCTAssertEqual(h.flow.requestID, old.requestID)
    }
    func testAnotherCoordinatorWithSameScopeCannotConsumeConfirmation() async throws {
        let h = Harness(); await h.flow.send("Original"); var p = pending(h); let token = try XCTUnwrap(p.confirmation)
        let other = MerchantNPCChatCoordinator(scope: h.scope, client: .init(transport: h.wire), currentScope: { h.scope }, grants: { h.grants })
        await other.send("Other")
        XCTAssertFalse(p.confirm(token, coordinator: other, revision: h.revision, sceneActive: true))
        XCTAssertNotNil(other.requestID); XCTAssertNotNil(h.flow.requestID)
    }
    func testInactiveSceneBlocksConfirmationBeforeLifecycleCallback() async throws {
        let h = Harness(); await h.flow.send("Original"); var p = pending(h); let token = try XCTUnwrap(p.confirmation)
        XCTAssertFalse(p.confirm(token, coordinator: h.flow, revision: h.revision, sceneActive: false))
        XCTAssertNotNil(h.flow.requestID)
    }
    func testBackgroundThenReturnRetiresOldConfirmationWithoutSend() async throws {
        let h = Harness(); await h.flow.send("Original"); var p = pending(h); let token = try XCTUnwrap(p.confirmation)
        p.sceneChanged(active: false); p.sceneChanged(active: true)
        XCTAssertFalse(p.confirm(token, coordinator: h.flow, revision: h.revision, sceneActive: true))
        XCTAssertNotNil(h.flow.requestID); XCTAssertEqual(h.wire.requests.count, 1)
    }
    func testDisappearReappearDoesNotReuseOldConfirmation() async throws {
        let h = Harness(); await h.flow.send("Original"); var p = pending(h); let token = try XCTUnwrap(p.confirmation)
        p.disappear(); p.appear(active: true)
        p.requestAbandon(h.flow.retryRecovery()!, coordinator: h.flow, revision: h.revision, sceneActive: true)
        XCTAssertNotEqual(p.confirmation?.id, token.id)
        XCTAssertFalse(p.confirm(token, coordinator: h.flow, revision: h.revision, sceneActive: true))
        XCTAssertNotNil(h.flow.requestID)
    }
    func testRevokedGrantAndOwnerRejectPendingConfirmation() async throws {
        let h = Harness(); await h.flow.send("Original"); var p = pending(h); let token = try XCTUnwrap(p.confirmation)
        h.grants.server = false
        XCTAssertFalse(p.confirm(token, coordinator: h.flow, revision: h.revision, sceneActive: true))
        h.grants.server = true; h.current = nil
        XCTAssertFalse(p.confirm(token, coordinator: h.flow, revision: h.revision, sceneActive: true))
        XCTAssertNotNil(h.flow.requestID); XCTAssertEqual(h.wire.requests.count, 1)
    }
    func testAbandonPreservesEarlierVerifiedTranscript() async throws {
        let h = Harness(); h.wire.unknown = false; h.wire.success = true
        await h.flow.send("Completed"); let history = h.flow.conversationHistory
        h.wire.unknown = true; await h.flow.send("Uncertain")
        var p = pending(h); let token = try XCTUnwrap(p.confirmation)
        XCTAssertTrue(p.confirm(token, coordinator: h.flow, revision: h.revision, sceneActive: true))
        XCTAssertEqual(h.flow.conversationHistory, history); XCTAssertEqual(h.wire.requests.count, 2)
    }
    func testHiddenOrInactivePresentationCannotPrepareConfirmation() async {
        let h = Harness(); await h.flow.send("Original")
        var p = MerchantNPCRecoveryPresentation()
        p.requestAbandon(h.flow.retryRecovery()!, coordinator: h.flow, revision: h.revision, sceneActive: true); XCTAssertNil(p.confirmation)
        p.appear(active: false)
        p.requestAbandon(h.flow.retryRecovery()!, coordinator: h.flow, revision: h.revision, sceneActive: true); XCTAssertNil(p.confirmation)
        p.appear(active: true)
        p.requestAbandon(h.flow.retryRecovery()!, coordinator: h.flow, revision: h.revision, sceneActive: false); XCTAssertNil(p.confirmation)
        XCTAssertEqual(h.wire.requests.count, 1)
    }
    private func pending(_ h: Harness) -> MerchantNPCRecoveryPresentation {
        var p = MerchantNPCRecoveryPresentation(); p.appear(active: true)
        p.requestAbandon(h.flow.retryRecovery()!, coordinator: h.flow, revision: h.revision, sceneActive: true)
        return p
    }
    @MainActor private final class Harness {
        let scope = MerchantNPCScope(accountID: 7, namespace: "synthetic", epoch: UUID(), merchantRowID: PublicMerchantRowID(9)!, accessRevision: UUID())
        var current: MerchantNPCScope?
        var grants = MerchantNPCGrants()
        var revision = 0
        let wire = Wire()
        lazy var flow: MerchantNPCChatCoordinator = {
            let value = MerchantNPCChatCoordinator(scope: scope, client: .init(transport: wire), currentScope: { [weak self] in self?.current }, grants: { [weak self] in self?.grants ?? .init() })
            value.onChange = { [weak self] in self?.revision += 1 }
            return value
        }()
        init() { current = scope; grants.server = true; grants.provider = true; grants.legal = true }
    }
    @MainActor private final class Wire: MerchantNPCHTTPTransport {
        var requests: [MerchantNPCHTTPRequest] = []
        var unknown = true, success = false, hold = false
        var delay = 0
        var continuation: CheckedContinuation<Void, Never>?
        func release() { let value = continuation; continuation = nil; value?.resume() }
        func perform(_ request: MerchantNPCHTTPRequest) async throws -> MerchantNPCHTTPResponse {
            requests.append(request)
            if hold { await withCheckedContinuation { continuation = $0 } }
            if unknown { throw MerchantNPCFailure.unknownOutcome }
            let sent = try XCTUnwrap(JSONSerialization.jsonObject(with: request.body) as? [String: Any])
            let id = try XCTUnwrap(sent["requestId"] as? String)
            return .init(status: 200, body: try JSONSerialization.data(withJSONObject: ["code": 200, "data": [
                "requestId": id, "outcomeStatus": success ? "SUCCEEDED" : "PROCESSING", "safetyDecision": success ? "PASS" : "NOT_RUN",
                "retryable": !success, "retryAfterSeconds": delay, "safeText": success ? "Safe reply" : "Still processing"
            ]]))
        }
    }
}

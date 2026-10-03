import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

@MainActor final class PlayRecoveryDispatchTests: XCTestCase {
    private func session(epoch: UInt64 = 1, token: String = "synthetic-token") throws -> PlayExperienceSession {
        try .init(accountID: 9001, epoch: epoch, namespace: "synthetic-cn", token: token)
    }
    private func service(_ transport: any HTTPTransport, enabled: Set<PlayExperienceCapability> = [.reads, .classicCompletion, .runPersistence]) throws -> PlayExperienceService {
        .init(configuration: try .init(baseURL: URL(string: "https://example.com/")!), transport: transport, enabled: enabled)
    }
    private func recorder(branch: Bool = false) -> PlayRecoveryRecordingTransport {
        let r = PlayRecoveryRecordingTransport()
        r.responses["/api/play/nodes"] = .reply(PlayExperienceSyntheticFixtures.envelope(branch ? PlayExperienceSyntheticFixtures.branch : PlayExperienceSyntheticFixtures.classic), 200)
        r.responses["/api/play/route-state"] = .reply(PlayExperienceSyntheticFixtures.envelope(PlayExperienceSyntheticFixtures.route), 200)
        r.responses["/api/play/answer"] = .failure(.unknownResult)
        r.responses["/api/play/run-session"] = .reply(PlayExperienceSyntheticFixtures.envelope("null"), 200)
        r.responses["/api/play/run-session/save"] = .failure(.unknownResult)
        r.responses["/api/play/run-session/clear"] = .failure(.unknownResult)
        return r
    }
    private func coordinator(_ transport: any HTTPTransport, recovery: any PlayCompletionRecoveryStore,
                             paused: (any PlayPausedStorage)? = nil, current: @escaping () -> PlayExperienceSession?) throws -> PlayExperienceCoordinator {
        .init(scope: .activity(41), service: try service(transport), recovery: recovery, pausedStorage: paused ?? PlayMemoryPausedStorage(), currentSession: current)
    }
    func testRawPayloadAndForgedCapabilityCannotReachArbitraryTransport() async throws {
        let transport = NetworkShapedSpy(), api = try service(transport)
        let operations: [() async throws -> Void] = [
            { _ = try await api.complete(scope: .activity(41), nodeID: 701, evidence: .answer("private"), advance: nil, token: "synthetic") },
            { try await api.savePaused(scope: .activity(41), record: .init(elapsedSeconds: 1, savedAt: 10), token: "synthetic") },
            { try await api.clearPaused(scope: .activity(41), savedAt: 10, token: "synthetic") },
            { _ = try await api.request("api/play/answer", query: ["synthetic": "1"], form: ["nodeId": "701"], capability: .reads, token: "synthetic") }
        ]
        for operation in operations {
            do { try await operation(); XCTFail("Raw production write bypass") }
            catch { XCTAssertEqual(error as? PlayExperienceError, .persistenceUnavailable) }
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }
    func testRouteAliasesCannotBypassProtectedRouteGate() async throws {
        let transport = NetworkShapedSpy(), api = try service(transport)
        for path in ["api/play/./answer", "api/play//answer", "api/play/answer/", "api/play/answer;x=1", "api/play/%61nswer", "api/play/../play/answer", "api/play\\answer"] {
            do { _ = try await api.request(path, form: ["nodeId": "701"], capability: .reads, token: "synthetic"); XCTFail(path) } catch {}
        }
        XCTAssertTrue(transport.requests.isEmpty)
    }
    func testInjectedMemoryAndEncryptedProtocolStoresCannotAuthorizeNetworkTransport() async throws {
        let current = try session(), a = PlayDurableRecoveryTests.Anchors(), b = PlayDurableRecoveryTests.Blobs()
        let durable = try PlayDurableRecovery(owner: .init(session: current), key: PlayRunStorageKey.make(session: current, scope: .activity(41)), anchors: a, ciphertexts: b)
        XCTAssertFalse(durable.isSystemBacked)
        let stores: [any PlayCompletionRecoveryStore] = [PlayMemoryCompletionRecovery(), durable]
        for recovery in stores {
            let transport = NetworkShapedSpy(), model = try coordinator(transport, recovery: recovery, current: { current })
            await model.load(); await model.submit(try model.review(nodeID: 701, evidence: .answer("synthetic")))
            XCTAssertEqual(model.issue, .persistenceUnavailable); XCTAssertTrue(model.unresolved)
            XCTAssertTrue(transport.requests.allSatisfy { $0.httpMethod == "GET" })
        }
    }
    func testUnknownRetryNeedsReadbackAndRejectedRetryKeepsOriginalPayload() async throws {
        let current = try session(), transport = recorder(branch: true), recovery = PlayMemoryCompletionRecovery()
        let model = try coordinator(transport, recovery: recovery, current: { current })
        await model.load(); await model.submit(try model.review(nodeID: 701, evidence: .answer("exact e\u{301}")))
        XCTAssertFalse(model.canRetryExactBranch); await model.load(); XCTAssertTrue(model.canRetryExactBranch)
        transport.responses["/api/play/answer"] = .reply(Data(#"{"code":409,"msg":"synthetic conflict","data":null}"#.utf8), 200)
        await model.retryExactBranchAfterReadback()
        XCTAssertTrue(model.unresolved); XCTAssertFalse(model.canWrite)
        let writes = transport.requests.filter { $0.httpMethod == "POST" }
        XCTAssertEqual(writes.count, 2); XCTAssertEqual(writes.first?.httpBody, writes.last?.httpBody)
        let pending = try await recovery.read(PlayRunStorageKey.make(session: current, scope: .activity(41)))
        XCTAssertEqual(pending?.value.state, .unknown); XCTAssertEqual(pending?.value.intent.evidence, .answer("exact e\u{301}"))
    }
    func testFirstAttemptBusinessErrorsCannotProveNoCommit() async throws {
        for code in [400, 403, 409, 500] {
            let current = try session(), transport = recorder(), recovery = PlayMemoryCompletionRecovery()
            transport.responses["/api/play/answer"] = .reply(Data("{\"code\":\(code),\"data\":null}".utf8), 200)
            let model = try coordinator(transport, recovery: recovery, current: { current })
            await model.load(); await model.submit(try model.review(nodeID: 701, evidence: .answer("synthetic")))
            XCTAssertTrue(model.unresolved); let pending = try await recovery.read(PlayRunStorageKey.make(session: current, scope: .activity(41)))
            XCTAssertEqual(pending?.value.state, .unknown)
        }
    }
    func testFreshProcessEncryptedReplayUsesFreshTokenButExactBodyAndOriginalEpoch() async throws {
        let a = PlayDurableRecoveryTests.Anchors(), b = PlayDurableRecoveryTests.Blobs(), old = try session(), key = PlayRunStorageKey.make(session: old, scope: .activity(41))
        let first = try PlayDurableRecovery(owner: .init(session: old), key: key, anchors: a, ciphertexts: b, processID: UUID()), transport = recorder(branch: true)
        let model = try coordinator(transport, recovery: first, current: { old })
        await model.load(); await model.submit(try model.review(nodeID: 701, evidence: .answer("original payload")))
        let fresh = try session(epoch: 2, token: "synthetic-refreshed-token")
        let reopened = try PlayDurableRecovery(owner: .init(session: fresh), key: key, anchors: a, ciphertexts: b, processID: UUID())
        let newModel = try coordinator(transport, recovery: reopened, current: { fresh })
        await newModel.load(); XCTAssertTrue(newModel.canRetryExactBranch); await newModel.retryExactBranchAfterReadback()
        let writes = transport.requests.filter { $0.httpMethod == "POST" }
        XCTAssertEqual(writes.count, 2); XCTAssertEqual(writes.first?.httpBody, writes.last?.httpBody)
        XCTAssertEqual(writes.last?.value(forHTTPHeaderField: "Authorization"), fresh.token)
        let pending = try await reopened.read(key); XCTAssertEqual(pending?.value.intent.originEpoch, 1)
    }
    func testInvalidationCancelsOwnedTransportAndRetainsPendingAcrossFreshSession() async throws {
        var current: PlayExperienceSession? = try session()
        let captured = try XCTUnwrap(current), transport = recorder(), recovery = PlayMemoryCompletionRecovery()
        let model = try coordinator(transport, recovery: recovery, current: { current })
        await model.load(); let review = try model.review(nodeID: 701, evidence: .answer("synthetic"))
        transport.pauseResponse = true; let submission = Task { await model.submit(review) }
        for _ in 0..<1_000 { if transport.isAwaitingResponse { break }; await Task.yield() }
        XCTAssertTrue(transport.isAwaitingResponse)
        current = try session(epoch: 2); model.invalidate(); transport.resumeResponse(); await submission.value
        XCTAssertTrue(transport.observedCancellation); XCTAssertNil(model.reward)
        let pending = try await recovery.read(PlayRunStorageKey.make(session: captured, scope: .activity(41)))
        XCTAssertEqual(pending?.value.state, .dispatching); await model.load(); XCTAssertTrue(model.unresolved)
    }
    func testPrepareSuspensionThenABAOrCancellationNeverDispatches() async throws {
        for cancel in [false, true] {
            let current = try session(), transport = recorder(), storage = SuspendingRecovery()
            let model = try coordinator(transport, recovery: storage, current: { current })
            await model.load(); let review = try model.review(nodeID: 701, evidence: .answer("synthetic"))
            storage.pausePrepare = true; let submission = Task { await model.submit(review) }
            for _ in 0..<1_000 { if storage.waiting != nil { break }; await Task.yield() }
            XCTAssertNotNil(storage.waiting)
            if cancel { submission.cancel() } else { model.invalidate() }
            storage.resume(); await submission.value
            XCTAssertTrue(transport.requests.allSatisfy { $0.httpMethod == "GET" })
            let pending = try await storage.read(PlayRunStorageKey.make(session: current, scope: .activity(41))); XCTAssertNotNil(pending)
        }
    }
    func testFinalReadRetirementCancellationAndRepeatedTapNeverDispatch() async throws {
        for cancel in [false, true] {
            let current = try session(), transport = recorder(), storage = SuspendingRecovery()
            let model = try coordinator(transport, recovery: storage, current: { current })
            await model.load(); let review = try model.review(nodeID: 701, evidence: .answer("synthetic"))
            storage.pauseRead = true; let submission = Task { await model.submit(review) }
            for _ in 0..<1_000 { if storage.waiting != nil { break }; await Task.yield() }
            XCTAssertNotNil(storage.waiting); await model.submit(review)
            if cancel { submission.cancel() } else { model.invalidate() }
            storage.resume(); await submission.value
            XCTAssertTrue(transport.requests.allSatisfy { $0.httpMethod == "GET" })
        }
    }
    func testFinalReadReplacementRejectsDispatchEvenWithAnUnchangedSession() async throws {
        let current = try session(), transport = recorder(), storage = SuspendingRecovery()
        let model = try coordinator(transport, recovery: storage, current: { current })
        await model.load(); let review = try model.review(nodeID: 701, evidence: .answer("synthetic"))
        storage.replaceAfterRead = true
        await model.submit(review)
        XCTAssertEqual(model.issue, .persistenceUnavailable); XCTAssertTrue(model.unresolved)
        XCTAssertTrue(transport.requests.allSatisfy { $0.httpMethod == "GET" })
        let pending = try await storage.read(PlayRunStorageKey.make(session: current, scope: .activity(41)))
        XCTAssertEqual(pending?.value.state, .unknown)
    }
    func testFinalReadRechecksLiveSelectorWithoutAnExplicitHostInvalidation() async throws {
        var current: PlayExperienceSession? = try session()
        let original = try XCTUnwrap(current), transport = recorder(), storage = SuspendingRecovery()
        let model = try coordinator(transport, recovery: storage, current: { current })
        await model.load(); let review = try model.review(nodeID: 701, evidence: .answer("synthetic"))
        storage.pauseRead = true; let submission = Task { await model.submit(review) }
        for _ in 0..<1_000 { if storage.waiting != nil { break }; await Task.yield() }
        XCTAssertNotNil(storage.waiting); current = try session(epoch: 2, token: "synthetic-new-token")
        storage.resume(); await submission.value
        XCTAssertTrue(transport.requests.allSatisfy { $0.httpMethod == "GET" }); XCTAssertNil(model.snapshot)
        let pending = try await storage.read(PlayRunStorageKey.make(session: original, scope: .activity(41)))
        XCTAssertEqual(pending?.value.state, .dispatching)
    }
    func testPausedUnknownBlocksNewOperationsUntilExactAuthoritativeReadback() async throws {
        let current = try session(), transport = recorder(), paused = PlayMemoryPausedStorage()
        let model = try coordinator(transport, recovery: PlayMemoryCompletionRecovery(), paused: paused, current: { current })
        await model.load(); await model.restoreRun(); model.startRun(now: 0); await model.pauseRun(now: 12, savedAt: 100)
        XCTAssertTrue(model.remoteRunSaveFailed); XCTAssertFalse(model.canManageRun)
        await model.restoreRun(); model.startRun(now: 20); await model.endRun(now: 30, savedAt: 200)
        XCTAssertEqual(transport.requests.filter { $0.httpMethod == "POST" }.count, 1)
        transport.responses["/api/play/run-session"] = .reply(PlayExperienceSyntheticFixtures.envelope(#"{"runState":"PAUSED","savedAt":100,"elapsedSeconds":12}"#), 200)
        await model.restoreRun(); XCTAssertTrue(model.canManageRun); XCTAssertFalse(model.remoteRunSaveFailed)
        let stored = try await paused.read(key: PlayRunStorageKey.make(session: current, scope: .activity(41)))
        XCTAssertEqual(stored.value?.pendingRemote, false)
    }
    func testStalePausedViewerCannotOverwriteNewPendingGeneration() async throws {
        let current = try session(), transport = recorder(), paused = PlayMemoryPausedStorage()
        let one = try coordinator(transport, recovery: PlayMemoryCompletionRecovery(), paused: paused, current: { current })
        let two = try coordinator(transport, recovery: PlayMemoryCompletionRecovery(), paused: paused, current: { current })
        await one.load(); await two.load(); await one.restoreRun(); await two.restoreRun()
        one.startRun(now: 0); two.startRun(now: 0); await one.pauseRun(now: 12, savedAt: 100); await two.pauseRun(now: 20, savedAt: 200)
        XCTAssertTrue(two.localRecoveryFailed); XCTAssertEqual(transport.requests.filter { $0.httpMethod == "POST" }.count, 1)
        let stored = try await paused.read(key: PlayRunStorageKey.make(session: current, scope: .activity(41))); XCTAssertEqual(stored.value?.record?.savedAt, 100)
    }
    func testReadOnlyRestoreDoesNotTouchPausedStorageOrDispatch() async throws {
        let current = try session(), transport = recorder(), paused = CountingPaused()
        let model = PlayExperienceCoordinator(scope: .activity(41), service: try service(transport, enabled: [.reads]), recovery: PlayMemoryCompletionRecovery(), pausedStorage: paused, currentSession: { current })
        await model.load(); await model.restoreRun(); model.startRun(now: 0); await model.pauseRun(now: 1, savedAt: 10); await model.endRun(now: 2, savedAt: 20)
        XCTAssertFalse(model.canManageRun); XCTAssertFalse(model.canWrite); XCTAssertEqual(paused.reads, 0); XCTAssertEqual(paused.writes, 0)
    }
    func testPausedStorageFailureDoesNotDispatchOrRecreateEmptyRun() async throws {
        let current = try session(), transport = recorder(), a = PlayDurableRecoveryTests.Anchors(), b = PlayDurableRecoveryTests.Blobs()
        let durable = try PlayDurableRecovery(owner: .init(session: current), key: PlayRunStorageKey.make(session: current, scope: .activity(41)), anchors: a, ciphertexts: b)
        await a.configure(locked: true)
        let model = try coordinator(transport, recovery: PlayMemoryCompletionRecovery(), paused: durable, current: { current })
        await model.load(); await model.restoreRun(); model.startRun(now: 0); await model.pauseRun(now: 1, savedAt: 10)
        XCTAssertTrue(model.localRecoveryFailed); XCTAssertFalse(model.canManageRun); XCTAssertTrue(transport.requests.allSatisfy { $0.httpMethod == "GET" })
    }
    func testRunCancellationRetainsRemotePending() async throws {
        let current = try session(), transport = recorder(), paused = PlayMemoryPausedStorage()
        let model = try coordinator(transport, recovery: PlayMemoryCompletionRecovery(), paused: paused, current: { current })
        await model.load(); await model.restoreRun(); model.startRun(now: 0); transport.pauseResponse = true
        let save = Task { await model.pauseRun(now: 12, savedAt: 100) }
        for _ in 0..<1_000 { if transport.isAwaitingResponse { break }; await Task.yield() }
        XCTAssertTrue(transport.isAwaitingResponse); model.invalidate(); transport.resumeResponse(); await save.value
        XCTAssertTrue(transport.observedCancellation)
        let pending = try await paused.read(key: PlayRunStorageKey.make(session: current, scope: .activity(41))); XCTAssertEqual(pending.value?.pendingRemote, true)
    }
    func testCurrentRun401RevokesButLateCompletion401CannotRevokeReplacement() async throws {
        var current: PlayExperienceSession? = try session(); let transport = recorder(), paused = PlayMemoryPausedStorage(); var revoked = 0
        let model = PlayExperienceCoordinator(scope: .activity(41), service: try service(transport), recovery: PlayMemoryCompletionRecovery(), pausedStorage: paused, currentSession: { current }, onUnauthorized: { _ in revoked += 1 })
        await model.load(); await model.restoreRun(); model.startRun(now: 0)
        transport.responses["/api/play/run-session/save"] = .reply(Data(#"{"code":401}"#.utf8), 200)
        await model.pauseRun(now: 12, savedAt: 100); XCTAssertEqual(revoked, 1); XCTAssertNil(model.snapshot)
        let second = PlayExperienceCoordinator(scope: .activity(41), service: try service(transport), recovery: PlayMemoryCompletionRecovery(), pausedStorage: PlayMemoryPausedStorage(), currentSession: { current }, onUnauthorized: { _ in revoked += 1 })
        await second.load(); let review = try second.review(nodeID: 701, evidence: .answer("synthetic"))
        transport.responses["/api/play/answer"] = .reply(Data(#"{"code":401}"#.utf8), 200); transport.pauseResponse = true
        let submission = Task { await second.submit(review) }
        for _ in 0..<1_000 { if transport.isAwaitingResponse { break }; await Task.yield() }
        current = try session(epoch: 2); second.invalidate(); transport.resumeResponse(); await submission.value
        XCTAssertEqual(revoked, 1); XCTAssertNil(second.reward)
        let third = PlayExperienceCoordinator(scope: .activity(41), service: try service(transport), recovery: PlayMemoryCompletionRecovery(), pausedStorage: PlayMemoryPausedStorage(), currentSession: { current }, onUnauthorized: { _ in revoked += 1 })
        await third.load(); await third.submit(try third.review(nodeID: 701, evidence: .answer("synthetic-current")))
        XCTAssertEqual(revoked, 2); XCTAssertNil(third.snapshot)
    }
    func testEndingRemainsGETWithScopedQuery() async throws {
        let r = recorder(); r.responses["/api/play/ending"] = .reply(PlayExperienceSyntheticFixtures.envelope(#"{"opener":"","fragments":[]}"#), 200)
        _ = try await service(r).ending(scope: .activity(41), token: "synthetic")
        let request = try XCTUnwrap(r.requests.last); XCTAssertEqual(request.httpMethod, "GET"); XCTAssertNil(request.httpBody); XCTAssertTrue(request.url!.absoluteString.contains("activityId=41"))
    }
    func testByteDistinctRealmAndRoleCannotCompareEqual() throws {
        let one = try PlayExperienceSession(accountID: 1, epoch: 1, namespace: "é", token: "synthetic", role: "é")
        let realm = try PlayExperienceSession(accountID: 1, epoch: 1, namespace: "e\u{301}", token: "synthetic", role: "é")
        let role = try PlayExperienceSession(accountID: 1, epoch: 1, namespace: "é", token: "synthetic", role: "e\u{301}")
        XCTAssertNotEqual(one, realm); XCTAssertNotEqual(one, role)
    }
}
@MainActor private final class NetworkShapedSpy: HTTPTransport {
    var requests: [URLRequest] = []
    func send(_ request: URLRequest) async throws -> (Data, Int) { requests.append(request); return (PlayExperienceSyntheticFixtures.envelope(PlayExperienceSyntheticFixtures.classic), 200) }
}
@MainActor private final class SuspendingRecovery: PlayCompletionRecoveryStore {
    let backing = PlayMemoryCompletionRecovery()
    var processID: UUID { backing.processID }
    var waiting: CheckedContinuation<Void, Never>?
    var pausePrepare = false, pauseRead = false, replaceAfterRead = false
    func resume() { let old = waiting; waiting = nil; old?.resume() }
    func read(_ key: String) async throws -> PlayCompletionRecoverySnapshot? {
        let result = try await backing.read(key)
        if pauseRead { pauseRead = false; await withCheckedContinuation { waiting = $0 } }
        if replaceAfterRead, let result { replaceAfterRead = false; return try await backing.transition(result, to: .unknown, key: key) }
        return result
    }
    func prepare(_ intent: PlayCompletionIntent, key: String) async throws -> PlayCompletionRecoverySnapshot {
        let result = try await backing.prepare(intent, key: key)
        if pausePrepare { pausePrepare = false; await withCheckedContinuation { waiting = $0 } }; return result
    }
    func transition(_ snapshot: PlayCompletionRecoverySnapshot, to state: PlayPendingCompletion.State, key: String) async throws -> PlayCompletionRecoverySnapshot { try await backing.transition(snapshot, to: state, key: key) }
    func clear(_ snapshot: PlayCompletionRecoverySnapshot, key: String) async throws { try await backing.clear(snapshot, key: key) }
}
@MainActor private final class CountingPaused: PlayPausedStorage {
    var reads = 0, writes = 0
    func read(key: String) async throws -> PlayPausedStorageSnapshot { reads += 1; return .init(value: nil, generation: nil) }
    func write(_ value: PlayPausedSnapshot, replacing snapshot: PlayPausedStorageSnapshot, key: String) async throws -> PlayPausedStorageSnapshot { writes += 1; return .init(value: value, generation: Data([1])) }
}

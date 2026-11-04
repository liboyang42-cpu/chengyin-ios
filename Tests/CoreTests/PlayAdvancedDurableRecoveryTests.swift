import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Synthetic encrypted-store and byte-scripted HTTP tests. No real account,
/// Keychain, filesystem, game server, camera, purchase or production dispatch.
@available(macOS 14.0, *)
@MainActor final class PlayAdvancedDurableRecoveryTests: XCTestCase {
    typealias Anchors = ContentDraftDurableJournalTests.Anchors
    typealias Blobs = ContentDraftDurableJournalTests.Blobs
    private let start = "/api/play/advanced/start", action = "/api/play/advanced/action", state = "/api/play/advanced/state"
    private func owner(account: Int = 7, epoch: UInt64 = 1, namespace: String = "synthetic-advanced", role: String = "player") throws -> PlayExperienceSession {
        try .init(accountID: account, epoch: epoch, namespace: namespace, token: "SYNTHETIC-DO-NOT-PERSIST", role: role)
    }
    private func scope(node: Int = 701) throws -> PlayAdvancedRecoveryScope { try .init(activityID: 41, topicID: 71, nodeID: node) }
    private func journal(_ a: Anchors, _ b: Blobs, owner: PlayExperienceSession? = nil, process: UUID = UUID(), node: Int = 701) throws -> PlayAdvancedDurableRecovery {
        try .init(owner: .init(session: owner ?? self.owner()), scope: scope(node: node), anchors: a, ciphertexts: b, processID: process)
    }
    private func reply(_ version: Int = 2, session: Int = 601) -> Data {
        PlayExperienceSyntheticFixtures.envelope(PlayExperienceSyntheticFixtures.advanced
            .replacingOccurrences(of: "\"version\":2", with: "\"version\":\(version)")
            .replacingOccurrences(of: "\"sessionId\":601", with: "\"sessionId\":\(session)"))
    }
    private func wire() -> PlayRecoveryRecordingTransport {
        let wire = PlayRecoveryRecordingTransport()
        wire.responses[start] = .reply(reply(), 200); wire.responses[action] = .failure(.unknownResult)
        wire.responses[state] = .reply(reply(3), 200); return wire
    }
    private func model(_ wire: PlayRecoveryRecordingTransport, _ journal: any PlayAdvancedRecovery, current: @escaping () -> PlayExperienceSession?) throws -> PlayAdvancedCoordinator {
        .init(activityID: 41, topicID: 71, nodeID: 701,
              service: .init(configuration: try .init(baseURL: URL(string: "https://example.test")!), transport: wire, enabled: [.reads, .advanced]),
              recovery: journal, currentSession: current)
    }
    private func original() -> PlayAdvancedPending {
        .init(sessionID: 601, version: 2, key: UUID().uuidString, action: "FLIP_COIN", payload: [:])
    }
    private func record(_ pending: PlayAdvancedPending? = nil, session: PlayExperienceSession? = nil) throws -> PlayAdvancedRecoveryRecord {
        try .init(session: session ?? owner(), scope: scope(), pending: pending ?? original(), requestedCard: false)
    }
    private func fail(_ operation: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line) async {
        do { try await operation(); XCTFail("Expected fail-closed persistence", file: file, line: line) }
        catch { XCTAssertEqual(error as? PlayExperienceError, .persistenceUnavailable, file: file, line: line) }
    }
    private func unknown(_ model: PlayAdvancedCoordinator) async throws -> PlayAdvancedPending {
        await model.submit(kind: "coinFlip", action: "FLIP_COIN")
        XCTAssertEqual(model.phase, "unknown"); return try XCTUnwrap(model.pending)
    }

    func testNormalEntryPersistsBeforeActionAndRestartReplaysOnlyExactOriginal() async throws {
        let a = Anchors(), b = Blobs(), s = try owner(), firstStore = try journal(a, b), firstWire = wire()
        let first = try model(firstWire, firstStore, current: { s }); await first.start()
        XCTAssertEqual(first.phase, "ready")
        let pending = try await unknown(first), bytes = try XCTUnwrap(firstWire.requests.last?.httpBody)
        let persisted = try await firstStore.read(); XCTAssertEqual(persisted?.value.pending, pending)
        XCTAssertEqual(persisted?.value.phase, .unknown)
        let refreshed = try owner(epoch: 2), freshStore = try journal(a, b, owner: refreshed), freshWire = wire()
        let fresh = try model(freshWire, freshStore, current: { refreshed }); await fresh.start()
        XCTAssertEqual(fresh.phase, "retryable"); XCTAssertEqual(fresh.pending, pending)
        XCTAssertEqual(freshWire.requests.map { $0.url?.path }, [state])
        XCTAssertFalse(fresh.canInteract); XCTAssertThrowsError(try fresh.review(kind: "coinFlip", action: "FLIP_COIN"))
        freshWire.responses[action] = .reply(reply(3), 200); await fresh.retryExact()
        XCTAssertNil(fresh.pending); XCTAssertEqual(fresh.phase, "ready")
        XCTAssertEqual(freshWire.requests.last?.httpBody, bytes)
        let cleared = try await freshStore.read(); XCTAssertNil(cleared)
    }
    func testLostStartReplySurvivesRestartAndNeverRepeatsStart() async throws {
        let a = Anchors(), b = Blobs(), s = try owner(), w1 = wire(), j1 = try journal(a, b)
        w1.responses[start] = .failure(.unknownResult)
        let first = try model(w1, j1, current: { s }); await first.start()
        XCTAssertTrue(first.startOutcomeUnknown); XCTAssertEqual(w1.requests.count, 1)
        let marker = try await j1.read(); XCTAssertEqual(marker?.value.phase, .starting)
        let w2 = wire(), second = try model(w2, journal(a, b), current: { s })
        await second.start(); await second.start(); await second.recover(); await second.retryExact()
        XCTAssertTrue(second.startOutcomeUnknown); XCTAssertTrue(second.blocksReadRebinding)
        XCTAssertTrue(w2.requests.isEmpty)
    }
    func testReceivedStartIdentityRecoversReadOnlyAfterInterruptedClear() async throws {
        let a = Anchors(), b = Blobs(), s = try owner(), j1 = try journal(a, b)
        let prepared = try await j1.prepare(.init(session: s, scope: scope(), process: j1.processID))
        _ = try await j1.transition(prepared, to: .started, startedSessionID: 601)
        let w2 = wire(), j2 = try journal(a, b), second = try model(w2, j2, current: { s })
        await second.start()
        XCTAssertEqual(second.phase, "ready"); XCTAssertFalse(second.startOutcomeUnknown)
        XCTAssertEqual(w2.requests.map { $0.url?.path }, [state])
        let cleared = try await j2.read(); XCTAssertNil(cleared)
    }
    func testFirstActionBusinessErrorNeverProvesNonCommit() async throws {
        for code in [403, 404, 409, 500] {
            let a = Anchors(), b = Blobs(), s = try owner(), j = try journal(a, b), w = wire()
            w.responses[action] = .reply(Data("{\"code\":\(code),\"msg\":\"synthetic post-commit failure\"}".utf8), 200)
            let player = try model(w, j, current: { s }); await player.start()
            let pending = try await unknown(player), stored = try await j.read()
            XCTAssertEqual(stored?.value.pending, pending); XCTAssertEqual(stored?.value.phase, .unknown)
            await player.submit(kind: "coinFlip", action: "FLIP_COIN")
            XCTAssertEqual(w.requests.filter { $0.url?.path == action }.count, 1)
        }
    }
    func testReadErrorUnknownAndHigherVersionCannotClearOriginal() async throws {
        let a = Anchors(), b = Blobs(), s = try owner(), j = try journal(a, b), w = wire()
        let player = try model(w, j, current: { s }); await player.start(); let pending = try await unknown(player)
        for response in [PlayRecoveryRecordingTransport.Response.failure(.unknownResult), .reply(Data("{\"code\":404}".utf8), 200), .reply(Data("bad".utf8), 200)] {
            w.responses[state] = response; await player.recover()
            let stored = try await j.read(); XCTAssertEqual(stored?.value.pending, pending)
            XCTAssertEqual(player.phase, "unknown")
        }
        w.responses[state] = .reply(reply(30), 200); await player.recover()
        XCTAssertEqual(player.phase, "retryable"); XCTAssertEqual(player.pending, pending)
        XCTAssertEqual(w.requests.filter { $0.url?.path == action }.count, 1)
    }
    func testCurrentProcessInFlightCannotBeReplayedBySecondViewer() async throws {
        let a = Anchors(), b = Blobs(), s = try owner(), process = UUID(), j = try journal(a, b, process: process)
        let prepared = try await j.prepare(record()), dispatched = try await j.transition(prepared, to: .dispatching, startedSessionID: nil)
        let w = wire(), viewer = try model(w, journal(a, b, process: process), current: { s })
        await viewer.start(); await viewer.recover(); await viewer.retryExact()
        XCTAssertEqual(viewer.pending, dispatched.value.pending); XCTAssertEqual(viewer.phase, "unknown")
        XCTAssertTrue(w.requests.isEmpty)
    }
    func testPreviousProcessDispatchRequiresReadThenExplicitSameKeyReplay() async throws {
        let a = Anchors(), b = Blobs(), s = try owner(), j = try journal(a, b)
        let prepared = try await j.prepare(record()), dispatched = try await j.transition(prepared, to: .dispatching, startedSessionID: nil)
        let w = wire(), viewer = try model(w, journal(a, b), current: { s })
        await viewer.start()
        XCTAssertEqual(viewer.phase, "retryable"); XCTAssertEqual(viewer.pending, dispatched.value.pending)
        XCTAssertEqual(w.requests.map { $0.url?.path }, [state])
        w.responses[action] = .reply(reply(3), 200); await viewer.retryExact()
        let raw = try JSONDecoder().decode(PlayWireValue.self, from: XCTUnwrap(w.requests.last?.httpBody))
        XCTAssertEqual(raw["idempotencyKey"].text, dispatched.value.pending?.key)
    }
    func testPersistedAcknowledgementResumesWithReadAndClearWithoutReplay() async throws {
        let a = Anchors(), b = Blobs(), s = try owner(), j1 = try journal(a, b)
        let prepared = try await j1.prepare(record()), dispatched = try await j1.transition(prepared, to: .dispatching, startedSessionID: nil)
        _ = try await j1.transition(dispatched, to: .acknowledged, startedSessionID: nil)
        let j2 = try journal(a, b), w = wire(), viewer = try model(w, j2, current: { s }); await viewer.start()
        XCTAssertEqual(viewer.phase, "ready"); XCTAssertNil(viewer.pending)
        XCTAssertEqual(w.requests.map { $0.url?.path }, [state]); let empty = try await j2.read(); XCTAssertNil(empty)
    }
    func testWrongAccountRealmNodeAndRoleCannotRecoverOriginal() async throws {
        let a = Anchors(), b = Blobs(), j = try journal(a, b), value = try record()
        _ = try await j.prepare(value)
        for s in [try owner(account: 8), try owner(namespace: "another-realm")] {
            let separate = try journal(a, b, owner: s), empty = try await separate.read(); XCTAssertNil(empty)
        }
        let separateNode = try journal(a, b, node: 702), empty = try await separateNode.read(); XCTAssertNil(empty)
        let wrongRole = try journal(a, b, owner: owner(role: "merchant"))
        await fail { _ = try await wrongRole.read() }
        await fail { _ = try await wrongRole.prepare(self.record(session: self.owner(role: "merchant"))) }
        let retained = try await j.read(); XCTAssertEqual(retained?.value, value)
    }
    func testScalarAndUnicodePayloadBytesSurviveEncryptedRestart() async throws {
        let a = Anchors(), b = Blobs(), j = try journal(a, b)
        let pending = PlayAdvancedPending(sessionID: 601, version: 2, key: UUID().uuidString, action: "SUBMIT_NOTE",
            payload: ["text": .string("synthetic private e\u{301}"), "decimal": .number(1.25), "integer": .integer(1), "flag": .bool(true), "null": .null])
        let initial = try await j.prepare(record(pending)), reopened = try journal(a, b)
        let raw = try await reopened.read(), restored = try XCTUnwrap(raw?.value.pending)
        XCTAssertEqual(try PlayAdvancedFrozenAction.requestBytes(restored), try PlayAdvancedFrozenAction.requestBytes(pending))
        XCTAssertEqual(restored.payload["decimal"], .number(1.25)); XCTAssertEqual(restored.payload["flag"], .bool(true))
        let bytes = try XCTUnwrap(initial.persistedBytes)
        XCTAssertNil(bytes.range(of: Data("SYNTHETIC-DO-NOT-PERSIST".utf8)))
        let anchors = await a.snapshots(), blobs = await b.snapshots()
        for item in anchors { XCTAssertNil(item.bytes.range(of: Data("synthetic private".utf8))) }
        for blob in blobs { XCTAssertNil(blob.range(of: Data("synthetic private".utf8))) }
    }
    func testExactUTF8NamespacePreventsCanonicalEquivalentSlotAlias() async throws {
        let a = Anchors(), b = Blobs(), one = try owner(namespace: "e\u{301}"), two = try owner(namespace: "\u{e9}")
        let j1 = try journal(a, b, owner: one), j2 = try journal(a, b, owner: two)
        _ = try await j1.prepare(record(session: one))
        let empty = try await j2.read(); XCTAssertNil(empty)
        XCTAssertNotEqual(try scope().key(owner: .init(session: one)), try scope().key(owner: .init(session: two)))
    }
    func testUnknownCannotBeClearedAndStaleGenerationCannotClearNewer() async throws {
        let a = Anchors(), b = Blobs(), j = try journal(a, b), prepared = try await j.prepare(record())
        await fail { try await j.clear(prepared) }
        let dispatched = try await j.transition(prepared, to: .dispatching, startedSessionID: nil)
        let unknown = try await j.transition(dispatched, to: .unknown, startedSessionID: nil)
        await fail { try await j.clear(unknown) }
        await fail { _ = try await j.transition(prepared, to: .dispatching, startedSessionID: nil) }
        let replay = try await j.transition(unknown, to: .dispatching, startedSessionID: nil)
        let ack = try await j.transition(replay, to: .acknowledged, startedSessionID: nil); try await j.clear(ack)
        let newer = try await j.prepare(record()); await fail { try await j.clear(ack) }
        let retained = try await j.read(); XCTAssertEqual(retained, newer)
    }
    func testInterruptedPrepareOrCiphertextCorruptionBlocksDispatchAndOverwrite() async throws {
        for partial in [false, true] {
            let a = Anchors(), b = Blobs(), s = try owner(), j = try journal(a, b), w = wire()
            await b.configure(failInsert: !partial, partial: partial)
            let first = try model(w, j, current: { s }); await first.start()
            XCTAssertTrue(w.requests.isEmpty)
            await b.configure(); let reopened = try journal(a, b)
            await fail { _ = try await reopened.read() }
            await fail { _ = try await reopened.prepare(self.record()) }
        }
    }
    func testMissingAnchorOrPresenceNeverFallsBackToEmpty() async throws {
        for loseAnchor in [false, true] {
            let a = Anchors(), b = Blobs(), j = try journal(a, b); _ = try await j.prepare(record())
            if loseAnchor { await a.loseAnchors() } else { await b.losePresence() }
            let reopened = try journal(a, b)
            await fail { _ = try await reopened.read() }; await fail { _ = try await reopened.prepare(self.record()) }
        }
    }
    func testFullyStagedWriteRecoversAfterInterruptedAnchorPublication() async throws {
        let a = Anchors(), b = Blobs(), j = try journal(a, b), value = try record()
        await a.configure(failExchange: true); await fail { _ = try await j.prepare(value) }; await a.configure()
        let reopened = try journal(a, b), restored = try await reopened.read()
        XCTAssertEqual(restored?.value, value)
        await fail { _ = try await reopened.prepare(self.record()) }
    }
    func testInterruptedAcknowledgedClearFinishesWithoutResurrectingAction() async throws {
        let a = Anchors(), b = Blobs(), j = try journal(a, b)
        let p = try await j.prepare(record()), d = try await j.transition(p, to: .dispatching, startedSessionID: nil)
        let ack = try await j.transition(d, to: .acknowledged, startedSessionID: nil)
        await b.configure(failRemove: true); await fail { try await j.clear(ack) }; await b.configure()
        let reopened = try journal(a, b), cleared = try await reopened.read(); XCTAssertNil(cleared)
        await fail { try await reopened.clear(ack) }
    }
    func testAccountChangeDuringOriginalReplyRetainsJournalWithoutExposingResult() async throws {
        let a = Anchors(), b = Blobs(), j = try journal(a, b), w = wire()
        var current: PlayExperienceSession? = try owner()
        let player = try model(w, j, current: { current }); await player.start()
        w.responses[action] = .reply(reply(3), 200); w.pauseResponse = true
        let operation = Task { await player.submit(kind: "coinFlip", action: "FLIP_COIN") }
        for _ in 0..<1000 { if w.isAwaitingResponse { break }; await Task.yield() }
        XCTAssertTrue(w.isAwaitingResponse); current = try owner(account: 8)
        w.resumeResponse(); await operation.value
        XCTAssertFalse(player.isCurrent); XCTAssertEqual(player.phase, "stale"); XCTAssertNotNil(player.pending)
        let saved = try await j.read(); XCTAssertEqual(saved?.value.phase, .unknown)
        await player.recover(); await player.retryExact()
        XCTAssertEqual(w.requests.filter { $0.url?.path == action }.count, 1)
    }
    func testCancellationDuringWriteKeepsDurableOriginalAndNeverRetriesAutomatically() async throws {
        let a = Anchors(), b = Blobs(), s = try owner(), j = try journal(a, b), w = wire()
        let player = try model(w, j, current: { s }); await player.start(); w.pauseResponse = true
        let operation = Task { await player.submit(kind: "coinFlip", action: "FLIP_COIN") }
        for _ in 0..<1000 { if w.isAwaitingResponse { break }; await Task.yield() }
        XCTAssertTrue(w.isAwaitingResponse); operation.cancel(); w.resumeResponse(); await operation.value
        let saved = try await j.read(); XCTAssertNotNil(saved?.value.pending); XCTAssertEqual(player.phase, "unknown")
        XCTAssertEqual(w.requests.filter { $0.url?.path == action }.count, 1)
    }
    func testForeignSessionReadNeverReleasesPersistedOriginal() async throws {
        let a = Anchors(), b = Blobs(), s = try owner(), j = try journal(a, b), w = wire()
        let player = try model(w, j, current: { s }); await player.start(); let pending = try await unknown(player)
        w.responses[state] = .reply(reply(3, session: 999), 200); await player.recover()
        XCTAssertEqual(player.pending, pending); XCTAssertEqual(player.phase, "unknown")
        let saved = try await j.read(); XCTAssertEqual(saved?.value.pending, pending)
    }
    func testUnavailableStoragePreventsNormalStartWithoutMemoryFallback() async throws {
        let s = try owner(), w = wire(), player = try model(w, PlayUnavailableAdvancedRecovery(), current: { s })
        await player.start(); await player.recover()
        XCTAssertTrue(w.requests.isEmpty); XCTAssertFalse(player.canInteract)
        XCTAssertEqual(player.issue, .persistenceUnavailable)
    }
    func testOlderExactReplayReceiptCannotRegressNewerAuthoritativeProjection() async throws {
        let a = Anchors(), b = Blobs(), s = try owner(), j = try journal(a, b), w = wire()
        let player = try model(w, j, current: { s }); await player.start(); _ = try await unknown(player)
        w.responses[state] = .reply(reply(30), 200); await player.recover()
        w.responses[action] = .reply(reply(3), 200); await player.retryExact()
        XCTAssertNil(player.pending); XCTAssertEqual(player.phase, "ready")
        XCTAssertEqual(player.state?.version, 30)
        let cleared = try await j.read(); XCTAssertNil(cleared)
    }
    func testAcknowledgementDoesNotClearAgainstOlderUnadvancedRead() async throws {
        let a = Anchors(), b = Blobs(), s = try owner(), j = try journal(a, b)
        let p = try await j.prepare(record()), d = try await j.transition(p, to: .dispatching, startedSessionID: nil)
        _ = try await j.transition(d, to: .acknowledged, startedSessionID: nil)
        let w = wire(); w.responses[state] = .reply(reply(2), 200)
        let reopened = try journal(a, b), viewer = try model(w, reopened, current: { s }); await viewer.start()
        XCTAssertEqual(viewer.phase, "unknown"); XCTAssertNotNil(viewer.pending)
        let retained = try await reopened.read(); XCTAssertEqual(retained?.value.phase, .acknowledged)
    }

    func testTemporarilyLockedPrepareResumesSameOriginalAfterUnlock() async throws {
        let a = Anchors(), b = Blobs(), s = try owner(), j = try journal(a, b), w = wire()
        let player = try model(w, j, current: { s }); await player.start()
        await a.configure(locked: true); let pending = try await unknown(player)
        XCTAssertEqual(w.requests.count, 1)
        await a.configure(); await player.recover()
        XCTAssertEqual(player.pending, pending); XCTAssertEqual(player.phase, "retryable")
        let persisted = try await j.read(); XCTAssertEqual(persisted?.value.pending, pending)
        XCTAssertEqual(w.requests.filter { $0.url?.path == action }.count, 0)
        w.responses[action] = .reply(reply(3), 200); await player.retryExact()
        XCTAssertNil(player.pending); XCTAssertEqual(player.phase, "ready")
        let raw = try JSONDecoder().decode(PlayWireValue.self, from: XCTUnwrap(w.requests.last?.httpBody))
        XCTAssertEqual(raw["idempotencyKey"].text, pending.key)
    }
    func testInitiallyLockedReadCanReopenStartControlWithoutSending() async throws {
        let a = Anchors(), b = Blobs(), s = try owner(), j = try journal(a, b), w = wire()
        await a.configure(locked: true)
        let player = try model(w, j, current: { s }); await player.start()
        XCTAssertTrue(w.requests.isEmpty); XCTAssertFalse(player.startOutcomeUnknown)
        await a.configure(); await player.recover()
        XCTAssertEqual(player.phase, "idle"); XCTAssertTrue(w.requests.isEmpty)
        await player.start(); XCTAssertEqual(player.phase, "ready"); XCTAssertEqual(w.requests.count, 1)
    }

    func testOlderCardReplayCannotRestoreReceiptRevokedByNewerProjection() async throws {
        func photo(_ version: Int, passed: Bool, degraded: Bool = false, mode: String = "CARD", card: Bool = false) -> Data {
            let receipt = card ? ",\"objectCard\":{\"id\":901,\"title\":\"Synthetic receipt\"}" : ""
            return PlayExperienceSyntheticFixtures.envelope("{\"sessionId\":601,\"activityId\":41,\"topicId\":71,\"nodeId\":701,\"version\":\(version),\"status\":\"RUNNING\",\"playKit\":{\"photoCheck\":{\"mode\":\"\(mode)\",\"passed\":\(passed),\"degraded\":\(degraded)}}\(receipt)}")
        }
        for newer in [photo(30, passed: false), photo(30, passed: true, degraded: true), photo(30, passed: true, mode: "VERIFY")] {
            let a = Anchors(), b = Blobs(), s = try owner(), j = try journal(a, b), w = wire()
            w.responses[start] = .reply(photo(2, passed: false), 200)
            let player = try model(w, j, current: { s }); await player.start()
            await player.submit(kind: "photoCheck", action: "SUBMIT_PHOTO_CHECK", detail: ["imageUrl": .string("https://example.test/photo")])
            XCTAssertNotNil(player.pending); XCTAssertEqual(player.phase, "unknown")
            w.responses[state] = .reply(newer, 200); await player.recover()
            w.responses[action] = .reply(photo(3, passed: true, card: true), 200); await player.retryExact()
            XCTAssertNil(player.pending); XCTAssertEqual(player.state?.version, 30)
            XCTAssertNil(player.objectCardReceipt)
        }
    }

    @MainActor private final class FirstPrepareFails: PlayAdvancedRecovery {
        private let base = PlayMemoryAdvancedRecovery()
        private var failed = false
        var processID: UUID { base.processID }
        func read() async throws -> PlayAdvancedRecoverySnapshot? { try await base.read() }
        func prepare(_ value: PlayAdvancedRecoveryRecord) async throws -> PlayAdvancedRecoverySnapshot {
            if !failed { failed = true; throw PlayExperienceError.persistenceUnavailable }
            return try await base.prepare(value)
        }
        func transition(_ snapshot: PlayAdvancedRecoverySnapshot, to phase: PlayAdvancedRecoveryRecord.Phase, startedSessionID: Int?) async throws -> PlayAdvancedRecoverySnapshot {
            try await base.transition(snapshot, to: phase, startedSessionID: startedSessionID)
        }
        func clear(_ snapshot: PlayAdvancedRecoverySnapshot) async throws { try await base.clear(snapshot) }
    }
    func testEmptyJournalAfterFailedInitialPrepareCanReopenStartWithoutResend() async throws {
        let s = try owner(), w = wire(), store = FirstPrepareFails()
        let player = try model(w, store, current: { s }); await player.start()
        XCTAssertTrue(w.requests.isEmpty); XCTAssertFalse(player.startOutcomeUnknown)
        XCTAssertEqual(player.phase, "unknown")
        await player.recover(); XCTAssertEqual(player.phase, "idle"); XCTAssertTrue(w.requests.isEmpty)
        await player.start(); XCTAssertEqual(player.phase, "ready"); XCTAssertEqual(w.requests.count, 1)
    }

}

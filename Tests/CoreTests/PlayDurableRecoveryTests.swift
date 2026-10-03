import XCTest
@testable import QuestifyCore

/// Synthetic stores only; actual OS probes live in the simulator app-unit target.
@MainActor final class PlayDurableRecoveryTests: XCTestCase {
    typealias Anchors = ContentDraftDurableJournalTests.Anchors
    typealias Blobs = ContentDraftDurableJournalTests.Blobs
    private func session(account: Int = 9001, epoch: UInt64 = 1, namespace: String = "synthetic-cn", role: String = "player") throws -> PlayExperienceSession {
        try .init(accountID: account, epoch: epoch, namespace: namespace, token: "NEVER-PERSIST-SYNTHETIC-TOKEN", role: role)
    }
    private func key(_ session: PlayExperienceSession) -> String { PlayRunStorageKey.make(session: session, scope: .activity(41)) }
    private func journal(_ a: Anchors, _ b: Blobs, session: PlayExperienceSession? = nil, process: UUID = UUID()) throws -> PlayDurableRecovery {
        let session = try session ?? self.session()
        return try .init(owner: .init(session: session), key: key(session), anchors: a, ciphertexts: b, processID: process)
    }
    private func intent(session: PlayExperienceSession? = nil, text: String = "synthetic private answer") throws -> PlayCompletionIntent {
        .init(review: .init(nodeID: 701, evidence: .answer(text), advance: try .init(actionID: "immutable-action", expectedVersion: 2), session: try session ?? self.session(), generation: 1, routeSessionID: 601))
    }
    private func fails(_ operation: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line) async {
        do { try await operation(); XCTFail("Expected fail-closed recovery", file: file, line: line) }
        catch { XCTAssertEqual(error as? PlayExperienceError, .persistenceUnavailable, file: file, line: line) }
    }
    func testRestartRetainsExactIntentWithoutCredentialsAndExcludesSameProcessReplay() async throws {
        let a = Anchors(), b = Blobs(), s = try session(), k = key(s), process = UUID()
        let first = try journal(a, b, process: process), value = try intent()
        let prepared = try await first.prepare(value, key: k), dispatched = try await first.transition(prepared, to: .dispatching, key: k)
        let sameProcess = try journal(a, b, process: process), readCurrent = try await sameProcess.read(k), current = try XCTUnwrap(readCurrent)
        await fails { _ = try await sameProcess.transition(current, to: .dispatching, key: k) }
        let fresh = try session(epoch: 2), restarted = try journal(a, b, session: fresh)
        let readRestored = try await restarted.read(k), restored = try XCTUnwrap(readRestored)
        XCTAssertEqual(restored.value.intent, value); XCTAssertEqual(restored.value.state, .dispatching)
        let review = try restored.value.intent.review(session: fresh, generation: 8)
        XCTAssertEqual(review.evidence, value.evidence); XCTAssertEqual(review.advance, value.advance); XCTAssertEqual(review.session, fresh)
        let replay = try await restarted.transition(restored, to: .dispatching, key: k)
        XCTAssertNotEqual(replay.generation, dispatched.generation)
        let bytes = try XCTUnwrap(replay.persistedBytes); XCTAssertNil(bytes.range(of: Data(s.token.utf8)))
        for anchor in await a.snapshots() { XCTAssertNil(anchor.bytes.range(of: Data(s.token.utf8))); XCTAssertNil(anchor.bytes.range(of: Data("synthetic private answer".utf8))) }
        for blob in await b.snapshots() { XCTAssertNil(blob.range(of: Data("synthetic private answer".utf8))) }
    }
    func testTwoViewersCannotOverwriteOrReuseOldDispatchOrClearGeneration() async throws {
        let a = Anchors(), b = Blobs(), k = key(try session()), process = UUID()
        let one = try journal(a, b, process: process), two = try journal(a, b, process: process)
        let initial = try await one.prepare(intent(), key: k)
        await fails { _ = try await two.prepare(self.intent(text: "different"), key: k) }
        let dispatched = try await one.transition(initial, to: .dispatching, key: k)
        await fails { _ = try await two.transition(initial, to: .dispatching, key: k) }
        await fails { try await two.clear(initial, key: k) }
        let unknown = try await one.transition(dispatched, to: .unknown, key: k), claimed = try await two.transition(unknown, to: .dispatching, key: k)
        await fails { _ = try await one.transition(unknown, to: .dispatching, key: k) }
        try await two.clear(claimed, key: k)
        let newer = try await one.prepare(intent(text: "newer"), key: k)
        await fails { try await two.clear(claimed, key: k) }
        let kept = try await one.read(k); XCTAssertEqual(kept, newer)
    }
    func testInterruptedPrepareAndDispatchMissingOrPartialBlobStayLocked() async throws {
        for duringDispatch in [false, true] {
            for partial in [false, true] {
                let a = Anchors(), b = Blobs(), j = try journal(a, b), k = key(try session())
                let initial = duringDispatch ? try await j.prepare(intent(), key: k) : nil
                await b.configure(failInsert: !partial, partial: partial)
                await fails {
                    if let initial { _ = try await j.transition(initial, to: .dispatching, key: k) }
                    else { _ = try await j.prepare(self.intent(), key: k) }
                }
                await b.configure(); let reopened = try journal(a, b)
                await fails { _ = try await reopened.read(k) }
                await fails { _ = try await reopened.prepare(self.intent(text: "must not replace"), key: k) }
            }
        }
    }
    func testFullyStagedPrepareRecoversButCannotBeOverwritten() async throws {
        let a = Anchors(), b = Blobs(), j = try journal(a, b), k = key(try session()), value = try intent()
        await a.configure(failExchange: true); await fails { _ = try await j.prepare(value, key: k) }; await a.configure()
        let reopened = try journal(a, b), restored = try await reopened.read(k)
        XCTAssertEqual(restored?.value.intent, value); XCTAssertEqual(restored?.value.state, .prepared)
        await fails { _ = try await reopened.prepare(value, key: k) }
    }
    func testClearTombstoneFinishesAfterInterruptionAndOldLeaseCannotClearNewIntent() async throws {
        let a = Anchors(), b = Blobs(), j = try journal(a, b), k = key(try session())
        let initial = try await j.prepare(intent(), key: k)
        await b.configure(failRemove: true); await fails { try await j.clear(initial, key: k) }; await b.configure()
        let reopened = try journal(a, b), empty = try await reopened.read(k); XCTAssertNil(empty)
        let next = try await reopened.prepare(intent(text: "next"), key: k)
        await fails { try await reopened.clear(initial, key: k) }
        let kept = try await reopened.read(k); XCTAssertEqual(kept, next)
    }
    func testLockedCorruptAndLostAfterWriteStorageNeverLooksEmpty() async throws {
        for failure in 0..<5 {
            let a = Anchors(), b = Blobs(), j = try journal(a, b), k = key(try session())
            _ = try await j.prepare(intent(), key: k)
            switch failure {
            case 0: await a.configure(locked: true)
            case 1: await a.corrupt()
            case 2: await b.corrupt()
            case 3: await a.loseAnchors()
            default: await b.losePresence()
            }
            let reopened = try journal(a, b)
            await fails { _ = try await reopened.read(k) }; await fails { _ = try await reopened.prepare(self.intent(), key: k) }
        }
    }
    func testAccountRealmScopeAndRoleCannotReadOrOverwriteForeignIntent() async throws {
        let a = Anchors(), b = Blobs(), original = try session(), k = key(original), j = try journal(a, b)
        let initial = try await j.prepare(intent(), key: k)
        for s in [try session(account: 9002), try session(namespace: "other-realm")] {
            let other = try journal(a, b, session: s), empty = try await other.read(key(s)); XCTAssertNil(empty)
            await fails { _ = try await other.prepare(self.intent(), key: self.key(s)) }
        }
        let role = try session(role: "merchant"), alias = try journal(a, b, session: role)
        await fails { _ = try await alias.read(k) }; await fails { _ = try await alias.prepare(self.intent(session: role), key: k) }
        await fails { _ = try await j.read(PlayRunStorageKey.make(session: original, scope: .topic(41))) }
        let kept = try await j.read(k); XCTAssertEqual(kept, initial)
    }
    func testCrossScopeAnchorTransplantAndCiphertextRollbackFailClosed() async throws {
        let a = Anchors(), b = Blobs(), k = key(try session()), j = try journal(a, b)
        let initial = try await j.prepare(intent(), key: k), savedBlobs = await b.playSnapshot()
        _ = try await j.transition(initial, to: .dispatching, key: k)
        await b.replaceAllPlayBlobs(with: savedBlobs.values.first!); await fails { _ = try await j.read(k) }
        let c = Anchors(), d = Blobs(), one = try journal(c, d)
        _ = try await one.prepare(intent(), key: k); let anchors = await c.snapshots()
        let otherSession = try session(account: 9002), other = try journal(c, d, session: otherSession)
        _ = try await other.prepare(intent(session: otherSession), key: key(otherSession)); await c.copyIntoEverySlot(anchors[0])
        await fails { _ = try await other.read(self.key(otherSession)) }
    }
    func testPausedAtomicTombstoneRejectsABAStaleTimeAndResurrectionAfterRelaunch() async throws {
        let a = Anchors(), b = Blobs(), s = try session(), k = key(s), j = try journal(a, b)
        let empty = try await j.read(key: k), record = try PlayPausedRecord(elapsedSeconds: 12, savedAt: 100)
        let first = try await j.write(.init(owner: .init(session: s), record: record), replacing: empty, key: k)
        let cleared = try await j.write(.init(owner: .init(session: s), record: nil, tombstone: 100), replacing: first, key: k)
        await fails { _ = try await j.write(.init(owner: .init(session: s), record: record), replacing: first, key: k) }
        await fails { _ = try await j.write(.init(owner: .init(session: s), record: record), replacing: cleared, key: k) }
        let reopened = try journal(a, b, session: session(epoch: 3)), restored = try await reopened.read(key: k)
        XCTAssertNil(restored.value?.record); XCTAssertEqual(restored.value?.tombstone, 100)
        await a.loseAnchors(); await fails { _ = try await reopened.read(key: k) }
    }
    func testTaggedEvidenceKeepsScalarTypesAndExactUnicodeAcrossRelaunch() async throws {
        let a = Anchors(), b = Blobs(), s = try session(), k = key(s), j = try journal(a, b)
        let evidence = PlayCompletionEvidence.sensor(type: "still", payload: ["float": .number(1.0), "int": .integer(1), "text": .string("e\u{301}"), "bool": .bool(true)])
        let value = PlayCompletionIntent(review: .init(nodeID: 701, evidence: evidence, advance: nil, session: s, generation: 1, routeSessionID: nil))
        _ = try await j.prepare(value, key: k); let restored = try await journal(a, b).read(k)
        XCTAssertEqual(restored?.value.intent.evidence, evidence)
        if case .sensor(_, let fields) = restored?.value.intent.evidence { XCTAssertEqual(fields["text"]?.text?.utf8.map { $0 }, Array("e\u{301}".utf8)) }
        else { XCTFail("Expected exact sensor evidence") }
    }
    func testFinalBlobReadRejectsGenerationChangedByAnotherEngine() async throws {
        let a = Anchors(), b = Blobs(), k = key(try session()), one = try journal(a, b), two = try journal(a, b)
        let initial = try await one.prepare(intent(), key: k)
        await b.pauseRead(); let reading = Task { try await one.read(k) }
        for _ in 0..<1_000 { if await b.isReadSuspended() { break }; await Task.yield() }
        let suspended = await b.isReadSuspended(); XCTAssertTrue(suspended)
        _ = try await two.transition(initial, to: .dispatching, key: k)
        await b.resumeRead(); await fails { _ = try await reading.value }
    }
}
extension ContentDraftDurableJournalTests.Blobs {
    func playSnapshot() -> [String: Data] { values }
    func replaceAllPlayBlobs(with bytes: Data) { for name in values.keys { values[name] = bytes } }
}

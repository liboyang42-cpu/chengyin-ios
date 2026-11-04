import XCTest
@testable import QuestifyCore

/// Independent synthetic primitives shared only by the new backpack tests.
/// No Keychain, disk, account, network, production factory, or shared journal mutation.
actor BackpackRecoveryTestAnchors: ContentDraftAnchorStore {
    private var items: [String: ContentDraftAnchorItem] = [:]
    private var locked = false, failExchange = false, interruptAfterInsert = false
    private var substituteAtExchange: ContentDraftAnchorItem?
    func read(slot: String) throws -> ContentDraftAnchorItem? {
        if locked { throw ContentDraftIssue.storageUnavailable }; return items[slot]
    }
    func insert(slot: String, item: ContentDraftAnchorItem) throws -> Bool {
        if locked { throw ContentDraftIssue.storageUnavailable }
        guard items[slot] == nil else { return false }; items[slot] = item
        if interruptAfterInsert { throw ContentDraftIssue.storageUnavailable }; return true
    }
    func exchange(slot: String, matchingTag: Data, item: ContentDraftAnchorItem) throws -> Bool {
        if locked || failExchange { throw ContentDraftIssue.storageUnavailable }
        if let replacement = substituteAtExchange { items[slot] = replacement; substituteAtExchange = nil }
        guard items[slot]?.tag == matchingTag else { return false }; items[slot] = item; return true
    }
    func configure(locked: Bool = false, failExchange: Bool = false, interrupt: Bool = false) {
        self.locked = locked; self.failExchange = failExchange; interruptAfterInsert = interrupt
    }
    func snapshots() -> [ContentDraftAnchorItem] { Array(items.values) }
    func loseAnchors() { items.removeAll() }
    func corrupt() { for key in Array(items.keys) { items[key] = .init(bytes: Data([0]), tag: Data(repeating: 0, count: 32)) } }
    func replaceOnExchange(_ item: ContentDraftAnchorItem) { substituteAtExchange = item }
    func copyIntoEverySlot(_ item: ContentDraftAnchorItem) { for key in Array(items.keys) { items[key] = item } }
}

actor BackpackRecoveryTestCiphertexts: ContentDraftCiphertextStore {
    private var values: [String: Data] = [:]
    private var presence: Set<String> = []
    private var failInsert = false, partialInsert = false, failRemove = false, interruptPresence = false
    private var pauseNextRead = false
    private var waitingRead: CheckedContinuation<Void, Never>?
    func hasPresence(slot: String) -> Bool { presence.contains(slot) }
    func createPresence(slot: String) throws -> Bool {
        let inserted = presence.insert(slot).inserted
        if interruptPresence { throw ContentDraftIssue.storageUnavailable }; return inserted
    }
    func insert(name: String, bytes: Data) throws {
        guard values[name] == nil else { throw ContentDraftIssue.storageUnavailable }
        if partialInsert { values[name] = Data(bytes.prefix(10)); throw ContentDraftIssue.storageUnavailable }
        if failInsert { throw ContentDraftIssue.storageUnavailable }; values[name] = bytes
    }
    func readDurably(name: String, limit: Int) async throws -> Data {
        guard let value = values[name], value.count <= limit else { throw ContentDraftIssue.storageUnavailable }
        if pauseNextRead { pauseNextRead = false; await withCheckedContinuation { waitingRead = $0 } }
        return value
    }
    func removeDurably(name: String) throws {
        if failRemove { throw ContentDraftIssue.storageUnavailable }; values[name] = nil
    }
    func configure(failInsert: Bool = false, partial: Bool = false, failRemove: Bool = false) {
        self.failInsert = failInsert; partialInsert = partial; self.failRemove = failRemove
    }
    func snapshots() -> [Data] { Array(values.values) }
    func losePresence() { presence.removeAll() }
    func corrupt() { for key in Array(values.keys) { values[key] = Data([1, 2, 3]) } }
    func interruptAfterPresence() { interruptPresence = true }
    func pauseRead() { pauseNextRead = true }
    func isReadSuspended() -> Bool { waitingRead != nil }
    func resumeRead() { let old = waitingRead; waitingRead = nil; old?.resume() }
}

@MainActor final class PlayThemeBackpackRecoveryTests: XCTestCase {
    private typealias Anchors = BackpackRecoveryTestAnchors
    private typealias Blobs = BackpackRecoveryTestCiphertexts
    private func session(account: Int = 7, epoch: UInt64 = 1, namespace: String = "synthetic-backpack",
                         role: String = "player") throws -> PlayExperienceSession {
        try .init(accountID: account, epoch: epoch, namespace: namespace, token: "SYNTHETIC-DO-NOT-PERSIST", role: role)
    }
    private func intent(session: PlayExperienceSession? = nil, scope: PlaySessionScope = .activity(41),
                        topic: Int = 71, run: Int = 601, version: Int = 2, action: String = "bag_synthetic",
                        operation: PlayThemeBackpackOperation = .use, content: String = "tea",
                        discard: [PlayThemeBackpackDiscard]? = nil) throws -> PlayThemeBackpackIntent {
        try .init(session: session ?? self.session(), scope: scope, topicID: topic,
                  command: .init(sessionID: run, version: version, operation: operation,
                                 contentID: content, discardOwned: discard, actionID: action))
    }
    private func store(_ anchors: Anchors, _ blobs: Blobs, session: PlayExperienceSession? = nil,
                       scope: PlaySessionScope = .activity(41), topic: Int = 71,
                       process: UUID = UUID()) throws -> PlayThemeBackpackRecoveryStore {
        try .init(session: session ?? self.session(), scope: scope, topicID: topic,
                  anchors: anchors, ciphertexts: blobs, processID: process)
    }
    private func receipt(run: Int = 601, version: Int = 3, topic: Int = 71, activity: Int = 41,
                         status: String = "ACTIVE", scope: String? = nil, runtimeScope: String? = "PLAYER",
                         padding: String? = nil) throws -> Data {
        var value: [String: Any] = ["sessionId": run, "version": version, "topicId": topic, "activityId": activity,
            "status": status, "inventoryEnabled": true, "used": 0, "capacity": 6,
            "contents": [], "pending": [:], "playInstanceId": "synthetic-original"]
        if let scope { value["scope"] = scope }
        if let runtimeScope { value["runtimeScope"] = runtimeScope }
        if let padding { value["note"] = padding }
        return try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    }
    private func fail(_ operation: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line) async {
        do { try await operation(); XCTFail("Expected fail-closed backpack storage", file: file, line: line) }
        catch { XCTAssertEqual(error as? PlayExperienceError, .persistenceUnavailable, file: file, line: line) }
    }
    private func dispatched(_ journal: PlayThemeBackpackRecoveryStore,
                            intent: PlayThemeBackpackIntent? = nil) async throws -> PlayThemeBackpackRecoverySnapshot {
        let prepared = try await journal.prepare(intent ?? self.intent())
        return try await journal.transition(prepared, to: .dispatching)
    }

    func testRoundTripPreservesOriginalBytesWithoutCredentialsOrPlaintextFiles() async throws {
        let a = Anchors(), b = Blobs(), j = try store(a, b)
        let value = try intent(content: "synthetic private e\u{301}")
        let prepared = try await j.prepare(value), recreated = try store(a, b)
        let restored = try await recreated.read(), saved = try XCTUnwrap(restored)
        XCTAssertEqual(saved.value.intent.body, value.body)
        XCTAssertEqual(saved.value.intent.command.contentId.utf8.map { $0 }, value.command.contentId.utf8.map { $0 })
        XCTAssertEqual(saved.value.state, .prepared); XCTAssertNil(saved.value.dispatchProcess)
        XCTAssertNil(saved.value.receipt); XCTAssertEqual(saved.generation.count, 32)
        let bytes = try XCTUnwrap(prepared.persistedBytes)
        XCTAssertNil(bytes.range(of: Data("SYNTHETIC-DO-NOT-PERSIST".utf8)))
        let anchorValues = await a.snapshots(), blobValues = await b.snapshots()
        for anchor in anchorValues { XCTAssertNil(anchor.bytes.range(of: Data("synthetic private".utf8))) }
        for blob in blobValues { XCTAssertNil(blob.range(of: Data("synthetic private".utf8))) }
    }
    func testPublicInjectedStoresShareProcessButNeverGrantDispatchAuthority() throws {
        let a = Anchors(), b = Blobs(), s = try session()
        let first = try PlayThemeBackpackRecoveryStore(session: s, scope: .activity(41), topicID: 71, anchors: a, ciphertexts: b)
        let second = try PlayThemeBackpackRecoveryStore(session: s, scope: .activity(41), topicID: 71, anchors: a, ciphertexts: b)
        XCTAssertEqual(first.processID, second.processID)
        for endpoint in ["https://example.test", "https://example.test/other"] {
            XCTAssertFalse(first.permitsSystemDispatch(to: URL(string: endpoint)!))
        }
    }
    func testEpochAndNewRunCannotBypassExistingSlotAndRoleCannotRebindIt() async throws {
        let a = Anchors(), b = Blobs(), j = try store(a, b), old = try intent()
        _ = try await j.prepare(old)
        let nextEpoch = try session(epoch: 9), reopened = try store(a, b, session: nextEpoch)
        let restored = try await reopened.read(); XCTAssertEqual(restored?.value.intent, old)
        await fail { _ = try await reopened.prepare(self.intent(session: nextEpoch, run: 999, action: "bag_new")) }
        let wrongRole = try session(role: "merchant"), alias = try store(a, b, session: wrongRole)
        await fail { _ = try await alias.read() }
        await fail { _ = try await alias.prepare(self.intent(session: wrongRole)) }
        let anchors = await a.snapshots(); XCTAssertEqual(anchors.count, 1)
    }
    func testAccountRealmActivitySelfPlayAndTopicAreSeparateAndForeignIntentIsRejected() async throws {
        let a = Anchors(), b = Blobs(), j = try store(a, b), original = try intent()
        _ = try await j.prepare(original)
        let alternatives = [
            try store(a, b, session: session(account: 8)),
            try store(a, b, session: session(namespace: "another-realm")),
            try store(a, b, scope: .activity(42)),
            try store(a, b, scope: .topic(71)),
            try store(a, b, topic: 72)
        ]
        for other in alternatives {
            let empty = try await other.read(); XCTAssertNil(empty)
            await fail { _ = try await other.prepare(original) }
        }
        XCTAssertThrowsError(try store(a, b, scope: .topic(72), topic: 71))
    }
    func testCanonicalEquivalentNamespacesAndItemIDsRemainDifferentUTF8Identities() async throws {
        let a = Anchors(), b = Blobs(), first = try session(namespace: "e\u{301}"), second = try session(namespace: "\u{e9}")
        let j1 = try store(a, b, session: first), j2 = try store(a, b, session: second)
        let one = try intent(session: first, content: "e\u{301}"), two = try intent(session: second, content: "\u{e9}")
        XCTAssertNotEqual(one.storageKey, two.storageKey); XCTAssertNotEqual(one.body, two.body)
        _ = try await j1.prepare(one); let empty = try await j2.read(); XCTAssertNil(empty)
    }
    func testAbsentAndEmptyDiscardSelectionsAndRowOrderStayExactAfterRestart() async throws {
        let choices: [[PlayThemeBackpackDiscard]?] = [
            nil, [], [.init(itemID: "tea", quantity: 1), .init(itemID: "map", quantity: 2)],
            [.init(itemID: "map", quantity: 2), .init(itemID: "tea", quantity: 1)]
        ]
        var bodies: [Data] = []
        for choice in choices {
            let a = Anchors(), b = Blobs(), j = try store(a, b)
            let value = try intent(operation: .receive, content: "chapter:0:END:reward", discard: choice)
            _ = try await j.prepare(value)
            let reopened = try store(a, b), read = try await reopened.read(), restored = try XCTUnwrap(read)
            XCTAssertEqual(restored.value.intent.body, value.body); bodies.append(value.body)
        }
        XCTAssertEqual(Set(bodies).count, choices.count)
    }
    func testAlteredStoredBodyNeverPreparesOrOverwritesSlot() async throws {
        let a = Anchors(), b = Blobs(), j = try store(a, b), value = try intent()
        var object = try XCTUnwrap(PropertyListSerialization.propertyList(from: PropertyListEncoder().encode(value), format: nil) as? [String: Any])
        object["body"] = Data(#"{"operation":"DISCARD"}"#.utf8)
        let altered = try PropertyListDecoder().decode(PlayThemeBackpackIntent.self,
            from: PropertyListSerialization.data(fromPropertyList: object, format: .binary, options: 0))
        await fail { _ = try await j.prepare(altered) }
        let empty = try await j.read(); XCTAssertNil(empty)
        _ = try await j.prepare(value)
        await fail { _ = try await j.prepare(altered) }
    }
    func testOnlyDispatchingMayBecomeUnknownOrAcknowledgedAndReceiptCannotBeInjectedElsewhere() async throws {
        let a = Anchors(), b = Blobs(), j = try store(a, b), p = try await j.prepare(intent())
        await fail { _ = try await j.transition(p, to: .unknown) }
        await fail { _ = try await j.transition(p, to: .acknowledged, receipt: self.receipt()) }
        await fail { _ = try await j.transition(p, to: .dispatching, receipt: self.receipt()) }
        let d = try await j.transition(p, to: .dispatching)
        await fail { _ = try await j.transition(d, to: .prepared) }
        await fail { _ = try await j.transition(d, to: .acknowledged) }
        let u = try await j.transition(d, to: .unknown)
        await fail { _ = try await j.transition(u, to: .acknowledged, receipt: self.receipt()) }
        let r = try await j.transition(u, to: .dispatching)
        XCTAssertEqual(r.value.intent.body, p.value.intent.body)
    }
    func testCurrentProcessCannotReplayInFlightAndPreviousProcessMustReclaimBeforeResult() async throws {
        let a = Anchors(), b = Blobs(), process = UUID(), first = try store(a, b, process: process)
        let d = try await dispatched(first)
        let sameProcess = try store(a, b, process: process)
        await fail { _ = try await sameProcess.transition(d, to: .dispatching) }
        let nextProcess = try store(a, b)
        await fail { _ = try await nextProcess.transition(d, to: .unknown) }
        await fail { _ = try await nextProcess.transition(d, to: .acknowledged, receipt: self.receipt()) }
        let reclaimed = try await nextProcess.transition(d, to: .dispatching)
        XCTAssertEqual(reclaimed.value.dispatchProcess, nextProcess.processID)
        XCTAssertNotEqual(reclaimed.generation, d.generation)
        XCTAssertEqual(reclaimed.value.intent.body, d.value.intent.body)
        await fail { _ = try await first.transition(d, to: .unknown) }
    }
    func testReceiptRequiresExactOriginalIdentityVersionKnownStatusAndPersonalProjection() async throws {
        let a = Anchors(), b = Blobs(), j = try store(a, b), d = try await dispatched(j)
        let invalid = [
            try receipt(run: 999), try receipt(topic: 72), try receipt(activity: 0),
            try receipt(version: 2), try receipt(version: 4), try receipt(status: "RUNNING"),
            try receipt(scope: "TEAM"), try receipt(runtimeScope: "TEAM"),
            Data("broken".utf8), Data("{}".utf8), Data("null".utf8), Data()
        ]
        for bytes in invalid {
            await fail { _ = try await j.transition(d, to: .acknowledged, receipt: bytes) }
            let kept = try await j.read(); XCTAssertEqual(kept, d)
        }
    }
    func testAcknowledgedReceiptCanBeTerminalOrLegacyAndResumesAcrossRestart() async throws {
        for status in ["ACTIVE", "COMPLETED", "ENDED"] {
            let a = Anchors(), b = Blobs(), j = try store(a, b), d = try await dispatched(j)
            let bytes = try receipt(status: status, runtimeScope: nil)
            let ack = try await j.transition(d, to: .acknowledged, receipt: bytes)
            let restarted = try store(a, b), read = try await restarted.read(), restored = try XCTUnwrap(read)
            XCTAssertEqual(restored, ack); XCTAssertEqual(restored.value.receipt, bytes)
            await fail { _ = try await restarted.transition(restored, to: .dispatching) }
            try await restarted.clear(restored); let empty = try await restarted.read(); XCTAssertNil(empty)
        }
    }
    func testSelfPlayReceiptRequiresExplicitZeroActivity() async throws {
        let a = Anchors(), b = Blobs(), j = try store(a, b, scope: .topic(71))
        let d = try await dispatched(j, intent: intent(scope: .topic(71)))
        await fail { _ = try await j.transition(d, to: .acknowledged, receipt: self.receipt(activity: 41)) }
        let ack = try await j.transition(d, to: .acknowledged, receipt: receipt(activity: 0))
        try await j.clear(ack)
    }
    func testMaximumInt32VersionAcknowledgesButDoesNotChangeOriginalBody() async throws {
        let a = Anchors(), b = Blobs(), j = try store(a, b)
        let value = try intent(version: Int(Int32.max) - 1)
        let d = try await dispatched(j, intent: value)
        let ack = try await j.transition(d, to: .acknowledged, receipt: receipt(version: Int(Int32.max)))
        XCTAssertEqual(ack.value.intent.body, value.body)
        try await j.clear(ack)
    }
    func testUnknownNeverClearsAndStaleAcknowledgementCannotDeleteNewIntent() async throws {
        let a = Anchors(), b = Blobs(), j = try store(a, b), p = try await j.prepare(intent())
        await fail { try await j.clear(p) }
        let d = try await j.transition(p, to: .dispatching); await fail { try await j.clear(d) }
        let u = try await j.transition(d, to: .unknown); await fail { try await j.clear(u) }
        let replay = try await j.transition(u, to: .dispatching)
        let ack = try await j.transition(replay, to: .acknowledged, receipt: receipt())
        try await j.clear(ack)
        let newer = try await j.prepare(intent(action: "bag_newer"))
        await fail { try await j.clear(ack) }
        let saved = try await j.read(); XCTAssertEqual(saved, newer)
    }
    func testForgedSnapshotWithoutOriginalBytesOrWithWrongGenerationCannotAdvance() async throws {
        let a = Anchors(), b = Blobs(), j = try store(a, b), p = try await j.prepare(intent())
        let missing = PlayThemeBackpackRecoverySnapshot(value: p.value, generation: p.generation)
        await fail { _ = try await j.transition(missing, to: .dispatching) }
        let stale = PlayThemeBackpackRecoverySnapshot(value: p.value, generation: Data(repeating: 9, count: 32), persistedBytes: p.persistedBytes)
        await fail { _ = try await j.transition(stale, to: .dispatching) }
        let changed = PlayThemeBackpackPending(intent: try intent(action: "bag_changed"), state: .prepared, dispatchProcess: nil, receipt: nil)
        let forged = PlayThemeBackpackRecoverySnapshot(value: changed, generation: p.generation, persistedBytes: p.persistedBytes)
        await fail { _ = try await j.transition(forged, to: .dispatching) }
        let saved = try await j.read(); XCTAssertEqual(saved, p)
    }
    func testConcurrentPrepareHasOneWinnerAndCrossInstanceCASRejectsOldGeneration() async throws {
        let a = Anchors(), b = Blobs(), first = try store(a, b), second = try store(a, b)
        let one = try intent(action: "bag_one"), two = try intent(action: "bag_two")
        let t1 = Task { try? await first.prepare(one) }, t2 = Task { try? await second.prepare(two) }
        let results = await (t1.value, t2.value)
        // A competing read may finish a fully staged reservation before its writer
        // publishes. Both callers may fail, but at most one intent is durable.
        XCTAssertLessThanOrEqual([results.0, results.1].compactMap { $0 }.count, 1)
        let read = try await first.read(), saved = try XCTUnwrap(read)
        XCTAssertTrue(saved.value.intent == one || saved.value.intent == two)
        let anchors = await a.snapshots(), blobs = await b.snapshots()
        XCTAssertEqual(anchors.count, 1); XCTAssertEqual(blobs.count, 1)
        let d = try await first.transition(saved, to: .dispatching)
        await fail { _ = try await second.transition(saved, to: .dispatching) }
        let still = try await first.read(); XCTAssertEqual(still, d)
    }
    func testInterruptedOrPartialCiphertextInsertFailsClosedAfterRestart() async throws {
        for partial in [false, true] {
            let a = Anchors(), b = Blobs(), j = try store(a, b)
            await b.configure(failInsert: !partial, partial: partial)
            await fail { _ = try await j.prepare(self.intent()) }
            await b.configure(); let reopened = try store(a, b)
            await fail { _ = try await reopened.read() }
            await fail { _ = try await reopened.prepare(self.intent(action: "bag_replacement")) }
        }
    }
    func testCorruptCiphertextAnchorAndMissingPresenceNeverLookLikeEmptyStorage() async throws {
        for kind in 0..<4 {
            let a = Anchors(), b = Blobs(), j = try store(a, b); _ = try await j.prepare(intent())
            switch kind {
            case 0: await b.corrupt()
            case 1: await a.corrupt()
            case 2: await a.loseAnchors()
            default: await b.losePresence()
            }
            let reopened = try store(a, b)
            await fail { _ = try await reopened.read() }
            await fail { _ = try await reopened.prepare(self.intent()) }
        }
    }
    func testLockedStorageAndInterruptedPresencePreventPreparation() async throws {
        let a = Anchors(), b = Blobs(), j = try store(a, b)
        await a.configure(locked: true); await fail { _ = try await j.prepare(self.intent()) }
        await a.configure(); await b.interruptAfterPresence()
        await fail { _ = try await j.prepare(self.intent()) }
        let restarted = try store(a, b)
        await fail { _ = try await restarted.read() }
    }
    func testFullyStagedReservationRecoversWithoutReplacingOriginal() async throws {
        let a = Anchors(), b = Blobs(), j = try store(a, b), value = try intent()
        await a.configure(failExchange: true); await fail { _ = try await j.prepare(value) }
        await a.configure()
        let restarted = try store(a, b), read = try await restarted.read(), saved = try XCTUnwrap(read)
        XCTAssertEqual(saved.value.intent, value); XCTAssertEqual(saved.value.state, .prepared)
        await fail { _ = try await restarted.prepare(self.intent(action: "bag_other")) }
    }
    func testInterruptedAcknowledgedClearFinishesAndRetainsEmptyAnchorTombstone() async throws {
        let a = Anchors(), b = Blobs(), j = try store(a, b), d = try await dispatched(j)
        let ack = try await j.transition(d, to: .acknowledged, receipt: receipt())
        await b.configure(failRemove: true); await fail { try await j.clear(ack) }; await b.configure()
        let reopened = try store(a, b), empty = try await reopened.read()
        XCTAssertNil(empty)
        let anchors = await a.snapshots(), blobs = await b.snapshots()
        XCTAssertEqual(anchors.count, 1); XCTAssertTrue(blobs.isEmpty)
        await fail { try await reopened.clear(ack) }
    }
    func testCrossScopeAnchorTransplantCannotExposeOrReplaceAnotherIntent() async throws {
        let a = Anchors(), b = Blobs(), first = try store(a, b), second = try store(a, b, topic: 72)
        _ = try await first.prepare(intent())
        let firstAnchors = await a.snapshots(), anchor = try XCTUnwrap(firstAnchors.first)
        _ = try await second.prepare(intent(topic: 72))
        await a.copyIntoEverySlot(anchor)
        await fail { _ = try await second.read() }
        await fail { _ = try await second.prepare(self.intent(topic: 72)) }
    }
    func testExpandedReceiptFitsIndependentSlotAndOversizeReceiptDoesNotAcknowledge() async throws {
        let a = Anchors(), b = Blobs(), j = try store(a, b), d = try await dispatched(j)
        let tooLarge = try receipt(padding: String(repeating: "x", count: 768 * 1024))
        await fail { _ = try await j.transition(d, to: .acknowledged, receipt: tooLarge) }
        let expanded = try receipt(padding: String(repeating: "x", count: 600 * 1024))
        let ack = try await j.transition(d, to: .acknowledged, receipt: expanded)
        let reopened = try store(a, b), restored = try await reopened.read()
        XCTAssertEqual(restored?.value.receipt, expanded)
        try await j.clear(ack)
    }
}


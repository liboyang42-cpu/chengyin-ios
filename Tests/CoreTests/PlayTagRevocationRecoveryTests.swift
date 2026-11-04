import XCTest
import CryptoKit
@testable import QuestifyCore

/// Synthetic anchors and blobs exercise the real PlayDurableRecovery implementation.
/// No HTTP, OS storage, device acceptance or native execution is claimed by these fixtures.
@MainActor final class PlayTagRevocationRecoveryTests: XCTestCase {
    typealias Anchors = ContentDraftDurableJournalTests.Anchors
    typealias Blobs = ContentDraftDurableJournalTests.Blobs
    private func session(account: Int = 9001, epoch: UInt64 = 1, namespace: String = "synthetic-cn", role: String = "player", token: String = "NEVER-PERSIST-TAG-TOKEN") throws -> PlayExperienceSession {
        try .init(accountID: account, epoch: epoch, namespace: namespace, token: token, role: role)
    }
    private func key(_ session: PlayExperienceSession, topic: Int = 41) -> String {
        PlayRunStorageKey.make(session: session, scope: .topic(topic))
    }
    private func intent(session: PlayExperienceSession? = nil, topic: Int = 41, tag: Int = 701) throws -> PlayTagRevocationIntent {
        try .init(session: session ?? self.session(), topicID: topic, tagID: tag)
    }
    private func journal(_ a: Anchors, _ b: Blobs, session: PlayExperienceSession? = nil, topic: Int = 41) throws -> PlayDurableRecovery {
        let s = try session ?? self.session()
        return try .init(owner: .init(session: s), key: key(s, topic: topic), anchors: a, ciphertexts: b, processID: UUID())
    }
    private func fails(_ operation: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line) async {
        do { try await operation(); XCTFail("Expected fail-closed tag recovery", file: file, line: line) }
        catch { XCTAssertEqual(error as? PlayExperienceError, .persistenceUnavailable, file: file, line: line) }
    }
    private func object(_ intent: PlayTagRevocationIntent) throws -> [String: Any] {
        try XCTUnwrap(PropertyListSerialization.propertyList(from: PropertyListEncoder().encode(intent), format: nil) as? [String: Any])
    }
    private func decode(_ value: [String: Any]) throws -> PlayTagRevocationIntent {
        try PropertyListDecoder().decode(PlayTagRevocationIntent.self, from: PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0))
    }

    func testReconstructionKeepsOriginalMarkerAcrossEpochAndTokenChangeWithoutSecrets() async throws {
        let a = Anchors(), b = Blobs(), first = try session(), original = try intent(), k = key(first)
        let snapshot = try await journal(a, b).recordTagRevocation(original, key: k)
        let fresh = try session(epoch: 9, token: "NEVER-PERSIST-REFRESHED-TAG-TOKEN"), reopened = try journal(a, b, session: fresh)
        XCTAssertEqual(key(fresh), k)
        let restored = try await reopened.readTagRevocation(k)
        XCTAssertEqual(restored, snapshot); XCTAssertEqual(restored?.value.originEpoch, 1)
        try XCTUnwrap(restored).value.validate(session: fresh, topicID: 41)
        await fails { _ = try await reopened.recordTagRevocation(self.intent(session: fresh), key: k) }
        let bytes = try XCTUnwrap(snapshot.persistedBytes), fields = try object(original)
        XCTAssertEqual(Set(fields.keys), Set(["schema", "id", "owner", "originEpoch", "topicID", "tagID"]))
        XCTAssertNil(fields["tagValue"]); XCTAssertNil(fields["token"])
        for secret in [first.token, fresh.token] {
            XCTAssertNil(bytes.range(of: Data(secret.utf8)))
            for anchor in await a.snapshots() { XCTAssertNil(anchor.bytes.range(of: Data(secret.utf8))) }
            for blob in await b.snapshots() { XCTAssertNil(blob.range(of: Data(secret.utf8))) }
        }
        for anchor in await a.snapshots() { XCTAssertNil(anchor.bytes.range(of: Data(original.id.uuidString.utf8))) }
        for blob in await b.snapshots() { XCTAssertNil(blob.range(of: bytes)) }
    }

    func testMalformedSchemaOwnerTopicTagAndMissingFieldsAreRejected() throws {
        let valid = try object(intent())
        for field in ["schema", "id", "owner", "originEpoch", "topicID", "tagID"] {
            var changed = valid; changed[field] = nil
            XCTAssertThrowsError(try decode(changed), "Missing \(field) must not decode")
        }
        for (field, value) in [("schema", 2), ("topicID", 0), ("topicID", -1), ("tagID", 0), ("tagID", -1), ("originEpoch", -1)] {
            var changed = valid; changed[field] = value; XCTAssertThrowsError(try decode(changed))
        }
        for (field, value) in [("namespace", ""), ("role", ""), ("role", String(repeating: "x", count: 129))] {
            var changed = valid, owner = try XCTUnwrap(changed["owner"] as? [String: Any])
            owner[field] = value; changed["owner"] = owner; XCTAssertThrowsError(try decode(changed))
        }
        var changed = valid, owner = try XCTUnwrap(changed["owner"] as? [String: Any])
        owner["accountID"] = 0; changed["owner"] = owner; XCTAssertThrowsError(try decode(changed))
        changed = valid; changed["id"] = "not-a-uuid"; XCTAssertThrowsError(try decode(changed))
        XCTAssertThrowsError(try intent(topic: 0)); XCTAssertThrowsError(try intent(tag: 0))
    }

    func testAuthenticatedButMalformedOrWrongOwnerTopicTagPayloadFailsClosed() async throws {
        for mode in 0..<7 {
            let a = Anchors(), b = Blobs(), j = try journal(a, b), original = try intent(), k = key(try session())
            _ = try await j.recordTagRevocation(original, key: k)
            var changed = try object(original)
            switch mode {
            case 0: changed["schema"] = 2
            case 1: changed["topicID"] = 42
            case 2: changed["tagID"] = 0
            case 3: changed["id"] = nil
            default:
                var owner = try XCTUnwrap(changed["owner"] as? [String: Any])
                if mode == 4 { owner["accountID"] = 9002 }
                if mode == 5 { owner["namespace"] = "other-realm" }
                if mode == 6 { owner["role"] = "merchant" }
                changed["owner"] = owner
            }
            try await replaceAuthenticatedPayload(changed, anchors: a, blobs: b)
            let reopened = try journal(a, b)
            await fails { _ = try await reopened.readTagRevocation(k) }
            await fails { _ = try await reopened.recordTagRevocation(original, key: k) }
        }
    }

    func testTwoViewersCannotOverwriteOrClearDifferentTagBytesOrGeneration() async throws {
        let a = Anchors(), b = Blobs(), one = try journal(a, b), two = try journal(a, b), k = key(try session())
        let first = try await one.recordTagRevocation(intent(), key: k)
        await fails { _ = try await two.recordTagRevocation(first.value, key: k) }
        await fails { _ = try await two.recordTagRevocation(self.intent(tag: 702), key: k) }
        let wrongTag = try intent(tag: 702)
        await fails { try await two.clearTagRevocation(.init(value: wrongTag, generation: first.generation, persistedBytes: first.persistedBytes), key: k) }
        await fails { try await two.clearTagRevocation(.init(value: first.value, generation: first.generation), key: k) }
        try await one.clearTagRevocation(first, key: k)
        let next = try await two.recordTagRevocation(intent(tag: 702), key: k)
        XCTAssertNotEqual(next.generation, first.generation)
        await fails { try await one.clearTagRevocation(first, key: k) }
        await fails { try await one.clearTagRevocation(.init(value: next.value, generation: first.generation, persistedBytes: next.persistedBytes), key: k) }
        await fails { try await one.clearTagRevocation(.init(value: first.value, generation: next.generation, persistedBytes: first.persistedBytes), key: k) }
        let kept = try await one.readTagRevocation(k); XCTAssertEqual(kept, next)
    }

    func testConcurrentWritersHaveOneWinnerAndOneMarker() async throws {
        let a = Anchors(), b = Blobs(), one = try journal(a, b), two = try journal(a, b), k = key(try session())
        let first = try intent(), second = try intent(tag: 702)
        let t1 = Task { try? await one.recordTagRevocation(first, key: k) }
        let t2 = Task { try? await two.recordTagRevocation(second, key: k) }
        let results = await [t1.value, t2.value]
        XCTAssertEqual(results.compactMap { $0 }.count, 1)
        let stored = try await journal(a, b).readTagRevocation(k)
        XCTAssertTrue(stored?.value == first || stored?.value == second)
        let anchors = await a.snapshots(), blobs = await b.snapshots()
        XCTAssertEqual(anchors.count, 1); XCTAssertEqual(blobs.count, 1)
    }

    func testPartialOrMissingBlobAfterReservationCannotLookEmptyOrBeReplaced() async throws {
        for partial in [false, true] {
            let a = Anchors(), b = Blobs(), j = try journal(a, b), k = key(try session())
            await b.configure(failInsert: !partial, partial: partial)
            await fails { _ = try await j.recordTagRevocation(self.intent(), key: k) }
            await b.configure(); let reopened = try journal(a, b)
            await fails { _ = try await reopened.readTagRevocation(k) }
            await fails { _ = try await reopened.recordTagRevocation(self.intent(tag: 702), key: k) }
            let anchors = await a.snapshots(); XCTAssertEqual(anchors.count, 1)
        }
    }

    func testPresenceAndAnchorInsertionInterruptionsStayFailClosed() async throws {
        for afterAnchor in [false, true] {
            let a = Anchors(), b = Blobs(), j = try journal(a, b), k = key(try session())
            if afterAnchor { await a.configure(interrupt: true) } else { await b.interruptAfterPresence() }
            await fails { _ = try await j.recordTagRevocation(self.intent(), key: k) }
            await a.configure(); let reopened = try journal(a, b)
            await fails { _ = try await reopened.readTagRevocation(k) }
            await fails { _ = try await reopened.recordTagRevocation(self.intent(), key: k) }
        }
    }

    func testCompleteStagedBlobRecoversOriginalMarkerWithoutReplacement() async throws {
        let a = Anchors(), b = Blobs(), j = try journal(a, b), original = try intent(), k = key(try session())
        await a.configure(failExchange: true)
        await fails { _ = try await j.recordTagRevocation(original, key: k) }
        await a.configure(); let reopened = try journal(a, b)
        let restored = try await reopened.readTagRevocation(k); XCTAssertEqual(restored?.value, original)
        await fails { _ = try await reopened.recordTagRevocation(self.intent(), key: k) }
    }

    func testLockedCorruptMissingAnchorPresenceAndBlobNeverBecomeFreshStorage() async throws {
        for mode in 0..<6 {
            let a = Anchors(), b = Blobs(), j = try journal(a, b), k = key(try session())
            _ = try await j.recordTagRevocation(intent(), key: k)
            switch mode {
            case 0: await a.configure(locked: true)
            case 1: await a.corrupt()
            case 2: await b.corrupt()
            case 3: await a.loseAnchors()
            case 4: await b.losePresence()
            default: await b.tagRecoveryLoseBlobs()
            }
            let reopened = try journal(a, b)
            await fails { _ = try await reopened.readTagRevocation(k) }
            await fails { _ = try await reopened.recordTagRevocation(self.intent(), key: k) }
        }
    }

    func testFailedClearCASPreservesMarkerAndFailedRemovalRecoversTombstone() async throws {
        let a = Anchors(), b = Blobs(), j = try journal(a, b), k = key(try session())
        let first = try await j.recordTagRevocation(intent(), key: k)
        await a.configure(failExchange: true); await fails { try await j.clearTagRevocation(first, key: k) }
        await a.configure(); let stillHeld = try await journal(a, b).readTagRevocation(k); XCTAssertEqual(stillHeld, first)
        await b.configure(failRemove: true); await fails { try await j.clearTagRevocation(first, key: k) }
        let blocked = try journal(a, b)
        await fails { _ = try await blocked.readTagRevocation(k) }
        await fails { _ = try await blocked.recordTagRevocation(self.intent(), key: k) }
        await b.configure(); let reopened = try journal(a, b), empty = try await reopened.readTagRevocation(k)
        XCTAssertNil(empty)
        let next = try await reopened.recordTagRevocation(intent(tag: 702), key: k)
        await fails { try await reopened.clearTagRevocation(first, key: k) }
        let kept = try await reopened.readTagRevocation(k); XCTAssertEqual(kept, next)
    }

    func testOwnerNamespaceRoleAndTopicIsolationUsesOriginalKey() async throws {
        let a = Anchors(), b = Blobs(), original = try session(), k = key(original), j = try journal(a, b)
        let held = try await j.recordTagRevocation(intent(), key: k)
        for s in [try session(account: 9002), try session(namespace: "other-realm")] {
            let other = try journal(a, b, session: s), otherKey = key(s)
            let empty = try await other.readTagRevocation(otherKey); XCTAssertNil(empty)
            await fails { _ = try await other.recordTagRevocation(held.value, key: otherKey) }
            await fails { try await other.clearTagRevocation(held, key: otherKey) }
        }
        let merchant = try session(role: "merchant"), roleAlias = try journal(a, b, session: merchant)
        XCTAssertEqual(key(merchant), k)
        await fails { _ = try await roleAlias.readTagRevocation(k) }
        await fails { _ = try await roleAlias.recordTagRevocation(self.intent(session: merchant), key: k) }
        await fails { try await roleAlias.clearTagRevocation(held, key: k) }
        let otherTopic = try journal(a, b, topic: 42), topicKey = key(original, topic: 42)
        let empty = try await otherTopic.readTagRevocation(topicKey); XCTAssertNil(empty)
        await fails { _ = try await otherTopic.recordTagRevocation(held.value, key: topicKey) }
        await fails { _ = try await j.readTagRevocation(topicKey) }
        let kept = try await j.readTagRevocation(k); XCTAssertEqual(kept, held)
    }

    func testActivityAndNoncanonicalKeysCannotRecordATopicMarker() async throws {
        let a = Anchors(), b = Blobs(), s = try session(), value = try intent()
        for wrong in [PlayRunStorageKey.make(session: s, scope: .activity(41)), key(s) + ":1", "play.run.v2:012:synthetic-cn4:90017:topicId2:41"] {
            let j = try PlayDurableRecovery(owner: .init(session: s), key: wrong, anchors: a, ciphertexts: b)
            await fails { _ = try await j.recordTagRevocation(value, key: wrong) }
        }
        let anchors = await a.snapshots(), blobs = await b.snapshots(); XCTAssertTrue(anchors.isEmpty); XCTAssertTrue(blobs.isEmpty)
    }

    func testDedicatedSlotDoesNotReduceExistingMaximumBindingLength() async throws {
        let a = Anchors(), b = Blobs(), s = try session(namespace: String(repeating: "x", count: 4049)), k = key(s)
        XCTAssertEqual((k + ":completion").utf8.count, 4096)
        let j = try journal(a, b, session: s)
        let held = try await j.recordTagRevocation(intent(session: s), key: k)
        let restored = try await journal(a, b, session: s).readTagRevocation(k)
        XCTAssertEqual(restored, held)
    }

    func testUnicodeOwnerBindingsAreByteExact() async throws {
        let a = Anchors(), b = Blobs(), nfc = try session(namespace: "é"), nfd = try session(namespace: "e\u{301}")
        let first = try journal(a, b, session: nfc), second = try journal(a, b, session: nfd)
        let held = try await first.recordTagRevocation(intent(session: nfc), key: key(nfc))
        let other = try await second.readTagRevocation(key(nfd)); XCTAssertNil(other)
        await fails { _ = try await second.recordTagRevocation(held.value, key: self.key(nfd)) }
        XCTAssertThrowsError(try held.value.validate(session: nfd, topicID: 41))
        let roleNFC = try session(role: "é"), roleNFD = try session(role: "e\u{301}")
        XCTAssertThrowsError(try intent(session: roleNFC).validate(session: roleNFD, topicID: 41))
    }

    func testAnchorTransplantAndCiphertextRollbackFailClosed() async throws {
        let a = Anchors(), b = Blobs(), j = try journal(a, b), k = key(try session())
        let first = try await j.recordTagRevocation(intent(), key: k)
        let oldBlobs = await b.snapshots(), oldAnchors = await a.snapshots()
        try await j.clearTagRevocation(first, key: k)
        _ = try await j.recordTagRevocation(intent(tag: 702), key: k)
        await b.tagRecoveryReplaceAllBlobs(with: try XCTUnwrap(oldBlobs.first))
        await fails { _ = try await j.readTagRevocation(k) }
        let otherSession = try session(account: 9002), other = try journal(a, b, session: otherSession)
        _ = try await other.recordTagRevocation(intent(session: otherSession), key: key(otherSession))
        await a.copyIntoEverySlot(try XCTUnwrap(oldAnchors.first))
        await fails { _ = try await other.readTagRevocation(self.key(otherSession)) }
    }

    func testInFlightReadRejectsGenerationClearedAndReplacedByOtherViewer() async throws {
        let a = Anchors(), b = Blobs(), one = try journal(a, b), two = try journal(a, b), k = key(try session())
        let first = try await one.recordTagRevocation(intent(), key: k)
        await b.pauseRead(); let reading = Task { try await one.readTagRevocation(k) }
        for _ in 0..<1_000 { if await b.isReadSuspended() { break }; await Task.yield() }
        let suspended = await b.isReadSuspended(); XCTAssertTrue(suspended)
        try await two.clearTagRevocation(first, key: k)
        let next = try await two.recordTagRevocation(intent(tag: 702), key: k)
        await b.resumeRead(); await fails { _ = try await reading.value }
        let kept = try await one.readTagRevocation(k); XCTAssertEqual(kept, next)
    }

    func testTagSlotRecordFailureAndClearLeaveOtherThreeSlotsUnchanged() async throws {
        let a = Anchors(), b = Blobs(), s = try session(), k = key(s), j = try journal(a, b)
        let completionIntent = PlayCompletionIntent(review: .init(nodeID: 701, evidence: .answer("synthetic answer"), advance: nil, session: s, generation: 1, routeSessionID: nil))
        let completion = try await j.prepare(completionIntent, key: k)
        let pausedEmpty = try await j.read(key: k)
        let paused = try await j.write(.init(owner: .init(session: s), record: .init(elapsedSeconds: 12, savedAt: 100)), replacing: pausedEmpty, key: k)
        let command = try PlayPlayerCommand(activityID: 41, nodeID: 701, requestID: "synthetic-command", expectedRevision: 4, action: .choice, payload: ["choiceId": .string("LEFT")])
        let game = try await j.recordGameCommand(.init(command: command, session: s, sessionID: 501), key: k)
        let before = await a.tagRecoveryAnchorMap()
        await b.configure(failInsert: true)
        await fails { _ = try await j.recordTagRevocation(self.intent(), key: k) }
        await b.configure()
        let reopened = try journal(a, b), after = await a.tagRecoveryAnchorMap()
        for (slot, anchor) in before { XCTAssertEqual(after[slot], anchor) }
        let c = try await reopened.read(k), p = try await reopened.read(key: k), g = try await reopened.readGameCommand(k)
        XCTAssertEqual(c, completion); XCTAssertEqual(p, paused); XCTAssertEqual(g, game)
        await fails { _ = try await reopened.readTagRevocation(k) }

        // A separate healthy fixture verifies successful tag clear also touches no other slot.
        let x = Anchors(), y = Blobs(), clean = try journal(x, y)
        let existing = try await clean.prepare(completionIntent, key: k)
        let emptyPause = try await clean.read(key: k)
        let existingPause = try await clean.write(.init(owner: .init(session: s), record: .init(elapsedSeconds: 12, savedAt: 100)), replacing: emptyPause, key: k)
        let existingGame = try await clean.recordGameCommand(.init(command: command, session: s, sessionID: 501), key: k)
        let originalAnchors = await x.tagRecoveryAnchorMap()
        let marker = try await clean.recordTagRevocation(intent(), key: k)
        try await clean.clearTagRevocation(marker, key: k)
        let finalAnchors = await x.tagRecoveryAnchorMap()
        for (slot, anchor) in originalAnchors { XCTAssertEqual(finalAnchors[slot], anchor) }
        let untouched = try await clean.read(k), untouchedPause = try await clean.read(key: k), untouchedGame = try await clean.readGameCommand(k)
        XCTAssertEqual(untouched, existing); XCTAssertEqual(untouchedPause, existingPause); XCTAssertEqual(untouchedGame, existingGame)
    }

    func testSyntheticAdapterUsesSameKeyAndExactGenerationWithoutOverwrite() async throws {
        let j = PlayMemoryTagRevocationRecovery(), s = try session(), k = key(s), original = try intent()
        let first = try await j.recordTagRevocation(original, key: k)
        await fails { _ = try await j.recordTagRevocation(original, key: k) }
        await fails { _ = try await j.recordTagRevocation(original, key: self.key(s, topic: 42)) }
        try await j.clearTagRevocation(first, key: k)
        let next = try await j.recordTagRevocation(intent(tag: 702), key: k)
        await fails { try await j.clearTagRevocation(first, key: k) }
        let kept = try await j.readTagRevocation(k); XCTAssertEqual(kept, next)
    }

    func testUnavailableAdapterNeverLooksEmptyOrRecordsOrClears() async throws {
        let j = PlayUnavailableTagRevocationRecovery(), original = try intent(), k = key(try session())
        await fails { _ = try await j.readTagRevocation(k) }
        await fails { _ = try await j.recordTagRevocation(original, key: k) }
        await fails { try await j.clearTagRevocation(.init(value: original, generation: Data()), key: k) }
    }

    /// Fixture-only rewrite preserves valid AES-GCM and anchor digest, so reads must reject
    /// invalid intent data rather than relying only on ciphertext authentication failure.
    private func replaceAuthenticatedPayload(_ value: [String: Any], anchors: Anchors, blobs: Blobs) async throws {
        let stored = await anchors.tagRecoveryAnchorMap(), entry = try XCTUnwrap(stored.first)
        var anchor = try XCTUnwrap(PropertyListSerialization.propertyList(from: entry.value.bytes, format: nil) as? [String: Any])
        let name = try XCTUnwrap(anchor["blob"] as? String), secret = try XCTUnwrap(anchor["key"] as? Data)
        let binding = try XCTUnwrap(anchor["binding"] as? Data)
        let plaintext = try PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0)
        let sealed = try AES.GCM.seal(plaintext, using: SymmetricKey(data: secret), authenticating: binding + Data(name.utf8))
        anchor["digest"] = Data(SHA256.hash(data: plaintext))
        let encoded = try PropertyListSerialization.data(fromPropertyList: anchor, format: .binary, options: 0)
        await blobs.tagRecoveryReplaceBlob(name: name, bytes: try XCTUnwrap(sealed.combined))
        await anchors.tagRecoveryReplaceAnchor(slot: entry.key, item: .init(bytes: encoded, tag: entry.value.tag))
    }
}

extension ContentDraftDurableJournalTests.Anchors {
    func tagRecoveryAnchorMap() -> [String: ContentDraftAnchorItem] { items }
    func tagRecoveryReplaceAnchor(slot: String, item: ContentDraftAnchorItem) { items[slot] = item }
}
extension ContentDraftDurableJournalTests.Blobs {
    func tagRecoveryLoseBlobs() { values.removeAll() }
    func tagRecoveryReplaceBlob(name: String, bytes: Data) { values[name] = bytes }
    func tagRecoveryReplaceAllBlobs(with bytes: Data) { for name in values.keys { values[name] = bytes } }
}

import XCTest
@testable import QuestifyCore

/// Entirely synthetic actor stores. No Security API, real account, filesystem, or HTTP.
@MainActor final class ContentDraftDurableJournalTests: XCTestCase {
    struct Payload: Codable, Equatable { let title: String }
    actor Anchors: ContentDraftAnchorStore {
        var items: [String: ContentDraftAnchorItem] = [:]
        var locked = false, failExchange = false, interruptAfterInsert = false
        var substituteAtExchange: ContentDraftAnchorItem?
        var substituteAtRemove: ContentDraftAnchorItem?
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
        func remove(slot: String, matchingTag: Data) throws -> Bool {
            if locked { throw ContentDraftIssue.storageUnavailable }
            if let replacement = substituteAtRemove { items[slot] = replacement; substituteAtRemove = nil }
            guard items[slot]?.tag == matchingTag else { return false }; items[slot] = nil; return true
        }
        func configure(locked: Bool = false, failExchange: Bool = false, interrupt: Bool = false) {
            self.locked = locked; self.failExchange = failExchange; interruptAfterInsert = interrupt
        }
        func corrupt() { for key in items.keys { items[key] = .init(bytes: Data([0]), tag: Data(repeating: 0, count: 32)) } }
        func snapshots() -> [ContentDraftAnchorItem] { Array(items.values) }
        func loseAnchors() { items.removeAll() }
        func replaceOnExchange(_ item: ContentDraftAnchorItem) { substituteAtExchange = item }
        func replaceOnRemove(_ item: ContentDraftAnchorItem) { substituteAtRemove = item }
        func copyIntoEverySlot(_ item: ContentDraftAnchorItem) { for key in items.keys { items[key] = item } }
    }
    actor Blobs: ContentDraftCiphertextStore {
        var values: [String: Data] = [:]
        var presence: Set<String> = []
        var interruptPresence = false
        func hasPresence(slot: String) -> Bool { presence.contains(slot) }
        func createPresence(slot: String) throws -> Bool {
            let inserted = presence.insert(slot).inserted
            if interruptPresence { throw ContentDraftIssue.storageUnavailable }; return inserted
        }
        func interruptAfterPresence() { interruptPresence = true }
        func losePresence() { presence.removeAll() }
        var failInsert = false, partialInsert = false, failRemove = false
        func insert(name: String, bytes: Data) throws {
            guard values[name] == nil else { throw ContentDraftIssue.storageUnavailable }
            if partialInsert { values[name] = Data(bytes.prefix(10)); throw ContentDraftIssue.storageUnavailable }
            if failInsert { throw ContentDraftIssue.storageUnavailable }; values[name] = bytes
        }
        private var pauseNextRead = false
        private var waitingRead: CheckedContinuation<Void, Never>?
        func pauseRead() { pauseNextRead = true }
        func isReadSuspended() -> Bool { waitingRead != nil }
        func resumeRead() { let saved = waitingRead; waitingRead = nil; saved?.resume() }
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
        func corrupt() { for key in values.keys { values[key] = Data([1, 2, 3]) } }
        func snapshots() -> [Data] { Array(values.values) }
    }
    private func context(account: Int = 7, namespace: String = "synthetic-realm", endpoint: String = "https://fixture.invalid/api", role: String = "player", epoch: UInt64 = 1) throws -> RuntimeDependencyContext {
        .init(market: .china, baseURL: URL(string: endpoint)!, role: role,
              session: try .init(accountID: account, epoch: epoch, namespace: namespace, token: "synthetic-token"))
    }
    private func identity(owner: Int64 = 7, key: String = "synthetic-key", scope: ContentDraftOwnerScope = .personal) throws -> ContentDraftIdentity {
        try .init(ownerMemberID: owner, businessType: .topic, clientDraftKey: key, scope: scope)
    }
    private func mutation(_ identity: ContentDraftIdentity, title: String = "synthetic secret") throws -> ContentDraftPending {
        .init(mutation: try .save(payload: Payload(title: title), identity: identity, subjectID: nil, deviceID: "synthetic-device", baseline: nil))
    }
    private func journal(_ anchors: Anchors, _ blobs: Blobs, context: RuntimeDependencyContext? = nil,
                         identity: ContentDraftIdentity? = nil) throws -> ContentDraftDurableJournal {
        try .init(scope: .init(context: context ?? self.context(), identity: identity ?? self.identity()), anchors: anchors, ciphertexts: blobs)
    }
    private func fails(_ operation: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line) async {
        do { try await operation(); XCTFail("Expected fail-closed storage", file: file, line: line) }
        catch { XCTAssertEqual(error as? ContentDraftIssue, .storageUnavailable, file: file, line: line) }
    }
    func testRestartKeepsExactCommandAndPossiblyDispatchedFlag() async throws {
        let a = Anchors(), b = Blobs(), j = try journal(a, b), pending = try mutation(identity())
        let initial = try await j.insert(pending)
        let dispatched = ContentDraftPending(mutation: pending.mutation, dispatched: true)
        _ = try await j.replace(initial, with: dispatched)
        let reopened = try journal(a, b), restored = try await reopened.read()
        XCTAssertEqual(restored?.value, dispatched)
        try await reopened.clear(matching: XCTUnwrap(restored))
        let empty = try await reopened.read(), files = await b.snapshots(), anchors = await a.snapshots()
        XCTAssertNil(empty); XCTAssertTrue(files.isEmpty); XCTAssertEqual(anchors.count, 1)
    }
    func testInsertOnlySameIDChangedPayloadAndDifferentOperationCannotOverwrite() async throws {
        let a = Anchors(), b = Blobs(), j = try journal(a, b), pending = try mutation(identity())
        let ticket = try await j.insert(pending); _ = try await j.insert(pending)
        let changed = try mutation(identity(), title: "different"), second = try journal(a, b)
        await fails { _ = try await second.insert(changed) }
        var object = try XCTUnwrap(PropertyListSerialization.propertyList(from: PropertyListEncoder().encode(pending.mutation), format: nil) as? [String: Any])
        var command = try XCTUnwrap(object["command"] as? [String: Any]); command["payloadJson"] = "{\"title\":\"changed same ID\"}"; object["command"] = command
        let sameID = try PropertyListDecoder().decode(ContentDraftMutation.self, from: PropertyListSerialization.data(fromPropertyList: object, format: .binary, options: 0))
        await fails { _ = try await j.clear(matching: .init(value: .init(mutation: sameID), generation: ticket.generation)) }
        let kept = try await j.read(); XCTAssertEqual(kept?.value, pending)
    }
    func testConcurrentDistinctWritersHaveExactlyOneWinner() async throws {
        let a = Anchors(), b = Blobs(), first = try journal(a, b), second = try journal(a, b)
        let one = try mutation(identity()), two = try mutation(identity(), title: "second")
        let t1 = Task { try? await first.insert(one) }, t2 = Task { try? await second.insert(two) }
        _ = await (t1.value, t2.value)
        let stored = try await journal(a, b).read(), files = await b.snapshots(), anchors = await a.snapshots()
        XCTAssertTrue(stored?.value == one || stored?.value == two); XCTAssertEqual(files.count, 1); XCTAssertEqual(anchors.count, 1)
    }
    func testSameOwnerRoleAliasesShareOneSlotWithoutRebindingCommand() async throws {
        let a = Anchors(), b = Blobs(), j = try journal(a, b), pending = try mutation(identity())
        try await j.insert(pending)
        for scope in [ContentDraftOwnerScope.club, .merchant] {
            let alias = try journal(a, b, context: context(role: "merchant", epoch: 2), identity: identity(scope: scope))
            let restored = try await alias.read(); XCTAssertEqual(restored?.value, pending)
            await fails { _ = try await alias.insert(self.mutation(self.identity(scope: scope))) }
        }
        let anchors = await a.snapshots(); XCTAssertEqual(anchors.count, 1)
    }
    func testAccountDeploymentOwnerTargetAndRawUnicodeBytesAreIsolated() async throws {
        let a = Anchors(), b = Blobs(), base = try journal(a, b), pending = try mutation(identity())
        try await base.insert(pending)
        let variants: [(RuntimeDependencyContext, ContentDraftIdentity)] = [
            (try context(account: 8), try identity()), (try context(namespace: "other"), try identity()),
            (try context(endpoint: "https://fixture.invalid/other"), try identity()),
            (try context(), try identity(owner: 8)), (try context(), try identity(key: "other"))]
        for (c, i) in variants { let value = try await journal(a, b, context: c, identity: i).read(); XCTAssertNil(value) }
        let nfc = try journal(a, b, context: context(namespace: "é")), nfd = try journal(a, b, context: context(namespace: "e\u{301}"))
        try await nfc.insert(pending); let different = try await nfd.read(); XCTAssertNil(different)
    }
    func testCrossScopeAnchorTransplantFailsClosed() async throws {
        let a = Anchors(), b = Blobs(), j = try journal(a, b), pending = try mutation(identity())
        let ticket = try await j.insert(pending); let snapshot = await a.snapshots(); let first = try XCTUnwrap(snapshot.first)
        let other = try journal(a, b, context: context(account: 8)); try await other.insert(pending)
        await a.copyIntoEverySlot(first)
        await fails { _ = try await other.read() }
    }
    func testInterruptedReservationAndPartialBlobNeverUnlock() async throws {
        for partial in [false, true] {
            let a = Anchors(), b = Blobs(), pending = try mutation(identity()), j = try journal(a, b)
            await b.configure(failInsert: !partial, partial: partial)
            await fails { _ = try await j.insert(pending) }
            await b.configure()
            let reopened = try journal(a, b)
            await fails { _ = try await reopened.read() }
            await fails { _ = try await reopened.insert(pending) }
            let anchors = await a.snapshots(); XCTAssertEqual(anchors.count, 1)
        }
    }
    func testAmbiguousAnchorInsertionRetainsReservationWithoutBlob() async throws {
        let a = Anchors(), b = Blobs(), pending = try mutation(identity()), j = try journal(a, b)
        await a.configure(interrupt: true); await fails { _ = try await j.insert(pending) }; await a.configure()
        await fails { _ = try await self.journal(a, b).read() }
        let anchors = await a.snapshots(), files = await b.snapshots(); XCTAssertEqual(anchors.count, 1); XCTAssertTrue(files.isEmpty)
    }
    func testCompleteStagedBlobRecoversAfterCrashBeforeReadyCAS() async throws {
        let a = Anchors(), b = Blobs(), pending = try mutation(identity()), j = try journal(a, b)
        await a.configure(failExchange: true); await fails { _ = try await j.insert(pending) }; await a.configure()
        let restored = try await journal(a, b).read(); XCTAssertEqual(restored?.value, pending)
    }
    func testLockedCorruptAnchorAndCorruptCiphertextPreserveLocks() async throws {
        for mode in 0..<3 {
            let a = Anchors(), b = Blobs(), pending = try mutation(identity()), j = try journal(a, b)
            let ticket = try await j.insert(pending)
            if mode == 0 { await a.configure(locked: true) }
            if mode == 1 { await a.corrupt() }
            if mode == 2 { await b.corrupt() }
            await fails { _ = try await j.read() }; await fails { _ = try await j.clear(matching: ticket) }
            let anchors = await a.snapshots(); XCTAssertEqual(anchors.count, 1)
        }
    }
    func testStaleGenerationCannotClearIdenticalReinsertedValue() async throws {
        let a = Anchors(), b = Blobs(), pending = try mutation(identity()), stale = try journal(a, b), current = try journal(a, b)
        let staleTicket = try await stale.insert(pending), currentTicket = try await current.read()
        try await current.clear(matching: XCTUnwrap(currentTicket))
        _ = try await current.insert(pending)
        await fails { _ = try await stale.clear(matching: staleTicket) }
        let restored = try await current.read(); XCTAssertEqual(restored?.value, pending)
    }
    func testReplacementBetweenReadAndCASCannotClearNewGeneration() async throws {
        let a = Anchors(), b = Blobs(), pending = try mutation(identity()), j = try journal(a, b)
        let ticket = try await j.insert(pending); let snapshot = await a.snapshots(); let old = try XCTUnwrap(snapshot.first)
        let replacement = ContentDraftAnchorItem(bytes: old.bytes, tag: Data(repeating: 0x42, count: 32))
        await a.replaceOnExchange(replacement)
        await fails { _ = try await j.clear(matching: ticket) }
        let items = await a.snapshots(), files = await b.snapshots(); XCTAssertEqual(items, [replacement]); XCTAssertEqual(files.count, 1)
    }
    func testClearTombstoneResumesCleanupAfterCrash() async throws {
        let a = Anchors(), b = Blobs(), pending = try mutation(identity()), j = try journal(a, b)
        let ticket = try await j.insert(pending); await b.configure(failRemove: true)
        await fails { _ = try await j.clear(matching: ticket) }; await b.configure()
        let empty = try await journal(a, b).read(), files = await b.snapshots(), anchors = await a.snapshots()
        XCTAssertNil(empty); XCTAssertTrue(files.isEmpty); XCTAssertEqual(anchors.count, 1)
    }
    func testMissingAnchorsWithRestoredFilesAndPresenceNeverBecomeFreshSlot() async throws {
        let a = Anchors(), b = Blobs(), pending = try mutation(identity()), j = try journal(a, b)
        _ = try await j.insert(pending); await a.loseAnchors()
        let restored = try journal(a, b)
        await fails { _ = try await restored.read() }
        await fails { _ = try await restored.insert(pending) }
        let files = await b.snapshots(); XCTAssertEqual(files.count, 1)
    }
    func testCrashAfterPresenceBeforeAnchorFailsClosed() async throws {
        let a = Anchors(), b = Blobs(), pending = try mutation(identity()), j = try journal(a, b)
        await b.interruptAfterPresence(); await fails { _ = try await j.insert(pending) }
        await fails { _ = try await self.journal(a, b).read() }
        let anchors = await a.snapshots(); XCTAssertTrue(anchors.isEmpty)
    }
    func testClearedSlotCanBeReusedOnlyWithMatchingEmptyAnchor() async throws {
        let a = Anchors(), b = Blobs(), pending = try mutation(identity()), j = try journal(a, b)
        let ticket = try await j.insert(pending); try await j.clear(matching: ticket)
        let next = try await j.insert(mutation(identity(), title: "next")); XCTAssertNotEqual(next.generation, ticket.generation)
        try await j.clear(matching: next); await a.loseAnchors()
        await fails { _ = try await self.journal(a, b).read() }
    }
    func testLargePayloadIsEncryptedFileAndSmallSecretAnchor() async throws {
        let a = Anchors(), b = Blobs(), j = try journal(a, b)
        let pending = try mutation(identity(), title: String(repeating: "x", count: 500_000))
        try await j.insert(pending)
        let files = await b.snapshots(), anchors = await a.snapshots(), restored = try await journal(a, b).read()
        XCTAssertEqual(restored?.value, pending); XCTAssertEqual(files.count, 1)
        XCTAssertGreaterThan(files[0].count, 500_000); XCTAssertLessThan(anchors[0].bytes.count, 8_192)
        XCTAssertNil(files[0].range(of: Data(String(repeating: "x", count: 128).utf8)))
        XCTAssertNil(anchors[0].bytes.range(of: Data("synthetic secret".utf8)))
        XCTAssertEqual(anchors[0].tag.count, 32)
    }
    private final class SuspendedService: ContentDraftServing {
        var entered: (() -> Void)?
        var continuation: CheckedContinuation<ContentDraftRecord, Error>?
        var calls = 0
        func restore(id: Int64, identity: ContentDraftIdentity) async throws -> ContentDraftRecord { throw ContentDraftIssue.unavailable }
        func list(type: ContentDraftBusinessType?) async throws -> [ContentDraftRecord] { throw ContentDraftIssue.unavailable }
        func mutate(_ attempt: ContentDraftPreparedDispatch) async throws -> ContentDraftRecord {
            calls += 1
            return try await withCheckedThrowingContinuation { continuation = $0; entered?() }
        }
        func fail(_ issue: ContentDraftIssue) { let saved = continuation; continuation = nil; saved?.resume(throwing: issue) }
    }
    func testCompetingCoordinatorsCannotAdoptAndClearOtherAttemptGeneration() async throws {
        for sharedJournal in [true, false] {
            let a = Anchors(), b = Blobs(), firstJournal = try journal(a, b), c = try context(), i = try identity()
            let secondJournal = try (sharedJournal ? firstJournal : journal(a, b))
            let firstService = SuspendedService(), secondService = SuspendedService()
            let first = ContentDraftCoordinator<Payload>(identity: i, service: firstService,
                lease: ContentDraftSessionLease(context: c, current: { c }), journal: firstJournal)
            let second = ContentDraftCoordinator<Payload>(identity: i, service: secondService,
                lease: ContentDraftSessionLease(context: c, current: { c }), journal: secondJournal)
            await first.initialize(); first.prepareSave(.init(title: "synthetic"), subjectID: nil, deviceID: "synthetic-device")
            let firstEntered = expectation(description: "first HTTP"); firstService.entered = { firstEntered.fulfill() }
            let firstTask = Task { await first.confirm() }; await fulfillment(of: [firstEntered], timeout: 2)
            await second.initialize()
            let secondEntered = expectation(description: "second HTTP"); secondService.entered = { secondEntered.fulfill() }
            let secondTask = Task { await second.retryExact() }; await fulfillment(of: [secondEntered], timeout: 2)
            let secondSnapshot = try await secondJournal.read()
            firstService.fail(.forbidden); await firstTask.value
            let keptDuringSecondHTTP = try await secondJournal.read()
            XCTAssertEqual(keptDuringSecondHTTP, secondSnapshot); XCTAssertEqual(first.phase, .unknown)
            secondService.fail(.unknownOutcome); await secondTask.value
            let retained = try await secondJournal.read(); XCTAssertEqual(retained, secondSnapshot)
            XCTAssertEqual(second.phase, .unknown); XCTAssertEqual(firstService.calls, 1); XCTAssertEqual(secondService.calls, 1)
        }
    }
    private final class VerificationGate: ContentDraftSecureJournal {
        let base: ContentDraftDurableJournal
        var scope: ContentDraftJournalScope { base.scope }
        var blockNextRead = false
        var reached: (() -> Void)?
        var waiting: CheckedContinuation<Void, Never>?
        init(_ base: ContentDraftDurableJournal) { self.base = base }
        func read() async throws -> ContentDraftJournalSnapshot? {
            if blockNextRead { blockNextRead = false; await withCheckedContinuation { waiting = $0; reached?() } }
            return try await base.read()
        }
        func insert(_ value: ContentDraftPending) async throws -> ContentDraftJournalSnapshot { try await base.insert(value) }
        func replace(_ old: ContentDraftJournalSnapshot, with new: ContentDraftPending) async throws -> ContentDraftJournalSnapshot {
            let snapshot = try await base.replace(old, with: new); blockNextRead = true; return snapshot
        }
        func clear(matching snapshot: ContentDraftJournalSnapshot) async throws { try await base.clear(matching: snapshot) }
        func resume() { let saved = waiting; waiting = nil; saved?.resume() }
    }
    func testGenerationAdvanceBeforeVerificationReadSendsZeroFirstHTTP() async throws {
        for sharedJournal in [true, false] {
            let a = Anchors(), b = Blobs(), base = try journal(a, b), gate = VerificationGate(base)
            let c = try context(), i = try identity(), firstService = SuspendedService(), secondService = SuspendedService()
            let first = ContentDraftCoordinator<Payload>(identity: i, service: firstService,
                lease: ContentDraftSessionLease(context: c, current: { c }), journal: gate)
            let secondJournal = try (sharedJournal ? base : journal(a, b))
            let second = ContentDraftCoordinator<Payload>(identity: i, service: secondService,
                lease: ContentDraftSessionLease(context: c, current: { c }), journal: secondJournal)
            await first.initialize(); first.prepareSave(.init(title: "synthetic"), subjectID: nil, deviceID: "synthetic-device")
            let blocked = expectation(description: "post replace read"); gate.reached = { blocked.fulfill() }
            let firstTask = Task { await first.confirm() }; await fulfillment(of: [blocked], timeout: 2)
            await second.initialize()
            let entered = expectation(description: "second HTTP"); secondService.entered = { entered.fulfill() }
            let secondTask = Task { await second.retryExact() }; await fulfillment(of: [entered], timeout: 2)
            let ownedBySecond = try await secondJournal.read()
            gate.resume(); await firstTask.value
            XCTAssertEqual(firstService.calls, 0); XCTAssertEqual(first.phase, .unknown)
            let retained = try await secondJournal.read(); XCTAssertEqual(retained, ownedBySecond)
            secondService.fail(.unknownOutcome); await secondTask.value
        }
    }
    func testMissingPresenceWithSurvivingAnchorFailsClosed() async throws {
        let a = Anchors(), b = Blobs(), j = try journal(a, b), pending = try mutation(identity())
        let ticket = try await j.insert(pending); await b.losePresence()
        await fails { _ = try await j.read() }
        await fails { _ = try await j.replace(ticket, with: .init(mutation: pending.mutation, dispatched: true)) }
        await fails { try await j.clear(matching: ticket) }
        let anchors = await a.snapshots(); XCTAssertEqual(anchors.count, 1)
    }
    func testExactNativePayloadLimitAndOversizeFailBeforeStorage() async throws {
        let overhead = try ContentDraftDocument<Payload>.encode(Payload(title: "")).utf8.count
        let title = String(repeating: "x", count: 524_288 - overhead), i = try identity()
        let pending = try mutation(i, title: title)
        XCTAssertEqual(pending.mutation.command.payloadJson?.utf8.count, 524_288)
        let a = Anchors(), b = Blobs(), j = try journal(a, b)
        _ = try await j.insert(pending)
        let stored = try await j.read(); XCTAssertEqual(stored?.value, pending)
        XCTAssertThrowsError(try mutation(i, title: title + "x"))
        let anchors = await a.snapshots(), files = await b.snapshots(); XCTAssertEqual(anchors.count, 1); XCTAssertEqual(files.count, 1)
    }
    private final class Service: ContentDraftServing {
        var calls = 0
        func restore(id: Int64, identity: ContentDraftIdentity) async throws -> ContentDraftRecord { calls += 1; throw ContentDraftIssue.unavailable }
        func list(type: ContentDraftBusinessType?) async throws -> [ContentDraftRecord] { calls += 1; throw ContentDraftIssue.unavailable }
        func mutate(_ attempt: ContentDraftPreparedDispatch) async throws -> ContentDraftRecord { calls += 1; throw ContentDraftIssue.unknownOutcome }
    }
    func testInterruptedSaveLockedAndCorruptStorageProduceZeroHTTP() async throws {
        for mode in 0..<3 {
            let a = Anchors(), b = Blobs(), j = try journal(a, b), c = try context(), service = Service()
            let coordinator = ContentDraftCoordinator<Payload>(identity: try identity(), initialPayload: .init(title: "synthetic"),
                service: service, lease: ContentDraftSessionLease(context: c, current: { c }), journal: j)
            await coordinator.initialize(); coordinator.prepareSave(.init(title: "synthetic"), subjectID: nil, deviceID: "synthetic-device")
            if mode == 0 { await b.configure(partial: true) }
            if mode == 1 { await a.configure(locked: true) }
            if mode == 2 { try await j.insert(mutation(identity())); await a.corrupt() }
            await coordinator.confirm(); XCTAssertEqual(service.calls, 0); XCTAssertEqual(coordinator.phase, .blocked)
        }
    }
    /// Device-local stores are intentionally independent. This is not server arbitration or migration proof.
    func testIndependentDeviceStoresRetainSeparateSameTargetUncertainty() async throws {
        let firstAnchors = Anchors(), firstBlobs = Blobs(), secondAnchors = Anchors(), secondBlobs = Blobs()
        let first = try journal(firstAnchors, firstBlobs), second = try journal(secondAnchors, secondBlobs)
        let firstPending = try mutation(identity(), title: "device one"), secondPending = try mutation(identity(), title: "device two")
        let firstInitial = try await first.insert(firstPending), secondInitial = try await second.insert(secondPending)
        let firstSent = try await first.replace(firstInitial, with: .init(mutation: firstPending.mutation, dispatched: true))
        let secondSent = try await second.replace(secondInitial, with: .init(mutation: secondPending.mutation, dispatched: true))
        XCTAssertNotEqual(firstPending.mutation.operationID, secondPending.mutation.operationID)
        XCTAssertNotEqual(firstSent.generation, secondSent.generation)
        try await first.clear(matching: firstSent)
        let firstRead = try await first.read(), secondRead = try await second.read()
        XCTAssertNil(firstRead); XCTAssertEqual(secondRead, secondSent)
        let reopened = try journal(secondAnchors, secondBlobs), recovered = try await reopened.read()
        XCTAssertEqual(recovered, secondSent)
    }
    func testMaximumUnicodeCommandAndBaselineFitEncryptedBlobBound() async throws {
        let overhead = try ContentDraftDocument<Payload>.encode(Payload(title: "")).utf8.count
        let suffix = String(repeating: "x", count: 524_288 - overhead - 2)
        let oldPayload = try ContentDraftDocument<Payload>.encode(Payload(title: "é" + suffix))
        let object: [String: Any] = ["id": 19, "ownerMemberId": 7, "businessType": "TOPIC", "clientDraftKey": "synthetic-key",
            "payloadJson": oldPayload, "payloadHash": ContentDraftRecord.hash(oldPayload), "status": "DRAFT",
            "version": 1, "updatedByDevice": "synthetic-device"]
        let baseline = try JSONDecoder().decode(ContentDraftRecord.self, from: JSONSerialization.data(withJSONObject: object))
        let pending = ContentDraftPending(mutation: try .save(payload: Payload(title: "ø" + suffix), identity: identity(),
            subjectID: nil, deviceID: "synthetic-device", baseline: baseline))
        XCTAssertEqual(pending.mutation.baseline?.payloadJson.utf8.count, 524_288)
        XCTAssertEqual(pending.mutation.command.payloadJson?.utf8.count, 524_288)
        let a = Anchors(), b = Blobs(), j = try journal(a, b)
        let original = try await j.insert(pending), recovered = try await journal(a, b).read()
        XCTAssertEqual(recovered, original)
        let files = await b.snapshots(), anchors = await a.snapshots()
        XCTAssertEqual(files.count, 1); XCTAssertEqual(anchors.count, 1)
        XCTAssertLessThanOrEqual(try XCTUnwrap(files.first).count, 4_194_304)
        XCTAssertLessThanOrEqual(try XCTUnwrap(anchors.first).bytes.count, 8_192)
    }
    func testRestoredMissingAnchorMarkerOrBlobBlocksBeforeAnyHTTP() async throws {
        for missing in ["anchor", "marker", "blob"] {
            let a = Anchors(), b = Blobs(), j = try journal(a, b), pending = try mutation(identity())
            _ = try await j.insert(pending)
            if missing == "anchor" { await a.loseAnchors() }
            if missing == "marker" { await b.losePresence() }
            if missing == "blob" {
                let values = await b.values
                for name in values.keys { try await b.removeDurably(name: name) }
            }
            let c = try context(), service = Service(), reopened = try journal(a, b)
            let coordinator = ContentDraftCoordinator<Payload>(identity: try identity(), initialPayload: .init(title: "startup"),
                service: service, lease: ContentDraftSessionLease(context: c, current: { c }), journal: reopened)
            await coordinator.initialize()
            coordinator.prepareSave(.init(title: "replacement"), subjectID: nil, deviceID: "synthetic-device")
            await coordinator.confirm(); await coordinator.retryExact()
            XCTAssertEqual(coordinator.phase, .blocked); XCTAssertEqual(coordinator.issue, .storageUnavailable)
            XCTAssertFalse(coordinator.canPrepare); XCTAssertFalse(coordinator.canRetryExact); XCTAssertEqual(service.calls, 0)
        }
    }
    func testRestartAliasCoordinatorBlocksWithoutHTTP() async throws {
        let a = Anchors(), b = Blobs(), j = try journal(a, b), c = try context(), service = Service()
        try await j.insert(mutation(identity()))
        let alias = try identity(scope: .club)
        let coordinator = ContentDraftCoordinator<Payload>(identity: alias, service: service,
            lease: ContentDraftSessionLease(context: c, current: { c }), journal: try journal(a, b, identity: alias))
        await coordinator.initialize(); XCTAssertEqual(coordinator.phase, .blocked); XCTAssertEqual(service.calls, 0)
    }
}

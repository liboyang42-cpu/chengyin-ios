import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// I02 / BK-SESSION: the exact game-session envelope survives a coordinator rebuild or process
/// restart and is read back by its original key. Sanitized A01 fixture values: requestId
/// a01-ready-71, expectedRevision 4 -> APPLIED revision 5, receiptId 501.
@available(macOS 14.0, *)
@MainActor final class PlayGameCommandJournalTests: XCTestCase {
    typealias Anchors = PlayDurableRecoveryTests.Anchors
    typealias Blobs = PlayDurableRecoveryTests.Blobs
    @MainActor private final class Owner {
        var session: PlayExperienceSession?
        init(_ session: PlayExperienceSession) { self.session = session }
    }
    private func session(account: Int = 7, epoch: UInt64 = 1, namespace: String = "synthetic-cn", token: String = "synthetic-token") throws -> PlayExperienceSession {
        try .init(accountID: account, epoch: epoch, namespace: namespace, token: token)
    }
    private func service(_ wire: JournalWire, enabled: Set<PlayExperienceCapability> = [.reads, .playerCommands]) throws -> PlayExperienceService {
        .init(configuration: try .init(baseURL: URL(string: "https://example.test")!), transport: wire, enabled: enabled)
    }
    private func model(_ wire: JournalWire, _ owner: Owner, journal: any PlayGameCommandJournal) throws -> PlayPlayerGameCoordinator {
        PlayPlayerGameCoordinator(activityID: 41, service: try service(wire), currentSession: { owner.session }, journal: journal)
    }
    private func key(_ session: PlayExperienceSession) -> String { PlayRunStorageKey.make(session: session, scope: .activity(41)) }
    private func command(_ id: String = "a01-ready-71", revision: Int = 4) throws -> PlayPlayerCommand {
        try .init(activityID: 41, nodeID: 701, requestID: id, expectedRevision: revision, action: .choice, payload: ["choiceId": .string("LEFT")])
    }
    private func receipt(_ command: PlayPlayerCommand, outcome: String = "APPLIED", revision: Int = 5) -> PlayWireValue {
        .object(["activityId": .int(41), "requestId": .string(command.requestID), "action": .string(command.action.rawValue),
                 "receiptId": .int(501), "outcome": .string(outcome), "revision": .int(revision), "replayed": .bool(false), "result": .object([:])])
    }
    private func missing(_ command: PlayPlayerCommand) -> PlayWireValue {
        .object(["activityId": .int(41), "requestId": .string(command.requestID), "outcome": .string("PENDING"), "replayed": .bool(false)])
    }
    private func projection(revision: Int = 4, sessionID: Int = 501) throws -> PlayWireValue {
        var value = try XCTUnwrap(PlayExperienceSyntheticFixtures.wire(PlayExperienceSyntheticFixtures.player).object)
        value["revision"] = .int(revision); value["sessionId"] = .int(sessionID)
        return .object(value)
    }
    private func durable(_ a: Anchors, _ b: Blobs, _ session: PlayExperienceSession) throws -> PlayDurableRecovery {
        try PlayDurableRecovery(owner: .init(session: session), key: key(session), anchors: a, ciphertexts: b, processID: UUID())
    }

    func testLockIsPersistedBeforeDispatchAndRestartReadsBackOriginalKeyWithoutPosting() async throws {
        let a = Anchors(), b = Blobs(), first = try session(), wire = JournalWire(), original = try command()
        wire.views = [.value(try projection())]
        let before = try model(wire, Owner(first), journal: try durable(a, b, first))
        await before.load()
        wire.onCommand = { [a, b] in
            // The exact envelope is durable before the first byte reaches the transport.
            let stored = try? await self.durable(a, b, first).readGameCommand(self.key(first))
            XCTAssertEqual(try? stored?.value.command(), original)
        }
        await before.submit(original)
        XCTAssertEqual(before.phase, "unknown"); XCTAssertEqual(before.pending, original)

        // A fresh process: new epoch/token, no in-memory pending, same owner and activity.
        let fresh = try session(epoch: 2, token: "synthetic-refreshed-token")
        let after = try model(wire, Owner(fresh), journal: try durable(a, b, fresh))
        wire.receipts = [.value(missing(original))]
        await after.load()
        XCTAssertEqual(after.phase, "unknown"); XCTAssertEqual(after.pending, original)
        XCTAssertEqual(wire.posts.count, 1)
        let query = URLComponents(url: try XCTUnwrap(wire.receiptRequests.last?.url), resolvingAgainstBaseURL: false)?.queryItems
        XCTAssertTrue(query?.contains(.init(name: "requestId", value: "a01-ready-71")) == true)
        // A different key is not accepted while the original attempt is unknown.
        await after.submit(try command("a01-replacement-71"))
        XCTAssertEqual(wire.posts.count, 1)
        let stored = try await durable(a, b, fresh).readGameCommand(key(fresh))
        XCTAssertEqual(stored?.value.originEpoch, 1); XCTAssertEqual(stored?.value.requestID, "a01-ready-71")
    }

    func testRestartedRetryExactSendsIdenticalEnvelopeThenAppliedReadbackReleasesLock() async throws {
        let a = Anchors(), b = Blobs(), first = try session(), wire = JournalWire(), original = try command()
        wire.views = [.value(try projection())]
        let before = try model(wire, Owner(first), journal: try durable(a, b, first))
        await before.load(); await before.submit(original)

        let fresh = try session(epoch: 2, token: "synthetic-refreshed-token")
        let after = try model(wire, Owner(fresh), journal: try durable(a, b, fresh))
        wire.receipts = [.value(receipt(original, outcome: "PENDING", revision: 4))]
        await after.load(); XCTAssertEqual(after.phase, "unknown")
        wire.commands = [.value(receipt(original))]; wire.views = [.value(try projection(revision: 5))]
        await after.retryExact()
        XCTAssertEqual(after.phase, "ready"); XCTAssertNil(after.pending); XCTAssertEqual(after.projection?.revision, 5)
        XCTAssertEqual(wire.posts.count, 2)
        let bodies = try wire.posts.map { try JSONDecoder().decode(PlayWireValue.self, from: XCTUnwrap($0.httpBody)) }
        XCTAssertEqual(bodies.first, bodies.last)
        XCTAssertEqual(wire.posts.last?.value(forHTTPHeaderField: "Authorization"), fresh.token)
        let released = try await durable(a, b, fresh).readGameCommand(key(fresh))
        XCTAssertNil(released)
    }

    func testFailedReceiptIsDefiniteAndReleasesLock() async throws {
        let journal = PlayMemoryGameCommandJournal(), owner = Owner(try session()), wire = JournalWire(), original = try command()
        wire.views = [.value(try projection())]
        let first = try model(wire, owner, journal: journal)
        await first.load(); await first.submit(original)
        let rebuilt = try model(wire, owner, journal: journal)
        wire.receipts = [.value(receipt(original, outcome: "FAILED", revision: 4))]
        await rebuilt.load()
        XCTAssertEqual(rebuilt.phase, "rejected"); XCTAssertNil(rebuilt.pending)
        let released = try await journal.readGameCommand(key(try XCTUnwrap(owner.session)))
        XCTAssertNil(released)
    }

    func testReadFailuresPendingAndPageExitNeverReleaseLock() async throws {
        let journal = PlayMemoryGameCommandJournal(), owner = Owner(try session()), wire = JournalWire(), original = try command()
        wire.views = [.value(try projection())]
        var current: PlayPlayerGameCoordinator? = try model(wire, owner, journal: journal)
        await current?.load(); await current?.submit(original)
        let replies: [JournalWire.Reply] = [.value(missing(original)), .value(receipt(original, outcome: "PENDING", revision: 4)),
                                            .businessError(500), .businessError(409), .failure(.unknownResult)]
        for reply in replies {
            current = nil  // Page exit / coordinator released.
            current = try model(wire, owner, journal: journal)
            wire.receipts = [reply]
            await current?.load()
            XCTAssertEqual(current?.phase, "unknown"); XCTAssertEqual(current?.pending, original)
            let stored = try await journal.readGameCommand(key(try XCTUnwrap(owner.session)))
            XCTAssertEqual(try stored?.value.command(), original)
        }
        XCTAssertEqual(wire.posts.count, 1)
    }

    func testAppliedReceiptWithFailedViewKeepsLockUntilProjectionReadback() async throws {
        let journal = PlayMemoryGameCommandJournal(), owner = Owner(try session()), wire = JournalWire(), original = try command()
        wire.views = [.value(try projection())]
        let first = try model(wire, owner, journal: journal)
        await first.load()
        wire.commands = [.value(receipt(original))]; wire.views = [.businessError(500)]
        await first.submit(original)
        XCTAssertEqual(first.phase, "unknown"); XCTAssertEqual(first.receipt?.outcome, "APPLIED")
        let held = try await journal.readGameCommand(key(try XCTUnwrap(owner.session)))
        XCTAssertNotNil(held)
        // After a rebuild, the original session identity still guards the readback.
        let rebuilt = try model(wire, owner, journal: journal)
        wire.receipts = [.value(receipt(original))]; wire.views = [.value(try projection(revision: 5, sessionID: 502))]
        await rebuilt.load()
        XCTAssertEqual(rebuilt.phase, "unknown"); XCTAssertEqual(rebuilt.pending, original)
        wire.views = [.value(try projection(revision: 5))]
        await rebuilt.retryExact()
        XCTAssertEqual(rebuilt.phase, "ready"); XCTAssertNil(rebuilt.pending)
        XCTAssertEqual(wire.posts.count, 1); XCTAssertEqual(wire.receiptRequests.count, 1)
        let released = try await journal.readGameCommand(key(try XCTUnwrap(owner.session)))
        XCTAssertNil(released)
    }

    func testUnwritableJournalNeverDispatchesAndUnreadableJournalBlocksNewCommands() async throws {
        let owner = Owner(try session()), wire = JournalWire(), journal = FailingJournal()
        wire.views = [.value(try projection())]
        journal.failRead = false
        let model = try model(wire, owner, journal: journal)
        await model.load(); XCTAssertEqual(model.phase, "ready")
        await model.submit(try command())
        XCTAssertTrue(wire.posts.isEmpty); XCTAssertNil(model.pending)
        XCTAssertEqual(model.issue, .persistenceUnavailable); XCTAssertTrue(model.localRecoveryFailed)
        journal.failRead = true
        await model.load()
        XCTAssertEqual(model.phase, "failed"); XCTAssertEqual(model.issue, .persistenceUnavailable)
        await model.submit(try command("a01-second-71"))
        XCTAssertTrue(wire.posts.isEmpty)
    }

    func testFailedReleaseKeepsLockAndRetriesReleaseWithoutPosting() async throws {
        let owner = Owner(try session()), wire = JournalWire(), journal = FailingJournal(), original = try command()
        wire.views = [.value(try projection())]
        let model = try model(wire, owner, journal: journal)
        journal.failRead = false; journal.failWrite = false; journal.failClear = true
        await model.load(); await model.submit(original)
        wire.receipts = [.value(receipt(original, outcome: "FAILED", revision: 4))]
        await model.recover()
        XCTAssertEqual(model.phase, "unknown"); XCTAssertEqual(model.pending, original); XCTAssertEqual(model.issue, .persistenceUnavailable)
        journal.failClear = false
        wire.receipts = [.value(receipt(original, outcome: "FAILED", revision: 4))]
        await model.retryExact()
        XCTAssertEqual(model.phase, "rejected"); XCTAssertNil(model.pending)
        XCTAssertEqual(wire.posts.count, 1)
    }

    func testOtherAccountRealmOrRoleCannotAdoptOrReleaseLock() async throws {
        let a = Anchors(), b = Blobs(), first = try session(), wire = JournalWire(), original = try command()
        wire.views = [.value(try projection())]
        let before = try model(wire, Owner(first), journal: try durable(a, b, first))
        await before.load(); await before.submit(original)
        let merchant = try PlayExperienceSession(accountID: 7, epoch: 1, namespace: "synthetic-cn", token: "synthetic-token", role: "merchant")
        for other in [try session(account: 8), try session(namespace: "synthetic-us"), merchant] {
            let foreign = try model(wire, Owner(other), journal: try durable(a, b, other))
            await foreign.load()
            XCTAssertNil(foreign.pending)
            if other == merchant {
                // Role shares the account slot: it fails closed instead of opening a fresh lock around it.
                XCTAssertEqual(foreign.phase, "failed"); XCTAssertEqual(foreign.issue, .persistenceUnavailable)
            } else {
                // Another account or realm has its own empty slot and never sees the original lock.
                XCTAssertEqual(foreign.phase, "ready")
            }
            // A durable store bound to another owner rejects the original key outright.
            do { _ = try await durable(a, b, other).readGameCommand(key(first)); XCTFail("Foreign key accepted") }
            catch { XCTAssertEqual(error as? PlayExperienceError, .persistenceUnavailable) }
        }
        let held = try await durable(a, b, first).readGameCommand(key(first))
        XCTAssertEqual(try held?.value.command(), original)
        XCTAssertEqual(wire.posts.count, 1)
    }

    func testLateReplyAfterAccountSwitchKeepsOriginalOwnersLock() async throws {
        let journal = PlayMemoryGameCommandJournal(), first = try session(), owner = Owner(first), wire = JournalWire(), original = try command()
        wire.views = [.value(try projection())]
        let model = try model(wire, owner, journal: journal)
        await model.load()
        wire.commands = [.value(receipt(original))]
        wire.onCommand = { owner.session = try? self.session(account: 8) }
        await model.submit(original)
        XCTAssertEqual(model.phase, "stale"); XCTAssertNil(model.projection); XCTAssertNil(model.receipt)
        let held = try await journal.readGameCommand(key(first))
        XCTAssertEqual(try held?.value.command(), original)
    }

    func testSecondDeviceWithoutLocalLockRefreshesAuthoritativeView() async throws {
        let owner = Owner(try session()), wire = JournalWire()
        wire.views = [.value(try projection()), .value(try projection(revision: 5))]
        let deviceA = try model(wire, owner, journal: PlayMemoryGameCommandJournal())
        await deviceA.load(); await deviceA.submit(try command())
        // Device B shares the account but not device A's local journal: it reads the view only.
        let deviceB = try model(wire, owner, journal: PlayMemoryGameCommandJournal())
        await deviceB.load()
        XCTAssertEqual(deviceB.phase, "ready"); XCTAssertNil(deviceB.pending); XCTAssertEqual(deviceB.projection?.revision, 5)
        XCTAssertEqual(wire.posts.count, 1); XCTAssertTrue(wire.receiptRequests.isEmpty)
    }

    func testTamperedOrForeignActivityRecordFailsClosed() async throws {
        let owner = Owner(try session()), wire = JournalWire(), journal = PlayMemoryGameCommandJournal()
        let stray = try PlayPlayerCommand(activityID: 42, nodeID: 701, requestID: "a01-other-72", expectedRevision: 4, action: .choice, payload: ["choiceId": .string("LEFT")])
        _ = try await journal.recordGameCommand(.init(command: stray, session: try XCTUnwrap(owner.session), sessionID: 501), key: key(try XCTUnwrap(owner.session)))
        wire.views = [.value(try projection())]
        let model = try model(wire, owner, journal: journal)
        await model.load()
        XCTAssertEqual(model.phase, "failed"); XCTAssertEqual(model.issue, .persistenceUnavailable); XCTAssertNil(model.pending)
        XCTAssertTrue(wire.requests.isEmpty)
    }

    func testRecordRoundTripsExactEnvelope() throws {
        let owner = try session()
        let submit = try PlayPlayerCommand(activityID: 41, nodeID: 701, requestID: "a01-ready-71", expectedRevision: 4, action: .submit,
            payload: ["taskCode": .string("OBSERVE"), "evidenceUrls": .array([.string(try PlayPlayerCommand.textEvidence("synthetic note"))])])
        let hint = try PlayPlayerCommand(activityID: 41, nodeID: 701, requestID: "a01-hint-71", expectedRevision: 4, action: .hint, payload: ["level": .int(1)])
        let choice = try command()
        for original in [submit, hint, choice] {
            let record = try PlayPendingGameCommand(command: original, session: owner, sessionID: 501)
            let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
            let decoded = try PropertyListDecoder().decode(PlayPendingGameCommand.self, from: encoder.encode(record))
            XCTAssertEqual(try decoded.command(), original)
        }
        XCTAssertThrowsError(try PlayPendingGameCommand(command: choice, session: owner, sessionID: 0))
    }
}

@MainActor private final class FailingJournal: PlayGameCommandJournal {
    var failRead = false, failWrite = true, failClear = false
    private let inner = PlayMemoryGameCommandJournal()
    func readGameCommand(_ key: String) async throws -> PlayGameCommandJournalSnapshot? {
        if failRead { throw PlayExperienceError.persistenceUnavailable }; return try await inner.readGameCommand(key)
    }
    func recordGameCommand(_ value: PlayPendingGameCommand, key: String) async throws -> PlayGameCommandJournalSnapshot {
        if failWrite { throw PlayExperienceError.persistenceUnavailable }; return try await inner.recordGameCommand(value, key: key)
    }
    func clearGameCommand(_ snapshot: PlayGameCommandJournalSnapshot, key: String) async throws {
        if failClear { throw PlayExperienceError.persistenceUnavailable }; try await inner.clearGameCommand(snapshot, key: key)
    }
}

@MainActor private final class JournalWire: HTTPTransport {
    enum Reply {
        case value(PlayWireValue), businessError(Int), failure(PlayExperienceError)
        func result() throws -> (Data, Int) {
            let envelope: PlayWireValue
            switch self {
            case .value(let value): envelope = .object(["code": .int(200), "data": value])
            case .businessError(let code): envelope = .object(["code": .int(code), "msg": .string("Synthetic request failure"), "data": .null])
            case .failure(let error): throw error
            }
            return (try JSONEncoder().encode(envelope), 200)
        }
    }
    var commands: [Reply] = [], receipts: [Reply] = [], views: [Reply] = []
    var requests: [URLRequest] = []
    var onCommand: (() async -> Void)?
    var posts: [URLRequest] { requests.filter { $0.httpMethod == "POST" } }
    var receiptRequests: [URLRequest] { requests.filter { $0.url?.path == "/api/game/session/receipt" } }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        switch request.url?.path {
        case "/api/game/session/command":
            if let hook = onCommand { onCommand = nil; await hook() }
            return try (commands.isEmpty ? .failure(.unknownResult) : commands.removeFirst()).result()
        case "/api/game/session/receipt":
            return try (receipts.isEmpty ? .failure(.unknownResult) : receipts.removeFirst()).result()
        case "/api/game/session/view":
            return try (views.isEmpty ? .value(try PlayExperienceSyntheticFixtures.wire(PlayExperienceSyntheticFixtures.player)) : views.removeFirst()).result()
        default: XCTFail("Unexpected synthetic request"); throw PlayExperienceError.malformed
        }
    }
}

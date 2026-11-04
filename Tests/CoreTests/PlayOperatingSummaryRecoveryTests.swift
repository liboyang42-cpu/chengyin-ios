import XCTest
@testable import QuestifyCore

/// Real original coordinator/service and encrypted journal, with synthetic OS primitives only.
@MainActor final class PlayOperatingSummaryRecoveryTests: XCTestCase {
    func testRestartWithActiveReadbackRemainsUnknownAndNeverResends() async throws {
        let f = try Fixture(); let first = try f.model(); await first.load()
        f.wire.postHTTP = 503; await first.revoke(tagID: 81)
        XCTAssertEqual(first.unresolvedTagIDs, [81]); XCTAssertEqual(f.wire.posts, 1)
        f.session = try Fixture.session(epoch: 2)
        let reopened = try f.model(); await reopened.load(); await reopened.revoke(tagID: 81)
        XCTAssertEqual(reopened.phase, "unknown"); XCTAssertEqual(reopened.unresolvedTagIDs, [81])
        XCTAssertEqual(f.wire.posts, 1)
        f.wire.tagState = "REVOKED"; await reopened.load()
        XCTAssertEqual(reopened.phase, "ready"); XCTAssertTrue(reopened.unresolvedTagIDs.isEmpty)
        let third = try f.model(); await third.load()
        XCTAssertTrue(third.unresolvedTagIDs.isEmpty); XCTAssertEqual(f.wire.posts, 1)
    }
    func testRestartReadFailuresAndForeignTopicNeverClearPendingMarker() async throws {
        let f = try Fixture(); let first = try f.model(); await first.load(); f.wire.postHTTP = 503
        await first.revoke(tagID: 81); let stored = try await f.pending(); let original = try XCTUnwrap(stored)
        for (status, topic) in [(401, 71), (403, 71), (503, 71), (200, 72)] {
            f.wire.getHTTP = status; f.wire.topicID = topic
            let reopened = try f.model(); await reopened.load(); await reopened.revoke(tagID: 81)
            XCTAssertEqual(reopened.unresolvedTagIDs, [81]); XCTAssertNotNil(reopened.issue)
            let kept = try await f.pending(); XCTAssertEqual(kept, original)
        }
        XCTAssertEqual(f.wire.posts, 1)
        f.wire.getHTTP = 200; f.wire.topicID = 71; f.wire.tagState = nil
        let reconciled = try f.model(); await reconciled.load()
        XCTAssertTrue(reconciled.unresolvedTagIDs.isEmpty)
        let cleared = try await f.pending(); XCTAssertNil(cleared)
    }
    func testMalformedOrIncompleteTagCollectionCannotMasqueradeAsAbsence() async throws {
        let f = try Fixture(); let first = try f.model(); await first.load(); f.wire.postHTTP = 503
        await first.revoke(tagID: 81); let saved = try await f.pending(); let marker = try XCTUnwrap(saved)
        let invalid: [[String: Any]] = [[:], ["tags": "unknown"], ["tags": NSNull()],
            ["tags": [["id": 81, "status": "ACTIVE"]]],
            ["tags": [["id": 81, "tagValue": "Synthetic", "status": "FUTURE"]]],
            ["tags": [["id": 81]]], ["tags": [["status": "REVOKED"]]],
            ["tags": [["id": 81, "status": "REVOKED"], ["id": 81, "status": "ACTIVE"]]]]
        for body in invalid {
            f.wire.summaryOverride = body.merging(["topicId": 71]) { _, fresh in fresh }
            let reopened = try f.model(); await reopened.load(); await reopened.revoke(tagID: 81)
            XCTAssertEqual(reopened.unresolvedTagIDs, [81]); XCTAssertNotEqual(reopened.phase, "ready")
            let kept = try await f.pending(); XCTAssertEqual(kept, marker)
        }
        XCTAssertEqual(f.wire.posts, 1)
        // Explicit original ID + REVOKED is sufficient even when display-only value is absent.
        f.wire.summaryOverride = ["topicId": 71, "tags": [["id": 81, "status": "REVOKED"]]]
        let resolved = try f.model(); await resolved.load(); XCTAssertTrue(resolved.unresolvedTagIDs.isEmpty)
    }
    func testMarkerCreatedDuringReadCannotPublishAnUnprotectedReadyState() async throws {
        let f = try Fixture(); let store = try f.store(), session = try XCTUnwrap(f.session)
        let key = PlayRunStorageKey.make(session: session, scope: .topic(71))
        f.wire.onGet = { _ = try await store.recordTagRevocation(.init(session: session, topicID: 71, tagID: 81), key: key) }
        let model = try f.model(); await model.load()
        XCTAssertNotEqual(model.phase, "ready"); XCTAssertEqual(model.issue, .persistenceUnavailable)
        await model.revoke(tagID: 81); XCTAssertEqual(f.wire.posts, 0)
        await model.load(); XCTAssertEqual(model.unresolvedTagIDs, [81]); XCTAssertEqual(model.phase, "unknown")
    }
    func testDurableRecordFailurePreventsOriginalPost() async throws {
        let f = try Fixture(); let model = try f.model(); await model.load()
        await f.blobs.configure(failInsert: true)
        await model.revoke(tagID: 81)
        XCTAssertEqual(f.wire.posts, 0); XCTAssertEqual(model.issue, .persistenceUnavailable)
        XCTAssertEqual(model.unresolvedTagIDs, [81])
        await f.blobs.configure()
        let reopened = try f.model(); await reopened.load(); await reopened.revoke(tagID: 81)
        XCTAssertEqual(reopened.issue, .persistenceUnavailable); XCTAssertEqual(f.wire.posts, 0)
    }
    func testAuthoritativeClearFailureCannotAdvertiseReady() async throws {
        let f = try Fixture(); let store = try f.store(); let gate = Gate(store)
        let first = f.model(recovery: gate); await first.load(); await first.revoke(tagID: 81)
        XCTAssertEqual(first.phase, "unknown"); f.wire.tagState = "REVOKED"; gate.failClear = true
        await first.load(); XCTAssertEqual(first.phase, "unknown")
        XCTAssertEqual(first.issue, .persistenceUnavailable); XCTAssertEqual(first.unresolvedTagIDs, [81])
        let retained = try await f.pending(); XCTAssertNotNil(retained)
        gate.failClear = false; await first.load()
        XCTAssertEqual(first.phase, "ready"); XCTAssertTrue(first.unresolvedTagIDs.isEmpty)
        XCTAssertEqual(f.wire.posts, 1)
    }
    func testExplicitRejectionAndDisabledCapabilityReleaseOnlyRecordedMarker() async throws {
        for disabled in [false, true] {
            let f = try Fixture(); f.wire.postBusiness = 409
            let first = try f.model(tags: !disabled); await first.load(); await first.revoke(tagID: 81)
            XCTAssertTrue(first.unresolvedTagIDs.isEmpty)
            let pending = try await f.pending(); XCTAssertNil(pending)
            XCTAssertEqual(f.wire.posts, disabled ? 0 : 1)
            XCTAssertEqual(first.issue, disabled ? .disabled : .rejected(409, nil))
        }
    }
    func testSecondViewerCannotDispatchUsingAnEarlierReadyRead() async throws {
        let f = try Fixture(); let first = try f.model(), second = try f.model()
        await first.load(); await second.load(); f.wire.postHTTP = 503
        await first.revoke(tagID: 81); await second.revoke(tagID: 81)
        XCTAssertEqual(f.wire.posts, 1); XCTAssertEqual(second.issue, .persistenceUnavailable)
        await second.load(); XCTAssertEqual(second.phase, "unknown")
        XCTAssertEqual(second.unresolvedTagIDs, [81])
    }
    func testOtherViewerCannotClearLiveWriteEvenIfItsReadOmitsTag() async throws {
        let f = try Fixture(); let first = try f.model(); await first.load(); f.wire.suspendPost = true
        let work = Task { await first.revoke(tagID: 81) }; await f.wire.waitForPost()
        f.wire.tagState = nil
        let other = try f.model(); await other.load(); await other.revoke(tagID: 81)
        XCTAssertEqual(other.phase, "unknown"); XCTAssertEqual(other.unresolvedTagIDs, [81])
        let retained = try await f.pending(); XCTAssertNotNil(retained); XCTAssertEqual(f.wire.posts, 1)
        f.wire.resumePost(status: 503); await work.value
        await other.load(); XCTAssertTrue(other.unresolvedTagIDs.isEmpty)
        XCTAssertEqual(f.wire.posts, 1)
    }
    func testCancellationKeepsDiskMarkerForNewOwnerUntilReadback() async throws {
        let f = try Fixture(); let first = try f.model(); await first.load(); f.wire.suspendPost = true
        let work = Task { await first.revoke(tagID: 81) }; await f.wire.waitForPost()
        work.cancel(); f.wire.resumePost(status: 200); await work.value
        XCTAssertEqual(first.unresolvedTagIDs, [81])
        let reopened = try f.model(); await reopened.load(); await reopened.revoke(tagID: 81)
        XCTAssertEqual(reopened.phase, "unknown"); XCTAssertEqual(f.wire.posts, 1)
    }
    func testIdentityChangesAfterDurableRecordCannotSendOldRequest() async throws {
        let f = try Fixture(); let gate = Gate(try f.store()); gate.suspendRecord = true
        let first = f.model(recovery: gate); await first.load()
        let work = Task { await first.revoke(tagID: 81) }; await gate.waitForRecord()
        f.session = try Fixture.session(account: 8, epoch: 2)
        gate.resumeRecord(); await work.value
        XCTAssertEqual(f.wire.posts, 0); XCTAssertEqual(first.phase, "stale")
        f.session = try Fixture.session(epoch: 3)
        let reopened = try f.model(); await reopened.load(); await reopened.revoke(tagID: 81)
        XCTAssertEqual(reopened.phase, "unknown"); XCTAssertEqual(reopened.unresolvedTagIDs, [81])
        XCTAssertEqual(f.wire.posts, 0)
    }
    func testUnavailableRecoveryFailsClosedWithoutReadOrWrite() async throws {
        let f = try Fixture(); let model = f.model(recovery: PlayUnavailableTagRevocationRecovery())
        await model.load(); await model.revoke(tagID: 81)
        XCTAssertEqual(model.issue, .persistenceUnavailable); XCTAssertTrue(f.wire.requests.isEmpty)
    }

    @MainActor private final class Fixture {
        let anchors = ContentDraftDurableJournalTests.Anchors()
        let blobs = ContentDraftDurableJournalTests.Blobs()
        let wire = Wire()
        var session: PlayExperienceSession?
        init() throws { session = try Self.session() }
        static func session(account: Int = 7, epoch: UInt64 = 1) throws -> PlayExperienceSession {
            try .init(accountID: account, epoch: epoch, namespace: "synthetic-tag-recovery", token: "NEVER-PERSIST-SYNTHETIC-TOKEN", role: "player")
        }
        func store() throws -> PlayDurableRecovery {
            let s = try XCTUnwrap(session)
            return try .init(owner: .init(session: s), key: PlayRunStorageKey.make(session: s, scope: .topic(71)),
                anchors: anchors, ciphertexts: blobs, processID: UUID())
        }
        func pending() async throws -> PlayTagRevocationRecoverySnapshot? {
            let s = try XCTUnwrap(session)
            return try await store().readTagRevocation(PlayRunStorageKey.make(session: s, scope: .topic(71)))
        }
        func model(tags: Bool = true) throws -> PlayOperatingSummaryCoordinator { model(recovery: try store(), tags: tags) }
        func model(recovery: any PlayTagRevocationRecovery, tags: Bool = true) -> PlayOperatingSummaryCoordinator {
            let service = PlayExperienceService(configuration: try! APIConfiguration(baseURL: URL(string: "https://example.test/")!),
                transport: wire, enabled: tags ? [.reads, .tags] : [.reads])
            return .init(topicID: 71, service: service, recovery: recovery, currentSession: { [weak self] in self?.session })
        }
    }
    @MainActor private final class Gate: PlayTagRevocationRecovery {
        let store: any PlayTagRevocationRecovery
        var failClear = false, suspendRecord = false
        private var pending: CheckedContinuation<Void, Never>?
        private var waiter: CheckedContinuation<Void, Never>?
        init(_ store: any PlayTagRevocationRecovery) { self.store = store }
        func waitForRecord() async { if pending != nil { return }; await withCheckedContinuation { waiter = $0 } }
        func resumeRecord() { let p = pending; pending = nil; p?.resume() }
        func readTagRevocation(_ key: String) async throws -> PlayTagRevocationRecoverySnapshot? { try await store.readTagRevocation(key) }
        func recordTagRevocation(_ intent: PlayTagRevocationIntent, key: String) async throws -> PlayTagRevocationRecoverySnapshot {
            let saved = try await store.recordTagRevocation(intent, key: key)
            if suspendRecord { await withCheckedContinuation { pending = $0; waiter?.resume(); waiter = nil } }
            return saved
        }
        func clearTagRevocation(_ snapshot: PlayTagRevocationRecoverySnapshot, key: String) async throws {
            if failClear { throw PlayExperienceError.persistenceUnavailable }
            try await store.clearTagRevocation(snapshot, key: key)
        }
    }
    @MainActor private final class Wire: HTTPTransport {
        var requests: [URLRequest] = []
        var tagState: String? = "ACTIVE"
        var summaryOverride: [String: Any]?
        var onGet: (() async throws -> Void)?
        var topicID = 71, getHTTP = 200, postHTTP = 200, postBusiness = 200
        var suspendPost = false
        private var pending: CheckedContinuation<(Data, Int), Error>?
        private var waiter: CheckedContinuation<Void, Never>?
        var posts: Int { requests.filter { $0.httpMethod == "POST" }.count }
        func waitForPost() async { if pending != nil { return }; await withCheckedContinuation { waiter = $0 } }
        func resumePost(status: Int) { let p = pending; pending = nil; p?.resume(returning: (reply(["id": 81, "status": "REVOKED"]), status)) }
        private func reply(_ value: [String: Any], code: Int = 200) -> Data {
            try! JSONSerialization.data(withJSONObject: ["code": code, "data": value])
        }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            if request.httpMethod == "POST" {
                XCTAssertEqual(request.url?.path, "/api/play/tag/81/revoke"); XCTAssertNil(request.httpBody)
                XCTAssertNil(request.url?.query)
                if suspendPost { suspendPost = false; return try await withCheckedThrowingContinuation { pending = $0; waiter?.resume(); waiter = nil } }
                return (reply(["id": 81, "status": "REVOKED"], code: postBusiness), postHTTP)
            }
            XCTAssertEqual(request.url?.path, "/api/play/os/71")
            if let work = onGet { onGet = nil; try await work() }
            let tags: [[String: Any]] = tagState.map { [["id": 81, "tagValue": "Synthetic", "status": $0]] } ?? []
            return (reply(summaryOverride ?? ["topicId": topicID, "tags": tags]), getHTTP)
        }
    }
}

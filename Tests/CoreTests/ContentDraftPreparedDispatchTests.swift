import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Actual coordinator + encrypted journal engine + actual service, with only synthetic
/// stores and an in-process HTTP recorder. No production storage, tokens or network.
@MainActor final class ContentDraftPreparedDispatchTests: XCTestCase {
    private struct Payload: Codable, Equatable { let title: String }
    private typealias Anchors = ContentDraftDurableJournalTests.Anchors
    private typealias Blobs = ContentDraftDurableJournalTests.Blobs
    @MainActor private final class Transport {
        let recorder = ContentDraftRecordingTransport()
        var requests: [URLRequest] { recorder.requests }
        var lose: Bool { get { recorder.lose } set { recorder.lose = newValue } }
        var status = 200
        func prepare(_ attempt: ContentDraftPreparedDispatch) throws {
            if status != 200 { recorder.response = (Data(), status); return }
            let command = attempt.mutation.command
            let payload = command.payloadJson ?? "{\"title\":\"synthetic\"}"
            let row: [String: Any] = ["id": command.id ?? 19, "ownerMemberId": 7, "businessType": "TOPIC",
                "clientDraftKey": command.clientDraftKey ?? "synthetic-key", "payloadJson": payload,
                "payloadHash": ContentDraftRecord.hash(payload), "status": attempt.route == .delete ? "DELETED" : "DRAFT",
                "version": command.expectedVersion + 1, "updatedByDevice": "synthetic-device"]
            recorder.response = (try JSONSerialization.data(withJSONObject: ["code": 200, "data": row]), 200)
        }
    }
    private final class ObservingService: ContentDraftServing {
        let base: ContentDraftService
        let transport: Transport
        var attempts: [ContentDraftPreparedDispatch] = []
        var before: ((ContentDraftPreparedDispatch) async throws -> Void)?
        var holdWithoutDispatch = false
        init(_ base: ContentDraftService, transport: Transport) { self.base = base; self.transport = transport }
        func restore(id: Int64, identity: ContentDraftIdentity) async throws -> ContentDraftRecord { try await base.restore(id: id, identity: identity) }
        func list(type: ContentDraftBusinessType?) async throws -> [ContentDraftRecord] { try await base.list(type: type) }
        func mutate(_ attempt: ContentDraftPreparedDispatch) async throws -> ContentDraftRecord {
            attempts.append(attempt); try transport.prepare(attempt); try await before?(attempt)
            if holdWithoutDispatch { throw ContentDraftIssue.unknownOutcome }
            return try await base.mutate(attempt)
        }
    }
    private final class Unauthorized { var count = 0 }
    @MainActor private final class Fixture {
        let context: RuntimeDependencyContext
        let identity: ContentDraftIdentity
        let lease: ContentDraftSessionLease
        let anchors = Anchors(), blobs = Blobs(), transport = Transport(), unauthorized = Unauthorized()
        let journal: ContentDraftDurableJournal
        let client: ContentDraftService
        let service: ObservingService
        let model: ContentDraftCoordinator<Payload>
        init(key: String = "synthetic-key", grant: Bool = true) throws {
            context = .init(market: .china, baseURL: URL(string: "https://prepared-fixture.invalid/api")!, role: "player",
                session: try .init(accountID: 7, epoch: 1, namespace: "synthetic-realm", token: "synthetic-token"))
            identity = try .init(ownerMemberID: 7, businessType: .topic, clientDraftKey: key)
            let captured = context
            lease = ContentDraftSessionLease(context: context, current: { captured })
            journal = try .init(scope: .init(context: context, identity: identity), anchors: anchors, ciphertexts: blobs)
            let callback = unauthorized
            client = try ContentDraftService(api: .init(baseURL: context.baseURL), transport: transport.recorder, lease: lease,
                grant: grant ? ContentDraftRouteGrant(context: context, ownerMemberID: 7, scope: .personal,
                    routes: Set(ContentDraftRoute.allCases), expiresAt: Date(timeIntervalSince1970: 1000)) : nil,
                now: { Date(timeIntervalSince1970: 100) }, onUnauthorized: { _ in callback.count += 1 })
            service = ObservingService(client, transport: transport)
            model = ContentDraftCoordinator(identity: identity, service: service, lease: lease, journal: journal)
        }
        func prepare() async {
            await model.initialize(); model.prepareSave(.init(title: "synthetic"), subjectID: nil, deviceID: "synthetic-device")
        }
    }
    private func issue(_ expected: ContentDraftIssue, _ action: () async throws -> Void) async {
        do { try await action(); XCTFail("Expected rejection") }
        catch { XCTAssertEqual(error as? ContentDraftIssue, expected) }
    }
    private func request(_ attempt: ContentDraftPreparedDispatch, context: RuntimeDependencyContext) -> URLRequest {
        var value = URLRequest(url: context.baseURL.appendingPathComponent(attempt.route.path))
        value.httpMethod = "POST"; value.httpBody = attempt.body
        value.setValue("application/json", forHTTPHeaderField: "Content-Type")
        value.setValue(context.session.token, forHTTPHeaderField: "Authorization")
        return value
    }
    func testRealServiceSeesExactDurableGenerationBeforeEveryHTTP() async throws {
        let f = try Fixture(); await f.prepare()
        var expected: ContentDraftJournalSnapshot?
        f.service.before = { attempt in
            let snapshot = try await f.journal.read()
            XCTAssertEqual(snapshot?.value.mutation, attempt.mutation)
            XCTAssertEqual(snapshot?.value.dispatched, true); XCTAssertEqual(snapshot?.generation.count, 32)
            expected = snapshot
        }
        f.transport.recorder.pausesResponse = true
        let task = Task { await f.model.confirm() }
        await f.transport.recorder.waitUntilSuspended()
        let atHTTP = try await f.journal.read()
        XCTAssertEqual(atHTTP, expected)
        let anchors = await f.anchors.snapshots(), blobs = await f.blobs.snapshots()
        XCTAssertEqual(anchors.count, 1); XCTAssertEqual(blobs.count, 1)
        f.transport.recorder.resumeResponse(); await task.value
        XCTAssertEqual(f.transport.requests.count, 1); XCTAssertEqual(f.model.phase, .ready)
        let cleared = try await f.journal.read(); XCTAssertNil(cleared)
    }
    func testMissingLockedCorruptAndInterruptedJournalDenyActualService() async throws {
        for mode in 0..<5 {
            let f = try Fixture(); await f.prepare()
            if mode == 0 { await f.anchors.configure(locked: true) }
            if mode == 1 { await f.blobs.configure(partial: true) }
            if mode >= 2 {
                let review = try XCTUnwrap(f.model.review)
                _ = try await f.journal.insert(.init(mutation: review))
                if mode == 2 { await f.anchors.loseAnchors() }
                if mode == 3 { await f.anchors.corrupt() }
                if mode == 4 { await f.blobs.corrupt() }
            }
            await f.model.confirm()
            XCTAssertTrue(f.transport.requests.isEmpty); XCTAssertTrue(f.service.attempts.isEmpty)
            XCTAssertEqual(f.model.phase, .blocked)
        }
        let f = try Fixture()
        let noJournal = ContentDraftCoordinator<Payload>(identity: f.identity, service: f.client, lease: f.lease)
        await noJournal.initialize(); noJournal.prepareSave(.init(title: "synthetic"), subjectID: nil, deviceID: "synthetic-device")
        await noJournal.confirm(); XCTAssertFalse(noJournal.canPrepare); XCTAssertTrue(f.transport.requests.isEmpty)
    }
    func testPermitRechecksGenerationAtServiceBoundary() async throws {
        let f = try Fixture(); await f.prepare()
        var replacement: ContentDraftJournalSnapshot?
        f.service.before = { _ in
            let readback = try await f.journal.read()
            let old = try XCTUnwrap(readback)
            replacement = try await f.journal.replace(old, with: old.value)
        }
        await f.model.confirm()
        XCTAssertTrue(f.transport.requests.isEmpty); XCTAssertEqual(f.model.issue, .storageUnavailable)
        XCTAssertEqual(f.model.phase, .unknown)
        let retained = try await f.journal.read(); XCTAssertEqual(retained, replacement)
    }
    func testCrossOperationSnapshotCannotReusePreparedPermit() async throws {
        let f = try Fixture(); await f.prepare()
        var changed: ContentDraftJournalSnapshot?
        f.service.before = { attempt in
            let value = try await f.journal.read(), original = try XCTUnwrap(value)
            try await f.journal.clear(matching: original)
            let other = try ContentDraftMutation.save(payload: Payload(title: "synthetic"), identity: f.identity,
                subjectID: nil, deviceID: "synthetic-device", baseline: nil)
            XCTAssertNotEqual(other.operationID, attempt.mutation.operationID)
            let inserted = try await f.journal.insert(.init(mutation: other))
            changed = try await f.journal.replace(inserted, with: .init(mutation: other, dispatched: true))
        }
        await f.model.confirm(); XCTAssertTrue(f.transport.requests.isEmpty)
        let retained = try await f.journal.read(); XCTAssertEqual(retained, changed)
        XCTAssertEqual(f.model.issue, .storageUnavailable)
    }
    private func waitForRead(_ blobs: Blobs) async {
        let deadline = Date().addingTimeInterval(2)
        while !(await blobs.isReadSuspended()) && Date() < deadline { await Task.yield() }
        let suspended = await blobs.isReadSuspended(); XCTAssertTrue(suspended)
    }
    func testGenerationAdvanceInsideFinalBlobReadCannotDispatchStaleSnapshot() async throws {
        let f = try Fixture(); await f.prepare()
        let competing = try ContentDraftDurableJournal(scope: f.journal.scope, anchors: f.anchors, ciphertexts: f.blobs)
        f.service.before = { _ in await f.blobs.pauseRead() }
        let task = Task { await f.model.confirm() }; await waitForRead(f.blobs)
        let readback = try await competing.read(), old = try XCTUnwrap(readback)
        let advanced = try await competing.replace(old, with: old.value)
        await f.blobs.resumeRead(); await task.value
        XCTAssertTrue(f.transport.requests.isEmpty); XCTAssertEqual(f.model.issue, .storageUnavailable)
        let retained = try await competing.read(); XCTAssertEqual(retained, advanced)
    }
    private final class ForkingService: ContentDraftServing {
        let base: ContentDraftService
        let blobs: Blobs
        var outstanding: Task<ContentDraftRecord, Error>?
        init(base: ContentDraftService, blobs: Blobs) { self.base = base; self.blobs = blobs }
        func restore(id: Int64, identity: ContentDraftIdentity) async throws -> ContentDraftRecord { try await base.restore(id: id, identity: identity) }
        func list(type: ContentDraftBusinessType?) async throws -> [ContentDraftRecord] { try await base.list(type: type) }
        func mutate(_ attempt: ContentDraftPreparedDispatch) async throws -> ContentDraftRecord {
            await blobs.pauseRead()
            outstanding = Task { try await base.mutate(attempt) }
            let deadline = Date().addingTimeInterval(2)
            while !(await blobs.isReadSuspended()) && Date() < deadline { await Task.yield() }
            let suspended = await blobs.isReadSuspended(); XCTAssertTrue(suspended)
            // Return control to the coordinator while the real service is inside consume.
            throw ContentDraftIssue.unknownOutcome
        }
    }
    func testRetirementDuringStartedFinalReadPreventsLaterHTTP() async throws {
        let f = try Fixture(), fork = ForkingService(base: f.client, blobs: f.blobs)
        let model = ContentDraftCoordinator<Payload>(identity: f.identity, service: fork, lease: f.lease, journal: f.journal)
        await model.initialize(); model.prepareSave(.init(title: "synthetic"), subjectID: nil, deviceID: "synthetic-device")
        await model.confirm(); XCTAssertEqual(model.phase, .unknown)
        let outstanding = try XCTUnwrap(fork.outstanding)
        await f.blobs.resumeRead()
        await issue(.storageUnavailable) { _ = try await outstanding.value }
        XCTAssertTrue(f.transport.requests.isEmpty)
        let retained = try await f.journal.read(); XCTAssertNotNil(retained)
    }
    func testRevocationInFinalGrantClockCallbackCannotReachHTTP() async throws {
        let f = try Fixture(); var clocks = 0
        let client = try ContentDraftService(api: .init(baseURL: f.context.baseURL), transport: f.transport.recorder, lease: f.lease,
            grant: ContentDraftRouteGrant(context: f.context, ownerMemberID: 7, scope: .personal,
                routes: Set(ContentDraftRoute.allCases), expiresAt: Date(timeIntervalSince1970: 1000)),
            now: { clocks += 1; if clocks == 3 { f.lease.revoke() }; return Date(timeIntervalSince1970: 100) })
        let model = ContentDraftCoordinator<Payload>(identity: f.identity, service: client, lease: f.lease, journal: f.journal)
        await model.initialize(); model.prepareSave(.init(title: "synthetic"), subjectID: nil, deviceID: "synthetic-device")
        await model.confirm()
        XCTAssertEqual(clocks, 3); XCTAssertTrue(f.transport.requests.isEmpty); XCTAssertEqual(model.phase, .invalidated)
    }
    func testStorageBecomingUnavailableAfterPrepareStillDeniesHTTP() async throws {
        for mode in 0..<4 {
            let f = try Fixture(); await f.prepare()
            f.service.before = { _ in
                if mode == 0 { await f.anchors.configure(locked: true) }
                if mode == 1 { await f.anchors.loseAnchors() }
                if mode == 2 { await f.anchors.corrupt() }
                if mode == 3 { await f.blobs.corrupt() }
            }
            await f.model.confirm()
            XCTAssertTrue(f.transport.requests.isEmpty); XCTAssertEqual(f.model.issue, .storageUnavailable)
        }
    }
    func testLostResponseRetryMintsNewAttemptWithOriginalKeyBodyAndOperation() async throws {
        let f = try Fixture(); await f.prepare(); f.transport.lose = true
        await f.model.confirm(); XCTAssertEqual(f.model.phase, .unknown)
        let old = try XCTUnwrap(f.service.attempts.first), original = try XCTUnwrap(f.transport.requests.first)
        let firstGeneration = try await f.journal.read()
        await issue(.storageUnavailable) { _ = try await f.client.mutate(old) }
        XCTAssertEqual(f.transport.requests.count, 1)
        f.service.before = { attempt in
            XCTAssertFalse(attempt === old); XCTAssertEqual(attempt.mutation, old.mutation)
            let retryGeneration = try await f.journal.read()
            XCTAssertNotEqual(retryGeneration?.generation, firstGeneration?.generation)
        }
        await f.model.retryExact()
        XCTAssertEqual(f.transport.requests.count, 2); XCTAssertEqual(f.model.phase, .ready)
        XCTAssertEqual(f.transport.requests[1].httpBody, original.httpBody)
        XCTAssertEqual(f.transport.requests[1].url, original.url)
        await issue(.storageUnavailable) { _ = try await f.client.mutate(old) }
        XCTAssertEqual(f.transport.requests.count, 2)
    }
    func testUnconsumedAttemptRetiresWhenCoordinatorReturns() async throws {
        let f = try Fixture(); await f.prepare(); f.service.holdWithoutDispatch = true
        await f.model.confirm()
        let captured = try XCTUnwrap(f.service.attempts.first)
        await issue(.storageUnavailable) { _ = try await f.client.mutate(captured) }
        XCTAssertTrue(f.transport.requests.isEmpty); XCTAssertEqual(f.model.phase, .unknown)
    }
    func testConsumedAttemptCannotAuthorizeNewReviewOrDelete() async throws {
        let f = try Fixture(); await f.prepare(); await f.model.confirm()
        let captured = try XCTUnwrap(f.service.attempts.first)
        f.model.prepareDelete(); XCTAssertEqual(f.model.review?.kind, .delete)
        await issue(.storageUnavailable) { _ = try await f.client.mutate(captured) }
        XCTAssertEqual(f.transport.requests.count, 1)
        await f.model.confirm(); XCTAssertEqual(f.model.phase, .deleted)
        XCTAssertEqual(f.transport.requests.count, 2); XCTAssertEqual(f.transport.requests.last?.url?.lastPathComponent, "delete")
    }
    func testMismatchedBodyPathKeyOwnerAndVersionBurnThePermit() async throws {
        for mode in 0..<9 {
            let f = try Fixture(); await f.prepare()
            f.service.before = { attempt in
                var changed = self.request(attempt, context: f.context)
                if mode == 0 { changed.url = f.context.baseURL.appendingPathComponent(ContentDraftRoute.delete.path) }
                if mode == 1 { changed.httpMethod = "GET" }
                if (2..<6).contains(mode) {
                    var body = try XCTUnwrap(JSONSerialization.jsonObject(with: attempt.body) as? [String: Any])
                    if mode == 2 { body["clientDraftKey"] = "different-key" }
                    if mode == 3 { body["ownerMemberId"] = 8 }
                    if mode == 4 { body["expectedVersion"] = 9 }
                    if mode == 5 { body["payloadJson"] = "{\"title\":\"different\"}" }
                    changed.httpBody = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys, .withoutEscapingSlashes])
                }
                if mode == 6 { changed.url = URL(string: "https://other-fixture.invalid/api/content-draft/save")! }
                if mode == 7 { changed.setValue("different-token", forHTTPHeaderField: "Authorization") }
                if mode == 8 { changed.setValue("text/plain", forHTTPHeaderField: "Content-Type") }
                await self.issue(.storageUnavailable) { try await attempt.consume(request: changed, lease: f.lease, transport: f.transport.recorder) }
            }
            await f.model.confirm()
            XCTAssertTrue(f.transport.requests.isEmpty); XCTAssertEqual(f.model.issue, .storageUnavailable)
        }
    }
    func testDifferentLeaseEvenWithEqualContextCannotUsePermit() async throws {
        let f = try Fixture(); await f.prepare()
        let other = ContentDraftSessionLease(context: f.context, current: { f.context })
        f.service.before = { attempt in
            await self.issue(.staleSession) { try await attempt.consume(request: self.request(attempt, context: f.context), lease: other, transport: f.transport.recorder) }
        }
        await f.model.confirm(); XCTAssertTrue(f.transport.requests.isEmpty)
    }
    func testRevokedSessionAndInvalidatedCoordinatorDenyPreparedAttempt() async throws {
        for revokeOnly in [false, true] {
            let f = try Fixture(); await f.prepare()
            f.service.before = { _ in if revokeOnly { f.lease.revoke() } else { f.model.invalidate() } }
            await f.model.confirm(); XCTAssertTrue(f.transport.requests.isEmpty); XCTAssertEqual(f.model.phase, .invalidated)
            let pending = try await f.journal.read(); XCTAssertNotNil(pending)
        }
    }
    private final class ArbitraryTransport: HTTPTransport {
        var calls = 0
        func send(_ request: URLRequest) async throws -> (Data, Int) { calls += 1; throw ContentDraftIssue.unavailable }
    }
    func testArbitraryTransportAndInjectedDurableStoresCannotAssertSystemProvenance() async throws {
        let f = try Fixture(), untrusted = ArbitraryTransport()
        XCTAssertFalse(f.journal.isSystemBacked)
        let client = try ContentDraftService(api: .init(baseURL: f.context.baseURL), transport: untrusted, lease: f.lease,
            grant: ContentDraftRouteGrant(context: f.context, ownerMemberID: 7, scope: .personal,
                routes: Set(ContentDraftRoute.allCases), expiresAt: Date(timeIntervalSince1970: 1000)),
            now: { Date(timeIntervalSince1970: 100) })
        let model = ContentDraftCoordinator<Payload>(identity: f.identity, service: client, lease: f.lease, journal: f.journal)
        await model.initialize(); model.prepareSave(.init(title: "synthetic"), subjectID: nil, deviceID: "synthetic-device")
        await model.confirm()
        XCTAssertEqual(untrusted.calls, 0); XCTAssertEqual(model.issue, .storageUnavailable)
        let pending = try await f.journal.read(); XCTAssertTrue(pending?.value.dispatched == true)
        // Reads remain independently grant-gated and require no journal or provenance.
        await issue(.unavailable) { _ = try await client.list(type: .topic) }
        XCTAssertEqual(untrusted.calls, 1)
    }
    func testRecorderPreparedAttemptCannotSwitchToNetworkCapableExecutor() async throws {
        let f = try Fixture(), otherTransport = ArbitraryTransport(); await f.prepare()
        let otherClient = try ContentDraftService(api: .init(baseURL: f.context.baseURL), transport: otherTransport, lease: f.lease,
            grant: ContentDraftRouteGrant(context: f.context, ownerMemberID: 7, scope: .personal,
                routes: Set(ContentDraftRoute.allCases), expiresAt: Date(timeIntervalSince1970: 1000)),
            now: { Date(timeIntervalSince1970: 100) })
        f.service.before = { attempt in _ = try await otherClient.mutate(attempt) }
        await f.model.confirm()
        XCTAssertEqual(otherTransport.calls, 0); XCTAssertTrue(f.transport.requests.isEmpty)
        XCTAssertEqual(f.model.issue, .storageUnavailable)
    }
    func testMissingDeploymentGrantStillDeniesPreparedAttempt() async throws {
        let f = try Fixture(grant: false); await f.prepare(); await f.model.confirm()
        XCTAssertTrue(f.transport.requests.isEmpty); XCTAssertEqual(f.model.issue, .disabled)
        XCTAssertEqual(f.service.attempts.count, 1)
    }
    func testLate401AfterActualWriteKeepsPendingAndDoesNotInvokeNewSessionCallback() async throws {
        let f = try Fixture(); await f.prepare(); f.transport.status = 401
        f.transport.recorder.pausesResponse = true
        let task = Task { await f.model.confirm() }
        await f.transport.recorder.waitUntilSuspended(); f.model.invalidate()
        f.transport.recorder.resumeResponse(); await task.value
        XCTAssertEqual(f.transport.requests.count, 1); XCTAssertEqual(f.model.phase, .invalidated)
        XCTAssertEqual(f.unauthorized.count, 0)
        let pending = try await f.journal.read(); XCTAssertTrue(pending?.value.dispatched == true)
    }
}

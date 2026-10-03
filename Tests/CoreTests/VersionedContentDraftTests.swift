import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class VersionedContentDraftTests: XCTestCase {
    private struct Payload: Codable, Equatable { let title: String }
    private let fixtureURL = URL(string: "https://draft-fixture.example/api-root")!
    private func context(account: Int = 7, epoch: UInt64 = 1, role: String = "player", token: String = "fixture-token", realm: String = "fixture-realm") throws -> RuntimeDependencyContext {
        .init(market: .china, baseURL: fixtureURL, role: role,
              session: try .init(accountID: account, epoch: epoch, namespace: realm, token: token))
    }
    private func identity(owner: Int64 = 7, key: String = "fixture-draft", scope: ContentDraftOwnerScope = .personal) throws -> ContentDraftIdentity {
        try .init(ownerMemberID: owner, businessType: .topic, clientDraftKey: key, scope: scope)
    }
    private func record(version: Int64 = 1, id: Int64 = 19, owner: Int64 = 7, key: String = "fixture-draft",
                        payload: String = "{\"title\":\"synthetic\"}", subject: Int64? = nil,
                        status: String = "DRAFT", hash: String? = nil, device: String = "fixture-device") throws -> ContentDraftRecord {
        var value: [String: Any] = ["id": id, "ownerMemberId": owner, "businessType": "TOPIC", "clientDraftKey": key,
            "payloadJson": payload, "payloadHash": hash ?? ContentDraftRecord.hash(payload),
            "status": status, "version": version, "updatedByDevice": device]
        if let subject { value["subjectId"] = subject }
        return try JSONDecoder().decode(ContentDraftRecord.self, from: JSONSerialization.data(withJSONObject: value))
    }
    private typealias Recorder = ContentDraftRecordingTransport
    private final class Journal: ContentDraftSecureJournal {
        let scope: ContentDraftJournalScope
        var value: ContentDraftPending? { didSet { revision += 1 } }
        private var revision: UInt8 = 0
        private var snapshot: ContentDraftJournalSnapshot? { value.map { .init(value: $0, generation: Data(repeating: revision, count: 32)) } }
        var failRead = false, failClear = false
        init(_ context: RuntimeDependencyContext, _ identity: ContentDraftIdentity) { scope = .init(context: context, identity: identity) }
        func read() throws -> ContentDraftJournalSnapshot? { if failRead { throw ContentDraftIssue.storageUnavailable }; return snapshot }
        func insert(_ value: ContentDraftPending) throws -> ContentDraftJournalSnapshot {
            guard self.value == nil || self.value == value else { throw ContentDraftIssue.storageUnavailable }
            if self.value == nil { self.value = value }; return snapshot!
        }
        func replace(_ old: ContentDraftJournalSnapshot, with new: ContentDraftPending) throws -> ContentDraftJournalSnapshot {
            guard snapshot == old, old.value.mutation == new.mutation else { throw ContentDraftIssue.storageUnavailable }
            value = new; return snapshot!
        }
        func clear(matching value: ContentDraftJournalSnapshot) throws {
            guard !failClear, snapshot == value else { throw ContentDraftIssue.storageUnavailable }; self.value = nil
        }
    }

    private func service(_ recorder: Recorder, _ lease: ContentDraftSessionLease, owner: Int64 = 7,
                         scope: ContentDraftOwnerScope = .personal, onUnauthorized: @escaping (RuntimeDependencyContext) -> Void = { _ in }) throws -> ContentDraftService {
        let grant = try ContentDraftRouteGrant(context: lease.context, ownerMemberID: owner, scope: scope,
            routes: Set(ContentDraftRoute.allCases), expiresAt: Date(timeIntervalSince1970: 10_000))
        return ContentDraftService(api: try .init(baseURL: fixtureURL), transport: recorder, lease: lease,
            grant: grant, now: { Date(timeIntervalSince1970: 100) }, onUnauthorized: onUnauthorized)
    }
    private func assertIssue(_ expected: ContentDraftIssue, _ operation: () async throws -> Void) async {
        do { try await operation(); XCTFail("Expected \(expected)") }
        catch { XCTAssertEqual(error as? ContentDraftIssue, expected) }
    }
    func testCreateRestoreUpdateDeleteUseExactExistingWireContract() async throws {
        let c = try context(), i = try identity(), transport = Recorder(), lease = ContentDraftSessionLease(context: c, current: { c })
        let client = try service(transport, lease)
        let initial = try record(); try transport.returning(initial)
        let model = ContentDraftCoordinator<Payload>(identity: i, service: client, lease: lease, journal: Journal(c, i))
        await model.initialize(); model.prepareSave(.init(title: "synthetic"), subjectID: nil, deviceID: "fixture-device")
        await model.confirm(); XCTAssertEqual(model.phase, .ready)
        let first = try XCTUnwrap(transport.requests.last)
        XCTAssertEqual(first.url?.path, "/api-root/api/content-draft/save"); XCTAssertEqual(first.httpMethod, "POST")
        XCTAssertEqual(first.value(forHTTPHeaderField: "Authorization"), "fixture-token")
        let fields = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(first.httpBody)) as? [String: Any])
        XCTAssertEqual(Set(fields.keys), ["businessType", "clientDraftKey", "payloadJson", "expectedVersion", "deviceId", "scope"])
        XCTAssertEqual(fields["expectedVersion"] as? Int, 0); XCTAssertNil(fields["ownerMemberId"]); XCTAssertNil(fields["operationID"])
        _ = try await client.restore(id: 19, identity: i)
        let restore = try XCTUnwrap(transport.requests.last)
        XCTAssertEqual(restore.value(forHTTPHeaderField: "Content-Type"), "application/x-www-form-urlencoded; charset=utf-8")
        XCTAssertEqual(String(data: try XCTUnwrap(restore.httpBody), encoding: .utf8), "draft_id=19&scope=")
        model.prepareSave(.init(title: "changed"), subjectID: 31, deviceID: "fixture-device")
        let second = try record(version: 2, payload: "{\"title\":\"changed\"}", subject: 31); try transport.returning(second)
        await model.confirm(); XCTAssertEqual(model.document?.record, second)
        model.prepareDelete()
        try transport.returning(record(version: 3, payload: second.payloadJson, subject: 31, status: "DELETED"))
        await model.confirm(); XCTAssertEqual(model.phase, .deleted)
        let deletedFields = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(transport.requests.last?.httpBody)) as? [String: Any])
        XCTAssertEqual(Set(deletedFields.keys), ["id", "expectedVersion", "scope"])
        XCTAssertTrue(transport.requests.allSatisfy { $0.url?.query == nil && $0.value(forHTTPHeaderField: "Cache-Control") == "no-store" })
    }
    func testDefaultGrantAndWrongResolvedOwnerNeverDispatch() async throws {
        let c = try context(), transport = Recorder(), lease = ContentDraftSessionLease(context: c, current: { c })
        let disabled = ContentDraftService(api: try .init(baseURL: fixtureURL), transport: transport, lease: lease)
        await assertIssue(.disabled) { _ = try await disabled.restore(id: 19, identity: self.identity()) }
        let client = try service(transport, lease)
        await assertIssue(.forbidden) { _ = try await client.restore(id: 19, identity: self.identity(owner: 8)) }
        XCTAssertTrue(transport.requests.isEmpty)
    }
    func testEnvelope409403404AreTypedAndNeverExposeServerMessages() async throws {
        let c = try context(), transport = Recorder(), lease = ContentDraftSessionLease(context: c, current: { c }), i = try identity()
        let client = try service(transport, lease)
        for (code, expected) in [(409, ContentDraftIssue.conflict), (403, .forbidden), (404, .notFound)] {
            transport.code(code)
            await assertIssue(expected) { _ = try await client.restore(id: 19, identity: i) }
        }
    }
    func testStaleCompletionAndLate401CannotInvalidateNewSession() async throws {
        let a = try context(), b = try context(account: 8, epoch: 2)
        var current: RuntimeDependencyContext? = a
        let lease = ContentDraftSessionLease(context: a, current: { current }), transport = Recorder()
        var unauthorized = 0
        let client = try service(transport, lease, onUnauthorized: { _ in unauthorized += 1 })
        transport.code(401); transport.pausesResponse = true
        let task = Task { await self.assertIssue(.staleSession) { _ = try await client.restore(id: 19, identity: self.identity()) } }
        await transport.waitUntilSuspended(); current = b; transport.resumeResponse(); await task.value
        XCTAssertEqual(unauthorized, 0)
        current = a
        await assertIssue(.staleSession) { _ = try await client.restore(id: 19, identity: self.identity()) }
        XCTAssertEqual(transport.requests.count, 1)
    }
    func testExplicitRevokeFencesABAEvenWhenContextReturnsEqual() async throws {
        let c = try context(), transport = Recorder(), lease = ContentDraftSessionLease(context: c, current: { c })
        var unauthorized = 0
        let client = try service(transport, lease, onUnauthorized: { _ in unauthorized += 1 })
        transport.code(401); transport.pausesResponse = true
        let task = Task { await self.assertIssue(.staleSession) { _ = try await client.restore(id: 19, identity: self.identity()) } }
        await transport.waitUntilSuspended(); lease.revoke(); transport.resumeResponse(); await task.value
        XCTAssertEqual(unauthorized, 0)
    }
    func testEveryAuthorityDimensionChangesInvalidateBeforeHTTP() async throws {
        let a = try context()
        for other in [try context(account: 8), try context(epoch: 2), try context(role: "merchant"), try context(token: "other-token"), try context(realm: "other-realm")] {
            let transport = Recorder(), lease = ContentDraftSessionLease(context: a, current: { other })
            let client = try service(transport, lease)
            await assertIssue(.staleSession) { _ = try await client.restore(id: 19, identity: self.identity()) }
            XCTAssertTrue(transport.requests.isEmpty)
        }
    }
    func testCurrent401InvokesOnlyCapturedOwnerCallback() async throws {
        let c = try context(), transport = Recorder(), lease = ContentDraftSessionLease(context: c, current: { c })
        var seen: [RuntimeDependencyContext] = []
        let client = try service(transport, lease, onUnauthorized: { seen.append($0) })
        transport.code(401)
        await assertIssue(.unauthorized) { _ = try await client.restore(id: 19, identity: self.identity()) }
        XCTAssertEqual(seen, [c])
    }
    func testMalformedHashOwnerIDTypeAndLossyPayloadAreRejected() throws {
        let i = try identity()
        for value in [try record(hash: String(repeating: "0", count: 64)), try record(owner: 8), try record(id: 0), try record(version: 0), try record(key: "wrong")] {
            XCTAssertThrowsError(try ContentDraftDocument<Payload>(record: value, identity: i))
        }
        XCTAssertThrowsError(try ContentDraftDocument<Payload>(record: record(payload: "{\"title\":\"synthetic\",\"unknown\":true}"), identity: i))
        XCTAssertThrowsError(try ContentDraftDocument<Payload>(record: record(payload: "{\"title\":true}"), identity: i))
    }
    func testLosslessJSONHandlesCanonicalizationWithoutNumericCollision() throws {
        XCTAssertEqual(try ContentDraftJSON.parse("{\"a\":1.00,\"b\":\"a\\/b\"}"), try ContentDraftJSON.parse("{ \"b\": \"a/b\", \"a\": 1e0 }"))
        XCTAssertNotEqual(try ContentDraftJSON.parse("9007199254740992"), try ContentDraftJSON.parse("9007199254740993"))
        XCTAssertNotEqual(try ContentDraftJSON.parse("true"), try ContentDraftJSON.parse("1"))
        XCTAssertNotEqual(try ContentDraftJSON.parse("\"é\""), try ContentDraftJSON.parse("\"e\u{0301}\""))
        for invalid in ["{\"a\":1,\"a\":2}", "01", "1.", "1e", "[1,]", "null junk", "1e999999999999999999"] {
            XCTAssertThrowsError(try ContentDraftJSON.parse(invalid), invalid)
        }
    }
    func testCreateRetryAcceptsLaterIdenticalVersionButUpdateRequiresExactNextVersion() throws {
        let i = try identity(), first = try record()
        let create = try ContentDraftMutation.save(payload: Payload(title: "synthetic"), identity: i, subjectID: nil, deviceID: "fixture-device", baseline: nil)
        try create.validate(receipt: record(version: 6))
        let update = try ContentDraftMutation.save(payload: Payload(title: "synthetic"), identity: i, subjectID: nil, deviceID: "fixture-device", baseline: first)
        XCTAssertThrowsError(try update.validate(receipt: record(version: 3)))
        try update.validate(receipt: record(version: 2))
    }
    func testUnknownCreateRetainsSameKeyBytesAcrossRecreationAndRetry() async throws {
        let c = try context(), i = try identity(), transport = Recorder(), journal = Journal(c, i)
        let firstLease = ContentDraftSessionLease(context: c, current: { c }), client = try service(transport, firstLease)
        let first = ContentDraftCoordinator<Payload>(identity: i, service: client, lease: firstLease, journal: journal)
        await first.initialize(); first.prepareSave(.init(title: "synthetic"), subjectID: nil, deviceID: "fixture-device")
        transport.lose = true; await first.confirm()
        XCTAssertEqual(first.phase, .unknown); XCTAssertTrue(journal.value?.dispatched == true)
        let original = transport.requests[0].httpBody
        first.invalidate(); XCTAssertNotNil(journal.value)
        let secondLease = ContentDraftSessionLease(context: c, current: { c }), secondClient = try service(transport, secondLease)
        let second = ContentDraftCoordinator<Payload>(identity: i, initialPayload: .init(title: "other edit"), service: secondClient, lease: secondLease, journal: journal)
        await second.initialize(); XCTAssertNil(second.localPayload); XCTAssertFalse(second.canPrepare)
        try transport.returning(record()); await second.retryExact()
        XCTAssertEqual(transport.requests[1].httpBody, original); XCTAssertEqual(second.phase, .ready); XCTAssertNil(journal.value)
    }
    func testKnownConflictKeepsLocalEditsAndNeedsNewReviewAfterLatestRead() async throws {
        let c = try context(), i = try identity(), transport = Recorder(), journal = Journal(c, i)
        let lease = ContentDraftSessionLease(context: c, current: { c }), client = try service(transport, lease)
        let model = ContentDraftCoordinator<Payload>(identity: i, serverDraftID: 19, service: client, lease: lease, journal: journal)
        try transport.returning(record()); await model.initialize()
        model.prepareSave(.init(title: "local"), subjectID: nil, deviceID: "fixture-device")
        transport.code(409); await model.confirm()
        XCTAssertEqual(model.phase, .conflict); XCTAssertNil(journal.value); XCTAssertEqual(model.localPayload?.title, "local")
        try transport.returning(record(version: 4, payload: "{\"title\":\"remote\"}")); await model.fetchLatestForConflict()
        XCTAssertEqual(model.document?.record.version, 1); XCTAssertEqual(model.cloudConflict?.record.version, 4)
        model.resolveConflict(useCloudPayload: false)
        XCTAssertEqual(model.localPayload?.title, "local"); XCTAssertNil(model.review)
        await model.confirm(); XCTAssertEqual(transport.requests.count, 3)
        model.prepareSave(.init(title: "local"), subjectID: nil, deviceID: "fixture-device")
        XCTAssertEqual(model.review?.command.expectedVersion, 4)
    }
    func testUnknownThenConflictAndGETCannotUnlockPending() async throws {
        let c = try context(), i = try identity(), transport = Recorder(), journal = Journal(c, i)
        let lease = ContentDraftSessionLease(context: c, current: { c }), client = try service(transport, lease)
        let model = ContentDraftCoordinator<Payload>(identity: i, serverDraftID: 19, service: client, lease: lease, journal: journal)
        try transport.returning(record()); await model.initialize()
        model.prepareSave(.init(title: "synthetic"), subjectID: nil, deviceID: "fixture-device")
        transport.lose = true; await model.confirm(); let saved = journal.value
        transport.code(409); await model.retryExact()
        XCTAssertEqual(model.phase, .unknown); XCTAssertEqual(journal.value, saved)
        try transport.returning(record(version: 4)); await model.fetchLatestForConflict(); model.resolveConflict(useCloudPayload: true)
        XCTAssertEqual(model.phase, .unknown); XCTAssertEqual(journal.value, saved); XCTAssertFalse(model.canPrepare)
    }
    func testLateSaveCannotPoisonNewDraftAndDurableUnknownSurvives() async throws {
        let c = try context(), i = try identity(), transport = Recorder(), journal = Journal(c, i)
        let lease = ContentDraftSessionLease(context: c, current: { c }), client = try service(transport, lease)
        let old = ContentDraftCoordinator<Payload>(identity: i, service: client, lease: lease, journal: journal)
        await old.initialize(); old.prepareSave(.init(title: "synthetic"), subjectID: nil, deviceID: "fixture-device")
        let newIdentity = try identity(key: "new-draft"), newLease = ContentDraftSessionLease(context: c, current: { c })
        let new = try ContentDraftCoordinator<Payload>(identity: newIdentity, initialPayload: .init(title: "new"),
            service: service(transport, newLease), lease: newLease, journal: Journal(c, newIdentity))
        await new.initialize(); transport.pausesResponse = true; try transport.returning(record())
        let task = Task { await old.confirm() }
        await transport.waitUntilSuspended(); old.invalidate(); transport.resumeResponse(); await task.value
        XCTAssertEqual(old.phase, .invalidated); XCTAssertNil(old.document); XCTAssertNotNil(journal.value)
        XCTAssertEqual(new.localPayload?.title, "new"); XCTAssertNil(new.document)
    }
    func testMissingOrWrongScopeJournalCannotAuthorizeWrite() async throws {
        let c = try context(), i = try identity(), transport = Recorder(), lease = ContentDraftSessionLease(context: c, current: { c }), client = try service(transport, lease)
        let noJournal = ContentDraftCoordinator<Payload>(identity: i, service: client, lease: lease)
        await noJournal.initialize(); noJournal.prepareSave(.init(title: "synthetic"), subjectID: nil, deviceID: "fixture-device"); await noJournal.confirm()
        XCTAssertFalse(noJournal.canPrepare); XCTAssertTrue(transport.requests.isEmpty)
        let wrong = Journal(c, try identity(key: "other"))
        let model = ContentDraftCoordinator<Payload>(identity: i, service: client, lease: lease, journal: wrong)
        await model.initialize(); XCTAssertEqual(model.phase, .blocked); XCTAssertTrue(transport.requests.isEmpty)
    }
    func testMalformedAcknowledgmentAndFailedJournalClearKeepPending() async throws {
        let c = try context(), i = try identity(), transport = Recorder(), journal = Journal(c, i)
        let lease = ContentDraftSessionLease(context: c, current: { c }), client = try service(transport, lease)
        let model = ContentDraftCoordinator<Payload>(identity: i, service: client, lease: lease, journal: journal)
        await model.initialize(); model.prepareSave(.init(title: "synthetic"), subjectID: nil, deviceID: "fixture-device")
        try transport.returning(record(key: "other")); await model.confirm(); XCTAssertEqual(model.phase, .unknown)
        try transport.returning(record()); journal.failClear = true; await model.retryExact()
        XCTAssertEqual(model.phase, .unknown); XCTAssertNotNil(journal.value)
    }

    func testMaximumVersionCanBeAcknowledgedButNotIncrementedAgain() throws {
        let i = try identity(), baseline = try record(version: Int64.max - 1)
        let mutation = try ContentDraftMutation.save(payload: Payload(title: "synthetic"), identity: i,
            subjectID: nil, deviceID: "fixture-device", baseline: baseline)
        let terminal = try record(version: Int64.max)
        try mutation.validate(receipt: terminal)
        XCTAssertThrowsError(try ContentDraftMutation.save(payload: Payload(title: "synthetic"), identity: i,
            subjectID: nil, deviceID: "fixture-device", baseline: terminal))
    }
    func testListUsesFormFilterAndRejectsDuplicateOrForeignRows() async throws {
        let c = try context(), transport = Recorder(), lease = ContentDraftSessionLease(context: c, current: { c })
        let client = try service(transport, lease)
        let row = try JSONSerialization.jsonObject(with: JSONEncoder().encode(record()))
        transport.response = (try JSONSerialization.data(withJSONObject: ["code": 200, "data": [row]]), 200)
        let values = try await client.list(type: .topic)
        XCTAssertEqual(values.count, 1)
        XCTAssertEqual(String(data: try XCTUnwrap(transport.requests.last?.httpBody), encoding: .utf8), "business_type=TOPIC&scope=")
        transport.response = (try JSONSerialization.data(withJSONObject: ["code": 200, "data": [row, row]]), 200)
        await assertIssue(.malformed) { _ = try await client.list(type: .topic) }
        let foreign = try JSONSerialization.jsonObject(with: JSONEncoder().encode(record(owner: 88)))
        transport.response = (try JSONSerialization.data(withJSONObject: ["code": 200, "data": [foreign]]), 200)
        await assertIssue(.malformed) { _ = try await client.list(type: .topic) }
    }
    func testExpiredGrantNeverReachesTransport() async throws {
        let c = try context(), transport = Recorder(), lease = ContentDraftSessionLease(context: c, current: { c })
        let grant = try ContentDraftRouteGrant(context: c, ownerMemberID: 7, scope: .personal,
            routes: [.restore], expiresAt: Date(timeIntervalSince1970: 100))
        let client = ContentDraftService(api: try .init(baseURL: fixtureURL), transport: transport, lease: lease,
            grant: grant, now: { Date(timeIntervalSince1970: 100) })
        await assertIssue(.disabled) { _ = try await client.restore(id: 19, identity: self.identity()) }
        XCTAssertTrue(transport.requests.isEmpty)
    }


    func testKnownDuplicateCreateKeyCanRecoverViaExactListIdentity() async throws {
        let c = try context(), i = try identity(), transport = Recorder(), journal = Journal(c, i)
        let lease = ContentDraftSessionLease(context: c, current: { c }), client = try service(transport, lease)
        let model = ContentDraftCoordinator<Payload>(identity: i, service: client, lease: lease, journal: journal)
        await model.initialize(); model.prepareSave(.init(title: "local"), subjectID: nil, deviceID: "fixture-device")
        transport.code(409); await model.confirm(); XCTAssertEqual(model.phase, .conflict)
        let row = try JSONSerialization.jsonObject(with: JSONEncoder().encode(record(version: 4)))
        transport.response = (try JSONSerialization.data(withJSONObject: ["code": 200, "data": [row]]), 200)
        await model.fetchLatestForConflict(); XCTAssertEqual(transport.requests.last?.url?.lastPathComponent, "list")
        model.resolveConflict(useCloudPayload: false)
        model.prepareSave(.init(title: "local"), subjectID: nil, deviceID: "fixture-device")
        XCTAssertEqual(model.review?.command.id, 19); XCTAssertEqual(model.review?.command.expectedVersion, 4)
        XCTAssertEqual(model.review?.command.clientDraftKey, "fixture-draft")
    }


    func testAmbiguousEnvelopeNeverReleasesFirstAttemptJournal() async throws {
        for body in ["{\"code\":409,\"code\":200}", "{\"code\":200,\"code\":409}"] {
            let c = try context(), i = try identity(), transport = Recorder(), journal = Journal(c, i)
            let lease = ContentDraftSessionLease(context: c, current: { c }), client = try service(transport, lease)
            let model = ContentDraftCoordinator<Payload>(identity: i, service: client, lease: lease, journal: journal)
            await model.initialize(); model.prepareSave(.init(title: "synthetic"), subjectID: nil, deviceID: "fixture-device")
            transport.response = (Data(body.utf8), 200); await model.confirm()
            XCTAssertEqual(model.phase, .unknown); XCTAssertEqual(model.issue, .malformed)
            XCTAssertTrue(journal.value?.dispatched == true); XCTAssertFalse(model.canPrepare)
        }
    }
    func testDuplicateIdentityDataAnd401KeysFailBeforeSideEffects() async throws {
        let c = try context(), transport = Recorder(), lease = ContentDraftSessionLease(context: c, current: { c })
        var unauthorized = 0
        let client = try service(transport, lease, onUnauthorized: { _ in unauthorized += 1 })
        let row = try XCTUnwrap(String(data: JSONEncoder().encode(record()), encoding: .utf8))
        let duplicateID = "{\"id\":19," + String(row.dropFirst())
        for body in ["{\"code\":401,\"code\":200}", "{\"code\":200,\"code\":401}",
                     "{\"code\":200,\"data\":" + row + ",\"data\":" + row + "}",
                     "{\"code\":200,\"data\":" + duplicateID + "}"] {
            transport.response = (Data(body.utf8), 200)
            await assertIssue(.malformed) { _ = try await client.restore(id: 19, identity: self.identity()) }
        }
        XCTAssertEqual(unauthorized, 0)
        transport.response = (Data("non-JSON proxy denial".utf8), 401)
        await assertIssue(.unauthorized) { _ = try await client.restore(id: 19, identity: self.identity()) }
        XCTAssertEqual(unauthorized, 1)
    }
    func testNonASCIIAuthorityAliasesAreDifferentLifetimes() async throws {
        let composed = "r\u{00e9}alm", decomposed = "re\u{0301}alm"
        XCTAssertEqual(composed, decomposed) // Swift's default equality is intentionally insufficient here.
        for pair in [(try context(realm: composed), try context(realm: decomposed)),
                     (try context(role: composed), try context(role: decomposed))] {
            var current: RuntimeDependencyContext? = pair.0
            let transport = Recorder(), lease = ContentDraftSessionLease(context: pair.0, current: { current })
            var unauthorized = 0
            let client = try service(transport, lease, onUnauthorized: { _ in unauthorized += 1 })
            transport.code(401); transport.pausesResponse = true
            let task = Task { await self.assertIssue(.staleSession) { _ = try await client.restore(id: 19, identity: self.identity()) } }
            await transport.waitUntilSuspended(); current = pair.1; transport.resumeResponse(); await task.value
            XCTAssertEqual(unauthorized, 0)
            current = pair.0
            await assertIssue(.staleSession) { _ = try await client.restore(id: 19, identity: self.identity()) }
            XCTAssertEqual(transport.requests.count, 1)
        }
    }
    func testAuthorityAliasCannotReuseGrantOrDurableJournal() async throws {
        let a = try context(realm: "r\u{00e9}alm"), b = try context(realm: "re\u{0301}alm")
        let i = try identity(), transport = Recorder(), lease = ContentDraftSessionLease(context: b, current: { b })
        let grant = try ContentDraftRouteGrant(context: a, ownerMemberID: 7, scope: .personal,
            routes: [.restore], expiresAt: Date(timeIntervalSince1970: 10_000))
        let client = ContentDraftService(api: try .init(baseURL: fixtureURL), transport: transport, lease: lease,
            grant: grant, now: { Date(timeIntervalSince1970: 100) })
        await assertIssue(.disabled) { _ = try await client.restore(id: 19, identity: i) }
        let model = ContentDraftCoordinator<Payload>(identity: i, service: try service(transport, lease), lease: lease, journal: Journal(a, i))
        await model.initialize(); XCTAssertEqual(model.phase, .blocked); XCTAssertEqual(model.issue, .storageUnavailable)
        XCTAssertTrue(transport.requests.isEmpty)
    }
    func testFullJournalRecordEqualityPreservesDeviceBytes() throws {
        let a = try record(device: "d\u{00e9}vice"), b = try record(device: "de\u{0301}vice")
        XCTAssertNotEqual(a, b)
        let i = try identity()
        let first = try ContentDraftMutation.delete(identity: i, baseline: a)
        let data = try JSONEncoder().encode(first)
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var baseline = try XCTUnwrap(raw["baseline"] as? [String: Any])
        baseline["updatedByDevice"] = b.updatedByDevice; raw["baseline"] = baseline
        let second = try JSONDecoder().decode(ContentDraftMutation.self, from: JSONSerialization.data(withJSONObject: raw))
        XCTAssertNotEqual(first, second)
    }


    func testServerTrimCannotChangeReviewedKeyOrDeviceIdentity() throws {
        for key in ["\u{0000}key", "key\u{0000}", "\u{001b}key", "key\u{0008}", " key", "key\n"] {
            XCTAssertThrowsError(try identity(key: key))
            XCTAssertThrowsError(try ContentDraftMutation.save(payload: Payload(title: "synthetic"),
                identity: identity(), subjectID: nil, deviceID: key, baseline: nil))
        }
        XCTAssertNoThrow(try identity(key: "key-middle\u{001b}still-exact"))
    }


    func testRequestScopeAliasCannotBypassUncertainOwnerDraftLock() async throws {
        let c = try context(), personal = try identity(), club = try identity(scope: .club)
        let merchant = try identity(scope: .merchant)
        XCTAssertEqual(ContentDraftJournalScope(context: c, identity: personal), ContentDraftJournalScope(context: c, identity: club))
        XCTAssertEqual(ContentDraftJournalScope(context: c, identity: personal), ContentDraftJournalScope(context: c, identity: merchant))
        let transport = Recorder(), journal = Journal(c, personal)
        let oldLease = ContentDraftSessionLease(context: c, current: { c })
        let old = ContentDraftCoordinator<Payload>(identity: personal, service: try service(transport, oldLease), lease: oldLease, journal: journal)
        await old.initialize(); old.prepareSave(.init(title: "synthetic"), subjectID: nil, deviceID: "fixture-device")
        transport.lose = true; await old.confirm(); let pending = journal.value; old.invalidate()
        let newLease = ContentDraftSessionLease(context: c, current: { c })
        let reopened = ContentDraftCoordinator<Payload>(identity: club, service: try service(transport, newLease, scope: .club), lease: newLease, journal: journal)
        await reopened.initialize(); reopened.prepareSave(.init(title: "different"), subjectID: nil, deviceID: "fixture-device"); await reopened.confirm()
        XCTAssertEqual(reopened.phase, .blocked); XCTAssertEqual(reopened.issue, .storageUnavailable)
        XCTAssertEqual(journal.value, pending); XCTAssertEqual(transport.requests.count, 1)
    }

}

private extension ContentDraftRecordingTransport {
    func returning(_ record: ContentDraftRecord) throws {
        let body = try JSONSerialization.jsonObject(with: JSONEncoder().encode(record))
        response = (try JSONSerialization.data(withJSONObject: ["code": 200, "data": body]), 200)
    }
    func code(_ code: Int, http: Int = 200) { response = (Data("{\"code\":\(code),\"msg\":\"untrusted\"}".utf8), http) }
}

extension ContentDraftRecordingTransport {
    func waitUntilSuspended(file: StaticString = #filePath, line: UInt = #line) async {
        let deadline = Date().addingTimeInterval(2)
        while !isAwaitingResponse && Date() < deadline { await Task.yield() }
        XCTAssertTrue(isAwaitingResponse, "Expected suspended response", file: file, line: line)
    }
}

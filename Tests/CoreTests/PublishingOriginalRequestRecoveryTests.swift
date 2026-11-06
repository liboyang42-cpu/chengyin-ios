import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

private final class OriginalRequestTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var handler: ((URLRequest) throws -> [String: Any])?
    var rawHandler: ((URLRequest) throws -> Data)?
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        if let rawHandler { return (try rawHandler(request), 200) }
        guard let handler else { throw URLError(.networkConnectionLost) }
        return (try JSONSerialization.data(withJSONObject: handler(request)), 200)
    }
}
@MainActor private final class OriginalRequestStorage: ProjectEditDataStorage {
    var values: [String: Data] = [:]
    var failRequestWrite = false
    func read(_ key: String) throws -> Data? { values[key] }
    func write(_ value: Data, key: String) throws {
        if failRequestWrite && key.contains("publishing.state.requests.v1.") && !key.hasSuffix(".index") { throw PublishModesError.storage }
        values[key] = value
    }
    func remove(_ key: String) throws { values[key] = nil }
}
@MainActor private final class OriginalRequestJournal: OperationPendingJournal {
    var records: [String: OperationPendingRecord] = [:]
    var failWrite = false
    var failClear = false
    func pending(ownerKey: String, targetKey: String) throws -> OperationPendingRecord? { records[ownerKey + targetKey] }
    func write(_ record: OperationPendingRecord) throws {
        if failWrite { throw PublishModesError.storage }; records[record.ownerKey + record.targetKey] = record
    }
    func clear(_ record: OperationPendingRecord) throws {
        if failClear { throw PublishModesError.storage }
        guard records[record.ownerKey + record.targetKey] == record else { throw PublishModesError.conflict }
        records[record.ownerKey + record.targetKey] = nil
    }
}
@MainActor final class PublishingOriginalRequestRecoveryTests: XCTestCase {
    private let activityTarget = "publishModes:activity:create"
    private func session(_ account: Int = 901) -> PublishingSession { .init(namespace: "request-recovery-fixture", accountID: account, epoch: UUID(), role: "club", region: .china) }
    private func api(_ s: PublishingSession, _ transport: OriginalRequestTransport, _ store: PublishingDraftStore, _ journal: OriginalRequestJournal, write: Bool = true) throws -> PublishingService {
        let config = try APIConfiguration(baseURL: URL(string: "https://example.test")!)
        let paths = [ActivityCreateRequestContract.submitPath, ActivityCreateRequestContract.readPath, ActivityCreateRequestContract.resumePath,
                     ProjectStateRequestContract.contextPath, ProjectStateRequestContract.submitPath, ProjectStateRequestContract.readPath,
                     "api/activity/publish", "api/topic/delete", "api/topic/update_user_status"]
        let approval = try OperationEndpointApproval(baseURL: config.baseURL, namespace: s.namespace, accountID: s.accountID, paths: paths)
        let credentials = try PublishingCredentials(session: s, token: "synthetic-token")
        return PublishingService(configuration: config, transport: transport, approval: write ? approval : nil, journal: journal,
            activityReceiptApproval: approval, activityRequestStore: store, credentials: { credentials })
    }
    private func draft() -> ActivityPublishDraft {
        var d = ActivityPublishDraft(); d.name = "Original activity"; d.description = "Fixture description"; d.coverURL = "fixture://cover"; d.addressName = "Fixture place"
        d.start = "2030-05-01 10:00:00"; d.end = "2030-05-01 12:00:00"; d.playTemplateID = .init(rawValue: 8); d.categoryIDs = [2]
        var t = ActivityPublishTicket(); t.name = "Ticket"; t.price = "0"; t.stock = "2"; t.start = d.start; t.end = d.end; d.tickets = [t]; return d
    }
    private func receipt(_ submit: ActivityCreateRequestContract.Submit, state: String, id: Int? = nil) -> [String: Any] {
        var result: [String: Any] = ["protocolVersion": submit.protocolVersion, "requestId": submit.requestId, "payloadSHA256": submit.payloadSHA256, "state": state]
        if let id { result["originalResult"] = ["activityId": id] }; return result
    }
    private func decode<T: Decodable>(_ type: T.Type, _ value: [String: Any]) throws -> T { try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: value)) }
    private func retainActivity(_ s: PublishingSession, _ store: PublishingDraftStore, _ journal: OriginalRequestJournal) throws -> ActivityCreateRequestContract.Submit {
        let submit = try ActivityCreateRequestContract.Submit(id: UUID(), fields: draft().wire())
        try store.saveActivityRequest(.init(ownerKey: s.storageKey, submit: submit), session: s, expected: nil)
        try journal.write(.init(operationID: UUID(uuidString: submit.requestId)!, ownerKey: s.storageKey, targetKey: activityTarget)); return submit
    }
    private func retainState(_ s: PublishingSession, _ store: PublishingDraftStore, _ journal: OriginalRequestJournal) throws -> ProjectStateRequestContract.Saved {
        let project = try PublishingProject(["id": .number(17), "bizType": .string("topic"), "title": .string("Original project"), "state": .string("offline"), "signupCount": .number(0), "ownerType": .string("member")])
        let context = try decode(ProjectStateRequestContract.Context.self, ["protocolVersion": ProjectStateRequestContract.protocolVersion,
            "kind": "topic", "resourceId": 17, "title": project.title, "online": project.online, "baselineHash": String(repeating: "a", count: 64)])
        let submit = try ProjectStateRequestContract.Submit(id: UUID(), request: PublishingContracts.project(project, action: .remove), project: project, context: context)
        let saved = ProjectStateRequestContract.Saved(ownerKey: s.storageKey, title: project.title, resource: project.resource, action: .remove, submit: submit)
        try store.saveStateRequest(saved, expected: nil, session: s)
        try journal.write(.init(operationID: UUID(uuidString: saved.id)!, ownerKey: s.storageKey, targetKey: saved.targetKey)); return saved
    }
    private func stateReceipt(_ saved: ProjectStateRequestContract.Saved, state: String, applied: Bool? = nil) -> [String: Any] {
        var result: [String: Any] = ["protocolVersion": saved.submit.protocolVersion, "requestId": saved.id,
            "payloadSHA256": saved.submit.payloadSHA256, "originalPath": saved.submit.command!.originalPath,
            "kind": saved.resource.kind.rawValue, "resourceId": saved.resource.value, "state": state]
        if let applied { result["originalResult"] = ["applied": applied] }; return result
    }
    func testActivityReceiptRequiresExactIdentityDigestProtocolAndPositiveCreatedID() throws {
        let original = try ActivityCreateRequestContract.Submit(id: UUID(), fields: draft().wire())
        XCTAssertTrue(original.valid)
        for changes in [["requestId": UUID().uuidString.lowercased()], ["payloadSHA256": String(repeating: "b", count: 64)], ["protocolVersion": "other"], ["state": "SUCCESS"]] {
            var value = receipt(original, state: "COMMITTED", id: 42); value.merge(changes) { _, new in new }
            XCTAssertFalse(try decode(ActivityCreateRequestContract.Receipt.self, value).matches(original))
        }
        for id in [nil, 0, -1] as [Int?] { XCTAssertFalse(try decode(ActivityCreateRequestContract.Receipt.self, receipt(original, state: "COMMITTED", id: id)).matches(original)) }
        var merchant = receipt(original, state: "COMMITTED", id: 42); merchant["merchantId"] = 7
        XCTAssertFalse(try decode(ActivityCreateRequestContract.Receipt.self, merchant).matches(original))
        XCTAssertThrowsError(try ActivityCreateRequestContract.Submit(id: UUID(), fields: ["scope": .string("MERCHANT")]))
    }
    func testUnknownActivityReadOnlyRecoveryKeepsLockOnNotFoundAndRunning() async throws {
        let s = session(), store = PublishingDraftStore(storage: OriginalRequestStorage()), journal = OriginalRequestJournal(), t = OriginalRequestTransport()
        let original = try retainActivity(s, store, journal), service = try api(s, t, store, journal, write: false)
        for state in ["NOT_FOUND", "RUNNING"] {
            t.handler = { _ in ["code": 200, "data": self.receipt(original, state: state)] }
            let result = try await service.readActivityOutcome(session: s)
            XCTAssertFalse(result.terminal); XCTAssertTrue(try service.hasUncertainOutcome(targetKey: activityTarget, session: s))
        }
        XCTAssertEqual(t.requests.map { $0.url!.path }, ["/api/activity/create-requests/read", "/api/activity/create-requests/read"])
        XCTAssertEqual(try store.activityRequest(session: s)?.submit, original)
        XCTAssertFalse(service.mutationsConfigured)
    }
    func testMatchedActivityTerminalReadClearsOnlyOriginalLockAndRetainsEvidence() async throws {
        let s = session(), store = PublishingDraftStore(storage: OriginalRequestStorage()), journal = OriginalRequestJournal(), t = OriginalRequestTransport()
        let original = try retainActivity(s, store, journal), service = try api(s, t, store, journal, write: false)
        t.handler = { _ in ["code": 200, "data": self.receipt(original, state: "COMMITTED", id: 42)] }
        let result = try await service.readActivityOutcome(session: s)
        XCTAssertTrue(result.committed); XCTAssertEqual(result.activityID, 42); XCTAssertTrue(journal.records.isEmpty)
        XCTAssertEqual(try service.retainedActivityReceipt(session: s), result)
        XCTAssertFalse(try service.hasUncertainOutcome(targetKey: activityTarget, session: s))
    }
    func testActivityMalformedReceiptAndTransportFailureKeepOriginalLock() async throws {
        let s = session(), store = PublishingDraftStore(storage: OriginalRequestStorage()), journal = OriginalRequestJournal(), t = OriginalRequestTransport()
        let original = try retainActivity(s, store, journal), service = try api(s, t, store, journal)
        t.handler = { _ in ["code": 200, "data": self.receipt(original, state: "COMMITTED")] }
        do { _ = try await service.readActivityOutcome(session: s); XCTFail("Missing created ID accepted") } catch {}
        t.handler = nil
        do { _ = try await service.readActivityOutcome(session: s); XCTFail("Transport failure accepted") } catch {}
        XCTAssertTrue(try service.hasUncertainOutcome(targetKey: activityTarget, session: s)); XCTAssertNil(try store.activityRequest(session: s)?.receipt)
    }
    func testLegacyCode200WithoutOriginalReceiptStaysUnknown() async throws {
        let s = session(), store = PublishingDraftStore(storage: OriginalRequestStorage()), journal = OriginalRequestJournal(), t = OriginalRequestTransport()
        let service = try api(s, t, store, journal)
        t.handler = { request in request.url?.path == "/api/publish/home" ? ["code": 200, "data": ["role": "club"]] : ["code": 200] }
        let review = try await service.prepareActivity(draft(), session: s), outcome = await service.submit(review)
        XCTAssertEqual(outcome, .unknown); XCTAssertEqual(journal.records.count, 1); XCTAssertNotNil(try store.activityRequest(session: s))
        XCTAssertFalse(t.requests.contains { $0.url?.path == "/api/activity/publish" })
    }
    func testDurableIntentSurvivesJournalFailureAndBlocksFreshDraftAfterRestart() async throws {
        let s = session(), storage = OriginalRequestStorage(), store = PublishingDraftStore(storage: storage), journal = OriginalRequestJournal(), t = OriginalRequestTransport()
        journal.failWrite = true
        t.handler = { _ in ["code": 200, "data": ["role": "club"]] }
        let service = try api(s, t, store, journal), review = try await service.prepareActivity(draft(), session: s)
        let first = await service.submit(review); XCTAssertEqual(first, .notSent)
        let retained = try XCTUnwrap(store.activityRequest(session: s)); XCTAssertTrue(journal.records.isEmpty)
        journal.failWrite = false
        let restarted = try api(s, t, PublishingDraftStore(storage: storage), journal)
        XCTAssertTrue(try restarted.hasUncertainOutcome(targetKey: activityTarget, session: s))
        let fresh = try await restarted.prepareActivity(draft(), session: s), second = await restarted.submit(fresh)
        XCTAssertEqual(second, .unknown); XCTAssertEqual(try store.activityRequest(session: s), retained)
        XCTAssertTrue(t.requests.allSatisfy { $0.url?.path == "/api/publish/home" })
    }
    func testPersistencePrecedesFirstActivityDispatch() async throws {
        let s = session(), store = PublishingDraftStore(storage: OriginalRequestStorage()), journal = OriginalRequestJournal(), t = OriginalRequestTransport()
        let service = try api(s, t, store, journal)
        t.handler = { request in
            if request.url?.path == "/api/publish/home" { return ["code": 200, "data": ["role": "club"]] }
            let original = try JSONDecoder().decode(ActivityCreateRequestContract.Submit.self, from: request.httpBody!)
            XCTAssertEqual(try store.activityRequest(session: s)?.submit, original); XCTAssertEqual(journal.records.count, 1)
            return ["code": 200, "data": self.receipt(original, state: "COMMITTED", id: 42)]
        }
        let review = try await service.prepareActivity(draft(), session: s), result = await service.submit(review)
        XCTAssertEqual(result, .acknowledged); XCTAssertTrue(journal.records.isEmpty)
        let replay = await service.submit(review); XCTAssertEqual(replay, .notSent); XCTAssertEqual(t.requests.count, 3)
    }
    func testStateNotFoundRunningAndMalformedCommitNeverUnlockOrResend() async throws {
        let s = session(), store = PublishingDraftStore(storage: OriginalRequestStorage()), journal = OriginalRequestJournal(), t = OriginalRequestTransport()
        var saved = try retainState(s, store, journal); let service = try api(s, t, store, journal, write: false)
        for state in ["NOT_FOUND", "RUNNING"] {
            let original = saved; t.handler = { _ in ["code": 200, "data": self.stateReceipt(original, state: state)] }
            let result = try await service.readStateOutcome(saved, session: s); XCTAssertFalse(result.terminal)
            saved = try XCTUnwrap(store.stateRequest(id: saved.id, session: s)); XCTAssertTrue(try service.hasUncertainOutcome(targetKey: saved.targetKey, session: s))
        }
        let original = saved; t.handler = { _ in ["code": 200, "data": self.stateReceipt(original, state: "COMMITTED")] }
        do { _ = try await service.readStateOutcome(saved, session: s); XCTFail("Missing applied fact accepted") } catch {}
        XCTAssertEqual(journal.records.count, 1); XCTAssertTrue(t.requests.allSatisfy { $0.url?.path == "/api/project/state-requests/read" })
    }
    func testStateReceiptBindsKindPathResourceAndOriginalRequest() throws {
        let s = session(), store = PublishingDraftStore(storage: OriginalRequestStorage()), journal = OriginalRequestJournal()
        let saved = try retainState(s, store, journal)
        let wrong: [[String: Any]] = [["kind": "activity"], ["resourceId": 18], ["originalPath": "api/topic/update_user_status"], ["requestId": UUID().uuidString.lowercased()], ["payloadSHA256": String(repeating: "b", count: 64)]]
        for changes in wrong {
            var value = stateReceipt(saved, state: "COMMITTED", applied: true); value.merge(changes) { _, new in new }
            XCTAssertFalse(try decode(ProjectStateRequestContract.Receipt.self, value).matches(saved.submit))
        }
    }
    func testStateTerminalReadIndependentOfListPresenceAndWriteApproval() async throws {
        for state in ["COMMITTED", "REJECTED"] {
            let s = session(), store = PublishingDraftStore(storage: OriginalRequestStorage()), journal = OriginalRequestJournal(), t = OriginalRequestTransport()
            let saved = try retainState(s, store, journal), service = try api(s, t, store, journal, write: false)
            t.handler = { _ in ["code": 200, "data": self.stateReceipt(saved, state: state, applied: state == "COMMITTED" ? true : nil)] }
            let result = try await service.readStateOutcome(saved, session: s)
            XCTAssertTrue(result.terminal); XCTAssertTrue(journal.records.isEmpty); XCTAssertEqual(t.requests.count, 1)
            XCTAssertEqual(t.requests[0].url?.path, "/api/project/state-requests/read")
            XCTAssertEqual(try service.stateRequests(session: s).count, 1)
        }
    }
    func testInterruptedStatePersistenceIsDiscoverableAndFailsClosed() throws {
        let s = session(), storage = OriginalRequestStorage(), store = PublishingDraftStore(storage: storage), journal = OriginalRequestJournal()
        storage.failRequestWrite = true
        XCTAssertThrowsError(try retainState(s, store, journal))
        XCTAssertTrue(storage.values.keys.contains { $0.hasSuffix(".index") })
        XCTAssertThrowsError(try PublishingDraftStore(storage: storage).stateRequests(session: s))
        let service = try api(s, OriginalRequestTransport(), store, journal)
        XCTAssertThrowsError(try service.hasUncertainOutcome(targetKey: "publishModes:topic:17", session: s))
    }
    func testAccountIsolationAndStaleSavedStateCannotRead() async throws {
        let s = session(), other = session(902), store = PublishingDraftStore(storage: OriginalRequestStorage()), journal = OriginalRequestJournal(), t = OriginalRequestTransport()
        let saved = try retainState(s, store, journal); _ = try retainActivity(s, store, journal)
        XCTAssertNil(try store.activityRequest(session: other)); XCTAssertTrue(try store.stateRequests(session: other).isEmpty)
        let otherService = try api(other, t, store, journal)
        do { _ = try await otherService.readStateOutcome(saved, session: other); XCTFail("Cross-account read accepted") } catch {}
        XCTAssertTrue(t.requests.isEmpty)
    }
    func testTerminalReceiptCannotBeDowngradedOrRetargeted() throws {
        let s = session(), store = PublishingDraftStore(storage: OriginalRequestStorage()), journal = OriginalRequestJournal()
        let original = try retainActivity(s, store, journal), first = try XCTUnwrap(store.activityRequest(session: s))
        let terminal = try decode(ActivityCreateRequestContract.Receipt.self, receipt(original, state: "COMMITTED", id: 42))
        let finished = ActivityCreateRequestContract.Saved(ownerKey: s.storageKey, submit: original, receipt: terminal)
        try store.saveActivityRequest(finished, session: s, expected: first)
        XCTAssertThrowsError(try store.saveActivityRequest(first, session: s, expected: finished))
        let altered = try ActivityCreateRequestContract.Submit(id: UUID(uuidString: original.requestId)!, fields: ["different": .string("payload")])
        XCTAssertThrowsError(try store.saveActivityRequest(.init(ownerKey: s.storageKey, submit: altered), session: s, expected: finished))
    }
    func testPostProcessingResumeUsesOnlyOriginalResumePath() async throws {
        let s = session(), store = PublishingDraftStore(storage: OriginalRequestStorage()), journal = OriginalRequestJournal(), t = OriginalRequestTransport()
        let original = try retainActivity(s, store, journal), first = try XCTUnwrap(store.activityRequest(session: s))
        var value = receipt(original, state: "COMMITTED", id: 42)
        value["processing"] = ["protocolVersion": "original-activity-create-postprocess-v1", "requestID": original.requestId,
            "payloadSHA256": original.payloadSHA256, "spotCheckState": "FAILED", "audits": [], "media": [], "canResume": true] as [String: Any]
        let receipt = try decode(ActivityCreateRequestContract.Receipt.self, value)
        try store.saveActivityRequest(.init(ownerKey: s.storageKey, submit: original, receipt: receipt), session: s, expected: first)
        t.handler = { _ in ["code": 200, "data": value] }; let service = try api(s, t, store, journal)
        _ = try await service.resumeActivityProcessing(session: s)
        XCTAssertEqual(t.requests.map { $0.url!.path }, ["/api/activity/create-requests/resume-post-processing"])
        let body = try JSONDecoder().decode(ActivityCreateRequestContract.Read.self, from: t.requests[0].httpBody!)
        XCTAssertEqual(body.requestId, original.requestId); XCTAssertEqual(body.payloadSHA256, original.payloadSHA256)
    }
    func testFailedJournalClearKeepsLockEvenWithTerminalReceipt() async throws {
        let s = session(), store = PublishingDraftStore(storage: OriginalRequestStorage()), journal = OriginalRequestJournal(), t = OriginalRequestTransport()
        let original = try retainActivity(s, store, journal), service = try api(s, t, store, journal)
        journal.failClear = true; t.handler = { _ in ["code": 200, "data": self.receipt(original, state: "COMMITTED", id: 42)] }
        do { _ = try await service.readActivityOutcome(session: s); XCTFail("Storage failure hidden") } catch {}
        XCTAssertTrue(try service.hasUncertainOutcome(targetKey: activityTarget, session: s)); XCTAssertTrue(try XCTUnwrap(store.activityRequest(session: s)?.receipt).committed)
    }

    /// Raw bytes are essential here: JSONSerialization cannot emit duplicate object keys.
    private func ambiguousOrUnboundedResponses(_ payload: [String: Any], identityKey: String) throws -> [(String, Data)] {
        let bytes = try JSONSerialization.data(withJSONObject: ["code": 200, "data": payload])
        let text = try XCTUnwrap(String(data: bytes, encoding: .utf8))
        let field = try XCTUnwrap(payload[identityKey])
        let encodedValue = try JSONSerialization.data(withJSONObject: field, options: [.fragmentsAllowed])
        let valueText = try XCTUnwrap(String(data: encodedValue, encoding: .utf8))
        let range = try XCTUnwrap(text.range(of: "\"\(identityKey)\":"))
        var duplicate = text
        duplicate.insert(contentsOf: "\"\(identityKey)\":\(valueText),", at: range.lowerBound)
        let first = try XCTUnwrap(identityKey.utf16.first)
        let escapedKey = String(format: "\\u%04x", Int(first)) + String(identityKey.dropFirst())
        var escapedDuplicate = text
        escapedDuplicate.insert(contentsOf: "\"\(escapedKey)\":\(valueText),", at: range.lowerBound)
        // Valid envelope and business facts, with a deliberately excessive extra root value.
        let tooDeep = String(text.dropLast()) + ",\"probe\":" + String(repeating: "[", count: 40) + "0" + String(repeating: "]", count: 40) + "}"
        var tooLarge = bytes; tooLarge.append(Data(repeating: 32, count: 4 * 1024 * 1024))
        return [("duplicate identity", Data(duplicate.utf8)), ("escaped duplicate identity", Data(escapedDuplicate.utf8)),
                ("excessive depth", Data(tooDeep.utf8)), ("excessive size", tooLarge)]
    }
    private func originalStateFixture() throws -> (PublishingProject, [String: Any], Data) {
        let project = try PublishingProject(["id": .number(17), "bizType": .string("topic"), "title": .string("Original project"), "state": .string("offline"), "signupCount": .number(0), "ownerType": .string("member")])
        let context: [String: Any] = ["protocolVersion": ProjectStateRequestContract.protocolVersion,
            "kind": "topic", "resourceId": 17, "title": project.title, "online": project.online, "baselineHash": String(repeating: "a", count: 64)]
        let page = try JSONEncoder().encode(ProjectEditJSON.object(["code": .number(200), "data": .object(["rows": .array([.object(project.raw)]), "total": .number(1)])]))
        return (project, context, page)
    }
    private var originalStateQuery: PublishingRead { .projects(type: "all", state: "all", ownerType: "all", scope: "", pageSize: 200) }

    func testOriginalStateContextRejectsDuplicateIdentityAndUnboundedRawResponses() async throws {
        let (project, context, page) = try originalStateFixture()
        for (label, malformed) in try ambiguousOrUnboundedResponses(context, identityKey: "resourceId") {
            let s = session(), store = PublishingDraftStore(storage: OriginalRequestStorage()), journal = OriginalRequestJournal(), t = OriginalRequestTransport()
            let service = try api(s, t, store, journal)
            t.rawHandler = { request in request.url?.path == "/api/project/my" ? page : malformed }
            do { _ = try await service.prepareProject(project, action: .remove, query: originalStateQuery, session: s); XCTFail(label) }
            catch { XCTAssertEqual(error as? ApprovedTopicReleaseError, .invalidResponse, label) }
            XCTAssertTrue(journal.records.isEmpty, label); XCTAssertTrue(try store.stateRequests(session: s).isEmpty, label)
            XCTAssertEqual(t.requests.map { $0.url!.path }, ["/api/project/my", "/api/project/state-requests/context"], label)
        }
    }
    func testOriginalActivitySubmitRejectsDuplicateIdentityAndUnboundedRawResponses() async throws {
        for index in 0..<4 {
            let s = session(), store = PublishingDraftStore(storage: OriginalRequestStorage()), journal = OriginalRequestJournal(), t = OriginalRequestTransport()
            let service = try api(s, t, store, journal)
            t.rawHandler = { request in
                if request.url?.path == "/api/publish/home" { return Data(#"{"code":200,"data":{"role":"club"}}"#.utf8) }
                let original = try JSONDecoder().decode(ActivityCreateRequestContract.Submit.self, from: request.httpBody!)
                return try self.ambiguousOrUnboundedResponses(self.receipt(original, state: "COMMITTED", id: 42), identityKey: "requestId")[index].1
            }
            let review = try await service.prepareActivity(draft(), session: s), result = await service.submit(review)
            XCTAssertEqual(result, .unknown); XCTAssertEqual(journal.records.count, 1)
            XCTAssertNil(try store.activityRequest(session: s)?.receipt)
            XCTAssertTrue(try service.hasUncertainOutcome(targetKey: activityTarget, session: s))
            XCTAssertEqual(t.requests.map { $0.url!.path }, ["/api/publish/home", "/api/publish/home", "/api/activity/create-requests/submit"])
        }
    }
    func testOriginalStateSubmitRejectsDuplicateIdentityAndUnboundedRawResponses() async throws {
        let (project, context, page) = try originalStateFixture()
        for index in 0..<4 {
            let s = session(), store = PublishingDraftStore(storage: OriginalRequestStorage()), journal = OriginalRequestJournal(), t = OriginalRequestTransport()
            let service = try api(s, t, store, journal)
            t.rawHandler = { request in
                if request.url?.path == "/api/project/my" { return page }
                if request.url?.path == "/api/project/state-requests/context" { return try JSONSerialization.data(withJSONObject: ["code": 200, "data": context]) }
                let original = try JSONDecoder().decode(ProjectStateRequestContract.Submit.self, from: request.httpBody!)
                let saved = ProjectStateRequestContract.Saved(ownerKey: s.storageKey, title: project.title, resource: project.resource, action: .remove, submit: original)
                return try self.ambiguousOrUnboundedResponses(self.stateReceipt(saved, state: "COMMITTED", applied: true), identityKey: "payloadSHA256")[index].1
            }
            let review = try await service.prepareProject(project, action: .remove, query: originalStateQuery, session: s)
            let result = await service.submit(review)
            XCTAssertEqual(result, .unknown); XCTAssertEqual(journal.records.count, 1)
            let saved = try XCTUnwrap(store.stateRequests(session: s).first); XCTAssertNil(saved.receipt)
            XCTAssertTrue(try service.hasUncertainOutcome(targetKey: saved.targetKey, session: s))
            XCTAssertEqual(t.requests.map { $0.url!.path }, ["/api/project/my", "/api/project/state-requests/context", "/api/project/my", "/api/project/state-requests/submit"])
        }
    }
    func testOriginalActivityReadAndResumeRejectDuplicateIdentityAndUnboundedRawResponses() async throws {
        for resume in [false, true] {
            for index in 0..<4 {
                let s = session(), store = PublishingDraftStore(storage: OriginalRequestStorage()), journal = OriginalRequestJournal(), t = OriginalRequestTransport()
                let original = try retainActivity(s, store, journal), service = try api(s, t, store, journal)
                var value = receipt(original, state: "COMMITTED", id: 42)
                if resume {
                    value["processing"] = ["protocolVersion": "original-activity-create-postprocess-v1", "requestID": original.requestId,
                        "payloadSHA256": original.payloadSHA256, "spotCheckState": "FAILED", "audits": [], "media": [], "canResume": true] as [String: Any]
                    let receipt = try decode(ActivityCreateRequestContract.Receipt.self, value)
                    let first = try XCTUnwrap(store.activityRequest(session: s))
                    try store.saveActivityRequest(.init(ownerKey: s.storageKey, submit: original, receipt: receipt), session: s, expected: first)
                }
                let before = try XCTUnwrap(store.activityRequest(session: s))
                let (label, malformed) = try ambiguousOrUnboundedResponses(value, identityKey: "requestId")[index]
                t.rawHandler = { _ in malformed }
                do {
                    if resume { _ = try await service.resumeActivityProcessing(session: s) }
                    else { _ = try await service.readActivityOutcome(session: s) }
                    XCTFail(label)
                } catch { XCTAssertEqual(error as? ApprovedTopicReleaseError, .invalidResponse, label) }
                XCTAssertEqual(try store.activityRequest(session: s), before, label); XCTAssertEqual(journal.records.count, 1, label)
                XCTAssertTrue(try service.hasUncertainOutcome(targetKey: activityTarget, session: s), label)
                XCTAssertEqual(t.requests.map { $0.url!.path }, [resume ? "/api/activity/create-requests/resume-post-processing" : "/api/activity/create-requests/read"], label)
            }
        }
    }
    func testOriginalStateReadRejectsDuplicateIdentityAndUnboundedRawResponses() async throws {
        for index in 0..<4 {
            let s = session(), store = PublishingDraftStore(storage: OriginalRequestStorage()), journal = OriginalRequestJournal(), t = OriginalRequestTransport()
            let saved = try retainState(s, store, journal), service = try api(s, t, store, journal, write: false)
            let (label, malformed) = try ambiguousOrUnboundedResponses(stateReceipt(saved, state: "COMMITTED", applied: true), identityKey: "resourceId")[index]
            t.rawHandler = { _ in malformed }
            do { _ = try await service.readStateOutcome(saved, session: s); XCTFail(label) }
            catch { XCTAssertEqual(error as? ApprovedTopicReleaseError, .invalidResponse, label) }
            XCTAssertEqual(try store.stateRequest(id: saved.id, session: s), saved, label); XCTAssertEqual(journal.records.count, 1, label)
            XCTAssertTrue(try service.hasUncertainOutcome(targetKey: saved.targetKey, session: s), label)
            XCTAssertEqual(t.requests.map { $0.url!.path }, ["/api/project/state-requests/read"], label)
        }
    }
}

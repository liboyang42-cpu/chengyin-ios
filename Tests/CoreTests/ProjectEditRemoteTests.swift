import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class ProjectEditRemoteTests: XCTestCase {
    private final class Owner {
        var session: ProjectEditSession? = try? .init(accountID: 901, epoch: 1, storageNamespace: "remote-edit-test")
    }
    private final class Storage: ProjectEditDataStorage {
        var data: [String: Data] = [:]; var events: [String] = []
        var failWrite = false; var failRemove = false; var onWrite: (() -> Void)?
        func read(_ key: String) throws -> Data? { data[key] }
        func write(_ value: Data, key: String) throws {
            events.append("write"); if failWrite { throw ProjectEditError.persistenceUnavailable }
            data[key] = value; let callback = onWrite; onWrite = nil; callback?()
        }
        func remove(_ key: String) throws {
            events.append("remove"); if failRemove { throw ProjectEditError.persistenceUnavailable }; data[key] = nil
        }
    }
    private final class Transport: HTTPTransport {
        var data: Data; var status = 200; var requests: [URLRequest] = []; var beforeReply: (() async -> Void)?
        init(_ data: Data) { self.data = data }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request); if let beforeReply { await beforeReply() }; return (data, status)
        }
    }
    private func setup(_ product: ProjectEditProduct = .freeExplore, completed: Bool? = nil) async throws -> (ProjectEditCoordinator, Owner, Storage, ProjectEditLocalStore, Transport) {
        let owner = Owner(), storage = Storage(), store = ProjectEditLocalStore(storage: storage)
        let wire = Transport(try ProjectEditRemoteFixtures.detail(product: product))
        let service = ProjectEditHTTPService(configuration: try .init(baseURL: URL(string: "https://example.com")!), transport: wire,
            owner: .personal, currentCredentials: { owner.session.flatMap { try? .init(session: $0, token: "synthetic-test-token") } })
        var placeholder = ProjectEditDraft(product: .city); placeholder.name = "Never rendered placeholder"
        let co = ProjectEditCoordinator(initial: .init(topicID: 71, draft: placeholder), service: service, store: store, currentSession: { owner.session })
        if let completed {
            let session = try XCTUnwrap(owner.session), identity = try ProjectEditDraftIdentity(topicID: 71)
            let record = ProjectEditPending(operationID: UUID(), ownerKey: session.ownerKey, identity: identity,
                payload: ["id": .number(71), "description": .string("e\u{301}")], completedTopicID: completed ? 71 : nil, serverAcknowledged: completed)
            try store.savePending(record, session: session)
        }
        await co.load(); return (co, owner, storage, store, wire)
    }
    func testOwnedRowTargetsOnlySupportedTopicScopesAndNeverGuessesMode() throws {
        for (kind, owner, valid) in [("topic", "member", true), ("topic", "merchant", true), ("topic", "club", false), ("topic", "", false), ("activity", "member", false), ("template", "member", false)] {
            let row = try JSONDecoder().decode(CreatorContentProject.self, from: Data("{\"id\":71,\"bizType\":\"\(kind)\",\"ownerType\":\"\(owner)\",\"title\":\"Synthetic\"}".utf8)), scope = UUID()
            let target = ProjectEditRemoteTarget(project: row, readerScope: scope)
            XCTAssertEqual(target != nil, valid); if valid { XCTAssertEqual(target?.topicID, 71); XCTAssertEqual(target?.readerScope, scope) }
        }
    }
    func testFreshActualHTTPAdapterReadRestoresBothModesRevisionStoryAndExactNodeBytes() async throws {
        for product in ProjectEditProduct.allCases {
            let (co, _, _, _, wire) = try await setup(product)
            let draft = try XCTUnwrap(co.snapshot?.draft)
            XCTAssertEqual(draft.product, product); XCTAssertEqual(draft.baseRevision, "fixture-r2"); XCTAssertEqual(co.snapshot?.topicID, 71)
            XCTAssertEqual(Array(draft.chapters[0].nodes[0].description.utf8), Array("  Raw e\u{301}\n".utf8))
            XCTAssertEqual(draft.chapters[0].nodes[0].templateID, 73); XCTAssertEqual(draft.chapters[0].nodes[0].nodeTime, 45)
            XCTAssertEqual(draft.chapters[0].blocks != nil, product == .city)
            if product == .city { XCTAssertEqual(draft.chapters[0].blocks?.last?.nodeID, draft.chapters[0].nodes[0].id) }
            XCTAssertEqual(wire.requests.count, 1); XCTAssertEqual(wire.requests[0].url?.path, "/api/topic/edit-detail")
            XCTAssertTrue(String(decoding: wire.requests[0].httpBody ?? Data(), as: UTF8.self).contains("scope"))
            XCTAssertFalse(co.canSubmit); co.prepare(draft); let review = try XCTUnwrap(co.confirmation)
            await co.confirm(review); XCTAssertEqual(wire.requests.count, 1)
        }
    }
    func testForbiddenAndMalformedRereadsKeepUnknownRecordProtected() async throws {
        for malformed in [false, true] {
            let (co, owner, storage, _, wire) = try await setup(completed: false), before = storage.data
            co.leaveScreen(); wire.data = malformed ? Data(#"{"code":200,"data":{"editScope":"FULL","topic":{"id":71,"productType":9,"updateTime":"r3"},"chapters":[],"tickets":[]}}"#.utf8) : Data(#"{"code":403,"msg":"Denied"}"#.utf8)
            wire.status = malformed ? 200 : 403
            await co.load(); XCTAssertEqual(co.state, .blocked); XCTAssertTrue(co.isLocked)
            XCTAssertEqual(storage.data, before); XCTAssertNotNil(owner.session); XCTAssertNil(co.acknowledgedContinuation)
        }
    }
    func testAcknowledgedContinuationRequiresExplicitActionAndWritesBaselineBeforeClear() async throws {
        let (co, owner, storage, store, wire) = try await setup(completed: true)
        let captured = try XCTUnwrap(co.acknowledgedContinuation), before = storage.data
        XCTAssertEqual(wire.requests.count, 1); XCTAssertEqual(storage.data, before)
        wire.data = try ProjectEditRemoteFixtures.detail(product: .freeExplore, revision: "fixture-r3")
        storage.events = []; let success = await co.continueAcknowledged(captured); XCTAssertTrue(success)
        XCTAssertEqual(storage.events, ["write", "remove"]); XCTAssertEqual(co.state, .idle); XCTAssertNil(co.pending)
        XCTAssertEqual(co.snapshot?.draft.baseRevision, "fixture-r3"); XCTAssertEqual(wire.requests.count, 2)
        XCTAssertNil(try store.pending(session: XCTUnwrap(owner.session), identity: captured.completed.identity))
        let result1 = await co.continueAcknowledged(captured); XCTAssertFalse(result1); XCTAssertEqual(wire.requests.count, 2)
    }
    func testBaselineWriteAndPendingRemovalFailuresKeepExplicitRecoverableCompletion() async throws {
        for failWrite in [true, false] {
            let (co, _, storage, _, wire) = try await setup(completed: true)
            let capture = try XCTUnwrap(co.acknowledgedContinuation), before = storage.data
            storage.failWrite = failWrite; storage.failRemove = !failWrite
            let success = await co.continueAcknowledged(capture); XCTAssertFalse(success); XCTAssertEqual(co.state, .acknowledged)
            XCTAssertNotNil(co.pending); XCTAssertNil(co.confirmation)
            if failWrite { XCTAssertEqual(storage.data, before); XCTAssertFalse(storage.events.contains("remove")) }
            else { XCTAssertEqual(co.messageKey, "projectRemote.continuationIncomplete"); XCTAssertGreaterThan(storage.data.count, before.count) }
            storage.failWrite = false; storage.failRemove = false
            let retry = try XCTUnwrap(co.acknowledgedContinuation); let result2 = await co.continueAcknowledged(retry); XCTAssertTrue(result2)
            XCTAssertEqual(wire.requests.filter { $0.url?.path != "/api/topic/edit-detail" }.count, 0)
        }
    }
    func testExactRecordCASRejectsReplacementBeforeAndAfterBaselineWrite() async throws {
        for midWrite in [false, true] {
            let (co, owner, storage, store, _) = try await setup(completed: true), session = try XCTUnwrap(owner.session)
            let capture = try XCTUnwrap(co.acknowledgedContinuation)
            var replacement = capture.completed; replacement.payload["description"] = .string("é")
            XCTAssertEqual(replacement.payload, capture.completed.payload) // Swift String equality is canonical.
            XCTAssertFalse(ProjectEditLocalStore.exactPending(replacement, capture.completed))
            if midWrite { storage.onWrite = { try? store.savePending(replacement, session: session) } }
            else { try store.savePending(replacement, session: session) }
            storage.events = []; let result3 = await co.continueAcknowledged(capture); XCTAssertFalse(result3)
            XCTAssertFalse(storage.events.contains("remove")); XCTAssertTrue(ProjectEditLocalStore.exactPending(try XCTUnwrap(store.pending(session: session, identity: replacement.identity)), replacement))
        }
    }
    func testOldContinuationAfterBackOrSameAccountReauthenticationDoesNothing() async throws {
        for changeSession in [false, true] {
            let (co, owner, storage, _, wire) = try await setup(completed: true), capture = try XCTUnwrap(co.acknowledgedContinuation)
            if changeSession { owner.session = try .init(accountID: 901, epoch: 2, storageNamespace: "remote-edit-test"); co.synchronizeSession(); await co.load() }
            else { co.leaveScreen() }
            let before = storage.data, count = wire.requests.count
            let result4 = await co.continueAcknowledged(capture); XCTAssertFalse(result4); XCTAssertEqual(storage.data, before); XCTAssertEqual(wire.requests.count, count)
        }
    }
    func testAccountChangeDuringFreshContinuationCannotSaveOrClearOldCompletion() async throws {
        let (co, owner, storage, _, wire) = try await setup(completed: true), capture = try XCTUnwrap(co.acknowledgedContinuation), before = storage.data
        wire.beforeReply = { owner.session = try? .init(accountID: 902, epoch: 2, storageNamespace: "remote-edit-test") }
        let result5 = await co.continueAcknowledged(capture); XCTAssertFalse(result5); XCTAssertEqual(storage.data, before); XCTAssertNil(co.confirmation)
    }
    func testAccountChangeDuringBaselineWriteCannotRemoveOldCompletion() async throws {
        let (co, owner, storage, store, _) = try await setup(completed: true), original = try XCTUnwrap(owner.session)
        let capture = try XCTUnwrap(co.acknowledgedContinuation)
        storage.onWrite = { owner.session = try? .init(accountID: 902, epoch: 2, storageNamespace: "remote-edit-test") }
        storage.events = []; let result = await co.continueAcknowledged(capture); XCTAssertFalse(result)
        XCTAssertEqual(storage.events, ["write"])
        XCTAssertTrue(ProjectEditLocalStore.exactPending(try XCTUnwrap(store.pending(session: original, identity: capture.completed.identity)), capture.completed))
    }
    func testFutureCompletionFieldsAreNotDiscardedByLossyProjection() async throws {
        let (co, _, storage, _, _) = try await setup(completed: true), capture = try XCTUnwrap(co.acknowledgedContinuation)
        let key = try XCTUnwrap(storage.data.keys.first)
        var raw = try JSONDecoder().decode([String: ProjectEditJSON].self, from: XCTUnwrap(storage.data[key]))
        raw["futureRetentionRule"] = .object(["retain": .bool(true)])
        storage.data[key] = try JSONEncoder().encode(raw); let before = storage.data
        storage.events = []; let result = await co.continueAcknowledged(capture)
        XCTAssertFalse(result); XCTAssertEqual(storage.data, before); XCTAssertTrue(storage.events.isEmpty)
    }
    func testUnknownMatchingReadbackNeverOffersContinuationOrReconciliation() async throws {
        let (co, _, storage, _, wire) = try await setup(completed: false), before = storage.data
        XCTAssertEqual(co.state, .unknown); XCTAssertTrue(co.isLocked); XCTAssertNil(co.acknowledgedContinuation)
        await co.checkOutcome(); XCTAssertEqual(wire.requests.count, 1); XCTAssertEqual(storage.data, before)
        if let draft = co.snapshot?.draft { co.prepare(draft) }; XCTAssertNil(co.confirmation)
    }
}

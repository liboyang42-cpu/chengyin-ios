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
            let completed = capture.completed
            var payload = completed.payload; payload["description"] = .string("é")
            let replacement = ProjectEditPending(operationID: completed.operationID,
                ownerKey: completed.ownerKey, identity: completed.identity, payload: payload,
                dispatchStarted: completed.dispatchStarted, baseline: completed.baseline,
                completedTopicID: completed.completedTopicID, serverAcknowledged: completed.serverAcknowledged,
                bundleAcknowledgment: completed.bundleAcknowledgment)
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

    func testSellingFrozenDetailRetainsCanonicalIDsAndRejectsUnknownScopes() throws {
        for product in ProjectEditProduct.allCases { for owner in [ProjectEditOwner.personal, .merchant] {
            let data = try ProjectEditRemoteFixtures.detail(product: product, scope: .sellingFrozen)
            let snapshot = try ProjectEditContract.decodeEditDetail(data, expectedTopicID: 71, owner: owner)
            XCTAssertEqual(snapshot.scope, .sellingFrozen); XCTAssertFalse(snapshot.scope.allowsEditing)
            XCTAssertEqual(snapshot.draft.owner, owner); XCTAssertEqual(snapshot.draft.product, product)
            XCTAssertEqual(snapshot.draft.chapters[0].preserved["id"], .number(11))
            XCTAssertEqual(snapshot.draft.chapters[0].nodes[0].localMetadata["id"], .number(22))
            XCTAssertEqual(snapshot.draft.chapters[0].nodes[0].templateID, 73)
            if product == .city { XCTAssertEqual(snapshot.draft.chapters[0].blocks?.last?.nodeID, snapshot.draft.chapters[0].nodes[0].id) }
            let unknown = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "SELLING_FROZEN", with: "FUTURE_SCOPE")
            XCTAssertThrowsError(try ProjectEditContract.decodeEditDetail(Data(unknown.utf8), expectedTopicID: 71, owner: owner))
        } }
    }
    func testFrozenPayloadAndRawPathsRejectBeforePartialDraftDateConversion() throws {
        let partial = ProjectEditDraft(), frozen = ProjectEditSnapshot(topicID: 71, scope: .sellingFrozen, draft: .init())
        XCTAssertThrowsError(try ProjectEditContract.payload(partial, topicID: 71, scope: .sellingFrozen))
        XCTAssertFalse(ProjectEditValidation.issues(partial, scope: .sellingFrozen).isEmpty)
        for requested in [ProjectEditScope.full, .whitelist] {
            XCTAssertThrowsError(try ProjectEditContract.payload(partial, topicID: 71, scope: requested, baseline: frozen))
        }
        for product in ProjectEditProduct.allCases {
            let body = try ProjectEditContract.payload(ProjectEditSyntheticFixtures.draft(product: product), topicID: 71, scope: .full)
            XCTAssertThrowsError(try ProjectEditStoryContract.path(payload: body, baseline: frozen))
            XCTAssertThrowsError(try ProjectEditStoryContract.validatePayload(body, baseline: frozen))
        }
        XCTAssertThrowsError(try ProjectEditStoryContract.path(payload: ["id": .number(71), "name": .string("No whitelist bypass")], baseline: frozen))
    }
    func testFrozenReopenPreservesLocalDraftAndBlocksRestoreDiscardAndSave() async throws {
        let (co, owner, storage, store, wire) = try await setup()
        let session = try XCTUnwrap(owner.session), identity = try XCTUnwrap(co.identity)
        var local = try XCTUnwrap(co.snapshot?.draft); local.name = "Retain unsent local edit"
        try store.save(local, session: session, identity: identity); let saved = storage.data
        co.leaveScreen(); wire.data = try ProjectEditRemoteFixtures.detail(product: .freeExplore, scope: .sellingFrozen)
        await co.load()
        XCTAssertEqual(co.state, .idle); XCTAssertTrue(co.isReadOnly); XCTAssertFalse(co.canSubmit)
        XCTAssertEqual(co.snapshot?.draft.name, "Owned fixture route")
        XCTAssertNil(co.restoredDraft()); XCTAssertFalse(co.saveLocal(local)); co.discardLocalDraft(); co.prepare(local)
        XCTAssertNil(co.confirmation); XCTAssertEqual(storage.data, saved)
        guard case .ready(let retained) = co.restore else { return XCTFail("Local draft should remain available for a later editable read") }
        XCTAssertEqual(retained.draft, local)
        co.leaveScreen(); wire.data = try ProjectEditRemoteFixtures.detail(product: .freeExplore)
        await co.load(); XCTAssertFalse(co.isReadOnly); XCTAssertEqual(co.restoredDraft()?.name, local.name)
    }
    func testUnknownFrozenRereadNeverConfirmsClearsOrReplaysOriginalSave() async throws {
        let (co, owner, storage, store, wire) = try await setup(completed: false)
        let original = try XCTUnwrap(co.pending), session = try XCTUnwrap(owner.session)
        try store.save(try XCTUnwrap(co.snapshot?.draft), session: session, identity: original.identity)
        let saved = storage.data
        co.leaveScreen(); wire.data = try ProjectEditRemoteFixtures.detail(product: .city, scope: .sellingFrozen)
        await co.load(); await co.checkOutcome(); co.discardLocalDraft()
        XCTAssertTrue(co.isReadOnly); XCTAssertTrue(co.isLocked); XCTAssertEqual(co.state, .unknown)
        XCTAssertEqual(co.pending?.operationID, original.operationID); XCTAssertNotEqual(co.pending?.serverAcknowledged, true)
        XCTAssertNil(co.acknowledgedContinuation); XCTAssertEqual(storage.data, saved)
        XCTAssertEqual(wire.requests.map { $0.url!.path }, ["/api/topic/edit-detail", "/api/topic/edit-detail"])
        var placeholder = ProjectEditDraft(); placeholder.owner = .personal
        let service = ProjectEditHTTPService(configuration: try .init(baseURL: URL(string: "https://example.com")!), transport: wire,
            owner: .personal, currentCredentials: { try? .init(session: session, token: "synthetic-test-token") })
        let reopened = ProjectEditCoordinator(initial: .init(topicID: 71, draft: placeholder), service: service, store: store, currentSession: { session })
        await reopened.load(); XCTAssertTrue(reopened.isLocked); XCTAssertTrue(reopened.isReadOnly)
        XCTAssertEqual(reopened.pending?.operationID, original.operationID); XCTAssertEqual(storage.data, saved)
    }
    func testAcknowledgedFrozenReadRetainsDraftAndJournalUntilEditableContinuation() async throws {
        let (co, owner, storage, store, wire) = try await setup(completed: true)
        let session = try XCTUnwrap(owner.session), original = try XCTUnwrap(co.pending)
        var local = try XCTUnwrap(co.snapshot?.draft); local.name = "Submitted local content"
        try store.save(local, session: session, identity: original.identity); let saved = storage.data
        wire.data = try ProjectEditRemoteFixtures.detail(product: .city, revision: "fixture-r3", scope: .sellingFrozen)
        storage.events = []
        let read = await co.continueAcknowledged(try XCTUnwrap(co.acknowledgedContinuation))
        XCTAssertTrue(read); XCTAssertTrue(co.isReadOnly); XCTAssertEqual(co.state, .acknowledged)
        XCTAssertEqual(co.snapshot?.draft.baseRevision, "fixture-r3"); XCTAssertEqual(co.snapshot?.draft.product, .city)
        XCTAssertEqual(co.pending?.operationID, original.operationID); XCTAssertEqual(storage.data, saved); XCTAssertTrue(storage.events.isEmpty)
        let reread = await co.continueAcknowledged(try XCTUnwrap(co.acknowledgedContinuation))
        XCTAssertTrue(reread); XCTAssertEqual(storage.data, saved)
        wire.data = try ProjectEditRemoteFixtures.detail(product: .freeExplore, revision: "fixture-r4")
        let continued = await co.continueAcknowledged(try XCTUnwrap(co.acknowledgedContinuation))
        XCTAssertTrue(continued); XCTAssertFalse(co.isReadOnly); XCTAssertEqual(co.state, .idle); XCTAssertNil(co.pending)
        XCTAssertEqual(storage.events, ["write", "remove"]); XCTAssertEqual(co.snapshot?.draft.baseRevision, "fixture-r4")
    }
    func testFailedFrozenRefreshRetainsOriginalJournalAndCanReread() async throws {
        let (co, _, storage, _, wire) = try await setup(completed: true), saved = storage.data
        wire.data = try ProjectEditRemoteFixtures.detail(product: .freeExplore, scope: .sellingFrozen)
        let frozen = await co.continueAcknowledged(try XCTUnwrap(co.acknowledgedContinuation)); XCTAssertTrue(frozen)
        wire.status = 503
        let failed = await co.continueAcknowledged(try XCTUnwrap(co.acknowledgedContinuation))
        XCTAssertFalse(failed); XCTAssertTrue(co.isReadOnly); XCTAssertEqual(co.state, .acknowledged)
        XCTAssertEqual(co.messageKey, "projectRemote.readFailed"); XCTAssertEqual(storage.data, saved)
        wire.status = 200
        let recovered = await co.continueAcknowledged(try XCTUnwrap(co.acknowledgedContinuation))
        XCTAssertTrue(recovered); XCTAssertEqual(storage.data, saved)
    }
    func testFrozenLateReadCannotReplaceChangedSessionOrPending() async throws {
        for changeSession in [true, false] {
            let (co, owner, storage, store, wire) = try await setup(completed: true)
            let session = try XCTUnwrap(owner.session), capture = try XCTUnwrap(co.acknowledgedContinuation), saved = storage.data
            wire.data = try ProjectEditRemoteFixtures.detail(product: .freeExplore, revision: "frozen-late", scope: .sellingFrozen)
            wire.beforeReply = {
                if changeSession { owner.session = try? .init(accountID: 902, epoch: 2, storageNamespace: "remote-edit-test") }
                else {
                    var replacement = capture.completed; replacement.completedTopicID = nil; replacement.serverAcknowledged = nil
                    try? store.savePending(replacement, session: session)
                }
            }
            storage.events = []
            let result = await co.continueAcknowledged(capture)
            XCTAssertFalse(result); XCTAssertNotEqual(co.snapshot?.draft.baseRevision, "frozen-late")
            XCTAssertFalse(storage.events.contains("remove"))
            if changeSession { XCTAssertEqual(storage.data, saved) }
            else { XCTAssertEqual(co.state, .unknown); XCTAssertTrue(co.isLocked) }
        }
    }
    func testApprovedHTTPServiceRefusesFrozenBaselineAndFreshFreezeWithoutDispatch() async throws {
        let owner = Owner(), session = try XCTUnwrap(owner.session), storage = Storage(), store = ProjectEditLocalStore(storage: storage)
        let full = try ProjectEditContract.decodeEditDetail(ProjectEditRemoteFixtures.detail(product: .freeExplore), expectedTopicID: 71, owner: .personal)
        let frozen = ProjectEditSnapshot(topicID: 71, scope: .sellingFrozen, draft: full.draft)
        let payload = try ProjectEditContract.payload(full.draft, topicID: 71, scope: .full, baseline: full)
        let wire = Transport(try ProjectEditRemoteFixtures.detail(product: .freeExplore, scope: .sellingFrozen))
        let configuration = try APIConfiguration(baseURL: URL(string: "https://example.com")!)
        let approval = try OperationEndpointApproval(baseURL: configuration.baseURL, namespace: session.storageNamespace, accountID: session.accountID,
            paths: ["api/topic/update", "api/topic/v2/update"])
        let service = ProjectEditHTTPService(configuration: configuration, transport: wire, owner: .personal, approval: approval, store: store,
            currentCredentials: { try? .init(session: session, token: "synthetic-test-token") })
        for baseline in [frozen, full] {
            let operation = try ProjectEditPending(operationID: UUID(), ownerKey: session.ownerKey, identity: .init(topicID: 71), payload: payload, baseline: baseline)
            try store.savePending(operation, session: session); let saved = storage.data
            let result = await service.submit(operation, session: session)
            XCTAssertEqual(result, .notSent); XCTAssertEqual(storage.data, saved)
            XCTAssertNotEqual(try store.pending(session: session, identity: operation.identity)?.dispatchStarted, true)
        }
        XCTAssertEqual(wire.requests.map { $0.url!.path }, ["/api/topic/edit-detail"])
    }
    func testFreezeBetweenReviewAndConfirmationLeavesLocalDraftAndAllowsReadback() async throws {
        let owner = Owner(), session = try XCTUnwrap(owner.session), storage = Storage(), store = ProjectEditLocalStore(storage: storage)
        let initial = ProjectEditSyntheticFixtures.snapshot(), service = ProjectEditSyntheticService(snapshot: initial)
        let co = ProjectEditCoordinator(initial: initial, service: service, store: store, currentSession: { owner.session })
        await co.load(); var edited = initial.draft; edited.name = "Retain reviewed edit"
        XCTAssertTrue(co.saveLocal(edited)); co.prepare(edited); let review = try XCTUnwrap(co.confirmation)
        let saved = storage.data
        service.snapshot = .init(topicID: initial.topicID, scope: .sellingFrozen, draft: initial.draft)
        await co.confirm(review)
        XCTAssertEqual(co.state, .blocked); XCTAssertTrue(service.submissions.isEmpty); XCTAssertEqual(storage.data, saved)
        await co.load(); XCTAssertTrue(co.isReadOnly); XCTAssertEqual(co.state, .idle)
        await co.confirm(review); XCTAssertTrue(service.submissions.isEmpty); XCTAssertNil(co.pending)
        let identity = try XCTUnwrap(co.identity)
        guard case .ready(let retained) = store.load(session: session, identity: identity, baseline: initial.draft) else { return XCTFail("Reviewed local draft must remain") }
        XCTAssertEqual(retained.draft.name, edited.name)
    }
}

import XCTest
@testable import QuestifyCore

/// Memory-only regression cases. These never invoke the production transport.
@MainActor final class TemplateAuthoringPublishReceiptTests: XCTestCase {
    private final class Wire: TemplateAuthoringTransport {
        var authority: TemplateAuthoringAuthority = .injectedHTTP
        var raw = #"{"code":200,"data":402}"#, status = 200, calls = 0
        var beforeReply: (() -> Void)?
        func send(_ request: TemplateAuthoringRequest) async throws -> (Data, Int) { calls += 1; beforeReply?(); return (Data(raw.utf8), status) }
    }
    private final class Storage: TemplateAuthoringStorage {
        var values: [String:Data] = [:], writes = 0
        var failTerminalWrite = false, dropTerminalWrite = false
        func read(_ key: String) throws -> Data? { values[key] }
        func write(_ data: Data, key: String) throws {
            if let value = try? JSONDecoder().decode(TemplateAuthoringPending.self, from:data), value.publishedReceipt != nil {
                if failTerminalWrite { throw TemplateAuthoringError.storageUnavailable }
                if dropTerminalWrite { return }
            }
            values[key] = data; writes += 1
        }
        func remove(_ key: String) throws { values.removeValue(forKey:key) }
    }
    private final class Owner { var session: TemplateAuthoringSession? = try? .init(accountID:40,namespace:"publish-receipt",epoch:1,authorizationRevision:"creator") }
    private func request(_ intent: TemplateAuthoringIntent = .publish) throws -> TemplateAuthoringRequest {
        try TemplateAuthoringContract.request(TemplateAuthoringSyntheticFixtures.draft(),intent:intent)
    }
    private func submit(_ coordinator: TemplateAuthoringCoordinator, intent: TemplateAuthoringIntent = .publish) async throws {
        coordinator.open(); coordinator.change(TemplateAuthoringSyntheticFixtures.draft()); coordinator.prepare(intent)
        await coordinator.confirm(try XCTUnwrap(coordinator.review))
    }
    func testPrimaryNumericPositiveResponseOnlyAndDraftIsSeparate() throws {
        let raw = Data(#"{"code":200,"data":402}"#.utf8)
        XCTAssertEqual(try TemplateAuthoringPublishReceipt.responseID(raw,request:request()).rawValue,402)
        for value in ["0","-1","true","false","\"402\"","1.5","null","[]","{}","{\"id\":402}","9223372036854775808"] {
            XCTAssertThrowsError(try TemplateAuthoringPublishReceipt.responseID(Data(("{\"code\":200,\"data\":" + value + "}").utf8),request:request()))
        }
        for response in [#"{"code":200}"#,#"{"code":500,"data":402}"#,#"{"code":200,"data":402,"data":403}"#] {
            XCTAssertThrowsError(try TemplateAuthoringPublishReceipt.responseID(Data(response.utf8),request:request()))
        }
        XCTAssertThrowsError(try TemplateAuthoringPublishReceipt.responseID(raw,request:request(.saveDraft)))
        XCTAssertThrowsError(try TemplateAuthoringSavedDraft.responseID(raw,request:request()))
    }
    func testAdapterKeepsLegacyOutcomeButNeverFabricatesAReceipt() async throws {
        let wire = Wire(), adapter = TemplateAuthoringAdapter(transport:wire)
        let valid = await adapter.submitWithReceipt(try request()); XCTAssertEqual(valid.publishedMemberTemplateID?.rawValue,402); XCTAssertNil(valid.savedMemberTemplateID)
        let draft = await adapter.submitWithReceipt(try request(.saveDraft)); XCTAssertEqual(draft.savedMemberTemplateID?.rawValue,402); XCTAssertNil(draft.publishedMemberTemplateID)
        wire.raw = #"{"code":200}"#
        let missing = await adapter.submitWithReceipt(try request()); XCTAssertEqual(missing.outcome,.acknowledged); XCTAssertNil(missing.publishedMemberTemplateID)
        wire.raw = #"{"code":200,"data":402}"#; wire.authority = .synthetic
        let simulation = await adapter.submitWithReceipt(try request()); XCTAssertNil(simulation.publishedMemberTemplateID); XCTAssertNil(simulation.savedMemberTemplateID)
        wire.authority = .injectedHTTP; wire.status = 503
        let unknown = await adapter.submitWithReceipt(try request()); XCTAssertEqual(unknown.outcome,.uncertain); XCTAssertNil(unknown.publishedMemberTemplateID)
        let disabled = await TemplateAuthoringAdapter().submitWithReceipt(try request()); XCTAssertEqual(disabled.outcome,.notSent); XCTAssertNil(disabled.publishedMemberTemplateID)
    }
    func testReceiptIsDurableInOneTerminalRecordAndReopenDoesNotResubmit() async throws {
        let owner = Owner(), wire = Wire(), storage = Storage(), store = TemplateAuthoringLocalStore(storage:storage)
        let c = TemplateAuthoringCoordinator(adapter:.init(transport:wire),store:store,currentSession:{ owner.session })
        try await submit(c); let receipt = try XCTUnwrap(c.publishedReceipt), pending = try XCTUnwrap(c.pending)
        XCTAssertNil(c.savedDraft); XCTAssertTrue(receipt.matches(pending,session:try XCTUnwrap(owner.session)))
        XCTAssertEqual(try store.pending(session:try XCTUnwrap(owner.session),identity:c.identity)?.publishedReceipt,receipt)
        XCTAssertEqual(storage.writes,4) // draft, active identity, pending intent, terminal+receipt
        let result = try XCTUnwrap(TemplateAuthoringPublishResult(coordinator:c)); XCTAssertEqual(result.title,TemplateAuthoringSyntheticFixtures.draft().title)
        let reopened = TemplateAuthoringCoordinator(adapter:.init(transport:wire),store:store,currentSession:{ owner.session }); reopened.open()
        XCTAssertEqual(reopened.publishedReceipt,receipt); XCTAssertEqual(wire.calls,1)
        owner.session = try .init(accountID:41,namespace:"publish-receipt",epoch:2,authorizationRevision:"creator")
        XCTAssertNil(c.publishedReceipt); XCTAssertFalse(result.isCurrent(in:c))
    }
    func testOptionalJournalFieldIsBackwardCompatibleAndNotInsertedWhenMissing() async throws {
        let owner = Owner(), c = TemplateAuthoringCoordinator(adapter:.init(transport:Wire()),store:.init(storage:Storage()),currentSession:{ owner.session })
        try await submit(c); var raw = try JSONDecoder().decode([String:ProjectEditJSON].self,from:JSONEncoder().encode(try XCTUnwrap(c.pending)))
        raw["publishedReceipt"] = nil
        let old = try JSONDecoder().decode(TemplateAuthoringPending.self,from:JSONEncoder().encode(raw))
        XCTAssertNil(old.publishedReceipt); XCTAssertTrue(old.terminal)
        let encoded = try JSONDecoder().decode([String:ProjectEditJSON].self,from:JSONEncoder().encode(old)); XCTAssertNil(encoded["publishedReceipt"])
    }
    func testMismatchedReceiptAndDualReceiptAreRejectedBeforeStorageWrite() async throws {
        let owner = Owner(), storage = Storage(), store = TemplateAuthoringLocalStore(storage:storage)
        let c = TemplateAuthoringCoordinator(adapter:.init(transport:Wire()),store:store,currentSession:{ owner.session }); try await submit(c)
        let original = try XCTUnwrap(c.pending), session = try XCTUnwrap(owner.session), id = try XCTUnwrap(MemberPlayTemplateID(rawValue:402)), writes = storage.writes
        var changed = TemplateAuthoringSyntheticFixtures.draft(); changed.title = "Changed request"
        let changedRequest = try TemplateAuthoringContract.request(changed,intent:.publish)
        let invalid = [
            try TemplateAuthoringPublishReceipt(operationID:UUID(),ownerKey:original.ownerKey,identity:original.identity,memberTemplateID:id,request:original.request),
            try .init(operationID:original.operationID,ownerKey:"another-owner",identity:original.identity,memberTemplateID:id,request:original.request),
            try .init(operationID:original.operationID,ownerKey:original.ownerKey,identity:.init(),memberTemplateID:id,request:original.request),
            try .init(operationID:original.operationID,ownerKey:original.ownerKey,identity:original.identity,memberTemplateID:id,request:changedRequest)
        ]
        for receipt in invalid { var pending = original; pending.publishedReceipt = receipt; XCTAssertThrowsError(try store.savePending(pending,session:session)) }
        var dual = original
        dual.savedDraft = try .init(operationID:original.operationID,ownerKey:original.ownerKey,identity:original.identity,memberTemplateID:id,request:request(.saveDraft))
        XCTAssertThrowsError(try store.savePending(dual,session:session)); XCTAssertEqual(storage.writes,writes)
        var nonterminal = original; nonterminal.terminal = false
        XCTAssertThrowsError(try store.savePending(nonterminal,session:session))
    }
    func testTerminalWriteAndReadbackFailureCannotExposeSuccess() async throws {
        for drop in [false,true] {
            let owner = Owner(), storage = Storage(), wire = Wire()
            storage.failTerminalWrite = !drop; storage.dropTerminalWrite = drop
            let c = TemplateAuthoringCoordinator(adapter:.init(transport:wire),store:.init(storage:storage),currentSession:{ owner.session })
            try await submit(c); XCTAssertEqual(c.state,.uncertain); XCTAssertTrue(c.locked); XCTAssertNil(c.publishedReceipt)
            XCTAssertNil(TemplateAuthoringPublishResult(coordinator:c)); XCTAssertEqual(wire.calls,1)
        }
    }
    func testReplyAfterOwnerChangeCannotExposePreviousOwnerReceipt() async throws {
        let owner = Owner(), wire = Wire()
        wire.beforeReply = { owner.session = try? .init(accountID:41,namespace:"publish-receipt",epoch:2,authorizationRevision:"creator") }
        let c = TemplateAuthoringCoordinator(adapter:.init(transport:wire),store:.init(storage:Storage()),currentSession:{ owner.session })
        try await submit(c); XCTAssertNil(c.publishedReceipt); XCTAssertNil(TemplateAuthoringPublishResult(coordinator:c)); XCTAssertEqual(wire.calls,1)
    }
}

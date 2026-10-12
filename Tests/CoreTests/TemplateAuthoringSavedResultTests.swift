import XCTest
@testable import QuestifyCore

@MainActor final class TemplateAuthoringSavedResultTests: XCTestCase {
    private final class Owner { var session: TemplateAuthoringSession? = try? .init(accountID: 36, namespace: "saved-result", epoch: 1, authorizationRevision: "creator") }
    private final class Wire: TemplateAuthoringTransport {
        var authority: TemplateAuthoringAuthority = .injectedHTTP
        var raw = #"{"code":200,"data":{"id":360}}"#, calls = 0
        var beforeReply: (() -> Void)?
        func send(_ request: TemplateAuthoringRequest) async throws -> (Data, Int) { calls += 1; beforeReply?(); return (Data(raw.utf8),200) }
    }
    private func setup() -> (TemplateAuthoringCoordinator, Owner, Wire, TemplateAuthoringMemoryStorage) {
        let owner = Owner(), wire = Wire(), memory = TemplateAuthoringMemoryStorage()
        let c = TemplateAuthoringCoordinator(adapter: .init(transport: wire), store: .init(storage: memory), currentSession: { owner.session })
        c.open(); c.change(TemplateAuthoringSyntheticFixtures.draft()); return (c,owner,wire,memory)
    }
    private func save(_ c: TemplateAuthoringCoordinator, intent: TemplateAuthoringIntent = .saveDraft) async throws {
        c.prepare(intent); await c.confirm(try XCTUnwrap(c.review))
    }
    func testExactAcknowledgedDraftProvidesPositiveIDTitleAndSourceDuration() async throws {
        let (c,_,wire,_) = setup(); try await save(c); let result = try XCTUnwrap(TemplateAuthoringSavedResult(coordinator:c))
        XCTAssertEqual(result.memberTemplateID.rawValue,360); XCTAssertEqual(result.id,c.pending?.operationID)
        XCTAssertEqual(result.title,c.draft.title.trimmingCharacters(in:.whitespacesAndNewlines)); XCTAssertTrue(result.isCurrent(in:c))
        XCTAssertEqual(TemplateAuthoringSavedResult.displayMilliseconds,2000); XCTAssertEqual(wire.calls,1)
    }
    func testMissingZeroNegativeBooleanAndStringIDsNeverProduceResult() async throws {
        for raw in [#"{"code":200}"#,#"{"code":200,"data":0}"#,#"{"code":200,"data":-1}"#,#"{"code":200,"data":true}"#,#"{"code":200,"data":"360"}"#] {
            let (c,_,wire,_) = setup(); wire.raw = raw; try await save(c)
            XCTAssertNil(TemplateAuthoringSavedResult(coordinator:c)); XCTAssertEqual(wire.calls,1)
        }
    }
    func testSimulationAndUnknownResponseNeverProduceSuccess() async throws {
        for synthetic in [true,false] {
            let (c,_,wire,_) = setup(); if synthetic { wire.authority = .synthetic } else { wire.raw = "unknown" }; try await save(c)
            XCTAssertNil(TemplateAuthoringSavedResult(coordinator:c)); XCTAssertEqual(wire.calls,1)
        }
    }
    func testPublishAcknowledgementDoesNotInventUnsupportedTypedReceipt() async throws {
        let (c,_,wire,_) = setup(); try await save(c,intent:.publish)
        XCTAssertEqual(c.state,.acknowledged); XCTAssertNil(c.savedDraft); XCTAssertNil(TemplateAuthoringSavedResult(coordinator:c)); XCTAssertEqual(wire.calls,1)
    }
    func testFailedDurableReceiptRemainsUncertainWithoutResult() async throws {
        let (c,_,wire,memory) = setup(); wire.beforeReply = { memory.failWrites = true }; try await save(c)
        XCTAssertEqual(c.state,.uncertain); XCTAssertNil(TemplateAuthoringSavedResult(coordinator:c)); XCTAssertEqual(wire.calls,1)
    }
    func testMissingAndLegacyPendingReceiptAreRejected() async throws {
        let (c,owner,_,_) = setup(); try await save(c); let receipt = try XCTUnwrap(c.savedDraft); var pending = try XCTUnwrap(c.pending)
        XCTAssertNil(TemplateAuthoringSavedResult(receipt:receipt,pending:nil,session:owner.session,identity:c.identity))
        pending.savedDraft = nil; XCTAssertNil(TemplateAuthoringSavedResult(receipt:receipt,pending:pending,session:owner.session,identity:c.identity))
    }
    func testNonterminalAndUnacknowledgedPendingCannotClaimSuccess() async throws {
        let (c,owner,_,_) = setup(); try await save(c); let receipt = try XCTUnwrap(c.savedDraft); var pending = try XCTUnwrap(c.pending)
        pending.terminal = false; XCTAssertNil(TemplateAuthoringSavedResult(receipt:receipt,pending:pending,session:owner.session,identity:c.identity))
        pending.terminal = true; pending.acknowledged = false; XCTAssertNil(TemplateAuthoringSavedResult(receipt:receipt,pending:pending,session:owner.session,identity:c.identity))
    }
    func testIdentityOwnerAndOperationMismatchCannotCreateResult() async throws {
        let (c,owner,_,_) = setup(); try await save(c); let receipt = try XCTUnwrap(c.savedDraft), pending = try XCTUnwrap(c.pending)
        XCTAssertNil(TemplateAuthoringSavedResult(receipt:receipt,pending:pending,session:owner.session,identity:.init()))
        let other = try TemplateAuthoringSession(accountID:37,namespace:"saved-result",epoch:1,authorizationRevision:"creator")
        XCTAssertNil(TemplateAuthoringSavedResult(receipt:receipt,pending:pending,session:other,identity:c.identity))
        var mismatched = TemplateAuthoringPending(operationID:UUID(),ownerKey:pending.ownerKey,identity:pending.identity,request:pending.request,createdAt:pending.createdAt)
        mismatched.terminal = true; mismatched.acknowledged = true; mismatched.savedDraft = receipt
        XCTAssertNil(TemplateAuthoringSavedResult(receipt:receipt,pending:mismatched,session:owner.session,identity:c.identity))
    }
    func testChangedRequestHashCannotReuseReceipt() async throws {
        let (c,owner,_,_) = setup(); try await save(c); let receipt = try XCTUnwrap(c.savedDraft), pending = try XCTUnwrap(c.pending)
        var draft = c.draft; draft.title = "Another title"; let request = try TemplateAuthoringContract.request(draft,intent:.saveDraft)
        var changed = TemplateAuthoringPending(operationID:pending.operationID,ownerKey:pending.ownerKey,identity:pending.identity,request:request,createdAt:pending.createdAt)
        changed.terminal = true; changed.acknowledged = true; changed.savedDraft = receipt
        XCTAssertNil(TemplateAuthoringSavedResult(receipt:receipt,pending:changed,session:owner.session,identity:c.identity))
    }
    func testSessionEpochAndAuthorizationChangeInvalidateCapturedResult() async throws {
        for changeEpoch in [true,false] {
            let (c,owner,_,_) = setup(); try await save(c); let result = try XCTUnwrap(TemplateAuthoringSavedResult(coordinator:c))
            owner.session = try .init(accountID:36,namespace:"saved-result",epoch:changeEpoch ? 2 : 1,authorizationRevision:changeEpoch ? "creator" : "revoked")
            XCTAssertFalse(result.isCurrent(in:c))
        }
    }
    func testUnicodeSessionCheckUsesExactBytes() throws {
        let a = try TemplateAuthoringSession(accountID:36,namespace:"caf\u{e9}",epoch:1,authorizationRevision:"creator")
        let b = try TemplateAuthoringSession(accountID:36,namespace:"cafe\u{301}",epoch:1,authorizationRevision:"creator")
        XCTAssertFalse(TemplateAuthoringSavedResult.exactSession(a,b)); XCTAssertTrue(TemplateAuthoringSavedResult.exactSession(a,a))
    }
    func testNewIdentityRevokesOldResultAndRetainsPriorReceipt() async throws {
        let (c,owner,wire,memory) = setup(); try await save(c); let result = try XCTUnwrap(TemplateAuthoringSavedResult(coordinator:c)), identity = c.identity
        XCTAssertTrue(c.beginNewDraft(after:result.receipt)); XCTAssertFalse(result.isCurrent(in:c))
        let store = TemplateAuthoringLocalStore(storage:memory)
        XCTAssertEqual(try store.pending(session:try XCTUnwrap(owner.session),identity:identity)?.savedDraft,result.receipt); XCTAssertEqual(wire.calls,1)
    }
}

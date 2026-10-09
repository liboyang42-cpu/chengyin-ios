import XCTest
@testable import QuestifyCore

@MainActor final class TemplateAuthoringSavedDraftTests: XCTestCase {
    @MainActor private final class Wire: TemplateAuthoringTransport {
        var authority: TemplateAuthoringAuthority = .injectedHTTP
        var raw = #"{"code":200,"data":42}"#, status = 200, calls = 0
        var beforeReply: (() -> Void)?
        func send(_ request: TemplateAuthoringRequest) async throws -> (Data, Int) { calls += 1; beforeReply?(); return (Data(raw.utf8), status) }
    }
    private final class Owner { var session: TemplateAuthoringSession? = try? .init(accountID: 7, namespace: "saved-draft", epoch: 1, authorizationRevision: "creator") }
    private func request(_ intent: TemplateAuthoringIntent = .saveDraft) throws -> TemplateAuthoringRequest {
        try TemplateAuthoringContract.request(TemplateAuthoringSyntheticFixtures.draft(), intent: intent)
    }
    private func save(_ coordinator: TemplateAuthoringCoordinator) async throws {
        coordinator.open(); coordinator.change(TemplateAuthoringSyntheticFixtures.draft()); coordinator.prepare(.saveDraft)
        await coordinator.confirm(try XCTUnwrap(coordinator.review))
    }
    func testReceiptOnlyAcceptsPositiveNumericMemberIDForActualDraftRequest() throws {
        for response in [#"{"code":200,"data":42}"#, #"{"code":200,"data":{"id":42}}"#] {
            XCTAssertEqual(try TemplateAuthoringSavedDraft.responseID(Data(response.utf8), request: request()).rawValue, 42)
        }
        for value in ["0", "-1", "true", "\"42\"", "1.5", "null", "[]"] {
            XCTAssertThrowsError(try TemplateAuthoringSavedDraft.responseID(Data(("{\"code\":200,\"data\":" + value + "}").utf8), request: request()))
        }
        XCTAssertThrowsError(try TemplateAuthoringSavedDraft.responseID(Data(#"{"code":200,"data":42,"data":43}"#.utf8), request: request()))
        XCTAssertThrowsError(try TemplateAuthoringSavedDraft.responseID(Data(#"{"code":200,"data":42}"#.utf8), request: request(.publish)))
    }
    func testLegacyOutcomeIsUnchangedButMissingSimulatedAndUnknownCannotReturnID() async throws {
        let wire = Wire(), adapter = TemplateAuthoringAdapter(transport: wire)
        wire.raw = #"{"code":200}"#; let legacyOutcome = await adapter.submit(try request()); XCTAssertEqual(legacyOutcome, .acknowledged)
        var result = await adapter.submitWithReceipt(try request()); XCTAssertEqual(result.outcome, .acknowledged); XCTAssertNil(result.savedMemberTemplateID)
        wire.raw = #"{"code":200,"data":42}"#; wire.authority = .synthetic
        result = await adapter.submitWithReceipt(try request()); XCTAssertEqual(result.outcome, .simulated); XCTAssertNil(result.savedMemberTemplateID)
        wire.authority = .injectedHTTP; wire.status = 503
        result = await adapter.submitWithReceipt(try request()); XCTAssertEqual(result.outcome, .uncertain); XCTAssertNil(result.savedMemberTemplateID)
    }
    func testTerminalAndReceiptPersistTogetherAndReopenDoesNotResubmit() async throws {
        let owner = Owner(), wire = Wire(), memory = TemplateAuthoringMemoryStorage(), store = TemplateAuthoringLocalStore(storage: memory)
        let coordinator = TemplateAuthoringCoordinator(adapter: .init(transport: wire), store: store, currentSession: { owner.session })
        try await save(coordinator); let receipt = try XCTUnwrap(coordinator.savedDraft), pending = try XCTUnwrap(coordinator.pending)
        XCTAssertTrue(receipt.matches(pending, session: try XCTUnwrap(owner.session)))
        let durable = try XCTUnwrap(store.pending(session: try XCTUnwrap(owner.session), identity: coordinator.identity))
        XCTAssertEqual(durable.savedDraft, receipt); XCTAssertTrue(durable.terminal); XCTAssertEqual(durable.acknowledged, true)
        let reopened = TemplateAuthoringCoordinator(adapter: .init(transport: wire), store: store, currentSession: { owner.session }); reopened.open()
        XCTAssertEqual(reopened.savedDraft, receipt); XCTAssertEqual(wire.calls, 1)
    }
    func testLegacyPendingWithoutReceiptDecodesAndMismatchedReceiptIsRejected() async throws {
        let owner = Owner(), wire = Wire(), store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage())
        let coordinator = TemplateAuthoringCoordinator(adapter: .init(transport: wire), store: store, currentSession: { owner.session })
        try await save(coordinator); var pending = try XCTUnwrap(coordinator.pending), raw = try JSONDecoder().decode([String: ProjectEditJSON].self, from: JSONEncoder().encode(pending))
        raw["savedDraft"] = nil
        let legacy = try JSONDecoder().decode(TemplateAuthoringPending.self, from: JSONEncoder().encode(raw))
        XCTAssertNil(legacy.savedDraft); XCTAssertTrue(legacy.terminal)
        let encoded = try JSONDecoder().decode([String: ProjectEditJSON].self, from: JSONEncoder().encode(legacy)); XCTAssertNil(encoded["savedDraft"])
        pending.savedDraft = try .init(operationID: UUID(), ownerKey: pending.ownerKey, identity: pending.identity,
            memberTemplateID: MemberPlayTemplateID(rawValue: 42)!, request: pending.request)
        XCTAssertThrowsError(try store.savePending(pending, session: try XCTUnwrap(owner.session)))
    }
    func testReceiptWriteFailureStaysUnknownAndNeverReturnsOrResetsIdentity() async throws {
        let owner = Owner(), wire = Wire(), memory = TemplateAuthoringMemoryStorage()
        let coordinator = TemplateAuthoringCoordinator(adapter: .init(transport: wire), store: .init(storage: memory), currentSession: { owner.session })
        wire.beforeReply = { memory.failWrites = true }; try await save(coordinator)
        XCTAssertEqual(coordinator.state, .uncertain); XCTAssertNil(coordinator.savedDraft); XCTAssertTrue(coordinator.locked); XCTAssertEqual(wire.calls, 1)
        let pending = try XCTUnwrap(coordinator.pending), originalIdentity = coordinator.identity
        let unsupportedClaim = try TemplateAuthoringSavedDraft(operationID: pending.operationID, ownerKey: pending.ownerKey,
            identity: pending.identity, memberTemplateID: MemberPlayTemplateID(rawValue: 42)!, request: pending.request)
        XCTAssertFalse(coordinator.beginNewDraft(after: unsupportedClaim)); XCTAssertEqual(coordinator.identity, originalIdentity)
    }
    func testExplicitNewDraftKeepsOldReceiptAndIdentityChangeRevokesOldHandoff() async throws {
        let owner = Owner(), wire = Wire(), store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage())
        let coordinator = TemplateAuthoringCoordinator(adapter: .init(transport: wire), store: store, currentSession: { owner.session })
        try await save(coordinator); let saved = try XCTUnwrap(coordinator.savedDraft), oldIdentity = coordinator.identity
        XCTAssertTrue(coordinator.beginNewDraft(after: saved)); XCTAssertNotEqual(coordinator.identity, oldIdentity); XCTAssertEqual(wire.calls, 1)
        XCTAssertEqual(try store.pending(session: try XCTUnwrap(owner.session), identity: oldIdentity)?.savedDraft, saved)
        XCTAssertNil(coordinator.savedDraft); XCTAssertFalse(coordinator.beginNewDraft(after: saved))
        owner.session = try .init(accountID: 8, namespace: "saved-draft", epoch: 2, authorizationRevision: "creator")
        XCTAssertFalse(coordinator.beginNewDraft(after: saved))
    }
}

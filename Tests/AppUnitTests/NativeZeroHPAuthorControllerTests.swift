import XCTest
@testable import Questify

@MainActor final class NativeZeroHPAuthorControllerTests: XCTestCase {
    private final class Owner {
        var session: ProjectEditSession?
        init() throws { session = try .init(accountID: 901, epoch: 1, storageNamespace: "zero-hp-test") }
    }
    private final class Reader {
        var calls = 0, fail = false, current = true
        var value: NativeRuntimeStructureAuthorInputs
        init() throws { value = try Self.inputs() }
        static func inputs(revision: Int = 1) throws -> NativeRuntimeStructureAuthorInputs {
            let policies = ["BLOCK_HP_COST", "THEME_FAIL", "WAIT", "CHALLENGE"].map(ProjectEditJSON.string)
            return try .init(matrix: ["schemaVersion": .number(1), "types": .array([]), "addons": .array([]),
                                      "constraints": .object([:]), "legacyProofs": .object([:]),
                                      "testRevision": .number(Decimal(revision)),
                                      "zeroHpPolicies": .object(["legacy": .array(policies), "generic": .array(policies)])], templates: [:])
        }
        func read(_ draft: ProjectEditDraft) async throws -> NativeRuntimeStructureAuthorInputs {
            calls += 1
            if fail { throw ProjectEditError.notConfigured }
            return value
        }
    }
    private struct Context {
        let owner: Owner, model: ProjectEditModel, editor: NativeZeroHPAuthorController
        let storage: ProjectEditMemoryStorage, store: ProjectEditLocalStore, service: ProjectEditSyntheticService, reader: Reader
    }
    private func setup(policy: String? = nil, scope: ProjectEditScope = .full,
                       merchant: Bool = false) async throws -> Context {
        let owner = try Owner(), reader = try Reader(), storage = ProjectEditMemoryStorage()
        var draft = ProjectEditDraft(); if merchant { draft.owner = .merchant }
        draft.preserved["journeyRules"] = .string("{\"schemaVersion\":1,\"stateEnabled\":true,\"hp\":{\"enabled\":true,\"init\":10,\"max\":10}}")
        if let policy { draft.preserved["themeRuntimeConfig"] = .string("{\"schemaVersion\":1,\"gameplayRuntime\":{\"survival\":{\"zeroHpPolicy\":\"" + policy + "\"}}}") }
        let snapshot = ProjectEditSnapshot(scope: scope, draft: draft)
        let service = ProjectEditSyntheticService(snapshot: snapshot), store = ProjectEditLocalStore(storage: storage)
        let coordinator = ProjectEditCoordinator(initial: snapshot, service: service, store: store, currentSession: { owner.session })
        let model = ProjectEditModel(coordinator: coordinator); await model.load()
        let editor = NativeZeroHPAuthorController(model: model, readInputs: { try await reader.read($0) }, inputsAreCurrent: { reader.current && $0 == reader.value })
        editor.setSceneActive(true); editor.open()
        let context = Context(owner: owner, model: model, editor: editor, storage: storage, store: store, service: service, reader: reader)
        await settle(editor); return context
    }
    private func settle(_ editor: NativeZeroHPAuthorController) async {
        for _ in 0..<100 where editor.busy { await Task.yield() }
        XCTAssertFalse(editor.busy, "The in-memory reader should settle without network or timing sleeps")
    }
    private func chooseWait(_ editor: NativeZeroHPAuthorController) {
        editor.mutate(editor.editToken) { try $0.select(.wait, inputs: $1) }
        XCTAssertEqual(editor.staged?.selected, .wait)
    }
    func testCancelDoesNotWriteOrSubmitAndReopenReadsOriginal() async throws {
        let c = try await setup(), original = ProjectEditPendingMaterials.exactData(c.model.draft)
        chooseWait(c.editor); c.editor.retire()
        XCTAssertNil(c.editor.staged); XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.model.draft), original)
        c.editor.open(); await settle(c.editor)
        XCTAssertEqual(c.editor.staged?.selected, .block); XCTAssertTrue(c.service.submissions.isEmpty)
    }
    func testSuccessfulCompletionPersistsOnlyOriginalLocalDraftAndReopensValue() async throws {
        let c = try await setup(); chooseWait(c.editor)
        let finished = await c.editor.finish(c.editor.editToken); XCTAssertTrue(finished)
        XCTAssertNil(c.editor.staged); XCTAssertTrue(c.service.submissions.isEmpty)
        let identity = try XCTUnwrap(c.model.coordinator.identity), session = try XCTUnwrap(c.owner.session)
        guard case .ready(let envelope) = c.store.load(session: session, identity: identity, baseline: c.model.draft) else { return XCTFail("Local writer must have confirmed a readable envelope") }
        XCTAssertEqual(try NativeZeroHPAuthorDraft(draft: envelope.draft).selected, .wait)
        c.editor.open(); await settle(c.editor); XCTAssertEqual(c.editor.staged?.selected, .wait)
    }
    func testFailedLocalWriteRetainsSameCopyAndExplicitRetrySucceeds() async throws {
        let c = try await setup(); chooseWait(c.editor)
        let original = ProjectEditPendingMaterials.exactData(c.model.draft), token = c.editor.editToken
        c.storage.failWrites = true
        let first = await c.editor.finish(token); XCTAssertFalse(first)
        XCTAssertEqual(c.editor.staged?.selected, .wait); XCTAssertEqual(c.editor.editToken, token)
        XCTAssertTrue(c.editor.canFinish); XCTAssertNotNil(c.editor.message)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.model.draft), original)
        c.storage.failWrites = false
        let retried = await c.editor.finish(token); XCTAssertTrue(retried)
        XCTAssertEqual(try NativeZeroHPAuthorDraft(draft: c.model.draft).selected, .wait)
        XCTAssertTrue(c.service.submissions.isEmpty)
    }
    func testReadFailureKeepsStagedValuesAndRequiresExplicitReload() async throws {
        let c = try await setup(); chooseWait(c.editor); c.reader.fail = true
        c.editor.reload(); await settle(c.editor)
        XCTAssertNil(c.editor.inputs); XCTAssertEqual(c.editor.staged?.selected, .wait)
        XCTAssertFalse(c.editor.canFinish); XCTAssertNotNil(c.editor.message)
        c.reader.fail = false; c.editor.reload(); await settle(c.editor)
        XCTAssertEqual(c.editor.staged?.selected, .wait); XCTAssertTrue(c.editor.canFinish)
    }
    func testConfirmationReadFailureDoesNotClaimSavedAndCopyCanRecover() async throws {
        let c = try await setup(); chooseWait(c.editor); c.reader.fail = true
        let finished = await c.editor.finish(c.editor.editToken); XCTAssertFalse(finished)
        XCTAssertEqual(c.editor.staged?.selected, .wait); XCTAssertNil(c.editor.inputs)
        XCTAssertTrue(c.service.submissions.isEmpty)
        c.reader.fail = false; c.editor.reload(); await settle(c.editor)
        let retried = await c.editor.finish(c.editor.editToken); XCTAssertTrue(retried)
    }
    func testChangedSupportVersionRequiresAnotherExplicitConfirmation() async throws {
        let c = try await setup(); chooseWait(c.editor)
        // The re-read returns another version while the previously loaded snapshot
        // remains current until this read. Use an independent current predicate here.
        let reader = c.reader
        let editor = NativeZeroHPAuthorController(model: c.model, readInputs: { try await reader.read($0) }, inputsAreCurrent: { _ in true })
        editor.setSceneActive(true); editor.open(); await settle(editor); chooseWait(editor)
        let before = editor.editToken; reader.value = try Reader.inputs(revision: 2)
        let first = await editor.finish(before); XCTAssertFalse(first)
        XCTAssertNotEqual(editor.editToken, before); XCTAssertEqual(editor.staged?.selected, .wait)
        let second = await editor.finish(editor.editToken); XCTAssertTrue(second)
        XCTAssertTrue(c.service.submissions.isEmpty)
    }
    func testRetainedTokenCannotChangeReplacementCopy() async throws {
        let c = try await setup(), old = c.editor.editToken
        chooseWait(c.editor)
        c.editor.mutate(old) { value, _ in value.message("late event") }
        XCTAssertEqual(c.editor.staged?.zeroMessage, "")
        c.editor.retire(); c.editor.open(); await settle(c.editor)
        c.editor.mutate(old) { try $0.select(.fail, inputs: $1) }
        XCTAssertEqual(c.editor.staged?.selected, .block)
    }
    func testAccountForegroundAndSameBytesDraftReplacementRetireOldCopy() async throws {
        for event in ["account", "foreground", "sameBytes", "ownerABA", "revision"] {
            let c = try await setup(); chooseWait(c.editor); let token = c.editor.editToken
            switch event {
            case "account": c.owner.session = try .init(accountID: 902, epoch: 2, storageNamespace: "zero-hp-test")
            case "foreground": c.editor.setSceneActive(false)
            case "sameBytes": let identical = c.model.draft; c.model.draft = identical
            case "ownerABA": c.model.draft.owner = .merchant; c.model.draft.owner = .personal
            default: c.model.draft.baseRevision = "new revision"
            }
            c.editor.retireIfInvalid(); let before = ProjectEditPendingMaterials.exactData(c.model.draft)
            let finished = await c.editor.finish(token); XCTAssertFalse(finished, event)
            XCTAssertNil(c.editor.staged, event); XCTAssertFalse(c.editor.canFinish, event)
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.model.draft), before, event)
            XCTAssertTrue(c.service.submissions.isEmpty, event)
        }
    }
    func testRevokedInputReceiptCannotCompleteOrMutate() async throws {
        let c = try await setup(); chooseWait(c.editor); c.reader.current = false
        c.editor.mutate(c.editor.editToken) { value, _ in value.message("must not write") }
        let finished = await c.editor.finish(c.editor.editToken); XCTAssertFalse(finished)
        XCTAssertEqual(c.editor.staged?.zeroMessage, ""); XCTAssertTrue(c.service.submissions.isEmpty)
    }
    func testCompatibilityDoneClosesWithoutReadingOrWriting() async throws {
        for policy in ["BLOCK_PAID", "LEGACY_END", "STEPS", "FUTURE"] {
            let c = try await setup(policy: policy), original = ProjectEditPendingMaterials.exactData(c.model.draft)
            XCTAssertEqual(c.reader.calls, 0); XCTAssertTrue(c.editor.staged?.readOnly == true)
            let finished = await c.editor.finish(c.editor.editToken); XCTAssertTrue(finished)
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.model.draft), original)
            XCTAssertTrue(c.service.submissions.isEmpty)
        }
    }
    func testMerchantAndWhitelistCannotOpen() async throws {
        for c in [try await setup(merchant: true), try await setup(scope: .whitelist)] {
            XCTAssertNil(c.editor.staged); XCTAssertFalse(c.editor.current); XCTAssertFalse(c.editor.canFinish)
            XCTAssertEqual(c.reader.calls, 0); XCTAssertTrue(c.service.submissions.isEmpty)
        }
    }
}

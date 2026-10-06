import XCTest
@testable import Questify

#if DEBUG
@MainActor final class ProjectStoryAudioPresentationTests: XCTestCase {
    private final class Owner { var session: ProjectEditSession? = try? .init(accountID: 7, epoch: 1, storageNamespace: "story-audio-host") }
    @MainActor private struct Context {
        let owner: Owner, storage: ProjectEditMemoryStorage, source: ProjectStoryAudioSynthetic
        let editor: ProjectEditModel, controller: ProjectStoryAudioPresentation
        var chapterID: String { editor.draft.chapters[0].id }
    }
    private func context(receiptFailure: Bool = false, unknown: Bool = false) async throws -> Context {
        let owner = Owner(), storage = ProjectEditMemoryStorage(), session = try XCTUnwrap(owner.session)
        var fail = receiptFailure
        let source = try ProjectStoryAudioSynthetic(session: session, unknownOnce: unknown, beforeReply: {
            if fail { fail = false; storage.failWrites = true }
        }, currentSession: { owner.session })
        var draft = ProjectEditSyntheticFixtures.draft(); let c = draft.chapters[0]
        draft.preserved["publishMode"] = .string("pro")
        draft.chapters[0].blocks = [.init(kind: .text, content: c.description), .init(kind: .node, nodeID: c.nodes[0].id)]
        let coordinator = ProjectEditCoordinator(initial: .init(draft: draft), service: ProjectEditSyntheticService(), store: .init(storage: storage),
            storyAudioSource: source, storyAudioJournal: .init(storage: storage), currentSession: { owner.session })
        let editor = ProjectEditModel(coordinator: coordinator); await editor.load(); editor.saveLocal()
        return .init(owner: owner, storage: storage, source: source, editor: editor, controller: .init(editor: editor))
    }
    private func insert(_ c: Context) throws -> String {
        let raw = try XCTUnwrap(ProjectEditPendingMaterials.exactData(c.editor.draft))
        return try XCTUnwrap(c.controller.insertEmpty(chapterID: c.chapterID, lease: c.editor.captureStarterLease(),
            topology: c.editor.storyTopologyRevision, draftHash: ProjectStoryImageTarget.hash(raw)))
    }
    private func open(_ c: Context, _ block: String) throws -> ProjectStoryAudioPresentation.Presentation {
        c.controller.open(try XCTUnwrap(c.controller.capture(chapterID: c.chapterID, blockID: block)))
        return try XCTUnwrap(c.controller.presentation)
    }
    private func model(_ c: Context, _ p: ProjectStoryAudioPresentation.Presentation, cancelFirst: Bool = false) -> ProjectStoryAudioAuthorModel {
        .init(original: p, picker: ProjectStoryAudioSynthetic.Picker(c.source.picked, cancelNext: cancelFirst), apply: { c.controller.apply($0) })
    }
    private func upload(_ model: ProjectStoryAudioAuthorModel) async throws {
        model.load(); await model.choose(); model.upload(try XCTUnwrap(model.flow.review))
        for _ in 0..<100 where model.flow.busy { await Task.yield() }
    }
    func testInsertSavesEmptyBlockBeforePickerAndCancellationKeepsIt() async throws {
        let c = try await context(), id = try insert(c), p = try open(c, id), m = model(c, p, cancelFirst: true)
        m.load(); await m.choose(); XCTAssertNil(p.flow.review); XCTAssertEqual(c.source.uploadCount, 0)
        XCTAssertEqual(c.editor.draft.chapters[0].blocks?.last?.id, id)
        XCTAssertEqual(c.editor.draft.chapters[0].blocks?.last?.url, "")
        let owner = try XCTUnwrap(c.owner.session), identity = try XCTUnwrap(c.editor.coordinator.identity)
        guard case .ready(let saved) = ProjectEditLocalStore(storage: c.storage).load(session: owner, identity: identity, baseline: c.editor.draft) else { return XCTFail() }
        XCTAssertEqual(saved.draft.chapters[0].blocks?.last?.id, id)
        XCTAssertFalse(try ProjectEditStoryContract.materializedBlocks(c.editor.draft.chapters[0], ordered: c.editor.draft.chapters[0].nodes).contains { $0.object?["type"]?.text == "audio" })
    }
    func testExactOriginalBlockApplyPersistsFilenameAndPreparedPayloadContainsOnlyReference() async throws {
        let c = try await context(), id = try insert(c), p = try open(c, id), m = model(c, p)
        try await upload(m); let receipt = try XCTUnwrap(p.flow.receipt); m.apply()
        XCTAssertNil(c.controller.presentation); XCTAssertEqual(c.source.uploadCount, 1)
        let block = try XCTUnwrap(c.editor.draft.chapters[0].blocks?.last)
        XCTAssertEqual(block.id, id); XCTAssertEqual(Array(block.url.utf8), Array(receipt.reference.utf8))
        XCTAssertEqual(Array(try XCTUnwrap(block.localAudio?.filename).utf8), Array(c.source.picked.filename.utf8))
        c.editor.review(); let prepared = try XCTUnwrap(c.editor.confirmation)
        let audio = try XCTUnwrap(prepared.payload["chapters"]?.array?.first?.object?["blocks"]?.array?.last?.object)
        XCTAssertEqual(audio["type"]?.text, "audio"); XCTAssertEqual(Array(try XCTUnwrap(audio["url"]?.text).utf8), Array(receipt.reference.utf8))
        XCTAssertNil(audio["localAudio"]); XCTAssertNil(audio["filename"]); XCTAssertNil(audio["duration"])
        let session = try XCTUnwrap(c.owner.session), identity = try XCTUnwrap(c.editor.coordinator.identity)
        guard case .ready(let saved) = ProjectEditLocalStore(storage: c.storage).load(session: session, identity: identity, baseline: prepared.draft) else { return XCTFail() }
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(saved.draft), ProjectEditPendingMaterials.exactData(prepared.draft))
        c.editor.draft.chapters[0].blocks?[2].url = "Changed after review"
        XCTAssertNil(c.editor.confirmation); XCTAssertEqual(audio["url"]?.text, receipt.reference)
    }
    func testReceiptFailureReopenSavesOriginalReceiptLocallyWithoutSecondUpload() async throws {
        let c = try await context(receiptFailure: true), id = try insert(c), old = try open(c, id), m = model(c, old)
        try await upload(m); XCTAssertTrue(old.flow.hasUnstoredReceipt); XCTAssertFalse(old.flow.canApply)
        m.close(); c.controller.close(old); c.storage.failWrites = false
        let next = try open(c, id), nextModel = model(c, next); nextModel.load()
        XCTAssertTrue(next.flow.hasUnstoredReceipt); XCTAssertEqual(next.flow.target, old.flow.target)
        nextModel.persistReceipt(); XCTAssertTrue(next.flow.canApply); nextModel.apply()
        XCTAssertEqual(c.source.uploadCount, 1); XCTAssertEqual(c.editor.draft.chapters[0].blocks?.last?.id, id)
    }
    func testLocalDraftFailureKeepsReferenceAndRetriesOnlyLocalApply() async throws {
        let c = try await context(), id = try insert(c), p = try open(c, id), m = model(c, p)
        try await upload(m); let before = ProjectEditPendingMaterials.exactData(c.editor.draft)
        c.storage.failWrites = true; m.apply()
        XCTAssertEqual(p.flow.state, .localSaveFailed); XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.editor.draft), before)
        c.storage.failWrites = false; m.apply(); XCTAssertNil(c.controller.presentation); XCTAssertEqual(c.source.uploadCount, 1)
    }
    func testRealReorderThenRestoreAndDeleteThenRestoreRetireOldPresentation() async throws {
        for delete in [false, true] {
            let c = try await context(), id = try insert(c), p = try open(c, id), m = model(c, p)
            try await upload(m); let captured = c.editor.draft
            if delete { c.editor.draft.chapters[0].blocks?.removeAll { $0.id == id } }
            else { c.editor.draft.chapters[0].blocks?.reverse() }
            c.editor.draft = captured
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.editor.draft), ProjectEditPendingMaterials.exactData(captured))
            XCTAssertFalse(p.flow.isCurrent); m.apply(); XCTAssertEqual(c.editor.draft.chapters[0].blocks?.last?.url, "")
            XCTAssertEqual(c.source.uploadCount, 1)
        }
    }
    func testRemovalUsesCapturedBlockAndOldDeleteCannotRemoveReplacement() async throws {
        let c = try await context(), id = try insert(c), captured = try XCTUnwrap(c.controller.captureBlock(chapterID: c.chapterID, blockID: id))
        let raw = c.editor.draft; c.controller.remove(captured)
        XCTAssertFalse(c.editor.draft.chapters[0].blocks?.contains { $0.id == id } == true)
        c.editor.draft = raw; let before = ProjectEditPendingMaterials.exactData(c.editor.draft)
        c.controller.remove(captured); XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.editor.draft), before)
        XCTAssertEqual(c.source.uploadCount, 0)
    }
    func testOldDismissAndQueuedUploadCannotAffectNewPresentation() async throws {
        let c = try await context(), id = try insert(c), old = try open(c, id), m = model(c, old), binding = c.controller.binding(old)
        m.load(); await m.choose(); m.upload(try XCTUnwrap(old.flow.review)); m.close(); c.controller.close(old)
        let next = try open(c, id); binding.wrappedValue = nil; c.controller.close(old)
        for _ in 0..<80 { await Task.yield() }
        XCTAssertEqual(c.controller.presentation?.id, next.id); XCTAssertEqual(c.source.uploadCount, 0); XCTAssertNil(binding.wrappedValue)
    }
    func testUnknownUploadReopenDoesNotResendAndRetainsOriginalEmptyBlock() async throws {
        let c = try await context(unknown: true), id = try insert(c), old = try open(c, id), m = model(c, old)
        try await upload(m); XCTAssertEqual(old.flow.state, .unknown); XCTAssertEqual(c.source.uploadCount, 1)
        m.close(); c.controller.close(old); let next = try open(c, id); next.flow.load()
        XCTAssertEqual(next.flow.unresolvedUploadCount, 1); XCTAssertNil(next.flow.receipt); XCTAssertFalse(next.flow.canApply)
        XCTAssertEqual(c.editor.draft.chapters[0].blocks?.last?.url, ""); XCTAssertEqual(c.source.uploadCount, 1)
    }
    func testAccountChangeAndExplicitDraftRestoreRetireOriginalApply() async throws {
        let c = try await context(), id = try insert(c), old = try open(c, id), m = model(c, old)
        try await upload(m); let session = try XCTUnwrap(c.owner.session), bytes = c.storage.data
        c.owner.session = try .init(accountID: 8, epoch: 2, storageNamespace: session.storageNamespace)
        m.apply(); m.persistReceipt(); XCTAssertEqual(c.storage.data, bytes); XCTAssertFalse(old.flow.isCurrent)
        c.owner.session = session; c.editor.restore(); XCTAssertFalse(old.flow.isCurrent)
        m.apply(); XCTAssertEqual(c.editor.draft.chapters[0].blocks?.last?.url, "")
    }
    func testHeldUploadAfterCrossChapterMoveOrDeletionCannotFillAnotherLocation() async throws {
        for move in [false, true] {
            let c = try await context(); var second = ProjectEditChapter(); second.name = "Second chapter"
            second.blocks = [.init(kind: .text, content: "Second story")]; c.editor.draft.chapters.append(second)
            let id = try insert(c), p = try open(c, id), m = model(c, p)
            c.source.wire.held = true; m.load(); await m.choose(); m.upload(try XCTUnwrap(p.flow.review))
            for _ in 0..<100 where c.source.wire.pending == nil { await Task.yield() }
            XCTAssertNotNil(c.source.wire.pending)
            let block = try XCTUnwrap(c.editor.draft.chapters[0].blocks?.last)
            c.editor.draft.chapters[0].blocks?.removeAll { $0.id == id }
            if move { c.editor.draft.chapters[1].blocks?.append(block) }
            let before = ProjectEditPendingMaterials.exactData(c.editor.draft)
            c.source.wire.release(); for _ in 0..<100 where p.flow.busy { await Task.yield() }
            m.apply(); XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.editor.draft), before)
            XCTAssertFalse(p.flow.isCurrent); XCTAssertEqual(c.source.uploadCount, 1)
        }
    }
    private final class PartialStorage: ProjectEditDataStorage {
        var data: [String: Data] = [:], failActivePointerOnce = false
        func read(_ key: String) throws -> Data? { data[key] }
        func remove(_ key: String) throws { data[key] = nil }
        func write(_ value: Data, key: String) throws {
            if failActivePointerOnce, let json = try? JSONDecoder().decode([String: ProjectEditJSON].self, from: value), json["draftUUID"] != nil {
                failActivePointerOnce = false; throw ProjectEditError.persistenceUnavailable
            }
            data[key] = value
        }
    }
    func testPartialEnvelopeSaveCanRecoverSameFilledBlockWithoutReupload() async throws {
        let owner = Owner(), session = try XCTUnwrap(owner.session), storage = PartialStorage()
        let source = try ProjectStoryAudioSynthetic(session: session, currentSession: { owner.session })
        var draft = ProjectEditSyntheticFixtures.draft(); let chapter = draft.chapters[0], audio = ProjectEditBlock(kind: .audio)
        draft.preserved["publishMode"] = .string("pro")
        draft.chapters[0].blocks = [.init(kind: .text, content: chapter.description), .init(kind: .node, nodeID: chapter.nodes[0].id), audio]
        let store = ProjectEditLocalStore(storage: storage)
        let editor = ProjectEditModel(coordinator: .init(initial: .init(draft: draft), service: ProjectEditSyntheticService(), store: store,
            storyAudioSource: source, storyAudioJournal: .init(storage: storage), currentSession: { owner.session }))
        await editor.load(); editor.saveLocal(); let controller = ProjectStoryAudioPresentation(editor: editor)
        controller.open(try XCTUnwrap(controller.capture(chapterID: chapter.id, blockID: audio.id))); let original = try XCTUnwrap(controller.presentation)
        let model = ProjectStoryAudioAuthorModel(original: original, picker: ProjectStoryAudioSynthetic.Picker(source.picked), apply: { controller.apply($0) })
        try await upload(model); storage.failActivePointerOnce = true; model.apply()
        XCTAssertEqual(original.flow.state, .localSaveFailed); XCTAssertEqual(editor.draft.chapters[0].blocks?.last?.url, "")
        guard case .ready(let partial) = store.load(session: session, identity: try XCTUnwrap(editor.coordinator.identity), baseline: draft) else { return XCTFail() }
        XCTAssertEqual(partial.draft.chapters[0].blocks?.last?.id, audio.id)
        XCTAssertEqual(partial.draft.chapters[0].blocks?.last?.url, source.reference)
        model.apply(); XCTAssertNil(controller.presentation); XCTAssertEqual(editor.draft.chapters[0].blocks?.count, 3)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(editor.draft), ProjectEditPendingMaterials.exactData(partial.draft)); XCTAssertEqual(source.uploadCount, 1)
    }

}
#endif

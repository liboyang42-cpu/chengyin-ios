import XCTest
@testable import Questify

#if DEBUG
@MainActor final class ProjectStoryImagePresentationTests: XCTestCase {
    private final class Owner { var session: ProjectEditSession? = try? .init(accountID: 7, epoch: 1, storageNamespace: "story-image-host") }
    @MainActor private struct Context {
        let owner: Owner, storage: ProjectEditMemoryStorage, source: ProjectStoryImageSynthetic
        let editor: ProjectEditModel, controller: ProjectStoryImagePresentation
        var chapterID: String { editor.draft.chapters[0].id }
    }
    private func context(receiptFailure: Bool = false) async throws -> Context {
        let owner = Owner(), storage = ProjectEditMemoryStorage(), session = try XCTUnwrap(owner.session)
        var fail = receiptFailure
        let source = try ProjectStoryImageSynthetic(session: session, beforeReply: { if fail { fail = false; storage.failWrites = true } }, currentSession: { owner.session })
        var draft = ProjectEditSyntheticFixtures.draft(); let c = draft.chapters[0]
        draft.preserved["publishMode"] = .string("pro")
        draft.chapters[0].blocks = [.init(kind: .text, content: c.description), .init(kind: .node, nodeID: c.nodes[0].id)]
        let coordinator = ProjectEditCoordinator(initial: .init(draft: draft), service: ProjectEditSyntheticService(), store: .init(storage: storage), storyImageSource: source, storyImageJournal: .init(storage: storage), currentSession: { owner.session })
        let editor = ProjectEditModel(coordinator: coordinator); await editor.load(); editor.saveLocal()
        return .init(owner: owner, storage: storage, source: source, editor: editor, controller: .init(editor: editor))
    }
    private func open(_ c: Context) throws -> ProjectStoryImagePresentation.Presentation {
        c.controller.open(try XCTUnwrap(c.controller.capture(chapterID: c.chapterID)))
        return try XCTUnwrap(c.controller.presentation)
    }
    private func model(_ c: Context, _ original: ProjectStoryImagePresentation.Presentation) -> ProjectStoryImageAuthorModel {
        .init(original: original, picker: ProjectStoryImageSynthetic.Picker(c.source.picked), apply: { c.controller.apply($0) })
    }
    private func select(_ model: ProjectStoryImageAuthorModel) async throws {
        model.load(); await model.choose(); let crop = try XCTUnwrap(model.crop.draft)
        XCTAssertNil(model.flow.review)
        model.confirmCrop(crop.id, try .init(sourceWidth: crop.source.width, sourceHeight: crop.source.height, horizontal: 0.5, vertical: 0.5, zoom: 1))
        XCTAssertNotNil(model.preview); XCTAssertNotNil(model.flow.review)
    }
    private func upload(_ model: ProjectStoryImageAuthorModel) async throws {
        try await select(model); model.upload(try XCTUnwrap(model.flow.review))
        for _ in 0..<100 where model.flow.receipt == nil { await Task.yield() }
        XCTAssertNotNil(model.flow.receipt)
    }
    func testOldPresentationCloseAndOpeningCannotActOnReplacement() async throws {
        let c = try await context(), opening = try XCTUnwrap(c.controller.capture(chapterID: c.chapterID))
        c.controller.open(opening); let old = try XCTUnwrap(c.controller.presentation), binding = c.controller.binding(old)
        c.controller.close(old); let current = try open(c)
        binding.wrappedValue = nil; c.controller.close(old); c.controller.apply(old); c.controller.open(opening)
        XCTAssertEqual(c.controller.presentation?.id, current.id); XCTAssertNil(binding.wrappedValue); XCTAssertEqual(c.source.uploadCount, 0)
    }
    func testActualPickerCropCancelLeavesNoEmptyImageAndNoUpload() async throws {
        let c = try await context(), original = try open(c), model = model(c, original), before = ProjectEditPendingMaterials.exactData(c.editor.draft)
        model.load(); await model.choose(); let crop = try XCTUnwrap(model.crop.draft)
        model.cancelCrop(crop.id); XCTAssertNil(model.flow.review); XCTAssertNil(model.crop.draft)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.editor.draft), before); XCTAssertEqual(c.source.uploadCount, 0)
        c.controller.close(original)
    }
    func testActualApplySavesRestoresAndPreparedPayloadUsesExactReturnedReference() async throws {
        let c = try await context(), original = try open(c), model = model(c, original)
        try await upload(model); XCTAssertEqual(c.editor.draft.chapters[0].blocks?.count, 2)
        model.apply(); XCTAssertNil(c.controller.presentation); XCTAssertEqual(c.source.uploadCount, 1)
        XCTAssertEqual(c.editor.draft.chapters[0].blocks?.count, 3)
        let receipt = try XCTUnwrap(original.flow.snapshot?.entries.last?.receipt)
        XCTAssertEqual(Array(try XCTUnwrap(c.editor.draft.chapters[0].blocks?.last?.url).utf8), Array(receipt.reference.utf8))
        c.editor.review(); let confirmation = try XCTUnwrap(c.editor.confirmation)
        let chapters = try XCTUnwrap(confirmation.payload["chapters"]?.array)
        let blocks = try XCTUnwrap(chapters[0].object?["blocks"]?.array)
        XCTAssertEqual(Array(try XCTUnwrap(blocks.last?.object?["url"]?.text).utf8), Array(receipt.reference.utf8))
        let store = ProjectEditLocalStore(storage: c.storage), session = try XCTUnwrap(c.owner.session), identity = try XCTUnwrap(c.editor.coordinator.identity)
        guard case .ready(let saved) = store.load(session: session, identity: identity, baseline: try XCTUnwrap(c.editor.coordinator.snapshot).draft) else { return XCTFail() }
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(saved.draft), ProjectEditPendingMaterials.exactData(confirmation.draft))
        c.editor.draft.chapters[0].blocks?.reverse(); XCTAssertNil(c.editor.confirmation)
        XCTAssertEqual(Array(try XCTUnwrap(blocks.last?.object?["url"]?.text).utf8), Array(receipt.reference.utf8))
    }
    func testDraftSaveFailureRetainsOriginalDraftAndRetriesOnlyLocalApply() async throws {
        let c = try await context(), original = try open(c), model = model(c, original), before = ProjectEditPendingMaterials.exactData(c.editor.draft)
        try await upload(model); c.storage.failWrites = true; model.apply()
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.editor.draft), before); XCTAssertEqual(original.flow.state, .localSaveFailed)
        XCTAssertEqual(c.controller.presentation?.id, original.id); XCTAssertEqual(c.source.uploadCount, 1)
        c.storage.failWrites = false; model.apply()
        XCTAssertNil(c.controller.presentation); XCTAssertEqual(c.editor.draft.chapters[0].blocks?.count, 3); XCTAssertEqual(c.source.uploadCount, 1)
    }
    func testReceiptPersistenceFailureReopensOriginalTargetAndCanSaveWithoutNetwork() async throws {
        let c = try await context(receiptFailure: true), old = try open(c), oldModel = model(c, old)
        try await upload(oldModel); XCTAssertTrue(old.flow.hasUnstoredReceipt); XCTAssertFalse(old.flow.canApply)
        oldModel.close(); c.controller.close(old); c.storage.failWrites = false
        let next = try open(c), nextModel = model(c, next); nextModel.load()
        XCTAssertTrue(next.flow.hasUnstoredReceipt); XCTAssertFalse(next.flow.canApply); XCTAssertEqual(next.flow.target, old.flow.target)
        nextModel.persistReceipt(); XCTAssertTrue(next.flow.canApply); nextModel.apply()
        XCTAssertEqual(c.source.uploadCount, 1); XCTAssertEqual(c.editor.draft.chapters[0].blocks?.count, 3)
    }
    func testQueuedUploadAfterCloseCannotSendOrConsumeNewPresentation() async throws {
        let c = try await context(), old = try open(c), oldModel = model(c, old)
        try await select(oldModel); oldModel.upload(try XCTUnwrap(old.flow.review)); oldModel.close(); c.controller.close(old)
        let current = try open(c); for _ in 0..<60 { await Task.yield() }
        XCTAssertEqual(c.source.uploadCount, 0); XCTAssertEqual(c.controller.presentation?.id, current.id)
        XCTAssertEqual(try old.opening.journal.read(session: old.opening.lease.session, identity: old.opening.lease.identity).entries.count, 1)
    }
    func testDraftReorderDiscardAndAccountChangeRejectOldApply() async throws {
        let c = try await context(), original = try open(c), model = model(c, original)
        try await upload(model); c.editor.draft.chapters[0].blocks?.reverse()
        XCTAssertFalse(original.flow.canApply); model.apply(); XCTAssertEqual(c.editor.draft.chapters[0].blocks?.count, 2)
        let before = c.storage.data; c.owner.session = try .init(accountID: 8, epoch: 2, storageNamespace: original.opening.lease.session.storageNamespace)
        model.apply(); model.persistReceipt(); XCTAssertEqual(c.storage.data, before); XCTAssertFalse(original.flow.isCurrent)
        c.owner.session = original.opening.lease.session; c.editor.discard(); XCTAssertFalse(original.flow.isCurrent)
    }
    func testRetainedCropCallbackCannotStageNewerSelection() async throws {
        let c = try await context(), original = try open(c), model = model(c, original)
        model.load(); await model.choose(); let old = try XCTUnwrap(model.crop.draft)
        model.cancelCrop(old.id); await model.choose(); let current = try XCTUnwrap(model.crop.draft)
        model.confirmCrop(old.id, try .init(sourceWidth: old.source.width, sourceHeight: old.source.height, horizontal: 0.5, vertical: 0.5, zoom: 1))
        XCTAssertEqual(model.crop.draft?.id, current.id); XCTAssertNil(original.flow.review); XCTAssertEqual(c.source.uploadCount, 0)
    }
    func testNewCropCannotApplyPreviousReceiptBehindPendingSelection() async throws {
        let c = try await context(), original = try open(c), model = model(c, original)
        try await upload(model); XCTAssertTrue(original.flow.canApply)
        await model.choose(); let crop = try XCTUnwrap(model.crop.draft)
        XCTAssertTrue(original.flow.busy); XCTAssertFalse(original.flow.canApply)
        model.apply(); XCTAssertEqual(c.editor.draft.chapters[0].blocks?.count, 2)
        model.cancelCrop(crop.id); XCTAssertTrue(original.flow.canApply); XCTAssertEqual(c.source.uploadCount, 1)
    }
    private final class PartialStorage: ProjectEditDataStorage {
        var data: [String: Data] = [:], failActivePointerOnce = false
        var failAppliedMarkerOnce = false
        func read(_ key: String) throws -> Data? { data[key] }
        func remove(_ key: String) throws { data[key] = nil }
        func write(_ value: Data, key: String) throws {
            if failAppliedMarkerOnce, let json = try? JSONDecoder().decode([String: ProjectEditJSON].self, from: value),
               json["entries"]?.array?.contains(where: { $0.object?["applied"] == .bool(true) }) == true {
                failAppliedMarkerOnce = false; throw ProjectEditError.persistenceUnavailable
            }
            if failActivePointerOnce, let json = try? JSONDecoder().decode([String: ProjectEditJSON].self, from: value), json["draftUUID"] != nil {
                failActivePointerOnce = false; throw ProjectEditError.persistenceUnavailable
            }
            data[key] = value
        }
    }
    func testPartialLocalEnvelopeSaveReportsFailureAndRetryKeepsOneBlockAndOneUpload() async throws {
        let owner = Owner(), session = try XCTUnwrap(owner.session), storage = PartialStorage()
        let source = try ProjectStoryImageSynthetic(session: session, currentSession: { owner.session })
        var draft = ProjectEditSyntheticFixtures.draft(); let chapter = draft.chapters[0]
        draft.preserved["publishMode"] = .string("pro")
        draft.chapters[0].blocks = [.init(kind: .text, content: chapter.description), .init(kind: .node, nodeID: chapter.nodes[0].id)]
        let store = ProjectEditLocalStore(storage: storage)
        let editor = ProjectEditModel(coordinator: .init(initial: .init(draft: draft), service: ProjectEditSyntheticService(), store: store, storyImageSource: source, storyImageJournal: .init(storage: storage), currentSession: { owner.session }))
        await editor.load(); editor.saveLocal(); let controller = ProjectStoryImagePresentation(editor: editor)
        controller.open(try XCTUnwrap(controller.capture(chapterID: chapter.id))); let original = try XCTUnwrap(controller.presentation)
        let model = ProjectStoryImageAuthorModel(original: original, picker: ProjectStoryImageSynthetic.Picker(source.picked), apply: { controller.apply($0) })
        try await upload(model); storage.failActivePointerOnce = true; model.apply()
        XCTAssertEqual(original.flow.state, .localSaveFailed); XCTAssertEqual(editor.draft.chapters[0].blocks?.count, 2)
        guard case .ready(let partial) = store.load(session: session, identity: try XCTUnwrap(editor.coordinator.identity), baseline: draft) else { return XCTFail() }
        XCTAssertEqual(partial.draft.chapters[0].blocks?.count, 3); XCTAssertEqual(source.uploadCount, 1)
        model.apply(); XCTAssertNil(controller.presentation); XCTAssertEqual(editor.draft.chapters[0].blocks?.count, 3)
        XCTAssertEqual(editor.draft.chapters[0].blocks?.last?.id, partial.draft.chapters[0].blocks?.last?.id)
        XCTAssertEqual(source.uploadCount, 1)
    }
    func testCapturedOpeningCannotReviveAfterStoryOrderABA() async throws {
        let c = try await context(), opening = try XCTUnwrap(c.controller.capture(chapterID: c.chapterID))
        let before = ProjectEditPendingMaterials.exactData(c.editor.draft)
        c.editor.draft.chapters[0].blocks?.reverse(); c.editor.draft.chapters[0].blocks?.reverse()
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.editor.draft), before)
        c.controller.open(opening); XCTAssertNil(c.controller.presentation)
        XCTAssertEqual(c.source.uploadCount, 0)
    }
    func testReceivedReferenceCannotApplyAfterDeleteAndRestoreSameBlockIDs() async throws {
        let c = try await context(), original = try open(c), model = model(c, original)
        try await upload(model); let blocks = c.editor.draft.chapters[0].blocks
        let before = ProjectEditPendingMaterials.exactData(c.editor.draft), stored = c.storage.data
        c.editor.draft.chapters[0].blocks = []; c.editor.draft.chapters[0].blocks = blocks
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.editor.draft), before)
        XCTAssertFalse(original.flow.isCurrent); XCTAssertFalse(original.flow.canApply)
        model.apply(); XCTAssertEqual(c.storage.data, stored); XCTAssertEqual(c.source.uploadCount, 1)
        XCTAssertNil(c.controller.binding(original).wrappedValue)
    }
    func testSuccessfulOwnAppendKeepsMarkerRetryButExternalOrderABARetiresIt() async throws {
        let owner = Owner(), session = try XCTUnwrap(owner.session), storage = PartialStorage()
        let source = try ProjectStoryImageSynthetic(session: session, currentSession: { owner.session })
        var draft = ProjectEditSyntheticFixtures.draft(); let chapter = draft.chapters[0]
        draft.preserved["publishMode"] = .string("pro")
        draft.chapters[0].blocks = [.init(kind: .text, content: chapter.description), .init(kind: .node, nodeID: chapter.nodes[0].id)]
        let editor = ProjectEditModel(coordinator: .init(initial: .init(draft: draft), service: ProjectEditSyntheticService(), store: .init(storage: storage), storyImageSource: source, storyImageJournal: .init(storage: storage), currentSession: { owner.session }))
        await editor.load(); editor.saveLocal(); let controller = ProjectStoryImagePresentation(editor: editor)
        controller.open(try XCTUnwrap(controller.capture(chapterID: chapter.id))); let original = try XCTUnwrap(controller.presentation)
        let model = ProjectStoryImageAuthorModel(original: original, picker: ProjectStoryImageSynthetic.Picker(source.picked), apply: { controller.apply($0) })
        try await upload(model); storage.failAppliedMarkerOnce = true; model.apply()
        XCTAssertEqual(original.flow.state, .localSaveFailed); XCTAssertEqual(editor.draft.chapters[0].blocks?.count, 3)
        XCTAssertTrue(original.flow.canApply); XCTAssertTrue(original.flow.alreadyApplied)
        editor.draft.chapters[0].blocks?.reverse(); editor.draft.chapters[0].blocks?.reverse()
        let before = storage.data; model.apply(); XCTAssertEqual(storage.data, before); XCTAssertFalse(original.flow.isCurrent)
        controller.close(original); controller.open(try XCTUnwrap(controller.capture(chapterID: chapter.id)))
        let reopened = try XCTUnwrap(controller.presentation); reopened.flow.load()
        XCTAssertTrue(reopened.flow.alreadyApplied); controller.apply(reopened)
        XCTAssertNil(controller.presentation); XCTAssertEqual(editor.draft.chapters[0].blocks?.count, 3); XCTAssertEqual(source.uploadCount, 1)
    }
}
#endif

import XCTest
import SwiftUI
@testable import Questify

#if DEBUG
@MainActor final class ProjectPendingStoryMediaTests: XCTestCase {
    private final class Owner { var session: ProjectEditSession? = try? .init(accountID: 7, epoch: 1, storageNamespace: "pending-story-media") }
    @MainActor private struct Context {
        let owner: Owner, storage: ProjectEditMemoryStorage, image: ProjectStoryImageSynthetic, audio: ProjectStoryAudioSynthetic
        let editor: ProjectEditModel, pending: ProjectEditPendingController
        let materialID: String
    }
    private func context(newChapter: Bool = false) async throws -> Context {
        let owner = Owner(), storage = ProjectEditMemoryStorage(), session = try XCTUnwrap(owner.session)
        let image = try ProjectStoryImageSynthetic(session: session, currentSession: { owner.session })
        let audio = try ProjectStoryAudioSynthetic(session: session, currentSession: { owner.session })
        var draft = ProjectEditSyntheticFixtures.draft(); let chapter = draft.chapters[0]
        draft.preserved["publishMode"] = .string("pro")
        draft.chapters[0].blocks = [.init(kind: .text, content: chapter.description), .init(kind: .node, nodeID: chapter.nodes[0].id)]
        if newChapter { draft.chapters = [] }
        var material = ProjectEditNode(); material.name = "Pending exact e\u{301}"; material.description = "  Keep\n"
        material.longitude = "121.5"; material.latitude = "31.2"; material.templateID = 41
        draft.pendingMaterials = [.init(node: material)]
        let editor = ProjectEditModel(coordinator: .init(initial: .init(draft: draft), service: ProjectEditSyntheticService(), store: .init(storage: storage),
            storyImageSource: image, storyImageJournal: .init(storage: storage), storyAudioSource: audio, storyAudioJournal: .init(storage: storage), currentSession: { owner.session }))
        await editor.load(); editor.saveLocal()
        return .init(owner: owner, storage: storage, image: image, audio: audio, editor: editor, pending: .init(model: editor), materialID: material.id)
    }
    private func open(_ c: Context, new: Bool = false) throws -> (ProjectEditPendingController.Destination, ProjectStoryMediaChapterScope) {
        if new { c.pending.createChapter(c.pending.captureNewChapter(c.materialID), name: "New local story") }
        else { c.pending.chooseChapter(try XCTUnwrap(c.editor.draft.chapters.first?.id), target: c.pending.capture(c.materialID)) }
        let original = try XCTUnwrap(c.pending.destination)
        return (original, try XCTUnwrap(c.pending.captureStoryMediaScope(original)))
    }
    private func imageModel(_ c: Context, _ scope: ProjectStoryMediaChapterScope) throws -> (ProjectStoryImagePresentation, ProjectStoryImageAuthorModel) {
        let controller = ProjectStoryImagePresentation(editor: c.editor, host: .pending(scope))
        controller.open(try XCTUnwrap(controller.capture(chapterID: scope.chapterID)))
        return (controller, .init(original: try XCTUnwrap(controller.presentation), picker: ProjectStoryImageSynthetic.Picker(c.image.picked), apply: { controller.apply($0) }))
    }
    private func selectImage(_ model: ProjectStoryImageAuthorModel) async throws {
        model.load(); await model.choose(); let crop = try XCTUnwrap(model.crop.draft)
        model.confirmCrop(crop.id, try .init(sourceWidth: crop.source.width, sourceHeight: crop.source.height, horizontal: 0.5, vertical: 0.5, zoom: 1))
    }
    private func uploadImage(_ model: ProjectStoryImageAuthorModel) async throws {
        try await selectImage(model); model.upload(try XCTUnwrap(model.flow.review))
        for _ in 0..<100 where model.flow.busy { await Task.yield() }
        XCTAssertNotNil(model.flow.receipt)
    }
    private func audioModel(_ c: Context, _ scope: ProjectStoryMediaChapterScope) throws -> (ProjectStoryAudioPresentation, ProjectStoryAudioAuthorModel, String) {
        let controller = ProjectStoryAudioPresentation(editor: c.editor, host: .pending(scope))
        let hash = ProjectStoryImageTarget.hash(try XCTUnwrap(ProjectEditPendingMaterials.exactData(c.editor.draft)))
        let id = try XCTUnwrap(controller.insertEmpty(chapterID: scope.chapterID, lease: c.editor.captureStarterLease(), topology: c.editor.storyTopologyRevision, draftHash: hash))
        controller.open(try XCTUnwrap(controller.capture(chapterID: scope.chapterID, blockID: id)))
        return (controller, .init(original: try XCTUnwrap(controller.presentation), picker: ProjectStoryAudioSynthetic.Picker(c.audio.picked), apply: { controller.apply($0) }), id)
    }
    private func uploadAudio(_ model: ProjectStoryAudioAuthorModel) async throws {
        model.load(); await model.choose(); model.upload(try XCTUnwrap(model.flow.review))
        for _ in 0..<100 where model.flow.busy { await Task.yield() }
        XCTAssertNotNil(model.flow.receipt)
    }
    private func saved(_ c: Context) throws -> ProjectEditDraft {
        guard case .ready(let value) = ProjectEditLocalStore(storage: c.storage).load(session: try XCTUnwrap(c.owner.session), identity: try XCTUnwrap(c.editor.coordinator.identity), baseline: c.editor.draft) else { throw ProjectEditError.persistenceUnavailable }
        return value.draft
    }
    func testNewPendingChapterImageCancelApplyBackAndReopenKeepMaterialUnplaced() async throws {
        let c = try await context(newChapter: true), (destination, scope) = try open(c, new: true)
        XCTAssertEqual(c.editor.draft.chapters.count, 1); XCTAssertEqual(c.editor.draft.pendingMaterials?.count, 1)
        let (controller, model) = try imageModel(c, scope); model.load(); await model.choose()
        model.cancelCrop(try XCTUnwrap(model.crop.draft).id)
        XCTAssertEqual(c.image.uploadCount, 0); XCTAssertTrue(c.editor.draft.chapters[0].blocks?.isEmpty == true)
        try await uploadImage(model); model.apply()
        XCTAssertNil(controller.presentation); XCTAssertTrue(c.pending.isCurrent(destination))
        XCTAssertEqual(c.editor.draft.pendingMaterials?.first?.id, c.materialID); XCTAssertTrue(c.editor.draft.chapters[0].nodes.isEmpty)
        let exact = c.image.reference; XCTAssertEqual(Array(try XCTUnwrap(saved(c).chapters[0].blocks?.last?.url).utf8), Array(exact.utf8))
        c.pending.close(destination); let (_, reopened) = try open(c)
        XCTAssertFalse(scope.isCurrent(editor: c.editor, chapterID: scope.chapterID)); XCTAssertNotEqual(scope.id, reopened.id)
        XCTAssertEqual(reopened.chapter(editor: c.editor, chapterID: reopened.chapterID)?.wrappedValue.blocks?.last?.url, exact)
        XCTAssertEqual(c.image.uploadCount, 1)
    }
    func testExistingPendingStoryAudioApplyThenExplicitNodeInsertClosesOldMediaScope() async throws {
        let c = try await context(), (destination, scope) = try open(c), (controller, model, id) = try audioModel(c, scope)
        model.load(); await model.choose(); model.cancel(try XCTUnwrap(model.flow.review))
        XCTAssertEqual(c.audio.uploadCount, 0); XCTAssertEqual(c.editor.draft.chapters[0].blocks?.last?.url, "")
        try await uploadAudio(model); let old = try XCTUnwrap(controller.presentation); model.apply()
        XCTAssertNil(controller.presentation); XCTAssertEqual(c.editor.draft.pendingMaterials?.count, 1)
        XCTAssertEqual(try saved(c).chapters[0].blocks?.last?.id, id)
        c.pending.insert(c.pending.slot(destination, before: nil))
        XCTAssertNil(c.pending.destination); XCTAssertEqual(c.editor.draft.pendingMaterials?.count, 0)
        let after = ProjectEditPendingMaterials.exactData(c.editor.draft)
        controller.apply(old); controller.open(old.opening)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.editor.draft), after); XCTAssertNil(controller.presentation)
        XCTAssertFalse(scope.isCurrent(editor: c.editor, chapterID: scope.chapterID)); XCTAssertEqual(c.audio.uploadCount, 1)
    }
    func testArbitraryOverrideWrongModelAndWrongChapterCannotBorrowOwnedScope() async throws {
        let c = try await context(), other = try await context()
        var second = ProjectEditChapter(); second.name = "Another real chapter"; second.blocks = [.init(kind: .text, content: "Different real story")]
        c.editor.draft.chapters.append(second)
        let (_, scope) = try open(c)
        other.editor.draft = c.editor.draft
        XCTAssertFalse(scope.isCurrent(editor: other.editor, chapterID: scope.chapterID))
        XCTAssertNil(scope.chapter(editor: other.editor, chapterID: scope.chapterID))
        let unavailable = ProjectStoryImagePresentation(editor: c.editor, host: .unavailable)
        XCTAssertNil(unavailable.capture(chapterID: scope.chapterID))
        let audio = ProjectStoryAudioPresentation(editor: c.editor, host: .unavailable)
        XCTAssertNil(audio.insertEmpty(chapterID: scope.chapterID, lease: c.editor.captureStarterLease(), topology: c.editor.storyTopologyRevision,
            draftHash: ProjectStoryImageTarget.hash(try XCTUnwrap(ProjectEditPendingMaterials.exactData(c.editor.draft)))))
        let allowed = ProjectStoryImagePresentation(editor: c.editor, host: .pending(scope))
        XCTAssertNil(allowed.capture(chapterID: second.id))
        XCTAssertNotNil(allowed.capture(chapterID: scope.chapterID)); XCTAssertEqual(c.image.uploadCount, 0)
    }
    func testOldParentCloseBeforeQueuedImageDispatchCannotUploadOrCloseNewDestination() async throws {
        let c = try await context(), (old, scope) = try open(c), (controller, model) = try imageModel(c, scope)
        try await selectImage(model); model.upload(try XCTUnwrap(model.flow.review)); c.pending.close(old)
        let (next, currentScope) = try open(c)
        c.pending.close(old); model.apply(); for _ in 0..<100 { await Task.yield() }
        XCTAssertEqual(c.pending.destination?.id, next.id); XCTAssertTrue(currentScope.isCurrent(editor: c.editor, chapterID: scope.chapterID))
        XCTAssertEqual(c.image.uploadCount, 0); XCTAssertFalse(model.flow.isCurrent)
        controller.close(model.original); XCTAssertEqual(c.pending.destination?.id, next.id)
    }
    func testHeldAudioAfterParentCloseAndReopenCannotFillNewDestination() async throws {
        let c = try await context(), (old, scope) = try open(c), (_, model, id) = try audioModel(c, scope)
        c.audio.wire.held = true; model.load(); await model.choose(); model.upload(try XCTUnwrap(model.flow.review))
        for _ in 0..<100 where c.audio.wire.pending == nil { await Task.yield() }; XCTAssertNotNil(c.audio.wire.pending)
        c.pending.close(old); let (next, _) = try open(c); let before = ProjectEditPendingMaterials.exactData(c.editor.draft)
        c.audio.wire.release(); for _ in 0..<100 where model.flow.busy { await Task.yield() }; model.apply()
        XCTAssertEqual(c.pending.destination?.id, next.id); XCTAssertFalse(model.flow.isCurrent)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.editor.draft), before)
        XCTAssertEqual(c.editor.draft.chapters[0].blocks?.first(where: { $0.id == id })?.url, ""); XCTAssertEqual(c.audio.uploadCount, 1)
    }
    func testActualReorderAndDeleteRestoreABARejectReceivedImageInPendingHost() async throws {
        for deletion in [false, true] {
            let c = try await context(), (_, scope) = try open(c), (_, model) = try imageModel(c, scope)
            try await uploadImage(model); let original = c.editor.draft
            if deletion { c.editor.draft.chapters.removeAll() } else { c.editor.draft.chapters[0].blocks?.reverse() }
            c.editor.draft = original; model.apply()
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.editor.draft), ProjectEditPendingMaterials.exactData(original))
            XCTAssertFalse(model.flow.isCurrent); XCTAssertEqual(c.image.uploadCount, 1)
        }
    }
    func testPendingImageLocalSaveFailureRetainsMaterialAndRetriesWithoutUpload() async throws {
        let c = try await context(), (destination, scope) = try open(c), (_, model) = try imageModel(c, scope)
        try await uploadImage(model); let original = ProjectEditPendingMaterials.exactData(c.editor.draft)
        c.storage.failWrites = true; model.apply(); XCTAssertEqual(model.flow.state, .localSaveFailed)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.editor.draft), original); XCTAssertTrue(c.pending.isCurrent(destination))
        c.storage.failWrites = false; model.apply(); XCTAssertEqual(c.image.uploadCount, 1)
        XCTAssertEqual(try saved(c).pendingMaterials?.first?.id, c.materialID)
    }
    func testExplicitRestoreAndAccountChangeRetireScopeWithoutChangingSavedMaterial() async throws {
        let c = try await context(), (_, scope) = try open(c), (_, model) = try imageModel(c, scope)
        try await uploadImage(model); c.editor.restore()
        XCTAssertFalse(scope.isCurrent(editor: c.editor, chapterID: scope.chapterID)); let before = c.storage.data
        model.apply(); XCTAssertEqual(c.storage.data, before)
        c.owner.session = try .init(accountID: 8, epoch: 2, storageNamespace: "pending-story-media")
        XCTAssertNil(scope.chapter(editor: c.editor, chapterID: scope.chapterID)); model.apply(); XCTAssertEqual(c.storage.data, before)
    }
}
#endif

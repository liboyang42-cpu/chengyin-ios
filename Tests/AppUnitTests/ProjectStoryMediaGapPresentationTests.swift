import XCTest
import SwiftUI
@testable import Questify

#if DEBUG
@MainActor final class ProjectStoryMediaGapPresentationTests: XCTestCase {
    private final class Owner { var session: ProjectEditSession? = try? .init(accountID: 7, epoch: 1, storageNamespace: "media-gap-host") }
    private final class Storage: ProjectEditDataStorage {
        var data: [String: Data] = [:], failWrites = false, failAppliedMarkerOnce = false
        func read(_ key: String) throws -> Data? { data[key] }
        func remove(_ key: String) throws { data[key] = nil }
        func write(_ value: Data, key: String) throws {
            if failWrites { throw ProjectEditError.persistenceUnavailable }
            if failAppliedMarkerOnce, let json = try? JSONDecoder().decode([String: ProjectEditJSON].self, from: value),
               json["entries"]?.array?.contains(where: { $0.object?["applied"] == .bool(true) }) == true {
                failAppliedMarkerOnce = false; throw ProjectEditError.persistenceUnavailable
            }
            data[key] = value
        }
    }
    @MainActor private struct Context {
        let owner: Owner, storage: Storage, image: ProjectStoryImageSynthetic, audio: ProjectStoryAudioSynthetic
        let baseline: ProjectEditDraft, editor: ProjectEditModel
        var chapterID: String { editor.draft.chapters[0].id }
    }
    private func context() async throws -> Context {
        let owner = Owner(), storage = Storage(), session = try XCTUnwrap(owner.session)
        let image = try ProjectStoryImageSynthetic(session: session, currentSession: { owner.session })
        let audio = try ProjectStoryAudioSynthetic(session: session, currentSession: { owner.session })
        var draft = ProjectEditSyntheticFixtures.draft(); let chapter = draft.chapters[0]
        draft.preserved["publishMode"] = .string("pro")
        draft.chapters[0].blocks = [.init(kind: .text, content: chapter.description), .init(kind: .node, nodeID: chapter.nodes[0].id), .init(kind: .text, content: "Last story")]
        var material = ProjectEditNode(); material.name = "Keep pending"; material.description = "Pending"; material.templateID = 41
        material.longitude = "121.5"; material.latitude = "31.2"; draft.pendingMaterials = [.init(node: material)]
        let editor = makeEditor(draft, owner, storage, image, audio)
        await editor.load(); editor.saveLocal()
        return .init(owner: owner, storage: storage, image: image, audio: audio, baseline: draft, editor: editor)
    }
    private func makeEditor(_ draft: ProjectEditDraft, _ owner: Owner, _ storage: Storage,
                            _ image: ProjectStoryImageSynthetic, _ audio: ProjectStoryAudioSynthetic) -> ProjectEditModel {
        .init(coordinator: .init(initial: .init(draft: draft), service: ProjectEditSyntheticService(), store: .init(storage: storage),
            storyImageSource: image, storyImageJournal: .init(storage: storage), storyAudioSource: audio, storyAudioJournal: .init(storage: storage), currentSession: { owner.session }))
    }
    private func saved(_ c: Context) throws -> ProjectEditDraft {
        guard case .ready(let value) = ProjectEditLocalStore(storage: c.storage).load(session: try XCTUnwrap(c.owner.session), identity: try XCTUnwrap(c.editor.coordinator.identity), baseline: c.baseline) else { throw ProjectEditError.persistenceUnavailable }
        return value.draft
    }
    private func openImage(_ c: Context, _ controller: ProjectStoryImagePresentation, before anchor: String?) throws -> ProjectStoryImageAuthorModel {
        controller.open(try XCTUnwrap(controller.capture(chapterID: c.chapterID, insertingBefore: anchor)))
        return .init(original: try XCTUnwrap(controller.presentation), picker: ProjectStoryImageSynthetic.Picker(c.image.picked), apply: { controller.apply($0) })
    }
    private func imageUpload(_ model: ProjectStoryImageAuthorModel) async throws {
        model.load(); await model.choose(); let crop = try XCTUnwrap(model.crop.draft)
        model.confirmCrop(crop.id, try .init(sourceWidth: crop.source.width, sourceHeight: crop.source.height, horizontal: 0.5, vertical: 0.5, zoom: 1))
        model.upload(try XCTUnwrap(model.flow.review)); for _ in 0..<100 where model.flow.busy { await Task.yield() }
        XCTAssertNotNil(model.flow.receipt)
    }
    private func openAudio(_ c: Context, _ controller: ProjectStoryAudioPresentation, blockID: String, cancelNext: Bool = false) throws -> ProjectStoryAudioAuthorModel {
        controller.open(try XCTUnwrap(controller.capture(chapterID: c.chapterID, blockID: blockID)))
        return .init(original: try XCTUnwrap(controller.presentation), picker: ProjectStoryAudioSynthetic.Picker(c.audio.picked, cancelNext: cancelNext), apply: { controller.apply($0) })
    }
    private func audioUpload(_ model: ProjectStoryAudioAuthorModel) async throws {
        model.load(); await model.choose(); model.upload(try XCTUnwrap(model.flow.review))
        for _ in 0..<100 where model.flow.busy { await Task.yield() }; XCTAssertNotNil(model.flow.receipt)
    }
    func testActualImageFirstMiddleEndSaveAndColdReopenKeepExactOrder() async throws {
        for index in [0, 1, 3] {
            let c = try await context(), old = try XCTUnwrap(c.editor.draft.chapters[0].blocks)
            let controller = ProjectStoryImagePresentation(editor: c.editor), anchor = index < old.count ? old[index].id : nil
            let model = try openImage(c, controller, before: anchor); try await imageUpload(model)
            XCTAssertEqual(c.editor.draft.chapters[0].blocks, old); model.apply()
            XCTAssertNil(controller.presentation); XCTAssertEqual(c.image.uploadCount, 1)
            let blocks = try XCTUnwrap(saved(c).chapters[0].blocks), image = blocks[index]
            XCTAssertEqual(image.kind, .image); XCTAssertEqual(Array(image.url.utf8), Array(c.image.reference.utf8))
            XCTAssertEqual(blocks.filter { $0.id != image.id }, old)
            c.editor.leave(); let cold = makeEditor(c.baseline, c.owner, c.storage, c.image, c.audio)
            await cold.load(); XCTAssertTrue(cold.canRestore); cold.restore()
            XCTAssertEqual(cold.draft.chapters[0].blocks, blocks); XCTAssertEqual(c.image.uploadCount, 1)
        }
    }
    func testActualAudioFirstMiddleEndCancelKeepsBlankThenFillsSameSavedBlock() async throws {
        for index in [0, 1, 3] {
            let c = try await context(), old = try XCTUnwrap(c.editor.draft.chapters[0].blocks), controller = ProjectStoryAudioPresentation(editor: c.editor)
            let anchor = index < old.count ? old[index].id : nil
            let slot = try XCTUnwrap(controller.captureInsertion(chapterID: c.chapterID, before: anchor))
            let id = try XCTUnwrap(controller.insertEmpty(chapterID: c.chapterID, captured: slot)); XCTAssertNil(controller.insertEmpty(chapterID: c.chapterID, captured: slot))
            XCTAssertEqual(try saved(c).chapters[0].blocks?[index].id, id); XCTAssertEqual(c.audio.uploadCount, 0)
            let model = try openAudio(c, controller, blockID: id, cancelNext: true)
            model.load(); await model.choose(); XCTAssertNil(model.flow.review); XCTAssertEqual(try saved(c).chapters[0].blocks?[index].url, "")
            try await audioUpload(model); model.apply(); XCTAssertNil(controller.presentation)
            let blocks = try XCTUnwrap(saved(c).chapters[0].blocks)
            XCTAssertEqual(blocks[index].id, id); XCTAssertEqual(blocks[index].url, c.audio.reference)
            XCTAssertEqual(blocks.filter { $0.id != id }, old); XCTAssertEqual(c.audio.uploadCount, 1)
        }
    }
    func testImageGapCropAndReviewCancellationNeverLeaveAnEmptyImage() async throws {
        let c = try await context(), before = ProjectEditPendingMaterials.exactData(c.editor.draft), controller = ProjectStoryImagePresentation(editor: c.editor)
        let model = try openImage(c, controller, before: try XCTUnwrap(c.editor.draft.chapters[0].blocks?[1].id))
        model.load(); await model.choose(); model.cancelCrop(try XCTUnwrap(model.crop.draft).id)
        await model.choose(); let crop = try XCTUnwrap(model.crop.draft)
        model.confirmCrop(crop.id, try .init(sourceWidth: crop.source.width, sourceHeight: crop.source.height, horizontal: 0.5, vertical: 0.5, zoom: 1))
        model.cancel(try XCTUnwrap(model.flow.review))
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.editor.draft), before); XCTAssertEqual(c.image.uploadCount, 0)
    }
    func testDurableImageReceiptColdRecoveryKeepsOriginalGapAndDoesNotReupload() async throws {
        let c = try await context(), anchor = try XCTUnwrap(c.editor.draft.chapters[0].blocks?[1].id), controller = ProjectStoryImagePresentation(editor: c.editor)
        let model = try openImage(c, controller, before: anchor); try await imageUpload(model)
        let original = try XCTUnwrap(controller.presentation); controller.close(original); c.editor.leave()
        let cold = makeEditor(c.baseline, c.owner, c.storage, c.image, c.audio); await cold.load(); cold.restore()
        let reopened = ProjectStoryImagePresentation(editor: cold)
        reopened.open(try XCTUnwrap(reopened.capture(chapterID: c.chapterID, insertingBefore: anchor)))
        let current = try XCTUnwrap(reopened.presentation); current.flow.load()
        XCTAssertEqual(current.flow.target, original.flow.target); XCTAssertTrue(current.flow.canApply)
        XCTAssertNotEqual(current.opening.lease.incarnation, original.opening.lease.incarnation)
        reopened.apply(current); XCTAssertNil(reopened.presentation); XCTAssertEqual(cold.draft.chapters[0].blocks?[1].id, original.flow.target.resultingBlockID)
        XCTAssertEqual(cold.draft.chapters[0].blocks?[2].id, anchor); XCTAssertEqual(c.image.uploadCount, 1)
    }
    func testUnstoredImageReceiptReopenAndLocalSaveFailureRecoverOnlySameGap() async throws {
        let c = try await context(), anchor = try XCTUnwrap(c.editor.draft.chapters[0].blocks?[1].id), controller = ProjectStoryImagePresentation(editor: c.editor)
        c.image.wire.beforeReply = { c.storage.failWrites = true }
        let model = try openImage(c, controller, before: anchor); try await imageUpload(model)
        XCTAssertTrue(model.flow.hasUnstoredReceipt); controller.close(try XCTUnwrap(controller.presentation)); c.storage.failWrites = false
        let wrong = try openImage(c, controller, before: nil); wrong.load(); XCTAssertNil(wrong.flow.receipt)
        controller.close(try XCTUnwrap(controller.presentation))
        let right = try openImage(c, controller, before: anchor); right.load(); XCTAssertTrue(right.flow.hasUnstoredReceipt)
        right.persistReceipt(); c.storage.failWrites = true; right.apply(); XCTAssertEqual(right.flow.state, .localSaveFailed)
        XCTAssertEqual(c.editor.draft.chapters[0].blocks?.count, 3)
        c.storage.failWrites = false; right.apply(); XCTAssertNil(controller.presentation)
        XCTAssertEqual(c.editor.draft.chapters[0].blocks?[2].id, anchor); XCTAssertEqual(c.image.uploadCount, 1)
    }
    func testInsertAppliedMarkerFailureRetriesLocallyAndFreshRecoveryRecognizesExactPostimage() async throws {
        let c = try await context(), anchor = try XCTUnwrap(c.editor.draft.chapters[0].blocks?[1].id), controller = ProjectStoryImagePresentation(editor: c.editor)
        let model = try openImage(c, controller, before: anchor); try await imageUpload(model); c.storage.failAppliedMarkerOnce = true; model.apply()
        XCTAssertEqual(model.flow.state, .localSaveFailed); XCTAssertTrue(model.flow.canApply); XCTAssertTrue(model.flow.alreadyApplied)
        let inserted = model.flow.target.resultingBlockID; controller.close(try XCTUnwrap(controller.presentation))
        let reopened = try openImage(c, controller, before: anchor); reopened.load()
        XCTAssertEqual(reopened.flow.target.resultingBlockID, inserted); XCTAssertTrue(reopened.flow.alreadyApplied); reopened.apply()
        XCTAssertNil(controller.presentation); XCTAssertEqual(c.editor.draft.chapters[0].blocks?.count, 4); XCTAssertEqual(c.image.uploadCount, 1)
    }
    func testCapturedImageAndAudioGapRejectDeleteMoveDuplicateReplaceAndABA() async throws {
        for mutation in 0..<9 {
            let c = try await context(), anchor = try XCTUnwrap(c.editor.draft.chapters[0].blocks?[1].id)
            let images = ProjectStoryImagePresentation(editor: c.editor), audios = ProjectStoryAudioPresentation(editor: c.editor)
            let image = try XCTUnwrap(images.capture(chapterID: c.chapterID, insertingBefore: anchor)), audio = try XCTUnwrap(audios.captureInsertion(chapterID: c.chapterID, before: anchor))
            let original = c.editor.draft.chapters[0].blocks
            switch mutation {
            case 0: c.editor.draft.chapters[0].blocks?.remove(at: 1)
            case 1: c.editor.draft.chapters[0].blocks?.swapAt(0, 1)
            case 2: c.editor.draft.chapters[0].blocks?.append(try XCTUnwrap(original?[1]))
            case 3: c.editor.draft.chapters[0].blocks?[1].content = "Replaced with same ID"
            case 4: c.editor.draft.chapters[0].blocks?.reverse(); c.editor.draft.chapters[0].blocks = original
            case 5: c.editor.draft.chapters[0].blocks?.remove(at: 1); c.editor.draft.chapters[0].blocks = original
            case 6: c.editor.draft.chapters[0].blocks?[1].kind = .text; c.editor.draft.chapters[0].blocks = original
            case 7:
                var other = ProjectEditChapter(); other.blocks = [try XCTUnwrap(original?[1])]
                c.editor.draft.chapters[0].blocks?.remove(at: 1); c.editor.draft.chapters.append(other)
            default: c.editor.draft.chapters[0].blocks?[1].content = "Temporary replacement"; c.editor.draft.chapters[0].blocks = original
            }
            let after = ProjectEditPendingMaterials.exactData(c.editor.draft)
            images.open(image); XCTAssertNil(images.presentation); XCTAssertNil(audios.insertEmpty(chapterID: c.chapterID, captured: audio))
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.editor.draft), after); XCTAssertEqual(c.image.uploadCount + c.audio.uploadCount, 0)
        }
    }
    func testLiveImageReceiptCannotApplyAfterAnchorReplaceRevertButFreshExactRecoveryCan() async throws {
        let c = try await context(), anchor = try XCTUnwrap(c.editor.draft.chapters[0].blocks?[1].id), controller = ProjectStoryImagePresentation(editor: c.editor)
        let model = try openImage(c, controller, before: anchor); try await imageUpload(model)
        let original = c.editor.draft.chapters[0].blocks, before = c.storage.data
        c.editor.draft.chapters[0].blocks?[1].kind = .text; c.editor.draft.chapters[0].blocks = original
        XCTAssertFalse(model.flow.isCurrent); model.apply(); XCTAssertEqual(c.storage.data, before)
        controller.close(try XCTUnwrap(controller.presentation)); let fresh = try openImage(c, controller, before: anchor); fresh.load()
        XCTAssertTrue(fresh.flow.canApply); fresh.apply(); XCTAssertEqual(c.editor.draft.chapters[0].blocks?[2].id, anchor); XCTAssertEqual(c.image.uploadCount, 1)
    }
    func testQueuedImageUploadAfterGapReplacementCannotSendIntoAnotherDraft() async throws {
        let c = try await context(), controller = ProjectStoryImagePresentation(editor: c.editor)
        let model = try openImage(c, controller, before: try XCTUnwrap(c.editor.draft.chapters[0].blocks?.first?.id))
        model.load(); await model.choose(); let crop = try XCTUnwrap(model.crop.draft)
        model.confirmCrop(crop.id, try .init(sourceWidth: crop.source.width, sourceHeight: crop.source.height, horizontal: 0.5, vertical: 0.5, zoom: 1))
        model.upload(try XCTUnwrap(model.flow.review)); c.editor.discard()
        for _ in 0..<100 { await Task.yield() }
        XCTAssertEqual(c.image.uploadCount, 0); XCTAssertFalse(model.flow.isCurrent); XCTAssertEqual(c.editor.draft.chapters[0].blocks?.count, 3)
    }
    func testDelayedImageResponseAfterReplaceRevertOrDiscardCannotWriteAnotherDraft() async throws {
        for discard in [false, true] {
            let c = try await context(), controller = ProjectStoryImagePresentation(editor: c.editor)
            let model = try openImage(c, controller, before: try XCTUnwrap(c.editor.draft.chapters[0].blocks?[1].id))
            let original = c.editor.draft.chapters[0].blocks
            c.image.wire.beforeReply = {
                if discard { c.editor.discard() }
                else { c.editor.draft.chapters[0].blocks?[1].kind = .text; c.editor.draft.chapters[0].blocks = original }
            }
            model.load(); await model.choose(); let crop = try XCTUnwrap(model.crop.draft)
            model.confirmCrop(crop.id, try .init(sourceWidth: crop.source.width, sourceHeight: crop.source.height, horizontal: 0.5, vertical: 0.5, zoom: 1))
            model.upload(try XCTUnwrap(model.flow.review)); for _ in 0..<100 where model.flow.busy { await Task.yield() }
            let current = ProjectEditPendingMaterials.exactData(c.editor.draft), stored = c.storage.data
            model.apply(); XCTAssertFalse(model.flow.isCurrent); XCTAssertNil(model.flow.receipt)
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.editor.draft), current); XCTAssertEqual(c.storage.data, stored)
            XCTAssertEqual(c.editor.draft.chapters[0].blocks, original); XCTAssertEqual(c.image.uploadCount, 1)
        }
    }
    func testHeldAudioCallbackRejectsSameIDReplaceRevertAndKeepsBlankAtGap() async throws {
        let c = try await context(), controller = ProjectStoryAudioPresentation(editor: c.editor), anchor = try XCTUnwrap(c.editor.draft.chapters[0].blocks?[1].id)
        let id = try XCTUnwrap(controller.insertEmpty(chapterID: c.chapterID, captured: try XCTUnwrap(controller.captureInsertion(chapterID: c.chapterID, before: anchor))))
        let model = try openAudio(c, controller, blockID: id); c.audio.wire.held = true
        model.load(); await model.choose(); model.upload(try XCTUnwrap(model.flow.review))
        for _ in 0..<100 where c.audio.wire.pending == nil { await Task.yield() }; XCTAssertNotNil(c.audio.wire.pending)
        let blocks = c.editor.draft.chapters[0].blocks
        c.editor.draft.chapters[0].blocks?[1].kind = .text; c.editor.draft.chapters[0].blocks = blocks
        c.audio.wire.release(); for _ in 0..<100 where model.flow.busy { await Task.yield() }
        model.apply(); XCTAssertFalse(model.flow.isCurrent); XCTAssertEqual(c.editor.draft.chapters[0].blocks?[1].id, id)
        XCTAssertEqual(c.editor.draft.chapters[0].blocks?[1].url, ""); XCTAssertEqual(c.audio.uploadCount, 1)
    }
    func testAudioDurableReceiptColdRecoveryAndMarkerRetryKeepExactInsertedBlock() async throws {
        let c = try await context(), controller = ProjectStoryAudioPresentation(editor: c.editor), anchor = try XCTUnwrap(c.editor.draft.chapters[0].blocks?[1].id)
        let id = try XCTUnwrap(controller.insertEmpty(chapterID: c.chapterID, captured: try XCTUnwrap(controller.captureInsertion(chapterID: c.chapterID, before: anchor))))
        let model = try openAudio(c, controller, blockID: id); try await audioUpload(model)
        controller.close(try XCTUnwrap(controller.presentation)); c.editor.leave()
        let cold = makeEditor(c.baseline, c.owner, c.storage, c.image, c.audio); await cold.load(); cold.restore()
        let fresh = ProjectStoryAudioPresentation(editor: cold); fresh.open(try XCTUnwrap(fresh.capture(chapterID: c.chapterID, blockID: id)))
        let current = try XCTUnwrap(fresh.presentation); current.flow.load(); XCTAssertTrue(current.flow.canApply)
        c.storage.failAppliedMarkerOnce = true; fresh.apply(current); XCTAssertEqual(current.flow.state, .localSaveFailed); XCTAssertTrue(current.flow.canApply)
        fresh.apply(current); XCTAssertNil(fresh.presentation); XCTAssertEqual(cold.draft.chapters[0].blocks?[1].id, id)
        XCTAssertEqual(cold.draft.chapters[0].blocks?[2].id, anchor); XCTAssertEqual(c.audio.uploadCount, 1)
    }
    func testTypedPendingHostAllowsExactGapsAndRetiredOrArbitraryHostsCannotAct() async throws {
        let c = try await context(), pending = ProjectEditPendingController(model: c.editor)
        let materialID = try XCTUnwrap(c.editor.draft.pendingMaterials?.first?.id)
        pending.chooseChapter(c.chapterID, target: pending.capture(materialID)); let destination = try XCTUnwrap(pending.destination)
        let scope = try XCTUnwrap(pending.captureStoryMediaScope(destination)), anchor = try XCTUnwrap(c.editor.draft.chapters[0].blocks?[1].id)
        let images = ProjectStoryImagePresentation(editor: c.editor, host: .pending(scope)), audios = ProjectStoryAudioPresentation(editor: c.editor, host: .pending(scope))
        let model = try openImage(c, images, before: anchor); try await imageUpload(model); model.apply()
        XCTAssertTrue(pending.isCurrent(destination)); XCTAssertEqual(c.editor.draft.pendingMaterials?.first?.id, materialID)
        let slot = try XCTUnwrap(audios.captureInsertion(chapterID: c.chapterID, before: anchor)); pending.close(destination)
        XCTAssertNil(audios.insertEmpty(chapterID: c.chapterID, captured: slot)); XCTAssertNil(images.capture(chapterID: c.chapterID, insertingBefore: anchor))
        XCTAssertNil(ProjectStoryAudioPresentation(editor: c.editor, host: .unavailable).captureInsertion(chapterID: c.chapterID, before: anchor))
        XCTAssertNil(ProjectStoryImagePresentation(editor: c.editor, host: .unavailable).capture(chapterID: c.chapterID, insertingBefore: anchor))
    }
    func testOwnerAndEditorIncarnationChangesRejectCapturedEndGap() async throws {
        let c = try await context(), audios = ProjectStoryAudioPresentation(editor: c.editor), images = ProjectStoryImagePresentation(editor: c.editor)
        let audio = try XCTUnwrap(audios.captureInsertion(chapterID: c.chapterID, before: nil)), image = try XCTUnwrap(images.capture(chapterID: c.chapterID))
        let old = try XCTUnwrap(c.owner.session); c.owner.session = try .init(accountID: 8, epoch: 2, storageNamespace: old.storageNamespace)
        XCTAssertNil(audios.insertEmpty(chapterID: c.chapterID, captured: audio)); images.open(image); XCTAssertNil(images.presentation)
        c.owner.session = old; c.editor.discard(); XCTAssertNil(audios.insertEmpty(chapterID: c.chapterID, captured: audio)); images.open(image); XCTAssertNil(images.presentation)
    }
}
#endif

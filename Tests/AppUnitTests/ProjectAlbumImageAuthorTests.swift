import XCTest
@testable import Questify

#if DEBUG
@MainActor final class ProjectAlbumImageAuthorTests: XCTestCase {
    private final class Owner { var session: ProjectEditSession? = try? .init(accountID: 7, epoch: 1, storageNamespace: "album-image-host") }
    private final class Storage: ProjectEditDataStorage {
        var data: [String: Data] = [:], failAppliedMarkerOnce = false, failWrites = false
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
    private struct Context {
        let owner: Owner, storage: Storage, source: ProjectStoryImageSynthetic
        let baseline: ProjectEditDraft, editor: ProjectEditModel, controller: ProjectStoryImagePresentation
        var chapterID: String { editor.draft.chapters[0].id }
        let albumID = "album-é"
    }
    private func makeEditor(_ draft: ProjectEditDraft, _ owner: Owner, _ storage: Storage, _ source: ProjectStoryImageSynthetic) -> ProjectEditModel {
        .init(coordinator: .init(initial: .init(draft: draft), service: ProjectEditSyntheticService(), store: .init(storage: storage),
            storyImageSource: source, storyImageJournal: .init(storage: storage), currentSession: { owner.session }))
    }
    private func context(_ count: Int = 2, active: Bool = true) async throws -> Context {
        let owner = Owner(), storage = Storage(), source = try ProjectStoryImageSynthetic(session: XCTUnwrap(owner.session), currentSession: { owner.session })
        var draft = ProjectEditSyntheticFixtures.draft(), album = ProjectEditBlock(kind: .dream)
        album.id = "album-é"; album.sourceFields = ["title": .string("Album"), "images": .array((0..<count).map { _ in
            .object(["url": .string("https://example.com/same.jpg"), "line": .string(" raw caption ")])
        })]
        draft.preserved["publishMode"] = .string("pro")
        draft.chapters[0].blocks = [.init(kind: .text, content: draft.chapters[0].description), album,
                                    .init(kind: .node, nodeID: draft.chapters[0].nodes[0].id)]
        let editor = makeEditor(draft, owner, storage, source); await editor.load(); editor.saveLocal()
        let controller = ProjectStoryImagePresentation(editor: editor); controller.setAlbumHostActive(active)
        return .init(owner: owner, storage: storage, source: source, baseline: draft, editor: editor, controller: controller)
    }
    private func open(_ c: Context) throws -> ProjectStoryImagePresentation.Presentation {
        c.controller.open(try XCTUnwrap(c.controller.captureAlbum(chapterID: c.chapterID, blockID: c.albumID)))
        return try XCTUnwrap(c.controller.presentation)
    }
    private func model(_ c: Context, _ p: ProjectStoryImagePresentation.Presentation) -> ProjectStoryImageAuthorModel {
        .init(original: p, picker: ProjectStoryImageSynthetic.Picker(c.source.picked), apply: { c.controller.apply($0) })
    }
    private func select(_ m: ProjectStoryImageAuthorModel) async throws {
        m.load(); await m.choose(); let crop = try XCTUnwrap(m.crop.draft)
        m.confirmCrop(crop.id, try .init(sourceWidth: crop.source.width, sourceHeight: crop.source.height, horizontal: 0.5, vertical: 0.5, zoom: 1))
        XCTAssertNotNil(m.flow.review)
    }
    private func upload(_ m: ProjectStoryImageAuthorModel) async throws {
        try await select(m); m.upload(try XCTUnwrap(m.flow.review))
        for _ in 0..<100 where m.flow.busy { await Task.yield() }
        XCTAssertNotNil(m.flow.receipt)
    }
    func testInactiveAndRetiredHostCannotOpenRetainedAlbumCapture() async throws {
        let c = try await context(active: false)
        XCTAssertNil(c.controller.captureAlbum(chapterID: c.chapterID, blockID: c.albumID))
        c.controller.setAlbumHostActive(true)
        let opening = try XCTUnwrap(c.controller.captureAlbum(chapterID: c.chapterID, blockID: c.albumID))
        c.controller.setAlbumHostActive(false); c.controller.setAlbumHostActive(true); c.controller.open(opening)
        XCTAssertNil(c.controller.presentation); XCTAssertEqual(c.source.uploadCount, 0)
        let unavailable = ProjectStoryImagePresentation(editor: c.editor, host: .unavailable); unavailable.setAlbumHostActive(true)
        XCTAssertNil(unavailable.captureAlbum(chapterID: c.chapterID, blockID: c.albumID))
    }
    func testAlbumCropCancelLeavesNoEmptyRowAndNoUpload() async throws {
        let c = try await context(), p = try open(c), m = model(c, p), before = ProjectEditPendingMaterials.exactData(c.editor.draft)
        m.load(); await m.choose(); let crop = try XCTUnwrap(m.crop.draft); m.cancelCrop(crop.id)
        XCTAssertNil(m.flow.review); XCTAssertEqual(c.source.uploadCount, 0)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.editor.draft), before)
        m.close(); c.controller.close(p)
    }
    func testAlbumExplicitUploadThenAppendPreservesNeighborsAndPreparedReference() async throws {
        let c = try await context(), p = try open(c), m = model(c, p), before = c.editor.draft
        try await select(m); XCTAssertEqual(c.source.uploadCount, 0)
        m.upload(try XCTUnwrap(m.flow.review)); for _ in 0..<100 where m.flow.busy { await Task.yield() }
        let receipt = try XCTUnwrap(m.flow.receipt)
        XCTAssertEqual(c.source.uploadCount, 1); XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.editor.draft), ProjectEditPendingMaterials.exactData(before))
        m.apply(); XCTAssertNil(c.controller.presentation)
        var expected = before
        let old = try XCTUnwrap(before.chapters[0].blocks?[1].sourceFields?["images"]?.array)
        expected.chapters[0].blocks?[1].sourceFields?["images"] = .array(old + [.object(["url": .string(receipt.reference), "line": .string("")])])
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.editor.draft), ProjectEditPendingMaterials.exactData(expected))
        c.editor.review(); let request = try XCTUnwrap(c.editor.confirmation)
        let value = try XCTUnwrap(request.payload["chapters"]?.array?[0].object?["blocks"]?.array?[1].object?["images"]?.array?.last?.object?["url"]?.text)
        XCTAssertEqual(Data(value.utf8), Data(receipt.reference.utf8)); XCTAssertEqual(c.source.uploadCount, 1)
    }
    func testAlbumAnyDraftSetterIncludingSameBytesRetiresUploadOrApply() async throws {
        for afterUpload in [false, true] {
            let c = try await context(), p = try open(c), m = model(c, p)
            if afterUpload { try await upload(m) } else { try await select(m) }
            let before = c.editor.draft; c.editor.draft = before
            XCTAssertFalse(p.flow.isCurrent)
            if let review = m.flow.review { m.upload(review) }
            m.apply(); for _ in 0..<30 { await Task.yield() }
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.editor.draft), ProjectEditPendingMaterials.exactData(before))
            XCTAssertEqual(c.source.uploadCount, afterUpload ? 1 : 0)
        }
    }
    func testAlbumOwnerRetirementAndBackgroundAfterClaimNeverDispatch() async throws {
        for ownerChange in [false, true] {
            let c = try await context(), p = try open(c), m = model(c, p)
            try await select(m); m.upload(try XCTUnwrap(m.flow.review))
            if ownerChange { c.owner.session = try .init(accountID: 8, epoch: 2, storageNamespace: "album-image-host") }
            else { c.controller.setAlbumHostActive(false) }
            for _ in 0..<60 { await Task.yield() }
            XCTAssertEqual(c.source.uploadCount, 0); XCTAssertFalse(p.flow.isCurrent)
            XCTAssertEqual(c.editor.draft.chapters[0].blocks?[1].sourceFields?["images"]?.array?.count, 2)
        }
    }
    func testAlbumFailedReceiptSaveReopensWithoutSecondUpload() async throws {
        let c = try await context(), p = try open(c), m = model(c, p)
        // Claim must persist before deliberately failing only the receipt write.
        try await select(m); let claim = try XCTUnwrap(m.flow.claimUpload(try XCTUnwrap(m.flow.review)))
        c.storage.failWrites = true; await m.flow.upload(claim)
        XCTAssertTrue(m.flow.hasUnstoredReceipt); XCTAssertFalse(m.flow.canApply)
        m.close(); c.controller.close(p); c.storage.failWrites = false
        let next = try open(c), nextModel = model(c, next); nextModel.load()
        XCTAssertTrue(next.flow.hasUnstoredReceipt); nextModel.persistReceipt(); nextModel.apply()
        XCTAssertEqual(c.source.uploadCount, 1); XCTAssertEqual(c.editor.draft.chapters[0].blocks?[1].sourceFields?["images"]?.array?.count, 3)
    }
    func testAlbumSixthPhotoMarkerFailureColdRecoveryProvesExactPostimage() async throws {
        let c = try await context(5), p = try open(c), m = model(c, p)
        try await upload(m); c.storage.failAppliedMarkerOnce = true; m.apply()
        XCTAssertEqual(p.flow.state, .localSaveFailed)
        let exact = ProjectEditPendingMaterials.exactData(c.editor.draft)
        XCTAssertEqual(c.editor.draft.chapters[0].blocks?[1].sourceFields?["images"]?.array?.count, 6)
        c.controller.close(p); c.editor.leave()
        let cold = makeEditor(c.baseline, c.owner, c.storage, c.source); await cold.load(); cold.restore()
        let controller = ProjectStoryImagePresentation(editor: cold); controller.setAlbumHostActive(true)
        let opening = try XCTUnwrap(controller.captureAlbum(chapterID: c.chapterID, blockID: c.albumID))
        XCTAssertNotNil(opening.recoveryOnly); controller.open(opening)
        let restored = try XCTUnwrap(controller.presentation); restored.flow.load()
        XCTAssertFalse(restored.flow.canPick); XCTAssertTrue(restored.flow.alreadyApplied); controller.apply(restored)
        XCTAssertNil(controller.presentation); XCTAssertEqual(ProjectEditPendingMaterials.exactData(cold.draft), exact)
        XCTAssertEqual(c.source.uploadCount, 1); XCTAssertNil(controller.captureAlbum(chapterID: c.chapterID, blockID: c.albumID))
    }
    func testAlbumSimilarCapacityArrayCannotBorrowReceiptRecovery() async throws {
        let c = try await context(5), p = try open(c), m = model(c, p)
        try await upload(m); c.storage.failAppliedMarkerOnce = true; m.apply(); c.controller.close(p)
        c.editor.draft.chapters[0].blocks?[1].sourceFields?["title"] = .string("Another title")
        let before = ProjectEditPendingMaterials.exactData(c.editor.draft), stored = c.storage.data
        XCTAssertNil(c.controller.captureAlbum(chapterID: c.chapterID, blockID: c.albumID))
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.editor.draft), before); XCTAssertEqual(c.storage.data, stored)
        XCTAssertEqual(c.source.uploadCount, 1)
    }
    func testAlbumOldCloseCannotDismissNewPresentationAndLocalSaveRetryNeverUploads() async throws {
        let c = try await context(), p = try open(c), m = model(c, p)
        try await upload(m); c.storage.failWrites = true; m.apply()
        XCTAssertEqual(p.flow.state, .localSaveFailed)
        c.storage.failWrites = false; c.controller.close(p)
        let next = try open(c), nextModel = model(c, next); nextModel.load()
        c.controller.close(p); XCTAssertEqual(c.controller.presentation?.id, next.id)
        nextModel.apply(); XCTAssertNil(c.controller.presentation); XCTAssertEqual(c.source.uploadCount, 1)
    }
}
#endif

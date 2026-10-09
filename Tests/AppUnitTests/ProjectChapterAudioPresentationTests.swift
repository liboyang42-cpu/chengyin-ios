import XCTest
@testable import Questify

#if DEBUG
@MainActor final class ProjectChapterAudioPresentationTests: XCTestCase {
    private final class Owner { var session: ProjectEditSession? = try? .init(accountID: 7, epoch: 1, storageNamespace: "chapter-audio-host") }
    private struct Context {
        let owner: Owner, storage: ProjectEditMemoryStorage, source: ProjectStoryAudioSynthetic
        let editor: ProjectEditModel, controller: ProjectChapterAudioPresentation
    }
    private func context(receiptFailure: Bool = false, unknown: Bool = false) async throws -> Context {
        let owner = Owner(), storage = ProjectEditMemoryStorage(), session = try XCTUnwrap(owner.session)
        var fail = receiptFailure
        let source = try ProjectStoryAudioSynthetic(session: session, unknownOnce: unknown, beforeReply: {
            if fail { fail = false; storage.failWrites = true }
        }, currentSession: { owner.session })
        var draft = ProjectEditSyntheticFixtures.draft()
        draft.chapters[0].preserved["audioUrl"] = .string("https://old.invalid/e\u{301}.mp3")
        draft.chapters[0].blocks = [.init(kind: .audio, url: "unchanged-story-block")]
        let coordinator = ProjectEditCoordinator(initial: .init(draft: draft), service: ProjectEditSyntheticService(), store: .init(storage: storage),
            storyAudioSource: source, storyAudioJournal: .init(storage: storage), currentSession: { owner.session })
        let editor = ProjectEditModel(coordinator: coordinator); await editor.load(); editor.saveLocal()
        return .init(owner: owner, storage: storage, source: source, editor: editor, controller: .init(editor: editor, chapterID: draft.chapters[0].id))
    }
    private func open(_ c: Context) throws -> ProjectChapterAudioPresentation.Presentation {
        c.controller.open(try XCTUnwrap(c.controller.capture())); return try XCTUnwrap(c.controller.presentation)
    }
    private func model(_ c: Context, _ p: ProjectChapterAudioPresentation.Presentation, cancel: Bool = false) -> ProjectStoryAudioAuthorModel {
        .init(flow: p.flow, picker: ProjectStoryAudioSynthetic.Picker(c.source.picked, cancelNext: cancel),
              permitsPicker: { p.opening.source.permitsPicker(session: p.opening.lease.session) }, apply: { c.controller.apply(p) })
    }
    private func upload(_ m: ProjectStoryAudioAuthorModel) async throws {
        m.load(); await m.choose(); m.upload(try XCTUnwrap(m.flow.review))
        for _ in 0..<100 where m.flow.busy { await Task.yield() }
    }
    func testCancelSelectionKeepsExactOriginalNarrationAndDoesNotUpload() async throws {
        let c = try await context(), original = try open(c), m = model(c, original, cancel: true)
        let before = ProjectEditPendingMaterials.exactData(c.editor.draft), storage = c.storage.data
        m.load(); await m.choose(); m.close(); c.controller.close(original)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.editor.draft), before)
        XCTAssertEqual(c.storage.data, storage); XCTAssertEqual(c.source.uploadCount, 0)
    }
    func testActualSelectionUploadExplicitApplyPersistsOnlyChapterNarration() async throws {
        let c = try await context(), original = try open(c), m = model(c, original)
        let before = c.editor.draft
        try await upload(m); XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.editor.draft), ProjectEditPendingMaterials.exactData(before))
        let receipt = try XCTUnwrap(original.flow.receipt), attempt = try XCTUnwrap(original.flow.activeAttempt)
        m.apply(); XCTAssertNil(c.controller.presentation); XCTAssertEqual(c.source.uploadCount, 1)
        XCTAssertEqual(ProjectChapterAudio.reference(in: c.editor.draft.chapters[0]), receipt.reference)
        XCTAssertEqual(c.editor.draft.chapters[0].blocks, before.chapters[0].blocks)
        let saved = try original.opening.journal.read(session: original.opening.lease.session, identity: original.opening.lease.identity)
        XCTAssertEqual(saved.entries[0].attemptID, attempt); XCTAssertTrue(saved.entries[0].applied)
        XCTAssertNil(saved.entries[0].target.blockID); XCTAssertEqual(saved.entries[0].target.kind, .chapterNarration)
    }
    func testReceiptSaveFailureReopensSameAttemptAndNeverUploadsAgain() async throws {
        let c = try await context(receiptFailure: true), old = try open(c), m = model(c, old)
        try await upload(m); let attempt = try XCTUnwrap(old.flow.activeAttempt)
        XCTAssertTrue(old.flow.hasUnstoredReceipt); m.close(); c.controller.close(old); c.storage.failWrites = false
        let next = try open(c), fresh = model(c, next); fresh.load()
        XCTAssertEqual(next.flow.activeAttempt, attempt); XCTAssertTrue(next.flow.hasUnstoredReceipt)
        fresh.persistReceipt(); fresh.apply()
        XCTAssertEqual(c.source.uploadCount, 1); XCTAssertNil(c.controller.presentation)
        XCTAssertEqual(ProjectChapterAudio.reference(in: c.editor.draft.chapters[0]), c.source.reference)
    }
    func testLocalSaveFailureKeepsOriginalAndRetriesOnlyLocalApply() async throws {
        let c = try await context(), p = try open(c), m = model(c, p)
        try await upload(m); let before = ProjectEditPendingMaterials.exactData(c.editor.draft)
        c.storage.failWrites = true; m.apply()
        XCTAssertEqual(p.flow.state, .localSaveFailed); XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.editor.draft), before)
        c.storage.failWrites = false; m.apply()
        XCTAssertNil(c.controller.presentation); XCTAssertEqual(c.source.uploadCount, 1)
    }
    func testUnknownKeepsSameDurableAttemptAndReopenDoesNotRetry() async throws {
        let c = try await context(unknown: true), p = try open(c), m = model(c, p)
        let before = ProjectEditPendingMaterials.exactData(c.editor.draft)
        try await upload(m); let attempt = try XCTUnwrap(p.flow.activeAttempt)
        XCTAssertEqual(p.flow.state, .unknown); m.close(); c.controller.close(p)
        let next = try open(c); next.flow.load()
        XCTAssertEqual(next.flow.unresolvedUploadCount, 1); XCTAssertNil(next.flow.receipt)
        XCTAssertEqual(next.flow.snapshot?.entries[0].attemptID, attempt)
        XCTAssertEqual(c.source.uploadCount, 1); XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.editor.draft), before)
    }
    func testHeldReplyAfterCancelDeleteReorderOrIdentityChangeCannotWriteDraft() async throws {
        for action in ["cancel", "delete", "reorder", "account", "sameBytesABA", "restore"] {
            let c = try await context(); c.editor.draft.chapters.append(ProjectEditChapter())
            let p = try open(c), m = model(c, p)
            c.source.wire.held = true; m.load(); await m.choose(); m.upload(try XCTUnwrap(p.flow.review))
            for _ in 0..<100 where c.source.wire.pending == nil { await Task.yield() }
            XCTAssertNotNil(c.source.wire.pending)
            switch action {
            case "cancel": m.close(); c.controller.close(p)
            case "delete": c.editor.draft.chapters.removeFirst()
            case "reorder": c.editor.draft.chapters.reverse()
            case "account": c.owner.session = try .init(accountID: 8, epoch: 2, storageNamespace: "chapter-audio-host")
            case "restore": c.editor.restore()
            default: let same = c.editor.draft; c.editor.draft = same
            }
            let before = ProjectEditPendingMaterials.exactData(c.editor.draft)
            c.source.wire.release(); for _ in 0..<100 where p.flow.busy { await Task.yield() }
            m.apply(); XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.editor.draft), before, action)
            XCTAssertFalse(p.flow.isCurrent, action); XCTAssertEqual(c.source.uploadCount, 1)
        }
    }
    func testOldDismissalCannotCloseNewChapterUploadAndCrossControllerOpeningIsRejected() async throws {
        let c = try await context(), opening = try XCTUnwrap(c.controller.capture())
        let other = ProjectChapterAudioPresentation(editor: c.editor, chapterID: c.controller.chapterID)
        other.open(opening); XCTAssertNil(other.presentation)
        let first = try open(c), binding = c.controller.binding(first); c.controller.close(first)
        let next = try open(c); binding.wrappedValue = nil; c.controller.close(first)
        XCTAssertEqual(c.controller.presentation?.id, next.id)
    }
    func testPreviewUsesIndependentPolicyConsentAndDisposalFencesOldCallback() throws {
        let driver = SyntheticPlatformAudioDriver()
        let denied = PlatformAudioPlayback(driver: driver, policy: .init(approvedOrigins: ["https://example.com"]), enabled: false)
        let media = PlatformMediaSource(url: try XCTUnwrap(URL(string: "https://example.com/chapter.mp3")), scope: UUID())
        denied.select(media); denied.approveSelectedMedia(); denied.toggle(); XCTAssertEqual(driver.starts, 0)
        let allowed = PlatformAudioPlayback(driver: driver, policy: .init(approvedOrigins: ["https://example.com"]), enabled: true)
        allowed.select(media); allowed.toggle(); XCTAssertEqual(driver.starts, 0)
        allowed.approveSelectedMedia(); allowed.toggle(); XCTAssertEqual(driver.starts, 1)
        let late = driver.event; allowed.dispose(); late?(.playing); XCTAssertEqual(allowed.state, .disposed)
        // Actual host appearance/scene/session lifecycle is still an Apple UI NOT_RUN check.
    }
}
#endif

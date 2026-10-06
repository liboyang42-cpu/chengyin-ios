import XCTest
@testable import Questify

#if DEBUG
@MainActor final class ProjectStoryImageCapacityRecoveryTests: XCTestCase {
    private final class Owner { var session: ProjectEditSession? = try? .init(accountID: 7, epoch: 1, storageNamespace: "story-gap-capacity") }
    private final class Storage: ProjectEditDataStorage {
        var data: [String: Data] = [:], failAppliedMarkerOnce = false
        func read(_ key: String) throws -> Data? { data[key] }
        func remove(_ key: String) throws { data[key] = nil }
        func write(_ value: Data, key: String) throws {
            if failAppliedMarkerOnce, let json = try? JSONDecoder().decode([String: ProjectEditJSON].self, from: value),
               json["entries"]?.array?.contains(where: { $0.object?["applied"] == .bool(true) }) == true {
                failAppliedMarkerOnce = false; throw ProjectEditError.persistenceUnavailable
            }
            data[key] = value
        }
    }
    @MainActor private struct Context {
        let owner: Owner, storage: Storage, source: ProjectStoryImageSynthetic, baseline: ProjectEditDraft, editor: ProjectEditModel
        var chapterID: String { editor.draft.chapters[0].id }
    }
    @MainActor private struct Applied {
        let context: Context, controller: ProjectStoryImagePresentation, presentation: ProjectStoryImagePresentation.Presentation
        let anchor: String?, exact: Data
    }
    private func makeEditor(_ baseline: ProjectEditDraft, _ owner: Owner, _ storage: Storage, _ source: ProjectStoryImageSynthetic) -> ProjectEditModel {
        .init(coordinator: .init(initial: .init(draft: baseline), service: ProjectEditSyntheticService(), store: .init(storage: storage),
            storyImageSource: source, storyImageJournal: .init(storage: storage), currentSession: { owner.session }))
    }
    private func context(count: Int = 199) async throws -> Context {
        let owner = Owner(), storage = Storage(), session = try XCTUnwrap(owner.session)
        let source = try ProjectStoryImageSynthetic(session: session, currentSession: { owner.session })
        var draft = ProjectEditSyntheticFixtures.draft(); let chapter = draft.chapters[0]
        draft.preserved["publishMode"] = .string("pro")
        draft.chapters[0].blocks = (0..<(count - 1)).map { .init(kind: .text, content: "Story \($0)") } + [.init(kind: .node, nodeID: chapter.nodes[0].id)]
        let editor = makeEditor(draft, owner, storage, source); await editor.load(); editor.saveLocal()
        return .init(owner: owner, storage: storage, source: source, baseline: draft, editor: editor)
    }
    private func pendingAtCapacity(position: Int) async throws -> Applied {
        let c = try await context(), blocks = try XCTUnwrap(c.editor.draft.chapters[0].blocks)
        let anchor = position < blocks.count ? blocks[position].id : nil, controller = ProjectStoryImagePresentation(editor: c.editor)
        controller.open(try XCTUnwrap(controller.capture(chapterID: c.chapterID, insertingBefore: anchor)))
        let presentation = try XCTUnwrap(controller.presentation)
        let model = ProjectStoryImageAuthorModel(original: presentation, picker: ProjectStoryImageSynthetic.Picker(c.source.picked), apply: { controller.apply($0) })
        model.load(); await model.choose(); let crop = try XCTUnwrap(model.crop.draft)
        model.confirmCrop(crop.id, try .init(sourceWidth: crop.source.width, sourceHeight: crop.source.height, horizontal: 0.5, vertical: 0.5, zoom: 1))
        model.upload(try XCTUnwrap(model.flow.review)); for _ in 0..<100 where model.flow.busy { await Task.yield() }
        XCTAssertNotNil(model.flow.receipt); c.storage.failAppliedMarkerOnce = true; model.apply()
        XCTAssertEqual(model.flow.state, .localSaveFailed); XCTAssertEqual(c.editor.draft.chapters[0].blocks?.count, 200)
        XCTAssertEqual(c.editor.draft.chapters[0].blocks?[position].id, model.flow.target.resultingBlockID)
        XCTAssertEqual(c.source.uploadCount, 1)
        return .init(context: c, controller: controller, presentation: presentation, anchor: anchor, exact: try XCTUnwrap(ProjectEditPendingMaterials.exactData(c.editor.draft)))
    }
    private func sessionAndIdentity(_ c: Context) throws -> (ProjectEditSession, ProjectEditDraftIdentity) {
        (try XCTUnwrap(c.owner.session), try XCTUnwrap(c.editor.coordinator.identity))
    }
    func testFirstMiddleEnd199To200ColdReceiptRecoveryDoesNotUploadOrInsertAgain() async throws {
        for position in [0, 99, 199] {
            let applied = try await pendingAtCapacity(position: position), c = applied.context
            applied.controller.close(applied.presentation); c.editor.leave()
            let cold = makeEditor(c.baseline, c.owner, c.storage, c.source); await cold.load(); XCTAssertTrue(cold.canRestore); cold.restore()
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(cold.draft), applied.exact)
            let controller = ProjectStoryImagePresentation(editor: cold)
            let opening = try XCTUnwrap(controller.capture(chapterID: c.chapterID, insertingBefore: applied.anchor))
            XCTAssertNotNil(opening.recoveryOnly); XCTAssertEqual(opening.target, applied.presentation.flow.target)
            XCTAssertNotEqual(opening.lease.incarnation, applied.presentation.opening.lease.incarnation)
            controller.open(opening); let current = try XCTUnwrap(controller.presentation); current.flow.load()
            XCTAssertTrue(current.flow.alreadyApplied); XCTAssertTrue(current.flow.canApply); XCTAssertFalse(current.flow.matchesCapturedDraft)
            XCTAssertFalse(current.flow.canPick); XCTAssertNil(current.flow.beginPicking())
            current.flow.stageCropped(c.source.picked); XCTAssertNil(current.flow.review)
            XCTAssertEqual(current.flow.activeAttempt, applied.presentation.flow.activeAttempt)
            controller.apply(current); XCTAssertNil(controller.presentation)
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(cold.draft), applied.exact); XCTAssertEqual(cold.draft.chapters[0].blocks?.count, 200)
            XCTAssertEqual(c.source.uploadCount, 1)
            let (session, identity) = try sessionAndIdentity(c)
            let entries = try ProjectStoryImageJournal(storage: c.storage).read(session: session, identity: identity).entries
            XCTAssertEqual(entries.count, 1); XCTAssertTrue(try XCTUnwrap(entries.first).applied)
            XCTAssertNil(controller.capture(chapterID: c.chapterID, insertingBefore: applied.anchor))
            guard case .ready(let saved) = ProjectEditLocalStore(storage: c.storage).load(session: session, identity: identity, baseline: c.baseline) else { return XCTFail() }
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(saved.draft), applied.exact)
        }
    }
    func test200WithoutMatchingReceiptAnd201BlocksCannotCreateNewInsertion() async throws {
        for count in [200, 201] {
            let c = try await context(count: count), images = ProjectStoryImagePresentation(editor: c.editor), audio = ProjectStoryAudioPresentation(editor: c.editor)
            let (session, identity) = try sessionAndIdentity(c), anchor = try XCTUnwrap(c.editor.draft.chapters[0].blocks?[99].id)
            for selected in [anchor, nil] as [String?] {
                XCTAssertNil(images.capture(chapterID: c.chapterID, insertingBefore: selected))
                XCTAssertNil(audio.captureInsertion(chapterID: c.chapterID, before: selected))
                XCTAssertThrowsError(try ProjectStoryMediaGap(draft: c.editor.draft, identity: identity, session: session, chapterID: c.chapterID, before: selected))
                XCTAssertThrowsError(try ProjectStoryImageTarget(draft: c.editor.draft, identity: identity, session: session, chapterID: c.chapterID, insertingBefore: selected))
            }
            XCTAssertEqual(c.editor.draft.chapters[0].blocks?.count, count); XCTAssertEqual(c.source.uploadCount, 0)
        }
    }
    func testCapacityReceiptDoesNotAuthorizeWrongAnchorMovedDuplicateOrReplacedPostimage() async throws {
        for mutation in 0..<6 {
            let applied = try await pendingAtCapacity(position: 99), c = applied.context
            applied.controller.close(applied.presentation)
            var anchor = applied.anchor
            switch mutation {
            case 0: anchor = c.editor.draft.chapters[0].blocks?[20].id
            case 1: c.editor.draft.chapters[0].blocks?.swapAt(98, 99)
            case 2: c.editor.draft.chapters[0].blocks?[20] = try XCTUnwrap(c.editor.draft.chapters[0].blocks?[100])
            case 3: c.editor.draft.chapters[0].blocks?[100].content = "replacement with same anchor ID"
            case 4: c.editor.draft.chapters[0].blocks?[99].content = "changed inserted image"
            default: c.editor.draft.chapters[0].blocks?.append(.init(kind: .text, content: "Invalid 201st block"))
            }
            let before = ProjectEditPendingMaterials.exactData(c.editor.draft), stored = c.storage.data
            XCTAssertNil(applied.controller.capture(chapterID: c.chapterID, insertingBefore: anchor))
            XCTAssertNil(applied.controller.presentation); XCTAssertEqual(c.storage.data, stored)
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.editor.draft), before); XCTAssertEqual(c.source.uploadCount, 1)
        }
    }
    func testCapturedRecoveryCannotReviveAfterLiveReplaceRevertOrDiscard() async throws {
        for discard in [false, true] {
            let applied = try await pendingAtCapacity(position: 99), c = applied.context
            applied.controller.close(applied.presentation)
            let opening = try XCTUnwrap(applied.controller.capture(chapterID: c.chapterID, insertingBefore: applied.anchor))
            if discard { c.editor.discard() }
            else {
                let old = c.editor.draft.chapters[0].blocks
                c.editor.draft.chapters[0].blocks?[100].content = "Temporary replacement"; c.editor.draft.chapters[0].blocks = old
            }
            let stored = c.storage.data; applied.controller.open(opening); XCTAssertNil(applied.controller.presentation)
            XCTAssertEqual(c.storage.data, stored); XCTAssertEqual(c.source.uploadCount, 1)
        }
    }
    func testRecoveryOpeningAndLoadRemainPinnedToExactUnappliedJournalEntry() async throws {
        let applied = try await pendingAtCapacity(position: 0), c = applied.context
        applied.controller.close(applied.presentation)
        let opening = try XCTUnwrap(applied.controller.capture(chapterID: c.chapterID, insertingBefore: applied.anchor))
        let (session, identity) = try sessionAndIdentity(c), journal = try XCTUnwrap(c.editor.coordinator.storyImageJournal)
        let pending = try journal.read(session: session, identity: identity), entry = try XCTUnwrap(opening.recoveryOnly)
        _ = try journal.markApplied(attemptID: entry.attemptID, expected: pending, session: session, identity: identity)
        applied.controller.open(opening); XCTAssertNil(applied.controller.presentation)
        XCTAssertNil(applied.controller.capture(chapterID: c.chapterID, insertingBefore: applied.anchor))
        let flow = ProjectStoryImageFlow(target: entry.target, session: session, identity: identity, source: c.source, journal: journal,
            recoveryOnly: entry, currentDraft: { c.editor.draft }, parentCurrent: { true })
        flow.load(); XCTAssertEqual(flow.state, .failed); XCTAssertNil(flow.receipt); XCTAssertFalse(flow.canApply)
        XCTAssertFalse(flow.canPick); flow.stageCropped(c.source.picked); XCTAssertNil(flow.review); XCTAssertEqual(c.source.uploadCount, 1)
        let originalDraft = ProjectStoryImageFlow(target: entry.target, session: session, identity: identity, source: c.source, journal: journal,
            recoveryOnly: entry, currentDraft: { c.baseline }, parentCurrent: { true })
        originalDraft.load(); XCTAssertTrue(originalDraft.matchesCapturedDraft)
        XCTAssertFalse(originalDraft.canPick); XCTAssertNil(originalDraft.beginPicking()); XCTAssertFalse(originalDraft.canApply)
        XCTAssertNil(originalDraft.draftForApply()); XCTAssertEqual(c.source.uploadCount, 1)
    }
    func testAmbiguousReceiptsForeignOwnerBucketAndUnavailableHostCannotRecover() async throws {
        let applied = try await pendingAtCapacity(position: 99), c = applied.context
        applied.controller.close(applied.presentation)
        XCTAssertNil(ProjectStoryImagePresentation(editor: c.editor, host: .unavailable).capture(chapterID: c.chapterID, insertingBefore: applied.anchor))
        let (session, identity) = try sessionAndIdentity(c)
        c.owner.session = try .init(accountID: 8, epoch: 2, storageNamespace: session.storageNamespace)
        XCTAssertNil(applied.controller.capture(chapterID: c.chapterID, insertingBefore: applied.anchor)); c.owner.session = session
        let storage = Storage(); storage.data = c.storage.data.filter { $0.key.hasPrefix("project-story-image.v1.") }
        let other = makeEditor(c.editor.draft, c.owner, storage, c.source); await other.load()
        XCTAssertNotEqual(other.coordinator.identity, identity)
        XCTAssertNil(ProjectStoryImagePresentation(editor: other).capture(chapterID: c.chapterID, insertingBefore: applied.anchor))
        let journal = try XCTUnwrap(c.editor.coordinator.storyImageJournal), receipt = try XCTUnwrap(applied.presentation.flow.receipt)
        let snapshot = try journal.read(session: session, identity: identity), duplicateID = UUID()
        let begun = try journal.begin(target: applied.presentation.flow.target, digest: String(repeating: "a", count: 64), expected: snapshot, session: session, identity: identity, id: duplicateID)
        let duplicate = try ProjectStoryUploadedImage.restore(attemptID: duplicateID, ownerKey: session.ownerKey, reference: receipt.reference)
        _ = try journal.record(duplicate, expected: begun, session: session, identity: identity)
        XCTAssertNil(applied.controller.capture(chapterID: c.chapterID, insertingBefore: applied.anchor)); XCTAssertEqual(c.source.uploadCount, 1)
    }
    func testNormalReplacementAt200RemainsAvailableButNewInsertionStaysBlocked() async throws {
        let applied = try await pendingAtCapacity(position: 99), c = applied.context
        applied.controller.close(applied.presentation)
        let imageID = applied.presentation.flow.target.resultingBlockID
        let replace = try XCTUnwrap(applied.controller.capture(chapterID: c.chapterID, replacing: imageID))
        XCTAssertNil(replace.recoveryOnly); XCTAssertEqual(replace.target.action, .replace(imageID))
        applied.controller.open(replace); let current = try XCTUnwrap(applied.controller.presentation); current.flow.load()
        XCTAssertTrue(current.flow.canPick); XCTAssertNil(current.flow.receipt)
        applied.controller.close(current)
        let unrelated = try XCTUnwrap(c.editor.draft.chapters[0].blocks?[20].id)
        XCTAssertNil(applied.controller.capture(chapterID: c.chapterID, insertingBefore: unrelated))
        XCTAssertNil(applied.controller.capture(chapterID: c.chapterID))
        XCTAssertEqual(c.editor.draft.chapters[0].blocks?.count, 200); XCTAssertEqual(c.source.uploadCount, 1)
    }
}
#endif

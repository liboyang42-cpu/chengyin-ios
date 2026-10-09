import XCTest
@testable import Questify

@MainActor final class ProjectNodeTemplateSelectionPresentationTests: XCTestCase {
    private final class Owner { var session: ProjectEditSession? = try? .init(accountID: 7, epoch: 1, storageNamespace: "node-template-host") }
    @MainActor private final class Source: ProjectStoryTemplateReading {
        var identity = UUID(), permitted = true
        let owner: Owner
        var id = 42, revision = "r1", reads = 0, lists = 0
        var hold = false, continuation: CheckedContinuation<ProjectStoryTemplateDraft, Error>?
        var held: ProjectStoryTemplateDraft?
        init(owner: Owner) { self.owner = owner }
        var raw: ProjectEditJSON { .object(["id": .number(Decimal(id)), "memberId": .number(7), "draftStatus": .number(0), "delFlag": .number(0),
            "title": .string("Selected game"), "validationMethod": .number(0), "revision": .string(revision), "answer": .string("private")]) }
        func isCurrent(session: ProjectEditSession) -> Bool { permitted && session == owner.session }
        func list(page: Int, session: ProjectEditSession) async throws -> ProjectStoryTemplatePage {
            lists += 1; return try .decode(.object(["rows": .array([raw]), "total": .number(1)]), accountID: session.accountID, page: page)
        }
        func detail(id: MemberPlayTemplateID, session: ProjectEditSession) async throws -> ProjectStoryTemplateDraft {
            reads += 1; let value = try ProjectStoryTemplateDraft.decode(raw, accountID: session.accountID, requestedID: id)
            if hold { hold = false; held = value; return try await withCheckedThrowingContinuation { continuation = $0 } }
            return value
        }
        func release() { let current = continuation; continuation = nil; if let held { current?.resume(returning: held) }; held = nil }
    }
    @MainActor private struct Context {
        let owner: Owner, source: Source, storage: ProjectEditMemoryStorage, editor: ProjectEditModel, controller: ProjectStoryTemplatePresentation
    }
    private func setup(selectedID: Int = 42) async throws -> Context {
        let owner = Owner(), storage = ProjectEditMemoryStorage(), source = Source(owner: owner); source.id = selectedID
        let draft = ProjectEditSyntheticFixtures.draft(), initial = ProjectEditSnapshot(draft: draft)
        let model = ProjectEditModel(coordinator: .init(initial: initial, service: ProjectEditSyntheticService(snapshot: initial),
            store: .init(storage: storage), storyTemplateSource: source, currentSession: { owner.session }))
        await model.load(); return .init(owner: owner, source: source, storage: storage, editor: model, controller: .init(editor: model))
    }
    private func open(_ c: Context) async throws -> ProjectStoryTemplatePresentation.Opening {
        let opening = try XCTUnwrap(c.controller.captureNode(chapterID: c.editor.draft.chapters[0].id, nodeID: c.editor.draft.chapters[0].nodes[0].id))
        let task = try XCTUnwrap(c.controller.open(opening)); await task.value; return opening
    }
    private func review(_ c: Context, _ opening: ProjectStoryTemplatePresentation.Opening) async throws -> ProjectStoryTemplatePresentation.Review {
        let row = try XCTUnwrap(c.controller.rows.first), task = try XCTUnwrap(c.controller.select(row, original: opening))
        await task.value; return try XCTUnwrap(c.controller.review)
    }
    func testRealSharedReaderTwiceVerifiesAndOnlyExplicitApplyUpdatesExistingNode() async throws {
        let c = try await setup(), original = try await open(c), before = ProjectEditPendingMaterials.exactData(c.editor.draft)
        guard case .nodeReference = original.target else { return XCTFail("must not fake story gap") }
        let selected = try await review(c, original); XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.editor.draft), before)
        let task = try XCTUnwrap(c.controller.apply(selected, original: original)); await task.value
        XCTAssertEqual(c.source.lists, 1); XCTAssertEqual(c.source.reads, 2); XCTAssertNil(c.controller.opening)
        XCTAssertEqual(c.editor.draft.chapters[0].nodes[0].templateID, 42); XCTAssertEqual(c.editor.draft.chapters[0].nodes.count, 1); XCTAssertNil(c.editor.draft.chapters[0].blocks)
    }
    func testNoOpAndCancelPreserveBytesStorageAndPreparedReview() async throws {
        let c = try await setup(selectedID: 41); c.editor.review()
        let prepared = try XCTUnwrap(c.editor.confirmation), before = ProjectEditPendingMaterials.exactData(c.editor.draft), saved = c.storage.data
        let old = try await open(c); c.controller.close(old)
        let original = try await open(c), selected = try await review(c, original)
        let task = try XCTUnwrap(c.controller.apply(selected, original: original)); await task.value
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.editor.draft), before); XCTAssertEqual(c.storage.data, saved); XCTAssertEqual(c.editor.confirmation?.id, prepared.id)
    }
    func testChangedPrivateSourceBetweenReadsRejectsReferenceAndLocalFailureKeepsOriginal() async throws {
        let c = try await setup(), original = try await open(c), selected = try await review(c, original)
        let before = ProjectEditPendingMaterials.exactData(c.editor.draft); c.source.revision = "r2"
        let task = try XCTUnwrap(c.controller.apply(selected, original: original)); await task.value
        XCTAssertEqual(c.controller.state, .changed); XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.editor.draft), before)
        c.controller.close(original); let next = try await open(c), current = try await review(c, next)
        c.storage.failWrites = true; let save = try XCTUnwrap(c.controller.apply(current, original: next)); await save.value
        XCTAssertEqual(c.controller.state, .saveFailed); XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.editor.draft), before)
    }
    func testHeldApplyCannotCrossCancelReorderReinsertIdentityOrSameByteABA() async throws {
        for action in ["cancel", "reorder", "reinsert", "account", "aba"] {
            let c = try await setup(); c.editor.draft.chapters[0].nodes.append(ProjectEditNode())
            let original = try await open(c), selected = try await review(c, original)
            c.source.hold = true; let task = try XCTUnwrap(c.controller.apply(selected, original: original))
            for _ in 0..<100 where c.source.continuation == nil { await Task.yield() }; XCTAssertNotNil(c.source.continuation)
            switch action {
            case "cancel": c.controller.close(original)
            case "reorder": c.editor.draft.chapters[0].nodes.reverse()
            case "reinsert": let node = c.editor.draft.chapters[0].nodes.removeFirst(); c.editor.draft.chapters[0].nodes.insert(node, at: 0)
            case "account": c.owner.session = try .init(accountID: 8, epoch: 2, storageNamespace: "node-template-host")
            default: let same = c.editor.draft; c.editor.draft = same
            }
            let before = ProjectEditPendingMaterials.exactData(c.editor.draft); c.source.release(); await task.value
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.editor.draft), before, action)
        }
    }
    func testSourceGenerationAndOldDismissalCannotAffectNewChooser() async throws {
        let c = try await setup(), old = try await open(c), binding = c.controller.binding(old)
        c.controller.close(old); let current = try await open(c); binding.wrappedValue = nil; c.controller.close(old)
        XCTAssertEqual(c.controller.opening?.id, current.id)
        c.source.identity = UUID(); XCTAssertFalse(c.controller.isCurrent(current))
        c.source.permitted = false; XCTAssertNil(c.controller.captureNode(chapterID: c.editor.draft.chapters[0].id, nodeID: c.editor.draft.chapters[0].nodes[0].id))
    }
}

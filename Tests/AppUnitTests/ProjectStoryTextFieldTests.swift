import XCTest
@testable import Questify

@MainActor final class ProjectStoryTextFieldTests: XCTestCase {
    private final class Owner { var session: ProjectEditSession? = try? .init(accountID: 7, epoch: 1, storageNamespace: "empty-story-text") }
    private func setup(_ text: String = "", scope: ProjectEditScope = .full) async throws -> (ProjectStoryTextController, Owner, ProjectEditMemoryStorage) {
        let owner = Owner(), storage = ProjectEditMemoryStorage(); var draft = ProjectEditSyntheticFixtures.draft()
        draft.chapters[0].id = "chapter"
        var block = ProjectEditBlock(kind: .text, content: text); block.id = "block"
        draft.chapters[0].blocks = [block]
        let initial = ProjectEditSnapshot(topicID: scope == .whitelist ? 101 : nil, scope: scope, draft: draft)
        let model = ProjectEditModel(coordinator: .init(initial: initial, service: ProjectEditSyntheticService(snapshot: initial), store: .init(storage: storage), currentSession: { owner.session }))
        await model.load()
        let controller = ProjectStoryTextController(model: model, chapterID: "chapter", blockID: "block")
        controller.appear(sceneActive: true); return (controller, owner, storage)
    }
    private func begin(_ c: ProjectStoryTextController) throws -> ProjectStoryTextController.Lifetime { c.begin(); return try XCTUnwrap(c.lifetime) }
    func testOpeningAndTypingToEmptyNeverDeleteUntilExplicitFinish() async throws {
        let (c, _, storage) = try await setup("text"), saved = storage.data
        let lifetime = try begin(c); c.edit("", in: lifetime)
        XCTAssertEqual(c.model.draft.chapters[0].blocks?.count, 1); XCTAssertEqual(c.text, "")
        c.synchronize(); XCTAssertEqual(c.lifetime, lifetime)
        let completion = try XCTUnwrap(c.completion), revision = c.model.draftMutationRevision
        XCTAssertTrue(c.finish(completion)); XCTAssertEqual(c.model.draft.chapters[0].blocks?.count, 0)
        XCTAssertEqual(c.model.draftMutationRevision, revision + 1); XCTAssertFalse(c.finish(completion)); XCTAssertEqual(storage.data, saved)
    }
    func testNonemptyFinishKeepsBytesRevisionAndStorage() async throws {
        for text in ["é", "e\u{301}", " \u{85} ", " \u{301}", "{KEY}"] {
            let (c, _, storage) = try await setup(text), before = ProjectEditPendingMaterials.exactData(c.model.draft), revision = c.model.draftMutationRevision, saved = storage.data
            _ = try begin(c); XCTAssertTrue(c.finish(try XCTUnwrap(c.completion)))
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.model.draft), before); XCTAssertEqual(c.model.draftMutationRevision, revision); XCTAssertEqual(storage.data, saved)
        }
    }
    func testUnclassifiedBlurCancelNavigationAndBackgroundRetainEmpty() async throws {
        for mode in ["blur", "cancel", "navigation", "background"] {
            let (c, _, _) = try await setup("\u{FEFF} "), lifetime = try begin(c), completion = try XCTUnwrap(c.completion), before = ProjectEditPendingMaterials.exactData(c.model.draft)
            switch mode {
            case "navigation": c.disappear()
            case "background": c.setSceneActive(false)
            default: c.retire(lifetime)
            }
            XCTAssertFalse(c.finish(completion)); XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.model.draft), before)
        }
    }
    func testInactiveOrDisappearedViewCannotBeginFromLateFocusCallback() async throws {
        let (c, _, _) = try await setup(); c.disappear(); c.begin(); XCTAssertNil(c.lifetime)
        c.appear(sceneActive: false); c.begin(); XCTAssertNil(c.lifetime)
        c.setSceneActive(true); _ = try begin(c)
    }
    func testStaleCompletionCannotDeleteNewTypingEvenInSameFocusLifetime() async throws {
        let (c, _, _) = try await setup(), lifetime = try begin(c), stale = try XCTUnwrap(c.completion)
        c.edit("new", in: lifetime); c.edit("", in: lifetime)
        let before = ProjectEditPendingMaterials.exactData(c.model.draft); XCTAssertFalse(c.finish(stale)); XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.model.draft), before)
        XCTAssertTrue(c.finish(try XCTUnwrap(c.completion)))
    }
    func testOldBindingCompletionAndRetirementCannotAffectNewFocusLifetime() async throws {
        let (c, _, _) = try await setup(), old = try begin(c), binding = c.binding(old), completion = try XCTUnwrap(c.completion)
        c.retire(old); let current = try begin(c)
        binding.wrappedValue = "old callback"; c.retire(old)
        XCTAssertEqual(c.lifetime, current); XCTAssertEqual(c.text, ""); XCTAssertFalse(c.finish(completion))
    }
    func testSameByteABARejectsQueuedEditAndFinishBeforeObserver() async throws {
        let (c, _, _) = try await setup(), lifetime = try begin(c), completion = try XCTUnwrap(c.completion), same = c.model.draft
        c.model.draft = same; let before = ProjectEditPendingMaterials.exactData(c.model.draft)
        XCTAssertFalse(c.finish(completion)); c.edit("late", in: lifetime)
        XCTAssertNil(c.lifetime); XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.model.draft), before)
    }
    func testOtherDraftChangesReorderAndDeletionRetireWithoutDeletion() async throws {
        for kind in ["other", "reorder", "delete", "rich"] {
            let (c, _, _) = try await setup(), old = try begin(c), completion = try XCTUnwrap(c.completion)
            switch kind {
            case "reorder": c.model.draft.chapters[0].blocks?.insert(.init(kind: .text, content: "neighbor"), at: 0)
            case "delete": c.model.draft.chapters[0].blocks = []
            case "rich": c.model.draft.chapters[0].blocks?[0].sourceFields = ["when": .object([:])]
            default: c.model.draft.name += "!"
            }
            let before = ProjectEditPendingMaterials.exactData(c.model.draft); c.edit("late", in: old); c.synchronize()
            XCTAssertNil(c.lifetime); XCTAssertFalse(c.finish(completion)); XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.model.draft), before)
        }
    }
    func testWhitelistSessionEpochRestoreAndRevocationFailClosed() async throws {
        let (locked, _, _) = try await setup(scope: .whitelist); locked.begin(); XCTAssertNil(locked.lifetime)
        for kind in ["account", "epoch", "restore", "revoke"] {
            let (c, owner, _) = try await setup(), lifetime = try begin(c), completion = try XCTUnwrap(c.completion)
            switch kind {
            case "restore": c.model.saveLocal(); await c.model.load(force: true); c.model.restore()
            case "revoke": c.model.coordinator.beginEditorVisit(UUID())
            default: owner.session = try .init(accountID: kind == "account" ? 8 : 7, epoch: 2, storageNamespace: "empty-story-text")
            }
            let before = ProjectEditPendingMaterials.exactData(c.model.draft); XCTAssertFalse(c.finish(completion)); c.edit("late", in: lifetime)
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.model.draft), before)
        }
    }
    func testCrossControllerCompletionCannotDeleteSameTarget() async throws {
        let (c, _, _) = try await setup(), other = ProjectStoryTextController(model: c.model, chapterID: "chapter", blockID: "block")
        other.appear(sceneActive: true); _ = try begin(c); _ = try begin(other)
        XCTAssertFalse(c.finish(try XCTUnwrap(other.completion))); XCTAssertEqual(c.model.draft.chapters[0].blocks?.count, 1)
    }
    func testCanonicalEquivalentTypingIsNotSwallowedAndOwnEchoDoesNotRetire() async throws {
        let (c, _, _) = try await setup("é"), lifetime = try begin(c)
        c.edit("e\u{301}", in: lifetime); c.synchronize()
        XCTAssertEqual(c.lifetime, lifetime); XCTAssertEqual(Data(c.text.utf8), Data("e\u{301}".utf8))
        XCTAssertEqual(Data(c.model.draft.chapters[0].blocks![0].content.utf8), Data(c.text.utf8))
    }
    func testExplicitRemovalIsWorkingDraftAndExistingSaveFailureDoesNotInventSuccess() async throws {
        let (c, _, storage) = try await setup(), saved = storage.data; storage.failWrites = true; _ = try begin(c)
        XCTAssertTrue(c.finish(try XCTUnwrap(c.completion))); XCTAssertEqual(storage.data, saved)
        c.model.saveLocal(); XCTAssertEqual(storage.data, saved); XCTAssertEqual(c.model.draft.chapters[0].blocks?.count, 0)
    }
}

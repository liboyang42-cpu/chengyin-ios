import XCTest
@testable import Questify

@MainActor final class ProjectStoryTextInsertionButtonTests: XCTestCase {
    private final class Owner { var session: ProjectEditSession? = try? .init(accountID: 7, epoch: 1, storageNamespace: "insert-story-text") }
    private func setup(scope: ProjectEditScope = .full) async throws -> (ProjectEditModel, Owner, ProjectEditMemoryStorage) {
        let owner = Owner(), storage = ProjectEditMemoryStorage(); var draft = ProjectEditSyntheticFixtures.draft()
        draft.chapters[0].id = "chapter"
        var first = ProjectEditBlock(kind: .text, content: "before"), anchor = ProjectEditBlock(kind: .image, url: "raw-asset")
        first.id = "first"; anchor.id = "anchor"; draft.chapters[0].blocks = [first, anchor]
        let initial = ProjectEditSnapshot(topicID: scope == .whitelist ? 101 : nil, scope: scope, draft: draft)
        let model = ProjectEditModel(coordinator: .init(initial: initial, service: ProjectEditSyntheticService(snapshot: initial), store: .init(storage: storage), currentSession: { owner.session }))
        await model.load(); return (model, owner, storage)
    }
    private func action(_ model: ProjectEditModel) throws -> ProjectStoryTextInsertionAction {
        try XCTUnwrap(.init(model: model, chapterID: "chapter", beforeBlockID: "anchor"))
    }
    func testExplicitClickAddsOneEmptyParagraphWithoutMediaConfiguration() async throws {
        let (model, _, storage) = try await setup(), original = model.draft, captured = try action(model), saved = storage.data, revision = model.draftMutationRevision
        XCTAssertNil(model.storyImagePicker); XCTAssertNil(model.storyAudioPicker)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), ProjectEditPendingMaterials.exactData(original))
        XCTAssertTrue(captured.insert(makeID: { "new" })); XCTAssertFalse(captured.insert(makeID: { "repeat" }))
        XCTAssertEqual(model.draft.chapters[0].blocks?.map(\.id), ["first", "new", "anchor"])
        XCTAssertEqual(model.draft.chapters[0].blocks?[1].content, ""); XCTAssertEqual(model.draftMutationRevision, revision + 1); XCTAssertEqual(storage.data, saved)
    }
    func testDefaultIDIsFreshNativeUUID() async throws {
        let (model, _, _) = try await setup(); XCTAssertTrue(try action(model).insert())
        let key = try XCTUnwrap(model.draft.chapters[0].blocks?[1].id); XCTAssertNotNil(UUID(uuidString: key)); XCTAssertNotEqual(key, "anchor")
    }
    func testWhitelistAndInvalidTargetCannotRenderEnabledAction() async throws {
        let (locked, _, _) = try await setup(scope: .whitelist)
        XCTAssertNil(ProjectStoryTextInsertionAction(model: locked, chapterID: "chapter", beforeBlockID: "anchor"))
        let (model, _, _) = try await setup()
        XCTAssertNil(ProjectStoryTextInsertionAction(model: model, chapterID: "other", beforeBlockID: "anchor"))
        XCTAssertNil(ProjectStoryTextInsertionAction(model: model, chapterID: "chapter", beforeBlockID: "missing"))
    }
    func testSameByteABARejectsOldMenuBeforeObserverAndBeforeGeneratingID() async throws {
        let (model, _, _) = try await setup(), captured = try action(model), same = model.draft; model.draft = same
        var calls = 0; XCTAssertFalse(captured.insert(makeID: { calls += 1; return "new" })); XCTAssertEqual(calls, 0)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), ProjectEditPendingMaterials.exactData(same))
    }
    func testChangedReorderedDeletedAndCapacityChangedAnchorsReject() async throws {
        for kind in ["reorder", "delete", "other", "limit"] {
            let (model, _, _) = try await setup(), captured = try action(model)
            switch kind {
            case "reorder": model.draft.chapters[0].blocks?.swapAt(0, 1)
            case "delete": model.draft.chapters[0].blocks?.remove(at: 1)
            case "limit": for index in 0..<198 { var block = ProjectEditBlock(kind: .text); block.id = "extra-\(index)"; model.draft.chapters[0].blocks?.append(block) }
            default: model.draft.name += "!"
            }
            let before = ProjectEditPendingMaterials.exactData(model.draft); XCTAssertFalse(captured.insert()); XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before)
        }
    }
    func testSessionEpochRestoreAndVisitRevocationRejectQueuedClick() async throws {
        for kind in ["account", "epoch", "restore", "revoke"] {
            let (model, owner, _) = try await setup(), captured = try action(model)
            switch kind {
            case "restore": model.saveLocal(); await model.load(force: true); model.restore()
            case "revoke": model.coordinator.beginEditorVisit(UUID())
            default: owner.session = try .init(accountID: kind == "account" ? 8 : 7, epoch: 2, storageNamespace: "insert-story-text")
            }
            let before = ProjectEditPendingMaterials.exactData(model.draft); XCTAssertFalse(captured.insert()); XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before)
        }
    }
    func testGeneratedCollisionFailsWithoutMutationOrRevisionAdvance() async throws {
        let (model, _, _) = try await setup(), captured = try action(model), before = ProjectEditPendingMaterials.exactData(model.draft), revision = model.draftMutationRevision
        XCTAssertFalse(captured.insert(makeID: { "anchor" })); XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before); XCTAssertEqual(model.draftMutationRevision, revision)
    }
    func testDraftActionCannotSwitchToAnotherEditorWithSameBytes() async throws {
        let (first, _, _) = try await setup(), (second, _, _) = try await setup(), captured = try action(first), secondBytes = ProjectEditPendingMaterials.exactData(second.draft)
        first.coordinator.beginEditorVisit(UUID()); XCTAssertFalse(captured.insert()); XCTAssertEqual(ProjectEditPendingMaterials.exactData(second.draft), secondBytes)
    }
    func testReentrantIDFactoryCannotWriteAfterOwnerRetirement() async throws {
        let (model, _, _) = try await setup(), captured = try action(model), before = ProjectEditPendingMaterials.exactData(model.draft)
        XCTAssertFalse(captured.insert(makeID: { model.coordinator.beginEditorVisit(UUID()); return "new" }))
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before)
    }
    func testWorkingDraftInsertionUsesExistingSaveFailurePath() async throws {
        let (model, _, storage) = try await setup(), saved = storage.data; storage.failWrites = true
        XCTAssertTrue(try action(model).insert()); XCTAssertEqual(storage.data, saved)
        model.saveLocal(); XCTAssertEqual(storage.data, saved); XCTAssertEqual(model.draft.chapters[0].blocks?.count, 3)
    }
}

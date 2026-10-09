import XCTest
@testable import Questify

@MainActor final class ProjectRichStoryInsertionPresentationTests: XCTestCase {
    private final class Owner { var session: ProjectEditSession? = try? .init(accountID: 7, epoch: 1, storageNamespace: "rich-insertion") }
    private func setup(scope: ProjectEditScope = .full) async throws -> (ProjectEditModel, Owner, ProjectEditMemoryStorage) {
        let owner = Owner(), storage = ProjectEditMemoryStorage(); var draft = ProjectEditSyntheticFixtures.draft()
        draft.chapters[0].id = "chapter"; var block = ProjectEditBlock(kind: .text, content: "anchor"); block.id = "anchor"; block.sourceFields = ["future": .string(" retain ")]; draft.chapters[0].blocks = [block]
        let initial = ProjectEditSnapshot(topicID: scope == .whitelist ? 101 : nil, scope: scope, draft: draft)
        let model = ProjectEditModel(coordinator: .init(initial: initial, service: ProjectEditSyntheticService(snapshot: initial), store: .init(storage: storage), currentSession: { owner.session }))
        await model.load(); return (model, owner, storage)
    }
    private func action(_ model: ProjectEditModel) -> ProjectRichStoryInsertionAction? { .init(model: model, chapterID: "chapter", beforeBlockID: "anchor") }
    func testEveryKindInsertsExactDefaultOnceBeforeAnchorWithoutImmediateSave() async throws {
        for kind in ProjectEditRichStoryContract.richKinds {
            let (model, _, storage) = try await setup(), captured = try XCTUnwrap(action(model)), saved = storage.data, revision = model.draftMutationRevision
            var expected = model.draft, added = ProjectEditRichStoryContract.defaultBlock(kind); added.id = "new"; expected.chapters[0].blocks!.insert(added, at: 0)
            XCTAssertTrue(captured.insert(kind, makeID: { "new" })); XCTAssertFalse(captured.insert(kind, makeID: { "another" }))
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), ProjectEditPendingMaterials.exactData(expected)); XCTAssertEqual(model.draftMutationRevision, revision + 1); XCTAssertEqual(storage.data, saved)
            model.saveLocal(); XCTAssertFalse(storage.data.isEmpty)
        }
    }
    func testWhitelistAndOwnerEpochSignoutVisitLossReject() async throws {
        let (locked, _, _) = try await setup(scope: .whitelist); XCTAssertNil(action(locked))
        for kind in ["owner", "epoch", "signout", "visit"] {
            let (model, owner, _) = try await setup(), captured = try XCTUnwrap(action(model))
            switch kind { case "signout": owner.session = nil; case "visit": model.coordinator.beginEditorVisit(UUID()); default: owner.session = try .init(accountID: kind == "owner" ? 8 : 7, epoch: 2, storageNamespace: "rich-insertion") }
            let before = ProjectEditPendingMaterials.exactData(model.draft); XCTAssertFalse(captured.insert(.dream)); XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before)
        }
    }
    func testSameByteABAAndAnchorDeletionInvalidateRenderedMenu() async throws {
        for aba in [false, true] {
            let (model, _, _) = try await setup(), captured = try XCTUnwrap(action(model))
            if aba { let same = model.draft; model.draft = same } else { model.draft.chapters[0].blocks = [] }
            let before = ProjectEditPendingMaterials.exactData(model.draft); XCTAssertFalse(captured.insert(.voice)); XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before)
        }
    }
    func testRejectedKindAndDuplicateGeneratedIDMakeNoDraftChange() async throws {
        let (model, _, _) = try await setup(), captured = try XCTUnwrap(action(model)), before = ProjectEditPendingMaterials.exactData(model.draft)
        XCTAssertFalse(captured.insert(.node)); XCTAssertFalse(captured.insert(.dream, makeID: { "anchor" })); XCTAssertFalse(captured.insert(.dream, makeID: { "" }))
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before)
    }
    func testIDFactoryCannotRaceOwnershipOrSameByteDraftRevision() async throws {
        for ownerLoss in [false, true] {
            let (model, owner, _) = try await setup(), captured = try XCTUnwrap(action(model)), before = ProjectEditPendingMaterials.exactData(model.draft)
            XCTAssertFalse(captured.insert(.mood, makeID: { if ownerLoss { owner.session = nil } else { let same = model.draft; model.draft = same }; return "new" }))
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before)
        }
    }
}

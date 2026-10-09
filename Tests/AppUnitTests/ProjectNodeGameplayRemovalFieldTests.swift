import XCTest
@testable import Questify

@MainActor final class ProjectNodeGameplayRemovalFieldTests: XCTestCase {
    private final class Owner { var session: ProjectEditSession? = try? .init(accountID: 7, epoch: 1, storageNamespace: "gameplay-removal") }
    private func setup() async throws -> (ProjectNodeGameplayRemovalController, Owner, ProjectEditMemoryStorage) {
        let owner = Owner(), storage = ProjectEditMemoryStorage(), draft = ProjectEditSyntheticFixtures.draft(), initial = ProjectEditSnapshot(draft: draft)
        let model = ProjectEditModel(coordinator: .init(initial: initial, service: ProjectEditSyntheticService(snapshot: initial),
            store: .init(storage: storage), currentSession: { owner.session }))
        await model.load(); return (.init(model: model, chapterID: draft.chapters[0].id, nodeID: draft.chapters[0].nodes[0].id), owner, storage)
    }
    private func open(_ controller: ProjectNodeGameplayRemovalController) throws -> ProjectNodeGameplayRemovalController.Confirmation {
        controller.open(); return try XCTUnwrap(controller.confirmation)
    }
    func testCancelPreservesDraftReviewAndStorageThenExplicitClearPersistsLocalOnly() async throws {
        let (controller, _, storage) = try await setup(), model = controller.model
        model.review(); let review = try XCTUnwrap(model.confirmation), before = ProjectEditPendingMaterials.exactData(model.draft), saved = storage.data
        let first = try open(controller); controller.close(first)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before); XCTAssertEqual(model.confirmation?.id, review.id); XCTAssertEqual(storage.data, saved)
        let next = try open(controller); controller.clear(next)
        XCTAssertNil(model.draft.chapters[0].nodes[0].templateID); XCTAssertNil(controller.confirmation)
        XCTAssertFalse(controller.available); XCTAssertNotEqual(storage.data, saved)
    }
    func testSaveFailureKeepsOriginalNodeAndDoesNotAutomaticallyRetry() async throws {
        let (controller, _, storage) = try await setup(), model = controller.model, original = try open(controller)
        let before = ProjectEditPendingMaterials.exactData(model.draft); storage.failWrites = true
        controller.clear(original); XCTAssertTrue(controller.saveUnconfirmed)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before); XCTAssertFalse(controller.available)
        storage.failWrites = false; controller.clear(original); controller.open()
        XCTAssertNil(controller.confirmation); XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before)
    }
    func testReorderDeleteReinsertAndSameByteABARejectOldTarget() async throws {
        for action in ["reorder", "reinsert", "delete", "aba"] {
            let (controller, _, storage) = try await setup(), model = controller.model
            model.draft.chapters[0].nodes.append(ProjectEditNode()); let original = try open(controller)
            let node = model.draft.chapters[0].nodes[0]
            switch action {
            case "reorder": model.draft.chapters[0].nodes.reverse()
            case "reinsert": model.draft.chapters[0].nodes.removeFirst(); model.draft.chapters[0].nodes.insert(node, at: 0)
            case "delete": model.draft.chapters[0].nodes.removeFirst()
            default: let same = model.draft; model.draft = same
            }
            let before = ProjectEditPendingMaterials.exactData(model.draft), saved = storage.data
            controller.clear(original); XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before, action); XCTAssertEqual(storage.data, saved)
        }
    }
    func testAccountEpochRestoreAndRetirementRejectOldConfirmation() async throws {
        for action in ["account", "epoch", "restore", "retire"] {
            let (controller, owner, storage) = try await setup(), model = controller.model, original = try open(controller)
            if action == "restore" { model.saveLocal(); await model.load(force: true); model.restore() }
            else if action == "retire" { controller.retire() }
            else { owner.session = try .init(accountID: action == "account" ? 8 : 7, epoch: 2, storageNamespace: "gameplay-removal") }
            let before = ProjectEditPendingMaterials.exactData(model.draft), saved = storage.data
            controller.clear(original); XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before); XCTAssertEqual(storage.data, saved)
        }
    }
    func testOldDismissalCannotCloseNewConfirmation() async throws {
        let (controller, _, _) = try await setup(), old = try open(controller), binding = controller.binding(old)
        controller.close(old); let current = try open(controller); binding.wrappedValue = false; controller.close(old)
        XCTAssertEqual(controller.confirmation?.id, current.id)
    }
}

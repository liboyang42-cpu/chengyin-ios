import XCTest
@testable import Questify

@MainActor final class ProjectNodePhotoRemovalViewTests: XCTestCase {
    private final class Owner { var session: ProjectEditSession? = try? .init(accountID: 7, epoch: 1, storageNamespace: "node-photos") }
    private func setup(raw: String = "a,b,a", scope: ProjectEditScope = .full) async throws -> (ProjectNodePhotoRemovalController, Owner, ProjectEditMemoryStorage) {
        let owner = Owner(), storage = ProjectEditMemoryStorage(); var draft = ProjectEditSyntheticFixtures.draft()
        draft.chapters[0].id = "chapter"; draft.chapters[0].nodes[0].id = "node"; draft.chapters[0].nodes[0].imgUrl = raw
        let initial = ProjectEditSnapshot(topicID: scope == .whitelist ? 101 : nil, scope: scope, draft: draft)
        let model = ProjectEditModel(coordinator: .init(initial: initial, service: ProjectEditSyntheticService(snapshot: initial),
            store: .init(storage: storage), currentSession: { owner.session }))
        await model.load(); return (.init(model: model, chapterID: "chapter", nodeID: "node"), owner, storage)
    }
    private func open(_ controller: ProjectNodePhotoRemovalController, slot: Int = 0) throws -> ProjectNodePhotoRemovalController.Confirmation {
        let captured = try XCTUnwrap(controller.capture(controller.snapshot)); controller.open(slot: slot, captured: captured)
        return try XCTUnwrap(controller.confirmation)
    }
    func testOpenCancelPreserveExactDraftRevisionAndStorage() async throws {
        let (controller, _, storage) = try await setup(raw: "fixture://é,fixture://e\u{301}"), model = controller.model
        let before = ProjectEditPendingMaterials.exactData(model.draft), revision = model.draftMutationRevision, saved = storage.data
        let original = try open(controller); controller.close(original)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before); XCTAssertEqual(model.draftMutationRevision, revision)
        XCTAssertEqual(storage.data, saved); XCTAssertFalse(controller.apply(original))
    }
    func testRemoveExactDuplicateSlotAppliesOnceAndUsesExistingSave() async throws {
        let (controller, _, storage) = try await setup(), model = controller.model, original = try open(controller, slot: 2)
        let revision = model.draftMutationRevision, initialStorage = storage.data
        XCTAssertTrue(controller.apply(original)); XCTAssertEqual(model.draft.chapters[0].nodes[0].imgUrl, "a,b")
        XCTAssertEqual(model.draftMutationRevision, revision + 1); XCTAssertEqual(storage.data, initialStorage)
        model.saveLocal(); XCTAssertFalse(storage.data.isEmpty)
        let saved = storage.data; XCTAssertFalse(controller.apply(original)); XCTAssertEqual(storage.data, saved)
        XCTAssertNil(controller.confirmation)
    }
    func testCombiningMarkPrefixedReferenceSurvivesRemovalOfPreviousSlot() async throws {
        for suffix in ["\u{301}b", "\u{FE0F}b"] {
            let (controller, _, _) = try await setup(raw: "a," + suffix + ",c"), original = try open(controller, slot: 0)
            XCTAssertEqual(original.capture.snapshot.photos.count, 3); XCTAssertTrue(controller.apply(original))
            XCTAssertEqual(Array(controller.model.draft.chapters[0].nodes[0].imgUrl.utf8), Array((suffix + ",c").utf8))
        }
    }
    func testLastPhotoRemovalSurvivesExistingLocalRestore() async throws {
        let (controller, _, _) = try await setup(raw: "fixture://only"), model = controller.model, original = try open(controller)
        XCTAssertTrue(controller.apply(original)); XCTAssertEqual(model.draft.chapters[0].nodes[0].imgUrl, "")
        model.saveLocal(); await model.load(force: true); model.restore(); XCTAssertEqual(model.draft.chapters[0].nodes[0].imgUrl, "")
    }
    func testApplyDoesNotClaimImmediatePersistenceAndKeepsExistingSaveBehavior() async throws {
        let (controller, _, storage) = try await setup(), model = controller.model, original = try open(controller)
        let revision = model.draftMutationRevision, saved = storage.data
        storage.failWrites = true
        XCTAssertTrue(controller.apply(original)); XCTAssertNil(controller.confirmation)
        XCTAssertEqual(model.draft.chapters[0].nodes[0].imgUrl, "b,a"); XCTAssertEqual(model.draftMutationRevision, revision + 1)
        XCTAssertEqual(storage.data, saved)
        // The existing Save local path reports its own failure. This feature does
        // not claim rollback or atomicity across the general store's two writes.
        model.saveLocal(); XCTAssertEqual(storage.data, saved); XCTAssertEqual(model.draft.chapters[0].nodes[0].imgUrl, "b,a")
        storage.failWrites = false; model.saveLocal(); XCTAssertFalse(storage.data.isEmpty)
    }
    func testStaleRenderedSlotAndSameByteABAEventCannotOpenDialog() async throws {
        for changed in [false, true] {
            let (controller, _, _) = try await setup(), model = controller.model
            let capture = try XCTUnwrap(controller.capture(controller.snapshot))
            if changed { model.draft.chapters[0].nodes[0].imgUrl = "b,a,a" } else { let same = model.draft; model.draft = same }
            controller.open(slot: 0, captured: capture); XCTAssertNil(controller.confirmation)
        }
    }
    func testPhotoChangeDeletionReorderAndSameByteABARejectOpenConfirmation() async throws {
        for action in ["photos", "delete", "reorder", "aba"] {
            let (controller, _, _) = try await setup(), model = controller.model, original = try open(controller)
            switch action {
            case "photos": model.draft.chapters[0].nodes[0].imgUrl = "b,a,a"
            case "delete": model.draft.chapters[0].nodes = []
            case "reorder": var other = ProjectEditNode(); other.id = "second"; model.draft.chapters[0].nodes.insert(other, at: 0)
            default: let same = model.draft; model.draft = same
            }
            let before = ProjectEditPendingMaterials.exactData(model.draft)
            XCTAssertFalse(controller.apply(original)); XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before)
        }
    }
    func testAccountEpochRestoreAndRevokedEditorAuthorityRejectApply() async throws {
        let (locked, _, _) = try await setup(scope: .whitelist); XCTAssertNil(locked.capture(locked.snapshot))
        for action in ["account", "epoch", "restore", "revoke"] {
            let (controller, owner, _) = try await setup(), model = controller.model, original = try open(controller)
            switch action {
            case "restore": model.saveLocal(); await model.load(force: true); model.restore()
            case "revoke": model.coordinator.beginEditorVisit(UUID())
            default: owner.session = try .init(accountID: action == "account" ? 8 : 7, epoch: 2, storageNamespace: "node-photos")
            }
            let before = ProjectEditPendingMaterials.exactData(model.draft)
            XCTAssertFalse(controller.apply(original)); XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before)
        }
    }
    func testUnknownCSVWrongNodeCaptureAndEmptyListCannotOpenRemoval() async throws {
        let (unknown, _, _) = try await setup(raw: "a,,b"); XCTAssertNil(unknown.capture(unknown.snapshot))
        let (empty, _, _) = try await setup(raw: ""), capture = try XCTUnwrap(empty.capture(empty.snapshot))
        empty.open(slot: 0, captured: capture); XCTAssertNil(empty.confirmation)
        let (controller, _, _) = try await setup(), model = controller.model
        var other = ProjectEditNode(); other.id = "second"; other.imgUrl = "other"; model.draft.chapters[0].nodes.append(other)
        let wrong = ProjectNodePhotoRemoval(draft: model.draft, chapterID: "chapter", nodeID: "second")
        XCTAssertNil(controller.capture(wrong))
    }
    func testOldDismissalAndNavigationRetirementCannotAffectNewConfirmation() async throws {
        let (controller, _, _) = try await setup(), old = try open(controller), binding = controller.binding(old)
        controller.close(old); let next = try open(controller); binding.wrappedValue = false; controller.close(old)
        XCTAssertEqual(controller.confirmation?.id, next.id)
        controller.retire(); let before = ProjectEditPendingMaterials.exactData(controller.model.draft)
        XCTAssertFalse(controller.apply(next)); XCTAssertEqual(ProjectEditPendingMaterials.exactData(controller.model.draft), before)
    }
}

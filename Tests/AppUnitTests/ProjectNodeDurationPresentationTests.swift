import XCTest
@testable import Questify

@MainActor final class ProjectNodeDurationPresentationTests: XCTestCase {
    private final class Owner { var session: ProjectEditSession? = try? .init(accountID: 7, epoch: 1, storageNamespace: "node-duration") }
    private func setup(scope: ProjectEditScope = .full) async throws -> (ProjectNodeDurationController, Owner, ProjectEditMemoryStorage) {
        let owner = Owner(), storage = ProjectEditMemoryStorage(); var draft = ProjectEditSyntheticFixtures.draft()
        draft.chapters[0].id = "chapter"; draft.chapters[0].nodes[0].id = "node"; draft.chapters[0].nodes[0].nodeTime = 30
        let initial = ProjectEditSnapshot(topicID: scope == .whitelist ? 101 : nil, scope: scope, draft: draft)
        let model = ProjectEditModel(coordinator: .init(initial: initial, service: ProjectEditSyntheticService(snapshot: initial), store: .init(storage: storage), currentSession: { owner.session }))
        await model.load(); return (.init(model: model, chapterID: "chapter", nodeID: "node"), owner, storage)
    }
    private func open(_ controller: ProjectNodeDurationController) throws -> ProjectNodeDurationController.Opening {
        controller.open(try XCTUnwrap(controller.capture())); return try XCTUnwrap(controller.opening)
    }
    func testOpenEditAndCancelDoNotMutateDraftOrStorage() async throws {
        let (c, _, storage) = try await setup(), before = ProjectEditPendingMaterials.exactData(c.model.draft), saved = storage.data, revision = c.model.draftMutationRevision
        let original = try open(c); c.edit("90", in: original); c.close(original)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.model.draft), before); XCTAssertEqual(storage.data, saved); XCTAssertEqual(c.model.draftMutationRevision, revision)
        XCTAssertFalse(c.apply(original))
    }
    func testSameValueAndInvalidTextCannotApplyOrMutate() async throws {
        let (c, _, _) = try await setup(), original = try open(c), before = ProjectEditPendingMaterials.exactData(c.model.draft)
        for text in ["30", "00030", "", "-1", "2147483648", "1.5"] {
            c.edit(text, in: original); XCTAssertFalse(c.canApply(original)); XCTAssertFalse(c.apply(original))
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.model.draft), before)
        }
    }
    func testExplicitApplyChangesOnlyDurationOnceThenExistingSavePersists() async throws {
        let (c, _, storage) = try await setup(), original = try open(c), saved = storage.data
        var expected = c.model.draft; expected.chapters[0].nodes[0].nodeTime = 90
        c.edit("90", in: original); XCTAssertTrue(c.apply(original)); XCTAssertFalse(c.apply(original))
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.model.draft), ProjectEditPendingMaterials.exactData(expected)); XCTAssertEqual(storage.data, saved)
        c.model.saveLocal(); XCTAssertFalse(storage.data.isEmpty)
    }
    func testWhitelistAccountEpochSignoutAndVisitInvalidation() async throws {
        let (locked, _, _) = try await setup(scope: .whitelist); XCTAssertNil(locked.capture())
        for kind in ["owner", "epoch", "signout", "visit", "restore"] {
            let (c, owner, _) = try await setup(), original = try open(c); c.edit("90", in: original)
            switch kind {
            case "signout": owner.session = nil
            case "visit": c.model.coordinator.beginEditorVisit(UUID())
            case "restore": c.model.saveLocal(); await c.model.load(force: true); c.model.restore()
            default: owner.session = try .init(accountID: kind == "owner" ? 8 : 7, epoch: 2, storageNamespace: "node-duration")
            }
            let before = ProjectEditPendingMaterials.exactData(c.model.draft); XCTAssertFalse(c.apply(original)); XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.model.draft), before)
        }
    }
    func testSameByteABAAndUnrelatedEditRejectStagedApply() async throws {
        for aba in [false, true] {
            let (c, _, _) = try await setup(), original = try open(c); c.edit("90", in: original)
            if aba { let same = c.model.draft; c.model.draft = same } else { c.model.draft.name += "!" }
            let before = ProjectEditPendingMaterials.exactData(c.model.draft); XCTAssertFalse(c.apply(original)); XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.model.draft), before)
        }
    }
    func testOldDismissalCannotCloseNewOpeningAndRetiredActionsFail() async throws {
        let (c, _, _) = try await setup(), old = try open(c), binding = c.binding(old)
        c.close(old); let current = try open(c); binding.wrappedValue = nil; c.edit("90", in: old)
        XCTAssertEqual(c.opening?.id, current.id); XCTAssertEqual(c.text, "30")
        c.edit("90", in: current); c.retire(); XCTAssertFalse(c.apply(current))
    }
    func testImportedInvalidDurationNeedsExplicitValidReplacement() async throws {
        let (c, _, _) = try await setup(); c.model.draft.chapters[0].nodes[0].nodeTime = Int.max
        let before = ProjectEditPendingMaterials.exactData(c.model.draft), original = try open(c)
        XCTAssertEqual(c.text, String(Int.max)); XCTAssertFalse(c.canApply(original)); XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.model.draft), before)
        c.edit("0", in: original); XCTAssertTrue(c.apply(original)); XCTAssertEqual(c.model.draft.chapters[0].nodes[0].nodeTime, 0)
    }
    func testStaleRenderedOpenAndForeignControllerCaptureRejected() async throws {
        let (c, _, _) = try await setup(), capture = try XCTUnwrap(c.capture())
        let other = ProjectNodeDurationController(model: c.model, chapterID: "chapter", nodeID: "node")
        other.open(capture); XCTAssertNil(other.opening)
        c.retire(); c.open(capture); XCTAssertNil(c.opening)
    }
}

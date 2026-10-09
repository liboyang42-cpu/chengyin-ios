import XCTest
@testable import Questify

@MainActor final class ProjectStoryVariablePickerTests: XCTestCase {
    private final class Owner { var session: ProjectEditSession? = try? .init(accountID: 7, epoch: 1, storageNamespace: "story-vars") }
    private func setup(scope: ProjectEditScope = .full) async throws -> (ProjectStoryVariableController, Owner, ProjectEditMemoryStorage) {
        let owner = Owner(), storage = ProjectEditMemoryStorage(); var draft = ProjectEditSyntheticFixtures.draft()
        draft.chapters[0].id = "chapter"; var block = ProjectEditBlock(kind: .text, content: "Hello e\u{301} "); block.id = "text"; draft.chapters[0].blocks = [block]
        draft.chapters[0].nodes[0].templateID = 41
        draft.chapters[0].nodes[0].localMetadata["templateInfo"] = .object(["id": .number(41), "advancedConfigJson": .string(#"{"schemaVersion":1,"profile":{"enabled":true,"questions":[{"key":"name","label":"Name","kind":"text"}]}}"#)])
        let initial = ProjectEditSnapshot(topicID: scope == .whitelist ? 101 : nil, scope: scope, draft: draft)
        let model = ProjectEditModel(coordinator: .init(initial: initial, service: ProjectEditSyntheticService(snapshot: initial), store: .init(storage: storage), currentSession: { owner.session }))
        await model.load(); return (.init(model: model, chapterID: "chapter", blockID: "text"), owner, storage)
    }
    private func open(_ controller: ProjectStoryVariableController) throws -> ProjectStoryVariableController.Opening {
        controller.open(try XCTUnwrap(controller.capture(controller.snapshot))); return try XCTUnwrap(controller.opening)
    }
    func testOpenSelectionAndCancelAreExactNoOps() async throws {
        let (controller, _, storage) = try await setup(), model = controller.model
        let before = ProjectEditPendingMaterials.exactData(model.draft), revision = model.draftMutationRevision, saved = storage.data
        let original = try open(controller); controller.select("name", in: original); controller.close(original)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before); XCTAssertEqual(model.draftMutationRevision, revision); XCTAssertEqual(storage.data, saved)
        XCTAssertFalse(controller.append(original)); XCTAssertNil(controller.selectedKey)
    }
    func testExplicitAppendChangesOnlyContentOnceAndUsesExistingSavePath() async throws {
        let (controller, _, storage) = try await setup(), model = controller.model, original = try open(controller)
        let saved = storage.data, revision = model.draftMutationRevision; var expected = model.draft; expected.chapters[0].blocks![0].content += "{name}"
        XCTAssertFalse(controller.append(original)); controller.select("name", in: original); XCTAssertTrue(controller.append(original))
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), ProjectEditPendingMaterials.exactData(expected)); XCTAssertEqual(model.draftMutationRevision, revision + 1)
        XCTAssertEqual(storage.data, saved); XCTAssertFalse(controller.append(original)); model.saveLocal(); XCTAssertFalse(storage.data.isEmpty)
    }
    func testUnknownOrCanonicalAliasSelectionCannotAppend() async throws {
        let (controller, _, _) = try await setup(), original = try open(controller)
        for key in ["Name", "missing", "name|fallback", "KEY"] { controller.select(key, in: original); XCTAssertNil(controller.selectedKey); XCTAssertFalse(controller.append(original)) }
    }
    func testStaleRenderedCaptureAndSameByteABAEventsCannotOpen() async throws {
        for changed in [false, true] {
            let (controller, _, _) = try await setup(), model = controller.model, capture = try XCTUnwrap(controller.capture(controller.snapshot))
            if changed { model.draft.chapters[0].blocks![0].content += "!" } else { let same = model.draft; model.draft = same }
            controller.open(capture); XCTAssertNil(controller.opening)
        }
    }
    func testTextDeclarationDeleteAndReorderChangesRejectPendingAppend() async throws {
        for kind in ["content", "declaration", "delete", "reorder", "aba"] {
            let (controller, _, _) = try await setup(), model = controller.model, original = try open(controller); controller.select("name", in: original)
            switch kind {
            case "content": model.draft.chapters[0].blocks![0].content += "!"
            case "declaration": model.draft.chapters[0].nodes[0].templateID = 42
            case "delete": model.draft.chapters[0].blocks = []
            case "reorder": model.draft.chapters[0].blocks!.insert(.init(kind: .text, content: "new"), at: 0)
            default: let same = model.draft; model.draft = same
            }
            let before = ProjectEditPendingMaterials.exactData(model.draft); XCTAssertFalse(controller.append(original)); XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before)
        }
    }
    func testWhitelistAccountEpochRestoreAndRevokedVisitRejectApply() async throws {
        let (locked, _, _) = try await setup(scope: .whitelist); XCTAssertNil(locked.capture(locked.snapshot))
        for kind in ["account", "epoch", "restore", "revoke"] {
            let (controller, owner, _) = try await setup(), model = controller.model, original = try open(controller); controller.select("name", in: original)
            switch kind {
            case "restore": model.saveLocal(); await model.load(force: true); model.restore()
            case "revoke": model.coordinator.beginEditorVisit(UUID())
            default: owner.session = try .init(accountID: kind == "account" ? 8 : 7, epoch: 2, storageNamespace: "story-vars")
            }
            let before = ProjectEditPendingMaterials.exactData(model.draft); XCTAssertFalse(controller.append(original)); XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before)
        }
    }
    func testOldDismissalAndSelectionCannotAffectNewOpening() async throws {
        let (controller, _, _) = try await setup(), old = try open(controller), binding = controller.binding(old)
        controller.close(old); let current = try open(controller); binding.wrappedValue = false; controller.close(old); controller.select("name", in: old)
        XCTAssertEqual(controller.opening?.id, current.id); XCTAssertNil(controller.selectedKey)
        controller.select("name", in: current); XCTAssertTrue(controller.append(current))
    }
    func testNavigationRetirementRejectsLateAppend() async throws {
        let (controller, _, _) = try await setup(), original = try open(controller); controller.select("name", in: original); controller.retire()
        let before = ProjectEditPendingMaterials.exactData(controller.model.draft)
        XCTAssertFalse(controller.append(original)); XCTAssertEqual(ProjectEditPendingMaterials.exactData(controller.model.draft), before)
    }
    func testEmptyAndWrongBlockSnapshotsCannotOpen() async throws {
        let (controller, _, _) = try await setup(), model = controller.model
        var other = ProjectEditBlock(kind: .text, content: "other"); other.id = "other"; model.draft.chapters[0].blocks!.append(other)
        XCTAssertNil(controller.capture(.init(draft: model.draft, chapterID: "chapter", blockID: "other")))
        model.draft.chapters[0].nodes[0].localMetadata["templateInfo"] = .object(["id": .number(41)])
        controller.open(try XCTUnwrap(controller.capture(controller.snapshot))); XCTAssertNil(controller.opening)
    }
    func testExistingPersistenceFailureDoesNotCreateImmediateSaveClaim() async throws {
        let (controller, _, storage) = try await setup(), original = try open(controller), before = storage.data
        storage.failWrites = true; controller.select("name", in: original); XCTAssertTrue(controller.append(original)); XCTAssertEqual(storage.data, before)
        XCTAssertTrue(controller.model.draft.chapters[0].blocks![0].content.hasSuffix("{name}")); controller.model.saveLocal(); XCTAssertEqual(storage.data, before)
    }
    func testChoiceThatExceedsSourceTextLimitCannotBeSelected() async throws {
        let (controller, _, _) = try await setup(); controller.model.draft.chapters[0].blocks![0].content = String(repeating: "a", count: 4995)
        let original = try open(controller); controller.select("name", in: original)
        XCTAssertNil(controller.selectedKey); XCTAssertFalse(controller.append(original))
        XCTAssertEqual(controller.model.draft.chapters[0].blocks![0].content.utf16.count, 4995)
    }

}

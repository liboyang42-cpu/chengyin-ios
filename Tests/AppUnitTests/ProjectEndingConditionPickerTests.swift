import XCTest
@testable import Questify

@MainActor final class ProjectEndingConditionPickerTests: XCTestCase {
    private final class Owner { var session: ProjectEditSession? = try? .init(accountID: 7, epoch: 1, storageNamespace: "ending-picker") }
    private func setup(scope: ProjectEditScope = .full) async throws -> (ProjectEndingConditionController, Owner, ProjectEditMemoryStorage) {
        let owner = Owner(), storage = ProjectEditMemoryStorage(); var draft = ProjectEditSyntheticFixtures.draft()
        draft.preserved["journeyRules"] = .string(#"{"schemaVersion":1,"thoughts":[{"key":"first","name":"First","need":120}]}"#)
        var ending = ProjectEditChapter(); ending.preserved["ending"] = .object(["fallback": .bool(false), "when": .array([.object(["op": .string("HAS_TAG"), "value": .string("thought.first.done")])])])
        draft.chapters.append(ending)
        let initial = ProjectEditSnapshot(topicID: scope == .whitelist ? 101 : nil, scope: scope, draft: draft)
        let model = ProjectEditModel(coordinator: .init(initial: initial, service: ProjectEditSyntheticService(snapshot: initial),
            store: .init(storage: storage), currentSession: { owner.session }))
        await model.load(); return (.init(context: .init(model: model, chapterID: ending.id, index: 0)), owner, storage)
    }
    private func open(_ controller: ProjectEndingConditionController) throws -> ProjectEndingConditionController.Presentation {
        controller.open(); return try XCTUnwrap(controller.presentation)
    }
    func testOpenCancelAndSameSelectionSavePreserveExactDraftAndStorage() async throws {
        let (controller, _, storage) = try await setup(), model = controller.context.model
        let before = ProjectEditPendingMaterials.exactData(model.draft), saved = storage.data
        let original = try open(controller); controller.close(original)
        let next = try open(controller); controller.apply(id: "thought:first", original: next)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before); XCTAssertEqual(storage.data, saved)
        XCTAssertNil(controller.presentation)
    }
    func testUnknownExistingValueStaysUntilExplicitRealSelection() async throws {
        let (controller, _, storage) = try await setup(), model = controller.context.model
        model.draft.chapters[1].preserved["ending"] = .object(["fallback": .bool(false), "when": .array([.object(["op": .string("HAS_TAG"), "value": .string("unknown.old")])])])
        let original = try open(controller), before = ProjectEditPendingMaterials.exactData(model.draft), saved = storage.data
        controller.apply(id: "invented", original: original); XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before)
        controller.apply(id: "thought:first", original: original)
        XCTAssertEqual(ProjectEndingConditionChoices.condition(model.draft, chapterID: controller.context.chapterID, index: 0)?["value"], .string("thought.first.done"))
        XCTAssertEqual(storage.data, saved)
    }
    func testDeletedReorderedConditionsSourceChangeAndSameByteABARejectOldConfirmation() async throws {
        for action in ["delete", "reorder", "source", "aba"] {
            let (controller, _, _) = try await setup(), model = controller.context.model
            var ending = model.draft.chapters[1].preserved["ending"]!.object!
            ending["when"] = .array(ending["when"]!.array! + [.object(["op": .string("HAS_TAG"), "value": .string("unknown.second")])])
            model.draft.chapters[1].preserved["ending"] = .object(ending)
            let original = try open(controller)
            switch action {
            case "delete": ending["when"] = .array([]); model.draft.chapters[1].preserved["ending"] = .object(ending)
            case "reorder": ending["when"] = .array(Array(ending["when"]!.array!.reversed())); model.draft.chapters[1].preserved["ending"] = .object(ending)
            case "source": model.draft.preserved["journeyRules"] = .string("{}")
            default: let same = model.draft; model.draft = same
            }
            let before = ProjectEditPendingMaterials.exactData(model.draft); controller.apply(id: "thought:first", original: original)
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before, action)
        }
    }
    func testAccountEpochRestoreAndWhitelistKeepOldTargetUnavailable() async throws {
        let (locked, _, _) = try await setup(scope: .whitelist); locked.open(); XCTAssertNil(locked.presentation)
        for action in ["account", "epoch", "restore"] {
            let (controller, owner, _) = try await setup(), model = controller.context.model, original = try open(controller)
            if action == "restore" { model.saveLocal(); await model.load(force: true); model.restore() }
            else { owner.session = try .init(accountID: action == "account" ? 8 : 7, epoch: 2, storageNamespace: "ending-picker") }
            let before = ProjectEditPendingMaterials.exactData(model.draft); controller.apply(id: "thought:first", original: original)
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before)
        }
    }
    func testOldDismissalAndNavigationRetirementCannotAffectNewPicker() async throws {
        let (controller, _, _) = try await setup(), old = try open(controller), binding = controller.binding(old)
        controller.close(old); let next = try open(controller); binding.wrappedValue = nil; controller.close(old)
        XCTAssertEqual(controller.presentation?.id, next.id)
        controller.retire(); let before = ProjectEditPendingMaterials.exactData(controller.context.model.draft)
        controller.apply(id: "thought:first", original: next); XCTAssertEqual(ProjectEditPendingMaterials.exactData(controller.context.model.draft), before)
    }
}

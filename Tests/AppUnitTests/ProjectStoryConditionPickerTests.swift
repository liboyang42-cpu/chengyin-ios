import SwiftUI
import XCTest
@testable import Questify

@MainActor final class ProjectStoryConditionPickerTests: XCTestCase {
    private final class Owner { var session: ProjectEditSession? = try? .init(accountID: 7, epoch: 1, storageNamespace: "voice-picker") }
    private func setup(scope: ProjectEditScope = .full) async throws -> (ProjectStoryConditionController, Owner, ProjectEditMemoryStorage) {
        let owner = Owner(), storage = ProjectEditMemoryStorage(); var draft = ProjectEditSyntheticFixtures.draft()
        draft.preserved["journeyRules"] = .string(#"{"schemaVersion":1,"thoughts":[{"key":"first","name":"First","need":120}]}"#)
        var voice = ProjectEditBlock(kind: .voice, content: "Voice"); voice.id = "voice"
        voice.sourceFields = ["when": .object(["op": .string("HAS_TAG"), "value": .string("thought.first.done"), "future": .string("e\u{301}")])]
        draft.chapters[0].blocks = [voice, .init(kind: .mood)]
        let initial = ProjectEditSnapshot(topicID: scope == .whitelist ? 101 : nil, scope: scope, draft: draft)
        let model = ProjectEditModel(coordinator: .init(initial: initial, service: ProjectEditSyntheticService(snapshot: initial),
            store: .init(storage: storage), currentSession: { owner.session }))
        await model.load()
        let id = draft.chapters[0].id
        let block = Binding<ProjectEditBlock>(get: { model.draft.chapters.first { $0.id == id }?.blocks?.first { $0.id == "voice" } ?? .init(kind: .text) }, set: { _ in })
        return (.init(model: model, chapterID: id, block: block), owner, storage)
    }
    private func open(_ controller: ProjectStoryConditionController) throws -> ProjectStoryConditionController.Presentation {
        controller.open(); return try XCTUnwrap(controller.presentation)
    }
    func testOpenCancelAndSameSelectionAreExactNoOps() async throws {
        let (controller, _, storage) = try await setup(), before = ProjectEditPendingMaterials.exactData(controller.model.draft), saved = storage.data
        let revision = controller.model.draftMutationRevision, old = try open(controller); controller.close(old)
        let next = try open(controller); controller.apply(id: "thought:first", original: next)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(controller.model.draft), before); XCTAssertEqual(storage.data, saved)
        XCTAssertEqual(controller.model.draftMutationRevision, revision); XCTAssertNil(controller.presentation)
    }
    func testUnknownValueAndFieldsRemainUntilExplicitKnownChoice() async throws {
        let (controller, _, storage) = try await setup(), model = controller.model
        model.draft.chapters[0].blocks![0].setField("when", .object(["op": .string("HAS_TAG"), "value": .string("unknown.old"), "future": .string("e\u{301}")]))
        let original = try open(controller), before = ProjectEditPendingMaterials.exactData(model.draft), saved = storage.data
        controller.apply(id: "invented", original: original); XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before)
        controller.apply(id: "thought:first", original: original)
        XCTAssertEqual(model.draft.chapters[0].blocks![0].sourceFields?["when"]?.object?["value"], .string("thought.first.done"))
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft.chapters[0].blocks![0].sourceFields?["when"]?.object?["future"]), ProjectEditPendingMaterials.exactData(ProjectEditJSON.string("e\u{301}")))
        XCTAssertEqual(storage.data, saved)
    }
    func testDeleteReorderSourceChangeAndSameByteReplacementRejectOldConfirmation() async throws {
        for action in ["delete", "reorder", "source", "aba"] {
            let (controller, _, _) = try await setup(), model = controller.model, original = try open(controller)
            switch action {
            case "delete": model.draft.chapters[0].blocks!.removeFirst()
            case "reorder": model.draft.chapters[0].blocks!.reverse()
            case "source": model.draft.preserved["journeyRules"] = .string("{}")
            default: let same = model.draft; model.draft = same
            }
            let before = ProjectEditPendingMaterials.exactData(model.draft); controller.apply(id: "thought:first", original: original)
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before, action)
        }
    }
    func testAccountEpochRestoreAndWhitelistRejectOldOrMissingAuthority() async throws {
        let (locked, _, _) = try await setup(scope: .whitelist); locked.open(); XCTAssertNil(locked.presentation)
        for action in ["account", "epoch", "restore"] {
            let (controller, owner, _) = try await setup(), model = controller.model, original = try open(controller)
            if action == "restore" { model.saveLocal(); await model.load(force: true); model.restore() }
            else { owner.session = try .init(accountID: action == "account" ? 8 : 7, epoch: 2, storageNamespace: "voice-picker") }
            let before = ProjectEditPendingMaterials.exactData(model.draft); controller.apply(id: "thought:first", original: original)
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before)
        }
    }
    func testDifferentBoundBlockAndStaleDismissalCannotRetargetPicker() async throws {
        let (controller, _, _) = try await setup(), old = try open(controller), binding = controller.binding(old)
        controller.close(old); let next = try open(controller); binding.wrappedValue = nil; XCTAssertEqual(controller.presentation?.id, next.id)
        controller.retire(); let before = ProjectEditPendingMaterials.exactData(controller.model.draft)
        controller.apply(id: "thought:first", original: next); XCTAssertEqual(ProjectEditPendingMaterials.exactData(controller.model.draft), before)
        var other = controller.block.wrappedValue; other.content = "unrelated override"
        let wrong = ProjectStoryConditionController(model: controller.model, chapterID: controller.chapterID, block: .constant(other))
        wrong.open(); XCTAssertNil(wrong.presentation)
    }
}

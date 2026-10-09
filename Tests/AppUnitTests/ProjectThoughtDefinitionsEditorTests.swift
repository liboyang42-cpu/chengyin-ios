import XCTest
@testable import Questify

@MainActor final class ProjectThoughtDefinitionsEditorTests: XCTestCase {
    private final class Owner { var session: ProjectEditSession? = try? .init(accountID: 7, epoch: 1, storageNamespace: "thought-editor") }
    private func setup(scope: ProjectEditScope = .full) async throws -> (ProjectThoughtDefinitionsController, Owner, ProjectEditMemoryStorage) {
        let owner = Owner(), storage = ProjectEditMemoryStorage(); var draft = ProjectEditSyntheticFixtures.draft()
        draft.preserved["journeyRules"] = .string(#" {"schemaVersion":1,"thoughts":[{"key":"first","name":"First","need":120}]} "#)
        var thought = ProjectEditBlock(kind: .thought); thought.setField("thoughtKey", .string("first"))
        draft.chapters[0].blocks = [thought]
        let snapshot = ProjectEditSnapshot(topicID: scope == .whitelist ? 101 : nil, scope: scope, draft: draft)
        let model = ProjectEditModel(coordinator: .init(initial: snapshot, service: ProjectEditSyntheticService(snapshot: snapshot),
            store: .init(storage: storage), currentSession: { owner.session }))
        await model.load(); return (.init(model: model), owner, storage)
    }
    private func open(_ controller: ProjectThoughtDefinitionsController) throws -> ProjectThoughtDefinitionsController.Presentation {
        controller.open(); return try XCTUnwrap(controller.presentation)
    }
    func testOpenCancelAndNoOpSaveKeepExactRawBytesAndStorage() async throws {
        let (controller, _, storage) = try await setup()
        let before = ProjectEditPendingMaterials.exactData(controller.model.draft), saved = storage.data
        let first = try open(controller); controller.close(first)
        let next = try open(controller); controller.save(next)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(controller.model.draft), before); XCTAssertEqual(storage.data, saved)
    }
    func testAddAndEditStayInBufferUntilExplicitSaveAndStableKeysDoNotChange() async throws {
        let (controller, _, storage) = try await setup(), original = try open(controller)
        let before = ProjectEditPendingMaterials.exactData(controller.model.draft), saved = storage.data
        controller.add(original); let key = try XCTUnwrap(controller.buffer?.rows.last?.key)
        controller.text(key, field: "name", original: original).wrappedValue = "Second"
        controller.text(key, field: "summary", original: original).wrappedValue = "e\u{301}"
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(controller.model.draft), before)
        controller.save(original); XCTAssertNil(controller.presentation); XCTAssertEqual(storage.data, saved)
        let next = ProjectThoughtDefinitions(raw: controller.model.draft.preserved["journeyRules"], draft: controller.model.draft)
        XCTAssertEqual(next.rows.map(\.key), ["first", key]); XCTAssertEqual(Array(next.rows[1].summary.utf8), Array("e\u{301}".utf8))
    }
    func testDeletionListsKnownReferencesNeverMigratesThemAndOldConfirmationLosesOwnership() async throws {
        let (controller, _, _) = try await setup(), original = try open(controller)
        controller.askRemoval(key: "first", original: original); let old = try XCTUnwrap(controller.removal)
        XCTAssertEqual(old.impacts.count, 1)
        controller.text("first", field: "name", original: original).wrappedValue = "Renamed"
        controller.confirmRemoval(old, original: original); XCTAssertEqual(controller.buffer?.rows.count, 1)
        controller.askRemoval(key: "first", original: original); let current = try XCTUnwrap(controller.removal)
        controller.confirmRemoval(current, original: original); XCTAssertTrue(controller.buffer?.rows.isEmpty == true)
        controller.save(original)
        XCTAssertEqual(controller.model.draft.chapters[0].blocks?[0].fieldText("thoughtKey"), "first")
        let next = ProjectThoughtDefinitions(raw: controller.model.draft.preserved["journeyRules"], draft: controller.model.draft)
        XCTAssertTrue(next.rows.isEmpty)
    }
    func testIdentityEpochABAAndRestoreRejectOldFieldBindingAndSave() async throws {
        for action in ["account", "epoch", "aba", "restore"] {
            let (controller, owner, _) = try await setup(), original = try open(controller), model = controller.model
            let binding = controller.text("first", field: "name", original: original)
            switch action {
            case "account": owner.session = try .init(accountID: 8, epoch: 1, storageNamespace: "thought-editor")
            case "epoch": owner.session = try .init(accountID: 7, epoch: 2, storageNamespace: "thought-editor")
            case "restore": model.saveLocal(); await model.load(force: true); model.restore()
            default: let same = model.draft; model.draft = same
            }
            let before = ProjectEditPendingMaterials.exactData(model.draft)
            binding.wrappedValue = "Must not land"; controller.save(original)
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before, action)
        }
    }
    func testWhitelistUnknownRulesAndUnlistedTagCannotMutate() async throws {
        let (locked, _, _) = try await setup(scope: .whitelist); locked.open(); XCTAssertNil(locked.presentation)
        let (controller, _, _) = try await setup(), original = try open(controller)
        controller.tag("tag.guessed", key: "first", done: true, original: original).wrappedValue = true
        XCTAssertTrue(controller.buffer?.rows[0].doneTags.isEmpty == true); controller.close(original)
        controller.model.draft.preserved["journeyRules"] = .string(#"{"schemaVersion":999}"#)
        let unknown = try open(controller), before = ProjectEditPendingMaterials.exactData(controller.model.draft)
        XCTAssertTrue(controller.buffer?.readOnly == true); controller.add(unknown); controller.save(unknown)
        XCTAssertTrue(controller.invalid); XCTAssertEqual(ProjectEditPendingMaterials.exactData(controller.model.draft), before)
    }
    func testOldDismissalCannotCloseNewEditorAndInvalidDraftRemainsEditableLocally() async throws {
        let (controller, _, _) = try await setup(), old = try open(controller), binding = controller.binding(old)
        controller.close(old); let next = try open(controller); controller.close(old); binding.wrappedValue = nil
        XCTAssertEqual(controller.presentation?.id, next.id)
        controller.text("first", field: "need", original: next).wrappedValue = ""
        controller.save(next); XCTAssertTrue(controller.invalid); XCTAssertNotNil(controller.presentation)
        controller.text("first", field: "need", original: next).wrappedValue = "120"; controller.save(next)
        XCTAssertNil(controller.presentation)
    }
}

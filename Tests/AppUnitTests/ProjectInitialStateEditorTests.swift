import XCTest
@testable import Questify

@MainActor final class ProjectInitialStateEditorTests: XCTestCase {
    private final class Owner { var session: ProjectEditSession? = try? .init(accountID: 7, epoch: 1, storageNamespace: "initial-state") }
    private func setup(scope: ProjectEditScope = .full) async throws -> (ProjectInitialStateController, Owner, ProjectEditMemoryStorage) {
        let owner = Owner(), storage = ProjectEditMemoryStorage(), draft = ProjectEditSyntheticFixtures.draft(product: .city)
        let initial = ProjectEditSnapshot(topicID: scope == .whitelist ? 101 : nil, scope: scope, draft: draft)
        let model = ProjectEditModel(coordinator: .init(initial: initial, service: ProjectEditSyntheticService(snapshot: initial),
            store: .init(storage: storage), currentSession: { owner.session }))
        await model.load()
        return (.init(model: model, chapterID: draft.chapters[0].id), owner, storage)
    }
    private func open(_ controller: ProjectInitialStateController) throws -> ProjectInitialStateController.Presentation {
        controller.open(); return try XCTUnwrap(controller.presentation)
    }
    func testOpeningCancelAndNoOpPreserveBytesReviewAndStorage() async throws {
        let (controller, _, storage) = try await setup(), model = controller.model
        model.draft.preserved["journeyRules"] = .string(" { \"schemaVersion\" : 1 } "); model.review()
        let review = try XCTUnwrap(model.confirmation), before = ProjectEditPendingMaterials.exactData(model.draft), saved = storage.data
        let first = try open(controller); controller.close(first)
        let next = try open(controller); XCTAssertTrue(controller.apply(next.initial, to: next))
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before); XCTAssertEqual(model.confirmation?.id, review.id)
        XCTAssertEqual(storage.data, saved)
    }
    func testWhitelistCannotOpenOrChangeInitialState() async throws {
        let (controller, _, storage) = try await setup(scope: .whitelist)
        let before = ProjectEditPendingMaterials.exactData(controller.model.draft), saved = storage.data
        XCTAssertFalse(controller.model.fullEdit); XCTAssertFalse(controller.available)
        controller.open(); XCTAssertNil(controller.presentation)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(controller.model.draft), before); XCTAssertEqual(storage.data, saved)
    }
    func testOnlyExplicitConfirmationAppliesResourceBufferThroughExistingDraftPath() async throws {
        let (controller, _, storage) = try await setup(), model = controller.model
        let original = try open(controller), before = ProjectEditPendingMaterials.exactData(model.draft), saved = storage.data
        var buffer = original.initial; buffer.setEnabled(true, kind: .hp); buffer.hp.initial = "4"; buffer.hp.maximum = "5"
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before)
        XCTAssertTrue(controller.apply(buffer, to: original)); XCTAssertNotEqual(ProjectEditPendingMaterials.exactData(model.draft), before)
        XCTAssertEqual(storage.data, saved); XCTAssertNil(controller.presentation)
    }
    func testFreshNilNoOpNeverCreatesJourneyRulesAndInvalidInputDoesNotApply() async throws {
        let (controller, _, _) = try await setup()
        let original = try open(controller); XCTAssertTrue(controller.apply(original.initial, to: original))
        XCTAssertNil(controller.model.draft.preserved["journeyRules"])
        let next = try open(controller); var invalid = next.initial; invalid.setEnabled(true, kind: .hp); invalid.hp.maximum = "21"
        XCTAssertFalse(controller.apply(invalid, to: next)); XCTAssertNotNil(controller.presentation)
        XCTAssertNil(controller.model.draft.preserved["journeyRules"])
    }
    func testOtherProductNonFirstDuplicateOrReorderedChapterCannotApply() async throws {
        for action in ["product", "reorder", "delete", "duplicate"] {
            let (controller, _, _) = try await setup(), model = controller.model
            model.draft.chapters.append(ProjectEditChapter()); let original = try open(controller)
            var buffer = original.initial; buffer.setEnabled(true, kind: .hp)
            switch action { case "product": model.draft.product = .freeExplore; case "reorder": model.draft.chapters.reverse(); case "delete": model.draft.chapters.removeFirst(); default: model.draft.chapters.append(model.draft.chapters[0]) }
            let before = ProjectEditPendingMaterials.exactData(model.draft)
            XCTAssertFalse(controller.apply(buffer, to: original)); XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before)
            XCTAssertFalse(controller.available)
        }
    }
    func testAccountEpochRestoreSameByteABAAndRetirementRejectStaleBuffer() async throws {
        for action in ["account", "epoch", "restore", "aba", "retire"] {
            let (controller, owner, _) = try await setup(), model = controller.model
            let original = try open(controller); var buffer = original.initial; buffer.setEnabled(true, kind: .luck)
            switch action {
            case "account": owner.session = try .init(accountID: 8, epoch: 1, storageNamespace: "initial-state")
            case "epoch": owner.session = try .init(accountID: 7, epoch: 2, storageNamespace: "initial-state")
            case "restore": model.saveLocal(); await model.load(force: true); model.restore()
            case "aba": let same = model.draft; model.draft = same
            default: controller.retire()
            }
            let before = ProjectEditPendingMaterials.exactData(model.draft)
            XCTAssertFalse(controller.apply(buffer, to: original)); XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before)
        }
    }
    func testUnknownSourceAndOldDismissalCannotOverwriteOrCloseNewEditor() async throws {
        let (controller, _, _) = try await setup(), model = controller.model
        model.draft.preserved["journeyRules"] = .string(#"{"schemaVersion":999}"#)
        let original = try open(controller), before = ProjectEditPendingMaterials.exactData(model.draft)
        XCTAssertTrue(original.initial.readOnly); XCTAssertFalse(controller.apply(original.initial, to: original))
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before); controller.close(original)
        let next = try open(controller); controller.close(original); XCTAssertEqual(controller.presentation?.id, next.id)
    }
}

import XCTest
@testable import Questify

@MainActor final class ProjectInitialAttributesPresentationTests: XCTestCase {
    private final class Owner { var session: ProjectEditSession? = try? .init(accountID: 7, epoch: 1, storageNamespace: "initial-attributes") }
    private func setup(scope: ProjectEditScope = .full) async throws -> (ProjectInitialAttributesController, Owner, ProjectEditMemoryStorage) {
        let owner = Owner(), storage = ProjectEditMemoryStorage(), draft = ProjectEditSyntheticFixtures.draft(product: .city)
        let initial = ProjectEditSnapshot(topicID: scope == .whitelist ? 101 : nil, scope: scope, draft: draft)
        let model = ProjectEditModel(coordinator: .init(initial: initial, service: ProjectEditSyntheticService(snapshot: initial),
            store: .init(storage: storage), currentSession: { owner.session }))
        await model.load()
        return (.init(model: model, chapterID: draft.chapters[0].id), owner, storage)
    }
    private func open(_ controller: ProjectInitialAttributesController) throws -> ProjectInitialAttributesController.Presentation {
        controller.open(try XCTUnwrap(controller.capture())); return try XCTUnwrap(controller.presentation)
    }
    private func add(_ controller: ProjectInitialAttributesController, _ original: ProjectInitialAttributesController.Presentation) throws -> UUID {
        controller.add(in: original); var row = try XCTUnwrap(controller.buffer?.rows.last)
        row.key = "counter.score"; row.label = "Score"; controller.replace(row, in: original); return row.id
    }
    func testOpenCancelAndNoOpKeepDraftPreparedReviewAndStorageExact() async throws {
        let (controller, _, storage) = try await setup(), model = controller.model
        model.draft.preserved["journeyRules"] = .string(" { \"schemaVersion\":1 } "); model.review()
        let review = try XCTUnwrap(model.confirmation), before = ProjectEditPendingMaterials.exactData(model.draft), saved = storage.data
        let original = try open(controller); _ = try add(controller, original); controller.close(original)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before)
        let next = try open(controller); XCTAssertTrue(controller.apply(next))
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before); XCTAssertEqual(model.confirmation?.id, review.id); XCTAssertEqual(storage.data, saved)
    }
    func testExplicitApplyOnlyMutatesJourneyRulesUsingExistingDraftPath() async throws {
        let (controller, _, storage) = try await setup(), model = controller.model
        let original = try open(controller), saved = storage.data, before = model.draft
        _ = try add(controller, original); XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), ProjectEditPendingMaterials.exactData(before))
        XCTAssertTrue(controller.apply(original)); XCTAssertEqual(storage.data, saved)
        var inverse = model.draft; inverse.preserved["journeyRules"] = before.preserved["journeyRules"]
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(inverse), ProjectEditPendingMaterials.exactData(before)); XCTAssertNil(controller.presentation)
    }
    func testInvalidRowKeepsSheetAndDraftUnchangedUntilCorrected() async throws {
        let (controller, _, _) = try await setup(); let original = try open(controller), before = ProjectEditPendingMaterials.exactData(controller.model.draft)
        controller.add(in: original); XCTAssertFalse(controller.apply(original)); XCTAssertNotNil(controller.presentation)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(controller.model.draft), before)
        var row = try XCTUnwrap(controller.buffer?.rows.last); row.key = "counter.score"; row.label = "Score"; controller.replace(row, in: original)
        XCTAssertTrue(controller.apply(original))
    }
    func testFreshUntouchedApplyKeepsJourneyRulesAbsent() async throws {
        let (controller, _, _) = try await setup(); let original = try open(controller)
        XCTAssertTrue(controller.apply(original)); XCTAssertNil(controller.model.draft.preserved["journeyRules"])
    }
    func testWhitelistCannotCaptureOrOpen() async throws {
        let (controller, _, storage) = try await setup(scope: .whitelist), saved = storage.data
        XCTAssertFalse(controller.available); XCTAssertNil(controller.capture()); XCTAssertNil(controller.presentation); XCTAssertEqual(storage.data, saved)
    }
    func testQueuedOpeningAfterDepartureOrForeignControllerCannotOpen() async throws {
        let (controller, _, _) = try await setup(); let capture = try XCTUnwrap(controller.capture())
        controller.retire(); controller.open(capture); XCTAssertNil(controller.presentation)
        let (other, _, _) = try await setup(); other.open(try XCTUnwrap(controller.capture())); XCTAssertNil(other.presentation)
    }
    func testAccountEpochLogoutRestoreAndSameByteABARejectApply() async throws {
        for action in ["account", "epoch", "logout", "restore", "aba", "retire", "leave"] {
            let (controller, owner, _) = try await setup(), model = controller.model
            let original = try open(controller); _ = try add(controller, original)
            switch action {
            case "account": owner.session = try .init(accountID: 8, epoch: 1, storageNamespace: "initial-attributes")
            case "epoch": owner.session = try .init(accountID: 7, epoch: 2, storageNamespace: "initial-attributes")
            case "logout": owner.session = nil
            case "restore": model.saveLocal(); await model.load(force: true); model.restore()
            case "aba": let same = model.draft; model.draft = same
            case "leave": model.leave()
            default: controller.retire()
            }
            let before = ProjectEditPendingMaterials.exactData(model.draft)
            XCTAssertFalse(controller.apply(original), action); XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before)
        }
    }
    func testProductFirstChapterReorderDeletionAndDuplicateFence() async throws {
        for action in ["product", "reorder", "delete", "duplicate"] {
            let (controller, _, _) = try await setup(), model = controller.model
            model.draft.chapters.append(ProjectEditChapter()); let original = try open(controller); _ = try add(controller, original)
            switch action { case "product": model.draft.product = .freeExplore; case "reorder": model.draft.chapters.reverse(); case "delete": model.draft.chapters.removeFirst(); default: model.draft.chapters.append(model.draft.chapters[0]) }
            XCTAssertFalse(controller.available); XCTAssertFalse(controller.apply(original))
        }
    }
    func testRemovalNeedsExplicitConfirmationAndCancelRetainsRow() async throws {
        let (controller, _, _) = try await setup(); let original = try open(controller), id = try add(controller, original)
        controller.requestRemoval(id, in: original); let intent = try XCTUnwrap(controller.removal)
        XCTAssertEqual(controller.buffer?.rows.count, 1); XCTAssertFalse(controller.apply(original)); controller.cancelRemoval(intent)
        XCTAssertEqual(controller.buffer?.rows.count, 1); XCTAssertFalse(controller.confirmRemoval(intent, in: original))
        controller.requestRemoval(id, in: original); XCTAssertTrue(controller.confirmRemoval(try XCTUnwrap(controller.removal), in: original)); XCTAssertEqual(controller.buffer?.rows.count, 0)
    }
    func testStaleRemovalRejectsBufferABAAndReopenedPresentation() async throws {
        let (controller, _, _) = try await setup(); let original = try open(controller), id = try add(controller, original)
        controller.requestRemoval(id, in: original); let old = try XCTUnwrap(controller.removal)
        let same = try XCTUnwrap(controller.buffer?.rows.first); controller.replace(same, in: original)
        XCTAssertFalse(controller.confirmRemoval(old, in: original)); XCTAssertEqual(controller.buffer?.rows.count, 1)
        controller.requestRemoval(id, in: original); let oldAgain = try XCTUnwrap(controller.removal); controller.close(original)
        let next = try open(controller); _ = try add(controller, next)
        XCTAssertFalse(controller.confirmRemoval(oldAgain, in: original)); controller.close(original); XCTAssertEqual(controller.presentation?.id, next.id)
    }
    func testRemovalAfterOwnerChangeCannotTouchDraftOrBuffer() async throws {
        let (controller, owner, _) = try await setup(); let original = try open(controller), id = try add(controller, original)
        controller.requestRemoval(id, in: original); let intent = try XCTUnwrap(controller.removal)
        owner.session = nil; XCTAssertFalse(controller.confirmRemoval(intent, in: original)); XCTAssertEqual(controller.buffer?.rows.count, 1)
    }
    func testUnsupportedImportStaysReadOnlyAndUnchanged() async throws {
        let (controller, _, _) = try await setup(); controller.model.draft.preserved["journeyRules"] = .string(#"{"schemaVersion":2,"attributes":[]}"#)
        let original = try open(controller), before = ProjectEditPendingMaterials.exactData(controller.model.draft)
        XCTAssertTrue(try XCTUnwrap(controller.buffer).readOnly); controller.add(in: original); controller.setEnabled(true, in: original)
        XCTAssertFalse(controller.apply(original)); XCTAssertEqual(ProjectEditPendingMaterials.exactData(controller.model.draft), before)
    }
}

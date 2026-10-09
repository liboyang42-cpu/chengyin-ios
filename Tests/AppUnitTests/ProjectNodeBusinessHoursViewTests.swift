import XCTest
@testable import Questify

@MainActor final class ProjectNodeBusinessHoursViewTests: XCTestCase {
    private final class Owner { var session: ProjectEditSession? = try? .init(accountID: 7, epoch: 1, storageNamespace: "node-hours") }
    private func setup(raw: ProjectEditJSON? = .string("09:00-18:00"), scope: ProjectEditScope = .full) async throws -> (ProjectNodeBusinessHoursController, Owner, ProjectEditMemoryStorage) {
        let owner = Owner(), storage = ProjectEditMemoryStorage(); var draft = ProjectEditSyntheticFixtures.draft()
        draft.chapters[0].id = "chapter"; draft.chapters[0].nodes[0].id = "node"; draft.chapters[0].nodes[0].localMetadata["businessTime"] = raw
        let initial = ProjectEditSnapshot(topicID: scope == .whitelist ? 101 : nil, scope: scope, draft: draft)
        let model = ProjectEditModel(coordinator: .init(initial: initial, service: ProjectEditSyntheticService(snapshot: initial), store: .init(storage: storage), currentSession: { owner.session }))
        await model.load(); return (.init(model: model, chapterID: "chapter", nodeID: "node"), owner, storage)
    }
    private func open(_ controller: ProjectNodeBusinessHoursController) throws -> ProjectNodeBusinessHoursController.Opening {
        controller.open(try XCTUnwrap(controller.capture(controller.snapshot))); return try XCTUnwrap(controller.opening)
    }
    private var replacement: ProjectNodeBusinessHours.Value { .init(startHour: 23, startMinute: 15, endHour: 0, endMinute: 30)! }
    func testOpenCancelAndUnchangedApplyPreserveBytesRevisionAndStorage() async throws {
        let (controller, _, storage) = try await setup(), model = controller.model, before = ProjectEditPendingMaterials.exactData(model.draft), revision = model.draftMutationRevision, saved = storage.data
        let old = try open(controller); controller.close(old); let next = try open(controller)
        XCTAssertFalse(controller.canApply(next)); XCTAssertTrue(controller.apply(next))
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before); XCTAssertEqual(model.draftMutationRevision, revision); XCTAssertEqual(storage.data, saved)
    }
    func testEmptyDoesNotStageOrWriteDefaultUntilExplicitActionAndConfirmation() async throws {
        for raw: ProjectEditJSON? in [nil, .null, .string("")] {
            let (controller, _, storage) = try await setup(raw: raw), model = controller.model, before = ProjectEditPendingMaterials.exactData(model.draft), saved = storage.data
            let original = try open(controller); XCTAssertNil(controller.selection); XCTAssertFalse(controller.apply(original)); XCTAssertFalse(controller.canApply(original))
            controller.beginReplacement(original); XCTAssertEqual(controller.selection?.text, "09:00-18:00")
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before); XCTAssertEqual(storage.data, saved)
            controller.close(original); XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before)
        }
    }
    func testExplicitReplacementMutatesWorkingDraftOnceWithNoImmediateSaveClaim() async throws {
        let (controller, _, storage) = try await setup(raw: nil), model = controller.model, original = try open(controller), saved = storage.data, revision = model.draftMutationRevision
        controller.beginReplacement(original); controller.select(replacement, in: original)
        XCTAssertTrue(controller.apply(original)); XCTAssertFalse(controller.apply(original)); XCTAssertEqual(model.draftMutationRevision, revision + 1)
        XCTAssertEqual(model.draft.chapters[0].nodes[0].localMetadata["businessTime"], .string("23:15-00:30")); XCTAssertEqual(storage.data, saved)
        model.saveLocal(); XCTAssertFalse(storage.data.isEmpty)
    }
    func testLegacyMalformedFieldsCannotOpenReplacement() async throws {
        for raw: ProjectEditJSON in [.string("09:00"), .string(" 09:00-18:00"), .number(900)] {
            let (controller, _, _) = try await setup(raw: raw); XCTAssertEqual(controller.snapshot.reason, .unsupported); XCTAssertNil(controller.capture(controller.snapshot))
        }
    }
    func testStaleRenderAndSameByteABARejectOpeningAndApply() async throws {
        let (controller, _, _) = try await setup(), model = controller.model, capture = try XCTUnwrap(controller.capture(controller.snapshot))
        let same = model.draft; model.draft = same; controller.open(capture); XCTAssertNil(controller.opening)
        let original = try open(controller); controller.select(replacement, in: original); let sameAgain = model.draft; model.draft = sameAgain
        XCTAssertFalse(controller.apply(original))
    }
    func testHoursDeletionReorderAndOtherChangesRejectConfirmation() async throws {
        for kind in ["hours", "delete", "reorder", "other"] {
            let (controller, _, _) = try await setup(), model = controller.model, original = try open(controller); controller.select(replacement, in: original)
            switch kind {
            case "hours": model.draft.chapters[0].nodes[0].localMetadata["businessTime"] = .string("10:00-18:00")
            case "delete": model.draft.chapters[0].nodes = []
            case "reorder": var other = ProjectEditNode(); other.id = "other"; model.draft.chapters[0].nodes.insert(other, at: 0)
            default: model.draft.name += "!"
            }
            let before = ProjectEditPendingMaterials.exactData(model.draft); XCTAssertFalse(controller.apply(original)); XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before)
        }
    }
    func testWhitelistAccountEpochRestoreAndRevokedVisitFailClosed() async throws {
        let (locked, _, _) = try await setup(scope: .whitelist); XCTAssertNil(locked.capture(locked.snapshot))
        for kind in ["account", "epoch", "restore", "revoke"] {
            let (controller, owner, _) = try await setup(), model = controller.model, original = try open(controller); controller.select(replacement, in: original)
            switch kind {
            case "restore": model.saveLocal(); await model.load(force: true); model.restore()
            case "revoke": model.coordinator.beginEditorVisit(UUID())
            default: owner.session = try .init(accountID: kind == "account" ? 8 : 7, epoch: 2, storageNamespace: "node-hours")
            }
            let before = ProjectEditPendingMaterials.exactData(model.draft); XCTAssertFalse(controller.apply(original)); XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before)
        }
    }
    func testOtherControllerAndWrongTargetCapturesCannotOpen() async throws {
        let (controller, _, _) = try await setup(), other = ProjectNodeBusinessHoursController(model: controller.model, chapterID: "chapter", nodeID: "node")
        controller.open(try XCTUnwrap(other.capture(other.snapshot))); XCTAssertNil(controller.opening)
        XCTAssertNil(controller.capture(.init(draft: controller.model.draft, chapterID: "chapter", nodeID: "other")))
    }
    func testOldCloseSelectionAndNavigationCallbacksCannotAffectNewOpening() async throws {
        let (controller, _, _) = try await setup(), old = try open(controller), binding = controller.binding(old)
        controller.close(old); let current = try open(controller); binding.wrappedValue = nil; controller.select(replacement, in: old); controller.close(old)
        XCTAssertEqual(controller.opening?.id, current.id); XCTAssertEqual(controller.selection?.text, "09:00-18:00")
        controller.retire(); XCTAssertFalse(controller.apply(current))
    }
    func testPersistenceFailureRemainsOwnedByExistingSaveFlow() async throws {
        let (controller, _, storage) = try await setup(), original = try open(controller), saved = storage.data
        storage.failWrites = true; controller.select(replacement, in: original); XCTAssertTrue(controller.apply(original)); XCTAssertEqual(storage.data, saved)
        controller.model.saveLocal(); XCTAssertEqual(storage.data, saved); XCTAssertEqual(controller.model.draft.chapters[0].nodes[0].localMetadata["businessTime"], .string("23:15-00:30"))
    }

    func testClearIsStagedUntilApplyAndCancelPreservesExactDraft() async throws {
        let (controller, _, storage) = try await setup(), original = try open(controller)
        let before = ProjectEditPendingMaterials.exactData(controller.model.draft), revision = controller.model.draftMutationRevision, saved = storage.data
        controller.chooseClear(original); XCTAssertTrue(controller.clearSelected); XCTAssertNil(controller.selection); XCTAssertTrue(controller.canApply(original))
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(controller.model.draft), before); XCTAssertEqual(storage.data, saved)
        controller.close(original); XCTAssertFalse(controller.clearSelected); XCTAssertFalse(controller.apply(original))
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(controller.model.draft), before); XCTAssertEqual(controller.model.draftMutationRevision, revision)
    }
    func testExplicitClearAppliesEmptyStringOnceAndReopenShowsEmpty() async throws {
        let (controller, _, storage) = try await setup(), original = try open(controller), saved = storage.data, revision = controller.model.draftMutationRevision
        var expected = controller.model.draft; expected.chapters[0].nodes[0].localMetadata["businessTime"] = .string("")
        controller.chooseClear(original); XCTAssertTrue(controller.apply(original)); XCTAssertFalse(controller.apply(original))
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(controller.model.draft), ProjectEditPendingMaterials.exactData(expected)); XCTAssertEqual(storage.data, saved); XCTAssertEqual(controller.model.draftMutationRevision, revision + 1)
        let reopened = try open(controller); XCTAssertNil(controller.selection); XCTAssertFalse(controller.clearSelected); XCTAssertFalse(controller.canApply(reopened))
    }
    func testUndoClearRestoresCapturedSelectionWithoutMutation() async throws {
        let (controller, _, _) = try await setup(), original = try open(controller), before = ProjectEditPendingMaterials.exactData(controller.model.draft)
        controller.chooseClear(original); controller.undoClear(original)
        XCTAssertFalse(controller.clearSelected); XCTAssertEqual(controller.selection?.text, "09:00-18:00"); XCTAssertFalse(controller.canApply(original))
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(controller.model.draft), before)
    }
    func testEmptyOriginalCannotAcquireClearIntentFromAStagedDefault() async throws {
        for raw: ProjectEditJSON? in [nil, .null, .string("")] {
            let (controller, _, _) = try await setup(raw: raw), original = try open(controller)
            controller.chooseClear(original); XCTAssertFalse(controller.clearSelected)
            controller.beginReplacement(original); controller.chooseClear(original)
            XCTAssertFalse(controller.clearSelected); XCTAssertEqual(controller.selection?.text, "09:00-18:00")
        }
    }
    func testClearOwnerLossSameByteABAAndRetirementRejectApply() async throws {
        for kind in ["owner", "epoch", "aba", "retire", "hours"] {
            let (controller, owner, _) = try await setup(), original = try open(controller); controller.chooseClear(original)
            switch kind {
            case "owner": owner.session = nil
            case "epoch": owner.session = try .init(accountID: 7, epoch: 2, storageNamespace: "node-hours")
            case "aba": let same = controller.model.draft; controller.model.draft = same
            case "hours": controller.model.draft.chapters[0].nodes[0].localMetadata["businessTime"] = .string("10:00-18:00")
            default: controller.retire()
            }
            let before = ProjectEditPendingMaterials.exactData(controller.model.draft)
            XCTAssertFalse(controller.apply(original)); XCTAssertEqual(ProjectEditPendingMaterials.exactData(controller.model.draft), before)
        }
    }
    func testOldClearUndoAndDismissalCannotChangeNewSheet() async throws {
        let (controller, _, _) = try await setup(), old = try open(controller), binding = controller.binding(old)
        controller.chooseClear(old); controller.close(old); let current = try open(controller)
        controller.chooseClear(old); controller.undoClear(old); binding.wrappedValue = nil
        XCTAssertEqual(controller.opening?.id, current.id); XCTAssertFalse(controller.clearSelected); XCTAssertEqual(controller.selection?.text, "09:00-18:00")
    }
}

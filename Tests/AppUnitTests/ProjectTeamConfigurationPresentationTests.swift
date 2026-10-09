import XCTest
@testable import Questify

@MainActor final class ProjectTeamConfigurationPresentationTests: XCTestCase {
    private final class Owner { var session: ProjectEditSession? = try? .init(accountID: 7, epoch: 1, storageNamespace: "team-config") }
    private func setup(scope: ProjectEditScope = .full, product: ProjectEditProduct = .city) async throws -> (ProjectTeamConfigurationController, Owner, ProjectEditMemoryStorage) {
        let owner = Owner(), storage = ProjectEditMemoryStorage(), draft = ProjectEditSyntheticFixtures.draft(product: product)
        let initial = ProjectEditSnapshot(topicID: scope == .whitelist ? 101 : nil, scope: scope, draft: draft)
        let model = ProjectEditModel(coordinator: .init(initial: initial, service: ProjectEditSyntheticService(snapshot: initial),
            store: .init(storage: storage), currentSession: { owner.session }))
        await model.load(); return (.init(model: model), owner, storage)
    }
    private func open(_ controller: ProjectTeamConfigurationController) throws -> ProjectTeamConfigurationController.Presentation {
        controller.open(try XCTUnwrap(controller.capture())); return try XCTUnwrap(controller.presentation)
    }
    func testChoiceIsDraftOnlyUntilApplyAndCancelKeepsExactSource() async throws {
        let (controller, _, storage) = try await setup(), model = controller.model
        let original = try open(controller), before = ProjectEditPendingMaterials.exactData(model.draft), saved = storage.data
        controller.selectMode(.afterRegistration, in: original); controller.selectMaximum(2, in: original)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before); controller.close(original)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before); XCTAssertEqual(storage.data, saved)
    }
    func testExplicitApplyChangesOnlyTwoFieldsThroughExistingDraftModel() async throws {
        let (controller, _, storage) = try await setup(), model = controller.model
        let before = model.draft, saved = storage.data, original = try open(controller)
        controller.selectMode(.afterRegistration, in: original); controller.selectMaximum(3, in: original)
        XCTAssertTrue(controller.apply(original)); XCTAssertNil(controller.presentation); XCTAssertEqual(storage.data, saved)
        var expected = before; expected.preserved["teamMode"] = .number(2); expected.preserved["teamMaxMembers"] = .number(3)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), ProjectEditPendingMaterials.exactData(expected))
    }
    func testNoOpApplyPreservesPreparedReviewAndMissingFields() async throws {
        let (controller, _, _) = try await setup(), model = controller.model; model.review()
        let review = try XCTUnwrap(model.confirmation), revision = model.draftMutationRevision, original = try open(controller)
        XCTAssertTrue(controller.apply(original)); XCTAssertNil(model.draft.preserved["teamMode"]); XCTAssertNil(model.draft.preserved["teamMaxMembers"])
        XCTAssertEqual(model.draftMutationRevision, revision); XCTAssertEqual(model.confirmation?.id, review.id)
    }
    func testReopenShowsAppliedValuesAndCancelledValuesNeverLeak() async throws {
        let (controller, _, _) = try await setup(); let first = try open(controller)
        controller.selectMode(.atRegistration, in: first); XCTAssertTrue(controller.apply(first))
        let second = try open(controller); XCTAssertEqual(controller.buffer?.mode, .atRegistration)
        controller.selectMaximum(2, in: second); controller.close(second)
        _ = try open(controller); XCTAssertEqual(controller.buffer?.mode, .atRegistration); XCTAssertEqual(controller.buffer?.maximum, 4)
    }
    func testWhitelistAndNonCityCannotCapture() async throws {
        let (limited, _, _) = try await setup(scope: .whitelist), (explore, _, _) = try await setup(product: .freeExplore)
        XCTAssertFalse(limited.available); XCTAssertNil(limited.capture()); XCTAssertFalse(explore.available); XCTAssertNil(explore.capture())
    }
    func testQueuedOpenAfterDepartureOrForeignControllerIsRejected() async throws {
        let (controller, _, _) = try await setup(); let capture = try XCTUnwrap(controller.capture())
        controller.retire(); controller.open(capture); XCTAssertNil(controller.presentation)
        let other = ProjectTeamConfigurationController(model: controller.model); other.open(try XCTUnwrap(controller.capture())); XCTAssertNil(other.presentation)
    }
    func testAccountEpochLogoutRestoreABAAndLeaveRejectAllMutation() async throws {
        for action in ["account", "epoch", "logout", "restore", "aba", "leave", "retire"] {
            let (controller, owner, _) = try await setup(), model = controller.model; let original = try open(controller)
            controller.selectMode(.afterRegistration, in: original)
            switch action {
            case "account": owner.session = try .init(accountID: 8, epoch: 1, storageNamespace: "team-config")
            case "epoch": owner.session = try .init(accountID: 7, epoch: 2, storageNamespace: "team-config")
            case "logout": owner.session = nil
            case "restore": model.saveLocal(); await model.load(force: true); model.restore()
            case "aba": let same = model.draft; model.draft = same
            case "leave": model.leave()
            default: controller.retire()
            }
            let before = ProjectEditPendingMaterials.exactData(model.draft)
            controller.selectMaximum(2, in: original); XCTAssertFalse(controller.apply(original), action)
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before)
        }
    }
    func testOldCloseAndApplyCannotAffectNewPresentation() async throws {
        let (controller, _, _) = try await setup(); let first = try open(controller); controller.close(first)
        let second = try open(controller); controller.close(first); XCTAssertFalse(controller.apply(first)); XCTAssertEqual(controller.presentation?.id, second.id)
    }
    func testUnsupportedWireValueIsReadOnlyAndNeverRepairedImplicitly() async throws {
        let (controller, _, _) = try await setup(); controller.model.draft.preserved["teamMode"] = .string("future")
        let before = ProjectEditPendingMaterials.exactData(controller.model.draft), original = try open(controller)
        XCTAssertTrue(try XCTUnwrap(controller.buffer).readOnly); controller.selectMode(.off, in: original)
        XCTAssertFalse(controller.apply(original)); XCTAssertEqual(ProjectEditPendingMaterials.exactData(controller.model.draft), before)
    }
    func testExactDraftChangeRetiresBufferBeforeFurtherUse() async throws {
        let (controller, _, _) = try await setup(); let original = try open(controller)
        controller.model.draft.name += " changed"; controller.synchronize()
        XCTAssertNil(controller.presentation); XCTAssertNil(controller.buffer); XCTAssertFalse(controller.apply(original))
    }
}

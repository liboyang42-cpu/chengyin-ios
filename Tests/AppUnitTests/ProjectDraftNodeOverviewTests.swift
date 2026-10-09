import XCTest
@testable import Questify

@MainActor final class ProjectDraftNodeOverviewTests: XCTestCase {
    private final class Owner { var session: ProjectEditSession? = try? .init(accountID: 7, epoch: 1, storageNamespace: "node-overview") }
    private func setup(product: ProjectEditProduct = .city, scope: ProjectEditScope = .full) async throws -> (ProjectDraftNodeOverviewController, Owner, ProjectEditMemoryStorage) {
        let owner = Owner(), storage = ProjectEditMemoryStorage(); var draft = ProjectEditSyntheticFixtures.draft(product: product)
        draft.chapters[0].id = "chapter"; draft.chapters[0].nodes[0].id = "node"
        let initial = ProjectEditSnapshot(topicID: scope == .whitelist ? 101 : nil, scope: scope, draft: draft)
        let model = ProjectEditModel(coordinator: .init(initial: initial, service: ProjectEditSyntheticService(snapshot: initial), store: .init(storage: storage), currentSession: { owner.session }))
        await model.load(); return (.init(model: model), owner, storage)
    }
    private func open(_ controller: ProjectDraftNodeOverviewController) throws -> ProjectDraftNodeOverviewController.Opening {
        controller.open(try XCTUnwrap(controller.capture(controller.projection))); return try XCTUnwrap(controller.opening)
    }
    private func choose(_ controller: ProjectDraftNodeOverviewController, _ opening: ProjectDraftNodeOverviewController.Opening) throws -> ProjectDraftNodeOverviewController.Destination {
        let projection = controller.projection, capture = try XCTUnwrap(controller.capture(projection))
        controller.choose(try XCTUnwrap(projection.rows.first).id, captured: capture, in: opening); return try XCTUnwrap(controller.destination)
    }
    func testOpenCloseNeverMutateDraftRevisionOrStorage() async throws {
        let (controller, _, storage) = try await setup(), model = controller.model
        let before = ProjectEditPendingMaterials.exactData(model.draft), revision = model.draftMutationRevision, saved = storage.data
        let original = try open(controller); controller.close(original)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before); XCTAssertEqual(model.draftMutationRevision, revision); XCTAssertEqual(storage.data, saved)
    }
    func testBothProductsActivateTheirExactExistingTargetWithoutMutating() async throws {
        for product in [ProjectEditProduct.city, .freeExplore] {
            let (controller, _, storage) = try await setup(product: product), before = ProjectEditPendingMaterials.exactData(controller.model.draft), saved = storage.data
            let opening = try open(controller), destination = try choose(controller, opening)
            XCTAssertEqual(destination.capture.lease.product, product); XCTAssertEqual(destination.row.chapterID, "chapter"); XCTAssertEqual(destination.row.nodeID, "node")
            XCTAssertTrue(controller.activate(destination)); XCTAssertTrue(controller.isDestinationPresented(destination)); XCTAssertFalse(controller.activate(destination))
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(controller.model.draft), before); XCTAssertEqual(storage.data, saved)
        }
    }
    func testStaleRenderedOpeningAndSameByteABAFailClosed() async throws {
        for changed in [false, true] {
            let (controller, _, _) = try await setup(), model = controller.model, capture = try XCTUnwrap(controller.capture(controller.projection))
            if changed { model.draft.name += "!" } else { let same = model.draft; model.draft = same }
            controller.open(capture); XCTAssertNil(controller.opening)
        }
    }
    func testStaleRowClickAndPreactivationABARejectChildMount() async throws {
        let (controller, _, _) = try await setup(), opening = try open(controller), model = controller.model
        let projection = controller.projection, capture = try XCTUnwrap(controller.capture(projection)); model.draft.name += "!"
        controller.choose(projection.rows[0].id, captured: capture, in: opening); XCTAssertNil(controller.destination)
        let destination = try choose(controller, opening); let same = model.draft; model.draft = same
        XCTAssertFalse(controller.activate(destination)); XCTAssertFalse(controller.isDestinationPresented(destination))
    }
    func testInvalidCoordinateStillOpensItsExistingEditorForCorrection() async throws {
        let (controller, _, _) = try await setup(); controller.model.draft.chapters[0].nodes[0].longitude = "NaN"
        let opening = try open(controller), destination = try choose(controller, opening)
        XCTAssertEqual(destination.row.coordinates, .invalid); XCTAssertTrue(controller.activate(destination))
    }
    func testActiveChildTextEditsStayOpenButIdentityABADeletionOrReorderRetire() async throws {
        for kind in ["delete", "aba", "reorder"] {
            let (controller, _, _) = try await setup(), model = controller.model, opening = try open(controller), destination = try choose(controller, opening)
            XCTAssertTrue(controller.activate(destination)); model.draft.chapters[0].nodes[0].name += "!"
            XCTAssertTrue(controller.isDestinationPresented(destination))
            switch kind {
            case "delete": model.draft.chapters[0].nodes = []
            case "reorder": var other = ProjectEditNode(); other.id = "other"; model.draft.chapters[0].nodes.insert(other, at: 0)
            default: let old = model.draft.chapters[0].nodes; model.draft.chapters[0].nodes = []; model.draft.chapters[0].nodes = old
            }
            XCTAssertFalse(controller.isDestinationPresented(destination))
        }
    }
    func testWhitelistAccountEpochRestoreAndRevokedVisitRejectChildActivation() async throws {
        let (locked, _, _) = try await setup(scope: .whitelist); XCTAssertNil(locked.capture(locked.projection))
        for kind in ["account", "epoch", "restore", "revoke"] {
            let (controller, owner, _) = try await setup(), model = controller.model, opening = try open(controller), destination = try choose(controller, opening)
            switch kind {
            case "restore": model.saveLocal(); await model.load(force: true); model.restore()
            case "revoke": model.coordinator.beginEditorVisit(UUID())
            default: owner.session = try .init(accountID: kind == "account" ? 8 : 7, epoch: 2, storageNamespace: "node-overview")
            }
            XCTAssertFalse(controller.activate(destination)); XCTAssertFalse(controller.isDestinationPresented(destination)); XCTAssertFalse(controller.isPresented(opening))
        }
    }
    func testCaptureFromAnotherControllerCannotOpenOrChoose() async throws {
        let (controller, _, _) = try await setup(), other = ProjectDraftNodeOverviewController(model: controller.model)
        let foreign = try XCTUnwrap(other.capture(other.projection)); controller.open(foreign); XCTAssertNil(controller.opening)
        let opening = try open(controller); controller.choose(foreign.projection.rows[0].id, captured: foreign, in: opening); XCTAssertNil(controller.destination)
    }
    func testOldDismissalCannotCloseNewOverviewOrNewDestination() async throws {
        let (controller, _, _) = try await setup(), old = try open(controller), oldBinding = controller.binding(old)
        controller.close(old); let current = try open(controller); oldBinding.wrappedValue = nil; XCTAssertEqual(controller.opening?.id, current.id)
        let oldDestination = try choose(controller, current), binding = controller.destinationBinding(oldDestination)
        controller.closeDestination(oldDestination); let next = try choose(controller, current); binding.wrappedValue = nil; controller.closeDestination(oldDestination)
        XCTAssertEqual(controller.destination?.id, next.id); XCTAssertTrue(controller.activate(next))
    }
    func testNavigationRetirementRejectsLateCallbacks() async throws {
        let (controller, _, _) = try await setup(), opening = try open(controller), destination = try choose(controller, opening)
        controller.retire(); XCTAssertFalse(controller.activate(destination)); XCTAssertFalse(controller.isPresented(opening)); XCTAssertFalse(controller.isDestinationPresented(destination))
    }
    func testDuplicateIdentityAndPendingOnlyNeverChooseAnArbitraryNode() async throws {
        let (controller, _, _) = try await setup(), model = controller.model
        model.draft.chapters[0].nodes.append(model.draft.chapters[0].nodes[0]); XCTAssertNil(controller.capture(controller.projection))
        let node = model.draft.chapters[0].nodes[0]; model.draft.chapters[0].nodes = []; model.draft.pendingMaterials = [.init(node: node)]
        let opening = try open(controller), capture = try XCTUnwrap(controller.capture(controller.projection))
        controller.choose(.init(chapterID: "chapter", nodeID: "node"), captured: capture, in: opening); XCTAssertNil(controller.destination)
        XCTAssertEqual(controller.projection.excludedPendingCount, 1); XCTAssertTrue(controller.projection.rows.isEmpty)
    }
}

import XCTest
@testable import Questify

@MainActor final class ProjectEditStarterControllerTests: XCTestCase {
    private final class Owner { var session: ProjectEditSession?; init() throws { session = try .init(accountID: 901, epoch: 1, storageNamespace: "starter-fixture") } }
    private func setup(_ product: ProjectEditProduct = .city, initial: ProjectEditSnapshot? = nil, scenario: ProjectEditSyntheticService.Scenario = .accepted) async throws -> (ProjectEditModel, ProjectEditStarterController, Owner, ProjectEditLocalStore, ProjectEditSyntheticService) {
        let owner = try Owner(), base = initial ?? ProjectEditSnapshot(draft: .init(product: product))
        let service = ProjectEditSyntheticService(scenario: scenario, snapshot: base), store = ProjectEditLocalStore(storage: ProjectEditMemoryStorage())
        let coordinator = ProjectEditCoordinator(initial: base, service: service, store: store, currentSession: { owner.session })
        let model = ProjectEditModel(coordinator: coordinator); await model.load()
        return (model, .init(model: model), owner, store, service)
    }
    private func validNode(_ controller: ProjectEditStarterController, _ target: ProjectEditStarterController.Destination) -> ProjectEditNode {
        var node = controller.node(for: target).wrappedValue
        node.name = "  Node e\u{301}\n"; node.description = "Raw detail\t"; node.longitude = "121.5"; node.latitude = "31.2"
        node.localMetadata["future"] = .string("untouched"); return node
    }
    func testCityArrivalBindsJustCreatedChapterAndQueuedStarterCannotDuplicateIt() async throws {
        let (model, controller, _, _, service) = try await setup(), opening = try XCTUnwrap(model.captureStarterLease())
        controller.createChapter(lease: opening, name: "Chapter 1"); let destination = try XCTUnwrap(controller.destination)
        XCTAssertEqual(destination.kind, .story); XCTAssertEqual(model.draft.chapters.count, 1)
        XCTAssertEqual(destination.chapterID, model.draft.chapters[0].id); XCTAssertEqual(model.draft.chapters[0].blocks, [])
        controller.createChapter(lease: opening, name: "Queued duplicate"); XCTAssertEqual(model.draft.chapters.count, 1)
        let binding = model.starterChapter(destination); var chapter = binding.wrappedValue
        XCTAssertThrowsError(try chapter.addNode(product: .city))
        chapter.blocks = [.init(kind: .text, content: "Real story")]; binding.wrappedValue = chapter
        XCTAssertTrue(model.draft.chapters[0].hasRealStory)
        controller.close(destination); chapter.name = "Late write"; binding.wrappedValue = chapter
        XCTAssertEqual(model.draft.chapters[0].name, "Chapter 1"); XCTAssertTrue(service.submissions.isEmpty)
    }
    func testFreeCancelKeepsEmptyChapterInRealLocalStoreAndDoesNotRepeatFirstNodeForLaterChapters() async throws {
        let (model, controller, owner, store, service) = try await setup(.freeExplore)
        controller.createChapter(lease: model.captureStarterLease(), name: "Chapter 1"); let destination = try XCTUnwrap(controller.destination)
        XCTAssertEqual(destination.kind, .firstNode); XCTAssertNil(model.draft.chapters[0].blocks)
        let binding = controller.node(for: destination); binding.wrappedValue = validNode(controller, destination)
        controller.close(destination); controller.finish(destination); model.saveLocal()
        let identity = try XCTUnwrap(model.coordinator.identity)
        guard case .ready(let envelope) = store.load(session: try XCTUnwrap(owner.session), identity: identity, baseline: .init(product: .freeExplore)) else { return XCTFail("Saved draft must exist") }
        XCTAssertEqual(envelope.draft.chapters.count, 1); XCTAssertTrue(envelope.draft.chapters[0].nodes.isEmpty)
        controller.createChapter(lease: model.captureStarterLease(), name: "Chapter 2")
        XCTAssertEqual(model.draft.chapters.count, 2); XCTAssertNil(controller.destination); XCTAssertTrue(service.submissions.isEmpty)
    }
    func testFreeFinishCommitsOnlyValidCandidateOnceToExactLocalChapterAndPreservesBytes() async throws {
        let (model, controller, _, _, service) = try await setup(.freeExplore)
        controller.createChapter(lease: model.captureStarterLease(), name: "Chapter 1"); let destination = try XCTUnwrap(controller.destination)
        controller.finish(destination); XCTAssertTrue(model.draft.chapters[0].nodes.isEmpty); XCTAssertNotNil(controller.destination)
        let node = validNode(controller, destination); controller.node(for: destination).wrappedValue = node
        XCTAssertTrue(controller.canFinish(destination)); controller.finish(destination); controller.finish(destination)
        XCTAssertNil(controller.destination); XCTAssertEqual(model.draft.chapters[0].nodes.count, 1)
        XCTAssertEqual(model.draft.chapters[0].nodes[0], node); XCTAssertEqual(Array(model.draft.chapters[0].nodes[0].name.utf8), Array(node.name.utf8))
        XCTAssertNil(model.draft.chapters[0].blocks); XCTAssertTrue(service.submissions.isEmpty)
    }
    func testOldDismissalAndRetainedChapterBindingCannotTargetNewDestination() async throws {
        let (model, controller, _, _, _) = try await setup()
        controller.createChapter(lease: model.captureStarterLease(), name: "One"); let old = try XCTUnwrap(controller.destination), binding = model.starterChapter(old)
        var chapter = binding.wrappedValue; controller.close(old)
        controller.createChapter(lease: model.captureStarterLease(), name: "Two"); let current = try XCTUnwrap(controller.destination)
        controller.close(old); controller.finish(old); chapter.name = "Wrong chapter"; binding.wrappedValue = chapter
        XCTAssertEqual(controller.destination?.id, current.id); XCTAssertEqual(model.draft.chapters.map(\.name), ["One", "Two"])
    }
    func testOldNodeSheetDismissalAndQueuedFieldsCannotOverwriteReplacementCandidate() async throws {
        let (model, controller, _, _, service) = try await setup(.freeExplore)
        controller.createChapter(lease: model.captureStarterLease(), name: "Old"); let old = try XCTUnwrap(controller.destination)
        let binding = controller.node(for: old), oldNode = validNode(controller, old)
        binding.wrappedValue = oldNode; controller.close(old); model.draft.chapters.removeAll()
        controller.createChapter(lease: model.captureStarterLease(), name: "New"); let current = try XCTUnwrap(controller.destination)
        var newNode = validNode(controller, current); newNode.name = "Replacement"
        controller.node(for: current).wrappedValue = newNode
        controller.close(old); binding.wrappedValue = oldNode; controller.finish(old)
        XCTAssertEqual(controller.destination?.id, current.id); XCTAssertEqual(controller.candidate, newNode)
        XCTAssertTrue(model.draft.chapters[0].nodes.isEmpty); controller.finish(current)
        XCTAssertEqual(model.draft.chapters[0].nodes.map(\.name), ["Replacement"]); XCTAssertTrue(service.submissions.isEmpty)
    }
    func testLifecycleModeAndTopologyABAInvalidateCapturedStarterAndPendingNode() async throws {
        for action in ["reload", "restore", "discard", "leave", "account", "modeABA", "deleteABA", "reorder"] {
            let (model, controller, owner, _, service) = try await setup(.freeExplore)
            controller.createChapter(lease: model.captureStarterLease(), name: "One"); let destination = try XCTUnwrap(controller.destination)
            let candidate = validNode(controller, destination), binding = controller.node(for: destination)
            binding.wrappedValue = candidate
            switch action {
            case "reload": await model.load(force: true)
            case "restore": model.restore()
            case "discard": model.discard()
            case "leave": model.leave()
            case "account": owner.session = try .init(accountID: 902, epoch: 2, storageNamespace: "starter-fixture")
            case "modeABA": model.draft.product = .city; model.draft.product = .freeExplore
            case "deleteABA": let chapter = model.draft.chapters.removeFirst(); model.draft.chapters.append(chapter)
            default: model.draft.chapters.append(.init()); model.draft.chapters.reverse()
            }
            let before = model.draft
            binding.wrappedValue = candidate; controller.finish(destination); controller.createChapter(lease: destination.lease, name: "Stale")
            XCTAssertFalse(controller.isCurrent(destination)); XCTAssertEqual(model.draft, before, action)
            XCTAssertTrue(service.submissions.isEmpty)
        }
    }
    func testWhitelistAndUnknownWriteLockCannotUseCapturedCreationAction() async throws {
        let (limited, limitedController, _, _, _) = try await setup(initial: ProjectEditSyntheticFixtures.snapshot(scope: .whitelist))
        XCTAssertNil(limited.captureStarterLease()); limitedController.createChapter(lease: nil, name: "Denied")
        XCTAssertEqual(limited.draft.chapters.count, 1)
        let base = ProjectEditSnapshot(draft: ProjectEditSyntheticFixtures.draft())
        let (model, controller, _, _, service) = try await setup(initial: base, scenario: .unknown)
        let lease = try XCTUnwrap(model.captureStarterLease())
        model.coordinator.prepare(model.draft); let review = try XCTUnwrap(model.coordinator.confirmation)
        await model.coordinator.confirm(review); XCTAssertTrue(model.coordinator.isLocked)
        controller.createChapter(lease: lease, name: "Denied")
        XCTAssertNil(controller.destination); XCTAssertEqual(model.draft.chapters.count, 1); XCTAssertEqual(service.submissions.count, 1)
    }
    func testRetainedActualAddNodeButtonActionRejectsOpeningChange() async throws {
        for product in [ProjectEditProduct.city, .freeExplore] {
            let (model, _, _, _, service) = try await setup(product)
            var chapter = ProjectEditChapter(); chapter.description = "Real story"
            chapter.blocks = [.init(kind: .text, content: "Real story")]
            XCTAssertTrue(chapter.hasRealStory)
            model.draft.chapters = [chapter]
            let view = ProjectEditChapterView(model: model, chapterID: chapter.id)
            let oldButtonAction = view.addNode
            oldButtonAction(); XCTAssertEqual(model.draft.chapters[0].nodes.count, 1)
            model.draft.chapters = [chapter]
            model.draft.chapters[0].preserved["opening"] = .bool(true)
            XCTAssertTrue(model.draft.chapters[0].hasRealStory)
            let original = model.draft
            oldButtonAction()
            XCTAssertEqual(model.draft, original); XCTAssertTrue(model.draft.chapters[0].nodes.isEmpty)
            model.draft.chapters[0].preserved["opening"] = .bool(false)
            oldButtonAction(); XCTAssertEqual(model.draft.chapters[0].nodes.count, 1)
            XCTAssertTrue(service.submissions.isEmpty)
        }
    }

}

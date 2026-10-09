import XCTest
@testable import Questify

@MainActor final class ProjectEditIssueNavigationTests: XCTestCase {
    private final class Owner {
        var session: ProjectEditSession? = try! .init(accountID: 901, epoch: 1, storageNamespace: "issue-location")
    }
    private final class Storage: ProjectEditDataStorage {
        var writes = 0
        func read(_ key: String) throws -> Data? { nil }
        func write(_ value: Data, key: String) throws { writes += 1 }
        func remove(_ key: String) throws {}
    }
    private func setup() async throws -> (ProjectEditIssueNavigation, Owner, Storage) {
        let owner = Owner(), storage = Storage()
        var draft = ProjectEditSyntheticFixtures.draft(product: .freeExplore)
        draft.name = ""; draft.chapters[0].nodes[0].name = ""
        var ticket = ProjectEditTicket(); ticket.id = "ticket-901-3"; ticket.price = ""
        draft.tickets = [ticket]
        let initial = ProjectEditSnapshot(draft: draft), service = ProjectEditSyntheticService(snapshot: initial)
        let model = ProjectEditModel(coordinator: .init(initial: initial, service: service,
            store: ProjectEditLocalStore(storage: storage), currentSession: { owner.session }))
        await model.load(); return (.init(model: model), owner, storage)
    }
    private func capture(_ id: String, _ controller: ProjectEditIssueNavigation) throws -> ProjectEditIssueNavigation.Capture {
        let issues = ProjectEditValidation.issues(controller.model.draft)
        return try XCTUnwrap(controller.rows(issues).first { $0.issue.id == id }?.capture)
    }
    func testKnownIssueOpensExactExistingTargetWithoutChangingOrSavingDraft() async throws {
        let (controller, _, storage) = try await setup(), model = controller.model
        let before = ProjectEditPendingMaterials.exactData(model.draft), nodeID = model.draft.chapters[0].nodes[0].id
        controller.open(try capture("nodeName" + nodeID, controller))
        let destination = try XCTUnwrap(controller.destination)
        XCTAssertEqual(destination.capture.location, .node(chapterID: model.draft.chapters[0].id, nodeID: nodeID, anchor: "project-issue-anchor-nodeName"))
        XCTAssertTrue(controller.isPresented(destination))
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before); XCTAssertEqual(storage.writes, 0)
    }
    func testSameBytesABAReorderAndFixedIssueRejectTheOldRenderedAction() async throws {
        for action in ["aba", "reorder", "fixed"] {
            let (controller, _, storage) = try await setup(), old = try capture("name", controller)
            switch action {
            case "aba": let same = controller.model.draft; controller.model.draft = same
            case "reorder": var chapter = ProjectEditChapter(); chapter.id = "new"; controller.model.draft.chapters.insert(chapter, at: 0)
            default: controller.model.draft.name = "Fixed"
            }
            controller.open(old)
            XCTAssertNil(controller.rootRequest); XCTAssertNil(controller.destination); XCTAssertTrue(controller.stale)
            XCTAssertEqual(storage.writes, 0)
        }
    }
    func testAccountEpochSignOutAndEditorRetirementRejectCapturedRows() async throws {
        for action in ["account", "epoch", "signOut", "incarnation", "controller"] {
            let (controller, owner, storage) = try await setup(), old = try capture("name", controller)
            switch action {
            case "account": owner.session = try .init(accountID: 902, epoch: 1, storageNamespace: "issue-location")
            case "epoch": owner.session = try .init(accountID: 901, epoch: 2, storageNamespace: "issue-location")
            case "signOut": owner.session = nil
            case "incarnation": controller.model.invalidateStarterLease()
            default: controller.retire()
            }
            controller.open(old)
            XCTAssertNil(controller.rootRequest); XCTAssertNil(controller.destination); XCTAssertEqual(storage.writes, 0)
        }
    }
    func testDestinationSurvivesValidFieldEditsButNotTargetDeletion() async throws {
        let (controller, _, _) = try await setup(), model = controller.model
        let nodeID = model.draft.chapters[0].nodes[0].id
        controller.open(try capture("nodeName" + nodeID, controller))
        let destination = try XCTUnwrap(controller.destination)
        model.draft.chapters[0].nodes[0].name = "Now valid"
        XCTAssertTrue(controller.isPresented(destination), "Editing the resolved destination must not pop on each keystroke.")
        model.draft.chapters[0].nodes.removeAll { $0.id == nodeID }
        XCTAssertFalse(controller.isPresented(destination)); XCTAssertNil(controller.binding(destination).wrappedValue)
    }
    func testRemoveThenReinsertSameNodeIdentityCannotReviveAnOpenDestination() async throws {
        let (controller, _, _) = try await setup(), model = controller.model
        let node = model.draft.chapters[0].nodes[0]
        controller.open(try capture("nodeName" + node.id, controller))
        let original = try XCTUnwrap(controller.destination)
        model.draft.chapters[0].nodes.removeAll { $0.id == node.id }
        model.draft.chapters[0].nodes.append(node)
        XCTAssertFalse(controller.isPresented(original))
    }
    func testChapterDestinationRemainsOpenWhenAddingTheNodeItWasMissing() async throws {
        let (controller, _, _) = try await setup(), model = controller.model
        model.draft.chapters[0].nodes = []
        controller.open(try capture("nodes0", controller))
        let original = try XCTUnwrap(controller.destination)
        var node = ProjectEditNode(); node.name = "Added here"
        model.draft.chapters[0].nodes.append(node)
        XCTAssertTrue(controller.isPresented(original))
    }
    func testOldDismissalCannotCloseNewDestinationAndRepeatedRootTapGetsFreshScrollRequest() async throws {
        let (controller, _, _) = try await setup(), model = controller.model
        controller.open(try capture("nodeName" + model.draft.chapters[0].nodes[0].id, controller))
        let old = try XCTUnwrap(controller.destination)
        controller.open(try capture("priceticket-901-3", controller))
        let current = try XCTUnwrap(controller.destination)
        controller.close(old); XCTAssertEqual(controller.destination?.id, current.id)
        let root = try capture("name", controller); controller.open(root)
        let first = try XCTUnwrap(controller.rootRequest?.id); controller.open(root)
        XCTAssertNotEqual(controller.rootRequest?.id, first)
    }
    func testUnknownOrAlreadyFixedRowsHaveNoClickableCapture() async throws {
        let (controller, _, _) = try await setup()
        let old = try capture("name", controller).issue
        controller.model.draft.name = "Fixed"
        let rows = controller.rows([old, .init("unknown", "projectEdit.validation.name"), .init("name", "invented")])
        XCTAssertTrue(rows.allSatisfy { $0.capture == nil })
        XCTAssertNil(controller.destination); XCTAssertNil(controller.rootRequest)
    }
}

import XCTest
@testable import Questify

@MainActor final class ProjectNodeRouteMappingEditorTests: XCTestCase {
    private final class Owner { var session: ProjectEditSession? = try? .init(accountID: 7, epoch: 1, storageNamespace: "route-mapping") }
    private func setup(scope: ProjectEditScope = .full) async throws -> (ProjectNodeRouteMappingController, Owner, ProjectEditMemoryStorage) {
        let owner = Owner(), storage = ProjectEditMemoryStorage(); var draft = ProjectEditSyntheticFixtures.draft()
        draft.preserved["publishMode"] = .string("pro"); draft.preserved["routeMode"] = .string("BRANCH_GRAPH")
        draft.preserved["routeGraphJson"] = .string(#"{ "schemaVersion":1,"startNodeId":1,"terminalNodeIds":[4],"edges":[{"id":"a","fromNodeId":1,"toNodeId" : 2,"trigger":{"type":"CHOICE","outcomeCode":"COMPLETED"}},{"id":"b","fromNodeId":2,"toNodeId":3,"trigger":{"type":"CHOICE","outcomeCode":"COMPLETED"}},{"id":"c","fromNodeId":3,"toNodeId":4,"trigger":{"type":"CHOICE","outcomeCode":"COMPLETED"}}],"fallbacks":[{"fromNodeId":1,"toNodeId":2}] }"#)
        draft.chapters[0].id = "chapter"; draft.chapters[0].nodes = (1...4).map { id in
            var node = ProjectEditNode(); node.id = "node\(id)"; node.name = "Node \(id)"; node.templateID = 40 + id
            node.localMetadata = ["id": .number(Decimal(id)), "templateInfo": .object(["id": .number(Decimal(40 + id)), "validationMethod": .number(0)])]; return node
        }
        let initial = ProjectEditSnapshot(topicID: scope == .whitelist ? 101 : nil, scope: scope, draft: draft)
        let model = ProjectEditModel(coordinator: .init(initial: initial, service: ProjectEditSyntheticService(snapshot: initial),
            store: .init(storage: storage), currentSession: { owner.session }))
        await model.load(); return (.init(model: model, chapterID: "chapter", nodeID: "node1"), owner, storage)
    }
    private func open(_ controller: ProjectNodeRouteMappingController) throws -> ProjectNodeRouteMappingController.Presentation {
        controller.open(edgeID: "a"); return try XCTUnwrap(controller.presentation)
    }
    func testOpenCancelAndNoOpRetainRawDraftRevisionAndStorage() async throws {
        let (controller, _, storage) = try await setup(), model = controller.model
        let before = ProjectEditPendingMaterials.exactData(model.draft), revision = model.draftMutationRevision, saved = storage.data
        let cancelled = try open(controller); controller.close(cancelled)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before); XCTAssertEqual(model.draftMutationRevision, revision)
        let original = try open(controller); XCTAssertTrue(controller.apply(targetID: 2, original: original))
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before); XCTAssertEqual(model.draftMutationRevision, revision)
        XCTAssertEqual(storage.data, saved); XCTAssertNil(controller.presentation)
    }
    func testSingleApplyUsesExistingSaveRestoreAndCannotApplyTwice() async throws {
        let (controller, _, storage) = try await setup(), model = controller.model
        let raw = try XCTUnwrap(model.draft.preserved["routeGraphJson"]?.text), revision = model.draftMutationRevision
        let original = try open(controller); XCTAssertTrue(controller.apply(targetID: 3, original: original))
        let expected = raw.replacingOccurrences(of: #""toNodeId" : 2"#, with: #""toNodeId" : 3"#)
        XCTAssertEqual(model.draft.preserved["routeGraphJson"]?.text, expected); XCTAssertEqual(model.draftMutationRevision, revision + 1)
        XCTAssertFalse(controller.apply(targetID: 4, original: original)); XCTAssertEqual(model.draftMutationRevision, revision + 1)
        model.saveLocal(); XCTAssertFalse(storage.data.isEmpty)
        await model.load(force: true); model.restore(); XCTAssertEqual(model.draft.preserved["routeGraphJson"]?.text, expected)
    }
    func testDeletedReorderedSourceChangedGraphChangedAndSameByteABARejectConfirmation() async throws {
        for action in ["delete", "reorder", "source", "graph", "aba"] {
            let (controller, _, _) = try await setup(), model = controller.model, original = try open(controller)
            switch action {
            case "delete": model.draft.chapters[0].nodes.removeLast()
            case "reorder": model.draft.chapters[0].nodes.reverse()
            case "source": model.draft.chapters[0].nodes[0].templateID = 99
            case "graph": model.draft.preserved["routeGraphJson"] = .string("{}")
            default: let same = model.draft; model.draft = same
            }
            let before = ProjectEditPendingMaterials.exactData(model.draft), revision = model.draftMutationRevision
            XCTAssertFalse(controller.apply(targetID: 3, original: original), action)
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before); XCTAssertEqual(model.draftMutationRevision, revision)
        }
    }
    func testAccountEpochRestoreAndWhitelistCannotRetarget() async throws {
        let (locked, _, _) = try await setup(scope: .whitelist); locked.open(edgeID: "a"); XCTAssertNil(locked.presentation)
        for action in ["account", "epoch", "restore", "incarnation"] {
            let (controller, owner, _) = try await setup(), model = controller.model, original = try open(controller)
            switch action {
            case "restore": model.saveLocal(); await model.load(force: true); model.restore()
            case "incarnation": model.invalidateStarterLease()
            default: owner.session = try .init(accountID: action == "account" ? 8 : 7, epoch: 2, storageNamespace: "route-mapping")
            }
            let before = ProjectEditPendingMaterials.exactData(model.draft)
            XCTAssertFalse(controller.apply(targetID: 3, original: original)); XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before)
        }
    }
    func testOldDismissalCannotCloseNewSheetAndNavigationRetiresIt() async throws {
        let (controller, _, _) = try await setup(), old = try open(controller), binding = controller.binding(old)
        controller.close(old); let next = try open(controller); binding.wrappedValue = nil; controller.close(old)
        XCTAssertEqual(controller.presentation?.id, next.id)
        controller.retire(); XCTAssertFalse(controller.apply(targetID: 3, original: next)); XCTAssertNil(controller.presentation)
    }
    func testUnsafeAndInventedDestinationsCannotBeApplied() async throws {
        let (controller, _, storage) = try await setup(), original = try open(controller)
        let before = ProjectEditPendingMaterials.exactData(controller.model.draft), saved = storage.data
        XCTAssertEqual(try XCTUnwrap(original.targets.first { $0.id == 1 }).reason, .cycle)
        XCTAssertFalse(controller.apply(targetID: 1, original: original)); XCTAssertFalse(controller.apply(targetID: 999, original: original))
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(controller.model.draft), before); XCTAssertEqual(storage.data, saved)
        XCTAssertEqual(controller.presentation?.id, original.id)
    }
}

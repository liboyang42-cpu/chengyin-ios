import XCTest
@testable import Questify

@MainActor final class ProjectNodeNarrativeControllerTests: XCTestCase {
    private final class Owner {
        var session: ProjectEditSession?
        init() throws { session = try .init(accountID: 901, epoch: 1, storageNamespace: "node-narrative") }
    }
    private final class Storage: ProjectEditDataStorage {
        var data: [String: Data] = [:]; var writes = 0; var failAt: Int?
        func read(_ key: String) throws -> Data? { data[key] }
        func write(_ value: Data, key: String) throws {
            writes += 1; if writes == failAt { throw ProjectEditError.persistenceUnavailable }; data[key] = value
        }
        func remove(_ key: String) throws { data[key] = nil }
    }
    private func setup(scope: ProjectEditScope = .full) async throws -> (ProjectEditModel, ProjectNodeNarrativeController, Owner, ProjectEditLocalStore, Storage, ProjectEditSyntheticService) {
        let owner = try Owner(), storage = Storage(), store = ProjectEditLocalStore(storage: storage)
        var initial = ProjectEditSnapshot(scope: scope, draft: ProjectEditSyntheticFixtures.draft(product: .freeExplore))
        initial.draft.chapters[0].nodes[0].description = "First paragraph\n\nSecond paragraph"
        initial.draft.chapters[0].nodes[0].localMetadata = ["hookText": .string("First paragraph\n\nSecond paragraph"),
            "cardHookLong": .string("A longer hook"), "fragmentText": .string("A fragment"), "future": .array([.null, .bool(true)])]
        var other = initial.draft.chapters[0].nodes[0]; other.id = "other-node"; other.name = "Other node"
        initial.draft.chapters[0].nodes.append(other)
        let service = ProjectEditSyntheticService(snapshot: initial)
        let model = ProjectEditModel(coordinator: .init(initial: initial, service: service, store: store, currentSession: { owner.session }))
        await model.load()
        return (model, .init(model: model, chapterID: model.draft.chapters[0].id, nodeID: model.draft.chapters[0].nodes[0].id), owner, store, storage, service)
    }
    private func open(_ controller: ProjectNodeNarrativeController) throws -> ProjectNodeNarrativeController.Destination {
        controller.open(controller.capture(chapterID: controller.hostIdentity.chapterID, nodeID: controller.hostIdentity.nodeID))
        return try XCTUnwrap(controller.destination)
    }
    private func stored(_ model: ProjectEditModel, _ owner: Owner, _ store: ProjectEditLocalStore) throws -> ProjectEditDraft {
        guard case .ready(let envelope) = store.load(session: try XCTUnwrap(owner.session), identity: try XCTUnwrap(model.coordinator.identity), baseline: try XCTUnwrap(model.coordinator.snapshot).draft) else { throw ProjectEditError.persistenceUnavailable }
        return envelope.draft
    }
    func testOpeningCancellationAndColdRestoreNeverMigrateLegacyFields() async throws {
        let (model, controller, owner, store, storage, service) = try await setup()
        model.saveLocal(); let original = model.draft, writes = storage.writes, opening = try open(controller)
        XCTAssertEqual(controller.text, "First paragraph\n\nSecond paragraph\nA longer hook\nA fragment")
        controller.binding(opening).wrappedValue = "Uncommitted text"; controller.close(opening)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), ProjectEditPendingMaterials.exactData(original))
        XCTAssertEqual(storage.writes, writes); XCTAssertEqual(try stored(model, owner, store), original)
        let fresh = ProjectEditModel(coordinator: .init(initial: try XCTUnwrap(model.coordinator.snapshot), service: service, store: store, currentSession: { owner.session }))
        await fresh.load(); fresh.restore(); XCTAssertEqual(fresh.draft, original); XCTAssertTrue(service.submissions.isEmpty)
    }
    func testExplicitCompletionPersistsOnlyCapturedNodeAndRestoresExactParagraphBytes() async throws {
        let (model, controller, owner, store, _, service) = try await setup()
        let original = model.draft, opening = try open(controller)
        let text = "  Edited e\u{301}\n\nA retained paragraph\n"
        controller.binding(opening).wrappedValue = text; controller.save(opening); controller.save(opening)
        XCTAssertNil(controller.destination)
        let saved = try stored(model, owner, store)
        XCTAssertEqual(Array(saved.chapters[0].nodes[0].description.utf8), Array(text.utf8))
        XCTAssertEqual(saved.chapters[0].nodes[1], original.chapters[0].nodes[1])
        XCTAssertEqual(saved.chapters[0].nodes[0].localMetadata["future"], original.chapters[0].nodes[0].localMetadata["future"])
        for field in ProjectNodeNarrative.Field.allCases { XCTAssertEqual(saved.chapters[0].nodes[0].localMetadata[field.rawValue], .string("")) }
        let fresh = ProjectEditModel(coordinator: .init(initial: try XCTUnwrap(model.coordinator.snapshot), service: service, store: store, currentSession: { owner.session }))
        await fresh.load(); fresh.restore(); XCTAssertEqual(fresh.draft, saved)
        fresh.review(); let review = try XCTUnwrap(fresh.confirmation)
        let prepared = try XCTUnwrap(ProjectEditPreparedNodes(payload: review.payload).chapters?.first?.nodes?.first)
        XCTAssertEqual(prepared.value(.description).text.map { Array($0.utf8) }, Array(text.utf8))
        for field in ProjectNodeNarrative.Field.allCases { XCTAssertEqual(prepared.raw.object?[field.rawValue], .string("")) }
        fresh.draft.chapters[0].nodes[0].description = "Later change"
        XCTAssertEqual(prepared.value(.description).text.map { Array($0.utf8) }, Array(text.utf8))
        XCTAssertTrue(service.submissions.isEmpty)
    }
    func testReorderDeleteAndSameBytesABAInvalidateQueuedActionsWithoutRetargeting() async throws {
        for mutation in ["reorder", "delete", "deleteABA", "textABA", "chapterABA"] {
            let (model, controller, _, _, _, service) = try await setup()
            let initial = model.draft, opening = try open(controller), binding = controller.binding(opening)
            binding.wrappedValue = "Queued replacement"
            switch mutation {
            case "reorder": model.draft.chapters[0].nodes.reverse()
            case "delete": model.draft.chapters[0].nodes.removeFirst()
            case "deleteABA": model.draft.chapters[0].nodes.removeFirst(); model.draft.chapters[0].nodes = initial.chapters[0].nodes
            case "textABA": model.draft.chapters[0].nodes[0].name = "Temporary"; model.draft.chapters[0].nodes[0].name = initial.chapters[0].nodes[0].name
            default: model.draft.chapters.removeFirst(); model.draft.chapters = initial.chapters
            }
            let before = ProjectEditPendingMaterials.exactData(model.draft)
            binding.wrappedValue = "Late edit"; controller.save(opening)
            XCTAssertFalse(controller.isCurrent(opening), mutation)
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before, mutation)
            controller.close(opening)
            if mutation == "reorder" {
                let currentController = ProjectNodeNarrativeController(model: model, chapterID: opening.chapterID, nodeID: "other-node")
                let current = try open(currentController); currentController.binding(current).wrappedValue = "Current first node"
                currentController.save(current)
                XCTAssertEqual(model.draft.chapters[0].nodes.first(where: { $0.id == "other-node" })?.description, "Current first node")
                XCTAssertEqual(model.draft.chapters[0].nodes.first(where: { $0.id == opening.nodeID })?.description, initial.chapters[0].nodes[0].description)
            }
            XCTAssertTrue(service.submissions.isEmpty)
        }
    }
    func testAccountLeaveRestoreDiscardAndNewVisitRetireCapturedSave() async throws {
        for action in ["account", "leave", "restore", "discard", "newVisit"] {
            let (model, controller, owner, _, _, service) = try await setup(), opening = try open(controller)
            controller.binding(opening).wrappedValue = "Retired edit"
            switch action {
            case "account": owner.session = try .init(accountID: 902, epoch: 2, storageNamespace: "node-narrative")
            case "leave": model.leave()
            case "restore": model.restore()
            case "discard": model.discard()
            default: model.coordinator.beginEditorVisit(UUID())
            }
            let before = ProjectEditPendingMaterials.exactData(model.draft)
            controller.save(opening); XCTAssertFalse(controller.isCurrent(opening), action)
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before); XCTAssertTrue(service.submissions.isEmpty)
        }
    }
    func testUnknownTypesWhitelistAndPendingSubmissionRemainUnavailable() async throws {
        let (limited, limitedController, _, _, _, _) = try await setup(scope: .whitelist)
        XCTAssertNil(limitedController.capture(chapterID: limited.draft.chapters[0].id, nodeID: limited.draft.chapters[0].nodes[0].id))
        let (model, controller, _, _, _, service) = try await setup()
        let chapterID = model.draft.chapters[0].id, nodeID = model.draft.chapters[0].nodes[0].id
        model.draft.chapters[0].nodes[0].localMetadata["hookText"] = .object(["future": .bool(true)])
        XCTAssertNil(controller.capture(chapterID: chapterID, nodeID: nodeID))
        model.draft.chapters[0].nodes[0].localMetadata["hookText"] = .null
        let opening = try open(controller); service.scenario = .unknown
        model.coordinator.prepare(model.draft); let review = try XCTUnwrap(model.coordinator.confirmation)
        await model.coordinator.confirm(review); let before = model.draft
        controller.save(opening); XCTAssertFalse(controller.isCurrent(opening)); XCTAssertEqual(model.draft, before)
    }
    func testFailedEnvelopeOrPointerSaveRetainsCandidateAndSafeRetryDoesNotDuplicate() async throws {
        for offset in [1, 2] {
            let (model, controller, owner, store, storage, service) = try await setup()
            model.saveLocal(); let before = model.draft, opening = try open(controller)
            controller.binding(opening).wrappedValue = "Retry exact candidate"
            storage.failAt = storage.writes + offset; controller.save(opening)
            XCTAssertTrue(controller.saveUnconfirmed); XCTAssertEqual(controller.destination?.id, opening.id)
            XCTAssertEqual(controller.text, "Retry exact candidate"); XCTAssertEqual(model.draft, before)
            if offset == 1 { XCTAssertEqual(try stored(model, owner, store), before) }
            else { XCTAssertEqual(try stored(model, owner, store).chapters[0].nodes[0].description, "Retry exact candidate") }
            storage.failAt = nil; controller.save(opening)
            XCTAssertNil(controller.destination); XCTAssertEqual(try stored(model, owner, store).chapters[0].nodes[0].description, "Retry exact candidate")
            XCTAssertEqual(model.draft.chapters[0].nodes.count, before.chapters[0].nodes.count); XCTAssertTrue(service.submissions.isEmpty)
        }
    }
    func testOldDismissalAndOversizedEditCannotClearNewSheetOrTruncateContent() async throws {
        let (model, controller, _, _, _, _) = try await setup(), old = try open(controller)
        controller.close(old); let current = try open(controller)
        let oversized = String(repeating: "🚲", count: 1001)
        controller.binding(current).wrappedValue = oversized
        let before = model.draft
        controller.close(old); controller.save(old); controller.save(current)
        XCTAssertEqual(controller.destination?.id, current.id); XCTAssertEqual(controller.text, oversized)
        XCTAssertFalse(controller.canSave(current)); XCTAssertEqual(model.draft, before)
    }
    func testEqualDraftReplacementModelHasDifferentHostAndRetiresAllOldCallbacks() async throws {
        let (first, oldController, owner, _, oldStorage, service) = try await setup()
        first.saveLocal(); let old = try open(oldController), oldBinding = oldController.binding(old)
        oldBinding.wrappedValue = "Old queued text"
        let second = ProjectEditModel(coordinator: .init(initial: try XCTUnwrap(first.coordinator.snapshot), service: service,
            store: .init(storage: Storage()), currentSession: { owner.session }))
        await second.load()
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(first.draft), ProjectEditPendingMaterials.exactData(second.draft))
        XCTAssertFalse(oldController.matchesHost(model: second, chapterID: old.chapterID, nodeID: old.nodeID))
        let currentController = ProjectNodeNarrativeController(model: second, chapterID: old.chapterID, nodeID: old.nodeID)
        XCTAssertNotEqual(currentController.hostIdentity, oldController.hostIdentity)
        // The keyed host's disappearance retires even a captured-but-not-yet-opened action.
        let queuedOpening = oldController.capture(chapterID: old.chapterID, nodeID: old.nodeID)
        oldController.retire(); let before = first.draft, writes = oldStorage.writes
        oldController.open(queuedOpening); oldBinding.wrappedValue = "Late callback"; oldController.save(old)
        XCTAssertNil(oldController.destination); XCTAssertEqual(first.draft, before); XCTAssertEqual(oldStorage.writes, writes)
        let current = try open(currentController); currentController.binding(current).wrappedValue = "New model text"
        currentController.save(current)
        XCTAssertEqual(second.draft.chapters[0].nodes[0].description, "New model text")
        XCTAssertEqual(first.draft, before); XCTAssertEqual(oldStorage.writes, writes); XCTAssertTrue(service.submissions.isEmpty)
    }
    func testSameNodeInDifferentChapterRequiresNewHostAndCannotReuseOldTarget() async throws {
        let (model, oldController, _, _, _, service) = try await setup(), old = try open(oldController)
        oldController.binding(old).wrappedValue = "Old chapter candidate"
        let node = model.draft.chapters[0].nodes.removeFirst()
        var chapter = ProjectEditChapter(); chapter.id = "other-chapter"; chapter.description = "Another chapter"; chapter.nodes = [node]
        model.draft.chapters.append(chapter)
        XCTAssertFalse(oldController.matchesHost(model: model, chapterID: chapter.id, nodeID: node.id))
        XCTAssertNil(oldController.capture(chapterID: chapter.id, nodeID: node.id))
        let currentController = ProjectNodeNarrativeController(model: model, chapterID: chapter.id, nodeID: node.id)
        XCTAssertNotEqual(currentController.hostIdentity, oldController.hostIdentity)
        oldController.retire(); let before = model.draft; oldController.open(old); oldController.save(old)
        XCTAssertEqual(model.draft, before); XCTAssertNil(oldController.destination)
        let current = try open(currentController); currentController.binding(current).wrappedValue = "Moved node text"
        currentController.save(current)
        XCTAssertEqual(model.draft.chapters[0], before.chapters[0])
        XCTAssertEqual(model.draft.chapters.first(where: { $0.id == chapter.id })?.nodes.first(where: { $0.id == node.id })?.description, "Moved node text")
        XCTAssertTrue(service.submissions.isEmpty)
    }
}

import XCTest
@testable import Questify

@MainActor final class ProjectEditPendingControllerTests: XCTestCase {
    private final class Owner { var session: ProjectEditSession?; init() throws { session = try .init(accountID: 901, epoch: 1, storageNamespace: "pending-fixture") } }
    private final class Storage: ProjectEditDataStorage {
        var data: [String: Data] = [:]; var writes = 0; var failAt: Int?
        func read(_ key: String) throws -> Data? { data[key] }
        func write(_ data: Data, key: String) throws { writes += 1; if writes == failAt { throw ProjectEditError.persistenceUnavailable }; self.data[key] = data }
        func remove(_ key: String) throws { data[key] = nil }
    }
    private func draft(_ product: ProjectEditProduct = .freeExplore, story: String = "Real story") -> ProjectEditDraft {
        var draft = ProjectEditSyntheticFixtures.draft(product: product); draft.chapters[0].description = story
        var node = ProjectEditNode(); node.name = "  Pending e\u{301}\n"; node.longitude = "121.5"; node.latitude = "31.2"
        node.localMetadata = ["hookText": .string("raw\t"), "future": .array([.null, .bool(true)])]
        draft.pendingMaterials = [.init(node: node, kind: .place)]; return draft
    }
    private func setup(_ draft: ProjectEditDraft) async throws -> (ProjectEditModel, ProjectEditPendingController, Owner, ProjectEditLocalStore, Storage, ProjectEditSyntheticService) {
        let owner = try Owner(), storage = Storage(), store = ProjectEditLocalStore(storage: storage)
        let initial = ProjectEditSnapshot(draft: draft), service = ProjectEditSyntheticService(snapshot: initial)
        let model = ProjectEditModel(coordinator: .init(initial: initial, service: service, store: store, currentSession: { owner.session }))
        await model.load(); return (model, .init(model: model), owner, store, storage, service)
    }
    private func stored(_ model: ProjectEditModel, _ owner: Owner, _ store: ProjectEditLocalStore) throws -> ProjectEditDraft {
        guard case .ready(let envelope) = store.load(session: try XCTUnwrap(owner.session), identity: try XCTUnwrap(model.coordinator.identity), baseline: try XCTUnwrap(model.coordinator.snapshot).draft) else { throw ProjectEditError.persistenceUnavailable }
        return envelope.draft
    }
    func testNamedIncompleteStarterSavesChapterAndMaterialTogetherAndRestores() async throws {
        let initial = ProjectEditDraft(product: .freeExplore)
        let (model, _, owner, store, _, service) = try await setup(initial), starter = ProjectEditStarterController(model: model)
        starter.createChapter(lease: model.captureStarterLease(), name: "Chapter 1"); let target = try XCTUnwrap(starter.destination)
        var candidate = starter.node(for: target).wrappedValue; candidate.name = "Incomplete local node"; candidate.localMetadata["future"] = .string("kept")
        starter.node(for: target).wrappedValue = candidate; XCTAssertTrue(starter.willSaveToPending(target)); starter.finish(target)
        XCTAssertNil(starter.destination); XCTAssertFalse(starter.saveUnconfirmed)
        let saved = try stored(model, owner, store)
        XCTAssertEqual(saved.chapters.count, 1); XCTAssertTrue(saved.chapters[0].nodes.isEmpty); XCTAssertEqual(saved.pendingMaterials?[0].node, candidate)
        let fresh = ProjectEditModel(coordinator: .init(initial: .init(draft: initial), service: service, store: store, currentSession: { owner.session }))
        await fresh.load(); XCTAssertTrue(fresh.canRestore); fresh.restore()
        XCTAssertEqual(fresh.draft.pendingMaterials?[0].node, candidate); XCTAssertTrue(fresh.draft.chapters[0].nodes.isEmpty); XCTAssertTrue(service.submissions.isEmpty)
    }
    func testPendingEditCancelPreservesOriginalBytesAndExplicitSaveKeepsMetadata() async throws {
        let initial = draft(), (model, controller, owner, store, _, service) = try await setup(initial)
        model.saveLocal(); let id = try XCTUnwrap(initial.pendingMaterials?.first?.id)
        controller.open(controller.capture(id)); let old = try XCTUnwrap(controller.destination), binding = controller.node(for: old)
        var candidate = binding.wrappedValue; candidate.name = "Changed"; binding.wrappedValue = candidate; controller.close(old)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), ProjectEditPendingMaterials.exactData(initial))
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(try stored(model, owner, store)), ProjectEditPendingMaterials.exactData(initial))
        controller.open(controller.capture(id)); let current = try XCTUnwrap(controller.destination)
        controller.node(for: current).wrappedValue = candidate; controller.save(current)
        XCTAssertNil(controller.destination); XCTAssertEqual(model.draft.pendingMaterials?[0].kind, .place)
        XCTAssertEqual(try stored(model, owner, store).pendingMaterials?[0].node.localMetadata, candidate.localMetadata); XCTAssertTrue(service.submissions.isEmpty)
    }
    func testFailedEnvelopeWriteKeepsDraftMaterialAndCandidateThenRetrySucceeds() async throws {
        let initial = draft(), (model, controller, owner, store, storage, _) = try await setup(initial)
        model.saveLocal(); let id = try XCTUnwrap(initial.pendingMaterials?.first?.id)
        controller.open(controller.capture(id)); let current = try XCTUnwrap(controller.destination)
        var candidate = controller.node(for: current).wrappedValue; candidate.name = "Retry candidate"; controller.node(for: current).wrappedValue = candidate
        storage.failAt = storage.writes + 1; controller.save(current)
        XCTAssertTrue(controller.saveUnconfirmed); XCTAssertEqual(controller.destination?.id, current.id); XCTAssertEqual(controller.candidate, candidate)
        XCTAssertEqual(model.draft, initial); XCTAssertEqual(try stored(model, owner, store), initial)
        storage.failAt = nil; controller.save(current)
        XCTAssertNil(controller.destination); XCTAssertEqual(try stored(model, owner, store).pendingMaterials?[0].node.name, "Retry candidate")
    }
    func testPointerFailureReportsUnconfirmedEvenWhenEnvelopeWasWrittenAndRetryDoesNotDuplicate() async throws {
        let initial = ProjectEditDraft(product: .freeExplore), (model, _, owner, store, storage, _) = try await setup(initial)
        model.saveLocal(); let starter = ProjectEditStarterController(model: model)
        starter.createChapter(lease: model.captureStarterLease(), name: "One"); let current = try XCTUnwrap(starter.destination)
        var node = starter.node(for: current).wrappedValue; node.name = "Pending"; starter.node(for: current).wrappedValue = node
        storage.failAt = storage.writes + 2; starter.finish(current)
        XCTAssertTrue(starter.saveUnconfirmed); XCTAssertEqual(starter.destination?.id, current.id); XCTAssertNil(model.draft.pendingMaterials)
        XCTAssertEqual(try stored(model, owner, store).pendingMaterials?.map(\.id), [node.id], "A failed pointer write does not mean the envelope was not written")
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertEqual(try stored(model, owner, store).pendingMaterials?.map(\.id), [node.id], "Cancelled autosave must not overwrite the uncertain envelope")
        storage.failAt = nil; starter.finish(current)
        XCTAssertNil(starter.destination); XCTAssertEqual(try stored(model, owner, store).pendingMaterials?.map(\.id), [node.id])
    }
    func testOldDismissalRetainedEditorAndDeleteConfirmationCannotAffectNewSheet() async throws {
        let initial = draft(), (model, controller, _, _, _, _) = try await setup(initial), id = try XCTUnwrap(initial.pendingMaterials?.first?.id)
        controller.open(controller.capture(id)); let old = try XCTUnwrap(controller.destination), binding = controller.node(for: old)
        var late = binding.wrappedValue; late.name = "Late"; controller.close(old)
        controller.open(controller.capture(id), kind: .remove); let removal = try XCTUnwrap(controller.destination); controller.close(removal)
        controller.open(controller.capture(id)); let current = try XCTUnwrap(controller.destination)
        binding.wrappedValue = late; controller.save(old); controller.remove(removal); controller.close(old)
        XCTAssertEqual(controller.destination?.id, current.id); XCTAssertEqual(model.draft, initial); XCTAssertNotEqual(controller.candidate.name, "Late")
    }
    func testCityArrangementUsesExplicitFreshGapAndRejectsTopologyABA() async throws {
        let initial = draft(.city, story: ""), (model, controller, _, _, _, service) = try await setup(initial)
        let id = try XCTUnwrap(initial.pendingMaterials?.first?.id), chapterID = initial.chapters[0].id
        controller.chooseChapter(chapterID, target: controller.capture(id)); let destination = try XCTUnwrap(controller.destination)
        XCTAssertFalse(controller.canInsert(destination)); controller.insert(controller.slot(destination, before: nil)); XCTAssertEqual(model.draft.pendingMaterials?.count, 1)
        var chapter = controller.storyChapter(destination).wrappedValue
        chapter.blocks?[0].content = "Written city story"; controller.storyChapter(destination).wrappedValue = chapter
        XCTAssertTrue(controller.canInsert(destination)); let stale = controller.slot(destination, before: nil)
        chapter.blocks?.append(.init(kind: .text, content: "Temporary")); controller.storyChapter(destination).wrappedValue = chapter
        chapter.blocks?.removeLast(); controller.storyChapter(destination).wrappedValue = chapter
        controller.insert(stale); XCTAssertEqual(model.draft.pendingMaterials?.count, 1)
        let slot = controller.slot(destination, before: nil); controller.insert(slot); controller.insert(slot)
        XCTAssertNil(controller.destination); XCTAssertEqual(model.draft.pendingMaterials, [])
        XCTAssertEqual(model.draft.chapters[0].nodes.filter { $0.id == id }.count, 1)
        XCTAssertEqual(model.draft.chapters[0].blocks?.last?.nodeID, id); XCTAssertTrue(service.submissions.isEmpty)
    }
    func testPendingTargetRejectsRawUnicodeABAAndLifecycleOrAccountReplacement() async throws {
        for action in ["unicodeABA", "deleteABA", "restore", "discard", "leave", "reload", "account", "modeABA"] {
            let initial = draft(), (model, controller, owner, _, _, service) = try await setup(initial), id = try XCTUnwrap(initial.pendingMaterials?.first?.id)
            controller.open(controller.capture(id)); let destination = try XCTUnwrap(controller.destination), candidate = controller.node(for: destination).wrappedValue
            switch action {
            case "unicodeABA": model.draft.pendingMaterials?[0].node.name = "  Pending é\n"; model.draft.pendingMaterials?[0].node.name = "  Pending e\u{301}\n"
            case "deleteABA": model.draft.pendingMaterials = []; model.draft.pendingMaterials = initial.pendingMaterials
            case "restore": model.restore()
            case "discard": model.discard()
            case "leave": model.leave()
            case "reload": await model.load(force: true)
            case "account": owner.session = try .init(accountID: 902, epoch: 2, storageNamespace: "pending-fixture")
            default: model.draft.product = .city; model.draft.product = .freeExplore
            }
            let before = ProjectEditPendingMaterials.exactData(model.draft)
            controller.node(for: destination).wrappedValue = candidate; controller.save(destination)
            controller.chooseChapter(initial.chapters[0].id, target: destination.target)
            XCTAssertFalse(controller.isCurrent(destination), action); XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before); XCTAssertTrue(service.submissions.isEmpty)
        }
    }
    func testExplicitRemoveFailureKeepsStoredMaterialAndRetryRemovesOnlyThatMaterial() async throws {
        var initial = draft(), other = ProjectEditNode(); other.name = "Other material"
        initial.pendingMaterials?.append(.init(node: other))
        let (model, controller, owner, store, storage, service) = try await setup(initial), id = try XCTUnwrap(initial.pendingMaterials?.first?.id)
        model.saveLocal(); controller.open(controller.capture(id), kind: .remove); let removal = try XCTUnwrap(controller.destination)
        storage.failAt = storage.writes + 1; controller.remove(removal)
        XCTAssertTrue(controller.saveUnconfirmed); XCTAssertEqual(model.draft, initial); XCTAssertEqual(try stored(model, owner, store), initial)
        storage.failAt = nil; controller.remove(removal)
        XCTAssertNil(controller.destination); XCTAssertEqual(try stored(model, owner, store).pendingMaterials?.map(\.id), [other.id]); XCTAssertTrue(service.submissions.isEmpty)
    }
    func testWhitelistAndUnknownWriteLockCannotArrangeOrSavePendingRows() async throws {
        let initial = draft(), owner = try Owner(), id = try XCTUnwrap(initial.pendingMaterials?.first?.id)
        var snapshot = ProjectEditSyntheticFixtures.snapshot(scope: .whitelist); snapshot.draft.pendingMaterials = initial.pendingMaterials
        let service = ProjectEditSyntheticService(snapshot: snapshot), store = ProjectEditLocalStore(storage: Storage())
        let limited = ProjectEditModel(coordinator: .init(initial: snapshot, service: service, store: store, currentSession: { owner.session }))
        await limited.load(); let disabled = ProjectEditPendingController(model: limited)
        XCTAssertNil(disabled.capture(id)); disabled.open(nil); XCTAssertNil(disabled.destination)
        let (model, controller, _, _, _, unknown) = try await setup(initial); unknown.scenario = .unknown
        let target = try XCTUnwrap(controller.capture(id)); controller.open(target); let destination = try XCTUnwrap(controller.destination)
        model.coordinator.prepare(model.draft); let review = try XCTUnwrap(model.coordinator.confirmation)
        await model.coordinator.confirm(review); XCTAssertTrue(model.coordinator.isLocked)
        let before = model.draft; controller.save(destination); controller.chooseChapter(initial.chapters[0].id, target: target)
        XCTAssertFalse(controller.isCurrent(destination)); XCTAssertEqual(model.draft, before); XCTAssertEqual(unknown.submissions.count, 1)
    }
    func testFreeArrangementAndRemovalPersistAtomicallyAndRetainUnknownMetadata() async throws {
        let initial = draft(), (model, controller, owner, store, storage, service) = try await setup(initial), id = try XCTUnwrap(initial.pendingMaterials?.first?.id)
        model.saveLocal(); storage.failAt = storage.writes + 1
        let target = controller.capture(id); controller.chooseChapter(initial.chapters[0].id, target: target)
        XCTAssertTrue(controller.saveUnconfirmed); XCTAssertEqual(model.draft, initial); XCTAssertEqual(try stored(model, owner, store), initial)
        storage.failAt = nil; controller.chooseChapter(initial.chapters[0].id, target: target)
        let saved = try stored(model, owner, store)
        XCTAssertEqual(saved.pendingMaterials, []); XCTAssertEqual(saved.chapters[0].nodes.last?.localMetadata, initial.pendingMaterials?[0].node.localMetadata)
        XCTAssertTrue(service.submissions.isEmpty)
    }
}

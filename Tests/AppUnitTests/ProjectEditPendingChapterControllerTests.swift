import XCTest
@testable import Questify

@MainActor final class ProjectEditPendingChapterControllerTests: XCTestCase {
    private final class Owner { var session: ProjectEditSession? = try? .init(accountID: 901, epoch: 1, storageNamespace: "pending-chapter") }
    private final class Storage: ProjectEditDataStorage {
        var data: [String: Data] = [:]; var writes = 0; var failAt: Int?
        func read(_ key: String) throws -> Data? { data[key] }
        func write(_ value: Data, key: String) throws { writes += 1; if writes == failAt { throw ProjectEditError.persistenceUnavailable }; data[key] = value }
        func remove(_ key: String) throws { data[key] = nil }
    }
    private func setup(_ product: ProjectEditProduct = .freeExplore, coordinates: Bool = true) async throws -> (ProjectEditModel, ProjectEditPendingController, Owner, Storage, ProjectEditLocalStore, ProjectEditSyntheticService) {
        let owner = Owner(), storage = Storage(), store = ProjectEditLocalStore(storage: storage)
        var draft = ProjectEditSyntheticFixtures.draft(product: product); draft.chapters = []
        var node = ProjectEditNode(); node.name = "Pending fixture"; node.description = "  e\u{301}\t"; node.nodeTime = 45; node.templateID = 73
        node.longitude = coordinates ? "121.5" : ""; node.latitude = coordinates ? "31.2" : ""
        node.localMetadata = ["future": .string("preserved")]; draft.pendingMaterials = [.init(node: node)]
        let snapshot = ProjectEditSnapshot(draft: draft), service = ProjectEditSyntheticService(snapshot: snapshot)
        let model = ProjectEditModel(coordinator: .init(initial: snapshot, service: service, store: store, currentSession: { owner.session }))
        await model.load(); return (model, .init(model: model), owner, storage, store, service)
    }
    private func saved(_ model: ProjectEditModel, _ owner: Owner, _ store: ProjectEditLocalStore) throws -> ProjectEditDraft {
        guard case .ready(let envelope) = store.load(session: try XCTUnwrap(owner.session), identity: try XCTUnwrap(model.coordinator.identity), baseline: try XCTUnwrap(model.coordinator.snapshot).draft) else { throw ProjectEditError.persistenceUnavailable }
        return envelope.draft
    }
    func testFreeActualActionSavesOneEnvelopeRestoresAndRejectsRepeatedOldButton() async throws {
        let (model, controller, owner, storage, store, service) = try await setup(), row = try XCTUnwrap(model.draft.pendingMaterials?.first)
        let target = try XCTUnwrap(controller.captureNewChapter(row.id)); controller.createChapter(target, name: "Chapter 1")
        XCTAssertFalse(controller.saveUnconfirmed); XCTAssertNil(controller.destination); XCTAssertEqual(model.draft.chapters[0].nodes, [row.node])
        XCTAssertEqual(try saved(model, owner, store).pendingMaterials, []); let count = storage.writes
        controller.createChapter(target, name: "Duplicate"); XCTAssertEqual(storage.writes, count); XCTAssertEqual(model.draft.chapters.count, 1)
        let reopened = ProjectEditModel(coordinator: .init(initial: try XCTUnwrap(model.coordinator.snapshot), service: service, store: store, currentSession: { owner.session }))
        await reopened.load(); reopened.restore(); XCTAssertEqual(reopened.draft.chapters[0].nodes, [row.node]); XCTAssertEqual(reopened.draft.pendingMaterials, [])
        XCTAssertTrue(service.submissions.isEmpty)
    }
    func testMissingCoordinatesOpensOriginalMaterialEditorAndCancelCreatesNothing() async throws {
        let (model, controller, _, storage, _, _) = try await setup(coordinates: false), row = try XCTUnwrap(model.draft.pendingMaterials?.first)
        controller.createChapter(controller.captureNewChapter(row.id), name: "Chapter 1")
        let view = try XCTUnwrap(controller.destination); XCTAssertEqual(view.kind, .edit); XCTAssertEqual(view.target.materialID, row.id)
        var edited = controller.node(for: view).wrappedValue; edited.longitude = "121.5"; controller.node(for: view).wrappedValue = edited
        controller.close(view); XCTAssertTrue(model.draft.chapters.isEmpty); XCTAssertEqual(model.draft.pendingMaterials?.first, row); XCTAssertTrue(storage.data.isEmpty)
    }
    func testCitySavedEmptyChapterRetainsMaterialThroughBackThenExplicitTextAndSlot() async throws {
        let (model, controller, owner, _, store, service) = try await setup(.city), row = try XCTUnwrap(model.draft.pendingMaterials?.first)
        controller.createChapter(controller.captureNewChapter(row.id), name: "Chapter 1")
        let original = try XCTUnwrap(controller.destination); guard case .story(let chapterID) = original.kind else { return XCTFail() }
        XCTAssertEqual(chapterID, model.draft.chapters[0].id); XCTAssertEqual(model.draft.chapters[0].blocks, []); XCTAssertFalse(controller.canInsert(original))
        XCTAssertEqual(try saved(model, owner, store).pendingMaterials?.first, row); controller.close(original)
        XCTAssertTrue(model.draft.chapters[0].nodes.isEmpty); XCTAssertEqual(model.draft.pendingMaterials?.first, row)
        controller.chooseChapter(chapterID, target: controller.capture(row.id)); let next = try XCTUnwrap(controller.destination)
        var chapter = controller.storyChapter(next).wrappedValue; chapter.blocks = [.init(kind: .text, content: "Real story")]; controller.storyChapter(next).wrappedValue = chapter
        controller.close(original); XCTAssertEqual(controller.destination?.id, next.id)
        controller.insert(controller.slot(next, before: nil)); XCTAssertNil(controller.destination); XCTAssertEqual(model.draft.pendingMaterials, [])
        XCTAssertEqual(try saved(model, owner, store).chapters[0].nodes, [row.node]); XCTAssertTrue(service.submissions.isEmpty)
    }
    func testFailureBeforeEnvelopeAndAfterEnvelopeNeverClaimsInMemoryCommit() async throws {
        for offset in [1, 2] {
            let (model, controller, owner, storage, store, _) = try await setup(), row = try XCTUnwrap(model.draft.pendingMaterials?.first)
            model.saveLocal(); let before = model.draft; storage.failAt = storage.writes + offset
            controller.createChapter(controller.captureNewChapter(row.id), name: "Chapter 1")
            XCTAssertTrue(controller.saveUnconfirmed); XCTAssertEqual(model.draft, before); XCTAssertNil(controller.destination)
            let actual = try saved(model, owner, store)
            if offset == 1 { XCTAssertTrue(actual.chapters.isEmpty); XCTAssertEqual(actual.pendingMaterials?.first, row) }
            else { XCTAssertEqual(actual.chapters.count, 1); XCTAssertEqual(actual.chapters[0].nodes, [row.node]); XCTAssertEqual(actual.pendingMaterials, []) }
            try await Task.sleep(nanoseconds: 500_000_000)
            XCTAssertEqual(try saved(model, owner, store), actual)
            storage.failAt = nil; controller.createChapter(controller.captureNewChapter(row.id), name: "Chapter 1")
            XCTAssertFalse(controller.saveUnconfirmed); XCTAssertEqual(model.draft.chapters.count, 1); XCTAssertEqual(try saved(model, owner, store).chapters.count, 1)
        }
    }
    func testOldMaterialOrChapterBytesCannotDispatchIntoChangedDraft() async throws {
        for field in ["material", "chapter", "mode", "restore", "account"] {
            let (model, controller, owner, storage, _, _) = try await setup()
            var chapter = ProjectEditChapter(); chapter.name = "e\u{301}"; model.draft.chapters = [chapter]
            let row = try XCTUnwrap(model.draft.pendingMaterials?.first), target = try XCTUnwrap(controller.captureNewChapter(row.id))
            switch field {
            case "material": model.draft.pendingMaterials?[0].node.name += " changed"
            case "chapter": model.draft.chapters[0].name = "é"
            case "mode": model.draft.product = .city
            case "restore": model.restore()
            default: owner.session = try .init(accountID: 902, epoch: 2, storageNamespace: "pending-chapter")
            }
            let before = ProjectEditPendingMaterials.exactData(model.draft), count = storage.writes
            controller.createChapter(target, name: "Stale")
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before); XCTAssertEqual(storage.writes, count); XCTAssertNil(controller.destination)
        }
    }
    func testActiveDifferentMaterialSheetCannotBeReplacedByCreateAction() async throws {
        let (model, controller, _, storage, _, _) = try await setup(), row = try XCTUnwrap(model.draft.pendingMaterials?.first)
        let target = controller.captureNewChapter(row.id); controller.open(controller.capture(row.id)); let old = try XCTUnwrap(controller.destination)
        controller.createChapter(target, name: "Chapter 1")
        XCTAssertEqual(controller.destination?.id, old.id); XCTAssertTrue(model.draft.chapters.isEmpty); XCTAssertTrue(storage.data.isEmpty)
    }
}

import XCTest
@testable import Questify

@MainActor final class ProjectEditPreparedReviewTests: XCTestCase {
    private final class Owner { var session: ProjectEditSession?; init() throws { session = try .init(accountID: 901, epoch: 1, storageNamespace: "prepared-nodes") } }
    private final class Storage: ProjectEditDataStorage {
        var data: [String: Data] = [:]; var writes = 0; var failAt: Int?
        func read(_ key: String) throws -> Data? { data[key] }
        func write(_ value: Data, key: String) throws { writes += 1; if writes == failAt { throw ProjectEditError.persistenceUnavailable }; data[key] = value }
        func remove(_ key: String) throws { data[key] = nil }
    }
    private func setup(_ product: ProjectEditProduct = .freeExplore) async throws -> (ProjectEditModel, Owner, ProjectEditLocalStore, Storage, ProjectEditSyntheticService) {
        let owner = try Owner(), storage = Storage(), store = ProjectEditLocalStore(storage: storage)
        let initial = ProjectEditSnapshot(draft: ProjectEditSyntheticFixtures.draft(product: product)), service = ProjectEditSyntheticService(snapshot: initial)
        let model = ProjectEditModel(coordinator: .init(initial: initial, service: service, store: store, currentSession: { owner.session }))
        await model.load(); return (model, owner, store, storage, service)
    }
    func testRawNodeEditAndRestoreInvalidateOldPreparedReviewBeforeAnyCallback() async throws {
        let (model, _, _, _, service) = try await setup()
        model.draft.chapters[0].nodes[0].description = "e\u{301}"; model.review(); let original = try XCTUnwrap(model.confirmation)
        XCTAssertTrue(model.reviewIsCurrent(original)); XCTAssertTrue(model.reviewLocalSaveConfirmed)
        model.draft.chapters[0].nodes[0].description = "é"
        XCTAssertNil(model.confirmation); XCTAssertNil(model.coordinator.confirmation)
        await model.submit(original); XCTAssertTrue(service.submissions.isEmpty)
        model.review(); let restored = try XCTUnwrap(model.confirmation); model.restore()
        XCTAssertFalse(model.reviewIsCurrent(restored)); await model.submit(restored); XCTAssertTrue(service.submissions.isEmpty)
    }
    func testOldSheetDismissalAndQueuedSubmitCannotClearNewPreparedRequest() async throws {
        let (model, _, _, _, service) = try await setup()
        model.review(); let old = try XCTUnwrap(model.confirmation); model.cancelReview(old)
        model.draft.chapters[0].nodes[0].description = "Current"; model.review(); let current = try XCTUnwrap(model.confirmation)
        model.cancelReview(old); await model.submit(old)
        XCTAssertEqual(model.confirmation?.id, current.id); XCTAssertEqual(model.coordinator.confirmation?.id, current.id)
        XCTAssertTrue(model.reviewIsCurrent(current)); XCTAssertTrue(service.submissions.isEmpty)
    }
    func testArrangedMaterialReeditSavesAndRestoresBeforePreparingExactValues() async throws {
        let (model, owner, store, _, service) = try await setup()
        var node = ProjectEditNode(); node.name = "Material"; node.longitude = "121.5"; node.latitude = "31.2"
        node.description = "First"; node.imgUrl = "fixture:reference"; node.nodeTime = 45; node.templateID = 73
        model.draft.pendingMaterials = [.init(node: node)]; let pending = ProjectEditPendingController(model: model), chapterID = model.draft.chapters[0].id
        pending.chooseChapter(chapterID, target: pending.capture(node.id)); XCTAssertEqual(model.draft.pendingMaterials, [])
        let binding = model.chapter(chapterID); var chapter = binding.wrappedValue; chapter.nodes[1].description = "  Edited e\u{301}\n"; binding.wrappedValue = chapter
        model.saveLocal(); let initial = try XCTUnwrap(model.coordinator.snapshot)
        let fresh = ProjectEditModel(coordinator: .init(initial: initial, service: service, store: store, currentSession: { owner.session }))
        await fresh.load(); XCTAssertTrue(fresh.canRestore); fresh.restore(); fresh.review()
        let review = try XCTUnwrap(fresh.confirmation), value = try XCTUnwrap(ProjectEditPreparedNodes(payload: review.payload).chapters?.first?.nodes?[1])
        XCTAssertEqual(value.value(.description).text.map { Array($0.utf8) }, Array(chapter.nodes[1].description.utf8))
        XCTAssertEqual(value.value(.imgUrl).text, "fixture:reference"); XCTAssertEqual(value.value(.nodeTime).text, "45"); XCTAssertEqual(value.value(.templateId).text, "73")
        fresh.cancelReview(review); XCTAssertTrue(service.submissions.isEmpty)
    }
    func testPartialLocalSaveFailureIsShownAndDoesNotReviveOldPreparedValues() async throws {
        let (model, _, _, storage, service) = try await setup()
        model.review(); let old = try XCTUnwrap(model.confirmation)
        model.draft.chapters[0].nodes[0].description = "Changed after review"
        storage.failAt = storage.writes + 2; model.review(); let current = try XCTUnwrap(model.confirmation)
        XCTAssertFalse(model.reviewLocalSaveConfirmed); XCTAssertTrue(model.reviewIsCurrent(current))
        await model.submit(old); model.cancelReview(old); XCTAssertEqual(model.confirmation?.id, current.id)
        XCTAssertEqual(ProjectEditPreparedNodes(payload: current.payload).chapters?.first?.nodes?.first?.value(.description).text, "Changed after review")
        XCTAssertTrue(service.submissions.isEmpty)
    }
    func testAccountLeaveDiscardAndUnsupportedRawContextCannotUsePreparedReview() async throws {
        for action in ["account", "leave", "discard", "unsupportedNumber"] {
            let (model, owner, _, _, service) = try await setup(); model.review(); let review = try XCTUnwrap(model.confirmation)
            switch action {
            case "account": owner.session = try .init(accountID: 902, epoch: 2, storageNamespace: "prepared-nodes")
            case "leave": model.leave()
            case "discard": model.discard()
            default: model.draft.chapters[0].nodes[0].localMetadata["future"] = .number(.nan)
            }
            XCTAssertFalse(model.reviewIsCurrent(review)); await model.submit(review); XCTAssertTrue(service.submissions.isEmpty)
        }
    }
    func testWhitelistReviewCapturesOmissionWithoutReplacingChapterContent() async throws {
        let owner = try Owner(), initial = ProjectEditSyntheticFixtures.snapshot(scope: .whitelist)
        let service = ProjectEditSyntheticService(snapshot: initial)
        let model = ProjectEditModel(coordinator: .init(initial: initial, service: service, store: .init(storage: Storage()), currentSession: { owner.session }))
        await model.load(); XCTAssertTrue(model.canEdit); XCTAssertFalse(model.fullEdit)
        model.review(); let review = try XCTUnwrap(model.confirmation)
        XCTAssertTrue(model.reviewIsCurrent(review)); XCTAssertTrue(ProjectEditPreparedNodes(payload: review.payload).omitted)
        XCTAssertEqual(review.draft.chapters, initial.draft.chapters); model.cancelReview(review)
        XCTAssertTrue(service.submissions.isEmpty)
    }
    func testStoryBlockReorderInvalidatesOldReviewAndReprepareUsesFinalSerializedOrder() async throws {
        let (model, _, _, _, service) = try await setup(.city)
        var second = model.draft.chapters[0].nodes[0]; second.id = "second"; second.name = "Second"
        let first = model.draft.chapters[0].nodes[0]
        model.draft.chapters[0].nodes.append(second)
        model.draft.chapters[0].blocks = [.init(kind: .text, content: "Story"), .init(kind: .node, nodeID: first.id), .init(kind: .node, nodeID: second.id)]
        model.review(); let old = try XCTUnwrap(model.confirmation)
        model.draft.chapters[0].blocks?.swapAt(1, 2)
        XCTAssertNil(model.confirmation); XCTAssertFalse(model.reviewIsCurrent(old))
        model.review(); let current = try XCTUnwrap(model.confirmation)
        XCTAssertEqual(ProjectEditPreparedNodes(payload: old.payload).chapters?.first?.nodes?.map { $0.value(.name).text }, [first.name, "Second"])
        XCTAssertEqual(ProjectEditPreparedNodes(payload: current.payload).chapters?.first?.nodes?.map { $0.value(.name).text }, ["Second", first.name])
        await model.submit(old); model.cancelReview(old); XCTAssertEqual(model.confirmation?.id, current.id)
        XCTAssertTrue(service.submissions.isEmpty)
    }

}

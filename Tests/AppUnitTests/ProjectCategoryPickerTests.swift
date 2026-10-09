import XCTest
import Combine
@testable import Questify

@MainActor final class ProjectCategoryPickerTests: XCTestCase {
    private final class Owner {
        var session: ProjectEditSession? = try! .init(accountID: 901, epoch: 1, storageNamespace: "project-categories")
    }
    private final class Storage: ProjectEditDataStorage {
        var writes = 0
        func read(_ key: String) throws -> Data? { nil }
        func write(_ value: Data, key: String) throws { writes += 1 }
        func remove(_ key: String) throws {}
    }
    private func categories(_ ids: [Int], type: Int = 1) throws -> [DiscoveryCategory] {
        try JSONDecoder().decode([DiscoveryCategory].self, from: JSONSerialization.data(withJSONObject:
            ids.map { ["id": $0, "categoryName": "Category \($0)", "type": type] as [String: Any] }))
    }
    private func setup(ids: [Int] = [99, 4]) async throws -> (ProjectCategoryPickerController, Owner, Storage, Reader) {
        let owner = Owner(), storage = Storage(), reader = Reader()
        var draft = ProjectEditSyntheticFixtures.draft(product: .freeExplore); draft.categoryIDs = ids
        let initial = ProjectEditSnapshot(draft: draft), service = ProjectEditSyntheticService(snapshot: initial)
        let model = ProjectEditModel(coordinator: .init(initial: initial, service: service,
            store: ProjectEditLocalStore(storage: storage), currentSession: { owner.session }))
        await model.load(); return (.init(model: model, reader: reader), owner, storage, reader)
    }
    private func open(_ controller: ProjectCategoryPickerController) throws -> ProjectCategoryPickerController.Presentation {
        controller.open(); return try XCTUnwrap(controller.presentation)
    }

    func testExactTypeOneReadAndExplicitSavePreserveUnknownIDsAndAllOtherDraftBytes() async throws {
        let (controller, _, storage, reader) = try await setup(), model = controller.model
        reader.rows = try categories([4, 7]); let original = try open(controller), before = model.draft
        await controller.load(original)
        XCTAssertEqual(reader.types, [1]); XCTAssertEqual(controller.state, .loaded)
        controller.toggle(7, in: original)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), ProjectEditPendingMaterials.exactData(before))
        controller.save(original)
        var expected = before; expected.categoryIDs = [99, 4, 7]
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), ProjectEditPendingMaterials.exactData(expected))
        XCTAssertEqual(storage.writes, 0)
    }
    func testCancelAndNoopSaveKeepExactBytesAndPreparedReview() async throws {
        let (controller, _, storage, reader) = try await setup(), model = controller.model
        reader.rows = try categories([4, 7]); model.review()
        let review = try XCTUnwrap(model.confirmation), before = ProjectEditPendingMaterials.exactData(model.draft), writes = storage.writes
        let first = try open(controller); await controller.load(first); controller.toggle(7, in: first); controller.close(first)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before)
        let second = try open(controller); await controller.load(second); controller.save(second)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before)
        XCTAssertEqual(model.confirmation?.id, review.id); XCTAssertEqual(storage.writes, writes)
    }
    func testFailureRetryTrueEmptyAndUnavailableAreDistinctAndNeverClearSavedIDs() async throws {
        let (controller, _, _, reader) = try await setup(), original = try open(controller)
        reader.failure = .httpStatus(503); await controller.load(original)
        XCTAssertEqual(controller.state, .failed); XCTAssertFalse(controller.canSave(original))
        reader.failure = nil; await controller.load(original)
        XCTAssertEqual(controller.state, .empty); XCTAssertEqual(controller.selection.selectedIDs, [99, 4])
        controller.close(original)
        reader.isConfigured = false; let unavailable = try open(controller); await controller.load(unavailable)
        XCTAssertEqual(controller.state, .unavailable); XCTAssertFalse(controller.canSave(unavailable))
        XCTAssertEqual(controller.model.draft.categoryIDs, [99, 4])
    }
    func testDuplicateWrongTypeAndUnsupportedSavedIDsCannotCommit() async throws {
        let (controller, _, _, reader) = try await setup(), original = try open(controller)
        for rows in [try categories([4, 4]), try categories([4], type: 4)] {
            reader.rows = rows; await controller.load(original)
            XCTAssertEqual(controller.state, .failed); XCTAssertFalse(controller.canSave(original))
        }
        controller.close(original)
        controller.model.draft.categoryIDs = [4, 4]; reader.rows = try categories([4])
        let duplicate = try open(controller); await controller.load(duplicate)
        XCTAssertFalse(controller.selection.isSupported); XCTAssertFalse(controller.canSave(duplicate))
        controller.save(duplicate); XCTAssertEqual(controller.model.draft.categoryIDs, [4, 4])
    }
    func testNewlySelectedIDRemainsVisibleAndRemovableAfterRetryDropsIt() async throws {
        let (controller, _, _, reader) = try await setup(), original = try open(controller)
        reader.rows = try categories([4, 7]); await controller.load(original)
        controller.toggle(7, in: original); reader.rows = try categories([4]); await controller.load(original)
        XCTAssertTrue(controller.retainedIDs.contains(7)); XCTAssertTrue(controller.selection.selectedIDs.contains(7))
        controller.toggle(7, in: original); controller.save(original)
        XCTAssertEqual(controller.model.draft.categoryIDs, [99, 4])
    }
    func testAccountReaderConfigurationAndSameBytesABARejectOldSelection() async throws {
        for action in ["account", "epoch", "reader", "configuration", "aba", "incarnation"] {
            let (controller, owner, storage, reader) = try await setup(), original = try open(controller)
            reader.rows = try categories([4, 7]); await controller.load(original); controller.toggle(7, in: original)
            switch action {
            case "account": owner.session = try .init(accountID: 902, epoch: 1, storageNamespace: "project-categories")
            case "epoch": owner.session = try .init(accountID: 901, epoch: 2, storageNamespace: "project-categories")
            case "reader": reader.identity = "replacement"
            case "configuration": reader.isConfigured = false
            case "aba": let same = controller.model.draft; controller.model.draft = same
            default: controller.model.invalidateStarterLease()
            }
            let before = ProjectEditPendingMaterials.exactData(controller.model.draft)
            controller.save(original)
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(controller.model.draft), before, action)
            XCTAssertEqual(storage.writes, 0); XCTAssertFalse(controller.canSave(original))
        }
    }
    func testClosedOrOlderRequestCannotPublishRowsOrExpireIdentity() async throws {
        for close in [false, true] {
            let (controller, _, _, reader) = try await setup(), original = try open(controller)
            var replies: [CheckedContinuation<[DiscoveryCategory], Error>] = []
            let firstStarted = expectation(description: "first category read"), secondStarted = expectation(description: "second category read")
            reader.read = {
                try await withCheckedThrowingContinuation { reply in
                    replies.append(reply)
                    if replies.count == 1 { firstStarted.fulfill() } else { secondStarted.fulfill() }
                }
            }
            let first = Task { await controller.load(original) }; await fulfillment(of: [firstStarted], timeout: 1)
            if close { controller.close(original) }
            else {
                let second = Task { await controller.load(original) }; await fulfillment(of: [secondStarted], timeout: 1)
                replies[1].resume(returning: try categories([7])); await second.value
            }
            replies[0].resume(throwing: APIError.unauthorized); await first.value
            XCTAssertEqual(reader.unauthorizedCount, 0)
            if close { XCTAssertTrue(controller.categories.isEmpty) }
            else { XCTAssertEqual(controller.categories.map(\.id), [7]) }
        }
    }
    func testOnlyAcceptedCurrentUnauthorizedCompletionMayExpireAndOldCloseDoesNotCloseNewSheet() async throws {
        let (controller, _, _, reader) = try await setup(), first = try open(controller)
        reader.failure = .unauthorized; await controller.load(first)
        XCTAssertEqual(reader.unauthorizedCount, 1)
        controller.close(first); reader.failure = nil
        let second = try open(controller); controller.close(first)
        XCTAssertEqual(controller.presentation?.id, second.id)
    }

    @MainActor private final class Reader: DiscoveryReading {
        var isConfigured = true, identity = "fixture"
        var discoveryPresentationIdentity: String { identity }
        var rows: [DiscoveryCategory] = [], types: [Int?] = []
        var failure: APIError?, unauthorizedCount = 0
        var read: (() async throws -> [DiscoveryCategory])?
        func projectMetadataCategoriesRequest() -> DiscoveryReadRequest<[DiscoveryCategory]> {
            .init(read: { try await self.discoveryCategories(type: 1) }, onUnauthorized: { self.unauthorizedCount += 1 })
        }
        func discoveryCategories(type: Int?) async throws -> [DiscoveryCategory] {
            types.append(type); if let read { return try await read() }; if let failure { throw failure }; return rows
        }
        func discoveryBanners() async throws -> [DiscoveryBanner] { throw APIError.notConfigured }
        func discoveryTemplateHome() async throws -> DiscoveryTemplateHome { throw APIError.notConfigured }
        func discoveryPlayTemplates(keyword: String, packType: DiscoveryPackType?) async throws -> [DiscoveryPlayTemplate] { throw APIError.notConfigured }
        func discoveryTopicTemplates() async throws -> [DiscoveryTopicTemplate] { throw APIError.notConfigured }
        func discoveryTopicTemplateDetail(id: Int) async throws -> PublicTopicTemplateDetail { throw APIError.notConfigured }
        func discoveryPlayTemplate(id: Int) async throws -> DiscoveryPlayTemplate { throw APIError.notConfigured }
    }
}

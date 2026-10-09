import XCTest
@testable import Questify

@MainActor final class ProjectChapterAudioFieldTests: XCTestCase {
    private final class Owner {
        var session: ProjectEditSession? = try! .init(accountID: 901, epoch: 1, storageNamespace: "chapter-audio")
    }
    private final class Storage: ProjectEditDataStorage {
        var data: [String: Data] = [:]; var writes = 0
        func read(_ key: String) throws -> Data? { data[key] }
        func write(_ value: Data, key: String) throws { data[key] = value; writes += 1 }
        func remove(_ key: String) throws { data[key] = nil }
    }
    private func setup() async throws -> (ProjectChapterAudioController, Owner, Storage) {
        let owner = Owner(), storage = Storage()
        var draft = ProjectEditSyntheticFixtures.draft(product: .freeExplore)
        draft.chapters[0].preserved["audioUrl"] = .string("https://old.invalid/e\u{301}.mp3")
        let initial = ProjectEditSnapshot(draft: draft), service = ProjectEditSyntheticService(snapshot: initial)
        let model = ProjectEditModel(coordinator: .init(initial: initial, service: service,
            store: ProjectEditLocalStore(storage: storage), currentSession: { owner.session }))
        await model.load()
        return (.init(model: model, chapterID: draft.chapters[0].id), owner, storage)
    }
    private func open(_ controller: ProjectChapterAudioController) throws -> ProjectChapterAudioController.Confirmation {
        controller.open(controller.capture()); return try XCTUnwrap(controller.confirmation)
    }
    func testOpenCancelAndReadKeepExactBytesReviewAndStorageUntouched() async throws {
        let (controller, _, storage) = try await setup(), model = controller.model
        model.review(); let review = try XCTUnwrap(model.confirmation)
        let before = ProjectEditPendingMaterials.exactData(model.draft), writes = storage.writes
        let original = try open(controller); _ = controller.chapter; controller.close(original)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before)
        XCTAssertEqual(model.confirmation?.id, review.id); XCTAssertEqual(storage.writes, writes)
    }
    func testExplicitClearOnlyChangesCurrentChapterAndUsesExistingDraftSavePath() async throws {
        let (controller, _, storage) = try await setup(), model = controller.model
        let original = try open(controller)
        let expected = try ProjectChapterAudio.clearing(chapterID: controller.chapterID, in: model.draft)
        controller.clear(original)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), ProjectEditPendingMaterials.exactData(expected))
        XCTAssertEqual(storage.writes, 0); XCTAssertNil(controller.confirmation); XCTAssertNil(controller.capture())
        let bytes = ProjectEditPendingMaterials.exactData(model.draft); controller.clear(original)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), bytes)
    }
    func testAccountEpochSignOutRestoreAndSameByteABARejectOldConfirmation() async throws {
        for action in ["account", "epoch", "signOut", "restore", "aba"] {
            let (controller, owner, storage) = try await setup(), model = controller.model
            let original = try open(controller)
            switch action {
            case "account": owner.session = try .init(accountID: 902, epoch: 1, storageNamespace: "chapter-audio")
            case "epoch": owner.session = try .init(accountID: 901, epoch: 2, storageNamespace: "chapter-audio")
            case "signOut": owner.session = nil
            case "restore": model.saveLocal(); await model.load(force: true); model.restore()
            default: let same = model.draft; model.draft = same
            }
            let before = ProjectEditPendingMaterials.exactData(model.draft), writes = storage.writes
            controller.clear(original)
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before, action)
            XCTAssertEqual(storage.writes, writes, action)
        }
    }
    func testDeleteReorderDuplicateAndRemoveReinsertSameChapterIDRejectOldClear() async throws {
        for action in ["delete", "reorder", "duplicate", "reinsert"] {
            let (controller, _, _) = try await setup(), model = controller.model
            var second = ProjectEditChapter(); second.name = "another"; model.draft.chapters.append(second)
            let original = try open(controller), saved = model.draft.chapters[0]
            switch action {
            case "delete": model.draft.chapters.removeFirst()
            case "reorder": model.draft.chapters.swapAt(0, 1)
            case "duplicate": model.draft.chapters.append(saved)
            default: model.draft.chapters.removeFirst(); model.draft.chapters.insert(saved, at: 0)
            }
            let before = ProjectEditPendingMaterials.exactData(model.draft)
            controller.clear(original)
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before, action)
        }
    }
    func testCancelAndDisappearInvalidateOldActionsWithoutClosingNewConfirmation() async throws {
        let (controller, _, _) = try await setup(), model = controller.model
        let first = try open(controller); controller.close(first)
        let second = try open(controller); controller.clear(first); controller.close(first)
        XCTAssertEqual(controller.confirmation?.id, second.id)
        let before = ProjectEditPendingMaterials.exactData(model.draft)
        controller.retire(); controller.clear(second)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before)
        XCTAssertNil(controller.confirmation)
    }
    func testUnknownAndAbsentReferenceNeverOfferClear() async throws {
        let (controller, _, _) = try await setup(), model = controller.model
        let values: [ProjectEditJSON?] = [nil, .null, .number(1), .string("")]
        for value in values {
            model.draft.chapters[0].preserved["audioUrl"] = value
            let before = ProjectEditPendingMaterials.exactData(model.draft)
            XCTAssertNil(controller.capture()); controller.open(controller.capture())
            XCTAssertNil(controller.confirmation)
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(model.draft), before)
        }
    }
}

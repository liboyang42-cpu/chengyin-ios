import XCTest
@testable import Questify

@MainActor final class ProjectPendingNodeRemovalControllerTests: XCTestCase {
    private final class Owner {
        var session: ProjectEditSession?
        init(guest: Bool = false) throws {
            if guest { session = nil }
            else { session = try .init(accountID: 901, epoch: 1, storageNamespace: "pending-node-removal") }
        }
    }
    private final class Clock { var value: TimeInterval = 100 }
    private final class Storage: ProjectEditDataStorage {
        var data: [String: Data] = [:]; var writes = 0; var failAt: Int?
        func read(_ key: String) throws -> Data? { data[key] }
        func write(_ value: Data, key: String) throws {
            writes += 1
            if writes == failAt { throw ProjectEditError.persistenceUnavailable }
            data[key] = value
        }
        func remove(_ key: String) throws { data[key] = nil }
    }
    private func setup(guest: Bool = false) async throws -> (ProjectPendingNodeRemovalController, Owner, Storage, Clock) {
        let owner = try Owner(guest: guest), storage = Storage(), clock = Clock()
        var draft = ProjectEditSyntheticFixtures.draft(product: .freeExplore)
        let first = draft.chapters[0].nodes[0]
        var second = first; second.id = "second-node"; second.name = "Second e\u{301}"
        draft.chapters[0].nodes.append(second)
        let initial = ProjectEditSnapshot(draft: draft), service = ProjectEditSyntheticService(snapshot: initial)
        let model = ProjectEditModel(coordinator: .init(initial: initial, service: service,
            store: ProjectEditLocalStore(storage: storage), currentSession: { owner.session }))
        await model.load()
        return (.init(model: model, chapterID: model.draft.chapters[0].id, now: { clock.value }), owner, storage, clock)
    }
    private func removeFirst(_ controller: ProjectPendingNodeRemovalController) throws {
        controller.open(offsets: IndexSet(integer: 0), captured: controller.capture())
        controller.confirm(try XCTUnwrap(controller.confirmation))
    }

    func testCancelDoesNotWriteAndConfirmedMoveUndoPreserveExactDraft() async throws {
        let (controller, _, storage, _) = try await setup(); defer { controller.retire() }
        let original = ProjectEditPendingMaterials.exactData(controller.model.draft)
        controller.open(offsets: IndexSet(integer: 0), captured: controller.capture())
        controller.close(try XCTUnwrap(controller.confirmation))
        XCTAssertEqual(storage.writes, 0)
        try removeFirst(controller)
        let undo = try XCTUnwrap(controller.undo), count = storage.writes
        XCTAssertEqual(controller.model.draft.chapters[0].nodes.count, 1)
        XCTAssertEqual(controller.model.draft.pendingMaterials?.count, 1)
        controller.restore(undo)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(controller.model.draft), original)
        XCTAssertGreaterThan(storage.writes, count)
        let restoredWrites = storage.writes; controller.restore(undo)
        XCTAssertEqual(storage.writes, restoredWrites)
    }
    func testMonotonicFiveSecondWindowDoesNotReviveExpiredUndo() async throws {
        let (controller, _, storage, clock) = try await setup(); defer { controller.retire() }
        try removeFirst(controller); let undo = try XCTUnwrap(controller.undo), count = storage.writes
        clock.value = 104.999; XCTAssertTrue(controller.canUndo(undo))
        clock.value = 105; XCTAssertFalse(controller.canUndo(undo))
        controller.restore(undo); XCTAssertNil(controller.undo); XCTAssertEqual(storage.writes, count)
        clock.value = 100; controller.restore(undo)
        XCTAssertEqual(storage.writes, count); XCTAssertEqual(controller.model.draft.pendingMaterials?.count, 1)
    }
    func testConsecutiveMovesShareTheOriginalSnapshotAndExtendOnlyTheNewWindow() async throws {
        let (controller, _, _, clock) = try await setup(); defer { controller.retire() }
        let original = ProjectEditPendingMaterials.exactData(controller.model.draft)
        try removeFirst(controller); let oldUndo = try XCTUnwrap(controller.undo)
        clock.value = 104; try removeFirst(controller)
        let current = try XCTUnwrap(controller.undo)
        XCTAssertFalse(controller.canUndo(oldUndo)); XCTAssertEqual(current.deadline, 109)
        XCTAssertTrue(controller.model.draft.chapters[0].nodes.isEmpty)
        controller.restore(current)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(controller.model.draft), original)
    }
    func testSameBytesABAChangedOwnerAndRetirementRejectOldConfirmationAndUndo() async throws {
        for action in ["aba", "account", "epoch", "signOut", "restore", "retire"] {
            let (controller, owner, storage, _) = try await setup(); defer { controller.retire() }
            try removeFirst(controller); let undo = try XCTUnwrap(controller.undo), count = storage.writes
            switch action {
            case "aba": let same = controller.model.draft; controller.model.draft = same
            case "account": owner.session = try .init(accountID: 902, epoch: 1, storageNamespace: "pending-node-removal")
            case "epoch": owner.session = try .init(accountID: 901, epoch: 2, storageNamespace: "pending-node-removal")
            case "signOut": owner.session = nil
            case "restore": await controller.model.load(force: true); XCTAssertTrue(controller.model.canRestore); controller.model.restore()
            default: controller.retire()
            }
            let current = ProjectEditPendingMaterials.exactData(controller.model.draft)
            controller.restore(undo)
            XCTAssertEqual(storage.writes, count, action)
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(controller.model.draft), current, action)
        }
        let (controller, _, storage, _) = try await setup(); defer { controller.retire() }
        let old = try XCTUnwrap(controller.capture())
        controller.model.draft.chapters[0].nodes.reverse()
        controller.open(offsets: IndexSet(integer: 0), captured: old)
        XCTAssertNil(controller.confirmation); XCTAssertEqual(storage.writes, 0)
    }
    func testEnvelopeOrPointerSaveFailureKeepsAllOriginalContentAndCannotRetryOldIntent() async throws {
        for failure in [1, 2] {
            let (controller, _, storage, _) = try await setup(); defer { controller.retire() }
            let original = ProjectEditPendingMaterials.exactData(controller.model.draft)
            storage.failAt = failure
            controller.open(offsets: IndexSet(integer: 0), captured: controller.capture())
            let confirmation = try XCTUnwrap(controller.confirmation); controller.confirm(confirmation)
            XCTAssertTrue(controller.saveUnconfirmed); XCTAssertNil(controller.undo)
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(controller.model.draft), original)
            let count = storage.writes; controller.confirm(confirmation)
            XCTAssertEqual(storage.writes, count); XCTAssertNil(controller.capture())
            if failure == 2 {
                let saved = try XCTUnwrap(storage.data.values.compactMap { try? JSONDecoder().decode(ProjectEditEnvelope.self, from: $0) }.first)
                XCTAssertEqual(saved.draft.pendingMaterials?.count, 1, "A partial save is reported as unconfirmed, not rolled back.")
                XCTAssertEqual(saved.draft.chapters[0].nodes.count, 1)
            }
        }
    }
    func testUndoSaveFailureKeepsMovedNodeInCurrentPendingListWithoutConsumingAnotherWrite() async throws {
        for offset in [1, 2] {
            let (controller, _, storage, _) = try await setup(); defer { controller.retire() }
            try removeFirst(controller)
            let undo = try XCTUnwrap(controller.undo), moved = ProjectEditPendingMaterials.exactData(controller.model.draft)
            storage.failAt = storage.writes + offset
            controller.restore(undo)
            XCTAssertTrue(controller.saveUnconfirmed)
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(controller.model.draft), moved)
            XCTAssertEqual(controller.model.draft.pendingMaterials?.count, 1)
            let count = storage.writes; controller.restore(undo)
            XCTAssertEqual(storage.writes, count)
        }
    }
    func testGuestMoveUndoStaysInMemoryAndNewSignInRetiresOldUndo() async throws {
        let (controller, owner, storage, _) = try await setup(guest: true); defer { controller.retire() }
        let original = ProjectEditPendingMaterials.exactData(controller.model.draft)
        try removeFirst(controller); controller.restore(try XCTUnwrap(controller.undo))
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(controller.model.draft), original)
        XCTAssertEqual(storage.writes, 0)
        try removeFirst(controller); let undo = try XCTUnwrap(controller.undo)
        owner.session = try .init(accountID: 901, epoch: 1, storageNamespace: "pending-node-removal")
        controller.restore(undo); XCTAssertEqual(storage.writes, 0)
        XCTAssertEqual(controller.model.draft.pendingMaterials?.count, 1)
    }
}

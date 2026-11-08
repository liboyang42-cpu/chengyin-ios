#if DEBUG
import XCTest
@testable import QuestifyCore

@MainActor private final class ProjectSaveReadbackStorage: ProjectEditDataStorage {
    var values: [String: Data] = [:]
    var dropEnvelope = false, dropPointer = false
    var afterWrite: (() -> Void)?
    var ignoreRemove = false
    var afterRemove: (() -> Void)?
    func read(_ key: String) throws -> Data? { values[key] }
    func write(_ data: Data, key: String) throws {
        if dropEnvelope, (try? JSONDecoder().decode(ProjectEditEnvelope.self, from: data)) != nil { return }
        if dropPointer, (try? JSONDecoder().decode(ProjectEditDraftIdentity.self, from: data)) != nil { return }
        values[key] = data; afterWrite?()
    }
    func remove(_ key: String) throws {
        if !ignoreRemove { values.removeValue(forKey: key) }
        afterRemove?()
    }
}

@MainActor final class ProjectLocalSaveReadbackTests: XCTestCase {
    func testDiscardVerifiesRemovalBeforeUnlockingRestoreAndProtectsIdentity() async throws {
        for scenario in ["ignored", "owner", "leave", "removed"] {
            let original = try ProjectEditSession(accountID: 7, epoch: 1, storageNamespace: "discard-readback")
            var session: ProjectEditSession? = original
            let storage = ProjectSaveReadbackStorage(), store = ProjectEditLocalStore(storage: storage)
            let draft = ProjectEditSyntheticFixtures.draft(), initial = ProjectEditSnapshot(draft: draft)
            func make() -> ProjectEditCoordinator {
                .init(initial: initial, service: ProjectEditSyntheticService(snapshot: initial), store: store, currentSession: { session })
            }
            let writer = make(); await writer.load(); XCTAssertTrue(writer.saveLocal(draft))
            let coordinator = make(); await coordinator.load()
            guard case .ready = coordinator.restore else { XCTFail("expected saved draft"); continue }
            storage.ignoreRemove = scenario == "ignored"
            if scenario == "owner" { storage.afterRemove = { session = nil; coordinator.synchronizeSession() } }
            if scenario == "leave" { storage.afterRemove = { coordinator.leaveScreen() } }
            coordinator.discardLocalDraft()
            if scenario == "ignored" {
                XCTAssertEqual(coordinator.messageKey, "projectEdit.localFailed")
                guard case .ready = coordinator.restore else { XCTFail("lost restore protection"); continue }
                XCTAssertFalse(coordinator.saveLocal(initial.draft))
            } else if scenario == "removed" {
                XCTAssertEqual(coordinator.messageKey, "projectEdit.localRemoved")
                guard case .missing = coordinator.restore else { XCTFail("not cleared"); continue }
            } else {
                XCTAssertNotEqual(coordinator.messageKey, "projectEdit.localRemoved")
                if scenario == "owner" { XCTAssertNil(coordinator.identity); XCTAssertNil(coordinator.snapshot) }
                else { guard case .ready = coordinator.restore else { XCTFail("old departure changed restore"); continue } }
            }
            storage.afterRemove = nil; session = original
            let reopened = make(); await reopened.load()
            if scenario == "ignored" {
                XCTAssertEqual(ProjectEditPendingMaterials.exactData(reopened.restoredDraft()), ProjectEditPendingMaterials.exactData(draft))
            } else {
                guard case .missing = reopened.restore else { XCTFail("removed bytes returned on reopen"); continue }
            }
        }
    }

    func testLocalSaveRequiresExactDraftAndRestartPointer() async throws {
        for existing in [false, true] {
            for drop in ["envelope", "pointer", "none"] {
                let session = try ProjectEditSession(accountID: 7, epoch: 1, storageNamespace: "save-readback")
                let storage = ProjectSaveReadbackStorage(), store = ProjectEditLocalStore(storage: storage)
                var original = ProjectEditSyntheticFixtures.draft(); original.baseRevision = "source-revision"
                let initial = ProjectEditSnapshot(topicID: existing ? 71 : nil, scope: .full, draft: original)
                func make() -> ProjectEditCoordinator {
                    .init(initial: initial, service: ProjectEditSyntheticService(snapshot: initial), store: store, currentSession: { session })
                }
                let coordinator = make(); await coordinator.load()
                var edited = original; edited.name = "Author edit"; edited.chapters[0].nodes[0].latitude = "32.5"
                storage.dropEnvelope = drop == "envelope"; storage.dropPointer = drop == "pointer"
                let expected = drop == "none" || (existing && drop == "pointer")
                XCTAssertEqual(coordinator.saveLocal(edited), expected)
                XCTAssertEqual(coordinator.messageKey, expected ? "projectEdit.localSaved" : "projectEdit.localFailed")
                let restarted = make(); await restarted.load()
                if expected {
                    var restoredExpected = edited
                    if existing { restoredExpected.publishToCreative = false }
                    XCTAssertEqual(ProjectEditPendingMaterials.exactData(restarted.restoredDraft()), ProjectEditPendingMaterials.exactData(restoredExpected))
                } else {
                    XCTAssertNil(restarted.restoredDraft())
                }
            }
        }
    }

    func testSilentlyRetainedOldDraftCannotAcknowledgeNewEdits() async throws {
        let session = try ProjectEditSession(accountID: 7, epoch: 1, storageNamespace: "save-old-draft")
        let storage = ProjectSaveReadbackStorage(), store = ProjectEditLocalStore(storage: storage)
        let original = ProjectEditSyntheticFixtures.draft(), initial = ProjectEditSnapshot(draft: original)
        let coordinator = ProjectEditCoordinator(initial: initial, service: ProjectEditSyntheticService(snapshot: initial), store: store, currentSession: { session })
        await coordinator.load(); XCTAssertTrue(coordinator.saveLocal(original))
        var changed = original; changed.name = "Unsaved newer title"
        storage.dropEnvelope = true
        XCTAssertFalse(coordinator.saveLocal(changed))
        XCTAssertEqual(coordinator.messageKey, "projectEdit.localFailed")
        let restarted = ProjectEditCoordinator(initial: initial, service: ProjectEditSyntheticService(snapshot: initial), store: store, currentSession: { session })
        await restarted.load()
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(restarted.restoredDraft()), ProjectEditPendingMaterials.exactData(original))
    }

    func testLocalSaveDoesNotReportSuccessAfterDepartureOrAccountChange() async throws {
        for changeOwner in [false, true] {
            let original = try ProjectEditSession(accountID: 7, epoch: 1, storageNamespace: "save-context")
            var current: ProjectEditSession? = original
            let storage = ProjectSaveReadbackStorage(), store = ProjectEditLocalStore(storage: storage)
            let draft = ProjectEditSyntheticFixtures.draft(), initial = ProjectEditSnapshot(draft: draft)
            let coordinator = ProjectEditCoordinator(initial: initial, service: ProjectEditSyntheticService(snapshot: initial), store: store, currentSession: { current })
            await coordinator.load()
            storage.afterWrite = {
                if changeOwner { current = nil; coordinator.synchronizeSession() }
                else { coordinator.leaveScreen() }
            }
            XCTAssertFalse(coordinator.saveLocal(draft))
            XCTAssertNotEqual(coordinator.messageKey, "projectEdit.localSaved")
            if changeOwner { XCTAssertNil(coordinator.identity); XCTAssertNil(coordinator.snapshot) }
            storage.afterWrite = nil
            let reopened = ProjectEditCoordinator(initial: initial, service: ProjectEditSyntheticService(snapshot: initial), store: store, currentSession: { original })
            await reopened.load()
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(reopened.restoredDraft()), ProjectEditPendingMaterials.exactData(draft))
        }
    }
}
#endif

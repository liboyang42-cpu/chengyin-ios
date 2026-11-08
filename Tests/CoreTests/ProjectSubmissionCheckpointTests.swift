#if DEBUG
import XCTest
@testable import QuestifyCore

@MainActor private final class ProjectCheckpointStorage: ProjectEditDataStorage {
    var values: [String: Data] = [:]
    var drop = ""
    var afterPending: (() -> Void)?
    func read(_ key: String) throws -> Data? { values[key] }
    func write(_ data: Data, key: String) throws {
        let pending = (try? JSONDecoder().decode(ProjectEditPending.self, from: data)) != nil
        if drop == "pending", pending { return }
        if drop == "draft", (try? JSONDecoder().decode(ProjectEditEnvelope.self, from: data)) != nil { return }
        if drop == "pointer", (try? JSONDecoder().decode(ProjectEditDraftIdentity.self, from: data)) != nil { return }
        values[key] = data
        if pending { afterPending?() }
    }
    func remove(_ key: String) throws { values.removeValue(forKey: key) }
}

@MainActor final class ProjectSubmissionCheckpointTests: XCTestCase {
    func testMissingRestartCheckpointNeverDispatches() async throws {
        for drop in ["draft", "pointer", "pending"] {
            let session = try ProjectEditSession(accountID: 7, epoch: 1, storageNamespace: "submit-checkpoint")
            let storage = ProjectCheckpointStorage(), store = ProjectEditLocalStore(storage: storage)
            let draft = ProjectEditSyntheticFixtures.draft(), initial = ProjectEditSnapshot(draft: draft)
            let service = ProjectEditSyntheticService(snapshot: initial)
            let coordinator = ProjectEditCoordinator(initial: initial, service: service, store: store, currentSession: { session })
            await coordinator.load(); coordinator.prepare(draft)
            let review = try XCTUnwrap(coordinator.confirmation)
            storage.drop = drop
            await coordinator.confirm(review)
            XCTAssertTrue(service.submissions.isEmpty)
            XCTAssertEqual(coordinator.state, drop == "pending" ? .unknown : .blocked)
            coordinator.prepare(draft); XCTAssertNil(coordinator.confirmation)
        }
    }
    func testDepartureOrAccountChangeAfterPendingPreservesLockWithoutDispatch() async throws {
        for changeOwner in [false, true] {
            let original = try ProjectEditSession(accountID: 7, epoch: 1, storageNamespace: "submit-context")
            var session: ProjectEditSession? = original
            let storage = ProjectCheckpointStorage(), store = ProjectEditLocalStore(storage: storage)
            let draft = ProjectEditSyntheticFixtures.draft(), initial = ProjectEditSnapshot(draft: draft)
            let service = ProjectEditSyntheticService(snapshot: initial)
            let coordinator = ProjectEditCoordinator(initial: initial, service: service, store: store, currentSession: { session })
            await coordinator.load(); coordinator.prepare(draft)
            let review = try XCTUnwrap(coordinator.confirmation), identity = try XCTUnwrap(coordinator.identity)
            storage.afterPending = {
                if changeOwner { session = nil; coordinator.synchronizeSession() }
                else { coordinator.leaveScreen() }
            }
            await coordinator.confirm(review)
            XCTAssertTrue(service.submissions.isEmpty)
            XCTAssertNotNil(try store.pending(session: original, identity: identity))
            if changeOwner { XCTAssertNil(coordinator.pending); XCTAssertNil(coordinator.identity) }
            else { XCTAssertEqual(coordinator.state, .unknown) }
            storage.afterPending = nil
            let reopened = ProjectEditCoordinator(initial: initial, service: service, store: store, currentSession: { original })
            await reopened.load(); XCTAssertEqual(reopened.state, .unknown)
            reopened.prepare(draft); XCTAssertNil(reopened.confirmation)
        }
    }
}
#endif

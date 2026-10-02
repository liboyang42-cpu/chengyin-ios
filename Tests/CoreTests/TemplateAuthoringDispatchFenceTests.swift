#if DEBUG
import XCTest
@testable import QuestifyCore

@MainActor private final class TemplateFenceStorage: TemplateAuthoringStorage {
    var values: [String: Data] = [:]
    var afterPending: (() -> Void)?
    func read(_ key: String) throws -> Data? { values[key] }
    func write(_ data: Data, key: String) throws {
        values[key] = data
        if (try? JSONDecoder().decode(TemplateAuthoringPending.self, from: data)) != nil { afterPending?() }
    }
    func remove(_ key: String) throws { values.removeValue(forKey: key) }
}
@MainActor final class TemplateAuthoringDispatchFenceTests: XCTestCase {
    func testLeaveFromPendingWriteRetainsLockAndDoesNotSubmit() async throws { try await verify(.leave) }
    func testAccountEpochChangeFromPendingWriteRetainsLockAndDoesNotSubmit() async throws { try await verify(.epoch) }
    func testTaskCancellationFromPendingWriteRetainsLockAndDoesNotSubmit() async throws { try await verify(.cancel) }
    private enum Invalidation: Equatable { case leave, epoch, cancel }
    private func verify(_ invalidation: Invalidation) async throws {
        let original = try TemplateAuthoringSession(accountID: 1, namespace: "template-fence", epoch: 1, authorizationRevision: "member")
        var session: TemplateAuthoringSession? = original
        let storage = TemplateFenceStorage(), store = TemplateAuthoringLocalStore(storage: storage)
        let transport = TemplateAuthoringSyntheticTransport()
        let coordinator = TemplateAuthoringCoordinator(adapter: .init(transport: transport), store: store, currentSession: { session })
        coordinator.open(seed: TemplateAuthoringSyntheticFixtures.draft()); coordinator.prepare(.publish)
        let review = try XCTUnwrap(coordinator.review), identity = coordinator.identity
        var operation: Task<Void, Never>?
        storage.afterPending = {
            switch invalidation {
            case .leave: coordinator.leaveScreen()
            case .epoch:
                session = try? .init(accountID: 1, namespace: "template-fence", epoch: 2, authorizationRevision: "member")
                coordinator.synchronizeSession()
            case .cancel: operation?.cancel()
            }
        }
        operation = Task { await coordinator.confirm(review) }; await operation?.value
        XCTAssertTrue(transport.requests.isEmpty)
        if invalidation == .epoch { XCTAssertNil(coordinator.pending); XCTAssertEqual(coordinator.state, .idle) }
        XCTAssertNotNil(try store.pending(session: original, identity: identity))
        let reopened = TemplateAuthoringCoordinator(store: store, currentSession: { original }); reopened.open()
        XCTAssertTrue(reopened.locked); XCTAssertEqual(reopened.state, .uncertain)
    }
}
#endif

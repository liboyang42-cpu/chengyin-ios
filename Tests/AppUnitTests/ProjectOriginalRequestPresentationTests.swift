import XCTest
import Foundation
@testable import Questify

/// Offline memory-only recovery through the real HTTP service and current editor model.
@MainActor final class ProjectOriginalRequestPresentationTests: XCTestCase {
    private final class Owner {
        var session = try! ProjectEditSession(accountID: 7, epoch: 2, storageNamespace: "project-recovery-presentation")
    }
    private final class Wire: HTTPTransport {
        var paths: [String] = []
        var beforeReply: (() -> Void)?
        let receipt: Data
        init(receipt: Data) { self.receipt = receipt }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            paths.append(request.url!.path)
            if request.url!.path.hasSuffix("/edit-detail") { throw URLError(.notConnectedToInternet) }
            beforeReply?(); return (receipt, 200)
        }
    }
    private struct Fixture {
        let owner: Owner
        let model: ProjectEditModel
        let store: ProjectEditLocalStore
        let original: ProjectEditPending
        let wire: Wire
    }
    private func fixture() throws -> Fixture {
        let owner = Owner(), store = ProjectEditLocalStore(storage: ProjectEditMemoryStorage())
        let draft = ProjectEditSyntheticFixtures.draft(product: .freeExplore), identity = try ProjectEditDraftIdentity(topicID: 71)
        var original = ProjectEditPending(operationID: UUID(), ownerKey: owner.session.ownerKey, identity: identity,
            payload: try ProjectEditContract.payload(draft, topicID: 71, scope: .full))
        original.dispatchStarted = true
        let envelope = try ProjectEditRequestContract.Submit(operationID: original.operationID, originalPath: "api/topic/update", payload: original.payload)
        original.serverRequest = envelope
        try store.save(draft, session: owner.session, identity: identity); try store.savePending(original, session: owner.session)
        let receipt: [String: Any] = ["protocolVersion": envelope.protocolVersion, "requestId": envelope.requestId,
            "originalPath": envelope.originalPath, "payloadSHA256": envelope.payloadSHA256, "state": "COMMITTED",
            "postProcessing": "NOT_RECONCILED", "originalResult": 71]
        let wire = Wire(receipt: try JSONSerialization.data(withJSONObject: ["code": 200, "data": receipt]))
        let configuration = try APIConfiguration(baseURL: URL(string: "https://example.test")!)
        let approval = try OperationEndpointApproval(baseURL: configuration.baseURL, namespace: owner.session.storageNamespace,
            accountID: 7, paths: [ProjectEditRequestContract.readPath])
        let api = ProjectEditHTTPService(configuration: configuration, transport: wire, owner: .personal, approval: approval,
            store: store, currentCredentials: { try? .init(session: owner.session, token: "fixture-only") })
        let coordinator = ProjectEditCoordinator(initial: .init(topicID: 71, draft: draft), service: api,
            store: store, currentSession: { owner.session })
        return .init(owner: owner, model: .init(coordinator: coordinator), store: store, original: original, wire: wire)
    }
    func testOfflineDetailStillAllowsOriginalModelReadAndExplicitContinuation() async throws {
        let f = try fixture(); await f.model.load()
        XCTAssertTrue(f.model.ownsVisit); XCTAssertNil(f.model.coordinator.snapshot)
        XCTAssertTrue(f.model.coordinator.isLocked); XCTAssertTrue(f.model.coordinator.canCheckOutcome)
        XCTAssertFalse(f.model.canReview); XCTAssertFalse(f.model.canSaveLocal)
        await f.model.check()
        XCTAssertEqual(f.model.coordinator.state, .acknowledged)
        XCTAssertEqual(f.model.coordinator.pending?.completedTopicID, 71)
        XCTAssertEqual(f.model.coordinator.pending?.serverRequest, f.original.serverRequest)
        XCTAssertNil(f.model.coordinator.snapshot); XCTAssertFalse(f.model.canReview)
        let continuation = try XCTUnwrap(f.model.coordinator.acknowledgedContinuation)
        await f.model.continueAcknowledged(continuation)
        // A failed fresh detail read retains the known original result and cannot reopen writing.
        XCTAssertEqual(f.model.coordinator.state, .acknowledged); XCTAssertFalse(f.model.canReview)
        XCTAssertEqual(try f.store.pending(session: f.owner.session, identity: f.original.identity)?.serverRequest, f.original.serverRequest)
        XCTAssertEqual(f.wire.paths, ["/api/topic/edit-detail", "/api/topic/edit-requests/read", "/api/topic/edit-detail"])
    }
    func testOwnerChangesDuringOfflineRecoveryKeepOldDurableIntentPrivate() async throws {
        let f = try fixture(), originalOwner = f.owner.session; await f.model.load()
        f.wire.beforeReply = {
            f.owner.session = try! .init(accountID: 8, epoch: 3, storageNamespace: originalOwner.storageNamespace)
            f.model.coordinator.synchronizeSession()
        }
        await f.model.check()
        XCTAssertNil(f.model.coordinator.pending); XCTAssertNil(f.model.coordinator.snapshot)
        XCTAssertNil(f.model.submissionEvidence); XCTAssertFalse(f.model.canReview)
        XCTAssertEqual(try f.store.pending(session: originalOwner, identity: f.original.identity), f.original)
        XCTAssertEqual(f.wire.paths, ["/api/topic/edit-detail", "/api/topic/edit-requests/read"])
    }
}

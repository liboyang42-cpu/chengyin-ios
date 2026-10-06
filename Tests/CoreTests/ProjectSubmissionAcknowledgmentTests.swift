import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class ProjectSubmissionAcknowledgmentTests: XCTestCase {
    private let raw = #"{"topicId":7901,"auditTaskId":3301,"reviewState":"PENDING","published":true,"bundledTemplateIds":[41,73]}"#
    private func acknowledgment() throws -> ProjectEditBundleAcknowledgment {
        try JSONDecoder().decode(ProjectEditBundleAcknowledgment.self, from: Data(raw.utf8))
    }
    private func session() throws -> ProjectEditSession { try .init(accountID: 7, epoch: 1, storageNamespace: "submission-test") }
    private func pending(_ session: ProjectEditSession) throws -> ProjectEditPending {
        var draft = ProjectEditSyntheticFixtures.draft(); draft.name = "Captured e\u{301}\n"
        return try .init(operationID: UUID(), ownerKey: session.ownerKey, identity: .init(), payload: ProjectEditContract.payload(draft, topicID: nil, scope: .full))
    }
    private func completed(_ session: ProjectEditSession) throws -> ProjectEditPending {
        var value = try pending(session); value.completedTopicID = 7901; value.serverAcknowledged = true; value.bundleAcknowledgment = try acknowledgment(); return value
    }
    private final class Wire: HTTPTransport {
        let reply: Data; var requests: [URLRequest] = []
        init(_ reply: Data) { self.reply = reply }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            if request.url?.path == "/api/publish/home" { return (Data(#"{"code":200,"data":{"permission":{"canProPublish":true},"quota":{"themesRemaining":2}}}"#.utf8), 200) }
            return (reply, 200)
        }
    }
    func testActualHTTPServiceToCoordinatorPersistsV2MetadataWithoutResending() async throws {
        let s = try session(), storage = ProjectEditMemoryStorage(), store = ProjectEditLocalStore(storage: storage), draft = ProjectEditSyntheticFixtures.draft()
        let configuration = try APIConfiguration(baseURL: URL(string: "https://example.com")!)
        let wire = Wire(Data(("{\"code\":200,\"data\":" + raw + "}").utf8))
        let credentials = try ProjectEditCredentials(session: s, token: "synthetic-only-token")
        let approval = try OperationEndpointApproval(baseURL: configuration.baseURL, namespace: s.storageNamespace, accountID: s.accountID, paths: [ProjectEditStoryContract.createPath])
        let service = ProjectEditHTTPService(configuration: configuration, transport: wire, owner: .personal, approval: approval, store: store, currentCredentials: { credentials })
        let co = ProjectEditCoordinator(initial: .init(draft: draft), service: service, store: store, currentSession: { s })
        await co.load(); co.prepare(draft); await co.confirm(try XCTUnwrap(co.confirmation))
        XCTAssertEqual(co.state, .acknowledged); XCTAssertEqual(co.pending?.bundleAcknowledgment, try acknowledgment())
        XCTAssertEqual(wire.requests.filter { $0.url?.path == "/api/topic/v2/create" }.count, 1)
        XCTAssertEqual(wire.requests.map { $0.url?.path }, ["/api/publish/home", "/api/publish/home", "/api/topic/v2/create"])
        let reopened = ProjectEditCoordinator(initial: .init(draft: draft), service: service, store: store, currentSession: { s })
        await reopened.load(); XCTAssertEqual(reopened.pending?.bundleAcknowledgment?.auditTaskID, 3301)
        XCTAssertEqual(reopened.state, .acknowledged); XCTAssertEqual(wire.requests.filter { $0.url?.path == "/api/topic/v2/create" }.count, 1)
    }
    func testActualHTTPDecoderRetainsSubmissionTaskButDoesNotInventApproval() throws {
        let op = try pending(session()), body = Data(("{\"code\":200,\"data\":" + raw + "}").utf8)
        guard case .bundleAcknowledged(let id, let ack) = ProjectEditHTTPService.decodeAcknowledgment(body, status: 200, operation: op) else { return XCTFail("V2 metadata was dropped") }
        XCTAssertEqual(id, op.operationID); XCTAssertEqual(ack.auditTaskID, 3301); XCTAssertEqual(ack.topicID, 7901)
        XCTAssertEqual(ack.reviewState, "PENDING"); XCTAssertTrue(ack.published); XCTAssertEqual(ack.bundledTemplateIDs, [41, 73])
    }
    func testAcknowledgmentCodableRoundTripRetainsAllSourceFields() throws {
        let value = try acknowledgment(), data = try JSONEncoder().encode(value)
        XCTAssertEqual(try JSONDecoder().decode(ProjectEditBundleAcknowledgment.self, from: data), value)
        let json = try JSONDecoder().decode(ProjectEditJSON.self, from: data).object
        XCTAssertEqual(Set(try XCTUnwrap(json).keys), Set(["topicId", "auditTaskId", "reviewState", "published", "bundledTemplateIds"]))
    }
    func testStoredAcknowledgmentCannotClaimApprovedOrAcceptInvalidTask() throws {
        for changed in [raw.replacingOccurrences(of: "PENDING", with: "APPROVED"), raw.replacingOccurrences(of: "3301", with: "0"), raw.replacingOccurrences(of: "[41,73]", with: "[41,41]"), raw.replacingOccurrences(of: "true", with: "1")] {
            XCTAssertThrowsError(try JSONDecoder().decode(ProjectEditBundleAcknowledgment.self, from: Data(changed.utf8)))
        }
    }
    func testCompletedEnvelopeRestoresExactTaskAndLegacyVisibility() throws {
        let s = try session(), storage = ProjectEditMemoryStorage(), store = ProjectEditLocalStore(storage: storage), value = try completed(s)
        try store.savePending(value, session: s)
        let restored = try XCTUnwrap(try store.pending(session: s, identity: value.identity))
        XCTAssertTrue(ProjectEditLocalStore.exactPending(restored, value)); XCTAssertEqual(restored.bundleAcknowledgment, value.bundleAcknowledgment)
        var differentDraft = ProjectEditSyntheticFixtures.draft(); differentDraft.name = "Later mutable title"
        let handoff = try XCTUnwrap(PublishingSubmissionHandoff(pending: restored, draft: differentDraft))
        XCTAssertEqual(Array(handoff.title.utf8), Array("Captured e\u{301}\n".utf8)); XCTAssertEqual(handoff.bundleAcknowledgment?.auditTaskID, 3301)
    }
    func testOldCompletionWithoutNewFieldRemainsReadable() throws {
        let s = try session(); var value = try completed(s); value.bundleAcknowledgment = nil
        let data = try JSONEncoder().encode(value), raw = try JSONDecoder().decode(ProjectEditJSON.self, from: data)
        XCTAssertNil(raw.object?["bundleAcknowledgment"])
        let restored = try JSONDecoder().decode(ProjectEditPending.self, from: data)
        XCTAssertTrue(restored.hasConsistentAcknowledgment); XCTAssertNil(restored.bundleAcknowledgment)
        XCTAssertNotNil(PublishingSubmissionHandoff(pending: restored, draft: .init()))
    }
    func testContradictoryCompletionOrLegacyPathCannotPersistBundleEvidence() throws {
        let s = try session(), storage = ProjectEditMemoryStorage(), store = ProjectEditLocalStore(storage: storage)
        var value = try completed(s); value.completedTopicID = 7902; XCTAssertThrowsError(try store.savePending(value, session: s))
        value = try completed(s); value.serverAcknowledged = false; XCTAssertThrowsError(try store.savePending(value, session: s))
        let bad = ProjectEditPending(operationID: value.operationID, ownerKey: s.ownerKey, identity: value.identity,
            payload: ["name": .string("Legacy")], completedTopicID: 7901, serverAcknowledged: true, bundleAcknowledgment: try acknowledgment())
        XCTAssertThrowsError(try store.savePending(bad, session: s)); XCTAssertTrue(storage.data.isEmpty)
    }
    func testMalformedStoredEvidenceFailsClosedWithoutRemovingOriginalBytes() throws {
        let s = try session(), storage = ProjectEditMemoryStorage(), store = ProjectEditLocalStore(storage: storage), value = try completed(s)
        try store.savePending(value, session: s); let key = try XCTUnwrap(storage.data.keys.first)
        let bytes = try XCTUnwrap(storage.data[key]); storage.data[key] = Data(String(decoding: bytes, as: UTF8.self).replacingOccurrences(of: "PENDING", with: "APPROVED").utf8)
        let before = storage.data; XCTAssertThrowsError(try store.pending(session: s, identity: value.identity)); XCTAssertEqual(storage.data, before)
    }
    func testUnknownOutcomeHasNoManufacturedAcknowledgment() throws {
        let value = try pending(session()); XCTAssertNil(value.bundleAcknowledgment); XCTAssertNil(PublishingSubmissionHandoff(pending: value, draft: .init()))
        let body = Data(("{\"code\":200,\"data\":" + raw.replacingOccurrences(of: "3301", with: "0") + "}").utf8)
        XCTAssertEqual(ProjectEditHTTPService.decodeAcknowledgment(body, status: 200, operation: value), .unknown)
    }
    func testCoordinatorPersistsExactAcknowledgmentAcrossRecreation() async throws {
        let s = try session(), storage = ProjectEditMemoryStorage(), store = ProjectEditLocalStore(storage: storage), draft = ProjectEditSyntheticFixtures.draft()
        let service = ProjectEditSyntheticService(scenario: .bundlePending)
        let co = ProjectEditCoordinator(initial: .init(draft: draft), service: service, store: store, currentSession: { s })
        await co.load(); co.prepare(draft); await co.confirm(try XCTUnwrap(co.confirmation))
        XCTAssertEqual(co.state, .acknowledged); XCTAssertFalse(co.isLocked); XCTAssertEqual(co.pending?.bundleAcknowledgment?.auditTaskID, 3301)
        let recreated = ProjectEditCoordinator(initial: .init(draft: draft), service: service, store: store, currentSession: { s })
        await recreated.load(); XCTAssertEqual(recreated.state, .acknowledged); XCTAssertEqual(recreated.pending, co.pending); XCTAssertEqual(service.submissions.count, 1)
    }
    func testAcknowledgmentPersistenceFailureKeepsUnknownLock() async throws {
        let s = try session(), storage = ProjectEditMemoryStorage(), store = ProjectEditLocalStore(storage: storage), draft = ProjectEditSyntheticFixtures.draft()
        let service = ProjectEditSyntheticService(scenario: .bundlePending); service.beforeSubmit = { storage.failWrites = true }
        let co = ProjectEditCoordinator(initial: .init(draft: draft), service: service, store: store, currentSession: { s })
        await co.load(); co.prepare(draft); await co.confirm(try XCTUnwrap(co.confirmation))
        XCTAssertEqual(co.state, .unknown); XCTAssertTrue(co.isLocked); XCTAssertNil(co.pending?.bundleAcknowledgment)
        let stored = try XCTUnwrap(try store.pending(session: s, identity: XCTUnwrap(co.identity)))
        XCTAssertNil(stored.completedTopicID); XCTAssertNil(stored.bundleAcknowledgment); XCTAssertEqual(service.submissions.count, 1)
    }
    func testSessionChangeDuringAcknowledgmentDoesNotAttachOldFactsToNewOwner() async throws {
        let original = try session(); var current: ProjectEditSession? = original
        let storage = ProjectEditMemoryStorage(), store = ProjectEditLocalStore(storage: storage), draft = ProjectEditSyntheticFixtures.draft(), service = ProjectEditSyntheticService(scenario: .bundlePending)
        service.beforeSubmit = { current = try? .init(accountID: 8, epoch: 2, storageNamespace: "submission-test") }
        let co = ProjectEditCoordinator(initial: .init(draft: draft), service: service, store: store, currentSession: { current })
        await co.load(); co.prepare(draft); let value = try XCTUnwrap(co.confirmation); let identity = try XCTUnwrap(co.identity)
        await co.confirm(value); co.synchronizeSession(); XCTAssertNil(co.pending)
        let old = try XCTUnwrap(try store.pending(session: original, identity: identity)); XCTAssertNil(old.bundleAcknowledgment); XCTAssertNil(old.completedTopicID)
        XCTAssertNil(try store.pending(session: XCTUnwrap(current), identity: identity)); XCTAssertEqual(service.submissions.count, 1)
    }
}

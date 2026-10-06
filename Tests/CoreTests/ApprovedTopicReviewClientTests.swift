import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class ApprovedTopicReviewClientTests: XCTestCase {
    private func session(_ account: Int = 7, epoch: UInt64 = 1) throws -> ProjectEditSession { try .init(accountID: account, epoch: epoch, storageNamespace: "review-client-tests") }
    private func origin(_ s: ProjectEditSession) throws -> ApprovedTopicReleaseReadTarget {
        let ack = try ProjectEditBundleAcknowledgment.decode(.object(["topicId": .number(7901), "auditTaskId": .number(3301), "reviewState": .string("PENDING"), "published": .bool(true), "bundledTemplateIds": .array([.number(41)])]), expectedTopicID: nil)
        let pending = try ProjectEditPending(operationID: UUID(), ownerKey: s.ownerKey, identity: .init(), payload: ProjectEditContract.payload(ProjectEditSyntheticFixtures.draft(), topicID: nil, scope: .full), completedTopicID: 7901, serverAcknowledged: true, bundleAcknowledgment: ack)
        return try XCTUnwrap(ApprovedTopicReleaseReadTarget(pending: pending, session: s))
    }
    @MainActor private final class Wire: HTTPTransport {
        var requests: [URLRequest] = []
        var status = 200, hold = false, empty = false
        var started: XCTestExpectation?
        var continuation: CheckedContinuation<(Data, Int), Error>?
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request); started?.fulfill()
            if hold { return try await withCheckedThrowingContinuation { continuation = $0 } }
            return try response()
        }
        func response() throws -> (Data, Int) {
            if empty { return (Data(), status) }
            return (try JSONEncoder().encode(["code": ProjectEditJSON.number(Decimal(status)), "data": ApprovedTopicReviewSynthetic.captureFields()]), status)
        }
        func finish() throws { let next = continuation; continuation = nil; next?.resume(returning: try response()) }
    }
    private func client(_ s: ProjectEditSession, wire: Wire, paths: Set<String>?, current: @escaping () -> ApprovedTopicReviewCredentials?, permits: @escaping (String) -> Bool = { _ in true }) throws -> ApprovedTopicReviewClient {
        let config = try APIConfiguration(baseURL: URL(string: "https://example.com")!)
        let approval = try paths.map { try OperationEndpointApproval(baseURL: config.baseURL, namespace: s.storageNamespace, accountID: s.accountID, paths: $0) }
        return .init(configuration: config, approval: approval, transport: wire, currentCredentials: current, currentCapability: permits)
    }
    func testDefaultAndAdjacentCapabilitiesDispatchNothing() async throws {
        let s = try session(), target = try origin(s), credentials = try ApprovedTopicReviewCredentials(session: s, token: "synthetic"), wire = Wire()
        let pathSets: [Set<String>?] = [nil, [ApprovedTopicReleasePaths.prepare], [ApprovedTopicReleasePublicationPath.publish], ["api/topic/v2/create"]]
        for paths in pathSets {
            let service = try client(s, wire: wire, paths: paths, current: { credentials })
            XCTAssertFalse(service.canPrepare(session: s)); XCTAssertFalse(service.canSubmit(session: s))
            do { _ = try await service.prepare(target, session: s); XCTFail("unconfigured") } catch { XCTAssertEqual(error as? ApprovedTopicReleaseError, .notConfigured) }
        }
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testPrepareSendsOnlyCapturedTopicAndObservedTaskUnderExactReadGrant() async throws {
        let s = try session(), target = try origin(s), credentials = try ApprovedTopicReviewCredentials(session: s, token: "synthetic"), wire = Wire()
        let service = try client(s, wire: wire, paths: [ApprovedTopicReviewPath.prepare], current: { credentials })
        let value = try await service.prepare(target, session: s); XCTAssertEqual(value.observedAuditTaskID, 3301)
        XCTAssertFalse(service.canSubmit(session: s)); XCTAssertFalse(service.canReadStatus(session: s))
        let request = try XCTUnwrap(wire.requests.first), body = try JSONDecoder().decode([String: ProjectEditJSON].self, from: XCTUnwrap(request.httpBody))
        XCTAssertEqual(request.httpMethod, "POST"); XCTAssertEqual(request.url?.path, "/" + ApprovedTopicReviewPath.prepare)
        XCTAssertEqual(body, ["topicId": .number(7901), "observedAuditTaskId": .number(3301)])
    }
    func testQueuedSecondLoadCannotReplaceTheOwnedReadAndCloseDropsLate401() async throws {
        let s = try session(), target = try origin(s), wire = Wire(); wire.hold = true; wire.started = expectation(description: "first actual transport")
        let credentials = try ApprovedTopicReviewCredentials(session: s, token: "synthetic"), service = try client(s, wire: wire, paths: [ApprovedTopicReviewPath.prepare], current: { credentials })
        let flow = ApprovedTopicReviewFlow(origin: target, session: s, source: service, journal: .init(storage: ProjectEditMemoryStorage()), stillCurrent: { true })
        let first = Task { await flow.load() }; await fulfillment(of: [try XCTUnwrap(wire.started)], timeout: 2)
        await flow.load(); XCTAssertEqual(wire.requests.count, 1); XCTAssertEqual(flow.state, .loading)
        flow.close(); wire.status = 401; wire.empty = true; try wire.finish(); await first.value
        XCTAssertEqual(flow.state, .closed); XCTAssertEqual(wire.requests.count, 1)
    }
    func testCurrentEmpty401IsUnauthorizedButChangedAccountResponseCannotMutateFlow() async throws {
        let s = try session(), target = try origin(s), wire = Wire(); wire.status = 401; wire.empty = true
        var credentials: ApprovedTopicReviewCredentials? = try .init(session: s, token: "synthetic")
        let service = try client(s, wire: wire, paths: [ApprovedTopicReviewPath.prepare], current: { credentials })
        let current = ApprovedTopicReviewFlow(origin: target, session: s, source: service, journal: .init(storage: ProjectEditMemoryStorage()), stillCurrent: { true }); await current.load(); XCTAssertEqual(current.state, .unauthorized)
        wire.hold = true; wire.started = expectation(description: "owned second transport")
        let changed = ApprovedTopicReviewFlow(origin: target, session: s, source: service, journal: .init(storage: ProjectEditMemoryStorage()), stillCurrent: { true })
        let task = Task { await changed.load() }; await fulfillment(of: [try XCTUnwrap(wire.started)], timeout: 2)
        credentials = try .init(session: session(8, epoch: 2), token: "replacement-synthetic"); try wire.finish(); await task.value
        XCTAssertEqual(changed.state, .closed); XCTAssertEqual(credentials?.session.accountID, 8)
    }
    func testRevokedPreparePermissionCannotReturnOldCapturedContent() async throws {
        let s = try session(), target = try origin(s), wire = Wire(); wire.hold = true; wire.started = expectation(description: "permission-bound read")
        let credentials = try ApprovedTopicReviewCredentials(session: s, token: "synthetic"); var granted = true
        let service = try client(s, wire: wire, paths: [ApprovedTopicReviewPath.prepare], current: { credentials }, permits: { _ in granted })
        let flow = ApprovedTopicReviewFlow(origin: target, session: s, source: service, journal: .init(storage: ProjectEditMemoryStorage()), stillCurrent: { true })
        let task = Task { await flow.load() }; await fulfillment(of: [try XCTUnwrap(wire.started)], timeout: 2); granted = false; try wire.finish(); await task.value
        XCTAssertEqual(flow.state, .closed); XCTAssertEqual(wire.requests.count, 1)
    }
    func testRecordFromAnotherOwnerCannotDispatchEvenWithNewOwnersSubmitGrant() async throws {
        let s = try session(), journal = ApprovedTopicReviewJournal(storage: ProjectEditMemoryStorage()), target = try origin(s)
        let c = try ApprovedTopicReviewCapture.decode(ApprovedTopicReviewSynthetic.captureFields(), topicID: 7901, observedAuditTaskID: 3301)
        let saved = try journal.begin(c, origin: target, expected: journal.read(session: s, topicID: 7901), session: s), record = try XCTUnwrap(saved.current)
        let other = try session(8), wire = Wire(), credentials = try ApprovedTopicReviewCredentials(session: other, token: "synthetic")
        let service = try client(other, wire: wire, paths: [ApprovedTopicReviewPath.submit], current: { credentials })
        do { _ = try await service.submit(record, session: other); XCTFail("foreign owner") } catch { XCTAssertEqual(error as? ApprovedTopicReleaseError, .changedContext) }
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testFeatureRegistryKeepsAllThreeOperationsIndependentAndDefaultOff() throws {
        let configuration = try BusinessRuntimeConfiguration(market: .china, baseURL: URL(string: "https://example.com")!, namespace: "review-client-tests", accountID: 7)
        XCTAssertTrue(configuration.routes.isEmpty)
        XCTAssertTrue(BusinessRuntimeFeature.approvedTopicReviewPrepare.accepts(try .post(ApprovedTopicReviewPath.prepare)))
        XCTAssertFalse(BusinessRuntimeFeature.approvedTopicReviewPrepare.accepts(try .post(ApprovedTopicReviewPath.submit)))
        XCTAssertFalse(BusinessRuntimeFeature.approvedTopicReleasePublish.accepts(try .post(ApprovedTopicReviewPath.submit)))
        XCTAssertFalse(BusinessRuntimeFeature.projectWrite.accepts(try .post(ApprovedTopicReviewPath.submit)))
    }
}

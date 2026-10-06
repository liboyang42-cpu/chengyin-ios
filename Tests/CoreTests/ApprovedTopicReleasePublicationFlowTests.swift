import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class ApprovedTopicReleasePublicationFlowTests: XCTestCase {
    private final class Owner {
        var session: ProjectEditSession? = try? .init(accountID: 7, epoch: 1, storageNamespace: "publication-flow-test")
        var credentials: ApprovedTopicReleasePublicationCredentials? { session.flatMap { try? .init(session: $0, token: "synthetic-token") } }
    }
    @MainActor private final class Wire: HTTPTransport {
        var requests: [URLRequest] = []
        var status = 200
        var badManifest = false
        var hold = false
        var started: XCTestExpectation?
        var continuation: CheckedContinuation<(Data, Int), Error>?
        var onSend: (() throws -> Void)?
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request); try onSend?()
            if hold { return try await withCheckedThrowingContinuation { continuation = $0; started?.fulfill() } }
            return try reply(request, status: status)
        }
        func reply(_ request: URLRequest, status: Int) throws -> (Data, Int) {
            guard status == 200 else { return (try JSONEncoder().encode(["code": status]), status) }
            let command = try JSONDecoder().decode([String: ProjectEditJSON].self, from: XCTUnwrap(request.httpBody))
            let row: ProjectEditJSON = .object(["releaseId": .number(501), "topicId": command["topicId"]!, "sourceConfigVersion": .number(1),
                "auditTaskId": command["auditTaskId"]!, "auditRecordId": .number(81), "auditTaskVersion": command["auditTaskVersion"]!, "schemaVersion": .number(1),
                "manifestHash": badManifest ? .string(String(repeating: "f", count: 64)) : command["expectedManifestHash"]!, "auditSnapshotHash": command["auditSnapshotHash"]!, "currentlyApproved": .bool(true)])
            return (try JSONEncoder().encode(["code": ProjectEditJSON.number(200), "data": row]), 200)
        }
        func finish(_ status: Int) throws { let value = continuation; continuation = nil; value?.resume(returning: try reply(XCTUnwrap(requests.last), status: status)) }
    }
    private func prepared(_ newer: Bool = false) throws -> ApprovedTopicReleasePreparation {
        var root = try XCTUnwrap(ApprovedTopicReleaseWire.envelope(ApprovedTopicReleaseSyntheticSource.preparationData())["data"]?.object)
        if newer { root["auditTaskVersion"] = .number(3); root["headRevision"] = .number(1) }
        return try .decode(.object(root), topicID: 7901, auditTaskID: 3301)
    }
    private func client(_ owner: Owner, wire: Wire, paths: Set<String>?) throws -> ApprovedTopicReleasePublicationClient {
        let session = try XCTUnwrap(owner.session), configuration = try APIConfiguration(baseURL: URL(string: "https://example.com")!)
        let approval = try paths.map { try OperationEndpointApproval(baseURL: configuration.baseURL, namespace: session.storageNamespace, accountID: session.accountID, paths: $0) }
        return .init(configuration: configuration, approval: approval, transport: wire, currentCredentials: { owner.credentials })
    }
    private func setup() throws -> (Owner, Wire, ProjectEditMemoryStorage, ApprovedTopicReleasePublicationJournal, ApprovedTopicReleasePublicationClient, ApprovedTopicReleasePublishFlow) {
        let owner = Owner(), wire = Wire(), storage = ProjectEditMemoryStorage(), journal = ApprovedTopicReleasePublicationJournal(storage: storage)
        let source = try client(owner, wire: wire, paths: [ApprovedTopicReleasePublicationPath.publish, ApprovedTopicReleasePublicationPath.status]), session = try XCTUnwrap(owner.session)
        let flow = ApprovedTopicReleasePublishFlow(session: session, topicID: 7901, source: source, journal: journal, stillCurrent: { owner.session == session })
        flow.reload(); return (owner, wire, storage, journal, source, flow)
    }
    func testPrepareOrLegacyGrantsCannotDispatchPublicationOrStatus() async throws {
        let owner = Owner(), wire = Wire(), storage = ProjectEditMemoryStorage(), journal = ApprovedTopicReleasePublicationJournal(storage: storage), session = try XCTUnwrap(owner.session)
        let record = try XCTUnwrap(journal.begin(prepared(), expected: journal.read(session: session, topicID: 7901), session: session).current)
        let pathSets: [Set<String>?] = [nil, [ApprovedTopicReleasePaths.prepare], ["api/topic/v2/create"]]
        for paths in pathSets {
            let source = try client(owner, wire: wire, paths: paths); XCTAssertFalse(source.canPublish(session: session)); XCTAssertFalse(source.canCheckStatus(session: session))
            do { _ = try await source.publish(record, session: session); XCTFail() } catch { XCTAssertEqual(error as? ApprovedTopicReleaseError, .notConfigured) }
            do { _ = try await source.status(record, session: session); XCTFail() } catch { XCTAssertEqual(error as? ApprovedTopicReleaseError, .notConfigured) }
        }
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testClaimPersistsBeforeActualHttpAndDuplicateConfirmationCannotGenerateSecondRequest() async throws {
        let (owner, wire, _, journal, _, flow) = try setup(), session = try XCTUnwrap(owner.session)
        let original = try XCTUnwrap(flow.review(prepared())), claim = try XCTUnwrap(flow.claim(original))
        let pending = try journal.read(session: session, topicID: 7901); XCTAssertNil(flow.claim(original)); XCTAssertTrue(wire.requests.isEmpty)
        wire.onSend = { XCTAssertEqual(try journal.read(session: session, topicID: 7901), pending) }
        await flow.submit(claim)
        guard case .known(let receipt) = flow.state else { return XCTFail() }
        XCTAssertEqual(receipt.releaseID, 501); XCTAssertEqual(wire.requests.count, 1)
        let request = try XCTUnwrap(wire.requests.first); XCTAssertEqual(request.url?.path, "/api/approved-topic-release/v1/publish")
        XCTAssertEqual(try JSONDecoder().decode([String: ProjectEditJSON].self, from: XCTUnwrap(request.httpBody)), pending.current?.command.fields)
        await flow.submit(claim); XCTAssertEqual(wire.requests.count, 1)
    }
    func testCancelledOldConfirmationCannotCancelOrClaimNewReview() throws {
        let (_, wire, storage, _, _, flow) = try setup()
        let old = try XCTUnwrap(flow.review(prepared())); flow.cancel(old)
        XCTAssertTrue(storage.data.isEmpty); XCTAssertTrue(wire.requests.isEmpty)
        let current = try XCTUnwrap(flow.review(prepared())); flow.cancel(old)
        XCTAssertEqual(flow.confirmation?.id, current.id); XCTAssertNil(flow.claim(old)); XCTAssertNotNil(flow.claim(current))
    }
    func testCloseAfterClaimBeforeQueuedTaskRetainsIntentButDispatchesNothing() async throws {
        let (owner, wire, _, journal, source, flow) = try setup(), session = try XCTUnwrap(owner.session)
        let claim = try XCTUnwrap(flow.claim(XCTUnwrap(flow.review(prepared())))), pending = try journal.read(session: session, topicID: 7901)
        flow.close(); await flow.submit(claim); XCTAssertTrue(wire.requests.isEmpty); XCTAssertEqual(flow.state, .closed)
        XCTAssertEqual(try journal.read(session: session, topicID: 7901), pending)
        let reopened = ApprovedTopicReleasePublishFlow(session: session, topicID: 7901, source: source, journal: journal, stillCurrent: { true }); reopened.reload()
        XCTAssertEqual(reopened.state, .unconfirmed); wire.status = 409; await reopened.checkStatus(try XCTUnwrap(reopened.snapshot))
        XCTAssertEqual(wire.requests.count, 1); XCTAssertEqual(wire.requests[0].url?.path, "/api/approved-topic-release/v1/status"); XCTAssertEqual(reopened.state, .unconfirmed)
    }
    func testActualFirstTransportRemainsOwnedAcrossQueuedSecondReadAndCloseBefore401() async throws {
        let (owner, wire, _, journal, _, flow) = try setup(), session = try XCTUnwrap(owner.session)
        let claim = try XCTUnwrap(flow.claim(XCTUnwrap(flow.review(prepared())))), pending = try XCTUnwrap(flow.snapshot)
        wire.hold = true; let started = expectation(description: "publication held"); wire.started = started
        let first = Task { await flow.submit(claim) }; await fulfillment(of: [started], timeout: 3)
        await flow.submit(claim); await flow.checkStatus(pending); XCTAssertEqual(wire.requests.count, 1)
        flow.close(); try wire.finish(401); await first.value
        XCTAssertEqual(flow.state, .closed); XCTAssertEqual(try journal.read(session: session, topicID: 7901), pending)
    }
    func testUnknownResponseReopensIntoStatusForExactOriginalBodyWithoutNewPublish() async throws {
        let (owner, wire, _, journal, source, flow) = try setup(), session = try XCTUnwrap(owner.session)
        let claim = try XCTUnwrap(flow.claim(XCTUnwrap(flow.review(prepared())))); wire.status = 503; await flow.submit(claim)
        XCTAssertEqual(flow.state, .unconfirmed); let originalBody = wire.requests[0].httpBody; flow.close()
        let reopened = ApprovedTopicReleasePublishFlow(session: session, topicID: 7901, source: source, journal: journal, stillCurrent: { true }); reopened.reload(); wire.status = 200
        await reopened.checkStatus(try XCTUnwrap(reopened.snapshot))
        guard case .known(let receipt) = reopened.state else { return XCTFail() }; XCTAssertEqual(receipt.releaseID, 501)
        XCTAssertEqual(wire.requests.count, 2); XCTAssertEqual(wire.requests[1].url?.path, "/api/approved-topic-release/v1/status")
        XCTAssertEqual(try JSONDecoder().decode([String: ProjectEditJSON].self, from: XCTUnwrap(originalBody)), try JSONDecoder().decode([String: ProjectEditJSON].self, from: XCTUnwrap(wire.requests[1].httpBody)))
    }
    func testFailedReceiptPersistenceKeepsPendingAndExplicitStatusCanRecover() async throws {
        let (_, wire, storage, _, _, flow) = try setup()
        let claim = try XCTUnwrap(flow.claim(XCTUnwrap(flow.review(prepared())))), pending = try XCTUnwrap(flow.snapshot), before = storage.data
        wire.onSend = { storage.failWrites = true }; await flow.submit(claim)
        XCTAssertEqual(flow.state, .unconfirmed); XCTAssertEqual(storage.data, before); XCTAssertNil(flow.snapshot?.current?.receipt)
        storage.failWrites = false; wire.onSend = nil; await flow.checkStatus(pending)
        guard case .known = flow.state else { return XCTFail() }; XCTAssertEqual(wire.requests.count, 2)
    }
    func testRetainedStatusAndRetryActionsCannotActOnNewerEntry() async throws {
        let (_, wire, _, _, _, flow) = try setup()
        let first = try XCTUnwrap(flow.claim(XCTUnwrap(flow.review(prepared())))), old = try XCTUnwrap(flow.snapshot); await flow.submit(first)
        let second = try XCTUnwrap(flow.claim(XCTUnwrap(flow.review(prepared(true))))), current = try XCTUnwrap(flow.snapshot)
        await flow.checkStatus(old); await flow.retryExact(old); XCTAssertEqual(wire.requests.count, 1); XCTAssertEqual(flow.snapshot, current)
        await flow.submit(second); XCTAssertEqual(wire.requests.count, 2)
    }
    func testAccountChangeBeforeLate401ClosesFlowWithoutResolvingOriginalIntent() async throws {
        let (owner, wire, storage, _, _, flow) = try setup()
        let claim = try XCTUnwrap(flow.claim(XCTUnwrap(flow.review(prepared())))), before = storage.data
        wire.hold = true; let started = expectation(description: "held before account change"); wire.started = started
        let task = Task { await flow.submit(claim) }; await fulfillment(of: [started], timeout: 3)
        owner.session = try .init(accountID: 8, epoch: 2, storageNamespace: "publication-flow-test")
        try wire.finish(401); await task.value
        XCTAssertEqual(flow.state, .closed); XCTAssertEqual(storage.data, before); XCTAssertEqual(owner.session?.accountID, 8)
    }
    func testWrongManifestReceiptNeverBecomesKnownOrClearsPending() async throws {
        let (_, wire, storage, _, _, flow) = try setup()
        let claim = try XCTUnwrap(flow.claim(XCTUnwrap(flow.review(prepared())))), before = storage.data
        wire.badManifest = true; await flow.submit(claim)
        XCTAssertEqual(flow.state, .unconfirmed); XCTAssertEqual(storage.data, before); XCTAssertNil(flow.snapshot?.current?.receipt)
    }
    func testFailedInitialPersistenceCannotReturnAClaimOrDispatch() async throws {
        let (_, wire, storage, _, _, flow) = try setup(), confirmation = try XCTUnwrap(flow.review(prepared()))
        storage.failWrites = true; XCTAssertNil(flow.claim(confirmation)); XCTAssertEqual(flow.state, .unavailable)
        XCTAssertTrue(wire.requests.isEmpty); XCTAssertTrue(storage.data.isEmpty)
    }
    func testRevokingOnlyPublishCapabilityCannotBorrowStillApprovedStatusRoute() async throws {
        let owner = Owner(), wire = Wire(), storage = ProjectEditMemoryStorage(), journal = ApprovedTopicReleasePublicationJournal(storage: storage), session = try XCTUnwrap(owner.session)
        let record = try XCTUnwrap(journal.begin(prepared(), expected: journal.read(session: session, topicID: 7901), session: session).current)
        let api = try APIConfiguration(baseURL: URL(string: "https://example.com")!)
        let approval = try OperationEndpointApproval(baseURL: api.baseURL, namespace: session.storageNamespace, accountID: session.accountID,
            paths: [ApprovedTopicReleasePublicationPath.publish, ApprovedTopicReleasePublicationPath.status])
        var permitted: Set<String> = [ApprovedTopicReleasePublicationPath.publish, ApprovedTopicReleasePublicationPath.status]
        let source = ApprovedTopicReleasePublicationClient(configuration: api, approval: approval, transport: wire,
            currentCredentials: { owner.credentials }, currentCapability: { permitted.contains($0) })
        permitted.remove(ApprovedTopicReleasePublicationPath.publish)
        XCTAssertFalse(source.canPublish(session: session)); XCTAssertTrue(source.canCheckStatus(session: session))
        do { _ = try await source.publish(record, session: session); XCTFail() } catch { XCTAssertEqual(error as? ApprovedTopicReleaseError, .notConfigured) }
        XCTAssertTrue(wire.requests.isEmpty)
        _ = try await source.status(record, session: session); XCTAssertEqual(wire.requests.count, 1)
        XCTAssertEqual(wire.requests[0].url?.path, "/api/approved-topic-release/v1/status")
    }

    @MainActor private final class WriteThenThrowStorage: ProjectEditDataStorage {
        var data: [String: Data] = [:]; var failNextWrite = true
        func read(_ key: String) throws -> Data? { data[key] }
        func write(_ value: Data, key: String) throws { data[key] = value; if failNextWrite { failNextWrite = false; throw ProjectEditError.persistenceUnavailable } }
        func remove(_ key: String) throws { XCTFail("publication never removes its records") }
    }
    func testPartialInitialWriteReturnsNoClaimAndReopensTheSameRequestWithoutAutomaticDispatch() async throws {
        let owner = Owner(), wire = Wire(), storage = WriteThenThrowStorage(), journal = ApprovedTopicReleasePublicationJournal(storage: storage), session = try XCTUnwrap(owner.session)
        let source = try client(owner, wire: wire, paths: [ApprovedTopicReleasePublicationPath.publish, ApprovedTopicReleasePublicationPath.status])
        let flow = ApprovedTopicReleasePublishFlow(session: session, topicID: 7901, source: source, journal: journal, stillCurrent: { true }); flow.reload()
        let confirmation = try XCTUnwrap(flow.review(prepared())); XCTAssertNil(flow.claim(confirmation)); XCTAssertEqual(flow.state, .unavailable); XCTAssertTrue(wire.requests.isEmpty)
        let pending = try journal.read(session: session, topicID: 7901), requestID = try XCTUnwrap(pending.current?.command.requestID)
        XCTAssertNil(pending.current?.receipt); flow.reload(); XCTAssertEqual(flow.state, .unconfirmed); XCTAssertTrue(wire.requests.isEmpty)
        await flow.retryExact(try XCTUnwrap(flow.snapshot))
        guard case .known = flow.state else { return XCTFail() }
        XCTAssertEqual(wire.requests.count, 1)
        XCTAssertEqual(try JSONDecoder().decode([String: ProjectEditJSON].self, from: XCTUnwrap(wire.requests[0].httpBody))["requestId"]?.text, requestID)
    }
    func testPartialReceiptWriteCanReadBackKnownReceiptWithoutRepeatingPublication() async throws {
        let owner = Owner(), wire = Wire(), storage = WriteThenThrowStorage(), journal = ApprovedTopicReleasePublicationJournal(storage: storage), session = try XCTUnwrap(owner.session)
        storage.failNextWrite = false
        let source = try client(owner, wire: wire, paths: [ApprovedTopicReleasePublicationPath.publish, ApprovedTopicReleasePublicationPath.status])
        let flow = ApprovedTopicReleasePublishFlow(session: session, topicID: 7901, source: source, journal: journal, stillCurrent: { true }); flow.reload()
        let claim = try XCTUnwrap(flow.claim(XCTUnwrap(flow.review(prepared())))); wire.onSend = { storage.failNextWrite = true }
        await flow.submit(claim); XCTAssertEqual(flow.state, .unconfirmed); XCTAssertEqual(wire.requests.count, 1)
        wire.onSend = nil; flow.reload(); guard case .known(let receipt) = flow.state else { return XCTFail() }
        XCTAssertEqual(receipt.releaseID, 501); XCTAssertEqual(wire.requests.count, 1)
        XCTAssertFalse(flow.canRetryExact)
    }

}

import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class ApprovedTopicReviewObservationTests: XCTestCase {
    private func session(_ epoch: UInt64 = 1) throws -> ProjectEditSession { try .init(accountID:7,epoch:epoch,storageNamespace:"review-observation") }
    private func origin(_ s: ProjectEditSession) throws -> ApprovedTopicReleaseReadTarget {
        let ack = try ProjectEditBundleAcknowledgment.decode(.object(["topicId":.number(7901),"auditTaskId":.number(3301),"reviewState":.string("PENDING"),"published":.bool(true),"bundledTemplateIds":.array([.number(41)])]),expectedTopicID:nil)
        let pending = try ProjectEditPending(operationID:UUID(),ownerKey:s.ownerKey,identity:.init(),payload:ProjectEditContract.payload(ProjectEditSyntheticFixtures.draft(),topicID:nil,scope:.full),completedTopicID:7901,serverAcknowledged:true,bundleAcknowledgment:ack)
        return try XCTUnwrap(ApprovedTopicReleaseReadTarget(pending:pending,session:s))
    }
    private func setup(observation: Bool = true) async throws -> (ApprovedTopicReviewFlow,ApprovedTopicReviewSynthetic,ProjectEditMemoryStorage,ApprovedTopicReviewJournal,ProjectEditSession) {
        let s = try session(), source = try ApprovedTopicReviewSynthetic(session:s,observationEnabled:observation,currentSession:{s}), storage = ProjectEditMemoryStorage(), journal = ApprovedTopicReviewJournal(storage:storage)
        let flow = try ApprovedTopicReviewFlow(origin:origin(s),session:s,source:source,journal:journal,stillCurrent:{true}); await flow.load()
        guard case .ready(let capture) = flow.state else { throw ApprovedTopicReleaseError.invalidResponse }
        let claim = try XCTUnwrap(flow.claim(XCTUnwrap(flow.review(capture)))); await flow.submit(claim)
        guard case .known = flow.state else { throw ApprovedTopicReleaseError.invalidResponse }; return (flow,source,storage,journal,s)
    }
    private func fields(_ record: ApprovedTopicReviewJournal.Record,status: ApprovedTopicReviewObservation.Status = .pending,changed: Bool = false) throws -> [String:ProjectEditJSON] {
        try XCTUnwrap(ApprovedTopicReviewSynthetic.observationFields(receipt:XCTUnwrap(record.receipt).fields,status:status,changedCapture:changed).object)
    }
    func testAllFiveTaskStatusesAreObservationOnlyAndPreserveOriginalSubmission() async throws {
        let (flow,_,storage,_,_) = try await setup(), before = storage.data, record = try XCTUnwrap(flow.snapshot?.current)
        for status in [ApprovedTopicReviewObservation.Status.pending,.approved,.rejected,.escalated,.cancelled] {
            let raw = try fields(record,status:status), value = try ApprovedTopicReviewObservation.decode(.object(raw),record:record)
            XCTAssertEqual(value.status,status); XCTAssertTrue(value.matchesSubmittedCapture); XCTAssertEqual(value.auditTaskID,4402)
            XCTAssertThrowsError(try ApprovedTopicReleasePreparation.decode(.object(raw),topicID:7901,auditTaskID:4402))
        }
        XCTAssertEqual(record.receipt?.submittedTaskStatus,0); XCTAssertEqual(storage.data,before)
    }
    func testWrongTaskRequestVersionsProofAndPrivateFieldsReject() async throws {
        let (flow,_,_,_,_) = try await setup(), record = try XCTUnwrap(flow.snapshot?.current), raw = try fields(record)
        let mutations:[(String,ProjectEditJSON)] = [("auditTaskId",.number(3301)),("topicId",.number(99)),("requestId",.string(UUID().uuidString)),("submittedTaskVersion",.number(1)),("observedTaskVersion",.number(-1)),("observedTaskStatus",.number(5)),("approvalProof",.bool(true)),("releaseAllocated",.bool(true)),("snapshotJson",.string("secret"))]
        for (key,value) in mutations { var changed = raw; changed[key] = value; XCTAssertThrowsError(try ApprovedTopicReviewObservation.decode(.object(changed),record:record),key) }
    }
    func testDifferentCaptureMustBeExplicitAndHashAgreementCannotBeForged() async throws {
        let (flow,_,_,_,_) = try await setup(), record = try XCTUnwrap(flow.snapshot?.current)
        var raw = try fields(record,status:.pending,changed:true)
        XCTAssertFalse(try ApprovedTopicReviewObservation.decode(.object(raw),record:record).matchesSubmittedCapture)
        raw["matchesSubmittedCapture"] = .bool(true); XCTAssertThrowsError(try ApprovedTopicReviewObservation.decode(.object(raw),record:record))
        raw = try fields(record); raw["observedSnapshotHash"] = .string("not a hash"); XCTAssertThrowsError(try ApprovedTopicReviewObservation.decode(.object(raw),record:record))
    }
    func testReadCurrentUsesOriginalSavedRequestWithoutUpdatingAnyJournalBytes() async throws {
        let (flow,source,storage,_,_) = try await setup(), saved = try XCTUnwrap(flow.snapshot), before = storage.data
        await flow.observeCurrent(saved); guard case .ready(let pending) = flow.observation else { return XCTFail() }; XCTAssertEqual(pending.status,.pending)
        source.simulateObservedStatus(.approved); await flow.observeCurrent(saved)
        guard case .ready(let approved) = flow.observation else { return XCTFail() }; XCTAssertEqual(approved.status,.approved); XCTAssertEqual(approved.observedTaskVersion,1)
        XCTAssertEqual(flow.snapshot,saved); XCTAssertEqual(storage.data,before); XCTAssertEqual(source.observationCount,2); XCTAssertEqual(source.submitCount,1); XCTAssertEqual(source.taskCount,1)
        guard case .known(let historical) = flow.state else { return XCTFail() }; XCTAssertEqual(historical.submittedTaskStatus,0)
    }
    func testAbsentObservationGrantOrUnconfirmedIntentNeverDispatchesCurrentRead() async throws {
        let (flow,source,_,_,_) = try await setup(observation:false); XCTAssertFalse(flow.canObserve)
        await flow.observeCurrent(try XCTUnwrap(flow.snapshot)); XCTAssertEqual(source.observationCount,0)
        let s = try session(), storage = ProjectEditMemoryStorage(), journal = ApprovedTopicReviewJournal(storage:storage), origin = try origin(s)
        let capture = try ApprovedTopicReviewCapture.decode(ApprovedTopicReviewSynthetic.captureFields(),topicID:7901,observedAuditTaskID:3301), snapshot = try journal.begin(capture,origin:origin,expected:journal.read(session:s,topicID:7901),session:s)
        let allowed = try ApprovedTopicReviewSynthetic(session:s,observationEnabled:true,currentSession:{s}), unknown = ApprovedTopicReviewFlow(origin:origin,session:s,source:allowed,journal:journal,stillCurrent:{true})
        await unknown.load(); XCTAssertFalse(unknown.canObserve); await unknown.observeCurrent(snapshot); XCTAssertEqual(allowed.observationCount,0)
    }
    private final class Wire: HTTPTransport {
        var reply: Data; var status = 200; var requests: [URLRequest] = []; var hold = false
        var started: XCTestExpectation?, continuation: CheckedContinuation<(Data,Int),Error>?
        init(_ reply: Data) { self.reply = reply }
        func send(_ request: URLRequest) async throws -> (Data,Int) { requests.append(request); if hold { return try await withCheckedThrowingContinuation { continuation = $0; started?.fulfill() } }; return (reply,status) }
        func finish(_ code: Int = 200) { let prior = continuation; continuation = nil; prior?.resume(returning:(reply,code)) }
    }
    private func actual(_ s: ProjectEditSession,_ wire: Wire,_ credentials: @escaping () -> ApprovedTopicReviewCredentials?) throws -> ApprovedTopicReviewClient {
        let api = try APIConfiguration(baseURL:URL(string:"https://example.com")!), approval = try OperationEndpointApproval(baseURL:api.baseURL,namespace:s.storageNamespace,accountID:s.accountID,paths:[ApprovedTopicReviewPath.current])
        return .init(configuration:api,approval:approval,transport:wire,currentCredentials:credentials)
    }
    func testOwnedHeldCurrentReadRejectsDoubleReadAndCloseBeforeLate401() async throws {
        let (original,_,storage,journal,s) = try await setup(), saved = try XCTUnwrap(original.snapshot), record = try XCTUnwrap(saved.current), before = storage.data
        let wire = Wire(try JSONEncoder().encode(["code":ProjectEditJSON.number(200),"data":.object(fields(record))])); wire.hold = true; let started = expectation(description:"actual current task read held"); wire.started = started
        let credentials = try ApprovedTopicReviewCredentials(session:s,token:"synthetic"), client = try actual(s,wire,{credentials}), flow = ApprovedTopicReviewFlow(origin:original.origin,session:s,source:client,journal:journal,stillCurrent:{true})
        await flow.load(); let first = Task { await flow.observeCurrent(saved) }; await fulfillment(of:[started],timeout:3); await flow.observeCurrent(saved); XCTAssertEqual(wire.requests.count,1)
        flow.close(); wire.reply = Data(); wire.finish(401); await first.value; XCTAssertEqual(flow.state,.closed); XCTAssertEqual(flow.observation,.notRequested); XCTAssertEqual(storage.data,before)
    }
    func testJournalReplacementDuringObservationDoesNotOverwriteNewerIntentOrExposeOldResult() async throws {
        let (original,_,storage,journal,s) = try await setup(), saved = try XCTUnwrap(original.snapshot), record = try XCTUnwrap(saved.current)
        let wire = Wire(try JSONEncoder().encode(["code":ProjectEditJSON.number(200),"data":.object(fields(record))])); wire.hold = true; let started = expectation(description:"current read before replacement"); wire.started = started
        let credentials = try ApprovedTopicReviewCredentials(session:s,token:"synthetic"), client = try actual(s,wire,{credentials}), flow = ApprovedTopicReviewFlow(origin:original.origin,session:s,source:client,journal:journal,stillCurrent:{true})
        await flow.load(); let task = Task { await flow.observeCurrent(saved) }; await fulfillment(of:[started],timeout:3)
        _ = try journal.begin(record.capture,origin:origin(s),expected:saved,session:s); let changed = storage.data
        wire.finish(); await task.value; XCTAssertEqual(flow.observation,.failed); XCTAssertEqual(storage.data,changed); XCTAssertNil(try journal.read(session:s,topicID:7901).current?.receipt)
    }
    func testCurrentEmpty401IsUnauthorizedButOlderSessionResponseCannotChangeCurrentOwner() async throws {
        let (original,_,storage,journal,s) = try await setup(), saved = try XCTUnwrap(original.snapshot), before = storage.data
        var credentials: ApprovedTopicReviewCredentials? = try .init(session:s,token:"synthetic")
        let wire = Wire(Data()); wire.status = 401; let client = try actual(s,wire,{credentials}), flow = ApprovedTopicReviewFlow(origin:original.origin,session:s,source:client,journal:journal,stillCurrent:{true})
        await flow.load(); await flow.observeCurrent(saved); XCTAssertEqual(flow.observation,.unauthorized); XCTAssertEqual(storage.data,before)
        wire.hold = true; let started = expectation(description:"old current read"); wire.started = started
        let task = Task { await flow.observeCurrent(saved) }; await fulfillment(of:[started],timeout:3)
        let fresh = try ApprovedTopicReviewCredentials(session:session(2),token:"new-synthetic"); credentials = fresh; wire.finish(401); await task.value
        XCTAssertEqual(flow.state,.closed); XCTAssertEqual(credentials,fresh); XCTAssertEqual(storage.data,before)
    }
}

import XCTest
import Combine
@testable import Questify

@MainActor final class ApprovedTopicReviewObservationPresentationTests: XCTestCase {
    private func setup() async throws -> (ApprovedTopicReviewReadModel,ApprovedTopicReviewSynthetic,ApprovedTopicReviewJournal,ProjectEditMemoryStorage,ProjectEditSession) {
        let s = try ProjectEditSession(accountID:7,epoch:1,storageNamespace:"observation-view-model"), storage = ProjectEditMemoryStorage(), journal = ApprovedTopicReviewJournal(storage:storage)
        let source = try ApprovedTopicReviewSynthetic(session:s,observationEnabled:true,currentSession:{s})
        let ack = try ProjectEditBundleAcknowledgment.decode(.object(["topicId":.number(7901),"auditTaskId":.number(3301),"reviewState":.string("PENDING"),"published":.bool(true),"bundledTemplateIds":.array([.number(41)])]),expectedTopicID:nil)
        let pending = try ProjectEditPending(operationID:UUID(),ownerKey:s.ownerKey,identity:.init(),payload:ProjectEditContract.payload(ProjectEditSyntheticFixtures.draft(),topicID:nil,scope:.full),completedTopicID:7901,serverAcknowledged:true,bundleAcknowledgment:ack)
        let origin = try XCTUnwrap(ApprovedTopicReleaseReadTarget(pending:pending,session:s)), flow = ApprovedTopicReviewFlow(origin:origin,session:s,source:source,journal:journal,stillCurrent:{true})
        await flow.load(); guard case .ready(let captured) = flow.state else { throw ApprovedTopicReleaseError.invalidResponse }
        await flow.submit(try XCTUnwrap(flow.claim(XCTUnwrap(flow.review(captured)))))
        return (ApprovedTopicReviewReadModel(flow:flow),source,journal,storage,s)
    }
    func testActualViewReadMethodRejectsDoubleTapAndPreservesHistoricalReceipt() async throws {
        let (model,source,_,storage,_) = try await setup(), saved = try XCTUnwrap(model.flow.snapshot), before = storage.data
        let done = expectation(description:"view observation finished"), subscription = model.$isWorking.dropFirst().filter { !$0 }.sink { _ in done.fulfill() }
        model.observe(saved); model.observe(saved); await fulfillment(of:[done],timeout:3); withExtendedLifetime(subscription) {}
        XCTAssertEqual(source.observationCount,1); XCTAssertEqual(storage.data,before)
        guard case .ready(let observed) = model.flow.observation, case .known(let submitted) = model.flow.state else { return XCTFail() }
        XCTAssertEqual(observed.status,.pending); XCTAssertEqual(submitted.submittedTaskStatus,0); XCTAssertEqual(observed.requestID,submitted.requestID)
    }
    func testActualViewQueuedReadCannotSendAfterOriginalPresentationCloses() async throws {
        let (model,source,_,storage,_) = try await setup(), saved = try XCTUnwrap(model.flow.snapshot), before = storage.data
        let done = expectation(description:"queued closed observation ended"), subscription = model.$isWorking.dropFirst().filter { !$0 }.sink { _ in done.fulfill() }
        model.observe(saved); model.flow.close(); await fulfillment(of:[done],timeout:3); withExtendedLifetime(subscription) {}
        XCTAssertEqual(source.observationCount,0); XCTAssertEqual(storage.data,before); XCTAssertEqual(model.flow.state,.closed)
    }
    func testRetainedViewSnapshotCannotReadAReplacementJournalRequest() async throws {
        let (model,source,journal,storage,s) = try await setup(), saved = try XCTUnwrap(model.flow.snapshot), record = try XCTUnwrap(saved.current)
        let capture = record.capture
        let ack = try ProjectEditBundleAcknowledgment.decode(.object(["topicId":.number(7901),"auditTaskId":.number(3301),"reviewState":.string("PENDING"),"published":.bool(true),"bundledTemplateIds":.array([.number(41)])]),expectedTopicID:nil)
        let pending = try ProjectEditPending(operationID:UUID(),ownerKey:s.ownerKey,identity:.init(),payload:ProjectEditContract.payload(ProjectEditSyntheticFixtures.draft(),topicID:nil,scope:.full),completedTopicID:7901,serverAcknowledged:true,bundleAcknowledgment:ack)
        _ = try journal.begin(capture,origin:XCTUnwrap(ApprovedTopicReleaseReadTarget(pending:pending,session:s)),expected:saved,session:s); let before = storage.data
        let done = expectation(description:"stale view read refused"), subscription = model.$isWorking.dropFirst().filter { !$0 }.sink { _ in done.fulfill() }
        model.observe(saved); await fulfillment(of:[done],timeout:3); withExtendedLifetime(subscription) {}
        XCTAssertEqual(source.observationCount,0); XCTAssertEqual(storage.data,before); XCTAssertEqual(model.flow.observation,.failed)
    }
}

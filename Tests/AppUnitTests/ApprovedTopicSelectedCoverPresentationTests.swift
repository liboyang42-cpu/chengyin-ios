import XCTest
@testable import Questify

@MainActor final class ApprovedTopicSelectedCoverPresentationTests: XCTestCase {
    private final class Owner { var session: ProjectEditSession? = try? .init(accountID: 7, epoch: 1, storageNamespace: "selected-cover-review-tests") }
    func testOrdinaryEditorViewModelKeepsAuthorCoverReadableButCannotClaimOrPersistReview() async throws {
        let owner = Owner(), storage = ProjectEditMemoryStorage(), session = try XCTUnwrap(owner.session)
        let source = try ApprovedTopicReviewSynthetic(session: session, selectedCoverEnabled: true, currentSession: { owner.session })
        let coordinator = ProjectEditCoordinator(initial: .init(draft: ProjectEditSyntheticFixtures.draft()), service: ProjectEditSyntheticService(scenario: .bundlePending), store: .init(storage: storage), releaseReviewSource: source, releaseReviewJournal: .init(storage: storage), currentSession: { owner.session })
        let editor = ProjectEditModel(coordinator: coordinator); await editor.load(); editor.review(); await editor.submit(try XCTUnwrap(editor.confirmation))
        let controller = ApprovedTopicReviewPresentation(model: editor); controller.open(try XCTUnwrap(controller.capture()))
        let presentation = try XCTUnwrap(controller.presentation), model = ApprovedTopicReviewReadModel(flow: presentation.flow); await model.load()
        guard case .ready(let capture) = model.flow.state else { return XCTFail("Missing server capture") }
        XCTAssertEqual(capture.selectedCover?.ownerMemberID,7); XCTAssertEqual(capture.selectedCover?.selectionVersion,9)
        let before = storage.data; XCTAssertFalse(model.flow.canConfirm(capture)); model.review(capture); XCTAssertNil(model.confirmation); XCTAssertNil(model.flow.confirmation)
        let journal = ApprovedTopicReviewJournal(storage: storage), saved = try journal.read(session: session,topicID: capture.topicID)
        XCTAssertFalse(journal.canBegin(capture,origin: model.flow.origin,expected:saved)); XCTAssertThrowsError(try journal.begin(capture,origin:model.flow.origin,expected:saved,session:session)); XCTAssertEqual(storage.data,before)
        controller.close(presentation); model.review(capture); XCTAssertEqual(model.flow.state,.closed); XCTAssertNil(model.confirmation); XCTAssertEqual(source.submitCount,0); XCTAssertEqual(source.taskCount,0); XCTAssertEqual(storage.data,before)
    }
    func testDirectActualClientSubmitCannotSendAnAuthorOnlyCapture() async throws {
        let session = try ProjectEditSession(accountID:7,epoch:1,storageNamespace:"selected-cover-client"), source = try ApprovedTopicReviewSynthetic(session:session,selectedCoverEnabled:true,currentSession:{session})
        let ack = try ProjectEditBundleAcknowledgment.decode(.object(["topicId":.number(7901),"auditTaskId":.number(3301),"reviewState":.string("PENDING"),"published":.bool(true),"bundledTemplateIds":.array([.number(41)])]),expectedTopicID:nil)
        let pending = try ProjectEditPending(operationID:UUID(),ownerKey:session.ownerKey,identity:.init(),payload:ProjectEditContract.payload(ProjectEditSyntheticFixtures.draft(),topicID:nil,scope:.full),completedTopicID:7901,serverAcknowledged:true,bundleAcknowledgment:ack)
        let origin = try XCTUnwrap(ApprovedTopicReleaseReadTarget(pending:pending,session:session)), capture = try await source.prepare(origin,session:session)
        let record = ApprovedTopicReviewJournal.Record(ownerKey:session.ownerKey,originOperationID:origin.operationID,command:.init(capture:capture),capture:capture,receipt:nil)
        do { _ = try await source.submit(record,session:session); XCTFail("Unexpected send") } catch { XCTAssertEqual(error as? ApprovedTopicReleaseError,.notConfigured) }
        XCTAssertEqual(source.submitCount,0); XCTAssertEqual(source.taskCount,0)
    }
}

import XCTest
@testable import Questify

@MainActor final class ApprovedTopicReviewPresentationTests: XCTestCase {
    private final class Owner { var session: ProjectEditSession? = try? .init(accountID: 7, epoch: 1, storageNamespace: "review-presentation-tests") }
    private func setup() async throws -> (ProjectEditModel, ApprovedTopicReviewPresentation, ApprovedTopicReviewReadModel, Owner, ProjectEditMemoryStorage, ApprovedTopicReviewSynthetic) {
        let owner = Owner(), storage = ProjectEditMemoryStorage(), session = try XCTUnwrap(owner.session)
        let source = try ApprovedTopicReviewSynthetic(session: session, currentSession: { owner.session })
        let reader = try ApprovedTopicReleaseSyntheticSource(session: session, currentSession: { owner.session })
        let coordinator = ProjectEditCoordinator(initial: .init(draft: ProjectEditSyntheticFixtures.draft()), service: ProjectEditSyntheticService(scenario: .bundlePending), store: ProjectEditLocalStore(storage: storage), releasePreparationSource: reader, releaseReviewSource: source, releaseReviewJournal: .init(storage: storage), currentSession: { owner.session })
        let editor = ProjectEditModel(coordinator: coordinator); await editor.load(); editor.review(); await editor.submit(try XCTUnwrap(editor.confirmation))
        let controller = ApprovedTopicReviewPresentation(model: editor); controller.open(try XCTUnwrap(controller.capture()))
        let model = ApprovedTopicReviewReadModel(flow: try XCTUnwrap(controller.presentation).flow); await model.load()
        return (editor, controller, model, owner, storage, source)
    }
    private func capture(_ model: ApprovedTopicReviewReadModel) throws -> ApprovedTopicReviewCapture {
        guard case .ready(let value) = model.flow.state else { throw ApprovedTopicReleaseError.invalidResponse }; return value
    }
    func testActualViewModelDoubleReviewKeepsFirstConfirmationAndOriginalDraftEvidence() async throws {
        let (editor, _, model, _, storage, source) = try await setup(), before = storage.data, draft = editor.draft
        let captured = try capture(model); model.review(captured); let first = try XCTUnwrap(model.confirmation); model.review(captured)
        XCTAssertEqual(model.confirmation?.id, first.id); XCTAssertEqual(model.flow.confirmation?.id, first.id)
        XCTAssertEqual(first.capture.name, "Test-only current review capture"); XCTAssertEqual(first.capture.chapters[0].blocks[1].node?.templateID, 73)
        XCTAssertEqual(editor.draft, draft); XCTAssertEqual(editor.coordinator.pending?.bundleAcknowledgment?.bundledTemplateIDs, [41]); XCTAssertEqual(storage.data, before); XCTAssertEqual(source.submitCount, 0)
    }
    func testOldCancelAndBindingCannotDismissAnotherConfirmation() async throws {
        let (_, _, model, _, storage, source) = try await setup(), before = storage.data, captured = try capture(model)
        model.review(captured); let first = try XCTUnwrap(model.confirmation), binding = model.binding(model.confirmation); model.cancel(first)
        model.review(captured); let second = try XCTUnwrap(model.confirmation); binding.wrappedValue = nil; model.cancel(first); model.confirm(first)
        XCTAssertEqual(model.confirmation?.id, second.id); XCTAssertEqual(model.flow.confirmation?.id, second.id); XCTAssertEqual(storage.data, before); XCTAssertEqual(source.submitCount, 0)
    }
    func testOriginalDismissalAfterDurableClaimCannotClearIntentBeforeQueuedTask() async throws {
        let (_, controller, model, owner, storage, source) = try await setup(), session = try XCTUnwrap(owner.session)
        model.review(try capture(model)); let confirmation = try XCTUnwrap(model.confirmation), binding = model.binding(model.confirmation)
        model.confirm(confirmation); let journal = ApprovedTopicReviewJournal(storage: storage), saved = try journal.read(session: session, topicID: 7901)
        XCTAssertNotNil(saved.current); XCTAssertNil(model.confirmation); binding.wrappedValue = nil; model.cancel(confirmation)
        controller.close(try XCTUnwrap(controller.presentation)); await Task.yield(); await Task.yield()
        XCTAssertEqual(source.submitCount, 0); XCTAssertEqual(try journal.read(session: session, topicID: 7901), saved); XCTAssertEqual(model.flow.state, .closed)
    }
    func testLeaveRejectsOriginalConfirmBeforeViewRedraw() async throws {
        let (editor, _, model, _, storage, source) = try await setup(), before = storage.data
        model.review(try capture(model)); let original = try XCTUnwrap(model.confirmation); editor.leave(); model.confirm(original); await Task.yield()
        XCTAssertNil(model.confirmation); XCTAssertEqual(storage.data, before); XCTAssertEqual(source.submitCount, 0)
    }
    func testAccountChangeAloneRejectsAHealthyOriginalConfirmationBeforeViewRedraw() async throws {
        let (editor, _, model, owner, storage, source) = try await setup(), before = storage.data
        model.review(try capture(model)); let original = try XCTUnwrap(model.confirmation); XCTAssertTrue(model.owns(original)); XCTAssertTrue(editor.ownsVisit)
        owner.session = try .init(accountID: 8, epoch: 2, storageNamespace: "review-presentation-tests"); model.confirm(original); await Task.yield()
        XCTAssertNil(model.confirmation); XCTAssertEqual(storage.data, before); XCTAssertEqual(source.submitCount, 0); XCTAssertEqual(owner.session?.accountID, 8)
    }
    func testRetainedOldParentCloseCannotCloseReplacementReviewSession() async throws {
        let (_, controller, model, _, _, source) = try await setup(), first = try XCTUnwrap(controller.presentation), binding = controller.binding(controller.presentation)
        controller.close(first); controller.open(try XCTUnwrap(controller.capture())); let second = try XCTUnwrap(controller.presentation)
        binding.wrappedValue = nil; controller.close(first); model.flow.close()
        XCTAssertEqual(controller.presentation?.id, second.id); XCTAssertTrue(second.flow.isCurrent); XCTAssertEqual(first.flow.state, .closed); XCTAssertEqual(source.submitCount, 0)
    }
    func testChangedReviewJournalPermanentlyInvalidatesOldApprovedPanelEvenForSameTaskID() async throws {
        let (editor, _, reviewModel, owner, storage, _) = try await setup(), session = try XCTUnwrap(owner.session)
        let reader = ApprovedReleaseAuthorPresentation(model: editor); reader.open(try XCTUnwrap(reader.capture())); let old = try XCTUnwrap(reader.presentation)
        let journal = ApprovedTopicReviewJournal(storage: storage), origin = try XCTUnwrap(ApprovedTopicReleaseReadTarget(pending: XCTUnwrap(editor.coordinator.pending), session: session))
        let saved = try journal.begin(capture(reviewModel), origin: origin, expected: journal.read(session: session, topicID: 7901), session: session)
        XCTAssertFalse(reader.isPresented(old)); XCTAssertNil(editor.approvedReleaseReadTarget)
        let record = try XCTUnwrap(saved.current); var fields = try XCTUnwrap(ApprovedTopicReviewSynthetic.receiptFields(command: record.command.fields, taskID: 3301).object)
        fields["submittedTaskVersion"] = .number(1)
        let receipt = try ApprovedTopicReviewReceipt.decode(.object(fields), command: record.command)
        _ = try journal.record(receipt, expected: saved, session: session)
        XCTAssertEqual(editor.approvedReleaseReadTarget?.auditTaskID, 3301); XCTAssertFalse(reader.isPresented(old)); XCTAssertFalse(old.flow.isCurrent)
        XCTAssertEqual(editor.coordinator.pending?.bundleAcknowledgment?.auditTaskID, 3301)
    }
}

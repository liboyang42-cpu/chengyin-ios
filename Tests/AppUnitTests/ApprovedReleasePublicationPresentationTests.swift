import XCTest
@testable import Questify

@MainActor final class ApprovedReleasePublicationPresentationTests: XCTestCase {
    private final class Owner { var session: ProjectEditSession? = try? .init(accountID: 7, epoch: 1, storageNamespace: "release-publication-presentation") }
    private func setup() async throws -> (ProjectEditModel, ApprovedReleaseAuthorPresentation, ApprovedReleaseReadModel, Owner, ProjectEditMemoryStorage, ApprovedTopicReleasePublicationSynthetic) {
        let owner = Owner(), storage = ProjectEditMemoryStorage(), session = try XCTUnwrap(owner.session)
        let reader = try ApprovedTopicReleaseSyntheticSource(session: session, currentSession: { owner.session })
        let publisher = try ApprovedTopicReleasePublicationSynthetic(session: session, currentSession: { owner.session })
        let coordinator = ProjectEditCoordinator(initial: .init(draft: ProjectEditSyntheticFixtures.draft()), service: ProjectEditSyntheticService(scenario: .bundlePending),
            store: ProjectEditLocalStore(storage: storage), releasePreparationSource: reader, releasePublicationSource: publisher,
            releasePublicationJournal: ApprovedTopicReleasePublicationJournal(storage: storage), currentSession: { owner.session })
        let model = ProjectEditModel(coordinator: coordinator); await model.load(); model.review(); await model.submit(try XCTUnwrap(model.confirmation))
        let controller = ApprovedReleaseAuthorPresentation(model: model); controller.open(try XCTUnwrap(controller.capture()))
        let readModel = ApprovedReleaseReadModel(original: try XCTUnwrap(controller.presentation)); await readModel.load()
        return (model, controller, readModel, owner, storage, publisher)
    }
    private func prepared(_ model: ApprovedReleaseReadModel) throws -> ApprovedTopicReleasePreparation {
        guard case .ready(let value) = model.flow.state else { throw ApprovedTopicReleaseError.invalidResponse }; return value
    }
    func testActualViewModelOldConfirmationDismissalCannotCancelNewConfirmation() async throws {
        let (_, controller, model, _, storage, publisher) = try await setup(), value = try prepared(model), before = storage.data
        model.review(value); let old = try XCTUnwrap(model.confirmation), oldBinding = model.confirmationBinding(model.confirmation)
        model.cancel(old); model.review(value); let current = try XCTUnwrap(model.confirmation)
        oldBinding.wrappedValue = nil; model.cancel(old)
        XCTAssertEqual(model.confirmation?.id, current.id); XCTAssertEqual(model.publisher?.confirmation?.id, current.id)
        XCTAssertEqual(storage.data, before); XCTAssertEqual(publisher.publishCount, 0); XCTAssertNotNil(controller.presentation)
    }
    func testClaimThenOriginalSheetDisappearanceBeforeQueuedTaskCannotClearPersistedIntent() async throws {
        let (_, controller, model, owner, storage, publisher) = try await setup(), session = try XCTUnwrap(owner.session)
        model.review(try prepared(model)); let confirmation = try XCTUnwrap(model.confirmation), oldBinding = model.confirmationBinding(model.confirmation)
        model.confirm(confirmation)
        let journal = ApprovedTopicReleasePublicationJournal(storage: storage), pending = try journal.read(session: session, topicID: 7901)
        XCTAssertNotNil(pending.current); XCTAssertNil(model.confirmation)
        oldBinding.wrappedValue = nil; model.cancel(confirmation)
        controller.close(try XCTUnwrap(controller.presentation))
        await Task.yield(); await Task.yield()
        XCTAssertEqual(publisher.publishCount, 0); XCTAssertEqual(try journal.read(session: session, topicID: 7901), pending)
        XCTAssertEqual(model.publisher?.state, .closed)
    }
    func testOldConfirmAfterParentLeaveCannotWriteBeforeAnyViewRedraw() async throws {
        let (editor, controller, model, _, storage, publisher) = try await setup(), before = storage.data
        model.review(try prepared(model)); let old = try XCTUnwrap(model.confirmation)
        editor.leave(); model.confirm(old); await Task.yield()
        XCTAssertEqual(publisher.publishCount, 0); XCTAssertEqual(storage.data, before)
        XCTAssertNil(model.confirmation); XCTAssertNotNil(controller.presentation)
    }
    func testOldConfirmAfterAccountChangeCannotWriteAnotherOwnersJournal() async throws {
        let (_, controller, model, owner, storage, publisher) = try await setup(), before = storage.data
        model.review(try prepared(model)); let old = try XCTUnwrap(model.confirmation)
        owner.session = try .init(accountID: 8, epoch: 2, storageNamespace: "release-publication-presentation")
        model.confirm(old); await Task.yield()
        XCTAssertEqual(publisher.publishCount, 0); XCTAssertEqual(storage.data, before); XCTAssertNotNil(controller.presentation)
    }
    func testRetainedOldPublisherCloseDoesNotRetireNewParentPresentation() async throws {
        let (_, controller, oldModel, _, _, publisher) = try await setup(), first = try XCTUnwrap(controller.presentation)
        controller.close(first); controller.open(try XCTUnwrap(controller.capture()))
        let second = try XCTUnwrap(controller.presentation), newModel = ApprovedReleaseReadModel(original: second); await newModel.load()
        oldModel.close(); controller.close(first)
        XCTAssertEqual(controller.presentation?.id, second.id); XCTAssertTrue(second.publisher?.isCurrent == true)
        XCTAssertEqual(publisher.publishCount, 0)
    }
    func testConfirmationShowsCapturedServerValuesInsteadOfHistoricalSubmissionOrEditableDraft() async throws {
        let (editor, controller, model, _, _, publisher) = try await setup()
        model.review(try prepared(model)); let confirmation = try XCTUnwrap(model.confirmation)
        XCTAssertEqual(confirmation.prepared.name, "Synthetic server-approved title")
        XCTAssertNotEqual(confirmation.prepared.name, editor.draft.name)
        XCTAssertEqual(confirmation.prepared.chapters[0].blocks[1].node?.templateID, 73)
        XCTAssertEqual(editor.coordinator.pending?.bundleAcknowledgment?.bundledTemplateIDs, [41])
        XCTAssertEqual(confirmation.prepared.headRevision, 0); XCTAssertEqual(publisher.publishCount, 0); XCTAssertNotNil(controller.presentation)
    }
}

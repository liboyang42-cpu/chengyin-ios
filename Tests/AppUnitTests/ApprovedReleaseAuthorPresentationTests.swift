import XCTest
@testable import Questify

@MainActor final class ApprovedReleaseAuthorPresentationTests: XCTestCase {
    private final class Owner { var session: ProjectEditSession? = try? .init(accountID: 7, epoch: 1, storageNamespace: "release-presentation-test") }
    private func setup() async throws -> (ProjectEditModel, ApprovedReleaseAuthorPresentation, Owner, ProjectEditMemoryStorage, ApprovedTopicReleaseSyntheticSource) {
        let owner = Owner(), storage = ProjectEditMemoryStorage(), draft = ProjectEditSyntheticFixtures.draft()
        let source = try ApprovedTopicReleaseSyntheticSource(session: XCTUnwrap(owner.session), currentSession: { owner.session })
        let co = ProjectEditCoordinator(initial: .init(draft: draft), service: ProjectEditSyntheticService(scenario: .bundlePending),
            store: ProjectEditLocalStore(storage: storage), releasePreparationSource: source, currentSession: { owner.session })
        let model = ProjectEditModel(coordinator: co); await model.load(); model.review(); await model.submit(try XCTUnwrap(model.confirmation))
        XCTAssertTrue(model.approvedReleaseReadIsConfigured)
        return (model, ApprovedReleaseAuthorPresentation(model: model), owner, storage, source)
    }
    func testOrdinaryModelCurrentReadDisplaysServerSnapshotWithoutChangingOriginalDraftOrCompletion() async throws {
        let (model, controller, _, storage, source) = try await setup(), before = storage.data, draft = model.draft
        controller.open(try XCTUnwrap(controller.capture())); let original = try XCTUnwrap(controller.presentation)
        await original.flow.load()
        guard case .ready(let value) = original.flow.state else { return XCTFail() }
        XCTAssertEqual(value.name, "Synthetic server-approved title"); XCTAssertNotEqual(value.name, model.draft.name)
        XCTAssertEqual(value.chapters[0].blocks[1].node?.templateID, 73); XCTAssertEqual(model.coordinator.pending?.bundleAcknowledgment?.bundledTemplateIDs, [41])
        XCTAssertEqual(model.draft, draft); XCTAssertEqual(storage.data, before); XCTAssertEqual(source.requestCount, 1)
    }
    func testRetainedOldCloseAndBindingCannotDismissNewPresentation() async throws {
        let (_, controller, _, _, source) = try await setup(); let opening = try XCTUnwrap(controller.capture())
        controller.open(opening); let first = try XCTUnwrap(controller.presentation), oldBinding = controller.binding(controller.presentation)
        controller.close(first); controller.open(try XCTUnwrap(controller.capture())); let second = try XCTUnwrap(controller.presentation)
        XCTAssertNotEqual(first.id, second.id); oldBinding.wrappedValue = nil; controller.close(first)
        XCTAssertEqual(controller.presentation?.id, second.id); XCTAssertEqual(first.flow.state, .closed)
        await first.flow.load(); XCTAssertEqual(source.requestCount, 0); await second.flow.load(); XCTAssertEqual(source.requestCount, 1)
    }
    func testCapturedOpeningCannotReacquireDifferentCompletionAfterLeaveOrAccountChange() async throws {
        let (model, controller, owner, storage, source) = try await setup(); let opening = try XCTUnwrap(controller.capture()), before = storage.data
        model.leave(); controller.open(opening); XCTAssertNil(controller.presentation)
        await model.load(); controller.open(opening); XCTAssertNil(controller.presentation)
        owner.session = try .init(accountID: 8, epoch: 2, storageNamespace: "release-presentation-test")
        XCTAssertNil(controller.capture()); XCTAssertFalse(model.approvedReleaseReadIsConfigured); XCTAssertEqual(source.requestCount, 0); XCTAssertEqual(storage.data, before)
    }
    func testUnknownCompletionAndDefaultCompositionNeverOfferAnApprovedReadTarget() async throws {
        let owner = Owner(), draft = ProjectEditSyntheticFixtures.draft(), storage = ProjectEditMemoryStorage()
        let co = ProjectEditCoordinator(initial: .init(draft: draft), service: ProjectEditSyntheticService(scenario: .unknown), store: ProjectEditLocalStore(storage: storage), currentSession: { owner.session })
        let model = ProjectEditModel(coordinator: co); await model.load(); model.review(); await model.submit(try XCTUnwrap(model.confirmation))
        XCTAssertTrue(co.isLocked); XCTAssertNil(ApprovedReleaseAuthorPresentation(model: model).capture()); XCTAssertFalse(model.approvedReleaseReadIsConfigured)
    }
}

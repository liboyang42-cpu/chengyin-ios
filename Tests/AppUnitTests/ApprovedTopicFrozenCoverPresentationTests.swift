import XCTest
@testable import Questify

@MainActor final class ApprovedTopicFrozenCoverPresentationTests: XCTestCase {
    private final class Owner { var session: ProjectEditSession? = try? .init(accountID: 7, epoch: 1, storageNamespace: "frozen-cover-host") }
    func testOrdinaryEditorCapturesBoundCoverAndOldCancelCannotClearNewConfirmation() async throws {
        let owner = Owner(), storage = ProjectEditMemoryStorage(), session = try XCTUnwrap(owner.session)
        let source = try ApprovedTopicReviewSynthetic(session: session, selectedCoverEnabled: true, selectedCoverReleaseBound: true, currentSession: { owner.session })
        let coordinator = ProjectEditCoordinator(initial: .init(draft: ProjectEditSyntheticFixtures.draft()), service: ProjectEditSyntheticService(scenario: .bundlePending), store: .init(storage: storage), releaseReviewSource: source, releaseReviewJournal: .init(storage: storage), currentSession: { owner.session })
        let editor = ProjectEditModel(coordinator: coordinator); await editor.load(); editor.review(); await editor.submit(try XCTUnwrap(editor.confirmation))
        let controller = ApprovedTopicReviewPresentation(model: editor); controller.open(try XCTUnwrap(controller.capture()))
        let original = try XCTUnwrap(controller.presentation), model = ApprovedTopicReviewReadModel(flow: original.flow); await model.load()
        guard case .ready(let capture) = model.flow.state else { return XCTFail() }
        XCTAssertTrue(capture.coverBindingAllowsReview); model.review(capture); let old = try XCTUnwrap(model.confirmation)
        model.cancel(old); model.review(capture); let current = try XCTUnwrap(model.confirmation)
        XCTAssertNotEqual(old.id, current.id); model.cancel(old); model.confirm(old)
        XCTAssertEqual(model.confirmation?.id, current.id); XCTAssertEqual(model.confirmation?.capture.selectedCover, capture.selectedCover)
        XCTAssertEqual(source.submitCount, 0)
        // The actual View method persists synchronously before scheduling transport.
        model.confirm(current); XCTAssertEqual(try ApprovedTopicReviewJournal(storage: storage).read(session: session, topicID: 7901).current?.capture, capture)
        controller.close(original)
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(source.submitCount, 0); XCTAssertEqual(original.flow.state, .closed)
        XCTAssertNotNil(try ApprovedTopicReviewJournal(storage: storage).read(session: session, topicID: 7901).current)
    }
    func testAccountChangeBetweenReviewAndConfirmKeepsBoundAssetOutOfNewOwnerJournal() async throws {
        let owner = Owner(), storage = ProjectEditMemoryStorage(), session = try XCTUnwrap(owner.session)
        let source = try ApprovedTopicReviewSynthetic(session: session, selectedCoverEnabled: true, selectedCoverReleaseBound: true, currentSession: { owner.session })
        let coordinator = ProjectEditCoordinator(initial: .init(draft: ProjectEditSyntheticFixtures.draft()), service: ProjectEditSyntheticService(scenario: .bundlePending), store: .init(storage: storage), releaseReviewSource: source, releaseReviewJournal: .init(storage: storage), currentSession: { owner.session })
        let editor = ProjectEditModel(coordinator: coordinator); await editor.load(); editor.review(); await editor.submit(try XCTUnwrap(editor.confirmation))
        let controller = ApprovedTopicReviewPresentation(model: editor); controller.open(try XCTUnwrap(controller.capture()))
        let model = ApprovedTopicReviewReadModel(flow: try XCTUnwrap(controller.presentation).flow); await model.load()
        guard case .ready(let capture) = model.flow.state else { return XCTFail() }
        model.review(capture); let confirmation = try XCTUnwrap(model.confirmation), saved = storage.data
        owner.session = try .init(accountID: 8, epoch: 2, storageNamespace: session.storageNamespace)
        model.confirm(confirmation); for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(source.submitCount, 0); XCTAssertEqual(storage.data, saved); XCTAssertNil(model.confirmation)
    }
}

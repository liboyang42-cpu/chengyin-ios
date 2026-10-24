import XCTest
@testable import Questify

@MainActor final class ProjectSubmissionEvidenceTests: XCTestCase {
    private final class Owner { var session: ProjectEditSession? = try? .init(accountID: 7, epoch: 1, storageNamespace: "submission-model-test") }
    private func setup() async throws -> (ProjectEditModel, ProjectEditCoordinator, Owner, ProjectEditMemoryStorage) {
        let owner = Owner(), storage = ProjectEditMemoryStorage(), draft = ProjectEditSyntheticFixtures.draft()
        let co = ProjectEditCoordinator(initial: .init(draft: draft), service: ProjectEditSyntheticService(scenario: .bundlePending),
            store: ProjectEditLocalStore(storage: storage), currentSession: { owner.session })
        let model = ProjectEditModel(coordinator: co); await model.load(); model.review()
        let captured = try XCTUnwrap(model.confirmation); await model.submit(captured)
        XCTAssertEqual(co.state, .acknowledged); return (model, co, owner, storage)
    }
    func testActualModelSubmissionExposesTaskAndNewOwnerCannotReadOldEvidenceBeforeRedraw() async throws {
        let (model, _, owner, storage) = try await setup(); let before = storage.data
        let original = try XCTUnwrap(model.submittedHandoff); let incarnation = model.editorIncarnation; XCTAssertTrue(model.submissionIsCurrent(original, incarnation: incarnation))
        XCTAssertEqual(model.submissionEvidence?.bundleAcknowledgment?.auditTaskID, 3301)
        XCTAssertEqual(model.submissionEvidence?.bundleAcknowledgment?.reviewState, "PENDING")
        XCTAssertEqual(model.submissionEvidence?.bundleAcknowledgment?.published, true)
        owner.session = try .init(accountID: 8, epoch: 2, storageNamespace: "submission-model-test")
        XCTAssertNil(model.submissionEvidence); XCTAssertFalse(model.submissionIsCurrent(original, incarnation: incarnation)); XCTAssertEqual(storage.data, before)
    }
    func testReplacementEditorVisitRetiresOldEvidenceWithoutClearingCompletion() async throws {
        let (model, co, _, storage) = try await setup(); let before = storage.data
        let original = try XCTUnwrap(model.submittedHandoff); let incarnation = model.editorIncarnation
        let replacement = ProjectEditModel(coordinator: co); XCTAssertFalse(replacement.submissionIsCurrent(original, incarnation: incarnation)); await replacement.load()
        XCTAssertNil(model.submissionEvidence); XCTAssertFalse(model.submissionIsCurrent(original, incarnation: incarnation)); XCTAssertFalse(replacement.submissionIsCurrent(original, incarnation: incarnation)); XCTAssertNotNil(replacement.submissionEvidence)
        model.leave(); XCTAssertNotNil(replacement.submissionEvidence); XCTAssertEqual(storage.data, before)
    }
    func testEvidenceTitleAndCountComeFromCapturedRequestNotMutableModel() async throws {
        let (model, _, _, _) = try await setup(); let evidence = try XCTUnwrap(model.submissionEvidence)
        model.draft.name = "Changed local projection"; model.draft.chapters = []
        XCTAssertEqual(model.submissionEvidence?.title, evidence.title); XCTAssertEqual(model.submissionEvidence?.chapterCount, evidence.chapterCount)
        XCTAssertEqual(model.submissionEvidence?.bundleAcknowledgment, evidence.bundleAcknowledgment)
    }
    func testRetainedDoneAndDismissalCaptureCannotReacquireNewIncarnationAfterLeave() async throws {
        let (model, _, _, storage) = try await setup()
        let original = try XCTUnwrap(model.submittedHandoff), incarnation = model.editorIncarnation, before = storage.data
        XCTAssertTrue(model.submissionIsCurrent(original, incarnation: incarnation))
        model.leave(); XCTAssertNotEqual(model.editorIncarnation, incarnation)
        XCTAssertFalse(model.submissionIsCurrent(original, incarnation: incarnation))
        await model.load(); XCTAssertFalse(model.submissionIsCurrent(original, incarnation: incarnation))
        XCTAssertEqual(storage.data, before)
    }

    func testResultLifecycleBackgroundResumeAndCloseReopenRejectRetainedCaptures() throws {
        let lifecycle = ProjectSubmissionResultLifecycle(); var completions = 0
        XCTAssertNil(lifecycle.capture)
        lifecycle.appear(active: true); let first = try XCTUnwrap(lifecycle.capture)
        lifecycle.appear(active: true); XCTAssertEqual(lifecycle.capture, first)
        lifecycle.sceneChanged(active: false); XCTAssertNil(lifecycle.capture)
        lifecycle.finish(first) { completions += 1 }; XCTAssertEqual(completions, 0)
        lifecycle.sceneChanged(active: true); let resumed = try XCTUnwrap(lifecycle.capture)
        XCTAssertNotEqual(resumed, first)
        lifecycle.finish(first) { completions += 1 }; XCTAssertEqual(completions, 0)
        lifecycle.disappear(); lifecycle.finish(resumed) { completions += 1 }
        XCTAssertEqual(completions, 0)
        lifecycle.appear(active: true); let reopened = try XCTUnwrap(lifecycle.capture)
        XCTAssertNotEqual(reopened, resumed)
        lifecycle.finish(resumed) { completions += 1 }; XCTAssertEqual(completions, 0)
        lifecycle.finish(reopened) { completions += 1 }
        lifecycle.finish(reopened) { completions += 1 }
        lifecycle.disappear(); lifecycle.appear(active: true)
        XCTAssertNil(lifecycle.capture); XCTAssertEqual(completions, 1)
    }
    func testInactiveAppearanceCannotConsumeResultAndNewPresentationCannotUseOldLease() throws {
        let old = ProjectSubmissionResultLifecycle(), replacement = ProjectSubmissionResultLifecycle()
        var completions = 0
        old.appear(active: false); XCTAssertNil(old.capture)
        old.sceneChanged(active: true); let original = try XCTUnwrap(old.capture)
        old.disappear(); replacement.appear(active: true)
        replacement.finish(original) { completions += 1 }; old.finish(original) { completions += 1 }
        XCTAssertEqual(completions, 0)
        replacement.finish(try XCTUnwrap(replacement.capture)) { completions += 1 }
        XCTAssertEqual(completions, 1)
    }
    func testResultDestinationSurvivesHostPushButRejectsReplacedSessionBeforeRedraw() async throws {
        let (model, _, owner, storage) = try await setup()
        let receipt = try XCTUnwrap(model.submittedHandoff), incarnation = model.editorIncarnation
        let destination = try XCTUnwrap(model.submissionDestination(receipt, incarnation: incarnation))
        let before = storage.data
        XCTAssertEqual(destination.receipt, receipt); XCTAssertTrue(model.submissionDestinationIsCurrent(destination))
        model.leave() // The ordinary navigation push covers the editor.
        XCTAssertFalse(model.submissionIsCurrent(receipt, incarnation: incarnation))
        XCTAssertNil(model.submissionDestination(receipt, incarnation: incarnation))
        XCTAssertTrue(model.submissionDestinationIsCurrent(destination))
        owner.session = try .init(accountID: 7, epoch: 2, storageNamespace: "submission-model-test")
        XCTAssertFalse(model.submissionDestinationIsCurrent(destination)); XCTAssertEqual(storage.data, before)
    }
    func testReplacementVisitRetiresResultDestinationWithoutDeletingReceipt() async throws {
        let (model, coordinator, _, storage) = try await setup()
        let receipt = try XCTUnwrap(model.submittedHandoff)
        let destination = try XCTUnwrap(model.submissionDestination(receipt, incarnation: model.editorIncarnation))
        let before = storage.data
        let replacement = ProjectEditModel(coordinator: coordinator); await replacement.load()
        XCTAssertFalse(model.submissionDestinationIsCurrent(destination))
        XCTAssertFalse(replacement.submissionDestinationIsCurrent(destination))
        XCTAssertNotNil(replacement.submissionEvidence); XCTAssertEqual(storage.data, before)
    }
    func testRetiredAcknowledgmentCannotReacquireDestinationWhenSessionValueReturns() async throws {
        let (model, coordinator, owner, storage) = try await setup()
        let receipt = try XCTUnwrap(model.submittedHandoff), session = owner.session
        let destination = try XCTUnwrap(model.submissionDestination(receipt, incarnation: model.editorIncarnation))
        let before = storage.data
        owner.session = nil; XCTAssertFalse(model.submissionDestinationIsCurrent(destination))
        coordinator.synchronizeSession(); owner.session = session
        XCTAssertFalse(model.submissionDestinationIsCurrent(destination))
        XCTAssertNil(model.submissionDestination(receipt, incarnation: model.editorIncarnation))
        XCTAssertEqual(storage.data, before)
    }
}

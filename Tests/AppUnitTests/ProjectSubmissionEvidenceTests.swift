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

}

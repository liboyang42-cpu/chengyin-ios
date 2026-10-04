import XCTest
@testable import Questify

@MainActor final class ProjectEditCompletionModelTests: XCTestCase {
    func testNormalModelLoadsEditsReviewsAndRestoresBingo() async throws {
        let session = try ProjectEditSession(accountID: 901, epoch: 1, storageNamespace: "fixture-cn")
        var initial = ProjectEditSyntheticFixtures.snapshot()
        initial.draft.preserved["completeRuleJson"] = .string(#"{"future":{"keep":true},"nodeCompletion":{"mode":"AT_LEAST","requiredCount":1}}"#)
        let storage = ProjectEditMemoryStorage(); let store = ProjectEditLocalStore(storage: storage)
        let service = ProjectEditSyntheticService(snapshot: initial)
        let coordinator = ProjectEditCoordinator(initial: initial, service: service, store: store, currentSession: { session })
        let model = ProjectEditModel(coordinator: coordinator)
        await model.load(); XCTAssertTrue(model.fullEdit)
        XCTAssertEqual(model.completionRules.wrappedValue.mode, "AT_LEAST")
        var rules = model.completionRules.wrappedValue
        rules.bingoEnabled = true; rules.cells[5].label = "Sixth physical cell"; rules.cells[5].feedbackText = "A small celebration"
        model.completionRules.wrappedValue = rules; model.changed(); model.saveLocal(); model.review()
        let review = try XCTUnwrap(model.confirmation)
        let readback = ProjectEditCompletionRules(raw: review.payload["completeRuleJson"])
        XCTAssertEqual(readback.cells[5].feedbackText, "A small celebration")
        XCTAssertEqual(readback.mode, "AT_LEAST")
        model.cancelReview(); model.leave()
        let reopened = ProjectEditModel(coordinator: ProjectEditCoordinator(initial: initial, service: service, store: store, currentSession: { session }))
        await reopened.load(); XCTAssertTrue(reopened.canRestore); reopened.restore()
        XCTAssertEqual(reopened.completionRules.wrappedValue.cells, rules.cells)
        XCTAssertTrue(service.submissions.isEmpty)
    }
    func testWhitelistAndUnsupportedSourceBindingsCannotMutateRules() async throws {
        let session = try ProjectEditSession(accountID: 901, epoch: 1, storageNamespace: "fixture-cn")
        for scope in [ProjectEditScope.full, .whitelist] {
            var snapshot = ProjectEditSyntheticFixtures.snapshot(scope: scope)
            if scope == .full { snapshot.draft.preserved["completeRuleJson"] = .string("{future malformed") }
            let service = ProjectEditSyntheticService(snapshot: snapshot)
            let model = ProjectEditModel(coordinator: ProjectEditCoordinator(initial: snapshot, service: service, store: .init(storage: ProjectEditMemoryStorage()), currentSession: { session }))
            await model.load(); let before = model.draft
            var rules = model.completionRules.wrappedValue; rules.bingoEnabled = true; rules.cells[0].feedbackText = "attempt"
            model.completionRules.wrappedValue = rules
            XCTAssertEqual(model.draft, before)
        }
    }
    func testSessionReplacementClearsImportedRulesAndReview() async throws {
        var session: ProjectEditSession? = try .init(accountID: 901, epoch: 1, storageNamespace: "fixture-cn")
        let service = ProjectEditSyntheticService()
        let model = ProjectEditModel(coordinator: ProjectEditCoordinator(initial: service.snapshot, service: service, store: .init(storage: ProjectEditMemoryStorage()), currentSession: { session }))
        await model.load()
        var rules = model.completionRules.wrappedValue; rules.bingoEnabled = true; rules.cells[0].feedbackText = "owner-only draft"
        model.completionRules.wrappedValue = rules; model.review(); XCTAssertNotNil(model.confirmation)
        session = nil; await model.load(force: true)
        XCTAssertNil(model.confirmation); XCTAssertNil(model.draft.completionRules); XCTAssertFalse(model.fullEdit)
        XCTAssertTrue(service.submissions.isEmpty)
    }
}

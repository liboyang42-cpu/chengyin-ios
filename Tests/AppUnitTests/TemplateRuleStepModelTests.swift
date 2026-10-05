import XCTest
@testable import Questify

@MainActor final class TemplateRuleStepModelTests: XCTestCase {
    private func session(_ account: Int = 901, epoch: UInt64 = 1) throws -> TemplateAuthoringSession {
        try .init(accountID: account, namespace: "rule-step-fixture", epoch: epoch, authorizationRevision: "member")
    }
    private func makeModel(owner: @escaping () -> TemplateAuthoringSession?, raw: String? = "First\nSecond") -> TemplateAuthoringModel {
        let coordinator = TemplateAuthoringCoordinator(store: .init(storage: TemplateAuthoringMemoryStorage()), currentSession: owner)
        var seed = TemplateAuthoringDraft(title: "Rules"); seed.ruleInstructions = raw
        coordinator.open(seed: seed)
        let model = TemplateAuthoringModel(coordinator: coordinator); model.load(); return model
    }
    func testLocalEditAndSaveSurviveParentReappearanceAndRestore() throws {
        let owner = try session(), store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage())
        let coordinator = TemplateAuthoringCoordinator(store: store, currentSession: { owner })
        var seed = TemplateAuthoringDraft(title: "Rules"); seed.ruleInstructions = " First \n Second "
        coordinator.open(seed: seed)
        let model = TemplateAuthoringModel(coordinator: coordinator); model.load()
        XCTAssertEqual(model.draft.ruleInstructions, seed.ruleInstructions)
        model.ruleStep(model.ruleSteps.rows[0].id).wrappedValue = " Changed "
        model.addRuleStep(); model.ruleStep(model.ruleSteps.rows[2].id).wrappedValue = "Third"
        XCTAssertEqual(model.draft.ruleInstructions, "Changed\nSecond\nThird")
        XCTAssertEqual(coordinator.draft, model.draft)
        model.leave(); model.load(); model.save()
        let reopened = TemplateAuthoringCoordinator(store: store, currentSession: { owner })
        reopened.open(); reopened.restoreDraft()
        XCTAssertEqual(reopened.draft.ruleInstructions, "Changed\nSecond\nThird")
        XCTAssertFalse(coordinator.canSubmit); XCTAssertNil(coordinator.review)
        XCTAssertNil(try store.pending(session: owner, identity: coordinator.identity))
    }
    func testDeletedOrDiscardedRowBindingCannotEditAnotherRow() throws {
        let owner = try session(), model = makeModel(owner: { owner })
        let stale = model.ruleStep(model.ruleSteps.rows[0].id)
        model.removeRuleStep(model.ruleSteps.rows[0].id)
        stale.wrappedValue = "deleted"
        XCTAssertEqual(model.draft.ruleInstructions, "Second"); XCTAssertEqual(stale.wrappedValue, "")
        let discarded = model.ruleStep(model.ruleSteps.rows[0].id)
        model.discard(); discarded.wrappedValue = "discarded"
        XCTAssertNil(model.draft.ruleInstructions); XCTAssertEqual(discarded.wrappedValue, "")
        model.ruleStep(model.ruleSteps.rows[0].id).wrappedValue = "Current"
        XCTAssertEqual(model.draft.ruleInstructions, "Current")
    }
    func testRetainedBindingCannotCrossAccountOrEpoch() throws {
        for replacement in [try session(902), try session(901, epoch: 2)] {
            var owner: TemplateAuthoringSession? = try session()
            let model = makeModel(owner: { owner }), binding = model.ruleStep(model.ruleSteps.rows[0].id)
            let previous = model.draft
            owner = replacement
            binding.wrappedValue = "late"; model.addRuleStep(); model.removeRuleStep(model.ruleSteps.rows[0].id)
            XCTAssertEqual(model.draft, previous); XCTAssertEqual(binding.wrappedValue, "")
            model.load(); binding.wrappedValue = "late after load"
            XCTAssertNil(model.draft.ruleInstructions); XCTAssertEqual(binding.wrappedValue, "")
        }
    }
    func testRestoreInvalidatesRetainedBindingsAndNeverNormalizesHistoricalText() throws {
        let owner = try session(), store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage())
        let coordinator = TemplateAuthoringCoordinator(store: store, currentSession: { owner })
        var seed = TemplateAuthoringDraft(title: "Rules"); seed.ruleInstructions = " \n legacy\r\n "
        coordinator.open(seed: seed); coordinator.saveLocal()
        let reopened = TemplateAuthoringCoordinator(store: store, currentSession: { owner })
        let model = TemplateAuthoringModel(coordinator: reopened); model.load()
        let binding = model.ruleStep(model.ruleSteps.rows[0].id)
        XCTAssertFalse(model.canEdit); binding.wrappedValue = "before restore"
        model.restore(); binding.wrappedValue = "stale after restore"
        XCTAssertEqual(model.draft.ruleInstructions, seed.ruleInstructions)
        model.save(); XCTAssertEqual(model.draft.ruleInstructions, seed.ruleInstructions)
    }
    func testHistoricalLimitsAndASCIIFailurePreserveTextAndShowRecoverableIssue() throws {
        let owner = try session(), model = makeModel(owner: { owner })
        let binding = model.ruleStep(model.ruleSteps.rows[0].id), previous = model.draft
        binding.wrappedValue = String(repeating: "x", count: 61)
        XCTAssertEqual(model.draft, previous); XCTAssertEqual(model.ruleStepIssue, "templateRules.asciiLimit")
        binding.wrappedValue = "Valid"; XCTAssertNil(model.ruleStepIssue)
        for _ in 2..<12 { model.addRuleStep() }
        let full = model.draft
        model.addRuleStep(); XCTAssertEqual(model.draft, full); XCTAssertEqual(model.ruleStepIssue, "templateRules.rowLimit")
        let historical = self.makeModel(owner: { owner }, raw: String(repeating: "x", count: 61))
        let raw = historical.draft.ruleInstructions
        historical.ruleStep(historical.ruleSteps.rows[0].id).wrappedValue = "replacement"
        historical.addRuleStep(); historical.removeRuleStep(historical.ruleSteps.rows[0].id)
        XCTAssertEqual(historical.draft.ruleInstructions, raw)
    }
    func testRuleEditInvalidatesReviewWithoutChangingRemoteGates() throws {
        let owner = try session(), model = makeModel(owner: { owner })
        model.prepare(.saveDraft); XCTAssertNotNil(model.review)
        model.ruleStep(model.ruleSteps.rows[0].id).wrappedValue = "Changed"
        XCTAssertNil(model.review); XCTAssertNil(model.coordinator.review)
        XCTAssertFalse(model.coordinator.canSubmit)
    }
    func testLockedSubmissionCannotEditAnyRuleControl() async throws {
        let owner = try session()
        let coordinator = TemplateAuthoringCoordinator(adapter: .init(transport: TemplateAuthoringSyntheticTransport(scenario: .uncertain)), store: .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { owner })
        var seed = TemplateAuthoringSyntheticFixtures.compoundDraft(); seed.ruleInstructions = "First\nSecond"
        coordinator.open(seed: seed)
        let model = TemplateAuthoringModel(coordinator: coordinator); model.load()
        let binding = model.ruleStep(model.ruleSteps.rows[0].id)
        model.prepare(.publish); await model.confirm(try XCTUnwrap(model.review))
        XCTAssertTrue(coordinator.locked)
        XCTAssertEqual(binding.wrappedValue, "First")
        let previous = model.draft
        binding.wrappedValue = "late"; model.addRuleStep(); model.removeRuleStep(model.ruleSteps.rows[0].id)
        XCTAssertEqual(model.draft, previous); XCTAssertEqual(coordinator.draft, previous)
    }
}

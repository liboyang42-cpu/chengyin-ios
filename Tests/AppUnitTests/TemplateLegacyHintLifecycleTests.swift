import XCTest
@testable import Questify

@MainActor final class TemplateLegacyHintLifecycleTests: XCTestCase {
    private func session(_ account: Int = 901, epoch: UInt64 = 1, role: String = "member") throws -> TemplateAuthoringSession {
        try .init(accountID: account, namespace: "hint-lifecycle-fixture", epoch: epoch, authorizationRevision: role)
    }
    private func seed() -> TemplateAuthoringDraft {
        var draft = TemplateAuthoringDraft(title: "Local hints"); draft.validationMethod = .text
        draft.hint1 = "first"; draft.hint2 = "second"; draft.answerReveal = "answer"
        return draft
    }
    func testChildNavigationRepeatedEditsSaveAndReopenPreserveIntentAndText() throws {
        let owner = try session(), store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage())
        let coordinator = TemplateAuthoringCoordinator(store: store, currentSession: { owner }); coordinator.open(seed: seed())
        let model = TemplateAuthoringModel(coordinator: coordinator); model.load()
        let binding = model.legacyHint(.hint1)
        binding.wrappedValue = "first edit"; binding.wrappedValue = "second edit"
        model.leave(); model.load(); model.save()
        let expected = model.draft
        XCTAssertEqual(expected.hint1, "second edit"); XCTAssertEqual(expected.answerReveal, "answer")
        let reopened = TemplateAuthoringCoordinator(store: store, currentSession: { owner })
        reopened.open(); reopened.restoreDraft(); XCTAssertEqual(reopened.draft, expected)
        XCTAssertFalse(coordinator.canSubmit); XCTAssertNil(try store.pending(session: owner, identity: coordinator.identity))
    }
    func testOffClearsAndRetainedFieldCannotRestoreClearedTextAfterReenable() throws {
        let owner = try session()
        let coordinator = TemplateAuthoringCoordinator(store: .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { owner })
        coordinator.open(seed: seed()); let model = TemplateAuthoringModel(coordinator: coordinator); model.load()
        let oldField = model.legacyHint(.hint1), oldToggle = model.legacyHintToggle()
        oldToggle.wrappedValue = false
        XCTAssertEqual(model.draft.hint1, ""); XCTAssertEqual(model.draft.hint2, ""); XCTAssertEqual(model.draft.answerReveal, "")
        oldToggle.wrappedValue = true; XCTAssertFalse(model.draft.legacyHintsAreEnabled)
        model.legacyHintToggle().wrappedValue = true
        oldField.wrappedValue = "late stale field"
        XCTAssertEqual(model.draft.hint1, ""); XCTAssertEqual(oldField.wrappedValue, "")
        model.legacyHint(.hint1).wrappedValue = "fresh field"; XCTAssertEqual(coordinator.draft.hint1, "fresh field")
    }
    func testMethodOneTwoOneKeepsDisabledStateAndFencesOldBindings() throws {
        let owner = try session()
        let coordinator = TemplateAuthoringCoordinator(store: .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { owner })
        coordinator.open(seed: seed()); let model = TemplateAuthoringModel(coordinator: coordinator); model.load()
        let field = model.legacyHint(.hint1), method = model.legacyHintMethodBinding()
        method.wrappedValue = .photo
        XCTAssertFalse(model.draft.legacyHintsAreEnabled); XCTAssertEqual(model.draft.hint1, "first")
        method.wrappedValue = .text; XCTAssertEqual(model.draft.validationMethod, .photo)
        model.legacyHintMethodBinding().wrappedValue = .text
        XCTAssertFalse(model.draft.legacyHintsAreEnabled)
        field.wrappedValue = "late"; XCTAssertEqual(model.draft.hint1, "first")
        model.legacyHintToggle().wrappedValue = true
        XCTAssertEqual(model.legacyHint(.hint1).wrappedValue, "first")
    }
    func testRetainedBindingsCannotCrossAccountEpochOrRoleAfterReload() throws {
        for next in [try session(902), try session(epoch: 2), try session(role: "merchant")] {
            var owner: TemplateAuthoringSession? = try session()
            let coordinator = TemplateAuthoringCoordinator(store: .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { owner })
            coordinator.open(seed: seed()); let model = TemplateAuthoringModel(coordinator: coordinator); model.load()
            let field = model.legacyHint(.hint1), toggle = model.legacyHintToggle(), method = model.legacyHintMethodBinding()
            let original = model.draft; owner = next
            field.wrappedValue = "late"; toggle.wrappedValue = false; method.wrappedValue = .photo
            XCTAssertEqual(model.draft, original); XCTAssertEqual(field.wrappedValue, "")
            XCTAssertFalse(toggle.wrappedValue); XCTAssertEqual(method.wrappedValue, .manual)
            XCTAssertEqual(model.legacyHint(.hint1).wrappedValue, "")
            XCTAssertEqual(model.legacyHint(.hint2).wrappedValue, "")
            XCTAssertEqual(model.legacyHint(.answerReveal).wrappedValue, "")
            XCTAssertFalse(model.legacyHintToggle().wrappedValue)
            XCTAssertEqual(model.legacyHintMethodBinding().wrappedValue, .manual)
            model.legacyHint(.hint1).wrappedValue = "fresh binding, old draft"
            model.legacyHintToggle().wrappedValue = false; model.legacyHintMethodBinding().wrappedValue = .photo
            XCTAssertEqual(model.draft, original)
            model.load(); model.draft.validationMethod = .text; model.legacyHintToggle().wrappedValue = true
            field.wrappedValue = "old owner"; toggle.wrappedValue = false; method.wrappedValue = .photo
            XCTAssertNil(model.draft.hint1); XCTAssertTrue(model.draft.legacyHintsAreEnabled); XCTAssertEqual(model.draft.validationMethod, .text)
        }
    }
    func testDiscardAndSameOwnerReloadInvalidateRetainedCallbacks() throws {
        let owner = try session()
        let coordinator = TemplateAuthoringCoordinator(store: .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { owner })
        coordinator.open(seed: seed()); let model = TemplateAuthoringModel(coordinator: coordinator); model.load()
        let beforeLoad = model.legacyHint(.hint1)
        model.load(); beforeLoad.wrappedValue = "late"; XCTAssertEqual(model.draft.hint1, "first")
        let beforeDiscard = model.legacyHint(.hint1), toggle = model.legacyHintToggle()
        model.discard(); model.draft.validationMethod = .text; model.legacyHintToggle().wrappedValue = true
        beforeDiscard.wrappedValue = "discarded"; toggle.wrappedValue = false
        XCTAssertNil(model.draft.hint1); XCTAssertTrue(model.draft.legacyHintsAreEnabled)
    }
    func testRestoreDoesNotNormalizeLegacyDraftAndFencesPreRestoreBindings() throws {
        let owner = try session(), store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage())
        let coordinator = TemplateAuthoringCoordinator(store: store, currentSession: { owner })
        coordinator.open(seed: seed()); coordinator.saveLocal()
        let reopened = TemplateAuthoringCoordinator(store: store, currentSession: { owner })
        let model = TemplateAuthoringModel(coordinator: reopened); model.load()
        let field = model.legacyHint(.hint1), toggle = model.legacyHintToggle()
        model.restore(); let restored = model.draft
        field.wrappedValue = "late restore"; toggle.wrappedValue = false
        XCTAssertEqual(model.draft, restored); XCTAssertEqual(restored, seed()); XCTAssertNil(restored.legacyHintsEnabled)
    }
    func testHiddenOrFinishDisabledFieldsCannotMutateAndModifiersStayEligible() throws {
        let owner = try session()
        let coordinator = TemplateAuthoringCoordinator(store: .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { owner })
        coordinator.open(seed: seed()); let model = TemplateAuthoringModel(coordinator: coordinator); model.load()
        model.draft.advanced.set("timer", "enabled", .bool(true))
        XCTAssertTrue(model.draft.legacyHintControlsVisible)
        model.legacyHint(.hint1).wrappedValue = "timer hint"
        model.draft.advanced.set("qa", "enabled", .bool(true)); let hidden = model.draft
        model.legacyHint(.hint1).wrappedValue = "wrong"; model.legacyHintToggle().wrappedValue = false
        XCTAssertEqual(model.draft, hidden)
        model.draft.advanced.set("qa", "enabled", .bool(false)); model.draft.finishEnabled = false
        let disabled = model.draft
        model.legacyHint(.hint1).wrappedValue = "wrong"; model.legacyHintToggle().wrappedValue = false
        XCTAssertEqual(model.draft, disabled)
    }
    func testNewHintEditInvalidatesPreparedReviewWithoutActivatingWrites() throws {
        let owner = try session()
        let coordinator = TemplateAuthoringCoordinator(store: .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { owner })
        coordinator.open(seed: seed()); let model = TemplateAuthoringModel(coordinator: coordinator); model.load()
        model.prepare(.saveDraft); XCTAssertNotNil(model.review)
        model.legacyHint(.hint1).wrappedValue = "revised"
        XCTAssertNil(model.review); XCTAssertNil(coordinator.review); XCTAssertFalse(coordinator.canSubmit)
    }
    func testLockedSubmissionRejectsHintAndMethodCallbacks() async throws {
        let owner = try session()
        let coordinator = TemplateAuthoringCoordinator(adapter: .init(transport: TemplateAuthoringSyntheticTransport(scenario: .uncertain)), store: .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { owner })
        coordinator.open(seed: seed()); let model = TemplateAuthoringModel(coordinator: coordinator); model.load()
        let field = model.legacyHint(.hint1), hint2 = model.legacyHint(.hint2), answer = model.legacyHint(.answerReveal)
        let toggle = model.legacyHintToggle(), method = model.legacyHintMethodBinding()
        model.prepare(.saveDraft); await model.confirm(try XCTUnwrap(model.review))
        XCTAssertTrue(coordinator.locked); let original = model.draft
        XCTAssertTrue(model.canReadLegacyHints); XCTAssertFalse(model.canEdit)
        XCTAssertEqual(field.wrappedValue, "first"); XCTAssertEqual(hint2.wrappedValue, "second"); XCTAssertEqual(answer.wrappedValue, "answer")
        XCTAssertTrue(toggle.wrappedValue); XCTAssertEqual(method.wrappedValue, .text)
        XCTAssertEqual(model.legacyHint(.hint1).wrappedValue, "first")
        XCTAssertEqual(model.legacyHint(.hint2).wrappedValue, "second")
        XCTAssertEqual(model.legacyHint(.answerReveal).wrappedValue, "answer")
        XCTAssertTrue(model.legacyHintToggle().wrappedValue); XCTAssertEqual(model.legacyHintMethodBinding().wrappedValue, .text)
        field.wrappedValue = "late"; toggle.wrappedValue = false; method.wrappedValue = .photo
        model.legacyHint(.hint1).wrappedValue = "fresh locked binding"
        model.legacyHintToggle().wrappedValue = false; model.legacyHintMethodBinding().wrappedValue = .photo
        XCTAssertEqual(model.draft, original); XCTAssertEqual(coordinator.draft, original)
    }
    func testLogoutHidesFreshAndRetainedBindingsBeforeReload() throws {
        var owner: TemplateAuthoringSession? = try session()
        let coordinator = TemplateAuthoringCoordinator(store: .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { owner })
        coordinator.open(seed: seed()); let model = TemplateAuthoringModel(coordinator: coordinator); model.load()
        let field = model.legacyHint(.answerReveal), toggle = model.legacyHintToggle(), method = model.legacyHintMethodBinding()
        let original = model.draft; owner = nil
        XCTAssertFalse(model.canReadLegacyHints)
        XCTAssertEqual(field.wrappedValue, ""); XCTAssertFalse(toggle.wrappedValue); XCTAssertEqual(method.wrappedValue, .manual)
        XCTAssertEqual(model.legacyHint(.answerReveal).wrappedValue, "")
        XCTAssertFalse(model.legacyHintToggle().wrappedValue); XCTAssertEqual(model.legacyHintMethodBinding().wrappedValue, .manual)
        field.wrappedValue = "retained"; toggle.wrappedValue = false; method.wrappedValue = .photo
        model.legacyHint(.answerReveal).wrappedValue = "fresh"
        model.legacyHintToggle().wrappedValue = false; model.legacyHintMethodBinding().wrappedValue = .photo
        XCTAssertEqual(model.draft, original)
    }
}

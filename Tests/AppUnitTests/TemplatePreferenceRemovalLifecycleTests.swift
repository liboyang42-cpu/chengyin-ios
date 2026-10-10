import XCTest
@testable import Questify

/// Authored app-hosted tests. Execution requires the Apple toolchain.
@MainActor final class TemplatePreferenceRemovalLifecycleTests: XCTestCase {
    private final class Owner {
        var value: TemplateAuthoringSession?
        init(_ value: TemplateAuthoringSession?) { self.value = value }
    }
    private let raw = #" {"steps":[{"title":"first","options":[{"text":"A"},{"text":"B"},{"text":"C"}]},{"title":"second","options":[{"text":"X"},{"text":"Y"}]}],"results":{"precise":9007199254740993},"future":1e1000} "#
    private func session(account: Int = 901, epoch: UInt64 = 1, role: String = "member", namespace: String = "removal-test") throws -> TemplateAuthoringSession {
        try .init(accountID: account, namespace: namespace, epoch: epoch, authorizationRevision: role)
    }
    private func setup() throws -> (TemplateAuthoringModel, TemplatePreferenceRemovalController, Owner, TemplateAuthoringLocalStore) {
        let owner = Owner(try session()), store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage())
        let coordinator = TemplateAuthoringCoordinator(store: store, currentSession: { owner.value })
        var seed = TemplateAuthoringDraft(title: "Local questionnaire"); seed.validationMethod = .preference; seed.preferenceJson = raw
        coordinator.open(seed: seed)
        let model = TemplateAuthoringModel(coordinator: coordinator); model.load()
        return (model, TemplatePreferenceRemovalController(model: model), owner, store)
    }
    private func open(_ controller: TemplatePreferenceRemovalController) throws -> TemplatePreferenceRemovalController.Presentation {
        controller.open(try XCTUnwrap(controller.capture())); return try XCTUnwrap(controller.currentPresentation)
    }
    private func request(_ controller: TemplatePreferenceRemovalController, _ original: TemplatePreferenceRemovalController.Presentation,
                         _ target: TemplatePreferenceRemoval.Target = .option(question: 0, index: 1)) throws -> TemplatePreferenceRemovalController.Review {
        controller.request(target, in: original); return try XCTUnwrap(controller.review)
    }
    func testOpenRequestCancelAndCloseNeverMutateOrPersist() throws {
        let (model, controller, owner, store) = try setup(), before = model.draft
        let original = try open(controller), intent = try request(controller, original)
        XCTAssertEqual(model.draft, before); XCTAssertEqual(model.coordinator.draft, before)
        controller.cancel(intent, in: original); XCTAssertNil(controller.review)
        controller.close(original); XCTAssertNil(controller.currentPresentation)
        XCTAssertEqual(model.draft, before); XCTAssertNil(try store.active(session: XCTUnwrap(owner.value)))
    }
    func testOnlyExplicitCurrentConfirmationCommitsOnceToExistingDraft() throws {
        let (model, controller, owner, store) = try setup(), before = model.draft
        let original = try open(controller), intent = try request(controller, original)
        let expected = try TemplatePreferenceRemoval(source: raw).removing(intent.target, from: raw)
        XCTAssertTrue(controller.confirm(intent, in: original)); XCTAssertFalse(controller.confirm(intent, in: original))
        XCTAssertEqual(Array(try XCTUnwrap(model.draft.preferenceJson).utf8), Array(expected.utf8))
        var comparison = model.draft; comparison.preferenceJson = before.preferenceJson
        XCTAssertEqual(comparison, before); XCTAssertEqual(model.coordinator.draft, model.draft)
        XCTAssertNil(controller.presentation); XCTAssertNil(controller.review)
        XCTAssertFalse(model.coordinator.canSubmit); XCTAssertNil(model.coordinator.review)
        XCTAssertNil(try store.pending(session: XCTUnwrap(owner.value), identity: model.coordinator.identity))
        model.save(); let reopened = TemplateAuthoringCoordinator(store: store, currentSession: { owner.value })
        reopened.open(); reopened.restoreDraft(); XCTAssertEqual(reopened.draft.preferenceJson, expected)
    }
    func testCancelledReviewCannotConfirmOrCancelReplacementReview() throws {
        let (model, controller, _, _) = try setup(), original = try open(controller)
        let old = try request(controller, original); controller.cancel(old, in: original)
        let fresh = try request(controller, original, .question(1))
        XCTAssertFalse(controller.confirm(old, in: original)); controller.cancel(old, in: original)
        XCTAssertEqual(controller.review?.id, fresh.id); XCTAssertEqual(model.draft.preferenceJson, raw)
        XCTAssertTrue(controller.confirm(fresh, in: original))
    }
    func testRetainedDismissalAndConfirmationCannotAffectReopenedSameBytes() throws {
        let (model, controller, _, _) = try setup(), old = try open(controller), intent = try request(controller, old)
        let queued = try XCTUnwrap(controller.capture()); controller.close(old)
        controller.open(queued); XCTAssertNil(controller.currentPresentation)
        let current = try open(controller), fresh = try request(controller, current)
        controller.close(old); controller.cancel(intent, in: old)
        XCTAssertFalse(controller.confirm(intent, in: old)); XCTAssertEqual(controller.review?.id, fresh.id)
        XCTAssertEqual(controller.currentPresentation?.id, current.id); XCTAssertEqual(model.draft.preferenceJson, raw)
    }
    func testExactRawChangeAndSameByteABARejectQueuedActions() throws {
        let (model, controller, _, _) = try setup(), original = try open(controller), intent = try request(controller, original)
        model.draft.preferenceJson = raw + " "
        XCTAssertFalse(controller.confirm(intent, in: original)); XCTAssertNil(controller.currentPresentation)
        model.changed(); model.draft.preferenceJson = raw; model.changed()
        XCTAssertFalse(controller.confirm(intent, in: original)); XCTAssertEqual(model.draft.preferenceJson, raw)
    }
    func testLoadRestoreDiscardAndLeaveFenceOldCaptureAndReview() throws {
        for action in ["load", "restore", "discard", "leave"] {
            let (model, controller, _, _) = try setup(), original = try open(controller), intent = try request(controller, original)
            let capture = try XCTUnwrap(controller.capture())
            switch action { case "load": model.load(); case "restore": model.restore(); case "discard": model.discard(); default: model.leave() }
            let after = model.draft
            XCTAssertFalse(controller.confirm(intent, in: original)); XCTAssertNil(controller.currentPresentation)
            controller.retire(); controller.open(capture); XCTAssertNil(controller.currentPresentation)
            XCTAssertEqual(model.draft, after)
        }
    }
    func testAccountEpochRoleNamespaceAndLogoutCannotMutateBeforeReload() throws {
        let nextOwners: [TemplateAuthoringSession?] = [try session(account: 902), try session(epoch: 2), try session(role: "merchant"), try session(namespace: "other"), nil]
        for next in nextOwners {
            let (model, controller, owner, _) = try setup(), original = try open(controller), intent = try request(controller, original)
            owner.value = next; let before = model.draft
            XCTAssertNil(controller.currentPresentation); XCTAssertNil(controller.capture())
            XCTAssertFalse(controller.confirm(intent, in: original)); XCTAssertEqual(model.draft, before)
        }
    }
    func testOwnerABAWithReloadNeverRevivesOldPresentation() throws {
        let (model, controller, owner, _) = try setup(), oldOwner = owner.value
        let original = try open(controller), intent = try request(controller, original)
        owner.value = try session(account: 902); model.load(); owner.value = oldOwner; model.load()
        model.draft.validationMethod = .preference; model.draft.preferenceJson = raw; model.changed()
        XCTAssertFalse(controller.confirm(intent, in: original)); XCTAssertEqual(model.draft.preferenceJson, raw)
    }
    func testMethodFinishAndExistingTemplateGuardsApplyBeforeObservation() throws {
        for action in ["method", "finish", "owned"] {
            let (model, controller, _, _) = try setup(), original = try open(controller), intent = try request(controller, original)
            switch action { case "method": model.draft.validationMethod = .text
            case "finish": model.draft.finishEnabled = false
            default: model.draft.id = AuthoringPlayTemplateID(rawValue: 123) }
            XCTAssertFalse(controller.confirm(intent, in: original)); XCTAssertNil(controller.capture())
            XCTAssertEqual(model.draft.preferenceJson, raw)
        }
    }
    func testMinimumAndUnsupportedJSONDoNotOfferConfirmation() throws {
        let (model, controller, _, _) = try setup(), original = try open(controller)
        controller.request(.option(question: 1, index: 0), in: original); XCTAssertNil(controller.review)
        controller.close(original); model.draft.preferenceJson = "{ unfinished"; model.changed()
        let unsupported = try open(controller); XCTAssertNil(unsupported.document)
        controller.request(.question(0), in: unsupported); XCTAssertNil(controller.review)
        controller.close(unsupported); XCTAssertEqual(model.draft.preferenceJson, "{ unfinished")
    }
    func testConcurrentControllersCannotCommitAnOlderReviewAfterFirstChangesSource() throws {
        let (model, first, _, _) = try setup(), second = TemplatePreferenceRemovalController(model: model)
        let a = try open(first), b = try open(second), aIntent = try request(first, a), bIntent = try request(second, b)
        XCTAssertTrue(first.confirm(aIntent, in: a)); let after = model.draft
        XCTAssertFalse(second.confirm(bIntent, in: b)); XCTAssertEqual(model.draft, after)
    }
    func testRemotePreparationStillRejectsLocalQuestionnaireAfterRemoval() throws {
        let (model, controller, _, _) = try setup(), original = try open(controller), intent = try request(controller, original)
        XCTAssertTrue(controller.confirm(intent, in: original))
        for operation in TemplateAuthoringIntent.allCases { model.prepare(operation); XCTAssertNil(model.coordinator.review); XCTAssertNil(model.review) }
        XCTAssertFalse(model.coordinator.canSubmit)
    }
}

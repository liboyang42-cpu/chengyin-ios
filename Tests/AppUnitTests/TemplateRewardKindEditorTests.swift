import XCTest
@testable import Questify

@MainActor final class TemplateRewardKindEditorTests: XCTestCase {
    private final class Owner {
        var session: TemplateAuthoringSession?
        init(_ value: TemplateAuthoringSession) { session = value }
    }
    private func setup(store: TemplateAuthoringLocalStore? = nil) throws -> (TemplateAuthoringModel, TemplateRewardKindEditor, Owner) {
        let owner = Owner(try .init(accountID: 913, namespace: "reward-kind-flow", epoch: 1, authorizationRevision: "member"))
        let model = TemplateAuthoringModel(coordinator: .init(store: store ?? .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { owner.session }))
        model.load(); model.draft.title = "Reward flow"; model.draft.rewardEnabled = true; model.changed()
        return (model, .init(model: model), owner)
    }
    private func fill(_ editor: TemplateRewardKindEditor) {
        editor.toggle(.coupon).wrappedValue = true; editor.coupon().wrappedValue = "42"
        editor.toggle(.feedback).wrappedValue = true; editor.text(.feedback).wrappedValue = "Well done"
        editor.toggle(.medal).wrappedValue = true
        editor.text(.medalName).wrappedValue = "Explorer"; editor.text(.medalImage).wrappedValue = "custom:medal"
        editor.medalStyle().wrappedValue = "enamel"
    }
    func testEnableFillAndFreshLocalRestoreCoverAllThreeRewardKinds() throws {
        let store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage())
        let (model, editor, owner) = try setup(store: store), empty = model.draft
        XCTAssertFalse(editor.hasSelection)
        editor.toggle(.coupon).wrappedValue = true
        XCTAssertEqual(model.draft, empty, "Enabling an empty editor does not fabricate a coupon")
        fill(editor); let expected = model.draft
        XCTAssertEqual(editor.enabled, [.coupon, .feedback, .medal]); XCTAssertEqual(model.coordinator.draft, expected)
        model.save(); editor.retire(); model.leave()
        let reopened = TemplateAuthoringModel(coordinator: .init(store: store, currentSession: { owner.session }))
        reopened.load(); reopened.restore(); let fresh = TemplateRewardKindEditor(model: reopened)
        XCTAssertEqual(reopened.draft, expected); XCTAssertEqual(fresh.enabled, [.coupon, .feedback, .medal])
        XCTAssertFalse(model.coordinator.canSubmit)
    }
    func testDisableAndReenableEachKindNeverRestoresItsClearedContent() throws {
        for kind in TemplateRewardKind.allCases {
            let (model, editor, _) = try setup(); fill(editor)
            let before = model.draft, expected = try XCTUnwrap(TemplateRewardKinds.disabling(kind, in: before))
            editor.toggle(kind).wrappedValue = false
            XCTAssertEqual(model.draft, expected); XCTAssertFalse(editor.isEnabled(kind))
            editor.toggle(kind).wrappedValue = true
            XCTAssertEqual(model.draft, expected); XCTAssertTrue(editor.isEnabled(kind))
        }
    }
    func testOldFieldsAndToggleCannotRepopulateAReenabledType() throws {
        let (model, editor, _) = try setup(); fill(editor)
        let feedback = editor.text(.feedback), toggle = editor.toggle(.feedback)
        toggle.wrappedValue = false; editor.toggle(.feedback).wrappedValue = true
        feedback.wrappedValue = "stale"; toggle.wrappedValue = false
        XCTAssertNil(model.draft.feedbackText); XCTAssertTrue(editor.isEnabled(.feedback))
        editor.text(.feedback).wrappedValue = "Current"; XCTAssertEqual(model.draft.feedbackText, "Current")
    }
    func testDisablingOneKindDoesNotInterruptTypingInAnother() throws {
        let (model, editor, _) = try setup(); fill(editor)
        let feedback = editor.text(.feedback)
        editor.toggle(.coupon).wrappedValue = false
        feedback.wrappedValue = "A"; feedback.wrappedValue = "Another message"
        XCTAssertEqual(model.draft.feedbackText, "Another message"); XCTAssertNil(model.draft.couponId)
        XCTAssertEqual(model.draft.medalName, "Explorer")
    }
    func testClearMedalKeepsItsEditorOpenForReplacementAndResetsStyle() throws {
        let (model, editor, _) = try setup(); fill(editor)
        model.clearRewardMedalAction()()
        XCTAssertTrue(editor.isEnabled(.medal)); XCTAssertNil(model.draft.medalName); XCTAssertNil(model.draft.medalImg)
        XCTAssertEqual(model.draft.medalStyle, "glow")
        editor.text(.medalName).wrappedValue = "Replacement"; editor.text(.medalImage).wrappedValue = "custom:new"
        XCTAssertEqual(model.draft.medalName, "Replacement"); XCTAssertEqual(model.draft.couponId, 42)
    }
    func testModuleOffOnPreservesDataButRetiresAllOldFieldBindings() throws {
        let (model, editor, _) = try setup(); fill(editor)
        let coupon = editor.coupon(), feedback = editor.text(.feedback), style = editor.medalStyle()
        let content = model.draft
        editor.moduleEnabled().wrappedValue = false; editor.moduleEnabled().wrappedValue = true
        coupon.wrappedValue = "999"; feedback.wrappedValue = "stale"; style.wrappedValue = "glow"
        XCTAssertEqual(model.draft, content)
        XCTAssertEqual(editor.enabled, [.coupon, .feedback, .medal])
    }
    func testReloadRestoreDiscardOwnerAndDismissalRejectRetainedCallbacks() throws {
        for action in ["load", "restore", "discard", "owner", "dismiss"] {
            let (model, editor, owner) = try setup(); fill(editor)
            let text = editor.text(.feedback), toggle = editor.toggle(.medal)
            switch action {
            case "load": model.load()
            case "restore": model.restore()
            case "discard": model.discard()
            case "owner": owner.session = try .init(accountID: 914, namespace: "reward-kind-flow", epoch: 2, authorizationRevision: "member")
            default: editor.retire()
            }
            let expected = model.draft; text.wrappedValue = "stale"; toggle.wrappedValue = false
            XCTAssertEqual(model.draft, expected, action)
            if action == "load" {
                editor.resume()
                XCTAssertTrue(editor.isEnabled(.feedback))
                XCTAssertEqual(editor.text(.feedback).wrappedValue, expected.feedbackText ?? "")
            }
        }
    }
    func testSameLeaseScrollReentryPreservesAnEmptySelectedEditorWithoutRevivingOldBindings() throws {
        let (model, editor, _) = try setup(), before = model.draft
        editor.toggle(.medal).wrappedValue = true
        let old = editor.text(.medalName)
        editor.retire(); editor.resume()
        XCTAssertTrue(editor.isEnabled(.medal)); old.wrappedValue = "stale"
        XCTAssertEqual(model.draft, before)
        editor.text(.medalName).wrappedValue = "Current"; XCTAssertEqual(model.draft.medalName, "Current")
    }
    func testOpeningDoesNotNormalizeHistoricalValuesAndEnablingRevealsThem() throws {
        let (model, editor, _) = try setup()
        model.draft.couponId = -2; model.draft.feedbackText = " \n"; model.draft.medalStyle = "future-style"; model.changed()
        let before = model.draft; editor.reload()
        XCTAssertEqual(model.draft, before); XCTAssertTrue(editor.isEnabled(.feedback))
        editor.toggle(.coupon).wrappedValue = true; editor.toggle(.medal).wrappedValue = true
        XCTAssertEqual(editor.coupon().wrappedValue, "-2"); XCTAssertEqual(editor.medalStyle().wrappedValue, "future-style")
        XCTAssertEqual(model.draft, before)
    }
    func testDurableWriteLockRejectsSubtypeAndFieldChanges() throws {
        let (seedModel, _, owner) = try setup(), session = try XCTUnwrap(owner.session)
        let store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage()), identity = TemplateAuthoringIdentity()
        var seed = seedModel.draft; seed.feedbackText = "Locked"; seed.couponId = 42
        try store.save(seed, session: session, identity: identity)
        try store.savePending(.init(operationID: UUID(), ownerKey: session.ownerKey, identity: identity,
            request: TemplateAuthoringContract.request(seed, intent: .saveDraft), createdAt: Date()), session: session)
        let model = TemplateAuthoringModel(coordinator: .init(store: store, currentSession: { session })); model.load(); model.draft = seed
        let editor = TemplateRewardKindEditor(model: model)
        editor.toggle(.feedback).wrappedValue = false; editor.text(.feedback).wrappedValue = "Changed"
        editor.moduleEnabled().wrappedValue = false
        XCTAssertEqual(model.draft, seed); XCTAssertFalse(editor.canEdit)
    }
}

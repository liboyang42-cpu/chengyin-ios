import XCTest
@testable import Questify

/// Cross-feature lifecycle coverage for the integrated rule, story, and legacy-hint editors.
/// Authored here; execution requires the Apple app-unit test host.
@MainActor final class TemplateEditorIntegrationTests: XCTestCase {
    private func owner(_ epoch: UInt64 = 1) throws -> TemplateAuthoringSession {
        try .init(accountID: 908, namespace: "template-editor-integration", epoch: epoch, authorizationRevision: "member")
    }
    private func seed() -> TemplateAuthoringDraft {
        var draft = TemplateAuthoringDraft(title: "Combined local editors")
        draft.validationMethod = .text; draft.ruleInstructions = " First \n Second "
        draft.hint1 = "first hint"; draft.hint2 = "second hint"; draft.answerReveal = "answer"
        draft.storyEnabled = true; draft.storyText = "independent historical summary"
        draft.storyJson = " [ {\"text\":\"  original scene  \", \"tag\":\"\", \"imgs\":[]} ]\n"
        return draft
    }
    func testSameOwnerReloadPreservesAllEditsAndInvalidatesAllRetainedBindings() throws {
        let session = try owner(), store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage())
        let coordinator = TemplateAuthoringCoordinator(store: store, currentSession: { session })
        coordinator.open(seed: seed()); let model = TemplateAuthoringModel(coordinator: coordinator); model.load()
        let editor = TemplateStoryEditor(model: model)
        let rule = model.ruleStep(try XCTUnwrap(model.ruleSteps.rows.first?.id))
        let story = editor.text(try XCTUnwrap(editor.beats.first?.id), \.text)
        model.legacyHintToggle().wrappedValue = true
        let hint = model.legacyHint(.hint1)
        rule.wrappedValue = "Changed rule"; story.wrappedValue = "  Changed scene  "; hint.wrappedValue = "Changed hint"
        let expected = model.draft
        XCTAssertEqual(coordinator.draft, expected)
        XCTAssertEqual(expected.ruleInstructions, "Changed rule\nSecond")
        XCTAssertEqual(try expected.preparedStoryText(), "Changed scene")
        XCTAssertEqual(expected.storyText, "independent historical summary")
        XCTAssertEqual(expected.storyTimelineEdited, true); XCTAssertEqual(expected.legacyHintsEnabled, true)
        model.leave(); model.load()
        rule.wrappedValue = "stale rule"; story.wrappedValue = "stale scene"; hint.wrappedValue = "stale hint"
        XCTAssertEqual(model.draft, expected); XCTAssertEqual(coordinator.draft, expected)
        XCTAssertFalse(editor.canEdit); model.save()
        let reopened = TemplateAuthoringCoordinator(store: store, currentSession: { session })
        reopened.open(); reopened.restoreDraft(); XCTAssertEqual(reopened.draft, expected)
        XCTAssertFalse(coordinator.canSubmit); XCTAssertNil(try store.pending(session: session, identity: coordinator.identity))
    }
    func testRestorePreservesRawHistoryAndMissingMarkersAcrossAllThreeEditors() throws {
        let session = try owner(), store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage())
        let saved = TemplateAuthoringCoordinator(store: store, currentSession: { session })
        let historical = seed(); saved.open(seed: historical); saved.saveLocal()
        let coordinator = TemplateAuthoringCoordinator(store: store, currentSession: { session })
        let model = TemplateAuthoringModel(coordinator: coordinator); model.load()
        let editor = TemplateStoryEditor(model: model)
        let rule = model.ruleStep(try XCTUnwrap(model.ruleSteps.rows.first?.id))
        let story = editor.text(try XCTUnwrap(editor.beats.first?.id), \.text), hint = model.legacyHint(.hint1)
        XCTAssertFalse(model.canEdit); model.restore()
        rule.wrappedValue = "stale rule"; story.wrappedValue = "stale scene"; hint.wrappedValue = "stale hint"
        XCTAssertEqual(model.draft, historical); XCTAssertEqual(coordinator.draft, historical)
        XCTAssertNil(model.draft.storyTimelineEdited); XCTAssertNil(model.draft.legacyHintsEnabled)
        editor.load(); XCTAssertTrue(editor.canEdit); XCTAssertEqual(model.draft, historical)
        model.save(); XCTAssertEqual(model.draft, historical)
    }
    func testDiscardFencesEveryEditorWithoutRelyingOnIdentityChange() throws {
        let session = try owner()
        let coordinator = TemplateAuthoringCoordinator(store: .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { session })
        coordinator.open(seed: seed()); let model = TemplateAuthoringModel(coordinator: coordinator); model.load()
        let editor = TemplateStoryEditor(model: model)
        let rule = model.ruleStep(try XCTUnwrap(model.ruleSteps.rows.first?.id))
        let story = editor.text(try XCTUnwrap(editor.beats.first?.id), \.text), hint = model.legacyHint(.hint1)
        let identity = coordinator.identity; model.discard()
        XCTAssertEqual(coordinator.identity, identity)
        let expected = model.draft
        rule.wrappedValue = "stale rule"; story.wrappedValue = "stale scene"; hint.wrappedValue = "stale hint"
        XCTAssertEqual(model.draft, expected); XCTAssertEqual(coordinator.draft, expected)
        XCTAssertNil(expected.ruleInstructions); XCTAssertNil(expected.storyJson); XCTAssertNil(expected.hint1)
        XCTAssertNil(expected.storyTimelineEdited); XCTAssertNil(expected.legacyHintsEnabled)
    }
    func testEpochReplacementRejectsEveryRetainedEditorBeforeAndAfterReload() throws {
        var session: TemplateAuthoringSession? = try owner()
        let coordinator = TemplateAuthoringCoordinator(store: .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { session })
        coordinator.open(seed: seed()); let model = TemplateAuthoringModel(coordinator: coordinator); model.load()
        let editor = TemplateStoryEditor(model: model)
        let rule = model.ruleStep(try XCTUnwrap(model.ruleSteps.rows.first?.id))
        let story = editor.text(try XCTUnwrap(editor.beats.first?.id), \.text), hint = model.legacyHint(.hint1)
        let original = model.draft; session = try owner(2)
        rule.wrappedValue = "wrong owner"; story.wrappedValue = "wrong owner"; hint.wrappedValue = "wrong owner"
        XCTAssertEqual(model.draft, original)
        model.load(); let replacement = model.draft
        rule.wrappedValue = "stale rule"; story.wrappedValue = "stale scene"; hint.wrappedValue = "stale hint"
        XCTAssertEqual(model.draft, replacement); XCTAssertEqual(coordinator.draft, replacement)
        XCTAssertNil(replacement.ruleInstructions); XCTAssertNil(replacement.storyJson); XCTAssertNil(replacement.hint1)
    }
}

@MainActor final class TemplateBasicFieldClearTests: XCTestCase {
    private final class Owner {
        var session: TemplateAuthoringSession?
        init(_ session: TemplateAuthoringSession) { self.session = session }
    }
    private struct Fixture {
        let model: TemplateAuthoringModel
        let owner: Owner
        let storage: TemplateAuthoringMemoryStorage
        let clear: TemplateBasicFieldClearController
    }
    private func fixture(_ field: TemplateBasicClearField = .title, visible: Bool = true) throws -> Fixture {
        let owner = Owner(try .init(accountID: 995, namespace: "basic-clear", epoch: 1, authorizationRevision: "member"))
        let storage = TemplateAuthoringMemoryStorage()
        let model = TemplateAuthoringModel(coordinator: .init(store: .init(storage: storage), currentSession: { owner.session }))
        model.load(); model.draft.title = "  e\u{0301} title  "; model.draft.description = " Original 👩🏽‍💻 description "
        model.draft.ruleInstructions = "First\nSecond"; model.draft.questionAnswer = "Do not clear"
        model.draft.advanced.value["future"] = .object(["raw": .string("keep")]); model.changed()
        let clear = TemplateBasicFieldClearController(model: model, field: field)
        if visible { clear.appear(sceneIsActive: true) }
        return .init(model: model, owner: owner, storage: storage, clear: clear)
    }
    func testTitleClearChangesOnlyTitleAndKeepsRequiredValidation() throws {
        let f = try fixture(); var expected = f.model.draft; expected.title = ""
        XCTAssertTrue(f.clear.canClear); f.clear.clearAction()()
        XCTAssertEqual(f.model.draft, expected); XCTAssertEqual(f.model.coordinator.draft, expected)
        XCTAssertFalse(f.model.draft.canSave); XCTAssertTrue(f.model.draft.publishIssues.contains("templateAuthor.validation.title"))
        XCTAssertFalse(f.clear.canClear)
    }
    func testDescriptionClearChangesOnlyDescriptionAndKeepsRequiredValidation() throws {
        let f = try fixture(.description); var expected = f.model.draft; expected.description = ""
        f.clear.clearAction()()
        XCTAssertEqual(f.model.draft, expected); XCTAssertEqual(f.model.coordinator.draft, expected)
        XCTAssertTrue(f.model.draft.canSave); XCTAssertTrue(f.model.draft.publishIssues.contains("templateAuthor.validation.description"))
    }
    func testClearDoesNotSaveSubmitPrepareOrReserve() throws {
        let f = try fixture(.description); f.clear.clearAction()()
        XCTAssertTrue(f.storage.values.isEmpty); XCTAssertNil(f.model.review); XCTAssertNil(f.model.coordinator.review)
        XCTAssertNil(f.model.coordinator.pending); XCTAssertFalse(f.model.coordinator.canSubmit)
    }
    func testRetainedClearCannotClearNewTextAfterFirstUse() throws {
        let f = try fixture(), clear = f.clear.clearAction(); clear()
        f.model.draft.title = "New text"; f.model.changed(); clear()
        XCTAssertEqual(f.model.draft.title, "New text")
        f.clear.clearAction()(); XCTAssertEqual(f.model.draft.title, "")
    }
    func testTypingBeforeTapInvalidatesPreviouslyCapturedClear() throws {
        let f = try fixture(.description), clear = f.clear.clearAction()
        f.model.draft.description = "Replacement description"
        clear(); XCTAssertEqual(f.model.draft.description, "Replacement description")
        f.clear.clearAction()(); XCTAssertEqual(f.model.draft.description, "")
    }
    func testByteEqualDraftABAStillInvalidatesOldAction() throws {
        let f = try fixture(), original = f.model.draft, clear = f.clear.clearAction()
        f.model.draft.title = "Temporary"; f.model.draft = original
        clear(); XCTAssertEqual(f.model.draft, original)
        f.clear.clearAction()(); XCTAssertEqual(f.model.draft.title, "")
    }
    func testOldCallbackCannotClearReappearedControl() throws {
        let f = try fixture(), original = f.model.draft, clear = f.clear.clearAction()
        f.clear.disappear(); f.clear.appear(sceneIsActive: true)
        clear(); XCTAssertEqual(f.model.draft, original)
        f.clear.clearAction()(); XCTAssertEqual(f.model.draft.title, "")
    }
    func testHiddenForegroundAndFreshCallbackRemainDisabled() throws {
        let f = try fixture(), original = f.model.draft
        f.clear.disappear(); f.clear.sceneChanged(isActive: false); f.clear.sceneChanged(isActive: true)
        XCTAssertFalse(f.clear.canClear); f.clear.clearAction()(); XCTAssertEqual(f.model.draft, original)
    }
    func testBackgroundRetiresOldActionAndInactiveAppearDoesNotEnable() throws {
        let f = try fixture(), original = f.model.draft, clear = f.clear.clearAction()
        f.clear.sceneChanged(isActive: false); clear(); XCTAssertEqual(f.model.draft, original)
        f.clear.sceneChanged(isActive: true); clear(); XCTAssertEqual(f.model.draft, original)
        f.clear.disappear(); f.clear.appear(sceneIsActive: false)
        XCTAssertFalse(f.clear.canClear); f.clear.clearAction()(); XCTAssertEqual(f.model.draft, original)
    }
    func testRepeatedVisibleAppearDoesNotNeedAReplacementOwner() throws {
        let f = try fixture(), clear = f.clear.clearAction()
        f.clear.appear(sceneIsActive: true); f.clear.appear(sceneIsActive: true)
        clear(); XCTAssertEqual(f.model.draft.title, "")
    }
    func testAccountReplacementBeforeViewUpdateRejectsOldAndFreshCallbacks() throws {
        let f = try fixture(), original = f.model.draft, clear = f.clear.clearAction()
        f.owner.session = try .init(accountID: 996, namespace: "basic-clear", epoch: 2, authorizationRevision: "member")
        clear(); f.clear.clearAction()(); XCTAssertEqual(f.model.draft, original); XCTAssertFalse(f.clear.canClear)
    }
    func testLoadRestoreDiscardAndLeaveRetireCapturedActions() throws {
        for operation in ["load", "restore", "discard", "leave"] {
            let f = try fixture(), clear = f.clear.clearAction()
            switch operation {
            case "load": f.model.load()
            case "restore": f.model.restore()
            case "discard": f.model.discard()
            default: f.model.leave()
            }
            let expected = f.model.draft; clear(); XCTAssertEqual(f.model.draft, expected, operation)
        }
    }
    func testBusyAndReviewPreventClearAndCancelPreservesText() throws {
        let f = try fixture(), original = f.model.draft, clear = f.clear.clearAction()
        f.model.busy = true; clear(); f.clear.clearAction()(); XCTAssertEqual(f.model.draft, original)
        f.model.busy = false
        // Unknown configuration is preserved; use an otherwise valid current draft for review.
        f.model.draft.advanced.value.removeValue(forKey: "future"); f.model.changed()
        let beforeReview = f.model.draft; f.model.prepare(.saveDraft)
        XCTAssertNotNil(f.model.review); XCTAssertFalse(f.clear.canClear)
        f.clear.clearAction()(); XCTAssertEqual(f.model.draft, beforeReview)
        f.model.cancel(); XCTAssertEqual(f.model.draft, beforeReview)
    }
    func testEmptyClearIsANoopWithoutPublishingModelChanges() throws {
        let f = try fixture(.description); f.clear.clearAction()()
        let revision = f.model.revision; XCTAssertFalse(f.clear.canClear)
        f.clear.clearAction()(); XCTAssertEqual(f.model.revision, revision)
    }
    func testExplicitLocalSaveStillControlsPersistenceAfterClear() throws {
        let f = try fixture(.description); f.model.save()
        let saved = f.storage.values; f.clear.clearAction()()
        XCTAssertEqual(f.storage.values, saved)
        f.model.save(); XCTAssertNotEqual(f.storage.values, saved)
        let reopened = TemplateAuthoringModel(coordinator: .init(store: .init(storage: f.storage), currentSession: { f.owner.session }))
        reopened.load(); reopened.restore(); XCTAssertEqual(reopened.draft.description, "")
        XCTAssertEqual(Data(reopened.draft.title.utf8), Data(f.model.draft.title.utf8))
    }
    func testPendingWriteLockRejectsClear() throws {
        let f = try fixture(); f.model.draft.advanced.value.removeValue(forKey: "future"); f.model.changed()
        let seed = f.model.draft, session = try XCTUnwrap(f.owner.session), identity = TemplateAuthoringIdentity()
        let store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage())
        try store.save(seed, session: session, identity: identity)
        try store.savePending(.init(operationID: UUID(), ownerKey: session.ownerKey, identity: identity,
            request: TemplateAuthoringContract.request(seed, intent: .saveDraft), createdAt: Date()), session: session)
        let model = TemplateAuthoringModel(coordinator: .init(store: store, currentSession: { session })); model.load(); model.draft = seed
        let clear = TemplateBasicFieldClearController(model: model, field: .title); clear.appear(sceneIsActive: true)
        XCTAssertFalse(clear.canClear); clear.clearAction()(); XCTAssertEqual(model.draft, seed)
    }
}

@MainActor final class TemplateCoverReferenceClearTests: XCTestCase {
    private final class Owner {
        var session: TemplateAuthoringSession?
        init(_ session: TemplateAuthoringSession) { self.session = session }
    }
    private struct Fixture {
        let model: TemplateAuthoringModel
        let owner: Owner
        let storage: TemplateAuthoringMemoryStorage
        let clear: TemplateBasicFieldClearController
    }
    private func fixture(reference: String? = "https://cover.example/Original%20Cover.png?version=7", visible: Bool = true) throws -> Fixture {
        let owner = Owner(try .init(accountID: 997, namespace: "cover-clear", epoch: 1, authorizationRevision: "member"))
        let storage = TemplateAuthoringMemoryStorage()
        let model = TemplateAuthoringModel(coordinator: .init(store: .init(storage: storage), currentSession: { owner.session }))
        model.load(); model.draft.title = "Original title"; model.draft.description = "Original description"
        model.draft.imgUrl = reference; model.draft.questionImg = "fixture:question"
        model.draft.questionAudio = "fixture:question-audio"; model.draft.audioUrl = "fixture:narration"
        model.draft.medalImg = "fixture:medal"; model.draft.storyText = "Keep the story"
        model.draft.advanced.value["future"] = .object(["keep": .string(" e\u{0301} ")]); model.changed()
        let clear = TemplateBasicFieldClearController(model: model, field: .cover)
        if visible { clear.appear(sceneIsActive: true) }
        return .init(model: model, owner: owner, storage: storage, clear: clear)
    }
    func testExplicitCoverClearChangesOnlyOptionalCoverReference() throws {
        let f = try fixture(); var expected = f.model.draft; expected.imgUrl = nil
        XCTAssertTrue(f.clear.canClear); f.clear.clearAction()()
        XCTAssertEqual(TemplateSamplePreview.snapshot(f.model.draft), TemplateSamplePreview.snapshot(expected))
        XCTAssertEqual(f.model.coordinator.draft, expected); XCTAssertNil(f.model.draft.imgUrl)
        XCTAssertTrue(f.model.draft.canSave); XCTAssertFalse(f.clear.canClear)
    }
    func testNilAndEmptyReferencesAreNoOpsWithoutNormalizingDraft() throws {
        let references: [String?] = [nil, ""]
        for reference in references {
            let f = try fixture(reference: reference), original = TemplateSamplePreview.snapshot(f.model.draft), revision = f.model.revision
            XCTAssertFalse(f.clear.canClear); f.clear.clearAction()()
            XCTAssertEqual(TemplateSamplePreview.snapshot(f.model.draft), original); XCTAssertEqual(f.model.revision, revision)
        }
    }
    func testWhitespaceAndUnrecognizedReferencesRequireExplicitActionAndOnlyClearCover() throws {
        for reference in ["  ", "future:opaque:reference", "https://cover.example/%65%CC%81?raw=%2f"] {
            let f = try fixture(reference: reference); var expected = f.model.draft; expected.imgUrl = nil
            XCTAssertEqual(Array(try XCTUnwrap(f.model.draft.imgUrl).utf8), Array(reference.utf8))
            f.clear.clearAction()(); XCTAssertEqual(TemplateSamplePreview.snapshot(f.model.draft), TemplateSamplePreview.snapshot(expected))
        }
    }
    func testQueuedClearRejectsByteDifferentReplacementURL() throws {
        let f = try fixture(reference: "https://cover.example/e\u{0301}.png"), clear = f.clear.clearAction()
        let replacement = "https://cover.example/é.png"; f.model.draft.imgUrl = replacement
        clear(); XCTAssertEqual(Array(try XCTUnwrap(f.model.draft.imgUrl).utf8), Array(replacement.utf8))
        f.clear.clearAction()(); XCTAssertNil(f.model.draft.imgUrl)
    }
    func testURLABAPublicationCannotReuseOldClearAction() throws {
        let f = try fixture(), original = f.model.draft, clear = f.clear.clearAction()
        f.model.draft.imgUrl = "fixture:replacement"; f.model.draft = original
        clear(); XCTAssertEqual(TemplateSamplePreview.snapshot(f.model.draft), TemplateSamplePreview.snapshot(original))
    }
    func testOldClearCannotAffectHiddenReopenedOwner() throws {
        let f = try fixture(), original = f.model.draft, clear = f.clear.clearAction()
        f.clear.disappear(); f.clear.appear(sceneIsActive: true)
        clear(); XCTAssertEqual(f.model.draft, original)
        f.clear.clearAction()(); XCTAssertNil(f.model.draft.imgUrl)
    }
    func testHiddenForegroundCannotReactivateCoverAction() throws {
        let f = try fixture(), original = f.model.draft
        f.clear.disappear(); f.clear.sceneChanged(isActive: false); f.clear.sceneChanged(isActive: true)
        XCTAssertFalse(f.clear.canClear); f.clear.clearAction()(); XCTAssertEqual(f.model.draft, original)
    }
    func testInactiveAppearAndBackgroundInvalidateCapturedCoverAction() throws {
        let f = try fixture(), original = f.model.draft, clear = f.clear.clearAction()
        f.clear.sceneChanged(isActive: false); clear(); f.clear.sceneChanged(isActive: true); clear()
        XCTAssertEqual(f.model.draft, original)
        f.clear.disappear(); f.clear.appear(sceneIsActive: false); f.clear.clearAction()()
        XCTAssertFalse(f.clear.canClear); XCTAssertEqual(f.model.draft, original)
    }
    func testRepeatedVisibleAppearPreservesCurrentCoverAction() throws {
        let f = try fixture(), clear = f.clear.clearAction()
        f.clear.appear(sceneIsActive: true); f.clear.appear(sceneIsActive: true); clear()
        XCTAssertNil(f.model.draft.imgUrl)
    }
    func testAccountSwitchRejectsOldAndFreshActionsBeforeViewUpdate() throws {
        let f = try fixture(), original = f.model.draft, clear = f.clear.clearAction()
        f.owner.session = try .init(accountID: 998, namespace: "cover-clear", epoch: 2, authorizationRevision: "member")
        clear(); f.clear.clearAction()(); XCTAssertEqual(f.model.draft, original); XCTAssertFalse(f.clear.canClear)
    }
    func testSignOutRejectsPendingClearWithoutChangingURL() throws {
        let f = try fixture(), original = f.model.draft, clear = f.clear.clearAction()
        f.owner.session = nil; clear(); f.clear.clearAction()()
        XCTAssertEqual(f.model.draft, original)
    }
    func testClearDoesNotWriteSaveSubmitOrReserve() throws {
        let f = try fixture(); f.clear.clearAction()()
        XCTAssertTrue(f.storage.values.isEmpty); XCTAssertNil(f.model.review); XCTAssertNil(f.model.coordinator.review)
        XCTAssertNil(f.model.coordinator.pending); XCTAssertFalse(f.model.coordinator.canSubmit)
    }
    func testCancelReviewAndUncommittedReopenPreserveSavedOriginalURL() throws {
        let f = try fixture(); f.model.draft.advanced.value.removeValue(forKey: "future"); f.model.changed(); f.model.save()
        let original = try XCTUnwrap(f.model.draft.imgUrl), saved = f.storage.values
        f.model.prepare(.saveDraft); XCTAssertNotNil(f.model.review)
        f.clear.clearAction()(); XCTAssertEqual(f.model.draft.imgUrl, original)
        f.model.cancel(); XCTAssertEqual(f.model.draft.imgUrl, original)
        f.clear.clearAction()(); XCTAssertNil(f.model.draft.imgUrl); XCTAssertEqual(f.storage.values, saved)
        let reopened = TemplateAuthoringModel(coordinator: .init(store: .init(storage: f.storage), currentSession: { f.owner.session }))
        reopened.load(); reopened.restore(); XCTAssertEqual(Array(try XCTUnwrap(reopened.draft.imgUrl).utf8), Array(original.utf8))
    }
    func testOnlyExplicitParentSavePersistsClearedCover() throws {
        let f = try fixture(); f.model.save(); let originalBytes = f.storage.values
        f.clear.clearAction()(); XCTAssertEqual(f.storage.values, originalBytes)
        f.model.save(); XCTAssertNotEqual(f.storage.values, originalBytes)
        let reopened = TemplateAuthoringModel(coordinator: .init(store: .init(storage: f.storage), currentSession: { f.owner.session }))
        reopened.load(); reopened.restore(); XCTAssertNil(reopened.draft.imgUrl)
        XCTAssertEqual(reopened.draft.questionImg, "fixture:question"); XCTAssertEqual(reopened.draft.audioUrl, "fixture:narration")
    }
    func testOldLoadRestoreDiscardAndLeaveCallbacksCannotClearNewDraft() throws {
        for operation in ["load", "restore", "discard", "leave"] {
            let f = try fixture(), clear = f.clear.clearAction()
            switch operation {
            case "load": f.model.load()
            case "restore": f.model.restore()
            case "discard": f.model.discard()
            default: f.model.leave()
            }
            let current = TemplateSamplePreview.snapshot(f.model.draft); clear()
            XCTAssertEqual(TemplateSamplePreview.snapshot(f.model.draft), current, operation)
        }
    }
    func testOriginalBasicClearActionsAndLabelsKeepTheirOwnTargets() throws {
        let f = try fixture(), originalURL = f.model.draft.imgUrl
        let title = TemplateBasicFieldClearController(model: f.model, field: .title)
        title.appear(sceneIsActive: true); title.clearAction()()
        XCTAssertEqual(f.model.draft.imgUrl, originalURL); XCTAssertEqual(f.model.draft.description, "Original description")
        let description = TemplateBasicFieldClearController(model: f.model, field: .description)
        description.appear(sceneIsActive: true); description.clearAction()()
        XCTAssertEqual(f.model.draft.imgUrl, originalURL)
        XCTAssertEqual(TemplateBasicClearField.cover.label(Locale(identifier: "en")), "Clear cover reference")
        XCTAssertEqual(TemplateBasicClearField.cover.label(Locale(identifier: "zh-Hans")), "清空封面引用")
    }
}

@MainActor final class TemplateLocalMediaClearGroupTests: XCTestCase {
    private final class Owner {
        var session: TemplateAuthoringSession?
        init(_ session: TemplateAuthoringSession) { self.session = session }
    }
    private struct Fixture {
        let model: TemplateAuthoringModel
        let owner: Owner
        let storage: TemplateAuthoringMemoryStorage
        let clear: TemplateBasicFieldClearController
    }
    private let mediaJSON = #"{"A":{"img":"image-a","audio":"audio-a"},"B":{"img":"image-b","audio":"audio-b"},"C":{"img":"image-c","audio":"audio-c"},"D":{"img":"image-d","audio":"audio-d"}}"#
    private func fixture(_ field: TemplateBasicClearField, method: TemplateAuthoringMethod = .choice) throws -> Fixture {
        let owner = Owner(try .init(accountID: 999, namespace: "local-media-clear", epoch: 1, authorizationRevision: "member"))
        let storage = TemplateAuthoringMemoryStorage()
        let model = TemplateAuthoringModel(coordinator: .init(store: .init(storage: storage), currentSession: { owner.session }))
        model.load(); model.draft.title = "Media draft"; model.draft.description = "Keep description"
        model.draft.finishEnabled = true; model.draft.validationMethod = method
        model.draft.questionName = "Question"; model.draft.questionAnswer = "Answer"
        model.draft.questionA = "One"; model.draft.questionB = "Two"; model.draft.questionC = "Three"; model.draft.questionD = "Four"; model.draft.correctAnswer = "B"
        model.draft.imgUrl = "fixture:cover"; model.draft.questionImg = "https://image.example/e%CC%81.png"
        model.draft.questionAudio = "https://audio.example/question.m4a"; model.draft.audioUrl = "fixture:narration"
        model.draft.questionOptionMediaJson = mediaJSON; model.draft.storyText = "Keep story"
        model.draft.advanced.value["future"] = .object(["keep": .string(" e\u{0301} ")]); model.changed()
        let clear = TemplateBasicFieldClearController(model: model, field: field); clear.appear(sceneIsActive: true)
        return .init(model: model, owner: owner, storage: storage, clear: clear)
    }
    func testQuestionImageClearOnlyRemovesImageForBothNormalQAMethods() throws {
        for method in [TemplateAuthoringMethod.text, .choice] {
            let f = try fixture(.questionImage, method: method); var expected = f.model.draft; expected.questionImg = nil
            f.clear.clearAction()()
            XCTAssertEqual(TemplateSamplePreview.snapshot(f.model.draft), TemplateSamplePreview.snapshot(expected))
            XCTAssertEqual(f.model.coordinator.draft, expected); XCTAssertFalse(f.clear.canClear)
        }
    }
    func testQuestionAudioClearOnlyRemovesItsInertReference() throws {
        let f = try fixture(.questionAudio); var expected = f.model.draft; expected.questionAudio = nil
        f.clear.clearAction()()
        XCTAssertEqual(TemplateSamplePreview.snapshot(f.model.draft), TemplateSamplePreview.snapshot(expected))
        XCTAssertEqual(f.model.draft.audioUrl, "fixture:narration"); XCTAssertTrue(f.storage.values.isEmpty)
    }
    func testOptionPairClearsAtomicallyWithoutDeletingRowTextAnswerOrOtherMedia() throws {
        let f = try fixture(.optionMedia(.b)); var expected = f.model.draft
        try expected.setChoiceOptionMedia(.b, .image, to: ""); try expected.setChoiceOptionMedia(.b, .audio, to: "")
        let revision = f.model.revision; f.clear.clearAction()()
        XCTAssertEqual(TemplateSamplePreview.snapshot(f.model.draft), TemplateSamplePreview.snapshot(expected))
        XCTAssertNil(f.model.draft.choiceOptionMedia.text(.b, .image)); XCTAssertNil(f.model.draft.choiceOptionMedia.text(.b, .audio))
        XCTAssertEqual(f.model.draft.questionB, "Two"); XCTAssertEqual(f.model.draft.correctAnswer, "B")
        XCTAssertEqual(f.model.revision, revision + 1); XCTAssertEqual(f.model.coordinator.draft, expected)
    }
    func testEachOptionIdentityAddressesOnlyItsOwnPair() throws {
        for letter in TemplateChoiceOptionMedia.Letter.allCases {
            let f = try fixture(.optionMedia(letter)); f.clear.clearAction()()
            for other in TemplateChoiceOptionMedia.Letter.allCases {
                let original = TemplateChoiceOptionMedia(raw: mediaJSON)
                for kind in TemplateChoiceOptionMedia.Kind.allCases {
                    XCTAssertEqual(f.model.draft.choiceOptionMedia.text(other, kind), other == letter ? nil : original.text(other, kind))
                }
            }
            XCTAssertEqual(f.model.draft.correctAnswer, "B"); XCTAssertEqual(TemplateChoiceOptionRows(draft: f.model.draft).letters.count, 4)
        }
    }
    func testUnknownMalformedAndOutOfContractOptionJSONRemainsByteExact() throws {
        for raw in [#"{ "A": {"img":"keep", "future":"unknown"} }"#, #"{"future":{"img":"keep"}}"#, #"{"A":{"img":7}}"#, "[{}]", "{broken", #"{"A":{"img":""}}"#] {
            let f = try fixture(.optionMedia(.a)); f.model.draft.questionOptionMediaJson = raw
            let original = TemplateSamplePreview.snapshot(f.model.draft), revision = f.model.revision
            XCTAssertFalse(f.clear.canClear); f.clear.clearAction()()
            XCTAssertEqual(TemplateSamplePreview.snapshot(f.model.draft), original); XCTAssertEqual(f.model.revision, revision)
            XCTAssertEqual(Array(try XCTUnwrap(f.model.draft.questionOptionMediaJson).utf8), Array(raw.utf8))
        }
    }
    func testDuplicateAndEscapedAliasKeysAreRejectedBeforeProjectionCanCollapseThem() throws {
        for raw in [#"{"A":{"img":"first"},"A":{"audio":"second"}}"#, #"{"A":{"img":"first","img":"second"}}"#, #"{"A":{"img":"first"},"\u0041":{"audio":"second"}}"#, #"{"A":{"img":"first","\u0069mg":"second"}}"#] {
            let f = try fixture(.optionMedia(.a)); f.model.draft.questionOptionMediaJson = raw
            XCTAssertFalse(f.clear.canClear); f.clear.clearAction()()
            XCTAssertEqual(Array(try XCTUnwrap(f.model.draft.questionOptionMediaJson).utf8), Array(raw.utf8))
        }
    }
    func testUniqueKeysAllowWhitespaceEscapesAndOtherOptionReferencesWithoutReinterpretation() throws {
        let f = try fixture(.optionMedia(.a))
        f.model.draft.questionOptionMediaJson = #" { "A" : {"img":"remove","audio":"remove"}, "B":{"img":"keep \\ path \"img\": { untouched }","audio":"e\u0301"} } "#
        let image = f.model.draft.choiceOptionMedia.text(.b, .image), audio = f.model.draft.choiceOptionMedia.text(.b, .audio)
        XCTAssertTrue(f.clear.canClear); f.clear.clearAction()()
        XCTAssertEqual(f.model.draft.choiceOptionMedia.text(.b, .image).map { Array($0.utf8) }, image.map { Array($0.utf8) })
        XCTAssertEqual(f.model.draft.choiceOptionMedia.text(.b, .audio).map { Array($0.utf8) }, audio.map { Array($0.utf8) })
    }
    func testEmptyMissingAndAbsentRowDoNotRewriteOrPublish() throws {
        let fields: [TemplateBasicClearField] = [.questionImage, .questionAudio, .optionMedia(.d)]
        for field in fields {
            let f = try fixture(field); f.model.draft.questionImg = nil; f.model.draft.questionAudio = ""
            f.model.draft.questionC = nil; f.model.draft.questionD = nil; f.model.draft.questionOptionMediaJson = #"{ "A": {} }"#
            let original = TemplateSamplePreview.snapshot(f.model.draft), revision = f.model.revision
            XCTAssertFalse(f.clear.canClear); f.clear.clearAction()()
            XCTAssertEqual(TemplateSamplePreview.snapshot(f.model.draft), original); XCTAssertEqual(f.model.revision, revision)
        }
    }
    func testMethodAndModuleVisibilityGateEveryMediaClear() throws {
        for field in [TemplateBasicClearField.questionImage, .questionAudio, .optionMedia(.a)] {
            let f = try fixture(field), clear = f.clear.clearAction(), original = f.model.draft
            f.model.draft.validationMethod = .manual; XCTAssertFalse(f.clear.canClear); f.clear.clearAction()()
            f.model.draft = original; clear(); XCTAssertEqual(f.model.draft, original)
            f.model.draft.finishEnabled = false; XCTAssertFalse(f.clear.canClear); f.clear.clearAction()()
            XCTAssertEqual(f.model.draft.questionImg, original.questionImg); XCTAssertEqual(f.model.draft.questionOptionMediaJson, original.questionOptionMediaJson)
        }
    }
    func testByteDifferentReferenceReplacementRejectsCapturedQuestionClear() throws {
        let f = try fixture(.questionImage), clear = f.clear.clearAction()
        f.model.draft.questionImg = "https://image.example/é.png"
        let replacement = try XCTUnwrap(f.model.draft.questionImg); clear()
        XCTAssertEqual(Array(try XCTUnwrap(f.model.draft.questionImg).utf8), Array(replacement.utf8))
        f.clear.clearAction()(); XCTAssertNil(f.model.draft.questionImg)
    }
    func testOptionABAAndRowShiftCannotReuseOldClearAction() throws {
        let f = try fixture(.optionMedia(.b)), original = f.model.draft, clear = f.clear.clearAction()
        f.model.draft.questionB = "intermediate"; f.model.draft = original; clear()
        XCTAssertEqual(f.model.draft, original)
        let shiftedClear = f.clear.clearAction(), rows = TemplateChoiceOptionRowsEditor(model: f.model)
        rows.action(.remove(.a))(); let shifted = TemplateSamplePreview.snapshot(f.model.draft); shiftedClear()
        XCTAssertEqual(TemplateSamplePreview.snapshot(f.model.draft), shifted)
    }
    func testHiddenForegroundAndReopenNeverReviveOldActions() throws {
        for field in [TemplateBasicClearField.questionImage, .questionAudio, .optionMedia(.a)] {
            let f = try fixture(field), original = f.model.draft, clear = f.clear.clearAction()
            f.clear.disappear(); f.clear.sceneChanged(isActive: true); clear(); f.clear.clearAction()()
            XCTAssertFalse(f.clear.canClear); XCTAssertEqual(f.model.draft, original)
            f.clear.appear(sceneIsActive: true); clear(); XCTAssertEqual(f.model.draft, original)
            f.clear.clearAction()(); XCTAssertNotEqual(TemplateSamplePreview.snapshot(f.model.draft), TemplateSamplePreview.snapshot(original))
        }
    }
    func testRepeatedVisibleAppearDoesNotInvalidateCurrentAction() throws {
        let f = try fixture(.optionMedia(.c)), clear = f.clear.clearAction()
        f.clear.appear(sceneIsActive: true); f.clear.appear(sceneIsActive: true); clear()
        XCTAssertNil(f.model.draft.choiceOptionMedia.text(.c, .image)); XCTAssertNil(f.model.draft.choiceOptionMedia.text(.c, .audio))
    }
    func testSwitchedOwnerAndSignOutRejectBothOldAndFreshCallbacks() throws {
        for field in [TemplateBasicClearField.questionImage, .questionAudio, .optionMedia(.a)] {
            let f = try fixture(field), original = f.model.draft, clear = f.clear.clearAction()
            f.owner.session = try .init(accountID: 1000, namespace: "local-media-clear", epoch: 2, authorizationRevision: "member")
            clear(); f.clear.clearAction()(); XCTAssertEqual(f.model.draft, original)
            f.owner.session = nil; clear(); f.clear.clearAction()(); XCTAssertEqual(f.model.draft, original)
        }
    }
    func testClearingEachKindRetiresHeldMediaInspectionBeforeLateCompletion() throws {
        let cases: [(TemplateBasicClearField, TemplateAuthoringMediaField)] = [(.questionImage, .questionImage), (.questionAudio, .questionAudio), (.optionMedia(.a), .optionImage(.a))]
        for (field, target) in cases {
            let f = try fixture(field), media = TemplateMediaReviewController(model: f.model, fixtureMode: "generated"); media.reload()
            media.open(try XCTUnwrap(media.rows.first { $0.field == target })); media.beginSynthetic(try XCTUnwrap(media.review), held: true)
            let pending = try XCTUnwrap(media.review); f.clear.clearAction()(); let expected = TemplateSamplePreview.snapshot(f.model.draft)
            XCTAssertNil(media.review); XCTAssertNil(media.presentation(for: pending.id))
            media.completeSynthetic(pending); media.finish(pending)
            XCTAssertNil(media.review); XCTAssertEqual(TemplateSamplePreview.snapshot(f.model.draft), expected)
        }
    }
    func testOnlyExplicitParentSavePersistsClearsAndUncommittedReopenRestoresOldReferences() throws {
        let f = try fixture(.optionMedia(.a)); f.model.save(); let originalBytes = f.storage.values
        f.clear.clearAction()(); XCTAssertEqual(f.storage.values, originalBytes)
        let reopened = TemplateAuthoringModel(coordinator: .init(store: .init(storage: f.storage), currentSession: { f.owner.session }))
        reopened.load(); reopened.restore(); XCTAssertEqual(reopened.draft.questionOptionMediaJson, mediaJSON)
        f.model.save(); XCTAssertNotEqual(f.storage.values, originalBytes)
        let saved = TemplateAuthoringModel(coordinator: .init(store: .init(storage: f.storage), currentSession: { f.owner.session }))
        saved.load(); saved.restore(); XCTAssertNil(saved.draft.choiceOptionMedia.text(.a, .image)); XCTAssertNil(saved.draft.choiceOptionMedia.text(.a, .audio))
        XCTAssertEqual(saved.draft.questionA, "One"); XCTAssertEqual(saved.draft.correctAnswer, "B")
        XCTAssertNil(f.model.coordinator.pending); XCTAssertFalse(f.model.coordinator.canSubmit)
    }
    func testBusyAndCancelledReviewDoNotEnablePreviouslyCapturedClear() throws {
        let f = try fixture(.questionAudio, method: .text); f.model.draft.advanced.value.removeValue(forKey: "future"); f.model.changed()
        let clear = f.clear.clearAction(), original = f.model.draft
        f.model.busy = true; clear(); f.clear.clearAction()(); XCTAssertEqual(f.model.draft, original)
        f.model.busy = false; clear(); XCTAssertEqual(f.model.draft, original)
        f.model.prepare(.saveDraft); XCTAssertNotNil(f.model.review); f.clear.clearAction()(); XCTAssertEqual(f.model.draft, original)
        f.model.cancel(); clear(); XCTAssertEqual(f.model.draft, original); XCTAssertTrue(f.storage.values.isEmpty)
    }
    func testLocalMediaClearLabelsAndIdentifiersAreSpecificInBothLanguages() {
        XCTAssertEqual(TemplateBasicClearField.questionImage.rawValue, "questionImage")
        XCTAssertEqual(TemplateBasicClearField.questionAudio.rawValue, "questionAudio")
        XCTAssertEqual(TemplateBasicClearField.optionMedia(.d).rawValue, "optionMedia.D")
        XCTAssertEqual(TemplateBasicClearField.questionImage.label(Locale(identifier: "en")), "Clear question image reference")
        XCTAssertEqual(TemplateBasicClearField.questionAudio.label(Locale(identifier: "zh-Hans")), "清空题干音频引用")
        XCTAssertEqual(TemplateBasicClearField.optionMedia(.b).label(Locale(identifier: "en")), "Clear option B media references")
    }
}

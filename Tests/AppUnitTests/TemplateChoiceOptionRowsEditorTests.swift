import XCTest
@testable import Questify

@MainActor final class TemplateChoiceOptionRowsEditorTests: XCTestCase {
    private final class Owner {
        var session: TemplateAuthoringSession?
        init(_ session: TemplateAuthoringSession) { self.session = session }
    }
    private func setup(full: Bool = true, store: TemplateAuthoringLocalStore? = nil) throws -> (TemplateAuthoringModel, TemplateChoiceOptionRowsEditor, Owner) {
        let owner = Owner(try .init(accountID: 911, namespace: "choice-row-edit", epoch: 1, authorizationRevision: "member"))
        let model = TemplateAuthoringModel(coordinator: .init(store: store ?? .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { owner.session }))
        model.load(); model.draft.title = "Choice rows"; model.draft.finishEnabled = true; model.draft.validationMethod = .choice
        model.draft.questionA = "One"; model.draft.questionB = "Two"
        if full {
            model.draft.questionC = "Three"; model.draft.questionD = "Four"; model.draft.correctAnswer = "D"
            model.draft.questionOptionMediaJson = #"{"B":{"img":"remove"},"C":{"img":"third","audio":"third-audio"},"D":{"audio":"fourth-audio"}}"#
        }
        model.changed()
        return (model, .init(model: model), owner)
    }
    func testOpeningReloadingAndRetiringDoNotRewriteDraft() throws {
        let (model, editor, _) = try setup(), before = model.draft
        editor.reload(); editor.retire(); editor.reload()
        XCTAssertEqual(model.draft, before); XCTAssertEqual(model.coordinator.draft, before)
    }
    func testAddRemoveAndBlankRowCountPersistThroughFreshLocalRestore() throws {
        let store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage())
        let (model, editor, owner) = try setup(full: false, store: store)
        editor.action(.add)(); editor.action(.add)()
        XCTAssertEqual(editor.letters.count, 4); XCTAssertEqual(model.draft.questionD, "")
        editor.action(.remove(.c))(); XCTAssertEqual(editor.letters.count, 3)
        let expected = model.draft; model.save(); editor.retire(); model.leave()
        let reopened = TemplateAuthoringModel(coordinator: .init(store: store, currentSession: { owner.session }))
        reopened.load(); reopened.restore()
        XCTAssertEqual(reopened.draft, expected)
        XCTAssertEqual(TemplateChoiceOptionRows(draft: reopened.draft).letters.count, 3)
    }
    func testDeleteMovesAttachmentsAndAnswerThroughTheLocalCoordinator() throws {
        let (model, editor, _) = try setup()
        editor.action(.remove(.b))()
        XCTAssertEqual(model.draft.questionB, "Three"); XCTAssertEqual(model.draft.questionC, "Four")
        XCTAssertEqual(model.draft.choiceOptionMedia.text(.b, .image), "third")
        XCTAssertEqual(model.draft.choiceOptionMedia.text(.b, .audio), "third-audio")
        XCTAssertEqual(model.draft.correctAnswer, "C")
        XCTAssertEqual(model.coordinator.draft, model.draft); XCTAssertFalse(model.coordinator.canSubmit)
    }
    func testRetainedTextMediaAnswerAndDeleteCallbacksCannotTouchShiftedRows() throws {
        let (model, editor, _) = try setup()
        let text = editor.text(.b), image = editor.attachment(.b, .image), answer = editor.answer(), removal = editor.action(.remove(.b))
        removal(); let expected = model.draft
        text.wrappedValue = "stale"; image.wrappedValue = "stale"; answer.wrappedValue = "A"; removal()
        XCTAssertEqual(model.draft, expected)
        XCTAssertEqual(text.wrappedValue, ""); XCTAssertEqual(image.wrappedValue, "")
    }
    func testTextBindingAcceptsRepeatedTypingAndAnswerOnlyUsesVisibleLetters() throws {
        let (model, editor, _) = try setup(full: false), text = editor.text(.a)
        text.wrappedValue = "T"; text.wrappedValue = "Typed"
        XCTAssertEqual(model.draft.questionA, "Typed")
        editor.answer().wrappedValue = "D"; XCTAssertNil(model.draft.correctAnswer)
        editor.answer().wrappedValue = "B"; XCTAssertEqual(model.draft.correctAnswer, "B")
    }
    func testOldActionsRejectCommittedABAAndOwnerOrLifecycleReplacement() throws {
        let (model, editor, owner) = try setup(), action = editor.action(.remove(.b))
        let original = model.draft.questionB
        editor.text(.b).wrappedValue = "different"; editor.text(.b).wrappedValue = original ?? ""
        let before = model.draft; action(); XCTAssertEqual(model.draft, before)
        let ownerAction = editor.action(.remove(.b))
        owner.session = try .init(accountID: 911, namespace: "choice-row-edit", epoch: 2, authorizationRevision: "member")
        ownerAction(); XCTAssertEqual(model.draft, before)
    }
    func testReloadDiscardRestoreAndDismissalRetireBindingsAndActions() throws {
        for transition in ["load", "discard", "restore", "dismiss"] {
            let (model, editor, _) = try setup(), text = editor.text(.b), action = editor.action(.remove(.b))
            switch transition { case "load": model.load(); case "discard": model.discard(); case "restore": model.restore(); default: editor.retire() }
            let expected = model.draft; text.wrappedValue = "stale"; action()
            XCTAssertEqual(model.draft, expected, transition)
        }
    }
    func testPendingMediaInspectionCannotCompleteIntoShiftedOption() throws {
        let (model, editor, _) = try setup()
        let media = TemplateMediaReviewController(model: model, fixtureMode: "generated"); media.reload()
        media.open(try XCTUnwrap(media.rows.first { $0.field == .optionAudio(.c) }))
        media.beginSynthetic(try XCTUnwrap(media.review), held: true)
        let pending = try XCTUnwrap(media.review)
        editor.action(.remove(.b))(); let expected = model.draft
        XCTAssertNil(media.review); media.completeSynthetic(pending); media.finish(pending)
        XCTAssertNil(media.review); XCTAssertEqual(model.draft, expected)
    }
    func testUnsupportedMediaKeepsRawBytesWhileTextStillEdits() throws {
        let (model, editor, _) = try setup()
        let raw = #"{ "C": { "future": "keep" } }"#
        model.draft.questionOptionMediaJson = raw; model.changed()
        XCTAssertFalse(editor.rows.canAdd); XCTAssertFalse(editor.rows.canRemove)
        editor.action(.remove(.b))(); editor.text(.a).wrappedValue = "Safe text edit"
        XCTAssertEqual(model.draft.questionOptionMediaJson, raw); XCTAssertEqual(model.draft.questionA, "Safe text edit")
    }
    func testChangingCompletionMethodRejectsOldBindingsEvenAfterReturning() throws {
        let (model, editor, _) = try setup(), text = editor.text(.b), action = editor.action(.remove(.b))
        model.legacyHintMethodBinding().wrappedValue = .text
        model.legacyHintMethodBinding().wrappedValue = .choice
        let before = model.draft; text.wrappedValue = "stale"; action()
        XCTAssertEqual(model.draft, before)
        editor.reload(); editor.text(.b).wrappedValue = "Current"; XCTAssertEqual(model.draft.questionB, "Current")
    }
}

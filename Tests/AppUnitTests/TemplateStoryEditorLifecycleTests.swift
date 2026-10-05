import XCTest
@testable import Questify

/// Authored Apple app-unit checks; runtime execution requires Xcode.
@MainActor final class TemplateStoryEditorLifecycleTests: XCTestCase {
    private func session(_ epoch: UInt64 = 1) throws -> TemplateAuthoringSession {
        try .init(accountID: 907, namespace: "story-lifecycle", epoch: epoch, authorizationRevision: "member")
    }
    func testOpenAndRepeatedLoadLeaveSupportedHistoricalBytesUntouched() throws {
        let owner = try session(), store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage())
        let coordinator = TemplateAuthoringCoordinator(store: store, currentSession: { owner })
        let model = TemplateAuthoringModel(coordinator: coordinator); model.load()
        model.draft.storyJson = " [ {\"text\":\"  historical \", \"tag\":\"\", \"imgs\":[]} ]\n"
        model.draft.storyText = "independent summary"; model.changed()
        let before = model.draft, editor = TemplateStoryEditor(model: model)
        editor.load(); editor.load()
        XCTAssertTrue(editor.canEdit); XCTAssertEqual(model.draft, before)
        XCTAssertEqual(coordinator.draft, before)
        let binding = editor.text(try XCTUnwrap(editor.beats.first?.id), \.text)
        binding.wrappedValue = "  historical "
        XCTAssertEqual(model.draft, before)
    }
    func testExplicitEditCommitsBeforeParentReappearanceAndSurvivesRestore() throws {
        let owner = try session(), store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage())
        let coordinator = TemplateAuthoringCoordinator(store: store, currentSession: { owner })
        let model = TemplateAuthoringModel(coordinator: coordinator); model.load()
        model.draft.title = "Story"; model.draft.storyText = "keep"; model.changed()
        let editor = TemplateStoryEditor(model: model), id = try XCTUnwrap(editor.beats.first?.id)
        editor.text(id, \.text).wrappedValue = "  First scene  "
        XCTAssertEqual(try coordinator.draft.preparedStoryText(), "First scene")
        model.leave(); model.load(); model.save()
        let reopened = TemplateAuthoringCoordinator(store: store, currentSession: { owner }); reopened.open(); reopened.restoreDraft()
        XCTAssertEqual(reopened.draft.storyTimelineEdited, true); XCTAssertEqual(try reopened.draft.preparedStoryText(), "First scene")
        XCTAssertEqual(reopened.draft.storyText, "keep")
    }
    func testSevenImageEditIsRejectedWithNoticeAndNoDataLoss() throws {
        let owner = try session(), coordinator = TemplateAuthoringCoordinator(store: .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { owner })
        let model = TemplateAuthoringModel(coordinator: coordinator); model.load()
        let editor = TemplateStoryEditor(model: model), id = try XCTUnwrap(editor.beats.first?.id)
        editor.images(id).wrappedValue = "1\n2\n3\n4\n5\n6"
        let before = model.draft
        editor.images(id).wrappedValue = "1\n2\n3\n4\n5\n6\n7"
        XCTAssertEqual(editor.issueKey, "templateStory.imageLimit"); XCTAssertEqual(model.draft, before)
        XCTAssertEqual(editor.beats[0].imgs.count, 6)
    }
    func testUnknownStoryRemainsReadOnlyAndUntouched() throws {
        let owner = try session(), coordinator = TemplateAuthoringCoordinator(store: .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { owner })
        let model = TemplateAuthoringModel(coordinator: coordinator); model.load()
        model.draft.storyJson = #"[{"text":"x","tag":"t","imgs":[],"unknown":9007199254740993}]"#; model.changed()
        let before = model.draft, editor = TemplateStoryEditor(model: model)
        XCTAssertFalse(editor.canEdit); XCTAssertEqual(editor.issueKey, "templateStory.unsupported")
        editor.add(); XCTAssertEqual(model.draft, before)
    }
    func testStaleBindingCannotWriteAfterEpochChangeOrReload() throws {
        var owner: TemplateAuthoringSession? = try session()
        let coordinator = TemplateAuthoringCoordinator(store: .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { owner })
        let model = TemplateAuthoringModel(coordinator: coordinator); model.load()
        let editor = TemplateStoryEditor(model: model), id = try XCTUnwrap(editor.beats.first?.id), stale = editor.text(id, \.text)
        owner = try session(2); stale.wrappedValue = "old owner"
        XCTAssertNil(model.draft.storyJson)
        model.load(); editor.load(); stale.wrappedValue = "late callback"
        XCTAssertNil(model.draft.storyJson)
    }
    func testDiscardInvalidatesStaleBindingEvenWhenIdentityAndRawJSONAreUnchanged() throws {
        let owner = try session(), coordinator = TemplateAuthoringCoordinator(store: .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { owner })
        let model = TemplateAuthoringModel(coordinator: coordinator); model.load()
        let editor = TemplateStoryEditor(model: model), id = try XCTUnwrap(editor.beats.first?.id), stale = editor.text(id, \.text)
        let identity = coordinator.identity; model.discard()
        XCTAssertEqual(identity, coordinator.identity); XCTAssertNil(model.draft.storyJson)
        stale.wrappedValue = "late discarded input"
        XCTAssertNil(model.draft.storyJson); XCTAssertNil(model.draft.storyTimelineEdited)
    }
    func testReorderAndRemovalUpdateProjectionAndRetainLastEditorBeat() throws {
        let owner = try session(), coordinator = TemplateAuthoringCoordinator(store: .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { owner })
        let model = TemplateAuthoringModel(coordinator: coordinator); model.load()
        let editor = TemplateStoryEditor(model: model)
        editor.text(try XCTUnwrap(editor.beats.first?.id), \.text).wrappedValue = "First"
        editor.add(); editor.text(try XCTUnwrap(editor.beats.last?.id), \.text).wrappedValue = "Second"
        editor.move(IndexSet(integer: 1), to: 0)
        XCTAssertEqual(try model.draft.preparedStoryText(), "Second\nFirst")
        editor.remove(IndexSet(integer: 1)); editor.remove(IndexSet(integer: 0))
        XCTAssertEqual(editor.beats.count, 1); XCTAssertEqual(try model.draft.preparedStoryText(), "Second")
    }
}

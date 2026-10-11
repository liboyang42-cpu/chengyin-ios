import XCTest
@testable import Questify

@MainActor final class TemplateStoryImageRemovalLifecycleTests: XCTestCase {
    private func owner(_ epoch: UInt64 = 1) throws -> TemplateAuthoringSession {
        try .init(accountID: 907, namespace: "story-image-removal", epoch: epoch, authorizationRevision: "member")
    }
    private func model(_ session: @escaping () -> TemplateAuthoringSession?) -> TemplateAuthoringModel {
        let coordinator = TemplateAuthoringCoordinator(store: .init(storage: TemplateAuthoringMemoryStorage()), currentSession: session)
        let model = TemplateAuthoringModel(coordinator: coordinator); model.load()
        model.draft.title = "Image removal"
        model.draft.storyJson = #"[{"text":"keep","tag":"tag","imgs":["unknown://a","","unknown://a"]}]"#
        model.draft.storyText = "legacy summary"; model.changed()
        return model
    }
    func testRemovalTargetsDuplicateOccurrenceAndPersistsLocally() throws {
        let session = try owner(), model = model({ session }), editor = TemplateStoryEditor(model: model)
        let id = try XCTUnwrap(editor.beats.first?.id)
        let remove = editor.removeImageAction(id, at: 2)
        remove(); remove()
        XCTAssertEqual(editor.beats[0].imgs, ["unknown://a", ""])
        XCTAssertEqual(editor.beats[0].text, "keep"); XCTAssertEqual(editor.beats[0].tag, "tag")
        XCTAssertEqual(model.draft.storyText, "legacy summary")
        XCTAssertEqual(model.coordinator.draft, model.draft)
        let expected = model.draft.storyJson
        model.save(); model.leave(); model.load(); model.coordinator.restoreDraft()
        XCTAssertEqual(model.coordinator.draft.storyJson, expected)
    }
    func testOpeningPreparingThenCancellingMakesNoChangesAndDismissalRetiresCallback() throws {
        let session = try owner(), model = model({ session }), before = model.draft
        let editor = TemplateStoryEditor(model: model), id = try XCTUnwrap(editor.beats.first?.id)
        let cancelled = editor.removeImageAction(id, at: 0)
        XCTAssertEqual(model.draft, before)
        editor.retire(); cancelled()
        XCTAssertEqual(model.draft, before)
    }
    func testOldActionCannotDeleteAfterReloadOrArrayEdit() throws {
        let session = try owner(), model = model({ session }), editor = TemplateStoryEditor(model: model)
        let id = try XCTUnwrap(editor.beats.first?.id), old = editor.removeImageAction(id, at: 0)
        editor.images(id).wrappedValue = "replacement\nsecond"
        let before = model.draft; old(); XCTAssertEqual(model.draft, before)
        let next = editor.removeImageAction(id, at: 0)
        editor.load(); next(); XCTAssertEqual(model.draft, before)
    }
    func testIdentityChangeAndDiscardRejectLateActions() throws {
        var session: TemplateAuthoringSession? = try owner()
        let model = model({ session }), editor = TemplateStoryEditor(model: model)
        let action = editor.removeImageAction(try XCTUnwrap(editor.beats.first?.id), at: 0)
        let before = model.draft; session = try owner(2); action()
        XCTAssertEqual(model.draft, before)
        model.load(); editor.load()
        let discarded = editor.removeImageAction(try XCTUnwrap(editor.beats.first?.id), at: 0)
        model.discard(); let afterDiscard = model.draft; discarded()
        XCTAssertEqual(model.draft, afterDiscard)
    }
    func testInvalidIndexUnknownTimelineAndMissingBeatStayUntouched() throws {
        let session = try owner(), model = model({ session }), editor = TemplateStoryEditor(model: model)
        let before = model.draft, id = try XCTUnwrap(editor.beats.first?.id)
        editor.removeImageAction(id, at: -1)(); editor.removeImageAction(id, at: 3)()
        editor.removeImageAction(UUID(), at: 0)(); XCTAssertEqual(model.draft, before)
        model.draft.storyJson = #"[{"text":"keep","tag":"tag","imgs":["a"],"unknown":true}]"#
        model.changed(); editor.load(); let unknown = model.draft
        editor.removeImageAction(id, at: 0)(); XCTAssertEqual(model.draft, unknown)
    }
    func testFinalEmptyReferenceAndOversizedHistoryCanBeReduced() throws {
        let session = try owner(), model = model({ session })
        model.draft.storyJson = #"[{"text":"keep","tag":"tag","imgs":[""]}]"#; model.changed()
        let editor = TemplateStoryEditor(model: model)
        editor.removeImageAction(try XCTUnwrap(editor.beats.first?.id), at: 0)()
        XCTAssertEqual(editor.beats[0].imgs, [])
        model.draft.storyJson = #"[{"text":"keep","tag":"tag","imgs":["0","1","2","3","4","5","6","7"]}]"#; model.changed(); editor.load()
        editor.removeImageAction(try XCTUnwrap(editor.beats.first?.id), at: 3)()
        XCTAssertEqual(editor.beats[0].imgs, ["0", "1", "2", "4", "5", "6", "7"])
        XCTAssertNil(editor.issueKey)
    }
}

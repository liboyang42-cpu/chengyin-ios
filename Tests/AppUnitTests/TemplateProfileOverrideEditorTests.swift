import XCTest
@testable import Questify

@MainActor final class TemplateProfileOverrideEditorTests: XCTestCase {
    private final class Owner { var session: TemplateAuthoringSession?; init(_ value: TemplateAuthoringSession) { session = value } }
    private func setup() throws -> (TemplateAuthoringModel, TemplateProfileOverrideController, Owner, TemplateAuthoringLocalStore, TemplateAuthoringMemoryStorage) {
        let owner = Owner(try .init(accountID: 999, namespace: "profile-override", epoch: 1, authorizationRevision: "member"))
        let storage = TemplateAuthoringMemoryStorage(), store = TemplateAuthoringLocalStore(storage: storage)
        let model = TemplateAuthoringModel(coordinator: .init(store: store, currentSession: { owner.session })); model.load(); model.draft.title = "Profile override"
        model.draft.advanced.set("profile", "enabled", .bool(true))
        let options: [TemplateAuthoringJSON] = [.object(["key": .string("A"), "label": .string("旅人"), "effects": .array([])]), .object(["key": .string("B"), "label": .string("守门人"), "effects": .array([])])]
        model.draft.advanced.set("profile", "questions", .array([
            .object(["key": .string("role"), "kind": .string("pick"), "label": .string("想当什么？"), "required": .bool(true), "options": .array(options)]),
            .object(["key": .string("name"), "kind": .string("text"), "label": .string("名字"), "maxLength": .number(12), "required": .bool(true)])
        ])); model.changed()
        let c = TemplateProfileOverrideController(model: model, questionKey: "role"); c.reload(); return (model, c, owner, store, storage)
    }
    private func override(_ model: TemplateAuthoringModel) -> [String: TemplateAuthoringJSON]? { model.draft.advanced.rows("profile", "questions").first?.object?["override"]?.object }
    private func stage(_ c: TemplateProfileOverrideController) { c.enabledBinding().wrappedValue = true; c.textBinding(.variable).wrappedValue = "counter.focus"; c.textBinding(.threshold).wrappedValue = "5"; c.textBinding(.option).wrappedValue = "B"; c.textBinding(.voice).wrappedValue = "你想当{picked}，表格写的是{assigned}。" }
    func testOpeningAndEditingStageNeverWriteDraftOrStorage() throws {
        let (model,c,_,_,storage) = try setup(), before = model.draft; c.reload(); stage(c)
        XCTAssertEqual(model.draft,before); XCTAssertEqual(model.coordinator.draft,before); XCTAssertTrue(storage.values.isEmpty); XCTAssertTrue(c.canApply); XCTAssertEqual(c.messageKey,"templateProfileOverride.staged")
    }
    func testApplyCommitsWholeGroupedFormToSelectedQuestionOnly() throws {
        let (model,c,_,_,storage) = try setup(), before = model.draft.advanced.rows("profile","questions"); stage(c); c.applyAction()()
        let value = try XCTUnwrap(override(model)); XCTAssertEqual(value["option"],.string("B")); XCTAssertEqual(value["voice"],.string("你想当{picked}，表格写的是{assigned}。")); XCTAssertEqual(value["requires"]?.array?.first?.object?["value"],.number(5))
        let rows = model.draft.advanced.rows("profile","questions"); XCTAssertEqual(rows[1],before[1]); var original = try XCTUnwrap(before[0].object), after = try XCTUnwrap(rows[0].object); original.removeValue(forKey:"override"); after.removeValue(forKey:"override"); XCTAssertEqual(after,original)
        XCTAssertEqual(model.coordinator.draft,model.draft); XCTAssertTrue(storage.values.isEmpty); XCTAssertEqual(c.messageKey,"templateProfileOverride.applied"); XCTAssertFalse(c.canApply)
    }
    func testInvalidStageBlocksApplyAndSaveWithoutCorruptingDraft() throws {
        let (model,c,_,_,storage) = try setup(), before = model.draft; stage(c); c.textBinding(.threshold).wrappedValue = "1.5"
        XCTAssertTrue(c.issues.contains("templateProfileOverride.thresholdInvalid")); XCTAssertFalse(c.canApply); XCTAssertFalse(c.canSave); c.applyAction()(); c.saveAction()(); XCTAssertEqual(model.draft,before); XCTAssertTrue(storage.values.isEmpty)
    }
    func testDisableApplyKeepsSessionValuesForReenableButReloadDropsInactiveCache() throws {
        let (model,c,_,_,_) = try setup(); stage(c); c.applyAction()(); c.enabledBinding().wrappedValue = false; c.applyAction()()
        XCTAssertNil(override(model)); XCTAssertEqual(c.form?.option,"B"); XCTAssertEqual(c.form?.threshold,"5"); XCTAssertFalse(c.form?.enabled ?? true)
        c.enabledBinding().wrappedValue = true; c.applyAction()(); XCTAssertEqual(override(model)?["option"],.string("B"))
        c.enabledBinding().wrappedValue = false; c.applyAction()(); c.reload(); XCTAssertEqual(c.form?.option,"A"); XCTAssertEqual(c.form?.threshold,"4"); XCTAssertNil(override(model))
    }
    func testSaveAppliesStagedFormAndRoundTripsOwnerScopedExistingStore() throws {
        let (model,c,owner,store,_) = try setup(); stage(c); c.saveAction()(); let session = try XCTUnwrap(owner.session)
        guard case .ready(let saved) = store.load(session:session,identity:model.coordinator.identity) else { return XCTFail("Expected local draft") }
        XCTAssertEqual(saved.draft,model.draft); XCTAssertEqual(override(model)?["option"],.string("B")); XCTAssertEqual(c.messageKey,"templateAuthor.localSaved"); XCTAssertNil(model.review)
    }
    func testStorageFailureRetainsAppliedDraftAndExplicitRetrySucceeds() throws {
        let (model,c,_,_,storage) = try setup(); stage(c); storage.failWrites = true; c.saveAction()()
        XCTAssertEqual(c.messageKey,"templateAuthor.storageFailed"); XCTAssertTrue(storage.values.isEmpty); XCTAssertEqual(override(model)?["option"],.string("B")); XCTAssertTrue(c.canSave)
        storage.failWrites = false; c.saveAction()(); XCTAssertEqual(c.messageKey,"templateAuthor.localSaved"); XCTAssertFalse(storage.values.isEmpty)
    }
    func testEarlierFieldApplySaveAndCloseCallbacksCannotOverrideNewStage() throws {
        let (model,c,_,_,storage) = try setup(); c.enabledBinding().wrappedValue = true
        let oldField = c.textBinding(.option), oldApply = c.applyAction(), oldSave = c.saveAction(); var closes = 0; let oldClose = c.closeAction { closes += 1 }
        c.textBinding(.option).wrappedValue = "B"; oldField.wrappedValue = "A"; oldApply(); oldSave(); oldClose()
        XCTAssertEqual(c.form?.option,"B"); XCTAssertNil(override(model)); XCTAssertTrue(storage.values.isEmpty); XCTAssertEqual(closes,0)
    }
    func testApplyRetiresEarlierSaveAndRepeatedApplyCallbacks() throws {
        let (model,c,_,_,storage) = try setup(); stage(c); let apply = c.applyAction(), save = c.saveAction(); apply(); let revision = model.revision; apply(); save()
        XCTAssertEqual(model.revision,revision); XCTAssertTrue(storage.values.isEmpty); XCTAssertEqual(override(model)?["option"],.string("B"))
    }
    func testExternalDraftEditDiscardsStageAndReloadReadsLatestWithoutOverwrite() throws {
        let (model,c,_,_,storage) = try setup(); stage(c); let apply = c.applyAction(), save = c.saveAction()
        model.draft.title = "Newer"; let before = model.draft; apply(); save(); XCTAssertNil(c.visibleConfiguration); XCTAssertNil(c.form); XCTAssertEqual(model.draft,before); XCTAssertTrue(storage.values.isEmpty)
        c.reload(); XCTAssertFalse(c.form?.enabled ?? true); XCTAssertEqual(model.draft.title,"Newer")
    }
    func testWholeDraftABARejectsEarlierActionAfterReload() throws {
        let (model,c,_,_,_) = try setup(), before = model.draft; stage(c); let apply = c.applyAction()
        model.draft.title = "Changed"; model.draft = before; c.reload(); apply(); XCTAssertEqual(model.draft,before); XCTAssertFalse(c.form?.enabled ?? true)
    }
    func testQuestionReorderKindChangeAndOptionRemovalRejectOldActions() throws {
        for change in ["reorder","kind","option","delete"] {
            let (model,c,_,_,_) = try setup(); stage(c); let apply = c.applyAction(); var rows = model.draft.advanced.rows("profile","questions")
            if change == "reorder" { rows.reverse() } else if change == "delete" { rows.removeFirst() } else {
                var row = rows[0].object!; if change == "kind" { row["kind"] = .string("text") } else { row["options"] = .array([row["options"]!.array![0]]) }; rows[0] = .object(row)
            }
            model.draft.advanced.set("profile","questions",.array(rows)); let before = model.draft; apply(); XCTAssertEqual(model.draft,before,change); XCTAssertNil(c.visibleConfiguration,change)
        }
    }
    func testOwnerSwitchBlocksStagingApplyAndSave() throws {
        let (model,c,owner,_,storage) = try setup(); stage(c); let field = c.textBinding(.voice), apply = c.applyAction(), save = c.saveAction(), before = model.draft
        owner.session = try .init(accountID:1000,namespace:"profile-override",epoch:2,authorizationRevision:"member"); field.wrappedValue = "Wrong owner"; apply(); save()
        XCTAssertNil(c.visibleConfiguration); XCTAssertEqual(model.draft,before); XCTAssertTrue(storage.values.isEmpty)
    }
    func testBusyReviewLoadLeaveAndExternalChangedRetireForm() throws {
        for operation in ["busy","review","load","leave","changed"] {
            let (model,c,_,_,_) = try setup(); stage(c); let apply = c.applyAction()
            switch operation { case "busy": model.busy = true; case "review": model.prepare(.saveDraft); case "load": model.load(); case "leave": model.leave(); default: model.changed() }
            let before = model.draft; apply(); XCTAssertEqual(model.draft,before,operation); XCTAssertNil(c.visibleConfiguration,operation)
        }
    }
    func testBackgroundReentryDiscardsUnappliedStageButKeepsAppliedDraft() throws {
        let (model,c,_,_,storage) = try setup(); stage(c); let oldApply = c.applyAction(), oldSave = c.saveAction(); c.retire(); c.reload(); oldApply(); oldSave(); XCTAssertNil(override(model)); XCTAssertFalse(c.form?.enabled ?? true)
        stage(c); c.applyAction()(); let applied = model.draft; c.textBinding(.voice).wrappedValue = "Unapplied"; c.retire(); c.reload(); XCTAssertEqual(model.draft,applied); XCTAssertNotEqual(c.form?.voice,"Unapplied"); XCTAssertTrue(storage.values.isEmpty)
    }
    func testCloseDiscardsOnlyStageAndOldCloseCannotDismissNewEntry() throws {
        let (model,c,_,_,_) = try setup(); stage(c); var closes = 0; let close = c.closeAction { closes += 1 }; close(); XCTAssertNil(c.form); XCTAssertNil(override(model)); c.reload(); close(); XCTAssertEqual(closes,1)
        stage(c); c.applyAction()(); let before = model.draft; c.closeAction { closes += 1 }(); XCTAssertEqual(model.draft,before); XCTAssertEqual(closes,2)
    }
    func testComplexManualOverrideRemainsReadOnlyAndCannotBeDeletedOrSaved() throws {
        let (model,c,_,_,storage) = try setup(); var rows = model.draft.advanced.rows("profile","questions"), row = rows[0].object!
        row["override"] = .object(["requires":.array([.object(["op":.string("EQ"),"var":.string("counter.focus"),"value":.number(2)])]),"option":.string("A")]); rows[0] = .object(row); model.draft.advanced.set("profile","questions",.array(rows)); c.reload(); let before = model.draft
        XCTAssertFalse(c.canEditForm); c.enabledBinding().wrappedValue = false; c.applyAction()(); c.saveAction()(); XCTAssertEqual(model.draft,before); XCTAssertTrue(storage.values.isEmpty)
    }
}

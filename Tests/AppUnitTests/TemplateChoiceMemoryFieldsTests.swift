import XCTest
@testable import Questify

@MainActor final class TemplateChoiceMemoryFieldsTests: XCTestCase {
    private final class Owner { var session: TemplateAuthoringSession?; init(_ value: TemplateAuthoringSession) { session = value } }
    private let qaPath: [TemplateCreatorPath] = [.field("options"), .index(0)]
    private let profilePath: [TemplateCreatorPath] = [.field("questions"), .index(0), .field("options"), .index(0)]
    private func setup(_ family: TemplateCreatorFamily = .qa, store: TemplateAuthoringLocalStore? = nil) throws -> (TemplateAuthoringModel, TemplateChoiceMemoryController, Owner) {
        let owner = Owner(try .init(accountID: 981, namespace: "choice-memory", epoch: 1, authorizationRevision: "member"))
        let model = TemplateAuthoringModel(coordinator: .init(store: store ?? .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { owner.session }))
        model.load(); model.draft.title = "Choice memory"; model.draft.advanced.setCreatorEnabled(family, true)
        let identityKey = family == .qa ? "id" : "key"
        let options: [TemplateAuthoringJSON] = [.object([identityKey: .string("A"), "label": .string("One"), "effects": .array([])]), .object([identityKey: .string("B"), "label": .string("Two"), "effects": .array([])])]
        if family == .qa {
            model.draft.advanced.set("qa", "mode", .string("PICK")); model.draft.advanced.set("qa", "title", .string("Choose")); model.draft.advanced.set("qa", "options", .array(options))
            model.draft.advanced.setCreatorValue(.qa, path: qaPath + [.field("correct")], entry: .bool(true))
        } else {
            model.draft.advanced.setCreatorValue(.profile, path: [.field("questions"), .index(0), .field("kind")], entry: .string("pick"))
            model.draft.advanced.setCreatorValue(.profile, path: [.field("questions"), .index(0), .field("label")], entry: .string("Role"))
            model.draft.advanced.setCreatorValue(.profile, path: [.field("questions"), .index(0), .field("options")], entry: .array(options))
        }
        model.changed(); return (model, .init(model: model, family: family, optionPath: family == .qa ? qaPath : profilePath), owner)
    }
    func testCompleteOnReadbackOffAndReenableInBothOptionContexts() throws {
        for family in [TemplateCreatorFamily.qa, .profile] {
            let (model, editor, _) = try setup(family); let original = model.draft
            editor.enabledInput().wrappedValue = true; let tag = try XCTUnwrap(editor.tags.first)
            XCTAssertTrue(editor.isEnabled); XCTAssertEqual(editor.tags.count, 1); XCTAssertEqual(model.coordinator.draft, model.draft)
            editor.enabledInput().wrappedValue = false; XCTAssertFalse(editor.isEnabled); XCTAssertEqual(model.draft, original)
            editor.enabledInput().wrappedValue = true; XCTAssertEqual(editor.tags.count, 1)
            // The generated tag is intentionally opaque; existing storage carries the exact current value.
            XCTAssertTrue(tag.hasPrefix("tag.m_")); XCTAssertTrue(editor.canChange)
        }
    }
    func testOldButtonsAndBindingCannotUndoANewerMemoryWrite() throws {
        let (model, editor, _) = try setup(); let oldOff = editor.setAction(false), oldInput = editor.enabledInput()
        editor.setAction(true)(); let before = model.draft
        oldOff(); oldInput.wrappedValue = false; XCTAssertEqual(model.draft, before); XCTAssertTrue(editor.isEnabled)
    }
    func testParentReviewRefreshKeepsCurrentMemoryButRetiresOldButtons() throws {
        let (model, editor, _) = try setup(); editor.setAction(true)(); let off = editor.setAction(false), tags = editor.tags
        model.changed(); XCTAssertFalse(editor.needsReopen); XCTAssertEqual(editor.tags, tags)
        off(); XCTAssertTrue(editor.isEnabled); editor.setAction(false)(); XCTAssertFalse(editor.isEnabled)
    }
    func testExternalSelectedEffectsRefreshReadbackButOldActionIsRejected() throws {
        let (model, editor, _) = try setup(); let oldOn = editor.setAction(true)
        model.draft.advanced.setCreatorValue(.qa, path: qaPath + [.field("effects")], entry: .array([.object(["op": .string("ADD_TAG"), "var": .string(""), "value": .string("tag.m_aaaaaa")])]))
        let before = model.draft; oldOn(); XCTAssertEqual(model.draft, before); XCTAssertEqual(editor.tags, ["tag.m_aaaaaa"]); XCTAssertFalse(editor.needsReopen)
        editor.setAction(false)(); XCTAssertFalse(editor.isEnabled)
    }
    func testOptionRenameAndReorderCannotRetargetOldController() throws {
        for change in ["rename", "reorder"] {
            let (model, editor, _) = try setup(); let on = editor.setAction(true)
            if change == "rename" { model.draft.advanced.setCreatorValue(.qa, path: qaPath + [.field("label")], entry: .string("Other")) }
            else { let rows = model.draft.advanced.value["qa"]?.object?["options"]?.array ?? []; model.draft.advanced.set("qa", "options", .array(Array(rows.reversed()))) }
            let before = model.draft; on(); editor.setAction(true)(); XCTAssertEqual(model.draft, before); XCTAssertTrue(editor.needsReopen)
            let fresh = TemplateChoiceMemoryController(model: model, family: .qa, optionPath: qaPath); fresh.setAction(true)(); XCTAssertTrue(fresh.isEnabled)
        }
    }
    func testSameValueABACannotReviveCapturedToggle() throws {
        let (model, editor, _) = try setup(); let input = editor.enabledInput(), before = model.draft
        model.draft.advanced.setCreatorValue(.qa, path: qaPath + [.field("label")], entry: .string("Other")); model.draft = before
        input.wrappedValue = true; XCTAssertEqual(model.draft, before); editor.enabledInput().wrappedValue = true; XCTAssertTrue(editor.isEnabled)
    }
    func testFullEffectCapacityDisablesOnWhileKeepingEffects() throws {
        let (model, _, _) = try setup(); let rows: [TemplateAuthoringJSON] = (0..<16).map { .object(["op": .string("INC"), "var": .string("counter.energy"), "value": .number(Double($0))]) }
        model.draft.advanced.setCreatorValue(.qa, path: qaPath + [.field("effects")], entry: .array(rows)); let before = model.draft
        let editor = TemplateChoiceMemoryController(model: model, family: .qa, optionPath: qaPath)
        XCTAssertFalse(editor.canEnable); XCTAssertFalse(editor.canChange); XCTAssertEqual(editor.otherEffectCount, 16); editor.setAction(true)(); XCTAssertEqual(model.draft, before)
    }
    func testModeSwitchAndUnsupportedEffectsDenyNewWrites() throws {
        let (model, editor, _) = try setup(); model.draft.advanced.set("qa", "mode", .string("TYPE")); let before = model.draft
        editor.setAction(true)(); XCTAssertEqual(model.draft, before); XCTAssertFalse(editor.canEdit)
        model.draft.advanced.set("qa", "mode", .string("PICK")); model.draft.advanced.setCreatorValue(.qa, path: qaPath + [.field("effects")], entry: .string("legacy"))
        let invalid = model.draft, fresh = TemplateChoiceMemoryController(model: model, family: .qa, optionPath: qaPath); fresh.setAction(true)(); XCTAssertFalse(fresh.canEdit); XCTAssertEqual(model.draft, invalid)
    }
    func testLoadRestoreDiscardOwnerLeaveAndDismissRejectRetainedControls() throws {
        for operation in ["load", "restore", "discard", "owner", "leave", "dismiss"] {
            let (model, editor, owner) = try setup(); let on = editor.setAction(true), input = editor.enabledInput()
            switch operation {
            case "load": model.load()
            case "restore": model.restore()
            case "discard": model.discard()
            case "owner": owner.session = try .init(accountID: 982, namespace: "choice-memory", epoch: 2, authorizationRevision: "member")
            case "leave": model.leave()
            default: editor.retire()
            }
            let before = model.draft; on(); input.wrappedValue = true; XCTAssertEqual(model.draft, before, operation)
        }
    }
    func testReappearanceDoesNotRestoreOldActionsOrRotateStoredTag() throws {
        let (model, editor, _) = try setup(); editor.setAction(true)(); let tag = editor.tags, off = editor.setAction(false), before = model.draft
        editor.retire(); editor.activate(); off(); XCTAssertEqual(model.draft, before); XCTAssertEqual(editor.tags, tag)
        editor.setAction(false)(); XCTAssertFalse(editor.isEnabled)
    }
    func testLocalSaveRestoreRetainsConfigurationWithoutRunningPlayerEffects() throws {
        let store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage()), (model, editor, owner) = try setup(store: store)
        editor.setAction(true)(); let expected = model.draft, tags = editor.tags; model.save(); editor.retire(); model.leave()
        let reopened = TemplateAuthoringModel(coordinator: .init(store: store, currentSession: { owner.session })); reopened.load(); reopened.restore()
        let fresh = TemplateChoiceMemoryController(model: reopened, family: .qa, optionPath: qaPath)
        XCTAssertEqual(reopened.draft, expected); XCTAssertEqual(fresh.tags, tags); XCTAssertTrue(fresh.isEnabled); XCTAssertFalse(reopened.coordinator.canSubmit)
    }
    func testPendingLockDeniesMemoryWrites() throws {
        let (seedModel, _, owner) = try setup(), session = try XCTUnwrap(owner.session)
        let store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage()), identity = TemplateAuthoringIdentity(), seed = seedModel.draft
        try store.save(seed, session: session, identity: identity)
        try store.savePending(.init(operationID: UUID(), ownerKey: session.ownerKey, identity: identity, request: TemplateAuthoringContract.request(seed, intent: .saveDraft), createdAt: Date()), session: session)
        let model = TemplateAuthoringModel(coordinator: .init(store: store, currentSession: { session })); model.load(); model.draft = seed
        let editor = TemplateChoiceMemoryController(model: model, family: .qa, optionPath: qaPath); editor.setAction(true)(); XCTAssertFalse(editor.canEdit); XCTAssertEqual(model.draft, seed)
    }
}

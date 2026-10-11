import XCTest
@testable import Questify

@MainActor final class TemplateProfileQuestionControllerTests: XCTestCase {
    private final class Owner { var session: TemplateAuthoringSession?; init(_ value: TemplateAuthoringSession) { session = value } }
    private func setup(store: TemplateAuthoringLocalStore? = nil) throws -> (TemplateAuthoringModel, Owner) {
        let owner = Owner(try .init(accountID: 952, namespace: "profile-questions", epoch: 1, authorizationRevision: "member"))
        let model = TemplateAuthoringModel(coordinator: .init(store: store ?? .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { owner.session }))
        model.load(); model.draft.title = "Question composition"; model.draft.advanced.setCreatorEnabled(.profile, true)
        model.draft.advanced.setCreatorValue(.profile, path: [.field("questions"), .index(0), .field("label")], entry: .string("Your name")); model.changed(); return (model, owner)
    }
    func testAddQuestionsSwitchKindsAndAllocateDistinctChoicesEndToEnd() throws {
        let (model, _) = try setup(), root = TemplateProfileQuestionController(model: model)
        let first = TemplateProfileQuestionController(model: model, questionIndex: 0); first.kindBinding().wrappedValue = "pick"
        XCTAssertEqual(first.entries.map(\.key), ["A", "B"]); root.addAction()()
        let second = TemplateProfileQuestionController(model: model, questionIndex: 1); second.kindBinding().wrappedValue = "pick"
        XCTAssertEqual(second.entries.map(\.key), ["C", "D"]); second.addAction()(); XCTAssertEqual(second.entries.last?.key, "E")
        second.removeAction()(IndexSet(integer: 1)); XCTAssertEqual(second.entries.map(\.key), ["C", "E"])
        root.moveAction()(IndexSet(integer: 1), 0); XCTAssertEqual(model.coordinator.draft, model.draft)
    }
    func testKindRoundTripRetainsLabelsAndEffectsThroughExistingFieldWrites() throws {
        let (model, _) = try setup(), editor = TemplateProfileQuestionController(model: model, questionIndex: 0)
        editor.kindAction("pick")()
        let path: [TemplateCreatorPath] = [.field("questions"), .index(0), .field("options"), .index(0)]
        model.draft.advanced.setCreatorValue(.profile, path: path + [.field("label")], entry: .string("Brave"))
        model.draft.advanced.setCreatorValue(.profile, path: path + [.field("effects")], entry: .array([.object(["op": .string("ADD_TAG"), "value": .string("tag.brave")])]))
        let before = model.draft.advanced.creatorValue(.profile, path: path)
        editor.kindAction("text")(); XCTAssertFalse(editor.canEditList); editor.kindAction("pick")()
        XCTAssertEqual(model.draft.advanced.creatorValue(.profile, path: path), before)
    }
    func testQuestionAndOptionDeleteCannotCrossSourceMinimums() throws {
        let (model, _) = try setup(), root = TemplateProfileQuestionController(model: model), before = model.draft
        root.removeAction()(IndexSet(integer: 0)); XCTAssertEqual(model.draft, before)
        let options = TemplateProfileQuestionController(model: model, questionIndex: 0); options.kindAction("pick")(); let seeded = model.draft
        options.removeAction()(IndexSet(integer: 0)); XCTAssertEqual(model.draft, seeded); XCTAssertFalse(options.canRemove)
    }
    func testRetainedAddDeleteMoveAndKindCallbacksCannotReplay() throws {
        let (model, _) = try setup(), root = TemplateProfileQuestionController(model: model)
        root.addAction()(); let add = root.addAction(), remove = root.removeAction(), move = root.moveAction()
        let editor = TemplateProfileQuestionController(model: model, questionIndex: 0), kind = editor.kindBinding()
        editor.kindAction("pick")(); let before = model.draft
        add(); remove(IndexSet(integer: 1)); move(IndexSet(integer: 0), 2); kind.wrappedValue = "text"
        XCTAssertEqual(model.draft, before)
    }
    func testSameValueABARetiresOldControlsBeforeViewRefresh() throws {
        let (model, _) = try setup(), editor = TemplateProfileQuestionController(model: model, questionIndex: 0), old = editor.kindBinding(), before = model.draft
        model.draft.advanced.set("profile", "title", .string("Other")); model.draft = before
        old.wrappedValue = "pick"; XCTAssertEqual(model.draft, before)
        editor.kindBinding().wrappedValue = "pick"; XCTAssertEqual(editor.entries.count, 2)
    }
    func testQuestionReorderCannotRetargetAnOpenOptionListEvenAfterReload() throws {
        let (model, _) = try setup(), root = TemplateProfileQuestionController(model: model); root.addAction()()
        let options = TemplateProfileQuestionController(model: model, questionIndex: 0); options.kindAction("pick")(); let add = options.addAction()
        root.moveAction()(IndexSet(integer: 0), 2); options.reload(); let before = model.draft
        XCTAssertFalse(options.canEdit); add(); options.addAction()(); XCTAssertEqual(model.draft, before)
    }
    func testQuestionKeyRenameRetiresOldIdentityAndFreshControllerCanEdit() throws {
        let (model, _) = try setup(), old = TemplateProfileQuestionController(model: model, questionIndex: 0), change = old.kindBinding()
        model.draft.advanced.setCreatorValue(.profile, path: [.field("questions"), .index(0), .field("key")], entry: .string("renamed")); let before = model.draft
        change.wrappedValue = "pick"; XCTAssertEqual(model.draft, before); XCTAssertFalse(old.canEdit)
        let fresh = TemplateProfileQuestionController(model: model, questionIndex: 0); fresh.kindAction("pick")(); XCTAssertEqual(fresh.entries.count, 2)
    }
    func testOptionReorderRetiresOldOffsetsWhilePreservingContent() throws {
        let (model, _) = try setup(), editor = TemplateProfileQuestionController(model: model, questionIndex: 0)
        editor.kindAction("pick")(); editor.addAction()(); let remove = editor.removeAction()
        editor.moveAction()(IndexSet(integer: 0), 3); let before = model.draft
        remove(IndexSet(integer: 0)); XCTAssertEqual(model.draft, before); XCTAssertEqual(editor.entries.map(\.key), ["B", "C", "A"])
    }
    func testLoadRestoreDiscardOwnerLeaveAndDismissFenceOldActions() throws {
        for operation in ["load", "restore", "discard", "owner", "leave", "dismiss"] {
            let (model, owner) = try setup(), editor = TemplateProfileQuestionController(model: model, questionIndex: 0)
            let kind = editor.kindBinding(), add = editor.addAction()
            switch operation {
            case "load": model.load()
            case "restore": model.restore()
            case "discard": model.discard()
            case "owner": owner.session = try .init(accountID: 953, namespace: "profile-questions", epoch: 2, authorizationRevision: "member")
            case "leave": model.leave()
            default: editor.retire()
            }
            let before = model.draft; kind.wrappedValue = "pick"; add(); XCTAssertEqual(model.draft, before, operation)
        }
    }
    func testListReappearanceAllowsFreshActionsNotRetainedOnes() throws {
        let (model, _) = try setup(), root = TemplateProfileQuestionController(model: model), old = root.addAction()
        root.retire(); root.reload(); let before = model.draft; old(); XCTAssertEqual(model.draft, before)
        root.addAction()(); XCTAssertEqual(root.entries.count, 2)
    }
    func testLocalSaveRestoreKeepsQuestionKindsAndGlobalKeys() throws {
        let store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage()), (model, owner) = try setup(store: store)
        let first = TemplateProfileQuestionController(model: model, questionIndex: 0); first.kindAction("pick")(); first.kindAction("text")()
        let root = TemplateProfileQuestionController(model: model); root.addAction()()
        let second = TemplateProfileQuestionController(model: model, questionIndex: 1); second.kindAction("pick")()
        let expected = model.draft; model.save(); model.leave()
        let reopened = TemplateAuthoringModel(coordinator: .init(store: store, currentSession: { owner.session })); reopened.load(); reopened.restore()
        XCTAssertEqual(reopened.draft, expected); XCTAssertEqual(TemplateProfileQuestionController(model: reopened, questionIndex: 1).entries.map(\.key), ["C", "D"])
        XCTAssertFalse(reopened.coordinator.canSubmit)
    }
    func testPendingWriteLockDeniesQuestionsKindsAndOptions() throws {
        let (seedModel, owner) = try setup(), session = try XCTUnwrap(owner.session)
        let store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage()), identity = TemplateAuthoringIdentity(), seed = seedModel.draft
        try store.save(seed, session: session, identity: identity)
        try store.savePending(.init(operationID: UUID(), ownerKey: session.ownerKey, identity: identity,
            request: TemplateAuthoringContract.request(seed, intent: .saveDraft), createdAt: Date()), session: session)
        let model = TemplateAuthoringModel(coordinator: .init(store: store, currentSession: { session })); model.load(); model.draft = seed
        let root = TemplateProfileQuestionController(model: model), child = TemplateProfileQuestionController(model: model, questionIndex: 0)
        root.addAction()(); child.kindAction("pick")(); child.addAction()(); XCTAssertEqual(model.draft, seed); XCTAssertFalse(root.canEdit)
    }
}

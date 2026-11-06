import XCTest
import Combine
@testable import Questify

@MainActor final class TemplateEffectListControllerTests: XCTestCase {
    private let path: [TemplateCreatorPath] = [.field("options"), .index(0), .field("effects")]
    private final class Owner { var session: TemplateAuthoringSession?; init(_ value: TemplateAuthoringSession) { session = value } }
    private func setup(store: TemplateAuthoringLocalStore? = nil) throws -> (TemplateAuthoringModel, TemplateEffectListController, Owner) {
        let owner = Owner(try .init(accountID: 921, namespace: "effect-editor", epoch: 1, authorizationRevision: "member"))
        let model = TemplateAuthoringModel(coordinator: .init(store: store ?? .init(storage: TemplateAuthoringMemoryStorage()), currentSession: { owner.session }))
        model.load(); model.draft.title = "Effect authoring"; model.draft.advanced.setCreatorEnabled(.qa, true)
        model.draft.advanced.set("qa", "mode", .string("PICK")); model.draft.advanced.set("qa", "title", .string("Choose"))
        for index in 0..<2 { model.draft.advanced.setCreatorValue(.qa, path: [.field("options"), .index(index), .field("label")], entry: .string("Option \(index)")) }
        model.draft.advanced.setCreatorValue(.qa, path: [.field("options"), .index(0), .field("correct")], entry: .bool(true))
        model.changed(); return (model, .init(model: model, family: .qa, path: path), owner)
    }
    func testFullAddTypeSwitchInputMoveAndRemoveFlow() throws {
        let (model, editor, _) = try setup(); editor.addAction()()
        editor.input(0, .variable).wrappedValue = "counter.visits"; editor.input(0, .value).wrappedValue = "2"
        editor.operation(0).wrappedValue = "ADD_TAG"; XCTAssertEqual(editor.rows[0].input, "")
        editor.input(0, .value).wrappedValue = "tag.brave"; editor.operation(0).wrappedValue = "INC"
        XCTAssertEqual(editor.rows[0].input, "1"); XCTAssertEqual(editor.rows[0].variable, "counter.visits")
        editor.addAction()(); editor.moveAction(0, 1)(); XCTAssertEqual(editor.rows[1].variable, "counter.visits")
        editor.removeAction(0)(); XCTAssertEqual(editor.rows.count, 1)
        XCTAssertEqual(model.coordinator.draft, model.draft); XCTAssertTrue(model.draft.advanced.creatorIssues(.qa).isEmpty)
    }
    func testRepeatedTypingAndInvalidIntermediateValueStayEditable() throws {
        let (_, editor, _) = try setup(); editor.addAction()()
        let variable = editor.input(0, .variable), value = editor.input(0, .value)
        variable.wrappedValue = "counter.v"; variable.wrappedValue = "counter.visits"
        value.wrappedValue = "-"; XCTAssertFalse(editor.issues.isEmpty)
        value.wrappedValue = "-3"; XCTAssertEqual(editor.rows[0].input, "-3"); XCTAssertTrue(editor.issues.isEmpty)
    }
    func testOperationChangeRetiresHiddenInputAndOldOperationBindings() throws {
        let (model, editor, _) = try setup(); editor.addAction()()
        let oldVariable = editor.input(0, .variable), oldValue = editor.input(0, .value), oldOperation = editor.operation(0)
        editor.operation(0).wrappedValue = "ADD_TAG"; let expected = model.draft
        oldVariable.wrappedValue = "counter.stale"; oldValue.wrappedValue = "99"; oldOperation.wrappedValue = "SET"
        XCTAssertEqual(model.draft, expected)
        editor.input(0, .value).wrappedValue = "tag.current"; XCTAssertEqual(editor.rows[0].input, "tag.current")
    }
    func testReorderingAndRemovingRetiresOldRowIndexControls() throws {
        let (model, editor, _) = try setup(); editor.addAction()(); editor.addAction()()
        let old = editor.input(0, .variable), remove = editor.removeAction(1), sameRows = model.draft
        var publications = 0
        let observation = editor.objectWillChange.sink { publications += 1 }; defer { observation.cancel() }
        editor.moveAction(0, 1)(); let expected = model.draft
        XCTAssertEqual(expected, sameRows) // Equal wire rows still retire their old index controls.
        XCTAssertGreaterThan(publications, 0) // The visible form must obtain the new binding generations.
        old.wrappedValue = "counter.wrong"; remove(); XCTAssertEqual(model.draft, expected)
        let removed = editor.input(0, .variable), shifted = editor.input(1, .variable), staleMove = editor.moveAction(1, 0)
        editor.removeAction(0)(); XCTAssertEqual(editor.rows.count, 1)
        let afterRemoval = model.draft
        removed.wrappedValue = "counter.removed"; shifted.wrappedValue = "counter.shifted"; staleMove()
        XCTAssertEqual(model.draft, afterRemoval)
        let fresh = editor.input(0, .variable)
        fresh.wrappedValue = "counter.f"; fresh.wrappedValue = "counter.fresh"
        XCTAssertEqual(editor.rows[0].variable, "counter.fresh"); XCTAssertEqual(model.coordinator.draft, model.draft)
    }
    func testEnclosingOptionChangeCannotSilentlyRetargetEvenAfterReload() throws {
        let (model, editor, _) = try setup(); editor.addAction()()
        let old = editor.input(0, .value), add = editor.addAction()
        var rows = model.draft.advanced.rows("qa", "options"); rows.swapAt(0, 1); model.draft.advanced.set("qa", "options", .array(rows))
        editor.reload(); let expected = model.draft
        XCTAssertTrue(editor.needsReopen); XCTAssertFalse(editor.canEdit)
        old.wrappedValue = "99"; add(); XCTAssertEqual(model.draft, expected)
    }
    func testSameValueParentABARejectsRetainedCallbacksBeforeOnChange() throws {
        let (model, editor, _) = try setup(); editor.addAction()()
        let old = editor.input(0, .value), operation = editor.operation(0), before = model.draft
        model.draft.advanced.set("qa", "mode", .string("TYPE")); model.draft = before
        old.wrappedValue = "99"; operation.wrappedValue = "SET"
        XCTAssertEqual(model.draft, before)
        editor.input(0, .value).wrappedValue = "3"; XCTAssertEqual(editor.rows[0].input, "3")
    }
    func testLocalSaveAndFreshRestoreRetainTypedEffectConfiguration() throws {
        let store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage())
        let (model, editor, owner) = try setup(store: store); editor.addAction()()
        editor.operation(0).wrappedValue = "ADD_TAG"; editor.input(0, .value).wrappedValue = "tag.brave"
        let expected = model.draft; model.save(); editor.retire(); model.leave()
        let reopened = TemplateAuthoringModel(coordinator: .init(store: store, currentSession: { owner.session })); reopened.load(); reopened.restore()
        let fresh = TemplateEffectListController(model: reopened, family: .qa, path: path)
        XCTAssertEqual(reopened.draft, expected); XCTAssertEqual(fresh.rows[0].input, "tag.brave"); XCTAssertTrue(fresh.canEdit)
        XCTAssertFalse(reopened.coordinator.canSubmit)
    }
    func testLoadRestoreDiscardOwnerAndDismissFenceOldControls() throws {
        for operation in ["load", "restore", "discard", "owner", "dismiss", "leave"] {
            let (model, editor, owner) = try setup(); editor.addAction()()
            let input = editor.input(0, .value), add = editor.addAction()
            switch operation {
            case "load": model.load()
            case "restore": model.restore()
            case "discard": model.discard()
            case "owner": owner.session = try .init(accountID: 922, namespace: "effect-editor", epoch: 2, authorizationRevision: "member")
            case "leave": model.leave()
            default: editor.retire()
            }
            let expected = model.draft; input.wrappedValue = "99"; add(); XCTAssertEqual(model.draft, expected, operation)
        }
    }
    func testSameParentReappearancePreservesContentButDoesNotReviveBindings() throws {
        let (model, editor, _) = try setup(); editor.addAction()()
        let old = editor.input(0, .value); editor.retire(); editor.reload(); let before = model.draft
        old.wrappedValue = "99"; XCTAssertEqual(model.draft, before)
        editor.input(0, .value).wrappedValue = "4"; XCTAssertEqual(editor.rows[0].input, "4")
    }
    func testPendingWriteLockDeniesAllEffectChanges() throws {
        let (seedModel, _, owner) = try setup(), session = try XCTUnwrap(owner.session)
        let store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage()), identity = TemplateAuthoringIdentity(), seed = seedModel.draft
        try store.save(seed, session: session, identity: identity)
        try store.savePending(.init(operationID: UUID(), ownerKey: session.ownerKey, identity: identity,
            request: TemplateAuthoringContract.request(seed, intent: .saveDraft), createdAt: Date()), session: session)
        let model = TemplateAuthoringModel(coordinator: .init(store: store, currentSession: { session })); model.load(); model.draft = seed
        let editor = TemplateEffectListController(model: model, family: .qa, path: path); editor.addAction()()
        XCTAssertFalse(editor.canEdit); XCTAssertEqual(model.draft, seed)
    }
}

@MainActor final class TemplateCheckPresetTests: XCTestCase {
    private final class Owner {
        var session: TemplateAuthoringSession?
        init(_ session: TemplateAuthoringSession) { self.session = session }
    }
    private struct Fixture {
        let model: TemplateAuthoringModel
        let editor: TemplateCheckPresetController
        let owner: Owner
        let storage: TemplateAuthoringMemoryStorage
    }
    private func draft(_ rows: [TemplateAuthoringJSON] = []) -> TemplateAdvancedDraft {
        var value = TemplateAdvancedDraft(); value.setCreatorEnabled(.check, true)
        value.set("check", "mods", .array(rows)); return value
    }
    private func custom(_ index: Int = 0) -> TemplateAuthoringJSON {
        .object(["label": .string("Custom \(index)"), "value": .number(2),
                 "when": .object(["var": .string("sys.exhausted"), "op": .string("EQ"), "value": .number(0)])])
    }
    private func fixture(appear: Bool = true) throws -> Fixture {
        let owner = Owner(try .init(accountID: 993, namespace: "check-presets", epoch: 1, authorizationRevision: "member"))
        let storage = TemplateAuthoringMemoryStorage()
        let model = TemplateAuthoringModel(coordinator: .init(store: .init(storage: storage), currentSession: { owner.session }))
        model.load(); model.draft.title = "Local check"; model.draft.advanced = draft(); model.changed()
        let editor = TemplateCheckPresetController(model: model)
        if appear { editor.viewAppeared(sceneIsActive: true) }
        return .init(model: model, editor: editor, owner: owner, storage: storage)
    }
    func testAllLuckChoicesUseExistingSchemaAndExactConditions() throws {
        let config = TemplateCheckPresetConfiguration(draft())
        for (choice, count) in [(TemplateCheckLuckChoice.off, 0), (.high, 1), (.low, 1), (.both, 2)] {
            let result = try XCTUnwrap(config.applying(luck: choice, hpLadder: false))
            XCTAssertEqual(result.rows("check", "mods").count, count)
            XCTAssertTrue(result.creatorIssues(.check).isEmpty)
            XCTAssertEqual(TemplateCheckPresetConfiguration(result).luck, choice)
        }
        let both = try XCTUnwrap(config.applying(luck: .both, hpLadder: false))
        XCTAssertEqual(TemplateCheckPresetConfiguration.modifier(in: both, hp: 9, luck: 3), 1)
        XCTAssertEqual(TemplateCheckPresetConfiguration.modifier(in: both, hp: 9, luck: 1), 0)
        XCTAssertEqual(TemplateCheckPresetConfiguration.modifier(in: both, hp: 9, luck: 0), -1)
    }
    func testHPLadderAccumulatesAtSixAndThreeWithoutExceedingTwo() throws {
        let value = try XCTUnwrap(TemplateCheckPresetConfiguration(draft()).applying(luck: .off, hpLadder: true))
        XCTAssertTrue(TemplateCheckPresetConfiguration(value).hpLadder)
        for (hp, amount) in [(7, 0), (6, -1), (4, -1), (3, -2), (0, -2)] {
            XCTAssertEqual(TemplateCheckPresetConfiguration.modifier(in: value, hp: hp, luck: 1), amount)
        }
        XCTAssertTrue(value.creatorIssues(.check).isEmpty)
    }
    func testPreviewIncludesUnrelatedMatchingModifiersWithoutMutatingOriginal() throws {
        let original = draft([custom()])
        let next = try XCTUnwrap(TemplateCheckPresetConfiguration(original).applying(luck: .both, hpLadder: true))
        XCTAssertEqual(TemplateCheckPresetConfiguration.modifier(in: next, hp: 3, luck: 0), -1)
        XCTAssertEqual(TemplateCheckPresetConfiguration.modifier(in: next, hp: 6, luck: 3), 2)
        XCTAssertEqual(original.rows("check", "mods"), [custom()])
    }
    func testSwitchPreservesCustomRowsAndExistingManagedPositions() throws {
        let high = TemplateCheckPresetConfiguration.Step.high.row
        let original = draft([custom(1), high, custom(2)])
        let next = try XCTUnwrap(TemplateCheckPresetConfiguration(original).applying(luck: .both, hpLadder: true))
        XCTAssertEqual(Array(next.rows("check", "mods").prefix(3)), [custom(1), high, custom(2)])
        var expected = original; expected.set("check", "mods", .array(next.rows("check", "mods")))
        XCTAssertEqual(next, expected)
    }
    func testSwitchingOffRemovesOnlyExactManagedRows() throws {
        let all = [custom(1)] + TemplateCheckPresetConfiguration.Step.allCases.map(\.row) + [custom(2)]
        let next = try XCTUnwrap(TemplateCheckPresetConfiguration(draft(all)).applying(luck: .off, hpLadder: false))
        XCTAssertEqual(next.rows("check", "mods"), [custom(1), custom(2)])
        XCTAssertTrue(next.enabled("check"))
    }
    func testRepeatedChoiceChangesAreIdempotentAndNeverDuplicateRows() throws {
        var value = draft([custom()])
        for _ in 0..<4 {
            value = try XCTUnwrap(TemplateCheckPresetConfiguration(value).applying(luck: .both, hpLadder: true))
            XCTAssertEqual(value.rows("check", "mods").count, 5)
            value = try XCTUnwrap(TemplateCheckPresetConfiguration(value).applying(luck: .high, hpLadder: false))
            XCTAssertEqual(value.rows("check", "mods").count, 2)
            value = try XCTUnwrap(TemplateCheckPresetConfiguration(value).applying(luck: .off, hpLadder: false))
            XCTAssertEqual(value.rows("check", "mods"), [custom()])
        }
    }
    func testMalformedEnabledAndModsArePreservedAndRefused() {
        for raw in [TemplateAuthoringJSON.string("true"), .number(1), .null, .bool(false)] {
            var value = draft(); value.set("check", "enabled", raw)
            let config = TemplateCheckPresetConfiguration(value)
            XCTAssertFalse(config.isSupported); XCTAssertNil(config.applying(luck: .high, hpLadder: true))
            XCTAssertEqual(config.original, value)
        }
        for raw in [TemplateAuthoringJSON.string(""), .object([:]), .null, .bool(false)] {
            var value = draft(); value.set("check", "mods", raw)
            let config = TemplateCheckPresetConfiguration(value)
            XCTAssertFalse(config.isSupported); XCTAssertNil(config.applying(luck: .off, hpLadder: false))
            XCTAssertEqual(config.original, value)
        }
    }
    func testAbsentModsRemainAbsentWhenNoPresetIsSelected() throws {
        var value = draft(); var fields = value.value["check"]!.object!
        fields.removeValue(forKey: "mods"); value.value["check"] = .object(fields)
        let config = TemplateCheckPresetConfiguration(value)
        XCTAssertTrue(config.isSupported)
        XCTAssertEqual(try XCTUnwrap(config.applying(luck: .off, hpLadder: false)), value)
        XCTAssertEqual(try XCTUnwrap(config.applying(luck: .high, hpLadder: false)).rows("check", "mods").count, 1)
    }
    func testCustomSameConditionAndSameLabelNeverBecomeOwned() {
        let known = TemplateCheckPresetConfiguration.Step.high.row.object!
        var renamed = known; renamed["label"] = .string("My custom label")
        var revalued = known; revalued["value"] = .number(3)
        var stringCondition = known
        var condition = TemplateCheckPresetConfiguration.Step.high.condition; condition["value"] = .string("3")
        stringCondition["when"] = .object(condition); stringCondition["label"] = .string("Other label")
        var extraCondition = known; var extra = TemplateCheckPresetConfiguration.Step.high.condition
        extra["nodeId"] = .number(1); extraCondition["when"] = .object(extra); extraCondition["label"] = .string("Extra field")
        for row in [renamed, revalued, stringCondition, extraCondition] {
            let value = draft([.object(row)]); let config = TemplateCheckPresetConfiguration(value)
            XCTAssertFalse(config.isSupported); XCTAssertNil(config.applying(luck: .off, hpLadder: false))
            XCTAssertEqual(config.original, value)
        }
    }
    func testUnknownDuplicateAndPartialLadderRowsFailClosed() {
        let high = TemplateCheckPresetConfiguration.Step.high.row
        var unknown = high.object!; unknown["future"] = .bool(true)
        for rows in [[high, high], [.object(unknown)], [TemplateCheckPresetConfiguration.Step.hurt.row], [TemplateCheckPresetConfiguration.Step.severe.row]] {
            let original = draft(rows); let config = TemplateCheckPresetConfiguration(original)
            XCTAssertFalse(config.isSupported); XCTAssertNil(config.applying(luck: .both, hpLadder: true))
            XCTAssertEqual(config.original, original)
        }
    }
    func testLimitNeverDropsExistingRowsToMakeRoom() throws {
        let original = draft((0..<16).map { custom($0) }); let config = TemplateCheckPresetConfiguration(original)
        XCTAssertTrue(config.isSupported); XCTAssertNil(config.applying(luck: .high, hpLadder: false))
        XCTAssertEqual(try XCTUnwrap(config.applying(luck: .off, hpLadder: false)), original)
        let atLimit = try XCTUnwrap(TemplateCheckPresetConfiguration(draft((0..<12).map { custom($0) })).applying(luck: .both, hpLadder: true))
        XCTAssertEqual(atLimit.rows("check", "mods").count, 16)
    }
    func testUnrelatedFutureFieldsRemainExactAndExistingValidationStillRejectsThem() throws {
        var original = draft([custom()]); original.set("check", "future", .string("retain"))
        original.value["futureRoot"] = .object(["opaque": .string("keep")])
        let next = try XCTUnwrap(TemplateCheckPresetConfiguration(original).applying(luck: .high, hpLadder: false))
        var expected = original; expected.set("check", "mods", .array(next.rows("check", "mods")))
        XCTAssertEqual(next, expected)
        XCTAssertTrue(next.creatorIssues(.check).contains { $0.path == "future" && $0.code == "unknown" })
    }
    func testStagingAndCancelDoNotChangeDraftStoreOrReview() throws {
        let f = try fixture(), original = f.model.draft
        for choice in TemplateCheckLuckChoice.allCases { f.editor.luckBinding.wrappedValue = choice; f.editor.hpBinding.wrappedValue = !f.editor.hpBinding.wrappedValue }
        f.editor.luckBinding.wrappedValue = .both; f.editor.hpBinding.wrappedValue = true
        XCTAssertTrue(f.editor.canApply); XCTAssertNotNil(f.editor.preview)
        var dismissals = 0; let cancel = f.editor.cancelAction { dismissals += 1 }; cancel(); cancel()
        XCTAssertEqual(dismissals, 1); XCTAssertEqual(f.model.draft, original)
        XCTAssertTrue(f.storage.values.isEmpty); XCTAssertNil(f.model.review)
    }
    func testExplicitApplyChangesOnlyModsInMemoryAndCannotReplay() throws {
        let f = try fixture(), original = f.model.draft
        f.editor.luckBinding.wrappedValue = .both; f.editor.hpBinding.wrappedValue = true
        let apply = f.editor.applyAction(); apply(); apply()
        var expected = original; expected.advanced.set("check", "mods", .array(f.model.draft.advanced.rows("check", "mods")))
        XCTAssertEqual(f.model.draft, expected); XCTAssertEqual(f.model.coordinator.draft, expected)
        XCTAssertEqual(f.model.draft.advanced.rows("check", "mods").count, 4)
        XCTAssertTrue(f.editor.didApply); XCTAssertFalse(f.editor.canApply)
        XCTAssertTrue(f.storage.values.isEmpty); XCTAssertFalse(f.model.coordinator.canSubmit)
        XCTAssertNil(f.model.coordinator.pending); XCTAssertNil(f.model.review)
    }
    func testOldBindingCannotReadOrWriteReopenedControls() throws {
        let f = try fixture(), oldLuck = f.editor.luckBinding, oldHP = f.editor.hpBinding
        f.editor.viewDisappeared(); f.editor.viewAppeared(sceneIsActive: true)
        f.editor.luckBinding.wrappedValue = .both; f.editor.hpBinding.wrappedValue = true
        XCTAssertEqual(oldLuck.wrappedValue, .off); XCTAssertFalse(oldHP.wrappedValue)
        oldLuck.wrappedValue = .low; oldHP.wrappedValue = false
        XCTAssertEqual(f.editor.luckBinding.wrappedValue, .both); XCTAssertTrue(f.editor.hpBinding.wrappedValue)
    }
    func testOldApplyCancelReloadCannotAffectReopenedOwner() throws {
        let f = try fixture(), original = f.model.draft
        var dismissals = 0
        let apply = f.editor.applyAction(), cancel = f.editor.cancelAction { dismissals += 1 }, reload = f.editor.reloadAction()
        f.editor.viewDisappeared(); f.editor.viewAppeared(sceneIsActive: true)
        f.editor.luckBinding.wrappedValue = .both; f.editor.hpBinding.wrappedValue = true
        apply(); cancel(); reload()
        XCTAssertEqual(f.model.draft, original); XCTAssertEqual(dismissals, 0)
        XCTAssertEqual(f.editor.luckBinding.wrappedValue, .both); XCTAssertTrue(f.editor.hpBinding.wrappedValue)
    }
    func testHiddenForegroundAndReloadDoNotReactivateOwner() throws {
        let f = try fixture()
        f.editor.viewDisappeared(); f.editor.sceneChanged(isActive: false); f.editor.sceneChanged(isActive: true)
        f.editor.reloadAction()(); f.editor.reload()
        XCTAssertNil(f.editor.visibleConfiguration); XCTAssertFalse(f.editor.canApply)
        f.editor.luckBinding.wrappedValue = .high; f.editor.applyAction()()
        XCTAssertTrue(f.model.draft.advanced.rows("check", "mods").isEmpty)
    }
    func testInactiveAppearanceStaysRetiredUntilActualActiveScene() throws {
        let f = try fixture(appear: false)
        f.editor.viewAppeared(sceneIsActive: false); XCTAssertNil(f.editor.visibleConfiguration)
        f.editor.sceneChanged(isActive: true); XCTAssertNotNil(f.editor.visibleConfiguration)
        f.editor.luckBinding.wrappedValue = .high; let old = f.editor.luckBinding
        f.editor.sceneChanged(isActive: false); XCTAssertEqual(old.wrappedValue, .off)
        f.editor.sceneChanged(isActive: true); f.editor.luckBinding.wrappedValue = .low
        old.wrappedValue = .both; XCTAssertEqual(f.editor.luckBinding.wrappedValue, .low)
    }
    func testRepeatedAppearPreservesStagedChoice() throws {
        let f = try fixture(); f.editor.luckBinding.wrappedValue = .both; f.editor.hpBinding.wrappedValue = true
        f.editor.viewAppeared(sceneIsActive: true); f.editor.viewAppeared(sceneIsActive: true)
        XCTAssertEqual(f.editor.luckBinding.wrappedValue, .both); XCTAssertTrue(f.editor.hpBinding.wrappedValue)
        XCTAssertTrue(f.model.draft.advanced.rows("check", "mods").isEmpty)
    }
    func testOwnerSwitchBeforeViewUpdateRejectsReadsWritesAndDismiss() throws {
        let f = try fixture(), original = f.model.draft, binding = f.editor.luckBinding
        var dismissals = 0; let cancel = f.editor.cancelAction { dismissals += 1 }, apply = f.editor.applyAction()
        f.owner.session = try .init(accountID: 994, namespace: "check-presets", epoch: 2, authorizationRevision: "member")
        XCTAssertEqual(binding.wrappedValue, .off); binding.wrappedValue = .both; cancel(); apply()
        XCTAssertNil(f.editor.visibleConfiguration); XCTAssertEqual(f.model.draft, original); XCTAssertEqual(dismissals, 0)
    }
    func testDraftABAPublicationRetiresOldControlsEvenWhenBytesMatchAgain() throws {
        let f = try fixture(), original = f.model.draft, binding = f.editor.luckBinding
        let apply = f.editor.applyAction()
        f.model.draft.title = "Temporary"; f.model.draft = original
        XCTAssertNil(f.editor.visibleConfiguration); binding.wrappedValue = .both; apply()
        XCTAssertEqual(f.model.draft, original)
        f.editor.reload(); f.editor.luckBinding.wrappedValue = .high
        XCTAssertEqual(binding.wrappedValue, .off); binding.wrappedValue = .low
        XCTAssertEqual(f.editor.luckBinding.wrappedValue, .high)
    }
    func testBusyAndReviewEventsRetireControlsWithoutApplying() throws {
        let f = try fixture(), original = f.model.draft, binding = f.editor.hpBinding
        let apply = f.editor.applyAction(); f.model.busy = true
        binding.wrappedValue = true; apply(); f.editor.reload()
        XCTAssertNil(f.editor.visibleConfiguration); XCTAssertEqual(f.model.draft, original)
        f.model.busy = false; f.editor.reload(); f.editor.hpBinding.wrappedValue = true
        f.model.review = nil // Any parent lifecycle publication retires the captured owner.
        XCTAssertFalse(f.editor.canApply); XCTAssertNil(f.editor.visibleConfiguration)
    }
    func testParentLoadDiscardAndLeaveRetireAllCapturedActions() throws {
        for operation in ["load", "discard", "leave"] {
            let f = try fixture(), binding = f.editor.luckBinding, apply = f.editor.applyAction()
            f.editor.luckBinding.wrappedValue = .both
            switch operation { case "load": f.model.load(); case "discard": f.model.discard(); default: f.model.leave() }
            let expected = f.model.draft; binding.wrappedValue = .low; apply()
            XCTAssertEqual(f.model.draft, expected, operation); XCTAssertEqual(binding.wrappedValue, .off, operation)
        }
    }
    func testExplicitParentSaveAndReopenRetainAppliedPresets() throws {
        let f = try fixture(); f.editor.luckBinding.wrappedValue = .both; f.editor.hpBinding.wrappedValue = true
        f.editor.applyAction()(); XCTAssertTrue(f.storage.values.isEmpty)
        let expected = f.model.draft; f.model.save(); XCTAssertFalse(f.storage.values.isEmpty)
        f.editor.viewDisappeared(); f.model.leave()
        let reopened = TemplateAuthoringModel(coordinator: .init(store: .init(storage: f.storage), currentSession: { f.owner.session }))
        reopened.load(); reopened.restore(); XCTAssertEqual(reopened.draft, expected)
        let editor = TemplateCheckPresetController(model: reopened); editor.viewAppeared(sceneIsActive: true)
        XCTAssertEqual(editor.luckBinding.wrappedValue, .both); XCTAssertTrue(editor.hpBinding.wrappedValue)
        XCTAssertFalse(reopened.coordinator.canSubmit)
    }

    func testPendingWriteLockCannotBeBypassedByPresetControls() throws {
        let f = try fixture(), session = try XCTUnwrap(f.owner.session), seed = f.model.draft
        let store = TemplateAuthoringLocalStore(storage: TemplateAuthoringMemoryStorage()), identity = TemplateAuthoringIdentity()
        try store.save(seed, session: session, identity: identity)
        try store.savePending(.init(operationID: UUID(), ownerKey: session.ownerKey, identity: identity,
            request: TemplateAuthoringContract.request(seed, intent: .saveDraft), createdAt: Date()), session: session)
        let model = TemplateAuthoringModel(coordinator: .init(store: store, currentSession: { session })); model.load(); model.draft = seed
        let editor = TemplateCheckPresetController(model: model); editor.viewAppeared(sceneIsActive: true)
        editor.luckBinding.wrappedValue = .both; editor.hpBinding.wrappedValue = true; editor.applyAction()()
        XCTAssertFalse(editor.canApply); XCTAssertNil(editor.visibleConfiguration); XCTAssertEqual(model.draft, seed)
    }
}

import XCTest
@testable import QuestifyCore

final class TemplateEffectListTests: XCTestCase {
    private let path: [TemplateCreatorPath] = [.field("options"), .index(0), .field("effects")]
    private func fixture() -> TemplateAdvancedDraft {
        var draft = TemplateAdvancedDraft(); draft.setCreatorEnabled(.qa, true)
        draft.set("qa", "mode", .string("PICK")); draft.set("qa", "title", .string("Choose"))
        for index in 0..<2 { draft.setCreatorValue(.qa, path: [.field("options"), .index(index), .field("label")], entry: .string("Option \(index)")) }
        draft.setCreatorValue(.qa, path: [.field("options"), .index(0), .field("correct")], entry: .bool(true))
        return draft
    }
    private func list(_ draft: TemplateAdvancedDraft) -> TemplateEffectList { .init(draft, family: .qa, path: path) }
    private func edit(_ edit: TemplateEffectList.Edit, _ draft: TemplateAdvancedDraft) throws -> TemplateAdvancedDraft { try XCTUnwrap(list(draft).applying(edit, to: draft)) }
    private func value(_ draft: TemplateAdvancedDraft, _ index: Int = 0) -> [String: TemplateAuthoringJSON] { draft.creatorValue(.qa, path: path)?.array?[index].object ?? [:] }

    func testOnlyExistingEffectPathsAreRecognized() {
        XCTAssertTrue(TemplateEffectList.isEffectPath(.qa, path))
        for key in ["successEffects", "failEffects", "critEffects", "fumbleEffects"] { XCTAssertTrue(TemplateEffectList.isEffectPath(.check, [.field(key)])) }
        XCTAssertTrue(TemplateEffectList.isEffectPath(.profile, [.field("questions"), .index(1), .field("options"), .index(2), .field("effects")]))
        XCTAssertTrue(TemplateEffectList.isEffectPath(.branch, [.field("steps"), .index(0), .field("options"), .index(0), .field("effects")]))
        XCTAssertFalse(TemplateEffectList.isEffectPath(.compare, [.field("effects")]))
        XCTAssertFalse(TemplateEffectList.isEffectPath(.check, [.field("mods")]))
        XCTAssertFalse(TemplateEffectList.isEffectPath(.qa, [.field("options"), .index(-1), .field("effects")]))
        XCTAssertFalse(TemplateEffectList.isEffectPath(.qa, []))
    }
    func testCheckProfileAndBranchUseExistingActiveParentContexts() throws {
        var draft = TemplateAdvancedDraft(); draft.setCreatorEnabled(.check, true)
        for key in ["successEffects", "failEffects", "critEffects", "fumbleEffects"] {
            let target: [TemplateCreatorPath] = [.field(key)]
            let list = TemplateEffectList(draft, family: .check, path: target)
            XCTAssertTrue(list.canEdit)
            XCTAssertNotNil(list.applying(.add, to: draft))
        }
        draft.setCreatorEnabled(.profile, true)
        draft.setCreatorValue(.profile, path: [.field("questions"), .index(0), .field("kind")], entry: .string("pick"))
        draft.setCreatorValue(.profile, path: [.field("questions"), .index(0), .field("options")], entry: .array([.object(["key": .string("one"), "label": .string("One")])]))
        let profile: [TemplateCreatorPath] = [.field("questions"), .index(0), .field("options"), .index(0), .field("effects")]
        XCTAssertTrue(TemplateEffectList(draft, family: .profile, path: profile).canEdit)
        draft.setCreatorValue(.profile, path: [.field("questions"), .index(0), .field("kind")], entry: .string("text"))
        XCTAssertFalse(TemplateEffectList(draft, family: .profile, path: profile).canEdit)
        draft.setCreatorEnabled(.branch, true)
        draft.setCreatorValue(.branch, path: [.field("steps"), .index(0), .field("options")], entry: .array([.object(["id": .string("one"), "label": .string("One")])]))
        let branch: [TemplateCreatorPath] = [.field("steps"), .index(0), .field("options"), .index(0), .field("effects")]
        XCTAssertFalse(TemplateEffectList(draft, family: .branch, path: branch).canEdit)
        draft.setCreatorValue(.branch, path: [.field("steps"), .index(0), .field("terminal")], entry: .bool(false))
        XCTAssertTrue(TemplateEffectList(draft, family: .branch, path: branch).canEdit)
    }
    func testAddDefaultAndSixteenRowLimit() throws {
        var draft = fixture(); XCTAssertTrue(list(draft).rows.isEmpty)
        draft = try edit(.add, draft)
        XCTAssertEqual(value(draft), ["var": .string(""), "op": .string("INC"), "value": .number(1)])
        for _ in 1..<16 { draft = try edit(.add, draft) }
        XCTAssertEqual(list(draft).rows.count, 16); XCTAssertFalse(list(draft).canAdd)
        XCTAssertNil(list(draft).applying(.add, to: draft))
    }
    func testSwitchOperationConvertsOnlyValueShapeAndPreservesVariable() throws {
        var draft = try edit(.add, fixture())
        draft = try edit(.input(0, .variable, "counter.visits"), draft)
        draft = try edit(.operation(0, "ADD_TAG"), draft)
        XCTAssertEqual(value(draft)["value"], .string("")); XCTAssertEqual(value(draft)["var"], .string("counter.visits"))
        draft = try edit(.input(0, .value, "tag.brave"), draft)
        draft = try edit(.operation(0, "SET"), draft)
        XCTAssertEqual(value(draft)["value"], .number(1)); XCTAssertEqual(value(draft)["var"], .string("counter.visits"))
        draft = try edit(.input(0, .value, " -2 "), draft)
        draft = try edit(.operation(0, "INC"), draft)
        XCTAssertEqual(value(draft)["value"], .number(-2))
    }
    func testStringTagPreservationAndEmptyVersusWhitespaceNumericTransition() throws {
        let cases: [(String, Double)] = [("", 1), (" ", 0), ("NaN", 1), ("3", 3)]
        for (text, expected) in cases {
            var draft = try edit(.add, fixture()); draft = try edit(.input(0, .value, text), draft)
            draft = try edit(.operation(0, "SET"), draft); XCTAssertEqual(value(draft)["value"], .number(expected))
        }
        var draft = try edit(.add, fixture()); draft = try edit(.input(0, .value, "tag.existing"), draft)
        draft = try edit(.operation(0, "ADD_TAG"), draft); XCTAssertEqual(value(draft)["value"], .string("tag.existing"))
    }
    func testNumericTypingStaysEditableAndExistingSerializerUsesNumber() throws {
        var draft = try edit(.add, fixture()); draft = try edit(.input(0, .variable, "counter.visits"), draft)
        draft = try edit(.input(0, .value, "-"), draft)
        XCTAssertEqual(value(draft)["value"], .string("-")); XCTAssertFalse(draft.creatorIssues(.qa).isEmpty)
        draft = try edit(.input(0, .value, "-3"), draft)
        XCTAssertTrue(draft.creatorIssues(.qa).isEmpty)
        let restored = try TemplateAdvancedDraft(raw: draft.serialize())
        XCTAssertEqual(value(restored)["value"], .number(-3)); XCTAssertEqual(value(draft)["value"], .number(-3))
    }
    func testTagSerializationAndHiddenVariableCannotBeWritten() throws {
        var draft = try edit(.add, fixture()); draft = try edit(.operation(0, "ADD_TAG"), draft)
        XCTAssertNil(list(draft).applying(.input(0, .variable, "counter.stale"), to: draft))
        draft = try edit(.input(0, .value, "tag.brave"), draft)
        let serialized = try TemplateAdvancedDraft(raw: draft.serialize())
        XCTAssertEqual(value(serialized)["value"], .string("tag.brave")); XCTAssertNil(value(serialized)["var"])
    }
    func testMoveAndRemovePreserveWholeRowsAndAllowEmptyList() throws {
        var draft = try edit(.add, fixture()); draft = try edit(.input(0, .variable, "counter.first"), draft)
        draft = try edit(.add, draft); draft = try edit(.input(1, .variable, "counter.second"), draft)
        draft = try edit(.move(0, 1), draft)
        XCTAssertEqual(list(draft).rows.map(\.variable), ["counter.second", "counter.first"])
        draft = try edit(.remove(0), draft); draft = try edit(.remove(0), draft)
        XCTAssertEqual(draft.creatorValue(.qa, path: path), .array([]))
    }
    func testUnknownFieldsSurviveAndOpeningNeverNormalizes() throws {
        var draft = try edit(.add, fixture())
        draft.setCreatorValue(.qa, path: path + [.index(0), .field("future")], entry: .object(["keep": .string("原样")]))
        let before = draft; _ = list(draft); XCTAssertEqual(draft, before)
        var changed = try edit(.operation(0, "ADD_TAG"), draft)
        changed = try edit(.input(0, .value, "tag.kept"), changed)
        XCTAssertEqual(value(changed)["future"], .object(["keep": .string("原样")]))
        XCTAssertThrowsError(try changed.serialize())
    }
    func testMalformedOversizedAndInactiveContextsArePreserved() {
        let invalid: [TemplateAuthoringJSON] = [.string("legacy"), .array([.string("row")]), .array(Array(repeating: .object([:]), count: 17)), .array([.object(["op": .number(1)])]), .array([.object(["value": .number(.infinity)])])]
        for raw in invalid {
            var draft = fixture(); draft.setCreatorValue(.qa, path: path, entry: raw)
            XCTAssertFalse(list(draft).isSupported); XCTAssertNil(list(draft).applying(.add, to: draft))
        }
        var draft = fixture(); draft.set("qa", "mode", .string("TYPE")); XCTAssertFalse(list(draft).canEdit)
        draft = fixture(); draft.setCreatorEnabled(.qa, false); XCTAssertFalse(list(draft).canEdit)
    }
    func testCapturedScopeStaysSameForEffectsButChangesForEnclosingOption() throws {
        let original = fixture(), captured = list(original), added = try edit(.add, original)
        XCTAssertEqual(captured.scopeFingerprint, list(added).scopeFingerprint)
        var changed = added; changed.setCreatorValue(.qa, path: [.field("options"), .index(0), .field("label")], entry: .string("Different parent"))
        XCTAssertNotEqual(list(added).scopeFingerprint, list(changed).scopeFingerprint)
        XCTAssertNil(list(added).applying(.remove(0), to: changed))
    }
    func testInvalidActionsCannotReachOtherFieldsOrConditionOperations() throws {
        let draft = try edit(.add, fixture())
        let invalid: [TemplateEffectList.Edit] = [.remove(-1), .move(0, 1), .operation(0, "EQ"), .input(4, .value, "3")]
        for operation in invalid { XCTAssertNil(list(draft).applying(operation, to: draft)) }
        XCTAssertEqual(list(draft).validationPrefix, "options[1].effects")
    }
    func testLocalDraftRoundTripPreservesEffectsAndOtherFamilies() throws {
        var draft = try edit(.add, fixture()); draft = try edit(.input(0, .variable, "counter.visits"), draft)
        draft.set("timer", "enabled", .bool(true))
        var local = TemplateAuthoringDraft(title: "Effects"); local.advanced = draft
        let restored = try JSONDecoder().decode(TemplateAuthoringDraft.self, from: JSONEncoder().encode(local))
        XCTAssertEqual(restored, local); XCTAssertEqual(list(restored.advanced).rows.count, 1)
    }
}

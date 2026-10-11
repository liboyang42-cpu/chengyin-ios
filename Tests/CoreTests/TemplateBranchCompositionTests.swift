import XCTest
@testable import QuestifyCore

final class TemplateBranchCompositionTests: XCTestCase {
    private func fixture() -> TemplateAdvancedDraft { var draft = TemplateAdvancedDraft(); draft.setCreatorEnabled(.branch, true); return draft }
    private func edit(_ draft: TemplateAdvancedDraft, _ change: TemplateBranchComposition.Edit) throws -> TemplateAdvancedDraft { try XCTUnwrap(TemplateBranchComposition(draft).applying(change, to: draft)) }
    private func step(_ draft: TemplateAdvancedDraft, _ index: Int = 0) -> [String: TemplateAuthoringJSON] { draft.rows("branch", "steps")[index].object! }
    private func set(_ draft: inout TemplateAdvancedDraft, _ field: String, _ value: TemplateAuthoringJSON?) { draft.setCreatorValue(.branch, path: [.field("steps"), .index(0), .field(field)], entry: value) }

    func testAddStepUsesMiniDefaultsAndNeverRewritesStartReference() throws {
        let original = fixture(), draft = try edit(original, .addStep("end"))
        XCTAssertEqual(step(draft, 1), ["id": .string("end"), "title": .string(""), "body": .string(""), "terminal": .bool(true), "outcomeCode": .string("COMPLETED"), "outcomeLabel": .string("完成节点"), "options": .array([])])
        XCTAssertEqual(draft.text("branch", "startStepId"), original.text("branch", "startStepId")); XCTAssertEqual(step(draft), step(original))
    }
    func testAddStepStopsAtFiftyAndRejectsDuplicateOrInvalidIdentity() throws {
        var draft = fixture(); for index in 1..<50 { draft = try edit(draft, .addStep("step_\(index)")) }
        XCTAssertEqual(TemplateBranchComposition(draft).steps.count, 50); XCTAssertFalse(TemplateBranchComposition(draft).canAddStep)
        for id in ["overflow", "start", "", "bad.id"] { XCTAssertNil(TemplateBranchComposition(draft).applying(.addStep(id), to: draft)) }
        XCTAssertNil(TemplateBranchComposition(fixture()).applying(.addStep("start"), to: fixture()))
    }
    func testAddOptionAtomicallyLeavesTerminalAndUsesSourceShape() throws {
        let draft = try edit(fixture(), .addOption(stepID: "start", optionID: "go"))
        XCTAssertEqual(step(draft)["terminal"], .bool(false))
        XCTAssertEqual(step(draft)["options"], .array([.object(["id": .string("go"), "label": .string(""), "nextStepId": .string(""), "score": .number(0)])]))
        XCTAssertEqual(step(draft)["outcomeCode"], .string("COMPLETED"))
        XCTAssertFalse(draft.creatorIssues(.branch).isEmpty) // No invented label or next-step destination.
    }
    func testOptionLimitAndIdentityAreBoundedToExistingStep() throws {
        var draft = fixture(); for index in 0..<12 { draft = try edit(draft, .addOption(stepID: "start", optionID: "option_\(index)")) }
        XCTAssertFalse(TemplateBranchComposition(draft).canAddOption("start"))
        for change in [TemplateBranchComposition.Edit.addOption(stepID: "start", optionID: "overflow"), .addOption(stepID: "missing", optionID: "go"), .addOption(stepID: "start", optionID: "option_0")] { XCTAssertNil(TemplateBranchComposition(draft).applying(change, to: draft)) }
    }
    func testTerminalTransitionClearsChoicesAndSuppliesOutcomeFromTitle() throws {
        var draft = try edit(fixture(), .addOption(stepID: "start", optionID: "go"))
        set(&draft, "title", .string("Find the clock")); set(&draft, "outcomeCode", .string("")); set(&draft, "outcomeLabel", .string(""))
        draft = try edit(draft, .terminal("start", true))
        XCTAssertEqual(step(draft)["terminal"], .bool(true)); XCTAssertEqual(step(draft)["options"], .array([]))
        XCTAssertEqual(step(draft)["outcomeCode"], .string("COMPLETED")); XCTAssertEqual(step(draft)["outcomeLabel"], .string("Find the clock"))
    }
    func testOutcomeFallbacksRespectNonemptySourceValuesIncludingWhitespace() throws {
        for title in ["", " "] {
            var draft = fixture(); set(&draft, "title", .string(title)); set(&draft, "outcomeCode", nil); set(&draft, "outcomeLabel", nil)
            let changed = try edit(draft, .terminal("start", true))
            XCTAssertEqual(step(changed)["outcomeLabel"], .string(title.isEmpty ? "完成节点" : title))
        }
        var draft = fixture(); set(&draft, "outcomeCode", .string("CUSTOM")); set(&draft, "outcomeLabel", .string("Existing"))
        let changed = try edit(draft, .terminal("start", true)); XCTAssertEqual(step(changed)["outcomeCode"], .string("CUSTOM")); XCTAssertEqual(step(changed)["outcomeLabel"], .string("Existing"))
    }
    func testTurningOffPreservesOutcomesAndOptionsWithoutInventingChoices() throws {
        let original = fixture(), changed = try edit(original, .terminal("start", false))
        XCTAssertEqual(step(changed)["options"], step(original)["options"])
        XCTAssertEqual(step(changed)["outcomeCode"], step(original)["outcomeCode"])
        XCTAssertEqual(step(changed)["outcomeLabel"], step(original)["outcomeLabel"])
        XCTAssertFalse(changed.creatorIssues(.branch).isEmpty)
    }
    func testUnknownFieldsAndUnrelatedFamiliesSurviveComposition() throws {
        var draft = fixture(); set(&draft, "future", .object(["keep": .number(2)])); draft.set("timer", "enabled", .bool(true))
        let changed = try edit(draft, .addOption(stepID: "start", optionID: "go"))
        XCTAssertEqual(step(changed)["future"], step(draft)["future"]); XCTAssertEqual(changed.value["timer"], draft.value["timer"])
        let terminal = try edit(changed, .terminal("start", true)); XCTAssertEqual(step(terminal)["future"], step(draft)["future"])
        XCTAssertThrowsError(try terminal.serialize()) // Unknown field is preserved, not silently accepted.
    }
    func testMalformedHistoricalDataFallsBackWithoutMutation() {
        var draft = fixture(); let before = draft; _ = TemplateBranchComposition(draft); XCTAssertEqual(draft, before)
        for value in [TemplateAuthoringJSON.string("legacy"), .array([.string("row")]), .array([.object(["id": .string("start"), "terminal": .string("true")])])] {
            draft = fixture(); draft.set("branch", "steps", value); XCTAssertFalse(TemplateBranchComposition(draft).isSupported)
            XCTAssertNil(TemplateBranchComposition(draft).applying(.addStep("new"), to: draft))
        }
    }
    func testSnapshotFencesChangedOrReorderedStepsAndInactiveFamily() throws {
        let draft = try edit(fixture(), .addStep("end")), snapshot = TemplateBranchComposition(draft)
        var changed = draft; changed.moveRow("branch", "steps", from: 0, to: 1)
        XCTAssertNil(snapshot.applying(.terminal("start", true), to: changed))
        changed = draft; changed.setCreatorEnabled(.branch, false)
        XCTAssertFalse(TemplateBranchComposition(changed).canEdit); XCTAssertNil(snapshot.applying(.addStep("more"), to: changed))
    }
    func testCompleteGraphUsesExistingValidationSerializationAndLocalRehearsal() throws {
        var draft = try edit(fixture(), .addStep("end")); draft = try edit(draft, .addOption(stepID: "start", optionID: "go"))
        draft.setCreatorValue(.branch, path: [.field("steps"), .index(0), .field("options"), .index(0), .field("label")], entry: .string("Continue"))
        draft.setCreatorValue(.branch, path: [.field("steps"), .index(0), .field("options"), .index(0), .field("nextStepId")], entry: .string("end"))
        XCTAssertTrue(draft.creatorIssues(.branch).isEmpty)
        let restored = try TemplateAdvancedDraft(raw: draft.serialize()); XCTAssertTrue(restored.creatorIssues(.branch).isEmpty)
        var rehearsal = TemplateCreatorRehearsal(); rehearsal.startBranch(restored); rehearsal.chooseBranch("go", draft: restored)
        XCTAssertEqual(rehearsal.branchStepID, "end"); XCTAssertEqual(rehearsal.result, .matched)
        let terminal = try edit(draft, .terminal("start", true)); XCTAssertTrue(terminal.creatorIssues(.branch).isEmpty)
        let continued = try edit(terminal, .addOption(stepID: "start", optionID: "again")); XCTAssertFalse(continued.creatorIssues(.branch).isEmpty)
    }
    func testLocalDraftRoundTripRetainsTransitionDataAndNoIncomingReferenceRepair() throws {
        var draft = try edit(fixture(), .addStep("end")); draft.set("branch", "startStepId", .string("missing"))
        draft = try edit(draft, .terminal("start", true)); XCTAssertEqual(draft.text("branch", "startStepId"), "missing")
        var local = TemplateAuthoringDraft(title: "Branches"); local.advanced = draft
        XCTAssertEqual(try JSONDecoder().decode(TemplateAuthoringDraft.self, from: JSONEncoder().encode(local)), local)
    }
}

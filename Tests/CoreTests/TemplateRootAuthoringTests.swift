import XCTest
@testable import QuestifyCore

final class TemplateRootAuthoringTests: XCTestCase {
    private func timer(_ seconds: Double = 300) -> TemplateAdvancedDraft { var draft = TemplateAdvancedDraft(); draft.set("timer", "enabled", .bool(true)); draft.set("timer", "durationSeconds", .number(seconds)); return draft }
    private func add(_ draft: inout TemplateAdvancedDraft, path: String = "timer.durationSeconds", operation: String = "+30", condition: [String: TemplateAuthoringJSON] = TemplateAuthorCondition().value) {
        draft.appendRootVariant(); draft.setRootVariant(draft.rootVariants.count - 1, key: "when", entry: .object(condition)); draft.setRootVariant(draft.rootVariants.count - 1, key: "relax", entry: .object([path: .string(operation)]))
    }
    private func d20() -> TemplateAdvancedDraft {
        var draft = TemplateAdvancedDraft(); draft.select(.dice); draft.setDiceMode("d20"); draft.set("diceRoll", "successText", .string("Door opens")); draft.set("diceRoll", "failText", .string("Try the other path")); return draft
    }
    func testRootFeaturesDoNotInflateThirtySevenFamilyRegistry() {
        XCTAssertEqual(TemplateRootCapability.allCases.count, 3)
        XCTAssertEqual(TemplateCreatorFamily.allCases.count, 24)
        XCTAssertEqual(TemplateAdvancedDraft.defaults.count, 38)
    }
    func testAllMistakeTiersRoundtripWithoutEnablingAGame() throws {
        for tier in ["easy", "medium", "hard"] { var draft = TemplateAdvancedDraft(); draft.value["mistakeTier"] = .string(tier); let raw = try draft.serialize(); XCTAssertFalse(raw.isEmpty); XCTAssertEqual(try TemplateAdvancedDraft(raw: raw).serialize(), raw) }
        var draft = TemplateAdvancedDraft(); draft.value["mistakeTier"] = .string("normal"); XCTAssertThrowsError(try draft.serialize())
    }
    func testVariantRoundtripPreservesRuleOrderAndWireStrings() throws {
        var draft = timer(); add(&draft); add(&draft, operation: "+60")
        let raw = try draft.serialize(); let restored = try TemplateAdvancedDraft(raw: raw)
        XCTAssertEqual(try restored.serialize(), raw); XCTAssertEqual(restored.rootVariants[0].object?["relax"]?.object?["timer.durationSeconds"], .string("+30"))
    }
    func testFirstMatchingVariantIsFrozenAndNotStacked() throws {
        var draft = timer(); add(&draft); add(&draft, operation: "+60")
        let result = try draft.rehearsedVariant(sample: .init())
        XCTAssertEqual(result.index, 0); XCTAssertEqual(result.draft.value["timer"]?.object?["durationSeconds"], .number(330)); XCTAssertEqual(draft.value["timer"]?.object?["durationSeconds"], .number(300))
        var state = TemplateRootSampleState(); state.values["sys.hp"] = 8
        XCTAssertNil(try draft.rehearsedVariant(sample: state).index)
    }
    func testIndependentVariantsDoNotIncorrectlyStackAtValidation() {
        var draft = timer(86_350); add(&draft); add(&draft)
        XCTAssertTrue(draft.rootCreatorIssues.isEmpty)
    }
    func testRelaxDirectionAndBoundsAreChecked() {
        for operation in ["-1", "+0", "=1", "+99999", "1", "+1.5"] { var draft = timer(); add(&draft, operation: operation); XCTAssertFalse(draft.rootCreatorIssues.isEmpty, operation) }
        var draft = timer(86_390); add(&draft); XCTAssertTrue(draft.rootCreatorIssues.contains { $0.code == "relaxedBounds" })
    }
    func testAnswersRewardsAndDisabledFieldsCannotBeRelaxed() {
        for key in ["estimate.answer", "qa.xp", "photoCheck.maxTries", "typeIn.seconds"] { var draft = timer(); add(&draft, path: key); XCTAssertFalse(draft.rootCreatorIssues.isEmpty, key) }
    }
    func testAlreadyUnlimitedAttemptsCannotBeRelaxed() {
        var draft = TemplateAdvancedDraft(); draft.select(.stopwatch); draft.set("stopwatch", "tries", .number(0)); add(&draft, path: "stopwatch.tries", operation: "+2")
        XCTAssertFalse(draft.rootCreatorIssues.isEmpty)
        draft.set("stopwatch", "tries", .number(3)); draft.setRootVariant(0, key: "relax", entry: .object(["stopwatch.tries": .string("=0")]))
        XCTAssertTrue(draft.rootCreatorIssues.isEmpty)
    }
    func testLowerRulesMustDecreaseAndRemainInRange() {
        var draft = TemplateAdvancedDraft(); draft.select(.quiet); add(&draft, path: "quietHold.seconds", operation: "-5"); XCTAssertTrue(draft.rootCreatorIssues.isEmpty)
        draft.setRootVariant(0, key: "relax", entry: .object(["quietHold.seconds": .string("+5")])); XCTAssertFalse(draft.rootCreatorIssues.isEmpty)
        draft.setRootVariant(0, key: "relax", entry: .object(["quietHold.seconds": .string("-11")])); XCTAssertFalse(draft.rootCreatorIssues.isEmpty)
    }
    func testUntimedBallCannotReceiveTimerRelaxation() {
        var draft = TemplateAdvancedDraft(); draft.select(.shake); add(&draft, path: "ballShake.seconds", operation: "+5"); XCTAssertFalse(draft.rootCreatorIssues.isEmpty)
        draft.set("ballShake", "timed", .bool(true)); XCTAssertTrue(draft.rootCreatorIssues.isEmpty)
    }
    func testFractionalEstimateToleranceIsNotTruncated() throws {
        var draft = try TemplateAdvancedDraft(raw: #"{"estimate":{"enabled":true,"title":"Count","min":0,"max":100,"answer":50,"tolerance":2.5}}"#)
        add(&draft, path: "estimate.tolerance", operation: "+2")
        let result = try draft.rehearsedVariant(sample: .init()); XCTAssertEqual(result.draft.value["estimate"]?.object?["tolerance"], .number(4.5))
    }
    func testVariantCountAndUnknownExtensionsFailClosedWithoutLoss() throws {
        var draft = timer(); for _ in 0..<17 { draft.appendRootVariant() }; XCTAssertEqual(draft.rootVariants.count, 16)
        draft.value["variants"] = .array([]); add(&draft); draft.setRootVariant(0, key: "future", entry: .string("retain"))
        let saved = try JSONEncoder().encode(draft); let restored = try JSONDecoder().decode(TemplateAdvancedDraft.self, from: saved)
        XCTAssertEqual(restored.rootVariants[0].object?["future"], .string("retain")); XCTAssertThrowsError(try restored.serialize())
    }
    func testConditionWireOperatorsAndWhitelist() {
        for op in ["EQ", "NE", "GT", "GTE", "LT", "LTE"] { XCTAssertTrue(TemplateAuthorCondition(["var": .string("sys.passed.42"), "op": .string(op), "value": .number(1)]).issues.isEmpty) }
        XCTAssertFalse(TemplateAuthorCondition(["var": .string("sys.secret"), "op": .string("LTE"), "value": .number(1)]).issues.isEmpty)
        XCTAssertFalse(TemplateAuthorCondition(["var": .string("sys.hp"), "op": .string("LTE"), "value": .string("")]).issues.isEmpty)
    }
    func testTagsAndCompletedNodesUseExactConditionShape() {
        var sample = TemplateRootSampleState(); sample.tags = ["tag.ready"]; sample.completedNodes = [42]
        XCTAssertTrue(TemplateAuthorCondition(["op": .string("HAS_TAG"), "value": .string("tag.ready")]).matches(sample: sample))
        XCTAssertTrue(TemplateAuthorCondition(["op": .string("NODE_COMPLETED"), "nodeId": .number(42)]).matches(sample: sample))
        XCTAssertFalse(TemplateAuthorCondition(["op": .string("HAS_TAG"), "tag": .string("tag.ready")]).issues.isEmpty)
    }
    func testRoleViewsStableABPairsRoundtripWithoutProviders() throws {
        var draft = TemplateAdvancedDraft(); draft.setRoleViewsEnabled(true)
        let raw = try draft.serialize(); XCTAssertEqual(try TemplateAdvancedDraft(raw: raw).serialize(), raw)
        XCTAssertEqual(Set((draft.value["roleViews"]?.object?["roles"]?.array ?? []).compactMap { $0.object?["id"]?.string }), ["A", "B"])
    }
    func testRoleViewsMustContainExactlyOneViewForEachRole() {
        var draft = TemplateAdvancedDraft(); draft.setRoleViewsEnabled(true)
        draft.set("roleViews", "views", .array([.object(["roleId": .string("A")]), .object(["roleId": .string("A")])]))
        XCTAssertFalse(draft.rootCreatorIssues.isEmpty)
    }
    func testRoleViewItemBoundsAndUnknownPreservation() throws {
        var draft = TemplateAdvancedDraft(); draft.setRoleViewsEnabled(true)
        draft.set("roleViews", "views", .array([.object(["roleId": .string("A"), "items": .array([.object(["label": .string("Clue"), "text": .string(String(repeating: "x", count: 201))])])]), .object(["roleId": .string("B")])]))
        XCTAssertTrue(draft.rootCreatorIssues.contains { $0.code == "text" })
        draft.set("roleViews", "future", .string("retain")); XCTAssertThrowsError(try draft.serialize()); XCTAssertEqual(draft.value["roleViews"]?.object?["future"], .string("retain"))
    }
    func testD20DoesNotRequireSixTasksAndRoundtripsNumbers() throws {
        var draft = d20(); draft.set("diceRoll", "dc", .string("15")); draft.set("diceRoll", "modifier", .string("-2")); draft.set("diceRoll", "rollMode", .string("advantage"))
        XCTAssertTrue(draft.issues.isEmpty)
        let raw = try draft.serialize(); let restored = try TemplateAdvancedDraft(raw: raw)
        XCTAssertEqual(restored.value["diceRoll"]?.object?["dc"], .number(15)); XCTAssertEqual(try restored.serialize(), raw)
    }
    func testD20RejectsBlankFractionalOutOfRangeAndUnknownValues() {
        for (key, value) in [("dc", TemplateAuthoringJSON.string("")), ("dc", .number(1.5)), ("dc", .number(41)), ("modifier", .number(-21)), ("modifier", .string("")), ("rollMode", .string("unknown")), ("successText", .string(""))] {
            var draft = d20(); draft.set("diceRoll", key, value); XCTAssertFalse(draft.issues.isEmpty, key)
        }
    }
    func testD20ModeSwitchRetainsBothSetsOfOwnedFields() throws {
        var draft = d20(); for index in 0..<6 { draft.setFace(index, "Task \(index)") }; draft.setDiceMode("d6"); XCTAssertTrue(draft.issues.isEmpty)
        draft.setDiceMode("d20"); XCTAssertEqual(draft.text("diceRoll", "successText"), "Door opens"); XCTAssertEqual(draft.value["diceRoll"]?.object?["faces"]?.array?.count, 6)
    }
    func testD20SampleIsDeterministicAndNotAServerResult() throws {
        var draft = d20(); draft.set("diceRoll", "dc", .number(15)); draft.set("diceRoll", "modifier", .number(2)); draft.set("diceRoll", "rollMode", .string("disadvantage"))
        let result = try TemplateD20Rehearsal(draft: draft); XCTAssertEqual(result.values, [12, 7]); XCTAssertEqual(result.kept, 7); XCTAssertEqual(result.total, 9); XCTAssertFalse(result.success)
    }
    func testBackendReaction3000AndSevenGameRewardBounds() {
        var draft = TemplateAdvancedDraft(); draft.select(.react); draft.set("reaction", "goalMs", .number(3000)); XCTAssertTrue(draft.issues.isEmpty)
        draft.set("reaction", "goalMs", .number(3001)); XCTAssertFalse(draft.issues.isEmpty)
        for game: TemplateAdvancedGame in [.coin, .dice, .react, .shake, .quiet, .countdown, .stopwatch] {
            var d = TemplateAdvancedDraft(); d.select(game); d.set(game.section, "xp", .number(1001)); XCTAssertTrue(d.legacyVariantIssues.contains { $0.path == game.section + ".xp" })
        }
    }
    func testSortAttemptOperandHasBoundsAndNumericSerialization() throws {
        var draft = try TemplateAdvancedDraft(raw: #"{"sort":{"enabled":true,"prompt":"Order","items":[{"id":"a","label":"A"},{"id":"b","label":"B"}],"answerOrder":["a","b"],"maxAttempts":"3"}}"#)
        add(&draft, path: "sort.maxAttempts", operation: "+2"); XCTAssertTrue(draft.issues.isEmpty)
        let restored = try TemplateAdvancedDraft(raw: draft.serialize()); XCTAssertEqual(restored.value["sort"]?.object?["maxAttempts"], .number(3))
        draft.set("sort", "maxAttempts", .number(11)); XCTAssertFalse(draft.issues.isEmpty)
    }
}

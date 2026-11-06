import XCTest
@testable import QuestifyCore

final class NativeZeroHPAuthorContractTests: XCTestCase {
    private func inputs(templates: [Int: [String: ProjectEditJSON]] = [:],
                        legacy: [String] = ["BLOCK_HP_COST", "THEME_FAIL", "WAIT", "CHALLENGE"],
                        generic: [String] = ["BLOCK_HP_COST", "THEME_FAIL", "WAIT", "CHALLENGE"]) throws -> NativeRuntimeStructureAuthorInputs {
        try .init(matrix: ["schemaVersion": .number(1), "types": .array([]), "addons": .array([]),
                           "constraints": .object([:]), "legacyProofs": .object([:]),
                           "zeroHpPolicies": .object(["legacy": .array(legacy.map(ProjectEditJSON.string)),
                                                     "generic": .array(generic.map(ProjectEditJSON.string))])], templates: templates)
    }
    private func draft(survival: [String: ProjectEditJSON] = [:],
                       themeFields: [String: ProjectEditJSON] = [:]) throws -> ProjectEditDraft {
        var draft = ProjectEditDraft()
        var theme: [String: ProjectEditJSON] = ["schemaVersion": .number(1), "capacity": .number(0)]
        theme.merge(themeFields) { _, next in next }
        theme["gameplayRuntime"] = .object(["survival": .object(survival), "futureRuntime": .string("keep")])
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        draft.preserved["themeRuntimeConfig"] = .string(String(decoding: try encoder.encode(theme), as: UTF8.self))
        draft.preserved["journeyRules"] = .string("{\"schemaVersion\":1,\"stateEnabled\":true,\"hp\":{\"enabled\":true,\"init\":10,\"max\":10}}")
        draft.preserved["unrelated"] = .string("keep exact e\u{301}")
        return draft
    }
    private func waitRow(minutes: ProjectEditJSON = .number(30)) -> [String: ProjectEditJSON] {
        ["version": .number(1), "minutes": minutes, "restoreTo": .number(1), "limit": .number(1), "thenPolicy": .string("THEME_FAIL")]
    }
    func testNoOpPreservesEntireOriginalIncludingAbsentConfiguration() throws {
        for original in [ProjectEditDraft(), try draft()] {
            let editor = try NativeZeroHPAuthorDraft(draft: original)
            XCTAssertTrue(editor.isUnchanged)
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(try editor.applying(to: original, inputs: inputs())),
                           ProjectEditPendingMaterials.exactData(original))
        }
    }
    func testCanonicallyEquivalentReplyIsStillAnExplicitEdit() throws {
        let original = try draft(survival: ["zeroMessage": .string("\u{e9}")])
        var editor = try NativeZeroHPAuthorDraft(draft: original)
        editor.message("e\u{301}")
        XCTAssertFalse(editor.isUnchanged)
        let changed = try editor.applying(to: original, inputs: inputs())
        let reread = try NativeZeroHPAuthorDraft(draft: changed)
        XCTAssertEqual(Array(reread.zeroMessage.utf8), Array("e\u{301}".utf8))
        XCTAssertNotEqual(ProjectEditPendingMaterials.exactData(changed), ProjectEditPendingMaterials.exactData(original))
    }
    func testReplyLimitUsesUTF16AsTheSourceDoes() throws {
        var editor = try NativeZeroHPAuthorDraft(draft: draft())
        editor.message(String(repeating: "😀", count: 1000)); XCTAssertTrue(editor.valueIssues.isEmpty)
        editor.message(String(repeating: "😀", count: 1001)); XCTAssertFalse(editor.valueIssues.isEmpty)
    }
    func testWaitDefaultsAndBoundaryValuesRoundTrip() throws {
        let original = try draft(); var editor = try NativeZeroHPAuthorDraft(draft: original)
        try editor.select(.wait, inputs: inputs())
        XCTAssertEqual(editor.text("minutes"), "30"); XCTAssertEqual(editor.text("restoreTo"), "1")
        XCTAssertEqual(editor.text("limit"), "1"); XCTAssertEqual(editor.text("thenPolicy"), "THEME_FAIL")
        editor.number("minutes", text: "10080"); editor.number("restoreTo", text: "10"); editor.number("limit", text: "99")
        try editor.then(.block)
        let changed = try editor.applying(to: original, inputs: inputs()), reread = try NativeZeroHPAuthorDraft(draft: changed)
        XCTAssertEqual(reread.selected, .wait); XCTAssertEqual(reread.text("minutes"), "10080")
        XCTAssertEqual(reread.text("thenPolicy"), "BLOCK_HP_COST")
        XCTAssertEqual(changed.preserved["journeyRules"], original.preserved["journeyRules"])
        XCTAssertEqual(changed.preserved["unrelated"], original.preserved["unrelated"])
        XCTAssertEqual(reread.theme["gameplayRuntime"]?.object?["futureRuntime"], .string("keep"))
    }
    func testInvalidNumericInputStaysVisibleAndCannotBeApplied() throws {
        for (field, values) in [("minutes", ["", "0", "10081", "1.5", "abc"]),
                                ("restoreTo", ["0", "11"]), ("limit", ["0", "100"])] {
            for value in values {
                let original = try draft(survival: ["zeroHpPolicy": .string("WAIT"), "zeroWait": .object(waitRow())])
                var editor = try NativeZeroHPAuthorDraft(draft: original); editor.number(field, text: value)
                XCTAssertEqual(editor.text(field), value)
                XCTAssertFalse(editor.valueIssues.isEmpty, field + "=" + value)
                XCTAssertThrowsError(try editor.applying(to: original, inputs: inputs()))
            }
        }
    }
    func testPolicyChangeRemovesOnlyOtherRecoveryBlocks() throws {
        let original = try draft(survival: ["zeroHpPolicy": .string("WAIT"), "zeroWait": .object(waitRow()),
                                            "futureSurvival": .string("retain")])
        var editor = try NativeZeroHPAuthorDraft(draft: original); try editor.select(.fail, inputs: inputs())
        let game = editor.proposedTheme["gameplayRuntime"]?.object, survival = game?["survival"]?.object
        XCTAssertNil(survival?["zeroWait"]); XCTAssertNil(survival?["zeroChallenge"]); XCTAssertNil(survival?["zeroSteps"])
        XCTAssertEqual(survival?["futureSurvival"], .string("retain")); XCTAssertEqual(game?["futureRuntime"], .string("keep"))
    }
    func testEmptyReplyIsRemovedAndDefaultBlockRemovesEmptySurvival() throws {
        let original = try draft(survival: ["zeroHpPolicy": .string("BLOCK_HP_COST"), "zeroMessage": .string("remove")])
        var editor = try NativeZeroHPAuthorDraft(draft: original); editor.message("")
        XCTAssertNil(editor.proposedTheme["gameplayRuntime"]?.object?["survival"])
    }
    func testLegacyUnknownAndNativeUnsupportedStepsStayByteExact() throws {
        for policy in ["BLOCK_PAID", "LEGACY_END", "FUTURE", "STEPS", "CHALLENGE"] {
            let original = try draft(survival: ["zeroHpPolicy": .string(policy), "zeroChallenge": .object(["version": .number(1)])])
            var editor = try NativeZeroHPAuthorDraft(draft: original)
            XCTAssertTrue(editor.readOnly, policy); editor.message("must not change")
            XCTAssertThrowsError(try editor.select(.wait, inputs: inputs()))
            XCTAssertEqual(ProjectEditPendingMaterials.exactData(try editor.applying(to: original, inputs: inputs())),
                           ProjectEditPendingMaterials.exactData(original))
        }
    }
    func testNativeStepsCannotBeSelectedEvenWhenMatrixAdvertisesIt() throws {
        var editor = try NativeZeroHPAuthorDraft(draft: draft())
        let advertised = try inputs(legacy: ["STEPS"], generic: ["STEPS"])
        XCTAssertNotNil(NativeZeroHPAuthorPolicy.reason(.steps, draft: editor, inputs: advertised))
        XCTAssertThrowsError(try editor.select(.steps, inputs: advertised))
    }
    func testMalformedOriginalIsNotReplacedWithDefaults() {
        for text in ["{", "[]", "{\"schemaVersion\":1,\"gameplayRuntime\":false}",
                     "{\"schemaVersion\":1,\"gameplayRuntime\":{\"survival\":{\"zeroHpPolicy\":7}}}"] {
            var original = ProjectEditDraft(); original.preserved["themeRuntimeConfig"] = .string(text)
            XCTAssertThrowsError(try NativeZeroHPAuthorDraft(draft: original))
            XCTAssertEqual(original.preserved["themeRuntimeConfig"], .string(text))
        }
    }
    func testChangedPreimageIncludingUnicodeSpellingRejectsApply() throws {
        let original = try draft(); var editor = try NativeZeroHPAuthorDraft(draft: original)
        try editor.select(.wait, inputs: inputs())
        var changed = original; changed.preserved["unrelated"] = .string("keep exact \u{e9}")
        XCTAssertThrowsError(try editor.applying(to: changed, inputs: inputs()))
        changed = original; changed.baseRevision = "new revision"
        XCTAssertThrowsError(try editor.applying(to: changed, inputs: inputs()))
    }
    func testUnreadableBoundTemplateCannotChooseLegacyPolicies() throws {
        var original = try draft(); var node = ProjectEditNode(); node.templateID = 41
        var chapter = ProjectEditChapter(); chapter.nodes = [node]; original.chapters = [chapter]
        var editor = try NativeZeroHPAuthorDraft(draft: original)
        XCTAssertTrue(NativeZeroHPAuthorPolicy.policyKeys(draft: editor, inputs: try inputs()).isEmpty)
        XCTAssertThrowsError(try editor.select(.wait, inputs: inputs()))
        let bad = try inputs(templates: [41: ["id": .number(41), "advancedConfigJson": .string("{")]])
        XCTAssertTrue(NativeZeroHPAuthorPolicy.policyKeys(draft: editor, inputs: bad).isEmpty)
        XCTAssertThrowsError(try editor.select(.wait, inputs: bad))
    }
    func testStructuredThemeUsesGenericPolicyList() throws {
        let original = try draft(themeFields: ["chapters": .array([.object(["completion": .object([:])])])])
        let editor = try NativeZeroHPAuthorDraft(draft: original)
        let source = try inputs(legacy: ["THEME_FAIL"], generic: ["WAIT"])
        XCTAssertEqual(NativeZeroHPAuthorPolicy.policyKeys(draft: editor, inputs: source), ["WAIT"])
    }
    func testChallengeLimitsAndMissingNodeAreBlocked() throws {
        let original = try draft(); var editor = try NativeZeroHPAuthorDraft(draft: original)
        try editor.select(.challenge, inputs: inputs())
        editor.number("requiredCompletions", text: "100"); editor.number("withinSeconds", text: "86401")
        XCTAssertFalse(editor.valueIssues.isEmpty)
        XCTAssertThrowsError(try editor.main(nodeID: 999, inputs: inputs()))
        XCTAssertThrowsError(try editor.alternative(nodeID: 999, selected: true, inputs: inputs()))
        XCTAssertThrowsError(try editor.applying(to: original, inputs: inputs()))
    }
    func testChallengeSelectionRequiresSavedDistinctNodesAndAnswerableSensorAlternative() throws {
        var original = try draft()
        var main = ProjectEditNode(); main.templateID = 41; main.localMetadata["id"] = .number(101)
        var alternative = ProjectEditNode(); alternative.templateID = 42; alternative.localMetadata["id"] = .number(102)
        var chapter = ProjectEditChapter(); chapter.nodes = [main, alternative]; original.chapters = [chapter]
        let types: [ProjectEditJSON] = [
            .object(["key": .string("reaction"), "section": .string("reaction"), "completionProof": .bool(false),
                     "tools": .object(["zeroChallenge": .string("CHALLENGE_ONLY")])]),
            .object(["key": .string("typeIn"), "section": .string("typeIn"), "completionProof": .bool(true),
                     "tools": .object(["zeroChallenge": .string("SUPPORTED")])])
        ]
        let source = try NativeRuntimeStructureAuthorInputs(matrix: ["schemaVersion": .number(1), "types": .array(types),
            "addons": .array([]), "constraints": .object([:]), "legacyProofs": .object([:]),
            "zeroHpPolicies": .object(["legacy": .array([.string("CHALLENGE")]), "generic": .array([.string("CHALLENGE")])])],
            templates: [41: ["id": .number(41), "advancedConfigJson": .string("{\"reaction\":{\"enabled\":true}}")],
                        42: ["id": .number(42), "advancedConfigJson": .string("{\"typeIn\":{\"enabled\":true}}")]])
        var editor = try NativeZeroHPAuthorDraft(draft: original); try editor.select(.challenge, inputs: source)
        try editor.main(nodeID: 101, inputs: source)
        XCTAssertEqual(editor.challenge["gameplayKey"], .string("reaction"))
        XCTAssertFalse(NativeZeroHPAuthorPolicy.challengeIssues(draft: editor, inputs: source).isEmpty)
        XCTAssertThrowsError(try editor.alternative(nodeID: 101, selected: true, inputs: source))
        try editor.alternative(nodeID: 102, selected: true, inputs: source)
        XCTAssertTrue(NativeZeroHPAuthorPolicy.challengeIssues(draft: editor, inputs: source).isEmpty)
        let reread = try NativeZeroHPAuthorDraft(draft: editor.applying(to: original, inputs: source))
        XCTAssertEqual(reread.alternatives, [102]); XCTAssertEqual(reread.challenge["challengeNodeId"], .number(101))
        try editor.alternative(nodeID: 102, selected: false, inputs: source)
        XCTAssertThrowsError(try editor.applying(to: original, inputs: source))
    }
    func testSubmissionRechecksCurrentHpMaximum() throws {
        var original = try draft(survival: ["zeroHpPolicy": .string("WAIT"), "zeroWait": .object(waitRow())])
        var editor = try NativeZeroHPAuthorDraft(draft: original); editor.number("restoreTo", text: "10")
        original = try editor.applying(to: original, inputs: inputs())
        original.preserved["journeyRules"] = .string("{\"schemaVersion\":1,\"stateEnabled\":true,\"hp\":{\"enabled\":true,\"init\":5,\"max\":5}}")
        XCTAssertThrowsError(try NativeZeroHPAuthorDraft.validateOriginalSubmission(original))
    }
    func testSchemaTwoHpUsesExplicitResourceDeclarationWithoutDowngrade() throws {
        var original = try draft()
        original.preserved["journeyRules"] = .string("{\"schemaVersion\":2,\"hp\":{\"enabled\":true,\"init\":4,\"max\":8}}")
        var editor = try NativeZeroHPAuthorDraft(draft: original); try editor.select(.wait, inputs: inputs())
        XCTAssertEqual(editor.hp.maximum, "8"); editor.number("restoreTo", text: "8")
        let changed = try editor.applying(to: original, inputs: inputs())
        XCTAssertEqual(changed.preserved["journeyRules"], original.preserved["journeyRules"])
        editor.number("restoreTo", text: "9"); XCTAssertThrowsError(try editor.applying(to: original, inputs: inputs()))
        original.preserved["journeyRules"] = .string("{\"schemaVersion\":2,\"hp\":{\"enabled\":true}}")
        editor = try .init(draft: original); try editor.select(.wait, inputs: inputs())
        XCTAssertFalse(editor.valueIssues.isEmpty)
        XCTAssertThrowsError(try editor.applying(to: original, inputs: inputs()))
    }
}

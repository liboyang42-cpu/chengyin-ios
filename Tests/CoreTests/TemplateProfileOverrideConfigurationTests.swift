import XCTest
@testable import QuestifyCore

final class TemplateProfileOverrideConfigurationTests: XCTestCase {
    private func draft() -> TemplateAuthoringDraft {
        var d = TemplateAuthoringDraft(title: "Profile override")
        d.advanced.set("profile","enabled",.bool(true))
        let effect: TemplateAuthoringJSON = .object(["op": .string("INC"), "var": .string("counter.focus"), "value": .number(1)])
        let options: [TemplateAuthoringJSON] = [
            .object(["key": .string("A"), "label": .string("旅人"), "effects": .array([])]),
            .object(["key": .string("B"), "label": .string("守门人"), "effects": .array([effect])])
        ]
        d.advanced.set("profile", "questions", .array([
            .object(["key": .string("role"), "kind": .string("pick"), "label": .string("想当什么？"), "required": .bool(true), "future": .string("keep"), "options": .array(options)]),
            .object(["key": .string("name"), "kind": .string("text"), "label": .string("名字"), "maxLength": .number(12), "required": .bool(true)])
        ]))
        return d
    }
    private func config(_ d: TemplateAuthoringDraft) -> TemplateProfileOverrideConfiguration { .init(d,questionKey:"role") }
    private func override(_ d: TemplateAuthoringDraft) -> TemplateAuthoringJSON? { d.advanced.rows("profile","questions")[0].object?["override"] }
    private func replacing(_ d: TemplateAuthoringDraft, _ raw: TemplateAuthoringJSON?) -> TemplateAuthoringDraft {
        var d = d, rows = d.advanced.rows("profile","questions"), first = rows[0].object!; first["override"] = raw; rows[0] = .object(first); d.advanced.set("profile","questions",.array(rows)); return d
    }
    private var expected: TemplateAuthoringJSON { .object(["requires":.array([.object(["op":.string("GTE"),"var":.string("counter.instability"),"value":.number(4)])]),"option":.string("A")]) }
    func testAbsentAndNullReadsHaveDefaultsWithoutWriting() {
        for d in [draft(),replacing(draft(),.null)] {
            let before = TemplateProfileOverrideConfiguration.snapshot(d), c = config(d)
            XCTAssertTrue(c.canEdit); XCTAssertFalse(c.initialForm.enabled); XCTAssertEqual(c.initialForm.variable,"counter.instability"); XCTAssertEqual(c.initialForm.threshold,"4"); XCTAssertEqual(c.initialForm.option,"A")
            XCTAssertEqual(TemplateProfileOverrideConfiguration.snapshot(d),before); XCTAssertNil(c.applying(c.initialForm,to:d))
        }
    }
    func testEnableProducesExactSingleGTEBackendOverride() throws {
        let d = draft(), c = config(d), form = c.toggling(c.initialForm,enabled:true)
        XCTAssertEqual(override(try XCTUnwrap(c.applying(form,to:d))),expected)
    }
    func testOptionAndVoiceTrimOnlyOnExplicitApplyAndPlaceholdersRemainLiteral() throws {
        let d = draft(), c = config(d); var f = c.toggling(c.initialForm,enabled:true)
        f.variable = " counter.focus "; f.threshold = " 5 "; f.option = " B "; f.voice = " 你想当{picked}，表格写的是{assigned}。 "
        let next = try XCTUnwrap(c.applying(f,to:d)), row = try XCTUnwrap(override(next)?.object)
        XCTAssertEqual(row["option"],.string("B")); XCTAssertEqual(row["voice"],.string("你想当{picked}，表格写的是{assigned}。")); XCTAssertNil(override(d))
    }
    func testDisableRemovesOnlyOverrideNeverPersistsKacchaEditorFields() throws {
        let d = replacing(draft(),expected), c = config(d); let next = try XCTUnwrap(c.applying(c.toggling(c.initialForm,enabled:false),to:d))
        XCTAssertNil(override(next)); XCTAssertEqual(next,draft()); XCTAssertNil(next.advanced.rows("profile","questions")[0].object?["kaccha"])
    }
    func testToggleRetainsInactiveFormValuesAndFirstOptionFallback() {
        let c = config(draft()); var f = c.initialForm; f.variable = "counter.focus"; f.threshold = "9"; f.option = "B"; f.voice = "Keep"
        f = c.toggling(f,enabled:true); f = c.toggling(f,enabled:false); f = c.toggling(f,enabled:true)
        XCTAssertEqual(f.variable,"counter.focus"); XCTAssertEqual(f.threshold,"9"); XCTAssertEqual(f.option,"B"); XCTAssertEqual(f.voice,"Keep")
        f.option = ""; XCTAssertEqual(c.toggling(f,enabled:true).option,"A")
    }
    func testOnlySelectedQuestionOverrideChangesIncludingEffectsAndFutureFields() throws {
        var d = draft(); d.advanced.set("timer","timeoutResult",.string("EXPIRED")); d.advanced.value["variants"] = .array([.object(["future":.bool(true)])])
        let c = config(d), next = try XCTUnwrap(c.applying(c.toggling(c.initialForm,enabled:true),to:d)), target = replacing(d,expected)
        XCTAssertEqual(TemplateProfileOverrideConfiguration.snapshot(next),TemplateProfileOverrideConfiguration.snapshot(target))
    }
    func testComplexMultipleConditionsStayReadOnlyAndCannotBeDisabled() throws {
        var raw = try XCTUnwrap(expected.object); raw["requires"] = .array([.object(["var":.string("counter.a"),"op":.string("GTE"),"value":.number(1)]),.object(["var":.string("counter.b"),"op":.string("GTE"),"value":.number(2)])])
        let d = replacing(draft(),.object(raw)), c = config(d); XCTAssertFalse(c.isSupported); XCTAssertNil(c.applying(.init(enabled:false),to:d)); XCTAssertEqual(override(d),.object(raw))
    }
    func testOtherOperatorAndMalformedRequiresNeverFlattened() {
        for raw in [TemplateAuthoringJSON.object(["requires":.array([.object(["var":.string("counter.a"),"op":.string("EQ"),"value":.number(1)])]),"option":.string("A")]),.object(["option":.string("A")]),.string("future")] {
            let d = replacing(draft(),raw); XCTAssertFalse(config(d).isSupported); XCTAssertEqual(override(d),raw)
        }
    }
    func testUnknownOverrideAndConditionFieldsArePreservedReadOnly() throws {
        var raw = try XCTUnwrap(expected.object); raw["future"] = .bool(true); XCTAssertFalse(config(replacing(draft(),.object(raw))).isSupported)
        raw = try XCTUnwrap(expected.object); var when = try XCTUnwrap(raw["requires"]?.array?.first?.object); when["future"] = .bool(true); raw["requires"] = .array([.object(when)])
        XCTAssertFalse(config(replacing(draft(),.object(raw))).isSupported)
    }
    func testMalformedAndDisabledProfileFlagsCannotEnableTheModule() {
        for value in [TemplateAuthoringJSON.bool(false),.string("true"),.number(1),.null] {
            var d = draft(); d.advanced.set("profile","enabled",value); let c = config(d)
            XCTAssertFalse(c.canEdit); XCTAssertNil(c.applying(c.toggling(c.initialForm,enabled:true),to:d)); XCTAssertEqual(d.advanced.value["profile"]?.object?["enabled"],value)
        }
    }
    func testTextAndMissingQuestionAreNotGuidedTargets() {
        let d = draft(); XCTAssertFalse(TemplateProfileOverrideConfiguration(d,questionKey:"name").isSupported); XCTAssertFalse(TemplateProfileOverrideConfiguration(d,questionKey:"missing").isSupported)
    }
    func testMissingOptionReferenceAndDuplicateOptionKeysBlockApply() throws {
        let d = draft(), c = config(d); var f = c.toggling(c.initialForm,enabled:true); f.option = "missing"; XCTAssertTrue(c.issueKeys(f).contains("templateProfileOverride.optionInvalid")); XCTAssertNil(c.applying(f,to:d))
        var changed = d, rows = changed.advanced.rows("profile","questions"), row = try XCTUnwrap(rows[0].object), options = try XCTUnwrap(row["options"]?.array); options[1] = options[0]; row["options"] = .array(options); rows[0] = .object(row); changed.advanced.set("profile","questions",.array(rows)); XCTAssertFalse(config(changed).isSupported)
    }
    func testVariableNamespaceUsesSourcePrefixNotAllGenericConditions() {
        let c = config(draft()); var f = c.toggling(c.initialForm,enabled:true)
        for value in ["clue.bridge","relation.friend","counter.instability"] { f.variable = value; XCTAssertFalse(c.issueKeys(f).contains("templateProfileOverride.variableInvalid")) }
        for value in ["sys.luck","tag.friend","counter.UP","counter.a-b","counter.1a"] { f.variable = value; XCTAssertTrue(c.issueKeys(f).contains("templateProfileOverride.variableInvalid")) }
    }
    func testIntegerThresholdUsesSourceConversionAndExistingNativeBounds() throws {
        let d = draft(), c = config(d); var f = c.toggling(c.initialForm,enabled:true)
        for value in ["-99","0","99",""] { f.threshold = value; XCTAssertTrue(c.issueKeys(f).isEmpty,value); XCTAssertNotNil(c.prepared(f,to:d)) }
        for value in ["-100","100","4.5","oops","inf","nan"] { f.threshold = value; XCTAssertTrue(c.issueKeys(f).contains("templateProfileOverride.thresholdInvalid"),value); XCTAssertNil(c.prepared(f,to:d)) }
    }
    func testVoiceLimitUsesUTF16AfterSourceTrim() {
        let c = config(draft()); var f = c.toggling(c.initialForm,enabled:true); f.voice = " " + String(repeating:"😀",count:60) + " "
        XCTAssertTrue(c.issueKeys(f).isEmpty); f.voice = String(repeating:"😀",count:61); XCTAssertTrue(c.issueKeys(f).contains("templateProfileOverride.voiceInvalid"))
    }
    func testRawNumericStringReadDoesNotNormalizeUntilApply() throws {
        var raw = try XCTUnwrap(expected.object); raw["requires"] = .array([.object(["op":.string("GTE"),"var":.string("counter.instability"),"value":.string("004")])])
        let d = replacing(draft(),.object(raw)), before = TemplateProfileOverrideConfiguration.snapshot(d), c = config(d)
        XCTAssertEqual(c.initialForm.threshold,"004"); XCTAssertEqual(TemplateProfileOverrideConfiguration.snapshot(d),before); XCTAssertEqual(override(try XCTUnwrap(c.applying(c.initialForm,to:d))),expected)
    }
    func testIdenticalApplyIsNoOpButExplicitSaveCandidateAvailable() {
        let d = replacing(draft(),expected), c = config(d); XCTAssertNil(c.applying(c.initialForm,to:d)); XCTAssertEqual(c.prepared(c.initialForm,to:d),d)
    }
    func testReorderDeleteKindOrOptionChangeRejectsCapturedConfiguration() {
        let d = draft(), c = config(d), f = c.toggling(c.initialForm,enabled:true)
        for action in ["reorder","delete","kind","option"] {
            var next = d, rows = d.advanced.rows("profile","questions")
            switch action { case "reorder": rows.reverse(); case "delete": rows.removeFirst(); default: var row = rows[0].object!; if action == "kind" { row["kind"] = .string("text") } else { row["options"] = .array([]) }; rows[0] = .object(row) }
            next.advanced.set("profile","questions",.array(rows)); XCTAssertNil(c.prepared(f,to:next),action)
        }
    }
    func testWholeDraftUnicodeAndNonfiniteValuesFailClosed() {
        var d = draft(); d.title = "\u{00E9}"; let c = config(d); d.title = "e\u{0301}"; XCTAssertNil(c.prepared(c.toggling(c.initialForm,enabled:true),to:d))
        d.advanced.value["future"] = .number(.nan); XCTAssertFalse(config(d).isSupported)
    }
    func testKnownShapeInvalidFieldsCanBeExplicitlyCorrectedWithoutSilentReadRepair() throws {
        var raw = try XCTUnwrap(expected.object); raw["option"] = .string("missing"); raw["requires"] = .array([.object(["op":.string("GTE"),"var":.string("bad"),"value":.string("oops")])])
        let d = replacing(draft(),.object(raw)), c = config(d); XCTAssertTrue(c.isSupported); XCTAssertFalse(c.issueKeys(c.initialForm).isEmpty); XCTAssertEqual(override(d),.object(raw))
        var f = c.initialForm; f.variable = "counter.instability"; f.threshold = "4"; f.option = "A"; XCTAssertEqual(override(try XCTUnwrap(c.applying(f,to:d))),expected)
    }
}

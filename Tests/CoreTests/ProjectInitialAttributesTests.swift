import XCTest
@testable import QuestifyCore

final class ProjectInitialAttributesTests: XCTestCase {
    private func object(_ raw: ProjectEditJSON?) throws -> [String: ProjectEditJSON] {
        let text = try XCTUnwrap(raw?.text)
        return try JSONDecoder().decode([String: ProjectEditJSON].self, from: Data(text.utf8))
    }
    private func exact(_ value: ProjectEditJSON?) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(value.map { ["raw": $0] } ?? [:])
    }
    private func add(_ state: inout ProjectInitialAttributes, key: String = "counter.score", label: String = "Score") throws -> UUID {
        let id = try XCTUnwrap(state.add()); var row = try XCTUnwrap(state.rows.first { $0.id == id })
        row.key = key; row.label = label; XCTAssertTrue(state.replace(row)); return id
    }
    func testNoOpPreservesMissingNullEmptyAndOriginalBytes() throws {
        let sources: [ProjectEditJSON?] = [nil, .null, .string(""), .string(" \n"), .string(" {} "), .string(" {\"schemaVersion\":1,\"attributes\":[],\"future\":\"e\\u0301\"} ")]
        for raw in sources {
            let state = ProjectInitialAttributes(raw: raw); XCTAssertFalse(state.readOnly)
            XCTAssertEqual(try exact(state.serialized(matching: raw)), try exact(raw))
        }
    }
    func testAddingAttributeDoesNotEnableStateOrTouchChecksAndOtherRules() throws {
        let raw: ProjectEditJSON = .string(#"{"schemaVersion":1,"checkEnabled":false,"stateEnabled":false,"hp":{"init":4,"future":"e\u0301"},"luck":{"enabled":false},"thoughts":[{"key":"pending","future":[1,2]}],"future":{"nested":true}}"#)
        var state = ProjectInitialAttributes(raw: raw); _ = try add(&state)
        let next = try object(state.serialized(matching: raw)), old = try object(raw)
        for key in ["checkEnabled", "stateEnabled", "hp", "luck", "thoughts", "future"] { XCTAssertEqual(try exact(next[key]), try exact(old[key])) }
        XCTAssertEqual(next["attributes"]?.array?.count, 1)
    }
    func testFreshAttributeAddsOnlySchemaAndDeclarations() throws {
        var state = ProjectInitialAttributes(raw: nil); _ = try add(&state)
        let next = try object(state.serialized(matching: nil))
        XCTAssertEqual(Set(next.keys), ["schemaVersion", "attributes"]); XCTAssertEqual(next["schemaVersion"], .number(1))
    }
    func testOnlyExplicitStateToggleChangesExistingFlag() throws {
        let raw: ProjectEditJSON = .string(#"{"schemaVersion":1,"checkEnabled":true,"attributes":[]}"#)
        var state = ProjectInitialAttributes(raw: raw); state.setStateEnabled(true)
        let next = try object(state.serialized(matching: raw)); XCTAssertEqual(next["stateEnabled"], .bool(true)); XCTAssertEqual(next["checkEnabled"], .bool(true))
        state.setStateEnabled(false); XCTAssertEqual(try exact(state.serialized(matching: raw)), try exact(raw))
    }
    func testEnableOnlyDoesNotCreateAttributesOrHPDefaults() throws {
        var state = ProjectInitialAttributes(raw: nil); state.setStateEnabled(true)
        let next = try object(state.serialized(matching: nil)); XCTAssertEqual(Set(next.keys), ["schemaVersion", "stateEnabled"])
    }
    func testExistingKeyCannotRenameAndUnknownRowFieldsSurvive() throws {
        let raw: ProjectEditJSON = .string(#"{"schemaVersion":1,"attributes":[{"key":"relation.friend","label":"Friend","future":{"x":"e\u0301"}}]}"#)
        var state = ProjectInitialAttributes(raw: raw); var row = try XCTUnwrap(state.rows.first)
        row.key = "relation.enemy"; XCTAssertFalse(state.replace(row)); row.key = "relation.friend"; row.label = "Ally"; row.visible = false
        XCTAssertTrue(state.replace(row)); let fields = try XCTUnwrap(object(state.serialized(matching: raw))["attributes"]?.array?.first?.object)
        XCTAssertEqual(fields["key"], .string("relation.friend")); XCTAssertEqual(fields["visible"], .bool(false))
        XCTAssertNil(fields["min"]); XCTAssertNil(fields["max"]); XCTAssertNil(fields["initial"])
        XCTAssertEqual(try exact(fields["future"]), try exact(object(raw)["attributes"]?.array?.first?.object?["future"]))
    }
    func testNumericNoOpAndRevertedChangesDoNotNormalizeRaw() throws {
        let raw: ProjectEditJSON = .string(" { \"schemaVersion\":1,\"attributes\":[{\"key\":\"counter.a\",\"label\":\"A\"}]} ")
        var state = ProjectInitialAttributes(raw: raw); var row = try XCTUnwrap(state.rows.first); row.initial = "000"; row.minimum = "-010000"
        XCTAssertTrue(state.replace(row)); XCTAssertTrue(state.isUnchanged); XCTAssertEqual(try exact(state.serialized(matching: raw)), try exact(raw))
        let id = try add(&state, key: "counter.b"); XCTAssertTrue(state.remove(id)); XCTAssertTrue(state.isUnchanged)
    }
    func testDuplicateKeysAndThirtyThirdDeclarationAreRejected() throws {
        var state = ProjectInitialAttributes(raw: nil)
        for index in 0..<32 { _ = try add(&state, key: "counter.k\(index)") }
        XCTAssertNil(state.add()); XCTAssertTrue(state.isValid)
        var last = try XCTUnwrap(state.rows.last); last.key = "counter.k0"; XCTAssertTrue(state.replace(last)); XCTAssertFalse(state.isValid)
        XCTAssertThrowsError(try state.serialized(matching: nil))
    }
    func testFlagBoundsAreExactlyZeroAndOne() throws {
        for key in ["clue.found", "tag.accepted"] {
            var state = ProjectInitialAttributes(raw: nil); let id = try add(&state, key: key)
            var row = try XCTUnwrap(state.rows.first { $0.id == id }); row.minimum = "0"; row.maximum = "1"; row.initial = "1"
            XCTAssertTrue(state.replace(row)); XCTAssertTrue(state.isValid)
            row.initial = "2"; XCTAssertTrue(state.replace(row)); XCTAssertFalse(state.isValid)
            row.initial = "1"; row.maximum = "2"; XCTAssertTrue(state.replace(row)); XCTAssertFalse(state.isValid)
        }
    }
    func testSignedIntegerRangeAndInitialContainment() throws {
        for values in [("-10000","-10000","10000",true),("10000","-10000","10000",true),("0","-10001","10000",false),("0","-10000","10001",false),("3","0","2",false),("0","2","1",false),("1.0","0","2",false),("+1","0","2",false),("1e0","0","2",false)] {
            var state = ProjectInitialAttributes(raw: nil); _ = try add(&state); var row = try XCTUnwrap(state.rows.first)
            row.initial = values.0; row.minimum = values.1; row.maximum = values.2; XCTAssertTrue(state.replace(row)); XCTAssertEqual(state.isValid, values.3)
        }
    }
    func testLabelUsesJavaTrimAndUTF16BoundsWithoutTruncatingInput() throws {
        for pair in [(String(repeating: "😀", count: 12),true),(String(repeating: "😀", count: 12)+"x",false),("\u{00A0}",true),(" \u{0000}\n",false)] {
            var state = ProjectInitialAttributes(raw: nil); _ = try add(&state, label: pair.0)
            XCTAssertEqual(state.rows[0].label, pair.0); XCTAssertEqual(state.isValid, pair.1)
        }
    }
    func testKeyVocabularyIsExactAndDoesNotTrimOrAcceptNewline() throws {
        for key in ["counter.a\n", " counter.a", "Counter.a", "counter.A", "score.a", "counter."+String(repeating:"a",count:49)] {
            var state = ProjectInitialAttributes(raw: nil); _ = try add(&state, key: key); XCTAssertFalse(state.isValid, key)
        }
    }
    func testMalformedUnsupportedNullAndWrongKnownTypesAreReadOnly() {
        for text in ["[]", "bad", #"{"schemaVersion":2}"#, #"{"future":true}"#, #"{"schemaVersion":1,"attributes":null}"#, #"{"schemaVersion":1,"attributes":[{"key":"counter.a","label":"A","initial":null}]}"#, #"{"schemaVersion":1,"attributes":[{"key":"counter.a","label":"A","visible":null}]}"#, #"{"schemaVersion":1,"attributes":[{"key":"counter.a","label":"A","initial":true}]}"#, #"{"schemaVersion":1,"attributes":[],"attributes":[]}"#] {
            XCTAssertTrue(ProjectInitialAttributes(raw: .string(text)).readOnly, text)
        }
    }
    func testImportedFloatingOrExponentAttributeTokensCannotBeSilentlyRepaired() {
        for number in ["1.0", "1e0", "-0.0", "2147483648"] {
            let raw = "{\"schemaVersion\":1,\"attributes\":[{\"key\":\"counter.a\",\"label\":\"A\",\"initial\":\(number)}]}"
            XCTAssertTrue(ProjectInitialAttributes(raw: .string(raw)).readOnly, number)
        }
        XCTAssertFalse(ProjectInitialAttributes(raw: .string(#"{"schemaVersion":1,"future":{"initial":1.0},"attributes":[{"key":"counter.a","label":"A","initial":1}]}"#)).readOnly)
    }
    func testCanonicalEquivalentUnknownKeysCannotCollapseOnEdit() {
        let raw = "{\"schemaVersion\":1,\"future\":{\"é\":1,\"e\u{301}\":2}}"
        XCTAssertTrue(ProjectInitialAttributes(raw: .string(raw)).readOnly)
    }
    func testExactSourceBindingRejectsCanonicalEquivalentForeignDraft() throws {
        let raw: ProjectEditJSON = .string("{\"schemaVersion\":1,\"future\":\"e\u{301}\"}")
        var state = ProjectInitialAttributes(raw: raw); _ = try add(&state)
        XCTAssertThrowsError(try state.serialized(matching: .string("{\"schemaVersion\":1,\"future\":\"é\"}")))
    }
    func testRemovingDeclarationKeepsDependenciesAndStateFlag() throws {
        let raw: ProjectEditJSON = .string(#"{"schemaVersion":1,"stateEnabled":true,"attributes":[{"key":"tag.ready","label":"Ready"}],"thoughts":[{"when":[{"op":"HAS_TAG","value":"tag.ready"}]}],"recovery":{"exhaustTag":"tag.ready"}}"#)
        var state = ProjectInitialAttributes(raw: raw); XCTAssertTrue(state.remove(try XCTUnwrap(state.rows.first?.id)))
        let next = try object(state.serialized(matching: raw)), before = try object(raw)
        XCTAssertEqual(next["attributes"], .array([])); XCTAssertEqual(next["stateEnabled"], .bool(true))
        for key in ["thoughts", "recovery"] { XCTAssertEqual(try exact(next[key]), try exact(before[key])) }
    }
    func testOversizeSourceAndOversizeEditedRulesFailClosed() throws {
        XCTAssertTrue(ProjectInitialAttributes(raw: .string(String(repeating:"x",count:16385))).readOnly)
        let raw: ProjectEditJSON = .string("{\"schemaVersion\":1,\"future\":\""+String(repeating:"x",count:16280)+"\"}")
        var state = ProjectInitialAttributes(raw: raw); XCTAssertFalse(state.readOnly); _ = try add(&state)
        XCTAssertThrowsError(try state.serialized(matching: raw))
    }
}

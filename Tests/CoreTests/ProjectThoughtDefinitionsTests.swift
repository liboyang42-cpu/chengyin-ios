import XCTest
@testable import QuestifyCore

final class ProjectThoughtDefinitionsTests: XCTestCase {
    private func draft(_ raw: ProjectEditJSON? = nil) -> ProjectEditDraft {
        var draft = ProjectEditSyntheticFixtures.draft(); draft.preserved["journeyRules"] = raw; return draft
    }
    private func object(_ raw: ProjectEditJSON?) throws -> [String: ProjectEditJSON] {
        try ApprovedTopicReleaseWire.envelope(Data(try XCTUnwrap(raw?.text).utf8))
    }
    func testNoOpKeepsOriginalBytesAndFreshThoughtsDoNotEnableNumericalState() throws {
        let raw: ProjectEditJSON = .string(" { \"schemaVersion\" : 1, \"future\" : \"e\\u0301\" } ")
        let unchanged = ProjectThoughtDefinitions(raw: raw, draft: draft(raw))
        XCTAssertEqual(Array(try XCTUnwrap(unchanged.serialized(matching: raw)?.text).utf8), Array(try XCTUnwrap(raw.text).utf8))
        var fresh = ProjectThoughtDefinitions(raw: nil, draft: draft()); XCTAssertTrue(fresh.add(key: "tfirst")); fresh.rows[0].name = "First"
        let root = try object(fresh.serialized(matching: nil))
        XCTAssertEqual(root["stateEnabled"], .bool(false)); XCTAssertEqual(root["hp"]?.object?["enabled"], .bool(false))
        XCTAssertEqual(root["luck"]?.object?["enabled"], .bool(false)); XCTAssertEqual(root["thoughts"]?.array?[0].object?["need"], .number(120))
    }
    func testNamesUseUTF16LimitsAndFulfilmentNeedsStepsOrConditions() throws {
        var value = ProjectThoughtDefinitions(raw: nil, draft: draft()); _ = value.add(key: "tfirst")
        value.rows[0].name = String(repeating: "😀", count: 10); value.rows[0].summary = String(repeating: "😀", count: 30)
        XCTAssertNotNil(try value.serialized(matching: nil))
        value.rows[0].name += "a"; XCTAssertThrowsError(try value.serialized(matching: nil)); value.rows[0].name = "First"
        value.rows[0].need = ""; XCTAssertThrowsError(try value.serialized(matching: nil))
        value.rows[0].doneTags = ["tag.guessed"]; XCTAssertThrowsError(try value.serialized(matching: nil))
        var actual = draft(); actual.chapters[0].nodes[0].localMetadata["templateInfo"] = .object(["id": .number(41),
            "advancedConfigJson": .string(#"{"schemaVersion":1,"effects":[{"op":"ADD_TAG","value":"tag.real"}]}"#)])
        var choices = ProjectThoughtDefinitions(raw: nil, draft: actual); _ = choices.add(key: "tfirst")
        choices.rows[0].name = "First"; choices.rows[0].need = ""; choices.rows[0].doneTags = ["tag.real"]
        XCTAssertNotNil(try choices.serialized(matching: nil))
        choices.rows[0].need = "100001"; XCTAssertThrowsError(try choices.serialized(matching: nil))
    }
    func testKnownNodeConditionsAndUnknownFieldsSurviveAnExplicitNameEdit() throws {
        let raw: ProjectEditJSON = .string(#"{"schemaVersion":1,"stateEnabled":false,"future":{"x":"keep"},"thoughts":[{"key":"tfirst","name":"Before","need":120,"future":"keep","when":[{"op":"NODE_COMPLETED","nodeId":9,"future":true}],"doneWhen":[{"op":"HAS_TAG","value":"tag.saved","future":"e\u0301"}]}]}"#)
        var value = ProjectThoughtDefinitions(raw: raw, draft: draft(raw)); XCTAssertFalse(value.readOnly)
        XCTAssertEqual(value.rows[0].whenNodeIDs, [9]); XCTAssertTrue(value.tags[0].retained)
        value.rows[0].name = "After"
        let root = try object(value.serialized(matching: raw)), old = try object(raw)
        let row = try XCTUnwrap(root["thoughts"]?.array?[0].object), oldRow = try XCTUnwrap(old["thoughts"]?.array?[0].object)
        XCTAssertEqual(root["future"], old["future"]); XCTAssertEqual(root["stateEnabled"], .bool(false))
        for key in ["future", "when", "doneWhen"] { XCTAssertEqual(row[key], oldRow[key]) }
        value.rows[0].doneTags = []; XCTAssertNotNil(try value.serialized(matching: raw)) // Explicit deselection only; node conditions stay.
    }
    func testUnknownPredicateDuplicateKeyAndMalformedRulesAreReadOnlyNotDropped() throws {
        for raw in [#"{"schemaVersion":1,"thoughts":[{"key":"a","name":"A","need":1,"when":[{"op":"FUTURE","value":1}]}]}"#,
                    #"{"schemaVersion":1,"thoughts":[{"key":"a","name":"A","need":1},{"key":"a","name":"B","need":1}]}"#,
                    #"{"schemaVersion":2}"#] {
            let value = ProjectThoughtDefinitions(raw: .string(raw), draft: draft(.string(raw)))
            XCTAssertTrue(value.readOnly); XCTAssertThrowsError(try value.serialized(matching: .string(raw)))
        }
    }
    func testOnlyMatchingTemplateIdentityExposesRealAddTagEffects() throws {
        var draft = draft()
        draft.chapters[0].nodes[0].templateID = 42
        let config = #"{"schemaVersion":1,"choice":{"question":"Choose","options":[{"label":"Door","effects":[{"op":"ADD_TAG","value":"tag.door"}]}]}}"#
        draft.chapters[0].nodes[0].localMetadata["templateInfo"] = .object(["id": .number(41), "advancedConfigJson": .string(config)])
        XCTAssertTrue(ProjectThoughtDefinitions.options(in: draft).isEmpty)
        draft.chapters[0].nodes[0].localMetadata["templateInfo"] = .object(["id": .number(42), "advancedConfigJson": .string(config)])
        let options = ProjectThoughtDefinitions.options(in: draft); XCTAssertEqual(options.map(\.tag), ["tag.door"])
        XCTAssertTrue(options[0].label.contains("Door")); XCTAssertFalse(options[0].retained)
    }
    func testGeneratedKeysAndEightDefinitionLimitStayStable() throws {
        var value = ProjectThoughtDefinitions(raw: nil, draft: draft())
        for _ in 0..<8 { XCTAssertTrue(value.add()) }
        let keys = value.rows.map(\.key); XCTAssertEqual(Set(keys).count, 8); XCTAssertTrue(keys.allSatisfy(ProjectThoughtDefinitions.validKey))
        XCTAssertFalse(value.add()); XCTAssertFalse(value.add(key: keys[0])); XCTAssertFalse(ProjectThoughtDefinitions.validKey("a\n"))
        XCTAssertEqual(value.rows.map(\.key), keys)
    }
    func testReferenceSelectionUsesActualDefinitionAndUniqueStableBlockAndKeepsUnknownOldUntilChosen() throws {
        let raw: ProjectEditJSON = .string(#"{"schemaVersion":1,"thoughts":[{"key":"first","name":"First","need":120}]}"#)
        var draft = draft(raw); var block = ProjectEditBlock(kind: .thought); block.setField("thoughtKey", .string("unknown")); draft.chapters[0].blocks = [block]
        let definitions = ProjectThoughtDefinitions(raw: raw, draft: draft), old = ProjectEditPendingMaterials.exactData(draft)
        XCTAssertThrowsError(try definitions.assigningReference("absent", chapterID: draft.chapters[0].id, blockID: block.id, in: draft))
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(draft), old)
        let next = try definitions.assigningReference("first", chapterID: draft.chapters[0].id, blockID: block.id, in: draft)
        XCTAssertEqual(next.chapters[0].blocks?[0].fieldText("thoughtKey"), "first")
        draft.chapters[0].blocks?.append(block)
        XCTAssertThrowsError(try definitions.assigningReference("first", chapterID: draft.chapters[0].id, blockID: block.id, in: draft))
    }
}

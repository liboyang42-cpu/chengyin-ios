import XCTest
@testable import QuestifyCore

final class TemplateD6RehearsalTests: XCTestCase {
    private func fixture(count: TemplateAuthoringJSON? = .number(1)) -> TemplateAdvancedDraft {
        var draft = TemplateAdvancedDraft(); draft.setGameEnabled(.dice, true)
        var fields = draft.value["diceRoll"]?.object ?? [:]; fields["diceCount"] = count
        draft.value["diceRoll"] = .object(fields)
        draft.set("diceRoll", "kicker", .string("  Test each face  "))
        for index in 0..<6 { draft.setFace(index, "  Action \(index + 1) \n") }
        return draft
    }
    func testEverySingleDieExampleUsesItsConfiguredFace() throws {
        let config = try TemplateD6Rehearsal(draft: fixture())
        for value in 1...6 {
            let sample = try config.sample(pips: [value])
            XCTAssertEqual(sample.pips, [value]); XCTAssertEqual(sample.total, value)
            XCTAssertEqual(sample.action, "Action \(value)")
        }
    }
    func testAllTwoDiceCombinationsOnlyShowPipsAndTotal() throws {
        let config = try TemplateD6Rehearsal(draft: fixture(count: .number(2)))
        for first in 1...6 { for second in 1...6 {
            let sample = try config.sample(pips: [first, second])
            XCTAssertEqual(sample.pips, [first, second]); XCTAssertEqual(sample.total, first + second)
            XCTAssertNil(sample.action, "Two dice never index the six face actions by their sum")
        } }
    }
    func testInspectionNormalizesDisplayLikeSerializationWithoutMutatingDraft() throws {
        let draft = fixture(), before = draft, config = try TemplateD6Rehearsal(draft: draft)
        XCTAssertEqual(config.kicker, "Test each face"); XCTAssertEqual(config.faces.first, "Action 1")
        XCTAssertEqual(draft, before)
        let serialized = try TemplateAdvancedDraft(raw: draft.serialize())
        XCTAssertEqual(try TemplateD6Rehearsal(draft: serialized), config)
    }
    func testExistingNumericTextAndAbsentCountUseExistingContract() throws {
        XCTAssertEqual(try TemplateD6Rehearsal(draft: fixture(count: .string("2"))).diceCount, 2)
        XCTAssertEqual(try TemplateD6Rehearsal(draft: fixture(count: nil)).diceCount, 1)
        let invalid: [TemplateAuthoringJSON] = [.number(0), .number(3), .number(1.5), .number(.infinity), .string(" "), .string("two"), .null, .bool(true), .array([]), .object([:])]
        for value in invalid { XCTAssertThrowsError(try TemplateD6Rehearsal(draft: fixture(count: value))) }
    }
    func testDisabledD20UnknownAndWrongTypedModesRefusePreview() {
        var draft = fixture(); draft.setGameEnabled(.dice, false)
        XCTAssertThrowsError(try TemplateD6Rehearsal(draft: draft))
        let modes: [TemplateAuthoringJSON] = [.string("d20"), .string("unknown"), .number(6)]
        for mode in modes {
            draft = fixture(); draft.set("diceRoll", "mode", mode)
            XCTAssertThrowsError(try TemplateD6Rehearsal(draft: draft))
        }
    }
    func testInvalidFacesAndUnknownDiceFieldsKeepExistingValidation() {
        let invalid: [TemplateAuthoringJSON] = [.array([]), .array([.string("one")]), .array(Array(repeating: .string(" "), count: 6)),
            .array(Array(repeating: .string(String(repeating: "🎲", count: 31)), count: 6)), .array(Array(repeating: .number(1), count: 6))]
        for value in invalid {
            var draft = fixture(); draft.set("diceRoll", "faces", value)
            XCTAssertThrowsError(try TemplateD6Rehearsal(draft: draft))
        }
        var draft = fixture(); draft.set("diceRoll", "future", .string("keep"))
        XCTAssertThrowsError(try TemplateD6Rehearsal(draft: draft)); XCTAssertEqual(draft.text("diceRoll", "future"), "keep")
    }
    func testUnrelatedInvalidFamilyDoesNotRewriteOrBlockLocalD6Inspection() throws {
        var draft = fixture(); draft.setCreatorEnabled(.qa, true); draft.set("qa", "title", .string(""))
        let before = draft
        XCTAssertThrowsError(try draft.serialize())
        XCTAssertEqual(try TemplateD6Rehearsal(draft: draft).sample(pips: [6]).action, "Action 6")
        XCTAssertEqual(draft, before)
    }
    func testSampleRejectsWrongCountOrOutOfRangeValues() throws {
        let one = try TemplateD6Rehearsal(draft: fixture()), two = try TemplateD6Rehearsal(draft: fixture(count: .number(2)))
        for pips in [[], [0], [7], [1, 2]] { XCTAssertThrowsError(try one.sample(pips: pips)) }
        for pips in [[], [1], [-1, 6], [6, 7], [1, 2, 3]] { XCTAssertThrowsError(try two.sample(pips: pips)) }
    }
    func testLocalDraftRoundTripRetainsConfigurationButNoSampleState() throws {
        var original = TemplateAuthoringDraft(title: "D6 authoring"); original.advanced = fixture(count: .number(2))
        let bytes = try JSONEncoder().encode(original)
        _ = try TemplateD6Rehearsal(draft: original.advanced).sample(pips: [6, 6])
        let restored = try JSONDecoder().decode(TemplateAuthoringDraft.self, from: bytes)
        XCTAssertEqual(restored, original); XCTAssertEqual(try TemplateD6Rehearsal(draft: restored.advanced).diceCount, 2)
        XCTAssertNil(restored.advanced.value["diceRoll"]?.object?["pips"])
        XCTAssertNil(restored.advanced.value["diceRoll"]?.object?["sum"])
    }
}

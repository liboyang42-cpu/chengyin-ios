import XCTest
@testable import QuestifyCore

final class TemplateReasoningRehearsalTests: XCTestCase {
    private func valid(_ game: TemplateAdvancedGame) -> TemplateAdvancedDraft {
        var draft = TemplateAdvancedDraft(); draft.setGameEnabled(game, true)
        draft.set(game.section, "prompt", .string("Current author question"))
        for field in game == .sort ? ["items"] : game == .match ? ["left", "right"] : ["items", "bins"] {
            for index in draft.rows(game.section, field).indices {
                draft.setRow(game.section, field, index: index, key: "label", text: "\(field) \(index)")
            }
        }
        return draft
    }
    private func make(_ game: TemplateAdvancedGame) throws -> TemplateReasoningRehearsal {
        try XCTUnwrap(TemplateReasoningRehearsal(valid(game), game: game))
    }
    private func order(_ ids: [String]) -> [String: PlayWireValue] { ["order": .array(ids.map(PlayWireValue.string))] }
    private func pairs(_ rows: [[String]]) -> [String: PlayWireValue] { ["pairs": .array(rows.map { .array($0.map(PlayWireValue.string)) })] }
    private var correctSort: [String: PlayWireValue] { order(["item_1", "item_2", "item_3"]) }
    private var correctMatch: [String: PlayWireValue] { pairs([["left_1", "right_1"], ["left_2", "right_2"]]) }
    private var correctClassify: [String: PlayWireValue] { ["placement": .object(["item_1": .string("bin_1"), "item_2": .string("bin_2")])] }

    func testOnlyEnabledValidReasoningConfigurationsAreAvailable() throws {
        for game in [TemplateAdvancedGame.sort, .match, .classify] {
            XCTAssertNil(TemplateReasoningRehearsal(TemplateAdvancedDraft(), game: game))
            var draft = valid(game); draft.set(game.section, "prompt", .string(""))
            XCTAssertNil(TemplateReasoningRehearsal(draft, game: game))
            XCTAssertEqual(try make(game).result, .ready)
        }
        XCTAssertNil(TemplateReasoningRehearsal(valid(.compass), game: .compass))
    }
    func testSortCurrentAuthoredOrderMatchesAndInitialPracticeOrderDoesNot() throws {
        var value = try make(.sort)
        let initial = value.segment["items"].array!.compactMap { $0["id"].text }
        XCTAssertEqual(initial, ["item_2", "item_3", "item_1"])
        XCTAssertTrue(value.submit(action: value.action, payload: order(initial))); XCTAssertEqual(value.result, .missed)
        value.reset(); XCTAssertTrue(value.submit(action: value.action, payload: correctSort)); XCTAssertEqual(value.result, .matched)
    }
    func testSortUsesCurrentRowsRatherThanStaleImportedAnswer() throws {
        var draft = valid(.sort); draft.set("sort", "answerOrder", .array([.string("obsolete")]))
        draft.moveRow("sort", "items", from: 0, to: 2)
        var value = try XCTUnwrap(TemplateReasoningRehearsal(draft, game: .sort))
        value.submit(action: value.action, payload: order(["item_2", "item_3", "item_1"]))
        XCTAssertEqual(value.result, .matched)
    }
    func testSortMissingDuplicateForeignAndTypedIDsAreInvalid() throws {
        for payload in [order(["item_1"]), order(["item_1", "item_1", "item_3"]), order(["item_1", "item_2", "foreign"]), ["order": .array([.integer(1), .string("item_2"), .string("item_3")])]] {
            var value = try make(.sort); value.submit(action: value.action, payload: payload); XCTAssertEqual(value.result, .invalid)
        }
    }
    func testMatchIgnoresPairRowOrderButRequiresCorrectMappings() throws {
        var value = try make(.match)
        value.submit(action: value.action, payload: pairs([["left_2", "right_2"], ["left_1", "right_1"]])); XCTAssertEqual(value.result, .matched)
        value.reset(); value.submit(action: value.action, payload: pairs([["left_1", "right_2"], ["left_2", "right_1"]])); XCTAssertEqual(value.result, .missed)
    }
    func testMatchUsesPairedEditorRowsAndDoesNotMutateOriginal() throws {
        var draft = valid(.match); draft.set("match", "pairs", .array([])); let before = draft
        var value = try XCTUnwrap(TemplateReasoningRehearsal(draft, game: .match))
        value.submit(action: value.action, payload: correctMatch)
        XCTAssertEqual(value.result, .matched); XCTAssertEqual(draft, before)
        XCTAssertEqual(value.segment["right"].array?.compactMap { $0["id"].text }, ["right_2", "right_1"])
    }
    func testMatchPartialDuplicateForeignAndWrongWidthAreInvalid() throws {
        for payload in [pairs([["left_1", "right_1"]]), pairs([["left_1", "right_1"], ["left_2", "right_1"]]), pairs([["foreign", "right_1"], ["left_2", "right_2"]]), pairs([["left_1", "right_1", "extra"], ["left_2", "right_2"]])] {
            var value = try make(.match); value.submit(action: value.action, payload: payload); XCTAssertEqual(value.result, .invalid)
        }
    }
    func testClassificationUsesOnlyExplicitCurrentAuthorAssignments() throws {
        var value = try make(.classify)
        value.submit(action: value.action, payload: correctClassify); XCTAssertEqual(value.result, .matched)
        value.reset(); value.submit(action: value.action, payload: ["placement": .object(["item_1": .string("bin_2"), "item_2": .string("bin_1")])]); XCTAssertEqual(value.result, .missed)
    }
    func testClassificationIncompleteForeignAndNonStringAssignmentsAreInvalid() throws {
        for assignment: [String: PlayWireValue] in [["item_1": .string("bin_1")], ["item_1": .string("foreign"), "item_2": .string("bin_2")], ["item_1": .bool(true), "item_2": .string("bin_2")], ["item_1": .string("bin_1"), "item_2": .string("bin_2"), "foreign": .string("bin_1")]] {
            var value = try make(.classify); value.submit(action: value.action, payload: ["placement": .object(assignment)]); XCTAssertEqual(value.result, .invalid)
        }
    }
    func testIncompleteAuthorClassificationHasNoGuessedAnswer() {
        var draft = valid(.classify); draft.setClassification(itemID: "item_1", binID: "")
        XCTAssertNil(TemplateReasoningRehearsal(draft, game: .classify))
    }
    func testDuplicateAuthorIDsAndUnbalancedMatchAreUnavailable() {
        var draft = valid(.sort); draft.setRow("sort", "items", index: 1, key: "id", text: "item_1")
        XCTAssertNil(TemplateReasoningRehearsal(draft, game: .sort))
        draft = valid(.match); draft.removeRow("match", "right", index: 0)
        XCTAssertNil(TemplateReasoningRehearsal(draft, game: .match))
    }
    func testActionMismatchAndExtraKeysNeverProduceMatch() throws {
        var value = try make(.sort)
        value.submit(action: "SUBMIT_MATCH", payload: correctSort); XCTAssertEqual(value.result, .invalid)
        value.reset(); var payload = correctSort; payload["passed"] = .bool(true)
        value.submit(action: value.action, payload: payload); XCTAssertEqual(value.result, .invalid)
    }
    func testDuplicateSubmitCannotOverwriteAcceptedResult() throws {
        var value = try make(.sort)
        XCTAssertTrue(value.submit(action: value.action, payload: correctSort))
        XCTAssertFalse(value.submit(action: value.action, payload: order(["item_3", "item_2", "item_1"])))
        XCTAssertEqual(value.result, .matched); XCTAssertFalse(value.canSubmit)
    }
    func testResetClearsMatchedMissedAndInvalidResults() throws {
        for payload in [correctSort, order(["item_3", "item_2", "item_1"]), order([])] {
            var value = try make(.sort); value.submit(action: value.action, payload: payload); value.reset()
            XCTAssertEqual(value.result, .ready); XCTAssertTrue(value.canSubmit)
            value.submit(action: value.action, payload: correctSort); XCTAssertEqual(value.result, .matched)
        }
    }
    func testProjectionHasOnlyTextControlsAndNoSecretsOrRuntimeStatus() throws {
        for game in [TemplateAdvancedGame.sort, .match, .classify] {
            var draft = valid(game)
            for key in ["answerOrder", "pairs", "answer", "xp", "passed", "attempts", "complete", "privateNote"] {
                if !["answerOrder", "pairs", "answer"].contains(key) { draft.set(game.section, key, .string("private sentinel")) }
            }
            let field = game == .match ? "left" : "items"
            draft.setRow(game.section, field, index: 0, key: "img", text: "https://example.com/private.png")
            draft.setRow(game.section, field, index: 0, key: "privateNote", text: "secret note")
            let before = draft, value = try XCTUnwrap(TemplateReasoningRehearsal(draft, game: game))
            for key in ["answerOrder", "pairs", "answer", "xp", "passed", "attempts", "complete", "privateNote"] { XCTAssertEqual(value.segment[key], .null) }
            for row in value.segment[field].array ?? [] { XCTAssertEqual(Set(row.object!.keys), Set(["id", "label"])) }
            XCTAssertEqual(draft, before)
        }
    }
    func testOriginalConfigurationRemainsByteIdenticalAfterAllLocalActions() throws {
        for (game, payload) in [(TemplateAdvancedGame.sort, correctSort), (.match, correctMatch), (.classify, correctClassify)] {
            let draft = valid(game), before = try JSONEncoder().encode(draft)
            var value = try XCTUnwrap(TemplateReasoningRehearsal(draft, game: game))
            value.submit(action: value.action, payload: payload); value.reset()
            XCTAssertEqual(draft, valid(game)); XCTAssertFalse(before.isEmpty)
        }
    }
    func testWhitespaceNormalizationMatchesExistingEditor() throws {
        var draft = valid(.sort); draft.setRow("sort", "items", index: 0, key: "id", text: " item_1 ")
        draft.set("sort", "prompt", .string(" Current author question \n"))
        var value = try XCTUnwrap(TemplateReasoningRehearsal(draft, game: .sort))
        value.submit(action: value.action, payload: correctSort); XCTAssertEqual(value.result, .matched)
        XCTAssertEqual(value.segment["prompt"].text, "Current author question")
    }
}

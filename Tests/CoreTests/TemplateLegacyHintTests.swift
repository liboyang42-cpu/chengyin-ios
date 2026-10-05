import XCTest
@testable import QuestifyCore

final class TemplateLegacyHintTests: XCTestCase {
    private func legacy(_ method: TemplateAuthoringMethod = .text) -> TemplateAuthoringDraft {
        var draft = TemplateAuthoringDraft(title: "Local hints")
        draft.validationMethod = method
        draft.hint1 = "  first  "; draft.hint2 = "second"; draft.answerReveal = "answer"
        draft.legacyHintsEnabled = nil
        return draft
    }
    func testNewBlankDraftIsOffAndOnlyLegacyMethodsSupportHints() {
        for method in TemplateAuthoringMethod.allCases {
            var draft = TemplateAuthoringDraft(); draft.validationMethod = method
            XCTAssertFalse(draft.legacyHintsAreEnabled)
            XCTAssertEqual(draft.legacyHintControlsVisible, [.text, .choice, .gps].contains(method))
        }
    }
    func testMissingFlagInfersAnyNonemptyStringWithoutTrimmingOrMutating() throws {
        for field in TemplateLegacyHintField.allCases {
            for text in ["hint", " ", "\n", "👩🏽‍🚀", String(repeating: "x", count: 10_000)] {
                var draft = TemplateAuthoringDraft(); draft.validationMethod = .text
                draft[keyPath: field.draftPath] = text
                let data = try JSONEncoder().encode(draft)
                XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("legacyHintsEnabled"))
                let decoded = try JSONDecoder().decode(TemplateAuthoringDraft.self, from: data)
                XCTAssertTrue(decoded.legacyHintsAreEnabled); XCTAssertNil(decoded.legacyHintsEnabled)
                XCTAssertEqual(decoded, draft)
            }
        }
    }
    func testExplicitOffClearsExactlyThreeStringsAndDoesNotTouchAdvancedAnswers() throws {
        for method in [TemplateAuthoringMethod.text, .choice, .gps] {
            var draft = legacy(method)
            draft.advanced.set("qa", "answerText", .string("private advanced answer"))
            draft.advanced.set("qa", "reveal", .bool(true))
            draft.questionAnswer = "legacy answer"; draft.correctAnswer = "B"
            var expected = draft
            expected.hint1 = ""; expected.hint2 = ""; expected.answerReveal = ""; expected.legacyHintsEnabled = false
            XCTAssertTrue(draft.setLegacyHintsEnabled(false)); XCTAssertEqual(draft, expected)
            let payload = try TemplateAuthoringContract.payload(draft)
            for key in ["hint1", "hint2", "answerReveal", "hintEnabled", "legacyHintsEnabled"] { XCTAssertNil(payload[key]) }
            XCTAssertTrue(draft.setLegacyHintsEnabled(true))
            XCTAssertEqual(draft.hint1, ""); XCTAssertEqual(draft.answerReveal, "")
        }
    }
    func testUnsupportedRoundTripDisablesWithoutClearingOrSilentlyReenabling() throws {
        var draft = legacy()
        draft.validationMethod = .photo
        XCTAssertEqual(draft.legacyHintsEnabled, false)
        XCTAssertEqual(draft.hint1, "  first  "); XCTAssertEqual(draft.answerReveal, "answer")
        XCTAssertNil(try TemplateAuthoringContract.payload(draft)["hint1"])
        draft.validationMethod = .text
        XCTAssertFalse(draft.legacyHintsAreEnabled)
        let restored = try JSONDecoder().decode(TemplateAuthoringDraft.self, from: JSONEncoder().encode(draft))
        XCTAssertEqual(restored, draft); XCTAssertFalse(restored.legacyHintsAreEnabled)
        XCTAssertNil(try TemplateAuthoringContract.payload(restored)["answerReveal"])
        XCTAssertTrue(draft.setLegacyHintsEnabled(true))
        XCTAssertEqual(try TemplateAuthoringContract.payload(draft)["hint1"], .string("  first  "))
    }
    func testSupportedMethodChangesKeepIntentAndUntouchedHistoricDecodeNeverRunsObserver() throws {
        var draft = legacy()
        draft.validationMethod = .choice; draft.validationMethod = .gps
        XCTAssertNil(draft.legacyHintsEnabled); XCTAssertTrue(draft.legacyHintsAreEnabled)
        draft.validationMethod = .photo; draft.legacyHintsEnabled = nil
        let restored = try JSONDecoder().decode(TemplateAuthoringDraft.self, from: JSONEncoder().encode(draft))
        XCTAssertNil(restored.legacyHintsEnabled); XCTAssertEqual(restored, draft)
        XCTAssertTrue(restored.legacyHintsAreEnabled); XCTAssertFalse(restored.legacyHintControlsVisible)
        XCTAssertNil(try TemplateAuthoringContract.payload(restored)["hint1"])
    }
    func testPayloadSuppressesDisabledUnsupportedAndFinishOffWithoutMutating() throws {
        for method in TemplateAuthoringMethod.allCases where !method.isLocalConfigurationOnly {
            for finish in [false, true] {
                for enabled in [false, true] {
                    var draft = legacy(method); draft.finishEnabled = finish; draft.legacyHintsEnabled = enabled
                    let original = draft, payload = try TemplateAuthoringContract.payload(draft)
                    for field in TemplateLegacyHintField.allCases {
                        let expected = finish && enabled && method.supportsLegacyHints ? draft[keyPath: field.draftPath].map(TemplateAuthoringJSON.string) : nil
                        XCTAssertEqual(payload[field.rawValue], expected)
                    }
                    XCTAssertNil(payload["hintEnabled"]); XCTAssertNil(payload["legacyHintsEnabled"])
                    XCTAssertEqual(draft, original)
                }
            }
        }
    }
    func testLocalOnlyMethodsStillCannotProduceRemoteRequestsOrPayloads() throws {
        for method in [TemplateAuthoringMethod.preference, .sensor] {
            let draft = legacy(method)
            XCTAssertThrowsError(try TemplateAuthoringContract.payload(draft))
            XCTAssertThrowsError(try TemplateAuthoringContract.request(draft, intent: .saveDraft))
        }
        var request = try TemplateAuthoringContract.payload(legacy())
        request["hintEnabled"] = .bool(true)
        XCTAssertFalse(TemplateAuthoringContract.permitsRemoteConfiguration(.init(path: "/api/template/draft", body: .json(request), mutates: true)))
    }
    func testRecognizedPrimarySectionsHideControlsAndDoNotMutateOrInventPayloadClearing() throws {
        let sections = ["album", "branch", "sort", "match", "classify", "estimate", "pricePair", "hiddenObject",
            "predict", "random", "profile", "note", "photoCheck", "steps", "reaction", "ballShake", "quietHold",
            "compass", "shout", "countdown", "stopwatch", "check", "typeIn", "coinFlip", "scan", "qa", "diceRoll"]
        for section in sections {
            var draft = legacy(); draft.advanced.set(section, "enabled", .bool(true))
            let original = draft
            XCTAssertFalse(draft.legacyHintControlsVisible, section)
            XCTAssertFalse(draft.setLegacyHintsEnabled(false), section)
            XCTAssertFalse(draft.setLegacyHint(.answerReveal, to: "changed"), section)
            XCTAssertEqual(draft, original, section)
        }
        var qa = legacy(); qa.advanced.set("qa", "enabled", .bool(true))
        qa.advanced.set("qa", "mode", .string("TYPE"))
        qa.advanced.set("qa", "title", .string("Which detail?"))
        qa.advanced.set("qa", "answerText", .string("Window"))
        XCTAssertTrue(qa.advanced.issues.isEmpty)
        XCTAssertEqual(try TemplateAuthoringContract.payload(qa)["hint1"], .string("  first  "))
    }
    func testModifiersAndUnknownSectionsDoNotHideLegacyHints() {
        let sections = ["timer", "leaderboard", "multiplayer", "timeWindow", "blindTaste", "silentOrder", "diyName",
            "musicCorner", "dailySign", "slowTask", "compare", "future"]
        var draft = legacy()
        for section in sections { draft.advanced.set(section, "enabled", .bool(true)) }
        XCTAssertTrue(draft.legacyHintControlsVisible)
    }
    func testPrimaryModeMatchingAndHistoricalTruthinessRemainReadOnly() {
        for mode in ["TYPE", "PICK", "SHOT", "", "future", "type"] {
            var draft = legacy(); draft.advanced.set("qa", "enabled", .bool(true)); draft.advanced.set("qa", "mode", .string(mode))
            XCTAssertEqual(draft.advanced.hasLegacyHintPrimaryGame, ["TYPE", "PICK", "SHOT"].contains(mode))
        }
        for mode in [TemplateAuthoringJSON.null, .bool(false), .number(0), .string(""), .string("d6"), .string("d20")] {
            var draft = legacy(); draft.advanced.set("diceRoll", "enabled", .bool(true)); draft.advanced.set("diceRoll", "mode", mode)
            XCTAssertTrue(draft.advanced.hasLegacyHintPrimaryGame)
        }
        for mode in [TemplateAuthoringJSON.bool(true), .number(6), .array([]), .object([:]), .string("future")] {
            var draft = legacy(); draft.advanced.set("diceRoll", "enabled", .bool(true)); draft.advanced.set("diceRoll", "mode", mode)
            XCTAssertFalse(draft.advanced.hasLegacyHintPrimaryGame)
        }
        for enabled in [TemplateAuthoringJSON.string("false"), .number(1), .array([]), .object([:])] {
            var draft = legacy(); draft.advanced.set("album", "enabled", enabled)
            let original = draft; XCTAssertTrue(draft.advanced.hasLegacyHintPrimaryGame); XCTAssertEqual(draft, original)
        }
    }
    func testExactHistoricalValuesAndUnknownOtherDataRoundTripUntilExplicitEdit() throws {
        var draft = legacy(); draft.storyJson = "{future unfinished"
        draft.questionOptionMediaJson = " {\"future\":[1]} "
        draft.advanced.value["future"] = .object(["unknown": .array([.number(1), .null])])
        let restored = try JSONDecoder().decode(TemplateAuthoringDraft.self, from: JSONEncoder().encode(draft))
        XCTAssertEqual(restored, draft); XCTAssertNil(restored.legacyHintsEnabled)
        XCTAssertTrue(draft.setLegacyHint(.hint2, to: "  exact replacement 👩🏽‍🚀\n "))
        XCTAssertEqual(draft.hint2, "  exact replacement 👩🏽‍🚀\n ")
        XCTAssertEqual(draft.storyJson, restored.storyJson); XCTAssertEqual(draft.advanced, restored.advanced)
        XCTAssertEqual(draft.hint1, restored.hint1); XCTAssertEqual(draft.answerReveal, restored.answerReveal)
    }
}

import XCTest
@testable import QuestifyCore

final class TemplateChoiceOptionMediaTests: XCTestCase {
    func testAbsentEmptyAndExplicitEmptyObjectRemainDistinctUntilEdited() throws {
        for raw in [nil, "", "{}", " { } "] as [String?] {
            let media = TemplateChoiceOptionMedia(raw: raw)
            XCTAssertTrue(media.isSupported)
            XCTAssertEqual(media.originalText, raw)
            XCTAssertNil(media.text(.a, .image))
            XCTAssertEqual(try media.updating(.a, .image, to: ""), raw)
        }
    }
    func testExactKnownReferencesKeepWhitespaceAndChoiceIdentityOnRead() throws {
        let raw = "\n{\"D\":{\"audio\":\" audio-d \"},\"A\":{\"img\":\" image-a \",\"audio\":\"\"}}\n"
        let media = TemplateChoiceOptionMedia(raw: raw)
        XCTAssertTrue(media.isSupported); XCTAssertEqual(media.originalText, raw)
        XCTAssertEqual(media.text(.a, .image), " image-a ")
        XCTAssertEqual(media.text(.a, .audio), ""); XCTAssertNil(media.text(.b, .image))
        XCTAssertEqual(media.text(.d, .audio), " audio-d ")
        XCTAssertEqual(try media.updating(.a, .image, to: " image-a "), raw)
    }
    func testExplicitEditAndClearKeepOtherMediaAndOptionValues() throws {
        let initial = TemplateChoiceOptionMedia(raw: #"{"A":{"img":"old","audio":"keep-audio"},"C":{},"D":{"img":"","audio":"  exact-d  "}}"#)
        let changed = TemplateChoiceOptionMedia(raw: try initial.updating(.a, .image, to: "  new  "))
        XCTAssertEqual(changed.text(.a, .image), "new")
        XCTAssertEqual(changed.text(.a, .audio), "keep-audio")
        XCTAssertEqual(changed.text(.d, .audio), "  exact-d  ")
        XCTAssertEqual(changed.text(.d, .image), "")
        let cleared = TemplateChoiceOptionMedia(raw: try changed.updating(.a, .image, to: ""))
        XCTAssertNil(cleared.text(.a, .image)); XCTAssertEqual(cleared.text(.a, .audio), "keep-audio")
        let fields = try JSONDecoder().decode(TemplateAuthoringJSON.self, from: Data(try XCTUnwrap(cleared.originalText).utf8))
        XCTAssertEqual(fields.object?["C"], .object([:]))
        XCTAssertEqual(try TemplateChoiceOptionMedia(raw: #"{"B":{"audio":"last"}}"#).updating(.b, .audio, to: "  "), "")
    }
    func testUnknownMalformedAndOversizeRawAreNeverReplacedByEditor() throws {
        let vectors = ["not json", "[]", "null", "42", " ", #"{"E":{"img":"future"}}"#,
            #"{"A":{"video":"future","img":"known"}}"#, #"{"A":null}"#,
            #"{"A":{"img":true}}"#, #"{"A":{"audio":1}}"#, #"{"A":["image"]}"#,
            String(repeating: " ", count: 65_537)]
        for raw in vectors {
            let media = TemplateChoiceOptionMedia(raw: raw)
            XCTAssertFalse(media.isSupported); XCTAssertEqual(media.originalText, raw)
            XCTAssertThrowsError(try media.updating(.a, .image, to: "replacement"))
            var draft = TemplateAuthoringDraft(); draft.questionOptionMediaJson = raw
            XCTAssertThrowsError(try draft.setChoiceOptionMedia(.b, .audio, to: "replacement"))
            XCTAssertEqual(draft.questionOptionMediaJson, raw)
        }
    }
    func testUnsupportedKnownSiblingIsAvailableForInspectionWithoutDroppingUnknown() {
        let raw = #"{"A":{"img":"known","future":{"nested":true}},"Z":"unknown"}"#
        let media = TemplateChoiceOptionMedia(raw: raw)
        XCTAssertFalse(media.isSupported); XCTAssertEqual(media.text(.a, .image), "known")
        XCTAssertEqual(media.originalText, raw)
    }
    func testOversizeEditDoesNotReplaceExistingDraft() throws {
        var draft = TemplateAuthoringDraft(); draft.questionOptionMediaJson = #"{"A":{"img":"keep"}}"#
        let previous = draft
        XCTAssertThrowsError(try draft.setChoiceOptionMedia(.a, .image, to: String(repeating: "x", count: 65_536)))
        XCTAssertEqual(draft, previous)
    }
    func testDraftEnvelopeRoundTripDoesNotNormalizeRaw() throws {
        for raw in ["\n{\"A\":{\"img\":\" exact \"}}\n", "{unknown unfinished"] {
            var draft = TemplateAuthoringDraft(title: "Local choice")
            draft.validationMethod = .choice; draft.questionOptionMediaJson = raw
            let decoded = try JSONDecoder().decode(TemplateAuthoringDraft.self, from: JSONEncoder().encode(draft))
            XCTAssertEqual(decoded.questionOptionMediaJson, raw)
            XCTAssertEqual(decoded, draft)
        }
    }
    func testExistingChoicePayloadAndInactiveOmissionAreUnchanged() throws {
        var draft = TemplateAuthoringDraft(title: "Local choice"); draft.validationMethod = .choice
        try draft.setChoiceOptionMedia(.c, .image, to: "https://images.example/choice-c.png")
        let raw = try XCTUnwrap(draft.questionOptionMediaJson)
        XCTAssertEqual(try TemplateAuthoringContract.payload(draft)["questionOptionMediaJson"], .string(raw))
        draft.validationMethod = .text
        XCTAssertNil(try TemplateAuthoringContract.payload(draft)["questionOptionMediaJson"])
        XCTAssertEqual(draft.questionOptionMediaJson, raw)
        draft.validationMethod = .choice; draft.finishEnabled = false
        XCTAssertNil(try TemplateAuthoringContract.payload(draft)["questionOptionMediaJson"])
        XCTAssertEqual(draft.questionOptionMediaJson, raw)
        for method in [TemplateAuthoringMethod.preference, .sensor] {
            draft.validationMethod = method
            XCTAssertThrowsError(try TemplateAuthoringContract.payload(draft))
        }
    }
    func testExplicitLastAttachmentClearUsesExistingEmptyStringWireValue() throws {
        var draft = TemplateAuthoringDraft(title: "Local choice"); draft.validationMethod = .choice
        XCTAssertNil(try TemplateAuthoringContract.payload(draft)["questionOptionMediaJson"])
        try draft.setChoiceOptionMedia(.a, .image, to: "https://images.example/a.png")
        try draft.setChoiceOptionMedia(.a, .image, to: "")
        XCTAssertEqual(draft.questionOptionMediaJson, "")
        XCTAssertEqual(try TemplateAuthoringContract.payload(draft)["questionOptionMediaJson"], .string(""))
    }
    func testReference500501BoundaryAndRelativeOpaqueFormatsUseSourceRules() throws {
        let empty = TemplateChoiceOptionMedia(raw: nil)
        let maximum = String(repeating: "a", count: 500)
        let accepted = try empty.updating(.a, .image, to: maximum)
        XCTAssertEqual(TemplateChoiceOptionMedia(raw: accepted).text(.a, .image), maximum)
        XCTAssertThrowsError(try empty.updating(.a, .image, to: maximum + "b"))
        XCTAssertEqual(TemplateChoiceOptionMedia(raw: try empty.updating(.a, .image, to: " \n" + maximum + "\t")).text(.a, .image), maximum)
        XCTAssertThrowsError(try empty.updating(.a, .image, to: String(repeating: "\u{00A0}", count: 501)))
        let historical = TemplateChoiceOptionMedia(raw: "{\"A\":{\"img\":\"" + maximum + "b\"}}")
        XCTAssertFalse(historical.isSupported)
        XCTAssertEqual(historical.text(.a, .image), maximum + "b")
        XCTAssertThrowsError(try historical.updating(.b, .audio, to: "replacement"))
        for reference in ["../images/choice.png", "asset:bundle/icon", "opaque-reference"] {
            let raw = try empty.updating(.a, .image, to: reference)
            XCTAssertEqual(TemplateChoiceOptionMedia(raw: raw).text(.a, .image), reference)
        }
    }
    func testAggregate20002001BoundaryPreservesExactHistoricalAndRejectedDraft() throws {
        let repeated = String(repeating: "a", count: 500)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let shape = ["A": ["img": repeated, "audio": repeated], "B": ["img": repeated, "audio": ""]]
        let emptyFourth = String(decoding: try encoder.encode(shape), as: UTF8.self)
        let remaining = 2_000 - emptyFourth.utf16.count
        XCTAssertGreaterThan(remaining, 0); XCTAssertLessThanOrEqual(remaining, 500)
        var draft = TemplateAuthoringDraft()
        try draft.setChoiceOptionMedia(.a, .image, to: repeated)
        try draft.setChoiceOptionMedia(.a, .audio, to: repeated)
        try draft.setChoiceOptionMedia(.b, .image, to: repeated)
        try draft.setChoiceOptionMedia(.b, .audio, to: String(repeating: "b", count: remaining))
        let maximum = try XCTUnwrap(draft.questionOptionMediaJson)
        XCTAssertEqual(maximum.utf16.count, 2_000); XCTAssertTrue(draft.choiceOptionMedia.isSupported)
        XCTAssertThrowsError(try draft.setChoiceOptionMedia(.b, .audio, to: String(repeating: "b", count: remaining + 1)))
        XCTAssertEqual(draft.questionOptionMediaJson, maximum)
        let overlong = maximum + " "
        XCTAssertEqual(overlong.utf16.count, 2_001)
        let historical = TemplateChoiceOptionMedia(raw: overlong)
        XCTAssertFalse(historical.isSupported); XCTAssertEqual(historical.originalText, overlong)
        XCTAssertThrowsError(try historical.updating(.a, .image, to: "shorter"))
    }
    func testSupplementaryUnicodeUsesUTF16RatherThanGraphemeOrUTF8Count() throws {
        let accepted = String(repeating: "😀", count: 250)
        XCTAssertEqual(accepted.count, 250); XCTAssertEqual(accepted.utf16.count, 500)
        var draft = TemplateAuthoringDraft()
        try draft.setChoiceOptionMedia(.a, .image, to: accepted)
        XCTAssertEqual(draft.choiceOptionMedia.text(.a, .image), accepted)
        let previous = draft.questionOptionMediaJson
        XCTAssertThrowsError(try draft.setChoiceOptionMedia(.a, .image, to: accepted + "x"))
        XCTAssertEqual(draft.questionOptionMediaJson, previous)
        let raw = "{\"A\":{\"img\":\"" + accepted + "x\"}}"
        XCTAssertFalse(TemplateChoiceOptionMedia(raw: raw).isSupported)
        let aggregate = String(repeating: " ", count: 2_000 - (previous?.utf16.count ?? 0)) + (previous ?? "")
        XCTAssertEqual(aggregate.utf16.count, 2_000)
        XCTAssertTrue(TemplateChoiceOptionMedia(raw: aggregate).isSupported)
        XCTAssertFalse(TemplateChoiceOptionMedia(raw: aggregate + " ").isSupported)
    }
}

import XCTest
@testable import QuestifyCore

final class TemplateSamplePreviewTests: XCTestCase {
    func testSevenSupportedChoicesUseSourceGroupsAndExcludeHardwareMedia() {
        XCTAssertEqual(TemplateSamplePreview.Choice.allCases.map(\.rawValue), ["qaText", "qaPick", "estimate", "random", "profile", "note", "typeIn"])
        for key in ["compass", "photoCheck", "hidden", "album", "shout", "scan"] { XCTAssertNil(TemplateSamplePreview.Choice(rawValue: key)) }
        XCTAssertEqual(TemplateSamplePreview.Choice.qaPick.group, .questions)
        XCTAssertEqual(TemplateSamplePreview.Choice.note.group, .interaction)
        XCTAssertEqual(TemplateSamplePreview.Choice.typeIn.group, .challenge)
    }
    func testAllDefaultChoicesReceiveSourceExamplesWithoutChangingOriginal() throws {
        let original = TemplateAdvancedDraft(), before = original
        for choice in TemplateSamplePreview.Choice.allCases {
            let sample = try XCTUnwrap(TemplateSamplePreview(original, choice: choice))
            XCTAssertFalse(sample.filledFields.isEmpty, choice.rawValue)
            XCTAssertTrue(sample.draft.enabled(choice.family.rawValue)); XCTAssertEqual(original, before)
        }
    }
    func testSourceExamplesAreExactAndNotInvented() throws {
        let original = TemplateAdvancedDraft()
        XCTAssertEqual(try XCTUnwrap(TemplateSamplePreview(original, choice: .qaText)).draft.text("qa", "answerText"), "1937")
        XCTAssertEqual(try XCTUnwrap(TemplateSamplePreview(original, choice: .typeIn)).draft.text("typeIn", "target"), "今天也要出发")
        XCTAssertEqual(try XCTUnwrap(TemplateSamplePreview(original, choice: .random)).draft.rows("random", "items").count, 3)
    }
    func testEditedTitleAndAnswerArePreservedWhilePristineFieldsCanFill() throws {
        var original = TemplateAdvancedDraft(); original.set("qa", "title", .string("My question")); original.set("qa", "answerText", .string("My answer"))
        let sample = try XCTUnwrap(TemplateSamplePreview(original, choice: .qaText))
        XCTAssertEqual(sample.draft.text("qa", "title"), "My question"); XCTAssertEqual(sample.draft.text("qa", "answerText"), "My answer"); XCTAssertTrue(sample.filledFields.isEmpty)
    }
    func testMissingWhitespaceAndNumericStringAreNotPristineDefaults() throws {
        var original = TemplateAdvancedDraft(); var fields = try XCTUnwrap(original.value["estimate"]?.object)
        fields.removeValue(forKey: "title"); fields["unit"] = .string(" "); fields["answer"] = .string("500"); original.value["estimate"] = .object(fields)
        let sample = try XCTUnwrap(TemplateSamplePreview(original, choice: .estimate))
        XCTAssertNil(sample.draft.value["estimate"]?.object?["title"]); XCTAssertEqual(sample.draft.text("estimate", "unit"), " ")
        XCTAssertEqual(sample.draft.value["estimate"]?.object?["answer"], .string("500")); XCTAssertFalse(sample.filledFields.contains("answer"))
    }
    func testCustomOptionRowsIncludingUnknownFieldsAreNeverReplaced() throws {
        var original = TemplateAdvancedDraft(); let rows: TemplateAuthoringJSON = .array([.object(["id": .string("mine"), "label": .string("Custom"), "future": .bool(true)])])
        original.set("qa", "options", rows)
        let sample = try XCTUnwrap(TemplateSamplePreview(original, choice: .qaPick))
        XCTAssertEqual(sample.draft.value["qa"]?.object?["options"], rows); XCTAssertFalse(sample.filledFields.contains("options"))
    }
    func testOnlyHypotheticalQAModeAndSelectedEnableChange() throws {
        var original = TemplateAdvancedDraft(); original.setCreatorEnabled(.note, true); original.set("note", "title", .string("Keep"))
        let sample = try XCTUnwrap(TemplateSamplePreview(original, choice: .qaPick))
        XCTAssertEqual(original.text("qa", "mode"), "TYPE"); XCTAssertFalse(original.enabled("qa"))
        XCTAssertEqual(sample.draft.text("qa", "mode"), "PICK"); XCTAssertEqual(sample.draft.value["note"], original.value["note"])
    }
    func testUnknownSectionsAndFieldsRemainExactlyPresent() throws {
        var original = TemplateAdvancedDraft(); original.value["future"] = .object(["nested": .string("Keep")]); original.set("note", "future", .number(7))
        let sample = try XCTUnwrap(TemplateSamplePreview(original, choice: .note))
        XCTAssertEqual(sample.draft.value["future"], original.value["future"]); XCTAssertEqual(sample.draft.value["note"]?.object?["future"], .number(7))
    }
    func testMalformedOrMissingTargetCannotBeSilentlyRebuilt() {
        var original = TemplateAdvancedDraft(); original.value["note"] = .string("Opaque")
        XCTAssertNil(TemplateSamplePreview(original, choice: .note)); original.value.removeValue(forKey: "note")
        XCTAssertNil(TemplateSamplePreview(original, choice: .note))
    }
    func testSnapshotDistinguishesUnicodeBytesAndOptionalPresence() {
        var first = TemplateAuthoringDraft(title: "\u{00E9}"), second = first; second.title = "e\u{0301}"
        XCTAssertNotEqual(TemplateSamplePreview.snapshot(first), TemplateSamplePreview.snapshot(second))
        second = first; first.questionAudio = ""; XCTAssertNotEqual(TemplateSamplePreview.snapshot(first), TemplateSamplePreview.snapshot(second))
    }
}

import XCTest
@testable import QuestifyCore

final class TemplateAdditionalSamplePreviewTests: XCTestCase {
    func testAllFourChoicesUseExistingNativeRenderersWithoutChangingOriginal() throws {
        let original = TemplateAdvancedDraft(), before = original
        XCTAssertEqual(TemplateAdditionalSamplePreview.Choice.allCases.map(\.rawValue), ["predict", "pricePair", "dice", "d20"])
        for choice in TemplateAdditionalSamplePreview.Choice.allCases {
            let item = try XCTUnwrap(TemplateAdditionalSamplePreview(original, choice: choice))
            XCTAssertFalse(item.filledFields.isEmpty); XCTAssertTrue(item.draft.enabled(choice.section))
        }
        XCTAssertEqual(original, before)
    }
    func testPredictAndPictureLabelsMatchSourceExamples() throws {
        let predict = try XCTUnwrap(TemplateAdditionalSamplePreview(.init(), choice: .predict))
        XCTAssertEqual(predict.draft.text("predict", "question"), "明天中午哪种豆子卖得更多?")
        let picture = try XCTUnwrap(TemplateAdditionalSamplePreview(.init(), choice: .pricePair))
        XCTAssertEqual(picture.draft.rows("pricePair", "items").map { $0.object?["name"]?.string }, ["木牌", "霓虹灯", "手写纸板"])
    }
    func testEditedFieldsAndMissingTitleAreNotOverwritten() throws {
        var original = TemplateAdvancedDraft(); original.set("predict", "question", .string("My question"))
        var fields = try XCTUnwrap(original.value["pricePair"]?.object); fields.removeValue(forKey: "title"); original.value["pricePair"] = .object(fields)
        XCTAssertEqual(try XCTUnwrap(TemplateAdditionalSamplePreview(original, choice: .predict)).draft.text("predict", "question"), "My question")
        XCTAssertNil(try XCTUnwrap(TemplateAdditionalSamplePreview(original, choice: .pricePair)).draft.value["pricePair"]?.object?["title"])
    }
    func testExistingImagesAndUnknownOptionDataRemainUntouched() throws {
        var original = TemplateAdvancedDraft(); var rows = original.rows("pricePair", "items")
        var row = try XCTUnwrap(rows[0].object); row["imageUrl"] = .string("https://example.invalid/keep.jpg"); row["future"] = .bool(true); rows[0] = .object(row)
        original.set("pricePair", "items", .array(rows))
        let item = try XCTUnwrap(TemplateAdditionalSamplePreview(original, choice: .pricePair))
        XCTAssertEqual(item.draft.rows("pricePair", "items"), rows); XCTAssertFalse(item.filledFields.contains("items"))
    }
    func testD6UsesSourceFixedFifthFace() throws {
        let item = try XCTUnwrap(TemplateAdditionalSamplePreview(.init(), choice: .dice))
        let sample = try TemplateD6Rehearsal(draft: item.draft).sample(pips: [5])
        XCTAssertEqual(sample.total, 5); XCTAssertEqual(sample.action, "把杯子摆正")
    }
    func testTwoDiceUseSourceFivePlusFourAndNeverChooseFaceText() throws {
        var original = TemplateAdvancedDraft(); original.set("diceRoll", "diceCount", .number(2))
        let item = try XCTUnwrap(TemplateAdditionalSamplePreview(original, choice: .dice))
        let sample = try TemplateD6Rehearsal(draft: item.draft).sample(pips: [5, 4])
        XCTAssertEqual(sample.total, 9); XCTAssertNil(sample.action)
    }
    func testModeSwitchInitializesD20DefaultsOnlyInsideCopy() throws {
        let original = TemplateAdvancedDraft(), before = original
        let item = try XCTUnwrap(TemplateAdditionalSamplePreview(original, choice: .d20))
        XCTAssertEqual(item.draft.diceMode, "d20"); XCTAssertEqual(item.draft.text("diceRoll", "dc"), "10")
        XCTAssertEqual(item.draft.text("diceRoll", "successText"), "你发现了门后的线索")
        XCTAssertEqual(original, before); XCTAssertNil(original.value["diceRoll"]?.object?["dc"])
    }
    func testConfiguredD20KeepsItsDifficultyModifierAndTexts() throws {
        var original = TemplateAdvancedDraft(); original.setDiceMode("d20")
        original.set("diceRoll", "dc", .number(18)); original.set("diceRoll", "modifier", .number(2)); original.set("diceRoll", "successText", .string("My success"))
        let item = try XCTUnwrap(TemplateAdditionalSamplePreview(original, choice: .d20))
        XCTAssertEqual(item.draft.text("diceRoll", "dc"), "18"); XCTAssertEqual(item.draft.text("diceRoll", "modifier"), "2")
        XCTAssertEqual(item.draft.text("diceRoll", "successText"), "My success")
    }
    func testAlreadyD20MissingRequiredFieldFailsClosedInsteadOfRepair() throws {
        var original = TemplateAdvancedDraft(); original.setDiceMode("d20")
        var fields = try XCTUnwrap(original.value["diceRoll"]?.object); fields.removeValue(forKey: "dc"); original.value["diceRoll"] = .object(fields)
        let before = original; XCTAssertNil(TemplateAdditionalSamplePreview(original, choice: .d20)); XCTAssertEqual(original, before)
    }
    func testD6ModePreviewPreservesOriginalD20ModeAndData() throws {
        var original = TemplateAdvancedDraft(); original.setDiceMode("d20"); original.set("diceRoll", "dc", .number(19))
        let before = original, item = try XCTUnwrap(TemplateAdditionalSamplePreview(original, choice: .dice))
        XCTAssertEqual(item.draft.diceMode, "d6"); XCTAssertEqual(item.draft.text("diceRoll", "dc"), "19"); XCTAssertEqual(original, before)
    }
    func testUnknownSiblingsAndWhitespaceArePreserved() throws {
        var original = TemplateAdvancedDraft(); original.value["future"] = .object(["opaque": .string("Keep")]); original.set("predict", "question", .string(" "))
        let item = try XCTUnwrap(TemplateAdditionalSamplePreview(original, choice: .predict))
        XCTAssertEqual(item.draft.value["future"], original.value["future"]); XCTAssertEqual(item.draft.text("predict", "question"), " ")
    }
    func testMalformedFamilyAndInvalidDiceCountAreNotRebuilt() {
        var original = TemplateAdvancedDraft(); original.value["predict"] = .string("Opaque")
        XCTAssertNil(TemplateAdditionalSamplePreview(original, choice: .predict))
        original.set("diceRoll", "diceCount", .number(3)); XCTAssertNil(TemplateAdditionalSamplePreview(original, choice: .dice))
    }
}

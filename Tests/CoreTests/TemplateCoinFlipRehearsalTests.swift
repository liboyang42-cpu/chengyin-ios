import XCTest
@testable import QuestifyCore

final class TemplateCoinFlipRehearsalTests: XCTestCase {
    func testCurrentConfigurationHasSourceFallbacksWithoutSeedingOrEnabling() throws {
        let original = TemplateAdvancedDraft(), item = try XCTUnwrap(TemplateCoinFlipRehearsal(original, mode: .currentConfiguration))
        XCTAssertEqual(item.kicker, "抛一次,认结果"); XCTAssertEqual(item.heads.label, "正面"); XCTAssertEqual(item.tails.label, "反面")
        XCTAssertEqual(item.heads.action, ""); XCTAssertEqual(item.tails.action, ""); XCTAssertEqual(item.draft, original)
        XCTAssertFalse(item.draft.enabled("coinFlip")); XCTAssertTrue(item.filledFields.isEmpty)
    }
    func testConfiguredTitlesAndActionsUseSourceTrimIncludingBOM() throws {
        var draft = TemplateAdvancedDraft(); draft.set("coinFlip", "kicker", .string("\u{FEFF}  My coin \n"))
        draft.setNested("coinFlip", "heads", "label", " Heads label "); draft.setNested("coinFlip", "heads", "action", " Do A \n")
        draft.setNested("coinFlip", "tails", "label", " Tail label "); draft.setNested("coinFlip", "tails", "action", " Do B ")
        let item = try XCTUnwrap(TemplateCoinFlipRehearsal(draft, mode: .currentConfiguration))
        XCTAssertEqual(item.kicker, "My coin"); XCTAssertEqual(item.heads, .init(label: "Heads label", action: "Do A"))
        XCTAssertEqual(item.tails, .init(label: "Tail label", action: "Do B")); XCTAssertEqual(item.draft, draft)
    }
    func testDefaultSelectionIsSourceHeadsAndHasNoPrematureResult() throws {
        var item = try XCTUnwrap(TemplateCoinFlipRehearsal(.init(), mode: .sourceExample))
        XCTAssertEqual(item.selection, .heads); XCTAssertNil(item.result); item.showSelectedResult()
        XCTAssertEqual(item.result?.face, .heads); XCTAssertEqual(item.result?.side.action, "这杯店家请")
    }
    func testTailsResultKeepsMatchingLabelAndAction() throws {
        var item = try XCTUnwrap(TemplateCoinFlipRehearsal(.init(), mode: .sourceExample)); item.select(.tails); item.showSelectedResult()
        XCTAssertEqual(item.result?.face, .tails); XCTAssertEqual(item.result?.side.label, "反面"); XCTAssertEqual(item.result?.side.action, "你请下一杯")
    }
    func testTryAgainIsDeterministicForSelectedFace() throws {
        var item = try XCTUnwrap(TemplateCoinFlipRehearsal(.init(), mode: .sourceExample)); item.select(.tails); item.showSelectedResult()
        let first = item.result; item.showSelectedResult(); XCTAssertEqual(item.result, first)
    }
    func testChangingFaceClearsOldResult() throws {
        var item = try XCTUnwrap(TemplateCoinFlipRehearsal(.init(), mode: .sourceExample)); item.showSelectedResult(); item.select(.tails)
        XCTAssertNil(item.result); XCTAssertEqual(item.selection, .tails)
    }
    func testResetRestoresHeadsAndClearsResultWithoutChangingConfiguration() throws {
        var item = try XCTUnwrap(TemplateCoinFlipRehearsal(.init(), mode: .sourceExample)); let configuration = item.draft
        item.select(.tails); item.showSelectedResult(); item.reset()
        XCTAssertEqual(item.selection, .heads); XCTAssertNil(item.result); XCTAssertEqual(item.draft, configuration)
    }
    func testSourceExampleFillsOnlyThreePristineFieldsInCopy() throws {
        let original = TemplateAdvancedDraft(), before = original, item = try XCTUnwrap(TemplateCoinFlipRehearsal(original, mode: .sourceExample))
        XCTAssertEqual(item.filledFields, ["heads", "kicker", "tails"]); XCTAssertEqual(item.kicker, "抛完照做")
        XCTAssertTrue(item.draft.enabled("coinFlip")); XCTAssertEqual(original, before)
    }
    func testEditedSideIncludingUnknownFieldsIsNotReplacedByDemo() throws {
        var draft = TemplateAdvancedDraft(); let side: TemplateAuthoringJSON = .object(["label": .string("Mine"), "action": .string(""), "future": .bool(true)])
        draft.set("coinFlip", "heads", side)
        let item = try XCTUnwrap(TemplateCoinFlipRehearsal(draft, mode: .sourceExample))
        XCTAssertEqual(item.draft.value["coinFlip"]?.object?["heads"], side); XCTAssertEqual(item.heads.action, ""); XCTAssertFalse(item.filledFields.contains("heads"))
    }
    func testMissingNestedSideStaysAbsentAndDisplaysFallbackOnly() throws {
        var draft = TemplateAdvancedDraft(); var fields = try XCTUnwrap(draft.value["coinFlip"]?.object); fields.removeValue(forKey: "heads"); draft.value["coinFlip"] = .object(fields)
        let item = try XCTUnwrap(TemplateCoinFlipRehearsal(draft, mode: .sourceExample))
        XCTAssertNil(item.draft.value["coinFlip"]?.object?["heads"]); XCTAssertEqual(item.heads.label, "正面"); XCTAssertEqual(item.heads.action, "")
    }
    func testWhitespaceAndUnknownSiblingsArePreservedInCopy() throws {
        var draft = TemplateAdvancedDraft(); draft.set("coinFlip", "kicker", .string(" ")); draft.value["future"] = .object(["opaque": .bool(true)])
        let item = try XCTUnwrap(TemplateCoinFlipRehearsal(draft, mode: .sourceExample))
        XCTAssertEqual(item.draft.text("coinFlip", "kicker"), " "); XCTAssertEqual(item.kicker, "抛一次,认结果"); XCTAssertEqual(item.draft.value["future"], draft.value["future"])
    }
    func testMalformedObjectsAndNonStringLabelsFailClosed() {
        var draft = TemplateAdvancedDraft(); draft.value["coinFlip"] = .string("Opaque"); XCTAssertNil(TemplateCoinFlipRehearsal(draft, mode: .currentConfiguration))
        draft = .init(); draft.set("coinFlip", "heads", .array([])); XCTAssertNil(TemplateCoinFlipRehearsal(draft, mode: .sourceExample))
        draft = .init(); draft.set("coinFlip", "tails", .object(["label": .number(42)])); XCTAssertNil(TemplateCoinFlipRehearsal(draft, mode: .currentConfiguration))
    }
}

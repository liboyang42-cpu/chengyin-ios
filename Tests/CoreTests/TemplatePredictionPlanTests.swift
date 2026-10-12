import XCTest
@testable import QuestifyCore

final class TemplatePredictionPlanTests: XCTestCase {
    private func fixture() -> TemplateAdvancedDraft {
        var draft = TemplateAdvancedDraft(); draft.setCreatorEnabled(.predict, true)
        draft.set("predict", "question", .string("Which drink?")); draft.set("predict", "hint", .string("Revealed tomorrow"))
        draft.set("predict", "options", .array([.object(["key": .string("A"), "label": .string("Tea")]), .object(["key": .string("B"), "label": .string("Coffee")])]))
        draft.set("predict", "closeAtHour", .number(20)); draft.set("predict", "revealDays", .number(1)); draft.set("predict", "revealHour", .number(20)); return draft
    }
    func testOpeningReadsCurrentPlanWithoutChangingDraft() {
        let draft = fixture(), before = draft, plan = TemplatePredictionPlan(draft)
        XCTAssertTrue(plan.isSupported); XCTAssertEqual(plan.question, "Which drink?"); XCTAssertEqual(plan.rows.map(\.key), ["A", "B"]); XCTAssertEqual(plan.timing(.closeAtHour), 20); XCTAssertEqual(draft, before)
    }
    func testQuestionHintAndLabelsPatchOnlyTheirLeaf() throws {
        let draft = fixture()
        for field in [TemplatePredictionPlan.TextField.question, .hint] {
            let next = try XCTUnwrap(TemplatePredictionPlan(draft).applying(.text(field, " raw\n"), to: draft)); var expected = draft; expected.set("predict", field.rawValue, .string(" raw\n")); XCTAssertEqual(next, expected)
        }
        let next = try XCTUnwrap(TemplatePredictionPlan(draft).applying(.label(1, "Latte"), to: draft)); var expected = draft
        expected.setCreatorValue(.predict, path: [.field("options"), .index(1), .field("label")], entry: .string("Latte")); XCTAssertEqual(next, expected)
    }
    func testAutomaticKeysUseNativeAllocatorAndPreserveUnknownRowFields() throws {
        var draft = fixture(); draft.setCreatorValue(.predict, path: [.field("options"), .index(0), .field("key")], entry: .string("options_1")); draft.setCreatorValue(.predict, path: [.field("options"), .index(0), .field("future")], entry: .string("keep"))
        let before = draft.value["predict"]?.object?["options"]?.array, next = try XCTUnwrap(TemplatePredictionPlan(draft).applying(.add, to: draft)), plan = TemplatePredictionPlan(next)
        XCTAssertEqual(plan.rows.map(\.key), ["options_1", "B", "options_2"]); XCTAssertEqual(plan.rows.last?.label, "")
        XCTAssertEqual(Array((next.value["predict"]?.object?["options"]?.array ?? []).prefix(2)), before)
    }
    func testMaximumFourAndEmptyIntermediateThenRebuild() throws {
        var draft = fixture()
        for _ in 0..<2 { draft = try XCTUnwrap(TemplatePredictionPlan(draft).applying(.add, to: draft)) }
        XCTAssertEqual(TemplatePredictionPlan(draft).rows.count, 4); XCTAssertNil(TemplatePredictionPlan(draft).applying(.add, to: draft))
        while !TemplatePredictionPlan(draft).rows.isEmpty { draft = try XCTUnwrap(TemplatePredictionPlan(draft).applying(.remove(0), to: draft)) }
        XCTAssertTrue(TemplatePredictionPlan(draft).isSupported); XCTAssertTrue(draft.creatorIssues(.predict).contains { $0.path == "options" && $0.code == "count" })
        draft = try XCTUnwrap(TemplatePredictionPlan(draft).applying(.add, to: draft)); XCTAssertEqual(TemplatePredictionPlan(draft).rows.count, 1)
    }
    func testDuplicateKeysAreTargetedByOccurrenceAndRepairableByRemoval() throws {
        var draft = fixture(); draft.setCreatorValue(.predict, path: [.field("options"), .index(1), .field("key")], entry: .string("A"))
        draft = try XCTUnwrap(TemplatePredictionPlan(draft).applying(.label(1, "Second"), to: draft)); XCTAssertEqual(TemplatePredictionPlan(draft).rows.map(\.label), ["Tea", "Second"])
        draft = try XCTUnwrap(TemplatePredictionPlan(draft).applying(.remove(0), to: draft)); XCTAssertEqual(TemplatePredictionPlan(draft).rows.map(\.label), ["Second"])
        XCTAssertNil(TemplatePredictionPlan(draft).applying(.label(1, "bad"), to: draft)); XCTAssertNil(TemplatePredictionPlan(draft).applying(.remove(-1), to: draft))
    }
    func testAllHoursAndDaysWriteNumericValuesInRange() throws {
        XCTAssertEqual(TemplatePredictionPlan.hours, Array(0...23)); XCTAssertEqual(TemplatePredictionPlan.days, Array(0...30))
        for field in TemplatePredictionPlan.TimingField.allCases {
            for value in field == .revealDays ? TemplatePredictionPlan.days : TemplatePredictionPlan.hours {
                let draft = fixture(), next = try XCTUnwrap(TemplatePredictionPlan(draft).applying(.timing(field, value), to: draft)); var expected = draft; expected.set("predict", field.rawValue, .number(Double(value))); XCTAssertEqual(next, expected)
            }
            for value in [-1, field == .revealDays ? 31 : 24] { let draft = fixture(); XCTAssertNil(TemplatePredictionPlan(draft).applying(.timing(field, value), to: draft)) }
        }
    }
    func testNumericStringsAndMissingDefaultsAreNotNormalizedOnOpen() {
        var draft = fixture(); draft.set("predict", "revealDays", .string(" 2 ")); draft.setCreatorValue(.predict, path: [.field("closeAtHour")], entry: nil)
        let before = draft, plan = TemplatePredictionPlan(draft); XCTAssertTrue(plan.isSupported); XCTAssertEqual(plan.timing(.revealDays), 2); XCTAssertEqual(plan.timing(.closeAtHour), 20); XCTAssertEqual(draft, before)
    }
    func testSameDayConflictUsesExistingValidatorAndNeverAdjustsOtherTimes() throws {
        var draft = fixture(); draft = try XCTUnwrap(TemplatePredictionPlan(draft).applying(.timing(.revealDays, 0), to: draft)); draft = try XCTUnwrap(TemplatePredictionPlan(draft).applying(.timing(.revealHour, 19), to: draft))
        XCTAssertTrue(TemplatePredictionPlan(draft).sameDayConflict); XCTAssertEqual(TemplatePredictionPlan(draft).timing(.closeAtHour), 20); XCTAssertTrue(draft.creatorIssues(.predict).contains { $0.path == "revealHour" && $0.code == "range" })
        draft = try XCTUnwrap(TemplatePredictionPlan(draft).applying(.timing(.revealHour, 20), to: draft)); XCTAssertFalse(TemplatePredictionPlan(draft).sameDayConflict); XCTAssertTrue(draft.creatorIssues(.predict).isEmpty)
    }
    func testTomorrowAllowsEarlierHourWithoutCalendarDateConversion() throws {
        var draft = fixture(); draft = try XCTUnwrap(TemplatePredictionPlan(draft).applying(.timing(.revealHour, 0), to: draft)); XCTAssertFalse(TemplatePredictionPlan(draft).sameDayConflict); XCTAssertTrue(draft.creatorIssues(.predict).isEmpty)
    }
    func testMalformedValuesFallBackWithoutDiscardingRawData() {
        for (field, value) in [("revealDays",TemplateAuthoringJSON.string(" ")),("revealHour",.number(24)),("closeAtHour",.number(1.5)),("options",.array([.object(["label":.string("No key")])])),("question",.bool(true)),("hint",.null)] {
            var draft = fixture(); draft.set("predict", field, value); let before = draft, plan = TemplatePredictionPlan(draft); XCTAssertFalse(plan.isSupported); XCTAssertNil(plan.applying(.add, to: draft)); XCTAssertEqual(draft, before)
        }
    }
    func testStaleByteDistinctAndDisabledPlanRejectChanges() {
        var draft = fixture(); draft.set("predict", "question", .string("\u{00E9}")); let plan = TemplatePredictionPlan(draft); draft.set("predict", "question", .string("e\u{0301}"))
        XCTAssertFalse(plan.isCurrent(draft)); XCTAssertNil(plan.applying(.add, to: draft)); draft.setCreatorEnabled(.predict, false); XCTAssertFalse(TemplatePredictionPlan(draft).canEdit)
    }
    func testOtherFamiliesXPAndFutureFieldsSurvive() throws {
        var draft = fixture(); draft.set("predict", "xp", .number(77)); draft.set("predict", "future", .array([.string("keep")])); draft.set("timer", "enabled", .bool(true))
        let next = try XCTUnwrap(TemplatePredictionPlan(draft).applying(.timing(.revealDays, 30), to: draft)); var expected = draft; expected.set("predict", "revealDays", .number(30)); XCTAssertEqual(next, expected)
    }
    func testExistingSerializationAndDraftRoundTripKeepRelativeSchedule() throws {
        var draft = fixture(); draft = try XCTUnwrap(TemplatePredictionPlan(draft).applying(.timing(.revealDays, 30), to: draft))
        let raw = try draft.serialize(), object = try JSONSerialization.jsonObject(with: Data(raw.utf8)) as? [String: Any], predict = object?["predict"] as? [String: Any]; XCTAssertEqual(predict?["revealDays"] as? Int, 30); XCTAssertNil(predict?["date"])
        var local = TemplateAuthoringDraft(title: "Predict"); local.advanced = draft; XCTAssertEqual(try JSONDecoder().decode(TemplateAuthoringDraft.self, from: JSONEncoder().encode(local)), local)
    }
}

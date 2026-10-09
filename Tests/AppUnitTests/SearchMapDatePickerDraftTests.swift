import XCTest
@testable import Questify

@MainActor final class SearchMapDatePickerDraftTests: XCTestCase {
    private var zone: TimeZone { TimeZone(secondsFromGMT: 0)! }
    private var now: Date { Date(timeIntervalSince1970: 1_791_460_800) }
    private var applied: GlobalSearchQuery {
        .init(keyword: "walk", categoryID: 7, startDate: "2028-02-28", endDate: "2028-03-31", minimumPrice: 20, maximumPrice: 100)
    }
    private func picker(_ field: SearchMapDatePickerField, draft: SearchMapDateFilterDraft) -> SearchMapDatePickerDraft {
        SearchMapDatePickerDraft(field: field, draft: draft, now: now, timeZone: zone)
    }

    func testWheelChangesCancelAndReopenLeaveOuterDraftAndAppliedQueryUnchanged() {
        let original = applied, draft = SearchMapDateFilterDraft(filter: original)
        var cancelled = picker(.start, draft: draft)
        cancelled.selectYear(2029); cancelled.selectMonth(12); cancelled.selectDay(31)
        // Cancel and interactive dismissal discard this value without confirming.
        let reopened = picker(.start, draft: draft)
        XCTAssertEqual(cancelled.value, "2029-12-31")
        XCTAssertEqual(reopened.value, "2028-02-28")
        XCTAssertEqual(try? draft.applying(to: original), original)
    }

    func testConfirmChangesOnlyOuterDraftAndFilterCancelDiscardsIt() throws {
        let original = applied
        var draft = SearchMapDateFilterDraft(filter: original)
        var selection = picker(.start, draft: draft); selection.selectDay(29)
        draft = try selection.confirming(in: draft)
        XCTAssertEqual(draft.startDate, "2028-02-29"); XCTAssertEqual(draft.endDate, original.endDate)
        XCTAssertEqual(original.startDate, "2028-02-28")
        let reopenedAfterFilterCancel = SearchMapDateFilterDraft(filter: original)
        XCTAssertEqual(picker(.start, draft: reopenedAfterFilterCancel).value, "2028-02-28")
    }

    func testApplyCommitsConcreteDateAndPreservesOtherFiltersOnReopen() throws {
        let original = applied
        var draft = SearchMapDateFilterDraft(filter: original)
        var selection = picker(.end, draft: draft); selection.selectMonth(2); selection.selectDay(29)
        draft = try selection.confirming(in: draft)
        let committed = try draft.applying(to: original)
        XCTAssertEqual(committed.startDate, "2028-02-28"); XCTAssertEqual(committed.endDate, "2028-02-29")
        XCTAssertEqual(committed.keyword, original.keyword); XCTAssertEqual(committed.categoryID, original.categoryID)
        XCTAssertEqual(committed.minimumPrice, original.minimumPrice); XCTAssertEqual(committed.maximumPrice, original.maximumPrice)
        let reopened = SearchMapDateFilterDraft(filter: committed)
        XCTAssertEqual(picker(.end, draft: reopened).value, "2028-02-29")
        XCTAssertEqual(try reopened.applying(to: committed), committed)
    }

    func testResetIsDraftLocalAndReopeningEndPickerUsesStartOrPhoneDay() throws {
        let original = applied
        let resetFilter = GlobalSearchQuery(keyword: original.keyword)
        var reset = SearchMapDateFilterDraft(filter: resetFilter)
        XCTAssertEqual(picker(.end, draft: reset).value, "2026-10-08")
        XCTAssertEqual(original.startDate, "2028-02-28")
        let cleared = try reset.applying(to: resetFilter)
        XCTAssertNil(cleared.startDate); XCTAssertNil(cleared.endDate)
        XCTAssertEqual(cleared.keyword, original.keyword); XCTAssertNil(cleared.categoryID)
        reset.startDate = "2028-02-29"
        XCTAssertEqual(picker(.end, draft: reset).value, "2028-02-29")
    }

    func testPresetsManualFieldsAndRepeatedPickerOpenRemainInteroperable() throws {
        var draft = SearchMapDateFilterDraft(filter: .init())
        try draft.select(.tomorrow, now: now, timeZone: zone)
        XCTAssertEqual(picker(.start, draft: draft).value, "2026-10-09")
        XCTAssertEqual(picker(.end, draft: draft).value, "2026-10-09")
        var selection = picker(.end, draft: draft); selection.selectDay(10)
        draft = try selection.confirming(in: draft)
        XCTAssertEqual(picker(.end, draft: draft).value, "2026-10-10")
        draft.endDate = "2026-10-11"
        XCTAssertEqual(picker(.end, draft: draft).value, "2026-10-11")
        try draft.select(.today, now: now, timeZone: zone)
        XCTAssertEqual(draft.startDate, "2026-10-08"); XCTAssertEqual(draft.endDate, "2026-10-08")
    }

    func testFailedConfirmKeepsDraftAndAllowsCorrectionBeforeApply() throws {
        var draft = SearchMapDateFilterDraft(filter: applied)
        var selection = picker(.end, draft: draft)
        selection.selectMonth(2); selection.selectDay(27)
        XCTAssertThrowsError(try selection.confirming(in: draft))
        XCTAssertEqual(draft.endDate, "2028-03-31")
        selection.selectDay(29)
        draft = try selection.confirming(in: draft)
        XCTAssertEqual(try draft.applying(to: applied).endDate, "2028-02-29")
    }
}

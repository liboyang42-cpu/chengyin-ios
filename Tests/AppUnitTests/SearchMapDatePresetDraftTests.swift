import XCTest
@testable import Questify

@MainActor final class SearchMapDatePresetDraftTests: XCTestCase {
    private var instant: Date { Date(timeIntervalSince1970: 1_791_460_800) } // 2026-10-08 12:00 UTC
    private var zone: TimeZone { TimeZone(secondsFromGMT: 0)! }
    func testCancelDiscardsShippingDraftWithoutChangingAppliedQuery() throws {
        let applied = GlobalSearchQuery(keyword: "walk", categoryID: 7, startDate: "2028-02-29", endDate: "2028-03-01")
        var cancelled = SearchMapDateFilterDraft(filter: applied)
        try cancelled.select(.tomorrow, now: instant, timeZone: zone)
        XCTAssertNotEqual(cancelled.startDate, applied.startDate)
        // Cancel never invokes applying(to:); reopening starts from the unchanged query.
        let reopened = SearchMapDateFilterDraft(filter: applied)
        XCTAssertEqual(reopened.startDate, "2028-02-29"); XCTAssertEqual(reopened.endDate, "2028-03-01")
        XCTAssertEqual(applied.keyword, "walk"); XCTAssertEqual(applied.categoryID, 7)
    }
    func testApplyReopenAndRepeatedReadsKeepConcreteDayUntilAnotherTap() throws {
        var draft = SearchMapDateFilterDraft(filter: .init())
        try draft.select(.tomorrow, now: instant, timeZone: zone)
        let applied = try draft.applying(to: .init())
        XCTAssertEqual(applied.startDate, "2026-10-09"); XCTAssertEqual(applied.endDate, "2026-10-09")
        var reopened = SearchMapDateFilterDraft(filter: applied)
        XCTAssertEqual(try reopened.applying(to: applied), applied)
        // A new explicit tap after midnight can move the draft; the old query stays fixed.
        try reopened.select(.tomorrow, now: instant.addingTimeInterval(172800), timeZone: zone)
        XCTAssertEqual(applied.startDate, "2026-10-09")
        XCTAssertEqual(try reopened.applying(to: applied).startDate, "2026-10-11")
    }
    func testDraftResetAndManualEditsDoNotCommitBeforeApply() throws {
        let applied = GlobalSearchQuery(keyword: "walk", startDate: "2026-10-08", endDate: "2026-10-08")
        var draft = SearchMapDateFilterDraft(filter: GlobalSearchQuery(keyword: applied.keyword))
        XCTAssertEqual(applied.startDate, "2026-10-08")
        XCTAssertNil(try draft.applying(to: applied).startDate)
        draft.startDate = "2026-10-07"; draft.endDate = "2026-10-10"
        XCTAssertEqual(try draft.applying(to: applied).endDate, "2026-10-10")
        XCTAssertEqual(applied.endDate, "2026-10-08")
    }
    func testAppliedPresetParticipatesInExistingRefreshQueryScopeAndAreaFence() throws {
        let area = RoamSearchArea(coordinate: try XCTUnwrap(RoamCoordinate(latitude: 1, longitude: 2)), label: "Synthetic")
        let original = CityNodeSearchQuery(filter: .init(), area: area)
        let scope = UUID(), result = CityNodeSearchResults(activities: [], nodes: [])
        var pages = SearchMapPagination()
        pages.reset(query: original, scope: scope, manualAreaRevision: 1, result: result)
        var refresh = SearchMapRefresh()
        let ticket = try XCTUnwrap(refresh.begin(query: original, scope: scope, manualAreaRevision: 1, result: result, pagination: pages))
        var draft = SearchMapDateFilterDraft(filter: original.filter)
        try draft.select(.today, now: instant, timeZone: zone)
        XCTAssertTrue(refresh.accepts(ticket, query: original, scope: scope, manualAreaRevision: 1))
        var changed = original; changed.filter = try draft.applying(to: original.filter)
        XCTAssertFalse(refresh.accepts(ticket, query: changed, scope: scope, manualAreaRevision: 1))
        XCTAssertFalse(pages.matches(query: changed, scope: scope, manualAreaRevision: 1))
        XCTAssertFalse(refresh.accepts(ticket, query: original, scope: UUID(), manualAreaRevision: 1))
        XCTAssertFalse(refresh.accepts(ticket, query: original, scope: scope, manualAreaRevision: 2))
        refresh.invalidate()
        XCTAssertFalse(refresh.accepts(ticket, query: original, scope: scope, manualAreaRevision: 1))
    }

    func testGlobalPresetCancelKeepsQueryAndAllNonDateFilters() throws {
        let original = GlobalSearchQuery(keyword: "Café & 城", categoryID: 7, startDate: "2028-02-29",
                                         endDate: "2028-03-01", minimumPrice: 20, maximumPrice: 100)
        var draft = SearchMapDateFilterDraft(filter: original)
        try draft.select(.today, now: instant, timeZone: zone)
        try draft.select(.tomorrow, now: instant, timeZone: zone)
        // Cancel discards only the draft; no applying(to:) call is made.
        let reopened = SearchMapDateFilterDraft(filter: original)
        XCTAssertEqual(reopened.startDate, "2028-02-29"); XCTAssertEqual(reopened.endDate, "2028-03-01")
        let applied = try draft.applying(to: original)
        XCTAssertEqual(applied.keyword, original.keyword); XCTAssertEqual(applied.categoryID, original.categoryID)
        XCTAssertEqual(applied.minimumPrice, original.minimumPrice); XCTAssertEqual(applied.maximumPrice, original.maximumPrice)
        XCTAssertEqual(applied.startDate, "2026-10-09"); XCTAssertEqual(applied.endDate, "2026-10-09")
        XCTAssertEqual(original.startDate, "2028-02-29")
    }
    func testGlobalPresetReopenDoesNotMoveAfterRolloverOrTimeZoneChange() throws {
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-08T01:30:00Z"))
        let losAngeles = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let kiritimati = try XCTUnwrap(TimeZone(identifier: "Pacific/Kiritimati"))
        var draft = SearchMapDateFilterDraft(filter: .init(keyword: "walk"))
        try draft.select(.today, now: now, timeZone: losAngeles)
        let applied = try draft.applying(to: .init(keyword: "walk"))
        XCTAssertEqual(applied.startDate, "2026-10-07")
        var reopened = SearchMapDateFilterDraft(filter: applied)
        // Reopening and applying the stored civil date do not consult the current clock or zone.
        XCTAssertEqual(try reopened.applying(to: applied), applied)
        try reopened.select(.today, now: now, timeZone: kiritimati)
        XCTAssertEqual(reopened.startDate, "2026-10-08")
        try reopened.select(.tomorrow, now: now.addingTimeInterval(172800), timeZone: kiritimati)
        XCTAssertEqual(reopened.startDate, "2026-10-11")
        XCTAssertEqual(applied.startDate, "2026-10-07"); XCTAssertEqual(applied.endDate, "2026-10-07")
        XCTAssertEqual(SearchMapDateFilterDraft(filter: applied).startDate, "2026-10-07")
    }
    func testGlobalDatePresetFiltersOnlyKnownTopicAndActivityStartDays() throws {
        var draft = SearchMapDateFilterDraft(filter: .init(keyword: "walk"))
        try draft.select(.tomorrow, now: instant, timeZone: zone)
        let applied = try draft.applying(to: .init(keyword: "walk"))
        for kind in [GlobalSearchKind.topic, .activity] {
            XCTAssertTrue(applied.matches(kind: kind, date: "2026-10-09 23:59:59", price: nil))
            XCTAssertFalse(applied.matches(kind: kind, date: "2026-10-08", price: nil))
            XCTAssertFalse(applied.matches(kind: kind, date: "2026-10-10", price: nil))
            XCTAssertTrue(applied.matches(kind: kind, date: nil, price: nil))
        }
        for kind in [GlobalSearchKind.club, .merchant] {
            XCTAssertTrue(applied.matches(kind: kind, date: "2026-10-08", price: nil))
        }
        let reset = SearchMapDateFilterDraft(filter: .init(keyword: applied.keyword))
        let cleared = try reset.applying(to: applied)
        XCTAssertNil(cleared.startDate); XCTAssertNil(cleared.endDate); XCTAssertEqual(cleared.keyword, "walk")
    }
}

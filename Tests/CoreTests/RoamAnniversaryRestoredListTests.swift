import XCTest
@testable import QuestifyCore

// Restored original tests in a new leaf. The old fixture-dependent test is not moved.
final class RoamAnniversaryRestoredListTests: XCTestCase {
    private func owner(account: Int = 7, epoch: UInt64 = 1) throws -> RoamExperienceIdentity {
        RoamExperienceIdentity(scope: try RoamHistoryScope(market: "cn", deployment: URL(string: "https://example.com/roam")!,
                                                         accountID: account), epoch: epoch)
    }
    private func page(start: Int = 100, count: Int = 20, cursor: String? = "page_a", month: Int = 10,
                      day: Int = 19, referenceYear: Int = 2026) -> RoamAnniversaryPage {
        let items = (0..<count).map { offset in
            RoamAnniversaryMemory(id: String(start - offset), topicID: String(7000 + start - offset), title: "Route",
                completedAt: String(format: "2024-%02d-%02d 12:00:00.000", month, day), year: 2024, yearsAgo: referenceYear - 2024)
        }
        return RoamAnniversaryPage(month: month, day: day, referenceYear: referenceYear,
            asOfMs: 1_792_382_400_000, items: items, hasMore: cursor != nil, nextCursor: cursor)
    }
    private func seeded(_ owner: RoamExperienceIdentity, pages: Int = 1) throws -> RoamAnniversaryListState {
        var state = RoamAnniversaryListState(); state.bind(to: owner)
        let first = try XCTUnwrap(state.begin(.refresh, owner: owner))
        XCTAssertTrue(try state.accept([page()], for: first, owner: owner))
        if pages > 1 {
            let more = try XCTUnwrap(state.begin(.more, owner: owner))
            XCTAssertTrue(try state.accept([page(start: 80, cursor: "page_b")], for: more, owner: owner))
        }
        return state
    }

    func testInitialServerTodayThenPaginationPinsConfirmedShanghaiDay() throws {
        let me = try owner(); var state = RoamAnniversaryListState(); state.bind(to: me)
        let first = try XCTUnwrap(state.begin(.refresh, owner: me))
        XCTAssertNil(first.query.month); XCTAssertNil(first.query.day); XCTAssertNil(first.query.cursor)
        XCTAssertTrue(try state.accept([page()], for: first, owner: me))
        let next = try XCTUnwrap(state.begin(.more, owner: me))
        XCTAssertEqual(next.query.month, 10); XCTAssertEqual(next.query.day, 19)
        XCTAssertEqual(next.query.referenceYear, 2026); XCTAssertEqual(next.query.cursor, "page_a")
        XCTAssertEqual(next.boundary?.id, "81")
        XCTAssertTrue(try state.accept([page(start: 80, cursor: nil)], for: next, owner: me))
        XCTAssertEqual(state.rows.count, 40); XCTAssertEqual(state.loadedPageCount, 2)
        XCTAssertNil(state.begin(.more, owner: me))
    }

    func testReturnRefreshKeepsAllPagesUntilAtomicReplacement() throws {
        let me = try owner(); var state = try seeded(me, pages: 2)
        let original = state.rows
        state.suspend() // Route covered the list.
        let request = try XCTUnwrap(state.begin(.refresh, owner: me))
        XCTAssertEqual(request.pageCount, 2); XCTAssertEqual(state.rows, original)
        XCTAssertEqual(request.query.month, 10); XCTAssertEqual(request.query.day, 19)
        XCTAssertNil(request.query.cursor); XCTAssertNil(request.query.referenceYear)
        XCTAssertTrue(try state.accept([page(cursor: "fresh_a"), page(start: 80, cursor: "fresh_b")], for: request, owner: me))
        XCTAssertEqual(state.rows, original); XCTAssertEqual(state.page?.nextCursor, "fresh_b")
        XCTAssertEqual(state.loadedPageCount, 2); XCTAssertFalse(state.isLoading)
    }

    func testPageTwoRouteUnavailableReturnThenReopenUsesRealTopicAndKeepsDate() throws {
        let me = try owner(); var list = try seeded(me, pages: 2)
        var navigation = RoamAnniversaryNavigationState(); navigation.bind(to: me)
        let item = try XCTUnwrap(list.rows.last)
        let target = try XCTUnwrap(RoamAnniversaryRouteTarget(memory: item))
        XCTAssertEqual(target.topicID, "7061"); XCTAssertNotEqual(target.topicID, item.id)
        XCTAssertTrue(navigation.open(target, memory: item, currentRows: list.rows, owner: me))
        let lease = try XCTUnwrap(navigation.openedPresentation)
        list.suspend()
        // A real topic-detail unavailable result leaves the navigation lease
        // intact. Its Back action is the same exact pop as successful detail.
        navigation.noteCovered(lease, owner: me)
        XCTAssertTrue(navigation.completeReturn(presentation: lease, owner: me))
        let refresh = try XCTUnwrap(list.begin(.refresh, owner: me))
        XCTAssertEqual(refresh.pageCount, 2); XCTAssertEqual(list.rows.count, 40)
        XCTAssertTrue(try list.accept([page(cursor: "fresh_a"), page(start: 80, count: 19, cursor: nil)],
                                     for: refresh, owner: me))
        XCTAssertEqual(list.displayedDay, .init(month: 10, day: 19)); XCTAssertEqual(list.rows.count, 39)
        XCTAssertFalse(navigation.open(target, memory: item, currentRows: list.rows, owner: me), "Unavailable route was removed by authoritative readback")
        let next = try XCTUnwrap(list.rows.last)
        XCTAssertTrue(navigation.open(try XCTUnwrap(RoamAnniversaryRouteTarget(memory: next)), memory: next,
                                     currentRows: list.rows, owner: me))
        XCTAssertFalse(navigation.completeReturn(presentation: lease, owner: me), "Old pop cannot close the reopened route")
        XCTAssertEqual(navigation.openedTarget?.topicID, "7062")
    }

    func testFailedReturnDoesNotEraseOriginalPagesAndRetryKeepsDepth() throws {
        let me = try owner(); var state = try seeded(me, pages: 2); let original = state.rows
        let request = try XCTUnwrap(state.begin(.refresh, owner: me))
        state.fail(APIError.httpStatus(503), for: request, owner: me)
        XCTAssertEqual(state.rows, original); XCTAssertEqual(state.page?.nextCursor, "page_b")
        XCTAssertEqual(state.error as? APIError, .httpStatus(503))
        XCTAssertEqual(state.begin(state.retryIntent, owner: me)?.pageCount, 2)
    }

    func testShortenedOrRemovedRouteResultCommitsAnHonestCompleteList() throws {
        let me = try owner(); var state = try seeded(me, pages: 2)
        let request = try XCTUnwrap(state.begin(.refresh, owner: me))
        XCTAssertTrue(try state.accept([page(count: 0, cursor: nil)], for: request, owner: me))
        XCTAssertTrue(state.rows.isEmpty); XCTAssertEqual(state.loadedPageCount, 1)
        XCTAssertNil(state.error); XCTAssertNil(state.begin(.more, owner: me))
    }

    func testDuplicateLoadAndStaleSuspendedCallbackAreRejected() throws {
        let me = try owner(); var state = try seeded(me)
        let first = try XCTUnwrap(state.begin(.more, owner: me))
        XCTAssertNil(state.begin(.more, owner: me)); XCTAssertNil(state.begin(.refresh, owner: me))
        state.suspend()
        let second = try XCTUnwrap(state.begin(.more, owner: me))
        XCTAssertNotEqual(first.generation, second.generation)
        XCTAssertFalse(try state.accept([page(start: 80, cursor: nil)], for: first, owner: me))
        state.fail(APIError.httpStatus(503), for: first, owner: me)
        XCTAssertTrue(state.isLoading); XCTAssertNil(state.error)
        XCTAssertTrue(try state.accept([page(start: 80, cursor: nil)], for: second, owner: me))
    }

    func testChangedDateRetiresOldReadAndClearsOldPagination() throws {
        let me = try owner(); var state = try seeded(me)
        let stale = try XCTUnwrap(state.begin(.more, owner: me))
        XCTAssertTrue(state.select(try XCTUnwrap(.init(month: 2, day: 29))))
        XCTAssertTrue(state.rows.isEmpty); XCTAssertNil(state.page); XCTAssertEqual(state.loadedPageCount, 0)
        XCTAssertFalse(try state.accept([page(start: 80, cursor: nil)], for: stale, owner: me))
        let fresh = try XCTUnwrap(state.begin(.refresh, owner: me))
        XCTAssertEqual(fresh.query.month, 2); XCTAssertEqual(fresh.query.day, 29); XCTAssertNil(fresh.query.cursor)
        XCTAssertTrue(try state.accept([page(count: 1, cursor: nil, month: 2, day: 29)], for: fresh, owner: me))
        XCTAssertFalse(state.select(try XCTUnwrap(.init(month: 2, day: 29))))
    }

    func testAccountEpochAndSignOutClearPrivateRowsAndRejectStaleResults() throws {
        let me = try owner()
        for next: RoamExperienceIdentity? in [try owner(account: 8), try owner(epoch: 2), nil] {
            var state = try seeded(me); let request = try XCTUnwrap(state.begin(.more, owner: me))
            state.bind(to: next)
            XCTAssertTrue(state.rows.isEmpty); XCTAssertNil(state.page); XCTAssertNil(state.selected)
            XCTAssertFalse(try state.accept([page(start: 80, cursor: nil)], for: request, owner: next))
            state.fail(APIError.unauthorized, for: request, owner: me)
            XCTAssertNil(state.error); XCTAssertNil(state.begin(.refresh, owner: me))
        }
    }

    func testUnauthorizedClearsPrivateRowsEvenBeforeHostIdentityChanges() throws {
        let me = try owner(); var state = try seeded(me)
        let request = try XCTUnwrap(state.begin(.more, owner: me))
        state.fail(APIError.unauthorized, for: request, owner: me)
        XCTAssertTrue(state.rows.isEmpty); XCTAssertNil(state.page); XCTAssertEqual(state.loadedPageCount, 0)
        XCTAssertEqual(state.error as? APIError, .unauthorized); XCTAssertEqual(state.retryIntent, .refresh)
    }

    func testReadDenialClearsRowsButPreservesServerResolvedDayForRecovery() throws {
        let me = try owner()
        for failure: APIError in [.unauthorized, .notConfigured, .httpStatus(403), .businessCode(403)] {
            var state = try seeded(me, pages: 2)
            XCTAssertNil(state.selected, "Initial date was resolved by the server")
            let request = try XCTUnwrap(state.begin(.more, owner: me))
            state.fail(failure, for: request, owner: me)
            XCTAssertTrue(state.rows.isEmpty); XCTAssertNil(state.page)
            XCTAssertEqual(state.loadedPageCount, 0); XCTAssertFalse(state.isLoading)
            XCTAssertEqual(state.displayedDay, .init(month: 10, day: 19))
            XCTAssertEqual(state.error as? APIError, failure); XCTAssertTrue(state.needsRefresh)
            XCTAssertFalse(try state.accept([page(start: 60, cursor: nil)], for: request, owner: me))
            let retry = try XCTUnwrap(state.begin(state.retryIntent, owner: me))
            XCTAssertEqual(retry.query.month, 10); XCTAssertEqual(retry.query.day, 19)
            XCTAssertNil(retry.query.cursor); XCTAssertEqual(retry.pageCount, 1)
        }
    }

    func testGrantRevocationWhileReadIsPendingRejectsLateSuccessAndError() throws {
        let me = try owner(); var state = try seeded(me)
        let request = try XCTUnwrap(state.begin(.more, owner: me))
        state.revokeAccess(APIError.notConfigured)
        XCTAssertFalse(try state.accept([page(start: 80, cursor: nil)], for: request, owner: me))
        state.fail(APIError.httpStatus(503), for: request, owner: me)
        XCTAssertTrue(state.rows.isEmpty); XCTAssertEqual(state.error as? APIError, .notConfigured)
        XCTAssertEqual(state.displayedDay, .init(month: 10, day: 19))
        let recovery = try XCTUnwrap(state.begin(.refresh, owner: me))
        XCTAssertTrue(try state.accept([page(count: 0, cursor: nil)], for: recovery, owner: me))
        XCTAssertTrue(state.rows.isEmpty); XCTAssertNotNil(state.page); XCTAssertNil(state.error)
        XCTAssertFalse(state.needsRefresh, "An authoritative empty list is a completed read")
    }

    func testRevokedCancellationClearsOnlyItsCurrentRequestBeforeBenignCancellationPath() throws {
        let me = try owner(); var state = try seeded(me, pages: 2)
        let revoked = try XCTUnwrap(state.begin(.more, owner: me))
        state.fail(CancellationError(), for: revoked, owner: me, isConfigured: false)
        XCTAssertTrue(state.rows.isEmpty); XCTAssertNil(state.page)
        XCTAssertEqual(state.error as? APIError, .notConfigured)
        XCTAssertEqual(state.displayedDay, .init(month: 10, day: 19))
        let recovery = try XCTUnwrap(state.begin(.refresh, owner: me))
        XCTAssertTrue(try state.accept([page()], for: recovery, owner: me))
        state.fail(CancellationError(), for: revoked, owner: me, isConfigured: false)
        XCTAssertEqual(state.rows.count, 20); XCTAssertNil(state.error)
        let ordinary = try XCTUnwrap(state.begin(.more, owner: me))
        state.fail(CancellationError(), for: ordinary, owner: me, isConfigured: true)
        XCTAssertEqual(state.rows.count, 20); XCTAssertEqual(state.loadedPageCount, 1)
        XCTAssertEqual(state.displayedDay, .init(month: 10, day: 19)); XCTAssertNil(state.error)
    }

    func testRevokedSelectedLeapDaySurvivesSameOwnerButNotAccountChange() throws {
        let me = try owner(); var state = try seeded(me)
        XCTAssertTrue(state.select(try XCTUnwrap(.init(month: 2, day: 29))))
        state.revokeAccess(APIError.notConfigured)
        state.bind(to: me)
        XCTAssertEqual(state.displayedDay, .init(month: 2, day: 29))
        let retry = try XCTUnwrap(state.begin(.refresh, owner: me))
        XCTAssertEqual(retry.query.month, 2); XCTAssertEqual(retry.query.day, 29)
        state.bind(to: try owner(account: 8))
        XCTAssertNil(state.selected); XCTAssertNil(state.displayedDay)
        XCTAssertFalse(state.isCurrent(retry, owner: me))
        XCTAssertTrue(state.needsRefresh)
    }

    func testPendingForegroundRefreshIsNotConsumedByForeignOrConcurrentRead() throws {
        let me = try owner(); var state = try seeded(me, pages: 2)
        let interrupted = try XCTUnwrap(state.begin(.more, owner: me))
        state.requestRefresh()
        XCTAssertNil(state.begin(.refresh, owner: me)); XCTAssertTrue(state.needsRefresh)
        state.suspend()
        XCTAssertNil(state.begin(.refresh, owner: try owner(account: 8)))
        XCTAssertTrue(state.needsRefresh)
        let resumed = try XCTUnwrap(state.begin(.refresh, owner: me))
        XCTAssertFalse(state.needsRefresh); XCTAssertEqual(resumed.pageCount, 2)
        XCTAssertEqual(resumed.query.month, 10); XCTAssertEqual(resumed.query.day, 19)
        XCTAssertFalse(try state.accept([page(start: 60, cursor: nil)], for: interrupted, owner: me))
        state.fail(APIError.unauthorized, for: interrupted, owner: me)
        XCTAssertEqual(state.rows.count, 40); XCTAssertNil(state.error); XCTAssertTrue(state.isLoading)
        XCTAssertTrue(try state.accept([page(cursor: "resumed_a"), page(start: 80, cursor: nil)],
                                      for: resumed, owner: me))
        XCTAssertFalse(state.needsRefresh); XCTAssertEqual(state.rows.count, 40)
    }

    func testBackgroundDetailKeepsLeaseAndDefersRefreshUntilExactReturn() throws {
        let me = try owner(); var list = try seeded(me, pages: 2)
        var navigation = RoamAnniversaryNavigationState(); navigation.bind(to: me)
        let item = try XCTUnwrap(list.rows.last)
        let target = try XCTUnwrap(RoamAnniversaryRouteTarget(memory: item))
        XCTAssertTrue(navigation.open(target, memory: item, currentRows: list.rows, owner: me))
        let lease = try XCTUnwrap(navigation.openedPresentation)
        list.suspend() // Detail covers the list.
        list.requestRefresh(); list.suspend() // Background must not pop detail.
        XCTAssertTrue(navigation.mayRemainOpen(lease, owner: me))
        XCTAssertTrue(list.needsRefresh); XCTAssertEqual(list.rows.count, 40)
        navigation.noteCovered(lease, owner: me)
        XCTAssertTrue(navigation.completeReturn(presentation: lease, owner: me))
        list.requestRefresh() // Pop may arrive before the list becomes visible.
        XCTAssertTrue(list.needsRefresh); XCTAssertFalse(list.isLoading)
        let resumed = try XCTUnwrap(list.begin(.refresh, owner: me))
        XCTAssertEqual(resumed.pageCount, 2); XCTAssertFalse(list.needsRefresh)
        XCTAssertFalse(navigation.completeReturn(presentation: lease, owner: me))
        list.fail(APIError.httpStatus(503), for: resumed, owner: me)
        XCTAssertEqual(list.rows.count, 40); XCTAssertEqual(list.displayedDay, .init(month: 10, day: 19))
        XCTAssertEqual(list.begin(list.retryIntent, owner: me)?.pageCount, 2)
    }

    func testTransientContinuationRetriesSameCursorButExpiredCursorRefreshes() throws {
        let me = try owner(); var state = try seeded(me, pages: 2); let original = state.rows
        let request = try XCTUnwrap(state.begin(.more, owner: me))
        state.fail(APIError.httpStatus(503), for: request, owner: me)
        XCTAssertEqual(state.retryIntent, .more)
        let retry = try XCTUnwrap(state.begin(state.retryIntent, owner: me))
        XCTAssertEqual(retry.query.cursor, "page_b")
        state.fail(APIError.businessCode(400), for: retry, owner: me)
        XCTAssertEqual(state.rows, original); XCTAssertEqual(state.retryIntent, .refresh)
        let refresh = try XCTUnwrap(state.begin(state.retryIntent, owner: me))
        XCTAssertNil(refresh.query.cursor); XCTAssertEqual(refresh.pageCount, 2)
    }

    func testCancellationKeepsConfirmedListWithoutError() throws {
        let me = try owner(); var state = try seeded(me); let original = state.rows
        let request = try XCTUnwrap(state.begin(.more, owner: me))
        state.fail(CancellationError(), for: request, owner: me)
        XCTAssertEqual(state.rows, original); XCTAssertNil(state.error); XCTAssertFalse(state.isLoading)
    }

    func testWrongDateYearDuplicateAndCursorCycleNeverPartiallyCommit() throws {
        let me = try owner()
        for invalid in [page(start: 80, cursor: nil, day: 20), page(start: 80, cursor: nil, referenceYear: 2027),
                        page(start: 81, cursor: nil), page(start: 80, cursor: "page_a")] {
            var state = try seeded(me); let original = state.rows
            let request = try XCTUnwrap(state.begin(.more, owner: me))
            XCTAssertThrowsError(try state.accept([invalid], for: request, owner: me))
            XCTAssertEqual(state.rows, original); XCTAssertEqual(state.page?.nextCursor, "page_a")
        }
    }

    func testMultiPageRefreshRequiresAllLoadedPagesUnlessEndReached() throws {
        let me = try owner(); var state = try seeded(me, pages: 2); let original = state.rows
        let request = try XCTUnwrap(state.begin(.refresh, owner: me))
        XCTAssertThrowsError(try state.accept([page()], for: request, owner: me))
        XCTAssertEqual(state.rows, original)
        XCTAssertTrue(try state.accept([page(count: 3, cursor: nil)], for: request, owner: me))
        XCTAssertEqual(state.rows.count, 3)
    }

    func testLeapDayPickerAndShanghaiMidnightAreNotDeviceTimezoneDependent() throws {
        let leap = try XCTUnwrap(RoamAnniversaryListState.Day(month: 2, day: 29))
        let date = try XCTUnwrap(leap.pickerDate(referenceYear: 2026))
        let selected = RoamShanghaiCalendar.today(now: date)
        XCTAssertEqual(selected.year, 2024); XCTAssertEqual(selected.month, 2); XCTAssertEqual(selected.day, 29)
        XCTAssertNil(RoamAnniversaryListState.Day(month: 2, day: 30))
        let midnight = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-10-18T16:00:00Z"))
        XCTAssertEqual(RoamShanghaiCalendar.today(now: midnight).day, 19)
        XCTAssertEqual(RoamShanghaiCalendar.today(now: midnight.addingTimeInterval(-1)).day, 18)
    }

}

final class RoamAnniversaryRestoredNavigationTests: XCTestCase {
    private func scope(account: Int = 7) throws -> RoamHistoryScope {
        try RoamHistoryScope(market: "cn", deployment: URL(string: "https://example.com/roam")!, accountID: account)
    }
    private func owner(account: Int = 7, epoch: UInt64 = 1) throws -> RoamExperienceIdentity {
        RoamExperienceIdentity(scope: try scope(account: account), epoch: epoch)
    }
    private func memory(id: String = "31", topic: String = "7001") -> RoamAnniversaryMemory {
        RoamAnniversaryMemory(id: id, topicID: topic, title: "Route", completedAt: "2025-10-19 19:42:10.120", year: 2025, yearsAgo: 1)
    }

    func testDuplicateTapCannotReplaceAnOpenPresentation() throws {
        let me = try owner(); let item = memory(); let other = memory(id: "12", topic: "7002")
        let target = try XCTUnwrap(RoamAnniversaryRouteTarget(memory: item))
        var state = RoamAnniversaryNavigationState(); state.bind(to: me)
        XCTAssertTrue(state.open(target, memory: item, currentRows: [item, other], owner: me))
        let lease = try XCTUnwrap(state.openedPresentation)
        XCTAssertFalse(state.open(target, memory: item, currentRows: [item, other], owner: me))
        XCTAssertFalse(state.open(try XCTUnwrap(RoamAnniversaryRouteTarget(memory: other)), memory: other,
                                  currentRows: [item, other], owner: me))
        XCTAssertEqual(state.openedPresentation, lease)
        XCTAssertTrue(state.completeReturn(presentation: lease, owner: me))
    }
}

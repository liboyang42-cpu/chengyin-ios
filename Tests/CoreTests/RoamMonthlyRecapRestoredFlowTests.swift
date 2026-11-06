import XCTest
@testable import QuestifyCore

@MainActor private final class MonthlyRecapFlowReader: RoamPassportToolsReading {
    var identity: RoamExperienceIdentity? = MonthlyRecapFlowReader.owner(81)
    var isConfigured = true
    var isOfflineExample = false
    var queries: [RoamMonthlyRecapQuery] = []
    var response: ((RoamMonthlyRecapQuery) throws -> RoamMonthlyRecapPage)?
    var waiting: [Int: CheckedContinuation<RoamMonthlyRecapPage, Error>] = [:]
    static func owner(_ account: Int, epoch: UInt64 = 1) -> RoamExperienceIdentity {
        let scope = try! RoamHistoryScope(market: "cn", deployment: URL(string: "https://recap.example/native")!, accountID: account)
        return .init(scope: scope, epoch: epoch)
    }
    func anniversary(_ query: RoamAnniversaryQuery, boundary: RoamAnniversaryMemory?) async throws -> RoamAnniversaryPage {
        throw APIError.notConfigured
    }
    func monthlyRecap(_ query: RoamMonthlyRecapQuery) async throws -> RoamMonthlyRecapPage {
        queries.append(query)
        if let response { return try response(query) }
        let index = queries.count - 1
        return try await withCheckedThrowingContinuation { waiting[index] = $0 }
    }
    func finish(_ index: Int, _ result: Result<RoamMonthlyRecapPage, Error>) {
        waiting.removeValue(forKey: index)!.resume(with: result)
    }
}

@MainActor final class RoamMonthlyRecapRestoredFlowTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_792_382_400)
    private func wire(_ query: RoamMonthlyRecapQuery, ids: [Int] = [90], total: Int = 1,
                      more: Bool = false, cursor: Int? = nil, objectID: Int? = 7001,
                      timeZone: String = "Asia/Shanghai") -> Data {
        let items = ids.enumerated().map { index, id in
            #"{"id":"\#(id)","objectId":\#(objectID.map(String.init) ?? "null"),"title":"Record \#(id)","occurredAt":"\#(query.month)-\#(String(format: "%02d", index + 1)) 10:00:00"}"#
        }.joined(separator: ",")
        return Data(#"{"code":200,"data":{"month":"\#(query.month)","kind":"\#(query.kind.rawValue)","timeZone":"\#(timeZone)","counts":{"routes":\#(total),"places":\#(total),"stamps":\#(total)},"items":[\#(items)],"hasMore":\#(more),"nextBeforeId":\#(cursor.map(String.init) ?? "null")}}"#.utf8)
    }
    private func page(_ query: RoamMonthlyRecapQuery, ids: [Int] = [90], total: Int = 1,
                      more: Bool = false, cursor: Int? = nil, objectID: Int? = 7001) throws -> RoamMonthlyRecapPage {
        try .decode(wire(query, ids: ids, total: total, more: more, cursor: cursor, objectID: objectID), query: query)
    }
    private func model(_ reader: MonthlyRecapFlowReader?) -> RoamMonthlyRecapCoordinator {
        RoamMonthlyRecapCoordinator(reader: reader, now: { self.now })
    }
    private func waitFor(_ count: Int, reader: MonthlyRecapFlowReader) async {
        for _ in 0..<100 where reader.queries.count < count { await Task.yield() }
        XCTAssertEqual(reader.queries.count, count)
    }

    func testTerminalContinuationIsNotAWholeMonthChart() throws {
        let first = RoamMonthlyRecapQuery(month: "2026-10")
        XCTAssertTrue(try page(first, ids: [90], total: 2, more: true, cursor: 90).weeks.isEmpty)
        let next = RoamMonthlyRecapQuery(month: "2026-10", beforeID: "90")
        let terminal = try page(next, ids: [80], total: 2)
        XCTAssertTrue(terminal.weeks.isEmpty)
        XCTAssertEqual(terminal.counts.routes, 2, "Monthly total is not replaced with this page's count")
        XCTAssertTrue(try page(next, ids: [80], total: 1).weeks.isEmpty, "Even changed totals do not prove a continuation is the full month")
        XCTAssertTrue(try page(first, ids: [90], total: 2).weeks.isEmpty)
        XCTAssertEqual(try page(first, ids: [90], total: 1).weeks.map(\.count), [1, 0, 0, 0, 0])
    }
    func testUnknownCountsAreNotSilentlyZeroAndWrongTimezoneFails() throws {
        let query = RoamMonthlyRecapQuery(month: "2026-10")
        let source = String(decoding: wire(query), as: UTF8.self)
        for invalid in [source.replacingOccurrences(of: #""routes":1,"#, with: ""),
                        source.replacingOccurrences(of: #""places":1"#, with: #""places":null"#),
                        source.replacingOccurrences(of: #""stamps":1"#, with: #""stamps":-1"#)] {
            XCTAssertThrowsError(try RoamMonthlyRecapPage.decode(Data(invalid.utf8), query: query))
        }
        XCTAssertThrowsError(try RoamMonthlyRecapPage.decode(wire(query, timeZone: "UTC"), query: query))
        let extended = source.replacingOccurrences(of: #""counts":{"#, with: #""extraFutureField":99,"counts":{"#)
        XCTAssertEqual(try RoamMonthlyRecapPage.decode(Data(extended.utf8), query: query).counts.routes, 1)
    }
    func testCursorMustAdvanceAndNameTheLastReturnedRow() throws {
        let first = RoamMonthlyRecapQuery(month: "2026-10")
        XCTAssertThrowsError(try page(first, ids: [90, 95], total: 3, more: true, cursor: 95))
        XCTAssertThrowsError(try page(first, ids: [90, 80], total: 3, more: true, cursor: 70))
        XCTAssertThrowsError(try page(.init(month: "2026-10", beforeID: "90"), ids: [90]))
        XCTAssertThrowsError(try page(.init(month: "2026-10", beforeID: "90"), ids: [99]))
        XCTAssertEqual(try page(.init(month: "2026-10", beforeID: "90"), ids: [80]).items.first?.objectID, "7001")
    }
    func testShanghaiMonthAndStrictDateBoundaries() throws {
        let boundary = ISO8601DateFormatter().date(from: "2025-12-31T16:00:00Z")!
        XCTAssertEqual(RoamShanghaiCalendar.month(now: boundary), "2026-01")
        XCTAssertEqual(RoamShanghaiCalendar.shift("2026-01", by: -1), "2025-12")
        XCTAssertNoThrow(try RoamMonthlyRecapQuery(month: "2000-01").validate(currentMonth: "2026-10"))
        for month in ["1999-12", "2026-11", "2026-00", "2026-13", "2026-1"] {
            XCTAssertThrowsError(try RoamMonthlyRecapQuery(month: month).validate(currentMonth: "2026-10"))
        }
        let query = RoamMonthlyRecapQuery(month: "2025-02")
        let invalid = String(decoding: wire(query), as: UTF8.self).replacingOccurrences(of: "2025-02-01", with: "2025-02-29")
        XCTAssertThrowsError(try RoamMonthlyRecapPage.decode(Data(invalid.utf8), query: query))
    }
    func testEmptyFailureAndUnconfiguredRemainDistinct() async throws {
        let reader = MonthlyRecapFlowReader(); let flow = model(reader)
        reader.response = { try self.page($0, ids: [], total: 0) }
        await flow.activate()
        XCTAssertNotNil(flow.page); XCTAssertTrue(flow.page!.items.isEmpty); XCTAssertNil(flow.error)
        reader.response = { _ in throw APIError.httpStatus(503) }
        await flow.refresh()
        XCTAssertNil(flow.page); XCTAssertEqual(flow.error as? APIError, .httpStatus(503)); XCTAssertFalse(flow.isLoading)
        let unconfigured = model(nil); await unconfigured.activate()
        XCTAssertEqual(unconfigured.error as? APIError, .notConfigured); XCTAssertNil(unconfigured.page)
        reader.identity = nil; await flow.activate()
        XCTAssertEqual(flow.error as? APIError, .unauthorized); XCTAssertNil(flow.page)
    }
    func testFailedContinuationRetriesExactCursorThenRefreshesFirstPage() async throws {
        let reader = MonthlyRecapFlowReader(); let flow = model(reader)
        reader.response = { try self.page($0, total: 2, more: true, cursor: 90) }
        await flow.activate()
        reader.response = { _ in throw APIError.httpStatus(503) }
        await flow.nextPage()
        XCTAssertEqual(reader.queries.last?.beforeID, "90"); XCTAssertNil(flow.page)
        reader.response = { try self.page($0, ids: [80], total: 2) }
        await flow.retry()
        XCTAssertEqual(reader.queries.last?.beforeID, "90"); XCTAssertEqual(flow.page?.items.first?.id, "80")
        await flow.refresh()
        XCTAssertNil(reader.queries.last?.beforeID); XCTAssertEqual(flow.month, "2026-10")
    }
    func testCancellationNeverLeavesBusyOrInventsFailure() async throws {
        let reader = MonthlyRecapFlowReader(); let flow = model(reader)
        reader.response = { try self.page($0) }; await flow.activate()
        reader.response = { _ in throw CancellationError() }; await flow.refresh()
        XCTAssertFalse(flow.isLoading); XCTAssertNil(flow.error); XCTAssertEqual(flow.page?.items.first?.id, "90")
    }
    func testCancelledFirstPageRefreshKeepsSecondPageCursorForDetailAndReactivation() async throws {
        let reader = MonthlyRecapFlowReader(); let flow = model(reader)
        reader.response = { try self.page($0, total: 2, more: true, cursor: 90) }
        await flow.activate()
        reader.response = { try self.page($0, ids: [80], total: 2) }
        await flow.nextPage()
        let confirmed = try XCTUnwrap(flow.page)
        XCTAssertEqual(confirmed.sourceBeforeID, "90")

        reader.response = { _ in throw CancellationError() }
        await flow.refresh()
        XCTAssertNil(reader.queries.last?.beforeID, "Refresh attempts the first page")
        XCTAssertEqual(flow.page, confirmed); XCTAssertFalse(flow.isLoading); XCTAssertNil(flow.error)
        XCTAssertTrue(flow.open(confirmed.items[0]))
        let detail = try XCTUnwrap(flow.presentation)
        reader.response = { try self.page($0, ids: [80], total: 2) }
        await flow.completeReturn(detail)
        XCTAssertEqual(reader.queries.last?.beforeID, "90", "Detail belongs to the still-confirmed second page")

        reader.response = { _ in throw CancellationError() }
        await flow.refresh()
        flow.suspend()
        reader.response = { try self.page($0, ids: [80], total: 2) }
        await flow.activate()
        XCTAssertEqual(reader.queries.last?.beforeID, "90", "Reactivation must not reinterpret the retained second page as the first")
        XCTAssertEqual(flow.page?.sourceBeforeID, "90")

        await flow.refresh()
        XCTAssertNil(reader.queries.last?.beforeID)
        XCTAssertNil(flow.page?.sourceBeforeID, "Only successful refresh commits the first-page cursor")
    }
    func testFailedFirstPageRefreshRetriesFirstPageDespitePriorSecondPage() async throws {
        let reader = MonthlyRecapFlowReader(); let flow = model(reader)
        reader.response = { try self.page($0, total: 2, more: true, cursor: 90) }
        await flow.activate()
        reader.response = { try self.page($0, ids: [80], total: 2) }
        await flow.nextPage()
        reader.response = { _ in throw APIError.httpStatus(503) }
        await flow.refresh()
        XCTAssertNil(flow.page); XCTAssertEqual(flow.error as? APIError, .httpStatus(503))
        reader.response = { try self.page($0, ids: [90], total: 1) }
        await flow.retry()
        XCTAssertNil(reader.queries.last?.beforeID, "Retry follows the failed first-page attempt, not the old confirmed cursor")
        XCTAssertNil(flow.page?.sourceBeforeID); XCTAssertEqual(flow.page?.items.first?.id, "90")
    }
    func testNewerMonthWinsOverLateSuccessAndLateFailure() async throws {
        let reader = MonthlyRecapFlowReader(); let flow = model(reader)
        let old = Task { await flow.activate() }; await waitFor(1, reader: reader)
        let fresh = Task { await flow.select(month: "2026-09") }; await waitFor(2, reader: reader)
        reader.finish(1, .success(try page(reader.queries[1], ids: [80])))
        await fresh.value
        reader.finish(0, .success(try page(reader.queries[0], ids: [90])))
        await old.value
        XCTAssertEqual(flow.page?.month, "2026-09"); XCTAssertEqual(flow.page?.items.first?.id, "80")
        let oldFailure = Task { await flow.refresh() }; await waitFor(3, reader: reader)
        let freshKind = Task { await flow.select(kind: .stamps) }; await waitFor(4, reader: reader)
        reader.finish(3, .success(try page(reader.queries[3], ids: [70])))
        await freshKind.value
        reader.finish(2, .failure(APIError.httpStatus(503))); await oldFailure.value
        XCTAssertNil(flow.error); XCTAssertEqual(flow.page?.kind, .stamps); XCTAssertFalse(flow.isLoading)
    }
    func testSuspendedReadCannotRestoreRowsAndReentryRereads() async throws {
        let reader = MonthlyRecapFlowReader(); let flow = model(reader)
        let old = Task { await flow.activate() }; await waitFor(1, reader: reader)
        flow.suspend()
        reader.finish(0, .success(try page(reader.queries[0])))
        await old.value
        XCTAssertNil(flow.page); XCTAssertNil(flow.error); XCTAssertFalse(flow.isLoading)
        reader.response = { try self.page($0, ids: [80]) }
        await flow.activate()
        XCTAssertEqual(reader.queries.count, 2); XCTAssertEqual(flow.page?.items.first?.id, "80")
    }
    func testIdentityChangeAndEpochChangeDiscardLatePrivateRows() async throws {
        let reader = MonthlyRecapFlowReader(); let flow = model(reader)
        let old = Task { await flow.activate() }; await waitFor(1, reader: reader)
        reader.identity = MonthlyRecapFlowReader.owner(82)
        reader.finish(0, .success(try page(reader.queries[0])))
        await old.value
        XCTAssertNil(flow.page); XCTAssertNil(flow.presentation); XCTAssertFalse(flow.isLoading)
        reader.response = { try self.page($0) }; await flow.activate()
        XCTAssertTrue(flow.open(flow.page!.items[0]))
        let lease = flow.presentation!
        reader.identity = MonthlyRecapFlowReader.owner(82, epoch: 2)
        XCTAssertFalse(flow.isCurrent(lease))
        flow.synchronizeIdentity()
        XCTAssertNil(flow.page); XCTAssertNil(flow.presentation); XCTAssertEqual(flow.kind, .routes)
        let requests = reader.queries.count
        await flow.completeReturn(lease)
        XCTAssertEqual(reader.queries.count, requests)
    }
    func testDetailReturnKeepsMonthKindCursorAndRejectsOldDismissal() async throws {
        let reader = MonthlyRecapFlowReader(); let flow = model(reader)
        reader.response = { try self.page($0, total: 2, more: true, cursor: 90) }
        await flow.select(month: "2026-09"); await flow.select(kind: .places)
        reader.response = { try self.page($0, ids: [80], total: 2, objectID: 27) }
        await flow.nextPage()
        let row = flow.page!.items[0]
        XCTAssertTrue(flow.open(row)); let first = flow.presentation!
        XCTAssertNil(first.topicID, "A POI ID must not open a topic")
        flow.suspend() // Covered or disappeared is not a true dismissal.
        XCTAssertTrue(flow.isCurrent(first))
        await flow.completeReturn(first)
        XCTAssertEqual(reader.queries.last, .init(month: "2026-09", kind: .places, beforeID: "90"))
        XCTAssertEqual(flow.page?.items.first?.id, "80"); XCTAssertNil(flow.presentation)
        XCTAssertTrue(flow.open(flow.page!.items[0])); let second = flow.presentation!
        let requests = reader.queries.count
        await flow.completeReturn(first)
        XCTAssertEqual(reader.queries.count, requests); XCTAssertEqual(flow.presentation, second)
        await flow.completeReturn(second); flow.suspend(); await flow.activate()
        XCTAssertEqual(reader.queries.last?.beforeID, "90", "Re-entry reauthorizes the current page")
        XCTAssertEqual(flow.month, "2026-09"); XCTAssertEqual(flow.kind, .places)
    }
    func testRouteAndStampTargetsUseOnlyTypedServerObjectIDs() async throws {
        let reader = MonthlyRecapFlowReader(); let flow = model(reader)
        reader.response = { try self.page($0, objectID: 7001) }; await flow.activate()
        XCTAssertTrue(flow.open(flow.page!.items[0])); XCTAssertEqual(flow.presentation?.topicID, "7001")
        await flow.select(kind: .stamps)
        XCTAssertTrue(flow.open(flow.page!.items[0])); XCTAssertNil(flow.presentation?.topicID)
        await flow.select(kind: .routes)
        reader.response = { try self.page($0, objectID: nil) }; await flow.refresh()
        XCTAssertTrue(flow.open(flow.page!.items[0])); XCTAssertNil(flow.presentation?.topicID)
    }
    func testReadApprovalRevocationInvalidatesDetailWithoutChangingIdentity() async throws {
        let reader = MonthlyRecapFlowReader(); let flow = model(reader)
        reader.response = { try self.page($0) }; await flow.activate()
        let record = try XCTUnwrap(flow.page?.items.first)
        XCTAssertTrue(flow.open(record)); let detail = try XCTUnwrap(flow.presentation)
        let identity = reader.identity, requests = reader.queries.count

        reader.isConfigured = false
        XCTAssertEqual(reader.identity, identity)
        XCTAssertFalse(flow.isLive)
        XCTAssertFalse(flow.isCurrent(detail), "Detail is unavailable even before a view change callback")
        await flow.completeReturn(detail)
        XCTAssertNil(flow.page); XCTAssertNil(flow.presentation); XCTAssertFalse(flow.isLoading)
        XCTAssertEqual(flow.error as? APIError, .notConfigured)
        XCTAssertEqual(reader.queries.count, requests, "Revoked access cannot dispatch a return refresh")
        XCTAssertFalse(flow.open(record))

        reader.isConfigured = true
        XCTAssertFalse(flow.isCurrent(detail), "Restored access does not resurrect an old detail lease")
        XCTAssertNil(flow.page)
        reader.response = { try self.page($0, ids: [80]) }; await flow.retry()
        XCTAssertEqual(flow.page?.items.first?.id, "80"); XCTAssertNil(flow.error)
    }
    func testUnconfiguredReaderDoesNotDispatchAndRetryRetainsSelectedFilters() async throws {
        let reader = MonthlyRecapFlowReader(); let flow = model(reader)
        reader.isConfigured = false
        await flow.select(month: "2026-09"); await flow.select(kind: .stamps)
        await flow.activate(); await flow.retry()
        XCTAssertTrue(reader.queries.isEmpty); XCTAssertNil(flow.page)
        XCTAssertEqual(flow.error as? APIError, .notConfigured)
        reader.isConfigured = true
        reader.response = { try self.page($0, ids: [], total: 0) }
        await flow.retry()
        XCTAssertEqual(reader.queries.last, .init(month: "2026-09", kind: .stamps))
        XCTAssertNotNil(flow.page); XCTAssertTrue(flow.page!.items.isEmpty); XCTAssertNil(flow.error)
    }
    func testRevocationDuringCancelledRefreshClearsOldRowsAndRetriesExactAttempt() async throws {
        let reader = MonthlyRecapFlowReader(); let flow = model(reader)
        reader.response = { try self.page($0, total: 2, more: true, cursor: 90) }
        await flow.select(month: "2026-09"); await flow.select(kind: .places)
        reader.response = { try self.page($0, ids: [80], total: 2) }; await flow.nextPage()
        XCTAssertEqual(flow.page?.sourceBeforeID, "90")
        reader.response = nil
        let pending = Task { await flow.refresh() }; await waitFor(4, reader: reader)
        reader.isConfigured = false
        reader.finish(3, .failure(CancellationError())); await pending.value
        XCTAssertNil(flow.page); XCTAssertNil(flow.presentation); XCTAssertFalse(flow.isLoading)
        XCTAssertEqual(flow.error as? APIError, .notConfigured)
        reader.isConfigured = true
        reader.response = { try self.page($0, ids: [70]) }; await flow.retry()
        XCTAssertEqual(reader.queries.last, .init(month: "2026-09", kind: .places))
        XCTAssertEqual(flow.page?.items.first?.id, "70"); XCTAssertNil(flow.page?.sourceBeforeID)
    }
    func testRevocationDropsLateSuccessAndRetiredRequestCannotReplaceRecovery() async throws {
        let reader = MonthlyRecapFlowReader(); let flow = model(reader)
        let pending = Task { await flow.activate() }; await waitFor(1, reader: reader)
        reader.isConfigured = false
        reader.finish(0, .success(try page(reader.queries[0]))); await pending.value
        XCTAssertNil(flow.page); XCTAssertEqual(flow.error as? APIError, .notConfigured)
        reader.isConfigured = true
        let stale = Task { await flow.retry() }; await waitFor(2, reader: reader)
        reader.isConfigured = false; flow.synchronizeAccess()
        reader.isConfigured = true
        let fresh = Task { await flow.retry() }; await waitFor(3, reader: reader)
        reader.finish(2, .success(try page(reader.queries[2], ids: [70]))); await fresh.value
        reader.finish(1, .success(try page(reader.queries[1], ids: [90]))); await stale.value
        XCTAssertEqual(flow.page?.items.first?.id, "70"); XCTAssertNil(flow.error)
        XCTAssertFalse(flow.isLoading)
    }
    func testMonthBoundsDoNotDispatchInvalidRequests() async {
        let reader = MonthlyRecapFlowReader(); let flow = model(reader)
        reader.response = { try self.page($0, ids: [], total: 0) }
        await flow.shiftMonth(by: 1)
        await flow.select(month: "1999-12")
        XCTAssertTrue(reader.queries.isEmpty)
        await flow.select(month: "2000-01")
        XCTAssertFalse(flow.canGoPrevious)
        await flow.shiftMonth(by: -1)
        XCTAssertEqual(reader.queries.count, 1)
    }
}

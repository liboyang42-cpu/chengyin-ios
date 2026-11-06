import XCTest
@testable import Questify

@MainActor final class HomeFeedReturnModelTests: XCTestCase {
    private final class Reader: HomeFeedReading {
        var scope = UUID()
        var isConfigured = true
        let isOfflineExample = true
        var requests: [(HomeFeedQuery, Int)] = []
        var bannerReads = 0
        var failPage = false
        var hold = false
        var onHeld: (() -> Void)?
        var held: CheckedContinuation<HomeFeedPage, Error>?
        func banners() async throws -> [DiscoveryBanner] { bannerReads += 1; return [] }
        func categories() async throws -> [DiscoveryCategory] { [] }
        func section(_ section: HomeFeedSection) async throws -> [HomeFeedItem] { [] }
        func page(query: HomeFeedQuery, number: Int) async throws -> HomeFeedPage {
            requests.append((query, number))
            if hold {
                hold = false
                return try await withCheckedThrowingContinuation { held = $0; onHeld?() }
            }
            if failPage { throw APIError.httpStatus(503) }
            return try pageValue(query: query, number: number)
        }
        func pageValue(query: HomeFeedQuery = .init(), number: Int = 1) throws -> HomeFeedPage {
            let item = try query.kind == .topics ? HomeFeedSyntheticFixtures.topic() : HomeFeedSyntheticFixtures.activity()
            return .init(items: number == 1 ? Array(repeating: item, count: query.pageSize) : [], number: number, size: query.pageSize)
        }
    }
    func testCancelledResumeCannotClearCurrentSnapshot() async {
        let model = HomeFeedModel(), reader = Reader()
        await model.resume(reader: reader, query: .init())
        let task = Task { await model.resume(reader: reader, query: .init(), available: false) }
        task.cancel(); await task.value
        XCTAssertTrue(model.matches(reader))
        XCTAssertEqual(model.pagination.items.count, 1)
        XCTAssertEqual(reader.requests.count, 1)
    }
    func testUnavailableMessageRetiresReadScopeAndRestorationLoadsAgain() async {
        let model = HomeFeedModel(), reader = Reader()
        await model.resume(reader: reader, query: .init())
        let previous = model.bind(reader)
        let unavailable = model.bind(reader, available: false)
        XCTAssertNotEqual(previous, unavailable)
        XCTAssertFalse(model.matches(reader))
        await model.resume(reader: reader, query: .init(), expectedBinding: previous)
        XCTAssertFalse(model.matches(reader))
        await model.resume(reader: reader, query: .init(), available: false, expectedBinding: unavailable)
        XCTAssertTrue(model.pagination.items.isEmpty)
        await model.resume(reader: reader, query: .init())
        XCTAssertEqual(reader.requests.count, 2)
    }
    func testDetailBackRetainsExhaustedPaginationAndDoesNotReloadSections() async {
        let model = HomeFeedModel(), reader = Reader()
        await model.resume(reader: reader, query: .init())
        await model.loadMore(reader: reader)
        XCTAssertFalse(model.pagination.hasMore)
        model.suspend()
        XCTAssertFalse(model.canOpen(reader))
        XCTAssertEqual(model.pagination.items.count, 1)
        await model.resume(reader: reader, query: .init())
        XCTAssertEqual(reader.requests.map(\.1), [1, 2])
        XCTAssertEqual(reader.bannerReads, 1)
        XCTAssertEqual(model.pagination.nextPage, 3)
        XCTAssertFalse(model.pagination.hasMore)
        XCTAssertFalse(model.loading)
    }
    func testExplicitRefreshAndQueryChangesStillReadFreshFirstPage() async {
        let model = HomeFeedModel(), reader = Reader()
        let query = HomeFeedQuery(kind: .activities, keyword: "walk", categoryID: 2)
        await model.resume(reader: reader, query: .init())
        await model.resetPage(reader: reader, query: query)
        model.suspend(); await model.resume(reader: reader, query: query)
        XCTAssertEqual(reader.requests.count, 2)
        XCTAssertEqual(model.pagination.items.map(\.id), [.activity(7)])
        await model.reload(reader: reader, query: query)
        XCTAssertEqual(reader.requests.count, 3)
        XCTAssertEqual(reader.requests.last?.0, query)
        XCTAssertEqual(reader.requests.last?.1, 1)
        XCTAssertEqual(reader.bannerReads, 2)
    }
    func testScopeReaderReplacementAndObservedABADoNotReuseSnapshot() async {
        let model = HomeFeedModel(), a = Reader(), b = Reader()
        await model.resume(reader: a, query: .init())
        model.suspend(); a.scope = UUID()
        model.bind(a); XCTAssertFalse(model.matches(a))
        await model.resume(reader: a, query: .init())
        XCTAssertEqual(a.requests.count, 2)
        b.scope = a.scope
        model.bind(b); XCTAssertFalse(model.matches(b))
        model.bind(a); XCTAssertFalse(model.matches(a))
        await model.resume(reader: a, query: .init())
        XCTAssertEqual(a.requests.count, 3)
        await model.resume(reader: b, query: .init())
        XCTAssertEqual(b.requests.count, 1)
    }
    func testRevocationHidesRetainedRowsAndRestorationReloads() async {
        let model = HomeFeedModel(), reader = Reader()
        await model.resume(reader: reader, query: .init())
        reader.isConfigured = false; model.bind(reader)
        XCTAssertFalse(model.matches(reader))
        XCTAssertFalse(model.canOpen(reader))
        await model.resume(reader: reader, query: .init())
        XCTAssertTrue(model.pagination.items.isEmpty)
        XCTAssertEqual(reader.requests.count, 1)
        reader.isConfigured = true
        await model.resume(reader: reader, query: .init())
        XCTAssertEqual(reader.requests.count, 2)
    }
    func testInterruptedInitialReadResumesAndOldCompletionCannotReplaceNewQuery() async throws {
        let model = HomeFeedModel(), reader = Reader()
        let held = expectation(description: "initial read held")
        reader.hold = true; reader.onHeld = { held.fulfill() }
        let initial = Task { await model.resume(reader: reader, query: .init()) }
        await fulfillment(of: [held], timeout: 2)
        model.suspend(); initial.cancel()
        let changed = HomeFeedQuery(kind: .activities)
        await model.resume(reader: reader, query: changed)
        reader.held?.resume(returning: try reader.pageValue()); reader.held = nil
        await initial.value
        XCTAssertEqual(model.pagination.items.map(\.id), [.activity(7)])
        XCTAssertEqual(reader.requests.count, 2)
        XCTAssertFalse(model.loadingPage)
        XCTAssertFalse(model.pageFailed)
    }
    func testHiddenRetryDoesNotReadAndReturnKeepsRecoverableFailure() async {
        let model = HomeFeedModel(), reader = Reader()
        reader.failPage = true
        await model.resume(reader: reader, query: .init())
        XCTAssertTrue(model.pageFailed)
        model.suspend()
        await model.loadMore(reader: reader)
        XCTAssertEqual(reader.requests.count, 1)
        await model.resume(reader: reader, query: .init())
        XCTAssertTrue(model.pageFailed)
        reader.failPage = false
        await model.loadMore(reader: reader)
        XCTAssertEqual(reader.requests.map(\.1), [1, 1])
        XCTAssertFalse(model.pageFailed)
    }
    func testLateNonCooperativeCompletionAfterReaderReplacementIsDiscarded() async throws {
        let model = HomeFeedModel(), a = Reader(), b = Reader()
        let held = expectation(description: "old reader held")
        a.hold = true; a.onHeld = { held.fulfill() }
        let old = Task { await model.resume(reader: a, query: .init()) }
        await fulfillment(of: [held], timeout: 2)
        model.bind(b)
        await model.resume(reader: b, query: .init(kind: .activities))
        a.held?.resume(returning: try a.pageValue()); a.held = nil
        await old.value
        XCTAssertEqual(model.pagination.items.map(\.id), [.activity(7)])
        XCTAssertTrue(model.matches(b)); XCTAssertFalse(model.matches(a))
    }
    func testScheduledRepeatedPageTapsKeepTheOriginalRead() async throws {
        let model = HomeFeedModel(), reader = Reader()
        await model.resume(reader: reader, query: .init())
        let held = expectation(description: "scheduled page held")
        reader.hold = true; reader.onHeld = { held.fulfill() }
        let permit = model.permit(reader)
        let first = try XCTUnwrap(model.schedule(.page, reader: reader, permit: permit))
        await fulfillment(of: [held], timeout: 2)
        let repeated = try XCTUnwrap(model.schedule(.page, reader: reader, permit: permit))
        XCTAssertFalse(first.isCancelled)
        XCTAssertEqual(reader.requests.map(\.1), [1, 2])
        reader.held?.resume(returning: try reader.pageValue(number: 2)); reader.held = nil
        await first.value; await repeated.value
        XCTAssertEqual(model.pagination.nextPage, 3)
        XCTAssertFalse(model.pagination.hasMore); XCTAssertFalse(model.loadingPage)
        XCTAssertFalse(model.pageFailed)
    }
    func testOtherScheduledReadDoesNotCancelHeldPageAndAllTasksRetireOnLeave() async throws {
        let model = HomeFeedModel(), reader = Reader()
        await model.resume(reader: reader, query: .init())
        let held = expectation(description: "held page alongside banner retry")
        reader.hold = true; reader.onHeld = { held.fulfill() }
        let permit = model.permit(reader)
        let page = try XCTUnwrap(model.schedule(.page, reader: reader, permit: permit))
        await fulfillment(of: [held], timeout: 2)
        await model.schedule(.banners, reader: reader, permit: permit)?.value
        XCTAssertFalse(page.isCancelled)
        model.suspend(); XCTAssertTrue(page.isCancelled)
        await model.resume(reader: reader, query: .init())
        XCTAssertNil(model.schedule(.page, reader: reader, permit: permit))
        reader.held?.resume(returning: try reader.pageValue(number: 2)); reader.held = nil
        await page.value
        XCTAssertEqual(model.pagination.nextPage, 2)
        XCTAssertFalse(model.loadingPage)
    }
    func testQueuedPageCannotStartAfterLeaveAndReentry() async throws {
        let model = HomeFeedModel(), reader = Reader()
        await model.resume(reader: reader, query: .init())
        let queued = try XCTUnwrap(model.schedule(.page, reader: reader, permit: model.permit(reader)))
        // No actor suspension between scheduling and leaving: the old task has not begun.
        model.suspend()
        await model.resume(reader: reader, query: .init())
        await queued.value
        XCTAssertTrue(queued.isCancelled)
        XCTAssertEqual(reader.requests.map(\.1), [1])
        XCTAssertEqual(model.pagination.nextPage, 2)
    }
    func testScheduledQueryReplacementsCaptureGenerationBeforeTasksStart() async throws {
        let model = HomeFeedModel(), reader = Reader()
        await model.resume(reader: reader, query: .init())
        let oldPermit = model.permit(reader)
        let first = try XCTUnwrap(model.schedule(.query(.init(keyword: "older")), reader: reader, permit: oldPermit))
        let changed = HomeFeedQuery(kind: .activities, keyword: "latest", categoryID: 2)
        let second = try XCTUnwrap(model.schedule(.query(changed), reader: reader, permit: model.permit(reader)))
        await first.value; await second.value
        XCTAssertTrue(first.isCancelled)
        XCTAssertEqual(reader.requests.map { $0.0.keyword }, ["", "latest"])
        XCTAssertEqual(model.pagination.items.map(\.id), [.activity(7)])
        XCTAssertNil(model.schedule(.page, reader: reader, permit: oldPermit))
    }
    func testResumeChangedQueryRetiresAnInFlightPageAndIgnoresLateFailure() async throws {
        let model = HomeFeedModel(), reader = Reader()
        await model.resume(reader: reader, query: .init())
        let held = expectation(description: "old query page held")
        reader.hold = true; reader.onHeld = { held.fulfill() }
        let older = Task { await model.loadMore(reader: reader) }
        await fulfillment(of: [held], timeout: 2)
        let changed = HomeFeedQuery(kind: .activities, keyword: "walk")
        await model.resume(reader: reader, query: changed)
        XCTAssertEqual(reader.requests.map(\.1), [1, 2, 1])
        XCTAssertEqual(reader.requests.last?.0, changed)
        XCTAssertEqual(model.pagination.items.map(\.id), [.activity(7)])
        reader.held?.resume(throwing: APIError.httpStatus(503)); reader.held = nil
        await older.value
        XCTAssertEqual(model.pagination.items.map(\.id), [.activity(7)])
        XCTAssertFalse(model.loadingPage); XCTAssertFalse(model.pageFailed)
    }
    func testScheduledRetryDuplicatesKeepSuccessfulRecovery() async throws {
        let model = HomeFeedModel(), reader = Reader()
        reader.failPage = true
        await model.resume(reader: reader, query: .init())
        XCTAssertTrue(model.pageFailed)
        let held = expectation(description: "retry held")
        reader.failPage = false; reader.hold = true; reader.onHeld = { held.fulfill() }
        let permit = model.permit(reader)
        let retry = try XCTUnwrap(model.schedule(.page, reader: reader, permit: permit))
        await fulfillment(of: [held], timeout: 2)
        let again = try XCTUnwrap(model.schedule(.page, reader: reader, permit: permit))
        reader.held?.resume(returning: try reader.pageValue()); reader.held = nil
        await retry.value; await again.value
        XCTAssertEqual(reader.requests.map(\.1), [1, 1])
        XCTAssertEqual(model.pagination.items.count, 1)
        XCTAssertFalse(model.pageFailed); XCTAssertFalse(model.loadingPage)
    }
    func testReaderReplacementRejectsQueuedActionsAndTheirPermits() async throws {
        let model = HomeFeedModel(), old = Reader(), current = Reader()
        await model.resume(reader: old, query: .init())
        let permit = model.permit(old)
        let queued = try XCTUnwrap(model.schedule(.page, reader: old, permit: permit))
        model.bind(current)
        await model.resume(reader: current, query: .init(kind: .activities))
        await queued.value
        XCTAssertTrue(queued.isCancelled)
        XCTAssertNil(model.schedule(.query(.init()), reader: old, permit: permit))
        XCTAssertEqual(old.requests.count, 1)
        XCTAssertEqual(model.pagination.items.map(\.id), [.activity(7)])
    }

}

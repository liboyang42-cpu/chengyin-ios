import XCTest
@testable import Questify

@MainActor final class SearchMapPaginationPresentationTests: XCTestCase {
    private var query: CityNodeSearchQuery {
        .init(filter: .init(), area: .init(coordinate: RoamCoordinate(latitude: 1, longitude: 1)!, label: "Synthetic"))
    }
    func testFixtureProjectsNextPageWithoutDuplicateReplacingOriginalPin() async throws {
        let reader = SearchMapFixtureReader(scenario: .pagination)
        let first = try await reader.citySearch(query)
        var state = SearchMapPagination()
        state.reset(query: query, scope: reader.scope, manualAreaRevision: 0, result: first)
        let original = try XCTUnwrap(state.rows.first)
        let ticket = try XCTUnwrap(state.begin(query: query, scope: reader.scope, manualAreaRevision: 0))
        let page = try await reader.cityActivityPage(query, page: ticket.page)
        state.finish(ticket, page: page)
        XCTAssertEqual(state.rows.map(\.id), [71, 73, 74]); XCTAssertEqual(state.rows.first, original)
        XCTAssertNil(state.nextPage); XCTAssertEqual(reader.activityPageRequests, [2])
    }
    func testFixtureFailedPageRetainsVisibleRowsAndRetriesSamePage() async throws {
        let reader = SearchMapFixtureReader(scenario: .pageFailure)
        var state = SearchMapPagination()
        state.reset(query: query, scope: reader.scope, manualAreaRevision: 0, result: try await reader.citySearch(query))
        let rows = state.rows
        let first = try XCTUnwrap(state.begin(query: query, scope: reader.scope, manualAreaRevision: 0))
        do { _ = try await reader.cityActivityPage(query, page: first.page); XCTFail() }
        catch { state.fail(first, error: .unavailable) }
        XCTAssertEqual(state.rows, rows)
        let retry = try XCTUnwrap(state.begin(query: query, scope: reader.scope, manualAreaRevision: 0))
        state.finish(retry, page: try await reader.cityActivityPage(query, page: retry.page))
        XCTAssertEqual(reader.activityPageRequests, [2, 2]); XCTAssertNil(state.failure)
        XCTAssertEqual(state.rows.count, 3)
    }
    func testFixtureFilteredFirstPageCanContinueWithoutEnablingMap() async throws {
        let reader = SearchMapFixtureReader(scenario: .filteredPage)
        var state = SearchMapPagination()
        state.reset(query: query, scope: reader.scope, manualAreaRevision: 0, result: try await reader.citySearch(query))
        XCTAssertTrue(state.rows.isEmpty); XCTAssertEqual(state.nextPage, 2)
        let ticket = try XCTUnwrap(state.begin(query: query, scope: reader.scope, manualAreaRevision: 0))
        state.finish(ticket, page: try await reader.cityActivityPage(query, page: ticket.page))
        XCTAssertEqual(state.rows.map(\.id), [71, 74]); XCTAssertNil(state.nextPage)
    }
    func testFixtureDelayedReadCancelsOnOwnerDismissalAndCanRetry() async throws {
        let reader = SearchMapFixtureReader(scenario: .pageDelayed)
        let owner = ManualMapReadTaskOwner()
        var completions = 0
        let capturedQuery = query
        owner.start {
            do { _ = try await reader.cityActivityPage(capturedQuery, page: 2); completions += 1 }
            catch { }
        }
        while reader.pendingActivityPageCount == 0 { await Task.yield() }
        owner.deactivate()
        while reader.pendingActivityPageCount != 0 { await Task.yield() }
        XCTAssertEqual(completions, 0)
        owner.activate()
        owner.start {
            do { _ = try await reader.cityActivityPage(capturedQuery, page: 2); completions += 1 }
            catch { }
        }
        while reader.pendingActivityPageCount == 0 { await Task.yield() }
        reader.releaseActivityPage()
        while completions == 0 { await Task.yield() }
        XCTAssertEqual(completions, 1); XCTAssertEqual(reader.activityPageRequests, [2, 2])
        owner.deactivate()
    }
}

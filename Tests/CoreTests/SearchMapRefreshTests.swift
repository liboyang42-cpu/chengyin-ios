import XCTest
@testable import QuestifyCore

final class SearchMapRefreshTests: XCTestCase {
    private let scope = UUID()
    private var query: CityNodeSearchQuery {
        .init(filter: .init(keyword: "Synthetic"), area: .init(coordinate: RoamCoordinate(latitude: 1, longitude: 2)!, label: "Manual"))
    }
    private func activity(_ id: Int, name: String = "Synthetic") throws -> ActivitySummary {
        try JSONDecoder().decode(ActivitySummary.self, from: JSONSerialization.data(withJSONObject:
            ["id": id, "name": name, "latitude": 1, "longitude": 2, "topicId": 99]))
    }
    private func node(_ id: Int) throws -> SearchMapCityNode {
        try JSONDecoder().decode(SearchMapCityNode.self, from: Data("{\"poiId\":\(id),\"name\":\"Synthetic\",\"lat\":1,\"lng\":2}".utf8))
    }
    private func result(_ ids: [Int] = [1], nodes: [Int] = [1], rawCount: Int = 50) throws -> CityNodeSearchResults {
        let rows = try ids.map { try activity($0) }
        return .init(activities: rows, nodes: try nodes.map(node),
            activityPage: try .init(rows: rows, pageNumber: 1, rawCount: rawCount))
    }
    private func pages(_ result: CityNodeSearchResults) -> SearchMapPagination {
        var value = SearchMapPagination()
        value.reset(query: query, scope: scope, manualAreaRevision: 7, result: result)
        return value
    }
    private func begin(_ state: inout SearchMapRefresh, _ result: CityNodeSearchResults, _ pages: SearchMapPagination) throws -> SearchMapRefresh.Ticket {
        try XCTUnwrap(state.begin(query: query, scope: scope, manualAreaRevision: 7, result: result, pagination: pages))
    }
    private func finish(_ state: inout SearchMapRefresh, _ ticket: SearchMapRefresh.Ticket, _ result: CityNodeSearchResults) throws -> SearchMapRefresh.Update {
        try XCTUnwrap(state.finish(ticket, result: result, query: query, scope: scope, manualAreaRevision: 7))
    }
    func testRefreshKeepsSnapshotAndRejectsDuplicateClick() throws {
        var state = SearchMapRefresh(); let old = try result(); let oldPages = pages(old)
        _ = try begin(&state, old, oldPages)
        XCTAssertTrue(state.isLoading)
        XCTAssertNil(state.begin(query: query, scope: scope, manualAreaRevision: 7, result: old, pagination: oldPages))
        XCTAssertEqual(oldPages.rows.map(\.id), [1]); XCTAssertEqual(oldPages.nextPage, 2)
    }
    func testUnavailableRefreshRetainsAllPagesAndSameContinuation() throws {
        var state = SearchMapRefresh(); let old = try result(); var oldPages = pages(old)
        let page = try XCTUnwrap(oldPages.begin(query: query, scope: scope, manualAreaRevision: 7))
        oldPages.finish(page, page: try .init(rows: [activity(2)], pageNumber: 2, rawCount: 50))
        let ticket = try begin(&state, old, oldPages)
        let update = try finish(&state, ticket, .init(activities: [], nodes: [], activityFailure: .unavailable, nodeFailure: .unavailable))
        XCTAssertEqual(update.pagination.rows.map(\.id), [1, 2]); XCTAssertEqual(update.pagination.nextPage, 3)
        XCTAssertEqual(update.result.nodes, old.nodes)
        XCTAssertTrue(state.retainedActivities); XCTAssertTrue(state.retainedNodes); XCTAssertFalse(state.isLoading)
    }
    func testPartialActivityFailureKeepsActivitiesAndRefreshesNodes() throws {
        var state = SearchMapRefresh(); let old = try result(); let ticket = try begin(&state, old, pages(old))
        let update = try finish(&state, ticket, .init(activities: [], nodes: [node(2)], activityFailure: .unavailable))
        XCTAssertEqual(update.pagination.rows.map(\.id), [1]); XCTAssertEqual(update.result.nodes.map(\.id), [2])
        XCTAssertTrue(state.retainedActivities); XCTAssertFalse(state.retainedNodes)
        XCTAssertNil(update.result.activityFailure)
    }
    func testPartialNodeFailureReplacesActivityPageAndKeepsOnlyNodes() throws {
        var state = SearchMapRefresh(); let old = try result(); let ticket = try begin(&state, old, pages(old))
        let fresh = try result([2], nodes: [], rawCount: 1)
        let update = try finish(&state, ticket, .init(activities: fresh.activities, nodes: [], nodeFailure: .unavailable, activityPage: fresh.activityPage))
        XCTAssertEqual(update.pagination.rows.map(\.id), [2]); XCTAssertNil(update.pagination.nextPage)
        XCTAssertEqual(update.result.nodes.map(\.id), [1]); XCTAssertTrue(state.retainedNodes); XCTAssertFalse(state.retainedActivities)
    }
    func testSuccessfulEmptyRefreshClearsOldRowsPinsAndContinuation() throws {
        var state = SearchMapRefresh(); let old = try result(); let ticket = try begin(&state, old, pages(old))
        let update = try finish(&state, ticket, result([], nodes: [], rawCount: 0))
        XCTAssertTrue(update.pagination.rows.isEmpty); XCTAssertTrue(update.result.nodes.isEmpty)
        XCTAssertNil(update.pagination.nextPage); XCTAssertFalse(state.hasRetainedResults)
    }
    func testFilteredEmptyFullPageStillContinuesAfterSuccessfulRefresh() throws {
        var state = SearchMapRefresh(); let old = try result(); let ticket = try begin(&state, old, pages(old))
        let update = try finish(&state, ticket, result([], nodes: [], rawCount: 50))
        XCTAssertTrue(update.pagination.rows.isEmpty); XCTAssertEqual(update.pagination.nextPage, 2)
    }
    func testAuthorizationOrConfigurationFailuresNeverRetainAffectedLayer() throws {
        for failure in [SearchMapFailure.unauthorized, .notConfigured, .invalidInput] {
            var state = SearchMapRefresh(); let old = try result(); let ticket = try begin(&state, old, pages(old))
            let update = try finish(&state, ticket, .init(activities: old.activities, nodes: old.nodes,
                activityFailure: failure, nodeFailure: failure, activityPage: old.activityPage))
            XCTAssertTrue(update.pagination.rows.isEmpty); XCTAssertTrue(update.result.activities.isEmpty)
            XCTAssertTrue(update.result.nodes.isEmpty); XCTAssertNil(update.pagination.nextPage)
            XCTAssertFalse(state.hasRetainedResults)
        }
    }
    func testFailedInitialLayerCannotBeDescribedAsRetainedSuccessfulResults() throws {
        var state = SearchMapRefresh()
        let old = CityNodeSearchResults(activities: [], nodes: [], activityFailure: .unavailable, nodeFailure: .unauthorized)
        let ticket = try begin(&state, old, pages(old))
        let update = try finish(&state, ticket, .init(activities: [], nodes: [], activityFailure: .unavailable, nodeFailure: .unavailable))
        XCTAssertFalse(state.hasRetainedResults)
        XCTAssertEqual(update.result.activityFailure, .unavailable); XCTAssertEqual(update.result.nodeFailure, .unavailable)
    }
    func testChangedQueryScopeAndAreaRevisionRejectLateCompletion() throws {
        var state = SearchMapRefresh(); let old = try result(); let ticket = try begin(&state, old, pages(old))
        var changed = query; changed.filter.keyword = "Other"
        XCTAssertNil(state.finish(ticket, result: try result([9]), query: changed, scope: scope, manualAreaRevision: 7))
        XCTAssertNil(state.finish(ticket, result: try result([9]), query: query, scope: UUID(), manualAreaRevision: 7))
        XCTAssertNil(state.finish(ticket, result: try result([9]), query: query, scope: scope, manualAreaRevision: 8))
        XCTAssertTrue(state.isLoading); XCTAssertFalse(state.hasRetainedResults)
        state.invalidate()
        XCTAssertNil(state.finish(ticket, result: try result([9]), query: query, scope: scope, manualAreaRevision: 7))
    }
    func testRepeatRefreshRetiresOldSuccessFailureAndCancellation() throws {
        var state = SearchMapRefresh(); let old = try result(); let retired = try begin(&state, old, pages(old))
        state.cancelPending()
        let current = try begin(&state, old, pages(old))
        XCTAssertNotEqual(current, retired)
        XCTAssertNil(state.finish(retired, result: try result([9]), query: query, scope: scope, manualAreaRevision: 7))
        XCTAssertNil(state.finish(retired, result: .init(activities: [], nodes: [], activityFailure: .unauthorized), query: query, scope: scope, manualAreaRevision: 7))
        state.cancel(retired); XCTAssertTrue(state.isLoading)
        let update = try finish(&state, current, result([2]))
        XCTAssertEqual(update.pagination.rows.map(\.id), [2]); XCTAssertFalse(state.isLoading)
    }
    func testRefreshCannotStartDuringLoadMoreOrAgainstDifferentSnapshot() throws {
        var state = SearchMapRefresh(); let old = try result(); var oldPages = pages(old)
        let page = try XCTUnwrap(oldPages.begin(query: query, scope: scope, manualAreaRevision: 7))
        XCTAssertNil(state.begin(query: query, scope: scope, manualAreaRevision: 7, result: old, pagination: oldPages))
        oldPages.cancel(page)
        XCTAssertNil(state.begin(query: query, scope: UUID(), manualAreaRevision: 7, result: old, pagination: oldPages))
        XCTAssertNil(state.begin(query: query, scope: scope, manualAreaRevision: 8, result: old, pagination: oldPages))
        _ = try begin(&state, old, oldPages)
    }
    func testFailedRefreshAllowsLoadMoreThenRetrySuccessReplacesAccumulatedPages() throws {
        var state = SearchMapRefresh(); let old = try result(); let ticket = try begin(&state, old, pages(old))
        let retained = try finish(&state, ticket, .init(activities: [], nodes: [], activityFailure: .unavailable, nodeFailure: .unavailable))
        var continued = retained.pagination
        let page = try XCTUnwrap(continued.begin(query: query, scope: scope, manualAreaRevision: 7))
        continued.finish(page, page: try .init(rows: [activity(2)], pageNumber: 2, rawCount: 1))
        XCTAssertTrue(state.retainedActivities); XCTAssertEqual(continued.rows.map(\.id), [1, 2])
        let retry = try begin(&state, retained.result, continued)
        let updated = try finish(&state, retry, result([3], nodes: [3], rawCount: 1))
        XCTAssertEqual(updated.pagination.rows.map(\.id), [3]); XCTAssertFalse(state.hasRetainedResults)
        XCTAssertNil(updated.pagination.nextPage)
    }
    func testPageFailureSurvivesRefreshFailureAndIsIndependentOfRefreshRetry() throws {
        var state = SearchMapRefresh(); let old = try result(); var oldPages = pages(old)
        let page = try XCTUnwrap(oldPages.begin(query: query, scope: scope, manualAreaRevision: 7))
        oldPages.fail(page, error: .unavailable)
        let ticket = try begin(&state, old, oldPages)
        let update = try finish(&state, ticket, .init(activities: [], nodes: [], activityFailure: .unavailable, nodeFailure: .unavailable))
        XCTAssertEqual(update.pagination.failure, .unavailable); XCTAssertEqual(update.pagination.nextPage, 2)
        XCTAssertTrue(state.hasRetainedResults)
    }
    func testRetainedActivityKeepsOwnIdentityAndRealTopicAssociation() throws {
        var state = SearchMapRefresh(); let old = try result(); let ticket = try begin(&state, old, pages(old))
        let update = try finish(&state, ticket, .init(activities: [], nodes: [], activityFailure: .unavailable, nodeFailure: .unavailable))
        let activity = try XCTUnwrap(update.pagination.rows.first)
        XCTAssertEqual(activity.id, 1); XCTAssertEqual(activity.linkedTopicID, 99)
        XCTAssertEqual(SearchMapActivityPresentation(activity).primaryDestination, .activity(1))
    }
}

import XCTest
@testable import QuestifyCore

@MainActor private final class DeferredRewardReader: NonCashRewardReading {
    var scope = UUID()
    var isConfigured = true
    var isAuthenticated = true
    var isOfflineExample = false
    var cursors: [String?] = []
    var pending: [Int: CheckedContinuation<NonCashRewardPage, Error>] = [:]
    func rewards(cursor: String?) async throws -> NonCashRewardPage {
        let index = cursors.count; cursors.append(cursor)
        return try await withCheckedThrowingContinuation { pending[index] = $0 }
    }
    func reward(_ reference: NonCashRewardReference) async throws -> NonCashReward { throw APIError.notConfigured }
    func waitFor(_ count: Int) async { while cursors.count < count { await Task.yield() } }
    func finish(_ index: Int, _ page: NonCashRewardPage) { pending.removeValue(forKey: index)?.resume(returning: page) }
    func fail(_ index: Int, _ error: Error) { pending.removeValue(forKey: index)?.resume(throwing: error) }
}
@MainActor final class NonCashRewardCollectionTests: XCTestCase {
    private func item(_ id: String) -> NonCashReward {
        NonCashReward(awardId: id, contextType: .map, contextId: "map", releaseId: "release", instanceId: "season",
                      rulesVersion: "v1", merchantId: "1", storeId: "2", rewardTitle: "Item", quantity: 1,
                      validFrom: Date(timeIntervalSince1970: 100), validUntil: Date(timeIntervalSince1970: 200),
                      redemptionConditions: "Store only", state: .awarded, awardedAt: Date(timeIntervalSince1970: 100),
                      asOf: Date(timeIntervalSince1970: 150))
    }
    private func page(_ ids: [String], next: String? = nil) -> NonCashRewardPage {
        NonCashRewardPage(items: ids.map(item), nextCursor: next, asOf: Date(timeIntervalSince1970: 150))
    }
    func testRefreshWhileNextPagePendingDiscardsLatePage() async {
        let reader = DeferredRewardReader(), model = NonCashRewardCollectionModel()
        let initial = Task { await model.refresh(reader: reader) }
        await reader.waitFor(1); reader.finish(0, page(["a"], next: "a")); await initial.value
        let more = Task { await model.loadMore(reader: reader) }; await reader.waitFor(2)
        let refresh = Task { await model.refresh(reader: reader) }; await reader.waitFor(3)
        reader.finish(2, page(["c"])); await refresh.value
        reader.finish(1, page(["b"])); await more.value
        XCTAssertEqual(model.rows.map(\.id), ["c"]); XCTAssertNil(model.nextCursor)
    }
    func testDuplicateNextPageLeavesRowsAndRetryCursorUnchanged() async {
        let reader = DeferredRewardReader(), model = NonCashRewardCollectionModel()
        let initial = Task { await model.refresh(reader: reader) }
        await reader.waitFor(1); reader.finish(0, page(["a"], next: "a")); await initial.value
        let more = Task { await model.loadMore(reader: reader) }; await reader.waitFor(2)
        reader.finish(1, page(["a"])); await more.value
        XCTAssertEqual(model.rows.map(\.id), ["a"]); XCTAssertEqual(model.nextCursor, "a"); XCTAssertNotNil(model.moreIssue)
        let retry = Task { await model.loadMore(reader: reader) }; await reader.waitFor(3)
        XCTAssertEqual(reader.cursors[2], "a")
        reader.finish(2, page(["b"])); await retry.value
        XCTAssertEqual(model.rows.map(\.id), ["a", "b"]); XCTAssertNil(model.moreIssue)
    }
    func testScopeSwitchAndCancellationDoNotExposeOldRows() async {
        let reader = DeferredRewardReader(), model = NonCashRewardCollectionModel()
        let initial = Task { await model.refresh(reader: reader) }; await reader.waitFor(1)
        reader.scope = UUID(); reader.finish(0, page(["a"])); await initial.value
        XCTAssertTrue(model.visibleRows(scope: reader.scope).isEmpty)
        let cancelled = Task { await model.refresh(reader: reader) }; await reader.waitFor(2)
        model.cancelPending(); reader.finish(1, page(["b"])); await cancelled.value
        XCTAssertTrue(model.visibleRows(scope: reader.scope).isEmpty)
    }
    func testRepeatedMoreDuringPendingRequestDoesNotDispatchTwice() async {
        let reader = DeferredRewardReader(), model = NonCashRewardCollectionModel()
        let initial = Task { await model.refresh(reader: reader) }; await reader.waitFor(1)
        reader.finish(0, page(["a"], next: "a")); await initial.value
        let more = Task { await model.loadMore(reader: reader) }; await reader.waitFor(2)
        await model.loadMore(reader: reader); XCTAssertEqual(reader.cursors.count, 2)
        reader.fail(1, APIError.httpStatus(503)); await more.value
        XCTAssertEqual(model.rows.map(\.id), ["a"]); XCTAssertNotNil(model.moreIssue)
    }
    func testUnauthorizedNextPageRemovesOldRows() async {
        let reader = DeferredRewardReader(), model = NonCashRewardCollectionModel()
        let initial = Task { await model.refresh(reader: reader) }; await reader.waitFor(1)
        reader.finish(0, page(["a"], next: "a")); await initial.value
        let more = Task { await model.loadMore(reader: reader) }; await reader.waitFor(2)
        reader.fail(1, APIError.unauthorized); await more.value
        XCTAssertTrue(model.rows.isEmpty); XCTAssertEqual(model.issue, .login); XCTAssertNil(model.nextCursor)
    }
}

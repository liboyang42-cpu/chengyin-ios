import XCTest
@testable import QuestifyCore

/// Intentionally non-cooperative: late completions still arrive after cancellation.
@MainActor private final class CategoryRecoveryReader: SearchMapReading {
    var isConfigured = true
    var isAuthenticated = false
    let isOfflineExample = false
    var scope = UUID()
    var manualAreaRevision: UInt64 = 0
    private(set) var categoryCalls = 0
    private(set) var otherCalls = 0
    private(set) var cancelledReturns = 0
    private var pending: [Int: CheckedContinuation<[DiscoveryCategory], Error>] = [:]
    func categories() async throws -> [DiscoveryCategory] {
        let index = categoryCalls; categoryCalls += 1
        defer { if Task.isCancelled { cancelledReturns += 1 } }
        return try await withCheckedThrowingContinuation { pending[index] = $0 }
    }
    func finish(_ index: Int, _ result: Result<[DiscoveryCategory], Error>) {
        pending.removeValue(forKey: index)!.resume(with: result)
    }
    func selectManualArea(_ area: RoamSearchArea?) { otherCalls += 1 }
    func search(_ query: GlobalSearchQuery) async throws -> GlobalSearchResults { otherCalls += 1; throw APIError.notConfigured }
    func citySearch(_ query: CityNodeSearchQuery) async throws -> CityNodeSearchResults { otherCalls += 1; throw APIError.notConfigured }
    func nearby(area: RoamSearchArea) async throws -> SearchMapNearbyResults { otherCalls += 1; throw APIError.notConfigured }
    func cityNode(id: Int) async throws -> SearchMapCityNode { otherCalls += 1; throw APIError.notConfigured }
    func merchant(id: Int) async throws -> RoamMerchantDetail { otherCalls += 1; throw APIError.notConfigured }
}

@MainActor final class SearchMapCategoryRecoveryTests: XCTestCase {
    private func values(_ id: Int = 3) throws -> [DiscoveryCategory] {
        try JSONDecoder().decode([DiscoveryCategory].self, from: Data("[{\"id\":\(id),\"categoryName\":\"Category\"}]".utf8))
    }
    private func present(_ state: SearchMapCategoryRecovery, _ reader: CategoryRecoveryReader,
                         id: UUID = UUID(), active: Bool = true) throws -> SearchMapCategoryRecovery.Context {
        state.update(reader: reader, presentationID: id, active: active)
        return try XCTUnwrap(state.context(for: .init(reader: reader)))
    }
    private func waitForCalls(_ count: Int, _ reader: CategoryRecoveryReader) async throws {
        for _ in 0..<1000 {
            if reader.categoryCalls == count { return }
            await Task.yield()
        }
        XCTFail("Category request did not start")
        throw APIError.notConfigured
    }
    private func failInitial(_ state: SearchMapCategoryRecovery, _ reader: CategoryRecoveryReader,
                             _ context: SearchMapCategoryRecovery.Context) async throws {
        let request = try XCTUnwrap(state.loadIfNeeded(in: context))
        try await waitForCalls(1, reader)
        reader.finish(0, .failure(APIError.notConfigured)); await request.value
        XCTAssertEqual(state.phase, .failed)
    }
    func testFailureRetrySingleFlightAndSuccessUseOnlyCategoryRead() async throws {
        let state = SearchMapCategoryRecovery(), reader = CategoryRecoveryReader()
        let context = try present(state, reader)
        try await failInitial(state, reader, context)
        let retry = try XCTUnwrap(state.retry(in: context))
        XCTAssertEqual(state.phase, .loading)
        XCTAssertNil(state.retry(in: context)); XCTAssertNil(state.loadIfNeeded(in: context))
        try await waitForCalls(2, reader)
        reader.finish(1, .success(try values())); await retry.value
        XCTAssertEqual(state.phase, .loaded); XCTAssertEqual(state.categories.map(\.id), [3])
        XCTAssertNil(state.retry(in: context)); XCTAssertEqual(reader.categoryCalls, 2)
        XCTAssertEqual(reader.otherCalls, 0)
    }
    func testInitialReadAlsoAcquiresSlotBeforeTaskStarts() async throws {
        let state = SearchMapCategoryRecovery(), reader = CategoryRecoveryReader()
        let context = try present(state, reader)
        let request = try XCTUnwrap(state.loadIfNeeded(in: context))
        XCTAssertNil(state.loadIfNeeded(in: context)); XCTAssertNil(state.retry(in: context))
        try await waitForCalls(1, reader); reader.finish(0, .success([])); await request.value
        XCTAssertEqual(reader.categoryCalls, 1)
    }
    func testAuthoritativeEmptySuccessDoesNotBecomeFailureOrReloadOnReopen() async throws {
        let state = SearchMapCategoryRecovery(), reader = CategoryRecoveryReader()
        let context = try present(state, reader)
        try await failInitial(state, reader, context)
        let request = try XCTUnwrap(state.retry(in: context))
        try await waitForCalls(2, reader); reader.finish(1, .success([])); await request.value
        XCTAssertEqual(state.phase, .loaded); XCTAssertTrue(state.categories.isEmpty)
        state.update(reader: reader, presentationID: nil, active: true)
        let reopened = try present(state, reader)
        XCTAssertNil(state.loadIfNeeded(in: reopened)); XCTAssertNil(state.retry(in: reopened))
        XCTAssertEqual(reader.categoryCalls, 2)
    }
    func testRetryFailureRemainsExplicitlyRetryable() async throws {
        let state = SearchMapCategoryRecovery(), reader = CategoryRecoveryReader()
        let context = try present(state, reader)
        try await failInitial(state, reader, context)
        let request = try XCTUnwrap(state.retry(in: context))
        try await waitForCalls(2, reader); reader.finish(1, .failure(APIError.unauthorized)); await request.value
        XCTAssertEqual(state.phase, .failed); XCTAssertTrue(state.categories.isEmpty)
        let third = try XCTUnwrap(state.retry(in: context))
        try await waitForCalls(3, reader); reader.finish(2, .success(try values(9))); await third.value
        XCTAssertEqual(state.categories.map(\.id), [9]); XCTAssertEqual(reader.otherCalls, 0)
    }
    func testNoRequestWithoutVisibleActiveConfiguredPresentation() throws {
        let state = SearchMapCategoryRecovery(), reader = CategoryRecoveryReader()
        state.update(reader: reader, presentationID: nil, active: true)
        XCTAssertNil(state.context(for: .init(reader: reader)))
        state.update(reader: reader, presentationID: UUID(), active: false)
        XCTAssertNil(state.context(for: .init(reader: reader)))
        reader.isConfigured = false
        state.update(reader: reader, presentationID: UUID(), active: true)
        XCTAssertNil(state.context(for: .init(reader: reader)))
        XCTAssertEqual(reader.categoryCalls, 0)
    }
    func testCloseBeforeQueuedReadPreventsDispatch() async throws {
        let state = SearchMapCategoryRecovery(), reader = CategoryRecoveryReader()
        let context = try present(state, reader)
        let request = try XCTUnwrap(state.loadIfNeeded(in: context))
        state.update(reader: reader, presentationID: nil, active: true)
        await request.value
        XCTAssertEqual(reader.categoryCalls, 0); XCTAssertEqual(state.phase, .idle)
        XCTAssertFalse(state.accepts(context))
    }
    func testCloseReopenRejectsOldSuccessAndOldRetryWithoutClearingNewPending() async throws {
        let state = SearchMapCategoryRecovery(), reader = CategoryRecoveryReader()
        let old = try present(state, reader)
        try await failInitial(state, reader, old)
        let firstRetry = try XCTUnwrap(state.retry(in: old)); try await waitForCalls(2, reader)
        state.update(reader: reader, presentationID: nil, active: true)
        let fresh = try present(state, reader)
        XCTAssertNil(state.retry(in: old))
        let secondRetry = try XCTUnwrap(state.retry(in: fresh)); try await waitForCalls(3, reader)
        reader.finish(1, .success(try values(1))); await firstRetry.value
        XCTAssertEqual(state.phase, .loading); XCTAssertTrue(state.categories.isEmpty)
        reader.finish(2, .success(try values(2))); await secondRetry.value
        XCTAssertEqual(state.categories.map(\.id), [2]); XCTAssertEqual(reader.cancelledReturns, 1)
    }
    func testLateOldFailureCannotOverwriteNewSuccessfulDirectory() async throws {
        let state = SearchMapCategoryRecovery(), reader = CategoryRecoveryReader()
        let old = try present(state, reader)
        let first = try XCTUnwrap(state.loadIfNeeded(in: old)); try await waitForCalls(1, reader)
        state.update(reader: reader, presentationID: nil, active: true)
        let fresh = try present(state, reader)
        let second = try XCTUnwrap(state.loadIfNeeded(in: fresh)); try await waitForCalls(2, reader)
        reader.finish(1, .success(try values(7))); await second.value
        reader.finish(0, .failure(APIError.unauthorized)); await first.value
        XCTAssertEqual(state.phase, .loaded); XCTAssertEqual(state.categories.map(\.id), [7])
    }
    func testReaderReplacementWithSameScopeRejectsOldObjectAndItsCompletion() async throws {
        let state = SearchMapCategoryRecovery(), firstReader = CategoryRecoveryReader(), secondReader = CategoryRecoveryReader()
        secondReader.scope = firstReader.scope
        let id = UUID(), old = try present(state, firstReader)
        let first = try XCTUnwrap(state.loadIfNeeded(in: old)); try await waitForCalls(1, firstReader)
        let fresh = try present(state, secondReader, id: id)
        XCTAssertFalse(state.owns(.init(reader: firstReader))); XCTAssertFalse(state.accepts(old))
        let second = try XCTUnwrap(state.loadIfNeeded(in: fresh)); try await waitForCalls(1, secondReader)
        firstReader.finish(0, .success(try values(1))); await first.value
        XCTAssertEqual(state.phase, .loading); XCTAssertTrue(state.categories.isEmpty)
        secondReader.finish(0, .success(try values(2))); await second.value
        XCTAssertEqual(state.categories.map(\.id), [2])
    }
    func testObservedOwnerScopeAndConfigurationABARetireOldContext() async throws {
        for change in 0..<3 {
            let state = SearchMapCategoryRecovery(), reader = CategoryRecoveryReader(), id = UUID()
            let old = try present(state, reader, id: id)
            let request = try XCTUnwrap(state.loadIfNeeded(in: old)); try await waitForCalls(1, reader)
            let scope = reader.scope
            if change == 0 { reader.scope = UUID() }
            if change == 1 { reader.isConfigured = false }
            if change == 2 { reader.isAuthenticated = true }
            state.update(reader: reader, presentationID: id, active: true)
            reader.scope = scope; reader.isConfigured = true; reader.isAuthenticated = false
            let fresh = try present(state, reader, id: id)
            XCTAssertNotEqual(old, fresh); XCTAssertFalse(state.accepts(old))
            reader.finish(0, .success(try values())); await request.value
            XCTAssertEqual(state.phase, .idle); XCTAssertTrue(state.categories.isEmpty)
            XCTAssertEqual(reader.cancelledReturns, 1)
        }
    }
    func testReaderObjectABARetiresOriginalCallbackEvenWithSameScope() async throws {
        let state = SearchMapCategoryRecovery(), first = CategoryRecoveryReader(), second = CategoryRecoveryReader(), id = UUID()
        second.scope = first.scope
        let old = try present(state, first, id: id)
        let request = try XCTUnwrap(state.loadIfNeeded(in: old)); try await waitForCalls(1, first)
        state.update(reader: second, presentationID: id, active: true)
        let fresh = try present(state, first, id: id)
        XCTAssertNotEqual(old, fresh); XCTAssertFalse(state.accepts(old))
        first.finish(0, .success(try values())); await request.value
        XCTAssertEqual(state.phase, .idle); XCTAssertTrue(state.categories.isEmpty)
    }
    func testBackgroundForegroundAndOwnerDepartureRetirePendingRetry() async throws {
        let state = SearchMapCategoryRecovery(), reader = CategoryRecoveryReader(), id = UUID()
        let old = try present(state, reader, id: id)
        try await failInitial(state, reader, old)
        let request = try XCTUnwrap(state.retry(in: old)); try await waitForCalls(2, reader)
        state.update(reader: reader, presentationID: id, active: false)
        XCTAssertEqual(state.phase, .failed)
        let fresh = try present(state, reader, id: id)
        XCTAssertNotEqual(old, fresh); XCTAssertNil(state.retry(in: old))
        reader.finish(1, .failure(APIError.unauthorized)); await request.value
        XCTAssertEqual(state.phase, .failed); XCTAssertEqual(reader.cancelledReturns, 1)
        XCTAssertNil(state.loadIfNeeded(in: fresh)) // Failed reads require the visible Retry button.
    }
    func testCancelledInitialAndRetryDoNotCreateNewFailure() async throws {
        let state = SearchMapCategoryRecovery(), reader = CategoryRecoveryReader()
        let context = try present(state, reader)
        let initial = try XCTUnwrap(state.loadIfNeeded(in: context)); try await waitForCalls(1, reader)
        reader.finish(0, .failure(CancellationError())); await initial.value
        XCTAssertEqual(state.phase, .idle)
        let second = try XCTUnwrap(state.loadIfNeeded(in: context)); try await waitForCalls(2, reader)
        reader.finish(1, .failure(APIError.notConfigured)); await second.value
        let retry = try XCTUnwrap(state.retry(in: context)); try await waitForCalls(3, reader)
        reader.finish(2, .failure(CancellationError())); await retry.value
        XCTAssertEqual(state.phase, .failed); XCTAssertTrue(state.categories.isEmpty)
    }
    func testActualReaderMutationIsCheckedWithoutWaitingForViewUpdate() async throws {
        for change in 0..<4 {
            let state = SearchMapCategoryRecovery(), reader = CategoryRecoveryReader()
            let old = try present(state, reader)
            let request = try XCTUnwrap(state.loadIfNeeded(in: old)); try await waitForCalls(1, reader)
            if change == 0 { reader.scope = UUID() }
            if change == 1 { reader.isConfigured = false }
            if change == 2 { reader.isAuthenticated = true }
            if change == 3 { reader.manualAreaRevision += 1 }
            reader.finish(0, .success(try values())); await request.value
            XCTAssertFalse(state.accepts(old)); XCTAssertEqual(state.phase, .idle)
            XCTAssertTrue(state.categories.isEmpty)
        }
    }
    func testSettledDirectoryIsClearedWhenReaderAuthorityChanges() async throws {
        let state = SearchMapCategoryRecovery(), reader = CategoryRecoveryReader(), id = UUID()
        let old = try present(state, reader, id: id)
        let request = try XCTUnwrap(state.loadIfNeeded(in: old)); try await waitForCalls(1, reader)
        reader.finish(0, .success(try values())); await request.value
        reader.scope = UUID(); state.update(reader: reader, presentationID: id, active: true)
        XCTAssertEqual(state.phase, .idle); XCTAssertTrue(state.categories.isEmpty)
        XCTAssertFalse(state.accepts(old)); XCTAssertEqual(reader.otherCalls, 0)
    }
    func testUnconfiguredVisiblePresentationCanApplyLocalDraftWithoutCategoryRead() throws {
        let state = SearchMapCategoryRecovery(), reader = CategoryRecoveryReader()
        reader.isConfigured = false
        state.update(reader: reader, presentationID: UUID(), active: true)
        let owner = SearchMapCategoryRecovery.Owner(reader: reader)
        let applyContext = try XCTUnwrap(state.presentationContext(for: owner))
        XCTAssertNil(state.context(for: owner))
        XCTAssertTrue(state.acceptsPresentation(applyContext)); XCTAssertFalse(state.accepts(applyContext))
        XCTAssertNil(state.loadIfNeeded(in: applyContext)); XCTAssertNil(state.retry(in: applyContext))
        var draft = GlobalSearchQuery(keyword: "manual")
        draft.categoryID = 73; draft.startDate = "2026-10-10"; draft.endDate = "2026-10-12"
        draft.minimumPrice = 12; draft.maximumPrice = 90
        var applied: GlobalSearchQuery?
        // The shipping Apply closure uses this presentation-only guard.
        if state.acceptsPresentation(applyContext) { applied = draft }
        XCTAssertEqual(applied, draft); XCTAssertEqual(applied?.categoryID, 73)
        XCTAssertEqual(applied?.minimumPrice, 12); XCTAssertEqual(applied?.endDate, "2026-10-12")
        XCTAssertEqual(reader.categoryCalls, 0); XCTAssertEqual(reader.otherCalls, 0)
    }
    func testUnconfiguredApplyRejectsClosedBackgroundAndConfigurationABACallbacks() throws {
        for change in 0..<3 {
            let state = SearchMapCategoryRecovery(), reader = CategoryRecoveryReader(), id = UUID()
            reader.isConfigured = false
            state.update(reader: reader, presentationID: id, active: true)
            let old = try XCTUnwrap(state.presentationContext(for: .init(reader: reader)))
            if change == 0 { state.update(reader: reader, presentationID: nil, active: true) }
            if change == 1 { state.update(reader: reader, presentationID: id, active: false) }
            if change == 2 {
                reader.isConfigured = true
                state.update(reader: reader, presentationID: id, active: true)
            }
            XCTAssertFalse(state.acceptsPresentation(old))
            reader.isConfigured = false
            state.update(reader: reader, presentationID: id, active: true)
            let fresh = try XCTUnwrap(state.presentationContext(for: .init(reader: reader)))
            XCTAssertNotEqual(old, fresh); XCTAssertFalse(state.acceptsPresentation(old))
            XCTAssertTrue(state.acceptsPresentation(fresh)); XCTAssertFalse(state.accepts(fresh))
            XCTAssertEqual(reader.categoryCalls, 0)
        }
    }
    func testUnconfiguredReaderReplacementCannotReuseLocalApplyCallback() throws {
        let state = SearchMapCategoryRecovery(), first = CategoryRecoveryReader(), second = CategoryRecoveryReader(), id = UUID()
        first.isConfigured = false; second.isConfigured = false; second.scope = first.scope
        state.update(reader: first, presentationID: id, active: true)
        let old = try XCTUnwrap(state.presentationContext(for: .init(reader: first)))
        state.update(reader: second, presentationID: id, active: true)
        XCTAssertFalse(state.acceptsPresentation(old))
        state.update(reader: first, presentationID: id, active: true)
        let fresh = try XCTUnwrap(state.presentationContext(for: .init(reader: first)))
        XCTAssertNotEqual(old, fresh); XCTAssertFalse(state.acceptsPresentation(old))
        XCTAssertTrue(state.acceptsPresentation(fresh)); XCTAssertEqual(first.categoryCalls, 0)
    }

}

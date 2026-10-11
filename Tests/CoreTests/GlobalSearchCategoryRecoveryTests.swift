import XCTest
@testable import QuestifyCore

/// Direct tests of the unchanged directory controller using the global host's
/// page/sheet lifetimes. These do not instantiate or render GlobalSearchView.
@MainActor private final class GlobalCategoryReader: SearchMapReading {
    var isConfigured = true
    var isAuthenticated = false
    var scope = UUID()
    let isOfflineExample = false
    private(set) var calls = 0
    private(set) var otherCalls = 0
    private var pending: [Int: CheckedContinuation<[DiscoveryCategory], Error>] = [:]
    func categories() async throws -> [DiscoveryCategory] {
        let index = calls; calls += 1
        // Deliberately completes even after Task cancellation.
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

@MainActor final class GlobalSearchCategoryRecoveryTests: XCTestCase {
    private func context(_ state: SearchMapCategoryRecovery, _ reader: GlobalCategoryReader,
                         _ id: UUID = UUID(), active: Bool = true) throws -> SearchMapCategoryRecovery.Context {
        state.update(reader: reader, presentationID: id, active: active)
        return try XCTUnwrap(state.context(for: .init(reader: reader)))
    }
    private func wait(_ calls: Int, _ reader: GlobalCategoryReader) async throws {
        for _ in 0..<1000 {
            if reader.calls == calls { return }
            await Task.yield()
        }
        XCTFail("Expected directory read did not start")
        throw APIError.notConfigured
    }
    private func values(_ id: Int) throws -> [DiscoveryCategory] {
        try JSONDecoder().decode([DiscoveryCategory].self, from: Data("[{\"id\":\(id),\"categoryName\":\"Category\"}]".utf8))
    }
    private func fail(_ state: SearchMapCategoryRecovery, _ reader: GlobalCategoryReader,
                      _ captured: SearchMapCategoryRecovery.Context) async throws {
        let task = try XCTUnwrap(state.loadIfNeeded(in: captured))
        try await wait(1, reader)
        reader.finish(0, .failure(APIError.notConfigured)); await task.value
        XCTAssertEqual(state.phase, .failed)
    }
    func testPageFailureRecoversInSheetWithoutChangingQueryOrDraft() async throws {
        let state = SearchMapCategoryRecovery(), reader = GlobalCategoryReader()
        let query = GlobalSearchQuery(keyword: "tea", categoryID: 9, startDate: "2026-10-10", minimumPrice: 3.5)
        var draft = query; draft.categoryID = 77; draft.maximumPrice = 83.5
        let savedDraft = draft
        let page = try context(state, reader)
        try await fail(state, reader, page)
        let sheet = try context(state, reader)
        XCTAssertNil(state.retry(in: page))
        let retry = try XCTUnwrap(state.retry(in: sheet))
        XCTAssertNil(state.retry(in: sheet)); XCTAssertNil(state.loadIfNeeded(in: sheet))
        try await wait(2, reader)
        reader.finish(1, .success(try values(2))); await retry.value
        XCTAssertEqual(state.phase, .loaded); XCTAssertEqual(state.categories.map(\.id), [2])
        XCTAssertEqual(query.categoryID, 9); XCTAssertEqual(draft, savedDraft)
        XCTAssertEqual(reader.otherCalls, 0)
    }
    func testSurfaceSwitchRejectsOldRetryAndNonCooperativeCompletion() async throws {
        let state = SearchMapCategoryRecovery(), reader = GlobalCategoryReader()
        let page = try context(state, reader)
        let old = try XCTUnwrap(state.loadIfNeeded(in: page)); try await wait(1, reader)
        state.update(reader: reader, presentationID: nil, active: true) // Opening, sheet not yet visible.
        XCTAssertFalse(state.accepts(page)); XCTAssertNil(state.retry(in: page))
        let sheet = try context(state, reader)
        let current = try XCTUnwrap(state.loadIfNeeded(in: sheet)); try await wait(2, reader)
        reader.finish(0, .success(try values(999))); await old.value
        XCTAssertTrue(state.categories.isEmpty); XCTAssertEqual(state.phase, .loading)
        XCTAssertNil(state.loadIfNeeded(in: sheet)) // Old defer must not clear the new slot.
        reader.finish(1, .success(try values(3))); await current.value
        XCTAssertEqual(state.categories.map(\.id), [3]); XCTAssertEqual(reader.otherCalls, 0)
    }
    func testCloseReopenKeepsSelectedMissingCategoryAndSettledEmptyDirectory() async throws {
        let state = SearchMapCategoryRecovery(), reader = GlobalCategoryReader()
        let draft = GlobalSearchQuery(keyword: "same query", categoryID: 77, minimumPrice: 5.5, maximumPrice: 5.5)
        let firstSheet = try context(state, reader)
        let request = try XCTUnwrap(state.loadIfNeeded(in: firstSheet)); try await wait(1, reader)
        reader.finish(0, .success([])); await request.value
        let page = try context(state, reader)
        let secondSheet = try context(state, reader)
        XCTAssertFalse(state.acceptsPresentation(firstSheet)); XCTAssertFalse(state.accepts(page))
        XCTAssertEqual(state.phase, .loaded); XCTAssertTrue(state.categories.isEmpty)
        XCTAssertNil(state.loadIfNeeded(in: secondSheet)); XCTAssertNil(state.retry(in: firstSheet))
        XCTAssertEqual(draft.categoryID, 77); XCTAssertEqual(draft.minimumPrice, draft.maximumPrice)
        XCTAssertEqual(reader.calls, 1); XCTAssertEqual(reader.otherCalls, 0)
    }
    func testForegroundResumeRetiresOldCallbackWithoutResettingDraft() async throws {
        let state = SearchMapCategoryRecovery(), reader = GlobalCategoryReader(), presentationID = UUID()
        var draft = GlobalSearchQuery(keyword: "tea", categoryID: 81)
        draft.startDate = "2026-11-11"; draft.maximumPrice = 9.5
        let saved = draft
        let before = try context(state, reader, presentationID)
        try await fail(state, reader, before)
        let old = try XCTUnwrap(state.retry(in: before)); try await wait(2, reader)
        state.update(reader: reader, presentationID: presentationID, active: false)
        XCTAssertFalse(state.acceptsPresentation(before))
        let resumed = try context(state, reader, presentationID)
        XCTAssertFalse(state.accepts(before)); XCTAssertEqual(state.phase, .failed)
        let current = try XCTUnwrap(state.retry(in: resumed)); try await wait(3, reader)
        reader.finish(2, .success(try values(5))); await current.value
        reader.finish(1, .failure(APIError.unauthorized)); await old.value
        XCTAssertEqual(state.phase, .loaded); XCTAssertEqual(state.categories.map(\.id), [5])
        XCTAssertEqual(draft, saved); XCTAssertEqual(reader.otherCalls, 0)
    }
    func testSameScopeReaderReplacementRejectsOldPageAndSheetActions() async throws {
        let state = SearchMapCategoryRecovery(), oldReader = GlobalCategoryReader(), newReader = GlobalCategoryReader()
        newReader.scope = oldReader.scope
        let page = try context(state, oldReader)
        let sheet = try context(state, oldReader)
        let old = try XCTUnwrap(state.loadIfNeeded(in: sheet)); try await wait(1, oldReader)
        let currentContext = try context(state, newReader)
        XCTAssertFalse(state.acceptsPresentation(page)); XCTAssertFalse(state.acceptsPresentation(sheet))
        XCTAssertNil(state.retry(in: sheet)); XCTAssertFalse(state.owns(.init(reader: oldReader)))
        let current = try XCTUnwrap(state.loadIfNeeded(in: currentContext)); try await wait(1, newReader)
        oldReader.finish(0, .success(try values(999))); await old.value
        XCTAssertTrue(state.categories.isEmpty); XCTAssertEqual(state.phase, .loading)
        newReader.finish(0, .success(try values(7))); await current.value
        XCTAssertEqual(state.categories.map(\.id), [7])
        XCTAssertEqual(oldReader.otherCalls + newReader.otherCalls, 0)
    }
    func testUnconfiguredSheetMayApplyLocalDraftButCannotReadCategories() throws {
        let state = SearchMapCategoryRecovery(), reader = GlobalCategoryReader(), id = UUID()
        reader.isConfigured = false
        state.update(reader: reader, presentationID: id, active: true)
        let apply = try XCTUnwrap(state.presentationContext(for: .init(reader: reader)))
        XCTAssertTrue(state.acceptsPresentation(apply)); XCTAssertNil(state.context(for: .init(reader: reader)))
        XCTAssertNil(state.loadIfNeeded(in: apply)); XCTAssertNil(state.retry(in: apply))
        state.update(reader: reader, presentationID: nil, active: true)
        XCTAssertFalse(state.acceptsPresentation(apply))
        state.update(reader: reader, presentationID: UUID(), active: true)
        XCTAssertFalse(state.acceptsPresentation(apply)); XCTAssertEqual(reader.calls, 0)
    }
}

import XCTest
@testable import Questify

@MainActor final class ProjectNodePlacePickerTests: XCTestCase {
    private final class Owner { var session: ProjectEditSession? = try? .init(accountID: 7, epoch: 1, storageNamespace: "node-place") }
    private final class Reader: SearchMapReading {
        var isConfigured = true, isAuthenticated = true, isOfflineExample = false
        var scope = UUID(), manualAreaRevision: UInt64 = 0
        var requests: [CityNodeSearchQuery] = [], result: [SearchMapCityNode] = []
        var paused = false, failure: APIError?
        var continuation: CheckedContinuation<[SearchMapCityNode], Error>?
        func selectManualArea(_ area: RoamSearchArea?) { manualAreaRevision += 1 }
        func cityNodes(_ query: CityNodeSearchQuery) async throws -> [SearchMapCityNode] {
            requests.append(query)
            if paused { return try await withCheckedThrowingContinuation { continuation = $0 } }
            if let failure { throw failure }; return result
        }
        func finish() { continuation?.resume(returning: result); continuation = nil }
        func categories() async throws -> [DiscoveryCategory] { throw APIError.notConfigured }
        func search(_ q: GlobalSearchQuery) async throws -> GlobalSearchResults { throw APIError.notConfigured }
        func citySearch(_ q: CityNodeSearchQuery) async throws -> CityNodeSearchResults { throw APIError.notConfigured }
        func nearby(area: RoamSearchArea) async throws -> SearchMapNearbyResults { throw APIError.notConfigured }
        func cityNode(id: Int) async throws -> SearchMapCityNode { throw APIError.notConfigured }
        func merchant(id: Int) async throws -> RoamMerchantDetail { throw APIError.notConfigured }
    }
    private func setup(scope: ProjectEditScope = .full) async throws -> (ProjectNodePlacePickerController, Owner, Reader, ProjectEditMemoryStorage) {
        let owner = Owner(), reader = Reader(), storage = ProjectEditMemoryStorage(); var draft = ProjectEditSyntheticFixtures.draft()
        draft.chapters[0].id = "chapter"; draft.chapters[0].nodes[0].id = "node"
        reader.result = [try JSONDecoder().decode(SearchMapCityNode.self, from: Data(#"{"poiId":7,"name":"Chosen label","lat":32.25,"lng":122.5}"#.utf8))]
        let initial = ProjectEditSnapshot(topicID: scope == .whitelist ? 101 : nil, scope: scope, draft: draft)
        let model = ProjectEditModel(coordinator: .init(initial: initial, service: ProjectEditSyntheticService(snapshot: initial), store: .init(storage: storage), currentSession: { owner.session }))
        await model.load(); let c = ProjectNodePlacePickerController(model: model, reader: reader, chapterID: "chapter", nodeID: "node"); c.setActive(true); return (c, owner, reader, storage)
    }
    private func open(_ c: ProjectNodePlacePickerController) throws -> ProjectNodePlacePickerController.Opening { c.open(try XCTUnwrap(c.capture())); return try XCTUnwrap(c.opening) }
    private func search(_ c: ProjectNodePlacePickerController, _ o: ProjectNodePlacePickerController.Opening) async {
        c.edit(.init(latitude: "31", longitude: "121", keyword: "park"), in: o); await c.search(o, action: c.captureSearch(o))
    }
    func testOpeningNeverSearchesAndCancelLeavesDraftAndStorageUntouched() async throws {
        let (c, _, r, storage) = try await setup(), bytes = ProjectEditPendingMaterials.exactData(c.model.draft), saved = storage.data, o = try open(c)
        XCTAssertTrue(r.requests.isEmpty); await search(c, o); c.choose(r.result[0], in: o); c.close(o)
        XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.model.draft), bytes); XCTAssertEqual(storage.data, saved); XCTAssertFalse(c.apply(o))
    }
    func testExplicitChoiceAppliesPOICoordinatesNeverSearchCenterAndOnlyOnce() async throws {
        let (c, _, r, _) = try await setup(), o = try open(c), name = c.model.draft.chapters[0].nodes[0].name
        await search(c, o); XCTAssertFalse(c.canApply(o)); c.choose(r.result[0], in: o); XCTAssertTrue(c.apply(o)); XCTAssertFalse(c.apply(o))
        XCTAssertEqual(c.model.draft.chapters[0].nodes[0].latitude, "32.25"); XCTAssertEqual(c.model.draft.chapters[0].nodes[0].longitude, "122.5")
        XCTAssertEqual(c.model.draft.chapters[0].nodes[0].name, name); XCTAssertEqual(r.requests[0].area.coordinate.latitude, 31)
    }
    func testInputChangeClearsSelectionAndStaleLateResults() async throws {
        let (c, _, r, _) = try await setup(), o = try open(c); r.paused = true
        c.edit(.init(latitude: "31", longitude: "121"), in: o); let task = Task { await c.search(o, action: c.captureSearch(o)) }
        for _ in 0..<100 where r.continuation == nil { await Task.yield() }
        c.edit(.init(latitude: "33", longitude: "123"), in: o); r.finish(); await task.value
        XCTAssertTrue(c.rows.isEmpty); XCTAssertNil(c.selected); XCTAssertEqual(c.state, .idle)
    }
    func testOwnerScopeAreaAndSameByteABARetireStagedApply() async throws {
        for change in ["owner", "reader", "area", "aba", "retire"] {
            let (c, owner, r, _) = try await setup(), o = try open(c); await search(c, o); c.choose(r.result[0], in: o)
            switch change {
            case "owner": owner.session = nil
            case "reader": r.scope = UUID()
            case "area": r.manualAreaRevision += 1
            case "aba": let same = c.model.draft; c.model.draft = same
            default: c.retire()
            }
            let before = ProjectEditPendingMaterials.exactData(c.model.draft); XCTAssertFalse(c.apply(o)); XCTAssertEqual(ProjectEditPendingMaterials.exactData(c.model.draft), before)
        }
    }
    func testUnavailableAndInvalidInputHaveNoRead() async throws {
        let (c, _, r, _) = try await setup(), o = try open(c)
        for input in [ProjectNodePlacePickerController.Input(), .init(latitude: "91", longitude: "121"), .init(latitude: "31", longitude: "121", keyword: " bad ")] {
            c.edit(input, in: o); await c.search(o, action: c.captureSearch(o)); XCTAssertEqual(c.state, .invalid)
        }
        XCTAssertTrue(r.requests.isEmpty); r.isConfigured = false; await c.search(o, action: c.captureSearch(o)); XCTAssertEqual(c.state, .unavailable); XCTAssertTrue(r.requests.isEmpty)
    }
    func testOldBindingCannotDismissNewPresentation() async throws {
        let (c, _, _, _) = try await setup(), old = try open(c), binding = c.binding(old); c.close(old); let next = try open(c)
        binding.wrappedValue = nil; c.edit(.init(latitude: "31"), in: old); XCTAssertEqual(c.opening?.id, next.id); XCTAssertEqual(c.input.latitude, "")
    }
    func testReadOnlyCannotOpenAndDeniedReadCannotChoose() async throws {
        let (locked, _, _, _) = try await setup(scope: .whitelist); XCTAssertNil(locked.capture())
        let (c, _, r, _) = try await setup(), o = try open(c); r.failure = .notConfigured; await search(c, o)
        XCTAssertEqual(c.state, .unavailable); c.choose(r.result[0], in: o); XCTAssertNil(c.selected); XCTAssertFalse(c.apply(o))
    }
    func testMalformedDuplicateResultsFailWithoutDroppingRows() async throws {
        let (c, _, r, _) = try await setup(), o = try open(c); r.result.append(r.result[0]); await search(c, o)
        XCTAssertEqual(c.state, .failed); XCTAssertTrue(c.rows.isEmpty)
    }
    func testRetiredQueuedOpeningAndInactiveHostCannotOpen() async throws {
        let (c, _, _, _) = try await setup(), old = try XCTUnwrap(c.capture())
        c.setActive(false); XCTAssertNil(c.capture()); c.setActive(true); c.open(old); XCTAssertNil(c.opening)
        let fresh = try XCTUnwrap(c.capture()); c.model.draft = c.model.draft; c.open(fresh); XCTAssertNil(c.opening)
    }

    func testCanonicalEquivalentKeywordEditClearsRowsAndSelection() async throws {
        let (c, _, r, _) = try await setup(), o = try open(c)
        c.edit(.init(latitude: "31", longitude: "121", keyword: "é"), in: o)
        await c.search(o, action: c.captureSearch(o)); c.choose(r.result[0], in: o); XCTAssertTrue(c.canApply(o))
        c.edit(.init(latitude: "31", longitude: "121", keyword: "e\u{0301}"), in: o)
        XCTAssertEqual(Data(c.input.keyword.utf8), Data("e\u{0301}".utf8)); XCTAssertTrue(c.rows.isEmpty); XCTAssertNil(c.selected); XCTAssertFalse(c.canApply(o))
    }
    func testQueuedSearchCapturesExactInputAndRejectsEditABAAndDuplicateAction() async throws {
        let (c, _, r, _) = try await setup(), o = try open(c)
        let first = ProjectNodePlacePickerController.Input(latitude: "31", longitude: "121", keyword: "park")
        c.edit(first, in: o); let action = try XCTUnwrap(c.captureSearch(o))
        c.edit(.init(latitude: "32", longitude: "122", keyword: "new"), in: o)
        await c.search(o, action: action); XCTAssertTrue(r.requests.isEmpty)
        c.edit(first, in: o); await c.search(o, action: action); XCTAssertTrue(r.requests.isEmpty)
        let current = try XCTUnwrap(c.captureSearch(o)); await c.search(o, action: current); await c.search(o, action: current)
        XCTAssertEqual(r.requests.count, 1)
    }

    func testQueuedSearchAfterDepartureMakesZeroRequests() async throws {
        let (c, _, r, _) = try await setup(), o = try open(c)
        c.edit(.init(latitude: "31", longitude: "121", keyword: "park"), in: o)
        let action = try XCTUnwrap(c.captureSearch(o)); c.setActive(false)
        await c.search(o, action: action); XCTAssertTrue(r.requests.isEmpty)
        c.setActive(true); _ = try open(c); await c.search(o, action: action); XCTAssertTrue(r.requests.isEmpty)
    }

    func testOrdinaryCaptureRetainsExplicitSavedTargetKind() async throws {
        let (c, _, _, _) = try await setup(), capture = try XCTUnwrap(c.capture())
        XCTAssertNil(c.pendingTarget)
        if case .saved = capture.snapshot {} else { XCTFail("ordinary node became pending") }
    }

}

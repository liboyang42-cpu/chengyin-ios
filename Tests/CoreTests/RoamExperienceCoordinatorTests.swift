import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor private final class ExperienceReaderDouble: RoamExperienceReading {
    var identity: RoamExperienceIdentity? = RoamExperienceIdentity(scope: try! RoamHistoryScope(market: "cn", deployment: URL(string: "https://example.com/fixture/")!, accountID: 1), epoch: 1)
    var isConfigured = true
    var isOfflineExample = true
    var requestedPages: [Int] = []
    var requestedCursors: [Int] = []
    var tileJSON = RoamExperienceSyntheticFixtures.tiles
    var tileWait: (() async -> Void)?
    var failNextPage = false
    var factJSON = RoamExperienceSyntheticFixtures.settled
    var onRead: (() -> Void)?
    func history() throws -> [RoamHistoryRecord] { [] }
    func sessionFact(_ query: RoamRecoveryQuery) async throws -> RoamSessionFact {
        onRead?(); return try JSONDecoder().decode(RoamSessionFact.self, from: Data(factJSON.utf8))
    }
    func album(page: Int, pageSize: Int) async throws -> RoamAlbumPage {
        requestedPages.append(page); onRead?()
        if failNextPage { throw APIError.httpStatus(503) }
        let json = page == 1
            ? #"{"list":[{"id":1,"checkState":0},{"id":2,"checkState":1}],"total":3,"pageNum":1,"pageSize":2}"#
            : #"{"list":[{"id":1,"checkState":2},{"id":3,"checkState":0}],"total":3,"pageNum":2,"pageSize":2}"#
        return try JSONDecoder().decode(RoamAlbumPage.self, from: Data(json.utf8))
    }
    func tilePage(afterID: Int, limit: Int) async throws -> RoamTileMemoryPage {
        requestedCursors.append(afterID); onRead?(); await tileWait?()
        if failNextPage { throw APIError.httpStatus(503) }
        return try JSONDecoder().decode(RoamTileMemoryPage.self, from: Data(tileJSON.utf8))
    }
    func shopBadge() async throws -> RoamShopBadge? { nil }
}
@MainActor final class RoamExperienceCoordinatorTests: XCTestCase {
    func testRecoveryDistinguishesActiveIncompleteMissingAndFinished() async {
        let reader = ExperienceReaderDouble()
        let model = RoamRecoveryCoordinator(reader: reader)
        for (json, phase) in [(RoamExperienceSyntheticFixtures.active, RoamRecoveryPhase.active), (RoamExperienceSyntheticFixtures.incomplete, .incomplete), (RoamExperienceSyntheticFixtures.missing, .notFound), (RoamExperienceSyntheticFixtures.settled, .finished)] {
            reader.factJSON = json; await model.recover(.sessionID(901)); XCTAssertEqual(model.phase, phase)
        }
    }
    func testNewerResetDiscardsOldRecoveryResult() async {
        let reader = ExperienceReaderDouble()
        let coordinator = RoamRecoveryCoordinator(reader: reader)
        reader.onRead = { coordinator.reset() }
        await coordinator.recover(.sessionID(901))
        XCTAssertEqual(coordinator.phase, .idle); XCTAssertNil(coordinator.fact)
    }
    func testWrongFactIdentityCannotBecomeSuccess() async {
        let reader = ExperienceReaderDouble()
        let coordinator = RoamRecoveryCoordinator(reader: reader)
        await coordinator.recover(.sessionID(902))
        XCTAssertEqual(coordinator.phase, .failed); XCTAssertNil(coordinator.fact)
    }
    func testAlbumFailureRetainsRowsAndRetriesSamePage() async {
        let reader = ExperienceReaderDouble()
        let model = RoamAlbumPager(reader: reader, pageSize: 2)
        await model.loadNext(); XCTAssertEqual(model.stamps.map(\.id), [1, 2])
        reader.failNextPage = true; await model.loadNext()
        XCTAssertEqual(model.stamps.map(\.id), [1, 2]); XCTAssertTrue(model.hasMore); XCTAssertNotNil(model.error)
        reader.failNextPage = false; await model.loadNext()
        XCTAssertEqual(reader.requestedPages, [1, 2, 2]); XCTAssertEqual(model.stamps.map(\.id), [2, 3]); XCTAssertFalse(model.hasMore)
    }
    func testAlbumIdentityChangeDiscardsOldRowsBeforeNextRead() async {
        let reader = ExperienceReaderDouble()
        let model = RoamAlbumPager(reader: reader, pageSize: 2)
        await model.loadNext(); XCTAssertFalse(model.stamps.isEmpty)
        reader.identity = nil; await model.loadNext()
        XCTAssertTrue(model.stamps.isEmpty); XCTAssertEqual(model.error as? APIError, .unauthorized)
        XCTAssertEqual(reader.requestedPages, [1])
    }
    func testAlbumResetDuringReadDiscardsStaleCompletion() async {
        let reader = ExperienceReaderDouble()
        let model = RoamAlbumPager(reader: reader, pageSize: 2)
        reader.onRead = { model.reset() }
        await model.loadNext()
        XCTAssertTrue(model.stamps.isEmpty); XCTAssertFalse(model.loading); XCTAssertFalse(model.loaded)
    }
    func testAlbumDetailNavigationCancelsWorkWithoutRemovingItsSourceRow() async {
        let reader = ExperienceReaderDouble()
        let model = RoamAlbumPager(reader: reader, pageSize: 2)
        await model.loadNext()
        model.cancelPending()
        XCTAssertEqual(model.stamps.map(\.id), [1, 2]); XCTAssertTrue(model.loaded); XCTAssertFalse(model.loading)
    }
    func testLiveStartNeverCallsDeviceOrNetworkAndConsentDoesNotEnableIt() {
        let model = RoamLiveCoordinator()
        XCTAssertThrowsError(try model.start(purposeAccepted: false))
        XCTAssertEqual(model.phase, .ready)
        XCTAssertThrowsError(try model.start(purposeAccepted: true))
        XCTAssertEqual(model.phase, .unavailable)
    }
}
private final class ExperienceClosureTransport: HTTPTransport {
    let operation: @MainActor (URLRequest) async throws -> (Data, Int)
    init(_ operation: @escaping @MainActor (URLRequest) async throws -> (Data, Int)) { self.operation = operation }
    func send(_ request: URLRequest) async throws -> (Data, Int) { try await operation(request) }
}
@MainActor private final class EmptyExperienceStorage: RoamHistoryDataStoring {
    func read(key: String) throws -> Data? { nil }
    func write(_ data: Data, key: String) throws { XCTFail("Unexpected history write") }
}
@MainActor final class RoamExperienceSessionBoundaryTests: XCTestCase {
    private let url = URL(string: "https://example.com/fixture/")!
    private func session(epoch: UInt64 = 1, token: String = "fixture-token") throws -> RoamExperienceSession {
        try RoamExperienceSession(scope: RoamHistoryScope(market: "cn", deployment: url, accountID: 1), epoch: epoch, token: token)
    }
    func testOldEpochSuccessAnd401CannotEscapeOrExpireReplacement() async throws {
        for status in [200, 401] {
            var current: RoamExperienceSession? = try session()
            let replacement = try session(epoch: 2)
            var expired = 0
            let service = RoamExperienceService(configuration: try APIConfiguration(baseURL: url), transport: ExperienceClosureTransport { _ in
                current = replacement; return (Data("{\"code\":200,\"data\":\(RoamExperienceSyntheticFixtures.settled)}".utf8), status)
            })
            let store = RoamHistoryStore(storage: EmptyExperienceStorage(), currentScope: { current?.identity.scope })
            let reader = RoamExperienceSessionReader(service: service, store: store, currentSession: { current }, onUnauthorized: { _ in expired += 1 })
            do { _ = try await reader.sessionFact(.sessionID(901)); XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
            XCTAssertEqual(expired, 0); XCTAssertEqual(current, replacement)
        }
    }
    func testSameIdentityTokenChangeDropsOldResult() async throws {
        var current: RoamExperienceSession? = try session()
        let replacement = try session(token: "new-fixture-token")
        let service = RoamExperienceService(configuration: try APIConfiguration(baseURL: url), transport: ExperienceClosureTransport { _ in
            current = replacement; return (Data(#"{"code":200,"data":null}"#.utf8), 200)
        })
        let store = RoamHistoryStore(storage: EmptyExperienceStorage(), currentScope: { current?.identity.scope })
        let reader = RoamExperienceSessionReader(service: service, store: store, currentSession: { current })
        do { _ = try await reader.shopBadge(); XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
    }
    func testCurrent401ExpiresOnlyCapturedSession() async throws {
        var current: RoamExperienceSession? = try session()
        let original = try XCTUnwrap(current)
        var expired: [RoamExperienceSession] = []
        let service = RoamExperienceService(configuration: try APIConfiguration(baseURL: url), transport: ExperienceClosureTransport { _ in (Data(), 401) })
        let store = RoamHistoryStore(storage: EmptyExperienceStorage(), currentScope: { current?.identity.scope })
        let reader = RoamExperienceSessionReader(service: service, store: store, currentSession: { current }, onUnauthorized: { expired.append($0); current = nil })
        do { _ = try await reader.shopBadge(); XCTFail() } catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        XCTAssertEqual(expired, [original]); XCTAssertNil(current)
    }
    func testWrongStoreScopeIsNotReadable() throws {
        let current = try session()
        let otherScope = try RoamHistoryScope(market: "us", deployment: url, accountID: 1)
        let store = RoamHistoryStore(storage: EmptyExperienceStorage(), currentScope: { otherScope })
        let reader = RoamExperienceSessionReader(service: nil, store: store, currentSession: { current })
        XCTAssertThrowsError(try reader.history())
    }
    func testDeploymentMismatchSendsNoRequest() async throws {
        let current = try session()
        var count = 0
        let service = RoamExperienceService(configuration: try APIConfiguration(baseURL: URL(string: "https://example.com/other/")!), transport: ExperienceClosureTransport { _ in count += 1; return (Data(), 500) })
        let store = RoamHistoryStore(storage: EmptyExperienceStorage(), currentScope: { current.identity.scope })
        let reader = RoamExperienceSessionReader(service: service, store: store, currentSession: { current })
        do { _ = try await reader.shopBadge(); XCTFail() } catch { XCTAssertEqual(error as? RoamExperienceFailure, .scopeMismatch) }
        XCTAssertEqual(count, 0)
    }
}

@MainActor final class RoamTileMemoryPagerTests: XCTestCase {
    func testUnionRetrySameCursorAndExplicitRefreshForOtherDevice() async {
        let reader = ExperienceReaderDouble(), pager: RoamTileMemoryPager
        pager = RoamTileMemoryPager(reader: reader)
        reader.tileJSON = #"{"tiles":["s00twy0"],"nextAfterId":1,"hasMore":true}"#
        await pager.loadNext()
        reader.failNextPage = true; await pager.loadNext()
        XCTAssertEqual(pager.tiles, ["s00twy0"]); XCTAssertNotNil(pager.error)
        reader.failNextPage = false
        reader.tileJSON = #"{"tiles":["s00twy0","s00twy1"],"nextAfterId":3,"hasMore":false}"#
        await pager.loadNext(); await pager.loadNext()
        XCTAssertEqual(reader.requestedCursors, [0, 1, 1]); XCTAssertEqual(pager.tiles.count, 2)
        XCTAssertFalse(pager.hasMore); XCTAssertNil(pager.error)
        pager.reset(); await pager.loadNext()
        XCTAssertEqual(reader.requestedCursors, [0, 1, 1, 0]); XCTAssertEqual(pager.tiles.count, 2)
    }
    func testCancelThenRetryDiscardsLatePageWithoutLosingEarlierUnion() async {
        let reader = ExperienceReaderDouble(), pager: RoamTileMemoryPager
        pager = RoamTileMemoryPager(reader: reader)
        reader.tileJSON = #"{"tiles":["s00twy0"],"nextAfterId":1,"hasMore":true}"#
        await pager.loadNext()
        reader.onRead = { pager.cancelPending() }
        reader.tileJSON = #"{"tiles":["s00twy1"],"nextAfterId":2,"hasMore":false}"#
        await pager.loadNext()
        XCTAssertEqual(pager.tiles, ["s00twy0"]); XCTAssertFalse(pager.loading)
        reader.onRead = nil; await pager.loadNext()
        XCTAssertEqual(reader.requestedCursors, [0, 1, 1]); XCTAssertEqual(pager.tiles.count, 2)
    }
    func testIdentityChangesRemoveEarlierAndLatePrivateTiles() async {
        let reader = ExperienceReaderDouble(), pager: RoamTileMemoryPager
        pager = RoamTileMemoryPager(reader: reader)
        reader.tileJSON = #"{"tiles":["s00twy0"],"nextAfterId":1,"hasMore":true}"#
        await pager.loadNext()
        reader.onRead = { reader.identity = nil }; await pager.loadNext()
        XCTAssertTrue(pager.tiles.isEmpty); XCTAssertFalse(pager.loaded); XCTAssertFalse(pager.loading)
        reader.onRead = nil; await pager.loadNext()
        XCTAssertEqual(pager.error as? APIError, .unauthorized)
        XCTAssertEqual(reader.requestedCursors, [0, 1])
    }
    func testNonAdvancingCursorRejectedAndSameCursorRetried() async {
        let reader = ExperienceReaderDouble(), pager: RoamTileMemoryPager
        pager = RoamTileMemoryPager(reader: reader)
        reader.tileJSON = #"{"tiles":["s00twy0"],"nextAfterId":0,"hasMore":true}"#
        await pager.loadNext(); await pager.loadNext()
        XCTAssertTrue(pager.tiles.isEmpty); XCTAssertFalse(pager.loaded)
        XCTAssertEqual(pager.error as? APIError, .malformedResponse)
        XCTAssertEqual(reader.requestedCursors, [0, 0])
    }
    func testUnconfiguredAndSignedOutReadersNeverDispatch() async {
        let reader = ExperienceReaderDouble(), pager: RoamTileMemoryPager
        pager = RoamTileMemoryPager(reader: reader)
        reader.isConfigured = false; await pager.loadNext()
        XCTAssertEqual(pager.error as? APIError, .notConfigured)
        reader.identity = nil; await pager.loadNext()
        XCTAssertEqual(pager.error as? APIError, .unauthorized); XCTAssertTrue(reader.requestedCursors.isEmpty)
    }
    func testRepeatedTapDoesNotDispatchWhileFirstPageIsPending() async {
        let reader = ExperienceReaderDouble(), pager: RoamTileMemoryPager
        pager = RoamTileMemoryPager(reader: reader)
        var pending: CheckedContinuation<Void, Never>?
        reader.tileWait = { await withCheckedContinuation { pending = $0 } }
        let task = Task { await pager.loadNext() }
        while pending == nil { await Task.yield() }
        await pager.loadNext(); XCTAssertEqual(reader.requestedCursors, [0])
        pending?.resume(); await task.value
        XCTAssertEqual(pager.tiles.count, 2); XCTAssertFalse(pager.loading)
    }
}

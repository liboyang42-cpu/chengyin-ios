import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Current authorization failures and transient failures take different paths through
/// the original service/session reader/pager. No real HTTP or local storage is touched.
@MainActor final class RoamAlbumDenialRecoveryTests: XCTestCase {
    func testCurrentHTTPAndBusiness403ClearRowsTotalAndPaginationWithoutEmptySuccess() async throws {
        for result in [(403, 200), (200, 403)] {
            let r = try AlbumDenialRig(); await r.pager.loadNext()
            XCTAssertEqual(r.pager.stamps.map(\.id), [1]); XCTAssertEqual(r.pager.total, 40)
            r.wire.status = result.0; r.wire.code = result.1
            await r.pager.loadNext()
            XCTAssertEqual(CollectionReadAccess(try XCTUnwrap(r.pager.error)), .denied)
            assertCleared(r.pager)
            await r.pager.loadNext(); XCTAssertEqual(r.wire.pages, [1, 2])
        }
    }

    func testCurrentHTTPAndBusiness401UseLoginStateAndDoNotRetainPrivateRows() async throws {
        for result in [(401, 200), (200, 401)] {
            let r = try AlbumDenialRig(); await r.pager.loadNext()
            r.wire.status = result.0; r.wire.code = result.1
            await r.pager.loadNext()
            XCTAssertEqual(r.pager.error as? APIError, .unauthorized)
            XCTAssertEqual(r.unauthorized, 1); assertCleared(r.pager)
            await r.pager.loadNext(); XCTAssertEqual(r.wire.pages, [1, 2])
        }
    }

    func testExplicitRefreshAfterDenialReadsPageOneAndDoesNotResurrectCachedRows() async throws {
        let r = try AlbumDenialRig(); await r.pager.loadNext()
        r.wire.status = 403; await r.pager.loadNext(); assertCleared(r.pager)
        r.wire.status = 200; r.wire.stampOffset = 100
        // Merely restoring the server response does not restart paging automatically.
        await r.pager.loadNext(); XCTAssertEqual(r.wire.pages, [1, 2])
        r.pager.reset(); await r.pager.loadNext()
        XCTAssertEqual(r.wire.pages, [1, 2, 1]); XCTAssertEqual(r.pager.stamps.map(\.id), [101])
        XCTAssertTrue(r.pager.loaded); XCTAssertTrue(r.pager.hasMore); XCTAssertNil(r.pager.error)
        await r.pager.loadNext()
        XCTAssertEqual(r.wire.pages, [1, 2, 1, 2]); XCTAssertEqual(r.pager.stamps.map(\.id), [101, 102])
        XCTAssertFalse(r.pager.hasMore)
    }

    func testTransientHTTPFailureEvenWith403BodyRetainsRowsAndSamePageRetry() async throws {
        for status in [408, 429, 500, 503] {
            let r = try AlbumDenialRig(); await r.pager.loadNext()
            r.wire.status = status; r.wire.code = 403
            await r.pager.loadNext()
            XCTAssertEqual(r.pager.error as? APIError, .httpStatus(status))
            XCTAssertEqual(r.pager.stamps.map(\.id), [1]); XCTAssertEqual(r.pager.total, 40)
            XCTAssertTrue(r.pager.loaded); XCTAssertTrue(r.pager.hasMore)
            r.wire.status = 200; r.wire.code = 200; await r.pager.loadNext()
            XCTAssertEqual(r.wire.pages, [1, 2, 2]); XCTAssertEqual(r.pager.stamps.map(\.id), [1, 2])
            XCTAssertNil(r.pager.error)
        }
    }

    func testMalformedOrOfflineContinuationPreservesOriginalPageForRetry() async throws {
        for malformed in [false, true] {
            let r = try AlbumDenialRig(); await r.pager.loadNext()
            if malformed { r.wire.malformed = true } else { r.wire.failure = URLError(.notConnectedToInternet) }
            await r.pager.loadNext()
            XCTAssertNotNil(r.pager.error); XCTAssertEqual(r.pager.stamps.map(\.id), [1])
            XCTAssertTrue(r.pager.hasMore); XCTAssertEqual(r.pager.total, 40)
            r.wire.malformed = false; r.wire.failure = nil; await r.pager.loadNext()
            XCTAssertEqual(r.wire.pages, [1, 2, 2]); XCTAssertEqual(r.pager.stamps.map(\.id), [1, 2])
        }
    }

    func testCancelledOld403CannotClearLaterRefreshedPage() async throws {
        let r = try AlbumDenialRig(); await r.pager.loadNext()
        r.wire.hold = true
        let held = expectation(description: "Old continuation held")
        r.wire.onHeld = { held.fulfill() }
        let old = Task { await r.pager.loadNext() }
        await fulfillment(of: [held], timeout: 2)
        r.pager.cancelPending(); r.pager.reset(); r.wire.hold = false; r.wire.stampOffset = 100
        await r.pager.loadNext()
        r.wire.completeHeld(status: 403, code: 403); await old.value
        XCTAssertEqual(r.pager.stamps.map(\.id), [101]); XCTAssertEqual(r.pager.total, 40)
        XCTAssertTrue(r.pager.loaded); XCTAssertTrue(r.pager.hasMore); XCTAssertNil(r.pager.error)
        XCTAssertEqual(r.wire.pages, [1, 2, 1])
    }

    func testNewAccountStartsAtPageOneAfterOldDeniedPagination() async throws {
        let r = try AlbumDenialRig(); await r.pager.loadNext()
        r.wire.status = 403; await r.pager.loadNext(); assertCleared(r.pager)
        r.session = try AlbumDenialRig.session(account: 8, epoch: 2)
        r.wire.status = 200; r.wire.stampOffset = 100
        await r.pager.loadNext()
        XCTAssertEqual(r.wire.pages, [1, 2, 1]); XCTAssertEqual(r.pager.stamps.map(\.id), [101])
        XCTAssertNil(r.pager.error)
    }

    func testFirstPageDenialIsNotEmptyAlbumAndPreservesExactError() async throws {
        let r = try AlbumDenialRig(); r.wire.status = 403
        await r.pager.loadNext(); assertCleared(r.pager)
        XCTAssertEqual(r.pager.error as? APIError, .httpStatus(403))
        await r.pager.loadNext(); XCTAssertEqual(r.wire.pages, [1])
        r.pager.reset(); r.wire.status = 200; r.wire.empty = true; await r.pager.loadNext()
        XCTAssertTrue(r.pager.loaded); XCTAssertEqual(r.pager.total, 0)
        XCTAssertTrue(r.pager.stamps.isEmpty); XCTAssertFalse(r.pager.hasMore); XCTAssertNil(r.pager.error)
    }

    private func assertCleared(_ pager: RoamAlbumPager, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(pager.stamps.isEmpty, file: file, line: line)
        XCTAssertNil(pager.total, file: file, line: line)
        XCTAssertFalse(pager.loaded, file: file, line: line)
        XCTAssertFalse(pager.loading, file: file, line: line)
        XCTAssertFalse(pager.hasMore, file: file, line: line)
    }
}

@MainActor private final class AlbumDenialRig {
    var session: RoamExperienceSession?
    var unauthorized = 0
    let wire = AlbumDenialWire()
    private(set) var reader: RoamExperienceSessionReader!
    private(set) var pager: RoamAlbumPager!
    init() throws {
        session = try Self.session()
        let store = RoamHistoryStore(storage: AlbumDenialNoStorage(), currentScope: { [weak self] in self?.session?.identity.scope })
        let service = RoamExperienceService(configuration: try .init(baseURL: Self.base), transport: wire)
        reader = .init(service: service, store: store, currentSession: { [weak self] in self?.session },
                       onUnauthorized: { [weak self] _ in self?.unauthorized += 1 })
        pager = .init(reader: reader)
    }
    static let base = URL(string: "https://example.test/album-denial")!
    static func session(account: Int = 7, epoch: UInt64 = 1) throws -> RoamExperienceSession {
        try .init(scope: .init(market: "cn", deployment: base, accountID: account, namespace: "album-denial"),
                  epoch: epoch, token: "synthetic-album-denial")
    }
}
@MainActor private final class AlbumDenialNoStorage: RoamHistoryDataStoring {
    func read(key: String) throws -> Data? { XCTFail("Album read must not read local history"); return nil }
    func write(_ data: Data, key: String) throws { XCTFail("Album read must not write history") }
}
@MainActor private final class AlbumDenialWire: HTTPTransport {
    var pages: [Int] = []
    var status = 200, code = 200, stampOffset = 0
    var malformed = false, empty = false, hold = false
    var failure: Error?
    var onHeld: (() -> Void)?
    private var pending: CheckedContinuation<(Data, Int), Error>?
    func completeHeld(status: Int, code: Int) {
        let value = pending; pending = nil
        value?.resume(returning: (Data("{\"code\":\(code)}".utf8), status))
    }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let route = try XCTUnwrap(RoamAlbumMetadataReadRoute(request: request, baseURL: AlbumDenialRig.base))
        pages.append(route.page)
        if hold { return try await withCheckedThrowingContinuation { pending = $0; onHeld?() } }
        if let failure { throw failure }
        if status != 200 || code != 200 { return (Data("{\"code\":\(code)}".utf8), status) }
        if malformed { return (Data(#"{"code":200,"data":{}}"#.utf8), 200) }
        let rows: [[String: Any]] = empty ? [] : [["id": route.page + stampOffset, "checkState": 0, "caption": "Synthetic metadata"]]
        let body: [String: Any] = ["code": 200, "data": ["list": rows, "total": empty ? 0 : 40, "pageNum": route.page, "pageSize": route.pageSize]]
        return (try JSONSerialization.data(withJSONObject: body), 200)
    }
}

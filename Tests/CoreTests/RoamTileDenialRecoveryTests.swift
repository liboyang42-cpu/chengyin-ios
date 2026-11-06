import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// The real owner-only reader, service and pager use only an in-memory GET transport.
/// No location, history storage, geometry projection or reveal writer is constructed.
@MainActor final class RoamTileDenialRecoveryTests: XCTestCase {
    func testCurrentHTTPAndBusiness403ClearPrivateTilesAndStopOldContinuation() async throws {
        for result in [(403, 200), (200, 403)] {
            let r = try TileDenialRig(); await r.pager.loadNext()
            XCTAssertEqual(r.pager.tiles, ["wx4g0ec"]); XCTAssertTrue(r.pager.loaded)
            r.wire.status = result.0; r.wire.code = result.1
            await r.pager.loadNext()
            XCTAssertEqual(CollectionReadAccess(try XCTUnwrap(r.pager.error)), .denied)
            assertCleared(r.pager)
            await r.pager.loadNext(); XCTAssertEqual(r.wire.cursors, [0, 5])
            XCTAssertFalse(r.access.isRevoked); XCTAssertTrue(r.reader.isConfigured)
        }
    }

    func testCurrent401ClearsTilesWhetherOriginalUnauthorizedCallbackKeepsOrClearsIdentity() async throws {
        for clearsIdentity in [false, true] {
            for result in [(401, 200), (200, 401)] {
                let r = try TileDenialRig(); await r.pager.loadNext()
                r.clearOnUnauthorized = clearsIdentity
                r.wire.status = result.0; r.wire.code = result.1
                await r.pager.loadNext()
                XCTAssertTrue(r.pager.tiles.isEmpty); XCTAssertFalse(r.pager.loaded)
                XCTAssertFalse(r.pager.loading); XCTAssertEqual(r.unauthorized, 1)
                if clearsIdentity {
                    // The pre-existing identity-change branch resets before recording an error.
                    XCTAssertNil(r.reader.identity); XCTAssertNil(r.pager.error)
                } else {
                    XCTAssertEqual(r.pager.error as? APIError, .unauthorized)
                    XCTAssertFalse(r.pager.hasMore)
                }
                XCTAssertEqual(r.wire.cursors, [0, 5])
            }
        }
    }

    func testExplicitRefreshAfterDenialRestartsAtZeroWithoutResurrectingOldTiles() async throws {
        let r = try TileDenialRig(); await r.pager.loadNext()
        r.wire.status = 403; await r.pager.loadNext(); assertCleared(r.pager)
        r.wire.status = 200; r.wire.replacement = true
        await r.pager.loadNext(); XCTAssertEqual(r.wire.cursors, [0, 5])
        r.pager.reset(); await r.pager.loadNext()
        XCTAssertEqual(r.wire.cursors, [0, 5, 0]); XCTAssertEqual(r.pager.tiles, ["wx4g0ef"])
        XCTAssertTrue(r.pager.loaded); XCTAssertTrue(r.pager.hasMore); XCTAssertNil(r.pager.error)
        await r.pager.loadNext()
        XCTAssertEqual(r.wire.cursors, [0, 5, 0, 5]); XCTAssertEqual(r.pager.tiles, ["wx4g0ef", "wx4g0eg"])
        XCTAssertFalse(r.pager.hasMore)
    }

    func testTransientHTTPFailureWith403BodyRetainsTilesAndOriginalCursorRetry() async throws {
        for status in [408, 429, 500, 503] {
            let r = try TileDenialRig(); await r.pager.loadNext()
            r.wire.status = status; r.wire.code = 403; await r.pager.loadNext()
            XCTAssertEqual(r.pager.error as? APIError, .httpStatus(status))
            XCTAssertEqual(r.pager.tiles, ["wx4g0ec"]); XCTAssertTrue(r.pager.loaded)
            XCTAssertTrue(r.pager.hasMore)
            r.wire.status = 200; r.wire.code = 200; await r.pager.loadNext()
            XCTAssertEqual(r.wire.cursors, [0, 5, 5]); XCTAssertEqual(r.pager.tiles, ["wx4g0ec", "wx4g0ed"])
            XCTAssertNil(r.pager.error); XCTAssertFalse(r.pager.hasMore)
        }
    }

    func testMalformedAndOfflineResponsesDoNotDiscardPriorTilesOrAdvanceCursor() async throws {
        for malformed in [false, true] {
            let r = try TileDenialRig(); await r.pager.loadNext()
            if malformed { r.wire.malformed = true } else { r.wire.failure = URLError(.notConnectedToInternet) }
            await r.pager.loadNext()
            XCTAssertNotNil(r.pager.error); XCTAssertEqual(r.pager.tiles, ["wx4g0ec"])
            XCTAssertTrue(r.pager.loaded); XCTAssertTrue(r.pager.hasMore)
            r.wire.malformed = false; r.wire.failure = nil; await r.pager.loadNext()
            XCTAssertEqual(r.wire.cursors, [0, 5, 5]); XCTAssertEqual(r.pager.tiles, ["wx4g0ec", "wx4g0ed"])
        }
    }

    func testRetiredOld403CannotClearARefreshedCurrentPage() async throws {
        let r = try TileDenialRig(); await r.pager.loadNext()
        r.wire.hold = true
        let held = expectation(description: "Old cursor continuation")
        r.wire.onHeld = { held.fulfill() }
        let old = Task { await r.pager.loadNext() }
        await fulfillment(of: [held], timeout: 2)
        r.pager.cancelPending(); r.pager.reset(); r.wire.hold = false; r.wire.replacement = true
        await r.pager.loadNext()
        r.wire.completeHeld(status: 403, code: 403); await old.value
        XCTAssertEqual(r.pager.tiles, ["wx4g0ef"]); XCTAssertTrue(r.pager.loaded)
        XCTAssertTrue(r.pager.hasMore); XCTAssertNil(r.pager.error)
        XCTAssertEqual(r.wire.cursors, [0, 5, 0])
    }

    func testOriginalReaderRejectsLateDeniedResultAfterAccountChangeAndFreshReadStartsAtZero() async throws {
        let r = try TileDenialRig(); await r.pager.loadNext()
        r.wire.hold = true
        let held = expectation(description: "Old owner read")
        r.wire.onHeld = { held.fulfill() }
        let old = Task { await r.pager.loadNext() }
        await fulfillment(of: [held], timeout: 2)
        r.context = try TileDenialRig.context(account: 8, epoch: 2)
        r.access = try TileDenialRig.access(try XCTUnwrap(r.context))
        r.viewerRevision += 1
        r.wire.completeHeld(status: 403, code: 403); await old.value
        XCTAssertTrue(r.pager.tiles.isEmpty); XCTAssertFalse(r.pager.loaded)
        XCTAssertNil(r.pager.error); XCTAssertEqual(r.unauthorized, 0)
        r.wire.hold = false; r.wire.replacement = true; await r.pager.loadNext()
        XCTAssertEqual(r.wire.cursors, [0, 5, 0]); XCTAssertEqual(r.pager.tiles, ["wx4g0ef"])
        XCTAssertNil(r.pager.error)
    }

    func testFirstReadDenialIsNotAnEmptySuccessAndExplicitRefreshCanReadActualEmptyPage() async throws {
        let r = try TileDenialRig(); r.wire.status = 403
        await r.pager.loadNext(); assertCleared(r.pager)
        XCTAssertEqual(r.pager.error as? APIError, .httpStatus(403))
        await r.pager.loadNext(); XCTAssertEqual(r.wire.cursors, [0])
        r.pager.reset(); r.wire.status = 200; r.wire.empty = true; await r.pager.loadNext()
        XCTAssertTrue(r.pager.loaded); XCTAssertTrue(r.pager.tiles.isEmpty)
        XCTAssertFalse(r.pager.hasMore); XCTAssertNil(r.pager.error)
        XCTAssertEqual(r.wire.cursors, [0, 0])
    }

    private func assertCleared(_ pager: RoamTileMemoryPager, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(pager.tiles.isEmpty, file: file, line: line)
        XCTAssertFalse(pager.loaded, file: file, line: line)
        XCTAssertFalse(pager.loading, file: file, line: line)
        XCTAssertFalse(pager.hasMore, file: file, line: line)
    }
}

@MainActor private final class TileDenialRig {
    var context: RuntimeDependencyContext?
    var access: RoamTileMemoryReadAccess
    var viewerRevision: UInt64 = 1
    var unauthorized = 0, clearOnUnauthorized = false
    let wire = TileDenialWire()
    private(set) var reader: RoamTileMemoryReader!
    private(set) var pager: RoamTileMemoryPager!
    init() throws {
        let context = try Self.context(); self.context = context; access = try Self.access(context)
        reader = .init(service: .init(configuration: try .init(baseURL: Self.base), transport: wire),
            current: { [weak self] in self?.context }, viewerRevision: { [weak self] in self?.viewerRevision ?? 0 },
            access: { [weak self] _ in self?.access }, onUnauthorized: { [weak self] _ in
                self?.unauthorized += 1
                if self?.clearOnUnauthorized == true { self?.context = nil }
            })
        pager = .init(reader: reader)
    }
    static let base = URL(string: "https://example.test/tile-denial")!
    static func context(account: Int = 7, epoch: UInt64 = 1) throws -> RuntimeDependencyContext {
        .init(market: .china, baseURL: base, role: "player",
              session: try .init(accountID: account, epoch: epoch, namespace: "tile-denial", token: "synthetic-tile-denial"))
    }
    static func access(_ context: RuntimeDependencyContext) throws -> RoamTileMemoryReadAccess {
        try .init(context: context, approval: .init(baseURL: context.baseURL, namespace: context.session.namespace,
            accountID: context.session.accountID, paths: [RoamTileMemoryReadRoute.path]))
    }
}
@MainActor private final class TileDenialWire: HTTPTransport {
    var cursors: [Int] = []
    var status = 200, code = 200
    var malformed = false, empty = false, hold = false, replacement = false
    var failure: Error?, onHeld: (() -> Void)?
    private var pending: CheckedContinuation<(Data, Int), Error>?
    func completeHeld(status: Int, code: Int) {
        let value = pending; pending = nil
        value?.resume(returning: (Data("{\"code\":\(code)}".utf8), status))
    }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        let route = try XCTUnwrap(RoamTileMemoryReadRoute(request: request, baseURL: TileDenialRig.base))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic-tile-denial")
        XCTAssertEqual(route.limit, 1000); cursors.append(route.afterID)
        if hold { return try await withCheckedThrowingContinuation { pending = $0; onHeld?() } }
        if let failure { throw failure }
        if status != 200 || code != 200 { return (Data("{\"code\":\(code)}".utf8), status) }
        if malformed { return (Data(#"{"code":200,"data":{}}"#.utf8), 200) }
        let tiles: [String] = empty ? [] : (route.afterID == 0 ? [replacement ? "wx4g0ef" : "wx4g0ec"] :
            (replacement ? ["wx4g0ef", "wx4g0eg"] : ["wx4g0ec", "wx4g0ed"]))
        let body: [String: Any] = ["code": 200, "data": ["tiles": tiles,
            "nextAfterId": empty ? route.afterID : (route.afterID == 0 ? 5 : 7), "hasMore": !empty && route.afterID == 0]]
        return (try JSONSerialization.data(withJSONObject: body), 200)
    }
}

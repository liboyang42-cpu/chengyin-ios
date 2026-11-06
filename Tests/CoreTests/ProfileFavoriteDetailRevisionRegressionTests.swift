import XCTest
import Observation
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Independent regression fixtures. Existing favorite tests and their historical ACK
/// assertions are deliberately untouched; this suite concerns only read projection.
@MainActor final class ProfileFavoriteDetailRevisionRegressionTests: XCTestCase {
    @MainActor @Observable private final class Context {
        var current: RuntimeDependencyContext?
        var viewer: UInt64 = 1
        var access: ProfileFavoriteDetailAccess?
        var unauthorized = 0
    }
    @MainActor private final class Wire: HTTPTransport {
        var requests: [URLRequest] = []
        var held: [Int: CheckedContinuation<(Data, Int), Error>] = [:]
        var holdDetails = false
        var detailNumber = 0
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            switch request.url?.path {
            case let path? where path.hasSuffix("/creativesquare/list"):
                return (Data(#"{"code":200,"data":{"rows":[{"id":101,"memberId":91,"contents":"Saved"}]}}"#.utf8), 200)
            case let path? where path.hasSuffix("/creativesquare/info"):
                detailNumber += 1
                let number = detailNumber
                if holdDetails { return try await withCheckedThrowingContinuation { held[number] = $0 } }
                return Self.detail(number)
            case let path? where path.hasSuffix("/comment/list"):
                return (Data(#"{"code":200,"data":{"rows":[]}}"#.utf8), 200)
            default: throw APIError.invalidRequest
            }
        }
        static func detail(_ number: Int) -> (Data, Int) {
            (Data("{\"code\":200,\"data\":{\"id\":101,\"memberId\":91,\"contents\":\"Revision \(number)\"}}".utf8), 200)
        }
        func finish(_ number: Int, status: Int = 200) {
            let continuation = held.removeValue(forKey: number)
            if status == 200 { continuation?.resume(returning: Self.detail(number)) }
            else { continuation?.resume(returning: (Data("{\"code\":\(status)}".utf8), status)) }
        }
        func abortHeld() {
            let values = Array(held.values); held.removeAll()
            for value in values { value.resume(throwing: CancellationError()) }
        }
        var comments: Int { requests.filter { $0.url?.path.hasSuffix("/comment/list") == true }.count }
    }
    @MainActor private struct Fixture {
        let context: Context, wire: Wire, lists: ProfileFavoritesReader
        let selection: ProfileFavoritePostSelection, reader: ProfileFavoriteDetailReader
        func replace() throws {
            let current = try XCTUnwrap(context.current)
            context.access = try .init(context: current, approval: .init(baseURL: current.baseURL,
                namespace: current.session.namespace, accountID: current.session.accountID,
                paths: ProfileFavoriteDetailRoute.paths))
        }
    }
    private func fixture() async throws -> Fixture {
        let context = Context(), wire = Wire()
        let runtime = RuntimeDependencyContext(market: .china, baseURL: URL(string: "https://favorite-revision.example/native")!, role: "player",
            session: try .init(accountID: 7, epoch: 1, namespace: "synthetic", token: "synthetic-token", role: "player"))
        context.current = runtime
        let config = try APIConfiguration(baseURL: runtime.baseURL)
        let listAccess = try ProfileFavoritesReadAccess(context: runtime, approval: .init(baseURL: runtime.baseURL,
            namespace: runtime.session.namespace, accountID: 7, paths: ProfileFavoritesReadRoute.paths))
        let lists = ProfileFavoritesReader(service: .init(configuration: config, transport: wire),
            current: { context.current }, viewerRevision: { context.viewer }, access: { _ in listAccess })
        _ = try await lists.favoritePosts(pageNumber: 1, pageSize: 10)
        let selected = try XCTUnwrap(lists.selectPost(.init(id: 101, generation: .legacySquare), renderedScope: lists.scope))
        let reader = ProfileFavoriteDetailReader(selection: selected, service: .init(configuration: config, transport: wire),
            current: { context.current }, viewerRevision: { context.viewer }, access: { _ in context.access },
            onUnauthorized: { _ in context.unauthorized += 1 })
        let result = Fixture(context: context, wire: wire, lists: lists, selection: selected, reader: reader)
        try result.replace()
        return result
    }
    private func waitHeld(_ wire: Wire, _ number: Int) async throws {
        for _ in 0..<1000 where wire.held[number] == nil { await Task.yield() }
        _ = try XCTUnwrap(wire.held[number], "Expected the independent detail attempt to dispatch")
    }
    func testValidReplacementChangesProjectionScopeAndWithdrawsOldConfirmation() async throws {
        let f = try await fixture()
        let first = f.reader.scope
        XCTAssertEqual(first, f.reader.scope)
        _ = try await f.reader.squareDetail(route: f.selection.route)
        XCTAssertTrue(f.reader.confirmsCurrentDetail)
        try f.replace()
        XCTAssertTrue(f.reader.isConfigured); XCTAssertTrue(f.selection.isCurrent)
        XCTAssertNotEqual(first, f.reader.scope)
        XCTAssertFalse(f.reader.confirmsCurrentDetail)
        let post = try await f.reader.squareDetail(route: f.selection.route)
        XCTAssertEqual(post.contents, "Revision 2")
        _ = try await f.reader.squareComments(route: f.selection.route, pageNumber: 1)
        XCTAssertTrue(f.reader.confirmsCurrentDetail); XCTAssertEqual(f.wire.comments, 1)
    }
    func testScopeReadObservesReplacementWithoutManualReaderMutation() async throws {
        let f = try await fixture()
        let changed = expectation(description: "Published selector replacement invalidates the loaded scope")
        let before = withObservationTracking { f.reader.scope } onChange: { changed.fulfill() }
        try f.replace()
        await fulfillment(of: [changed], timeout: 2)
        XCTAssertNotEqual(before, f.reader.scope)
    }
    func testRevocationChangesScopeAndBlocksBothReadsWithoutRequests() async throws {
        let f = try await fixture(); _ = try await f.reader.squareDetail(route: f.selection.route)
        let before = f.reader.scope, requests = f.wire.requests.count
        let changed = expectation(description: "Revocation publishes the private projection change")
        _ = withObservationTracking { f.reader.scope } onChange: { changed.fulfill() }
        f.context.access?.revoke()
        await fulfillment(of: [changed], timeout: 2)
        XCTAssertNotEqual(before, f.reader.scope); XCTAssertEqual(f.reader.scope, f.reader.scope)
        XCTAssertFalse(f.reader.isConfigured); XCTAssertFalse(f.reader.confirmsCurrentDetail)
        do { _ = try await f.reader.squareDetail(route: f.selection.route); XCTFail() } catch {}
        do { _ = try await f.reader.squareComments(route: f.selection.route, pageNumber: 1); XCTFail() } catch {}
        XCTAssertEqual(f.wire.requests.count, requests)
    }
    func testNewRevisionNeverJoinsOldTaskAndLateSuccessCannotEraseCompletedNewRead() async throws {
        try await assertLateOldResult(status: 200)
    }
    func testNewRevisionNeverJoinsOldTaskAndLateUnauthorizedCannotEraseOrExpireNewRead() async throws {
        try await assertLateOldResult(status: 401)
    }
    private func assertLateOldResult(status: Int) async throws {
        let f = try await fixture(); defer { f.wire.abortHeld() }; f.wire.holdDetails = true
        let old = Task { try await f.reader.squareDetail(route: f.selection.route) }
        try await waitHeld(f.wire, 1)
        try f.replace()
        let next = Task { try await f.reader.squareDetail(route: f.selection.route) }
        // B starts while A remains suspended; a replaced approval cannot lend its task.
        try await waitHeld(f.wire, 2)
        XCTAssertFalse(f.reader.confirmsCurrentDetail)
        f.wire.finish(2)
        let post = try await next.value
        XCTAssertEqual(post.contents, "Revision 2"); XCTAssertTrue(f.reader.confirmsCurrentDetail)
        f.wire.finish(1, status: status)
        do { _ = try await old.value; XCTFail("Retired access returned a detail") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(f.reader.confirmsCurrentDetail)
        XCTAssertEqual(f.context.unauthorized, 0); XCTAssertEqual(f.wire.detailNumber, 2)
        _ = try await f.reader.squareComments(route: f.selection.route, pageNumber: 1)
        XCTAssertEqual(f.wire.detailNumber, 2); XCTAssertEqual(f.wire.comments, 1)
    }
    func testOldFailureWhileNewReadIsPendingCannotDropNewCoalescingTask() async throws {
        let f = try await fixture(); defer { f.wire.abortHeld() }; f.wire.holdDetails = true
        let old = Task { try await f.reader.squareDetail(route: f.selection.route) }
        try await waitHeld(f.wire, 1); try f.replace()
        let next = Task { try await f.reader.squareDetail(route: f.selection.route) }
        try await waitHeld(f.wire, 2)
        f.wire.finish(1, status: 401)
        do { _ = try await old.value; XCTFail() } catch {}
        let comments = Task { try await f.reader.squareComments(route: f.selection.route, pageNumber: 1) }
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(f.wire.detailNumber, 2); XCTAssertEqual(f.wire.comments, 0)
        f.wire.finish(2); _ = try await next.value; _ = try await comments.value
        XCTAssertTrue(f.reader.confirmsCurrentDetail); XCTAssertEqual(f.wire.comments, 1)
        XCTAssertEqual(f.context.unauthorized, 0)
    }
    func testSameRevisionStillCoalescesDetailAndComments() async throws {
        let f = try await fixture(); defer { f.wire.abortHeld() }; f.wire.holdDetails = true
        let detail = Task { try await f.reader.squareDetail(route: f.selection.route) }
        try await waitHeld(f.wire, 1)
        let comments = Task { try await f.reader.squareComments(route: f.selection.route, pageNumber: 1) }
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(f.wire.detailNumber, 1); XCTAssertEqual(f.wire.comments, 0)
        f.wire.finish(1); _ = try await detail.value; _ = try await comments.value
        XCTAssertTrue(f.reader.confirmsCurrentDetail); XCTAssertEqual(f.wire.comments, 1)
    }
    func testReturnPageOneRefreshRetiresOldDetailWithoutBorrowingCurrentList() async throws {
        let f = try await fixture(); _ = try await f.reader.squareDetail(route: f.selection.route)
        let before = f.reader.scope
        _ = try await f.lists.favoritePosts(pageNumber: 1, pageSize: 10)
        XCTAssertFalse(f.selection.isCurrent); XCTAssertNotEqual(before, f.reader.scope)
        let requests = f.wire.requests.count
        do { _ = try await f.reader.squareDetail(route: f.selection.route); XCTFail() } catch {}
        do { _ = try await f.reader.squareComments(route: f.selection.route, pageNumber: 1); XCTFail() } catch {}
        XCTAssertEqual(f.wire.requests.count, requests)
    }
    func testViewerChangeAndLogoutHideProjectionAndRejectLateUnauthorized() async throws {
        for logout in [false, true] {
            let f = try await fixture(); defer { f.wire.abortHeld() }; let before = f.reader.scope; f.wire.holdDetails = true
            let task = Task { try await f.reader.squareDetail(route: f.selection.route) }
            try await waitHeld(f.wire, 1)
            if logout { f.context.current = nil } else { f.context.viewer += 1 }
            XCTAssertNotEqual(before, f.reader.scope); XCTAssertFalse(f.reader.confirmsCurrentDetail)
            f.wire.finish(1, status: 401)
            do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
            XCTAssertEqual(f.context.unauthorized, 0); XCTAssertEqual(f.wire.comments, 0)
        }
    }
}

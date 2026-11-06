import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import QuestifyCore

/// In-memory original received reads. No account, image, database or business writer is exercised.
@MainActor final class RoamReceivedStampMetadataScopeTests: XCTestCase {
    func testScopeIsStableButChangesForEveryOriginalOwnerAndGrantBoundary() throws {
        for change in ["replace", "revoke", "remove", "viewer", "account", "epoch", "token", "namespace", "role", "base", "logout"] {
            let r = try Rig(), before = r.reader.scope
            XCTAssertEqual(before, r.reader.scope)
            try r.change(change)
            XCTAssertNotEqual(before, r.reader.scope, change)
            XCTAssertEqual(r.reader.scope, r.reader.scope, change)
        }
    }
    func testRevokedLeaseNeverRevivesWhenSameAccountGetsNewGrant() throws {
        let r = try Rig(), first = r.reader.scope
        r.grant?.revoke(); let revoked = r.reader.scope
        r.grant = try Rig.grant(try XCTUnwrap(r.current))
        XCTAssertNotEqual(first, revoked); XCTAssertNotEqual(first, r.reader.scope)
        XCTAssertTrue(r.reader.isConfigured)
    }
    func testDefaultNilAndWrongDeploymentDoNotDispatch() async throws {
        for denied in ["nil", "base"] {
            let r = try Rig()
            if denied == "nil" { r.grant = nil } else { try r.change("base") }
            XCTAssertFalse(r.reader.isConfigured)
            do { _ = try await r.reader.album(page: 1, pageSize: 20); XCTFail() }
            catch { XCTAssertEqual(error as? APIError, .notConfigured) }
            XCTAssertTrue(r.wire.requests.isEmpty)
        }
    }
    func testLateSuccessCannotPublishAfterSameAccountGrantOrViewerReplacement() async throws {
        for change in ["replace", "viewer", "token", "namespace", "revoke"] {
            let r = try Rig(); r.wire.hold = true
            let task = Task { try await r.reader.album(page: 1, pageSize: 20) }
            try await waitFor { r.wire.pending != nil }; try r.change(change); r.wire.finish()
            do { _ = try await task.value; XCTFail(change) } catch { XCTAssertTrue(error is CancellationError, change) }
            XCTAssertTrue(r.expired.isEmpty)
        }
    }
    func testLate401DoesNotExpireSuccessorButCurrent401Does() async throws {
        let r = try Rig(); r.wire.hold = true
        let task = Task { try await r.reader.album(page: 1, pageSize: 20) }
        try await waitFor { r.wire.pending != nil }; try r.change("replace"); r.wire.finish(status: 401)
        do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(r.expired.isEmpty)
        r.wire.hold = false; r.wire.status = 401
        do { _ = try await r.reader.album(page: 1, pageSize: 20); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        XCTAssertEqual(r.expired, [try XCTUnwrap(r.current)])
    }
    func testCancelledRequestCannotPublishEvenWhenTransportIgnoresCancellation() async throws {
        let r = try Rig(); r.wire.hold = true
        let task = Task { try await r.reader.album(page: 1, pageSize: 20) }
        try await waitFor { r.wire.pending != nil }; task.cancel(); r.wire.finish()
        do { _ = try await task.value; XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(r.expired.isEmpty)
    }
    func testStrictOriginalResponseRejectsMissingListAndInvalidTotalsInsteadOfEmptySuccess() async throws {
        let r = try Rig()
        let bodies = [
            #"{"code":200,"data":{"total":0,"pageNum":1,"pageSize":20}}"#,
            #"{"code":200,"data":{"list":[],"total":-1,"pageNum":1,"pageSize":20}}"#,
            #"{"code":200,"data":{"list":[{"id":1}],"total":0,"pageNum":1,"pageSize":20}}"#,
            #"{"code":200,"data":{"list":[{"id":0}],"total":1,"pageNum":1,"pageSize":20}}"#,
            #"{"code":200,"data":{"list":[{"id":1},{"id":1}],"total":2,"pageNum":1,"pageSize":20}}"#]
        for body in bodies {
            r.wire.body = body
            do { _ = try await r.reader.album(page: 1, pageSize: 20); XCTFail(body) }
            catch { XCTAssertEqual(error as? APIError, .malformedResponse) }
        }
    }
    func testOriginalKindIsOptionalAndUnknownKindNeverInvented() throws {
        for (raw, kind): (String, Int?) in [(#"{"id":1}"#, nil), (#"{"id":1,"kind":null}"#, nil),
            (#"{"id":1,"kind":0}"#, 0), (#"{"id":1,"kind":1}"#, 1), (#"{"id":1,"kind":9}"#, 9)] {
            let value = try JSONDecoder().decode(RoamAlbumStamp.self, from: Data(raw.utf8))
            XCTAssertEqual(value.kind, kind); XCTAssertTrue(value.isVisible)
        }
    }
    func testHTTPFailurePrecedesPayloadAndOldBusiness500IsNotReclassifiedAsLogin() async throws {
        let r = try Rig()
        for (status, code, expected): (Int, Int, APIError) in [
            (503, 401, .httpStatus(503)), (403, 200, .httpStatus(403)),
            (200, 500, .businessCode(500)), (200, 403, .businessCode(403))] {
            r.wire.status = status; r.wire.body = "{\"code\":\(code),\"msg\":\"请先登录\"}"
            do { _ = try await r.reader.album(page: 1, pageSize: 20); XCTFail() }
            catch { XCTAssertEqual(error as? APIError, expected) }
        }
        XCTAssertTrue(r.expired.isEmpty)
    }
    func testPagerRetains503CursorButClears403AndRequiresFirstPageRefresh() async throws {
        let r = try Rig(), pager = RoamAlbumPager(reader: r.reader)
        await pager.loadNext(); XCTAssertEqual(pager.stamps.map(\.id), [1]); XCTAssertTrue(pager.hasMore)
        r.wire.status = 503; await pager.loadNext()
        XCTAssertEqual(pager.stamps.map(\.id), [1]); XCTAssertEqual(pager.error as? APIError, .httpStatus(503))
        r.wire.status = 403; await pager.loadNext()
        XCTAssertTrue(pager.stamps.isEmpty); XCTAssertNil(pager.total); XCTAssertFalse(pager.hasMore)
        let count = r.wire.requests.count; r.wire.status = 200; await pager.loadNext()
        XCTAssertEqual(r.wire.requests.count, count)
        pager.reset(); await pager.loadNext()
        XCTAssertEqual(r.wire.pages, [1, 2, 2, 1]); XCTAssertNil(pager.error)
    }
    func testOriginalModerationFilterKeepsServerCountAndNoOtherReadOpens() async throws {
        let r = try Rig()
        r.wire.body = #"{"code":200,"data":{"list":[{"id":1,"checkState":0},{"id":2,"checkState":1},{"id":3,"checkState":2}],"total":3,"pageNum":1,"pageSize":20}}"#
        let pager = RoamAlbumPager(reader: r.reader); await pager.loadNext()
        XCTAssertEqual(pager.stamps.map(\.id), [1, 2]); XCTAssertEqual(pager.total, 3)
        XCTAssertThrowsError(try r.reader.history())
        do { _ = try await r.reader.tilePage(afterID: 0, limit: 20); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        XCTAssertEqual(r.wire.requests.count, 1)
    }
    private func waitFor(_ condition: () -> Bool) async throws {
        for _ in 0..<200 { if condition() { return }; await Task.yield() }
        XCTAssertTrue(condition())
    }
    @MainActor private final class Rig {
        static let base = URL(string: "https://received-scope.example/native")!
        let wire = Wire()
        var current: RuntimeDependencyContext?, viewer: UInt64 = 1, grant: RoamReceivedStampReadAccess?
        var expired: [RuntimeDependencyContext] = []
        lazy var reader = RoamReceivedStampReader(service: try! .init(configuration: APIConfiguration(baseURL: Self.base), transport: wire),
            current: { [unowned self] in current }, viewerRevision: { [unowned self] in viewer },
            access: { [unowned self] _ in grant }, onUnauthorized: { [unowned self] in expired.append($0) })
        init() throws { current = try Self.context(); grant = try Self.grant(current!) }
        static func context(account: Int = 81, epoch: UInt64 = 1, token: String = "synthetic-received", namespace: String = "synthetic", role: String = "player", base: URL = URL(string: "https://received-scope.example/native")!) throws -> RuntimeDependencyContext {
            .init(market: .china, baseURL: base, role: role, session: try .init(accountID: account, epoch: epoch, namespace: namespace, token: token))
        }
        static func grant(_ c: RuntimeDependencyContext) throws -> RoamReceivedStampReadAccess {
            try .init(context: c, approval: .init(baseURL: c.baseURL, namespace: c.session.namespace, accountID: c.session.accountID, paths: [RoamReceivedStampReadRoute.path]))
        }
        func change(_ value: String) throws {
            switch value {
            case "replace": grant = try Self.grant(current!)
            case "revoke": grant?.revoke()
            case "remove": grant = nil
            case "viewer": viewer += 1
            case "account": current = try Self.context(account: 82)
            case "epoch": current = try Self.context(epoch: 2)
            case "token": current = try Self.context(token: "other-received")
            case "namespace": current = try Self.context(namespace: "other")
            case "role": current = try Self.context(role: "club")
            case "base": current = try Self.context(base: URL(string: "https://other.example/native")!)
            default: current = nil
            }
        }
    }
    @MainActor private final class Wire: HTTPTransport {
        var requests: [URLRequest] = [], pages: [Int] = [], body: String?, status = 200, hold = false
        var pending: CheckedContinuation<(Data, Int), Error>?
        private var held = Data()
        func finish(status: Int = 200) { let p = pending; pending = nil; p?.resume(returning: (held, status)) }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            let route = try XCTUnwrap(RoamReceivedStampReadRoute(request: request, baseURL: Rig.base))
            requests.append(request); pages.append(route.page)
            let value = body ?? "{\"code\":200,\"data\":{\"list\":[{\"id\":\(route.page),\"kind\":0}],\"total\":21,\"pageNum\":\(route.page),\"pageSize\":20}}"
            let bytes = Data(value.utf8)
            if hold { held = bytes; return try await withCheckedThrowingContinuation { pending = $0 } }
            return (bytes, status)
        }
    }
}

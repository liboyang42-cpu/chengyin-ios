import XCTest
@testable import QuestifyCore
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@MainActor final class GrowthNormalReadTransportTests: XCTestCase {
    private func context(account: Int = 7, epoch: UInt64 = 1, token: String = "synthetic-7",
                         role: String = "player", namespace: String = "synthetic-growth",
                         base: String = "https://example.test/native") throws -> RuntimeDependencyContext {
        RuntimeDependencyContext(market: .china, baseURL: URL(string: base)!, role: role,
            session: try PlayExperienceSession(accountID: account, epoch: epoch, namespace: namespace, token: token))
    }
    private func request(_ route: GrowthNormalReadRoute, context: RuntimeDependencyContext) throws -> URLRequest {
        var request = try AuthRequestBuilder.makeFormRequest(url: context.baseURL.appendingPathComponent(route.rawValue), fields: [:], token: context.session.token)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("{}".utf8)
        return request
    }
    func testOnlyFrozenThreeOriginalJSONReadsMatch() throws {
        let context = try context(), approval = try GrowthNormalReadApproval(context: context, expiresAt: Date().addingTimeInterval(600))
        XCTAssertEqual(GrowthNormalReadApproval.authorityCommit, "58f4cc429b0d0e3035ccdf1bd4a9c3dfd76eb9a4")
        XCTAssertEqual(Set(GrowthNormalReadRoute.allCases.map(\.rawValue)), ["api/growth/center", "api/play/growth", "api/play/my-completed"])
        for route in GrowthNormalReadRoute.allCases {
            let request = try request(route, context: context)
            XCTAssertEqual(GrowthNormalReadRoute(request: request, baseURL: context.baseURL), route)
            XCTAssertTrue(GrowthNormalReadRoute.accepts(request, context: context, approval: approval))
        }
    }
    func testBodyMethodHeadersAndExactURLCannotBroadenOriginalReads() throws {
        let context = try context(), original = try request(.center, context: context)
        let edits: [(inout URLRequest) -> Void] = [
            { $0.httpMethod = "GET" }, { $0.httpMethod = "PUT" },
            { $0.httpBody = nil }, { $0.httpBody = Data("[]".utf8) },
            { $0.httpBody = Data("{ }".utf8) }, { $0.httpBody = Data(#"{"memberId":7}"#.utf8) },
            { $0.httpBody = Data(#"{"scope":"MERCHANT"}"#.utf8) },
            { $0.httpBodyStream = InputStream(data: Data("{}".utf8)) },
            { $0.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type") },
            { $0.setValue(nil, forHTTPHeaderField: "Accept") },
            { $0.setValue("sid=synthetic", forHTTPHeaderField: "Cookie") },
            { $0.setValue("7", forHTTPHeaderField: "X-Member-ID") },
            { $0.url = URL(string: "https://other.test/native/api/growth/center") },
            { $0.url = URL(string: "https://example.test/native/api/growth/center?memberId=7") },
            { $0.url = URL(string: "https://example.test/native/api/growth/center#fragment") },
            { $0.url = URL(string: "https://example.test/native/api/growth/center/") }
        ]
        for edit in edits {
            var changed = original; edit(&changed)
            XCTAssertNil(GrowthNormalReadRoute(request: changed, baseURL: context.baseURL))
        }
    }
    func testAnonymousLegacyAndMutationRoutesRemainClosed() throws {
        let context = try context()
        for path in ["api/growth/leaderboard/anonymous", "api/growth/leaderboard", "api/growth/mission/complete", "api/play/checkin", "api/registration/info"] {
            var request = try request(.center, context: context); request.url = context.baseURL.appendingPathComponent(path)
            XCTAssertNil(GrowthNormalReadRoute(request: request, baseURL: context.baseURL), path)
        }
        let anonymous = try AuthRequestBuilder.makeFormRequest(url: context.baseURL.appendingPathComponent("api/growth/leaderboard/anonymous"),
            fields: ["metric":"point", "period":"total", "limit":"1"], token: context.session.token)
        XCTAssertNil(GrowthNormalReadRoute(request: anonymous, baseURL: context.baseURL))
    }
    func testLeaseBindsFullContextExpiryRevocationAndRawCredential() throws {
        let original = try context(), request = try request(.center, context: original)
        let approval = try GrowthNormalReadApproval(context: original, expiresAt: Date().addingTimeInterval(600))
        for other in [try context(account: 8), try context(epoch: 2), try context(token: "synthetic-8"),
                      try context(role: "merchant"), try context(namespace: "other"), try context(base: "https://other.test/native")] {
            XCTAssertFalse(approval.matches(other))
        }
        var bearer = request; bearer.setValue("Bearer synthetic-7", forHTTPHeaderField: "Authorization")
        XCTAssertFalse(GrowthNormalReadRoute.accepts(bearer, context: original, approval: approval))
        XCTAssertFalse(approval.matches(original, now: approval.expiresAt))
        approval.revoke(); XCTAssertFalse(approval.matches(original))
        XCTAssertFalse(GrowthNormalReadRoute.accepts(request, context: original, approval: approval))
        XCTAssertThrowsError(try GrowthNormalReadApproval(context: original, expiresAt: Date().addingTimeInterval(-1)))
        XCTAssertThrowsError(try GrowthNormalReadApproval(context: original, expiresAt: Date().addingTimeInterval(86_500)))
    }
    func testReadScopeRetiresOnApprovalAndViewerRevisionWithoutChangingAccount() throws {
        let revision = UUID()
        var session: GrowthCenterReadSession? = try .init(accountID: 7, epoch: 1, token: "synthetic-7", approvalRevision: revision, viewerRevision: 1)
        let reader = GrowthCenterSessionReader(service: nil, currentSession: { session })
        let first = reader.scope
        session = try .init(accountID: 7, epoch: 1, token: "synthetic-7", approvalRevision: revision, viewerRevision: 2)
        let refreshed = reader.scope; XCTAssertNotEqual(first, refreshed)
        session = try .init(accountID: 7, epoch: 1, token: "synthetic-7", approvalRevision: nil, viewerRevision: 2)
        XCTAssertNotEqual(refreshed, reader.scope)
        let cold = GrowthCenterSessionReader(service: nil, currentSession: { session })
        XCTAssertNotEqual(cold.scope, reader.scope)
    }
    func testOwnedOverviewCancellationReachesLateUnauthorizedReader() async throws {
        let wire = PausedWire(), owner = GrowthNormalReadTask()
        let service = GrowthCenterService(configuration: try APIConfiguration(baseURL: URL(string: "https://example.test/native")!), transport: wire)
        let session = try GrowthCenterReadSession(accountID: 7, epoch: 1, token: "synthetic-7")
        var expirations = 0, returned = false
        let reader = GrowthCenterSessionReader(service: service, currentSession: { session }, onUnauthorized: { _ in expirations += 1 })
        owner.start {
            do { _ = try await reader.overview(); XCTFail("Canceled overview must not return") }
            catch { XCTAssertTrue(error is CancellationError) }
            returned = true
        }
        while wire.pending == nil { await Task.yield() }
        owner.cancel(); wire.finish()
        while !returned { await Task.yield() }
        XCTAssertEqual(expirations, 0)
    }
    func testReadSessionTreatsCredentialBytesAsOpaque() throws {
        let revision = UUID()
        let first = try GrowthCenterReadSession(accountID: 7, epoch: 1, token: "synthetic-7", approvalRevision: revision, viewerRevision: 1)
        let second = try GrowthCenterReadSession(accountID: 7, epoch: 1, token: "synthetic-8", approvalRevision: revision, viewerRevision: 1)
        XCTAssertNotEqual(first, second)
        var current: GrowthCenterReadSession? = first
        let reader = GrowthCenterSessionReader(service: nil, currentSession: { current })
        let oldScope = reader.scope
        current = second
        XCTAssertNotEqual(oldScope, reader.scope)
    }
    func testReadbackAfterFailureDoesNotRetainIssueAndScopeMismatchHidesValue() async {
        let model = GrowthCenterReadModel<Int>()
        let first = GrowthCenterLoadKey(scope: UUID())
        var current = first
        await model.load(key: first, currentKey: { current }) { throw APIError.notConfigured }
        XCTAssertEqual(model.visibleIssue(key: first), .notConfigured)
        XCTAssertNil(model.visibleValue(key: first))
        await model.load(key: first, currentKey: { current }) { 0 }
        XCTAssertEqual(model.visibleValue(key: first), 0)
        XCTAssertNil(model.visibleIssue(key: first))
        current = GrowthCenterLoadKey(scope: UUID())
        XCTAssertNil(model.visibleValue(key: current))
        await model.load(key: current, currentKey: { current }) { 7 }
        XCTAssertEqual(model.visibleValue(key: current), 7)
        XCTAssertNil(model.visibleValue(key: first))
    }
    func testLateReplacedFailureCannotEraseNewReadback() async {
        let model = GrowthCenterReadModel<Int>()
        let key = GrowthCenterLoadKey(scope: UUID())
        var pending: CheckedContinuation<Int, Error>?
        let old = Task { @MainActor in
            await model.load(key: key, currentKey: { key }) {
                try await withCheckedThrowingContinuation { pending = $0 }
            }
        }
        for _ in 0..<1000 {
            if pending != nil { break }
            await Task.yield()
        }
        guard let continuation = pending else {
            old.cancel()
            XCTFail("Old read did not reach the synthetic suspension point")
            return
        }
        await model.load(key: key, currentKey: { key }) { 42 }
        continuation.resume(throwing: APIError.notConfigured)
        await old.value
        XCTAssertEqual(model.visibleValue(key: key), 42)
        XCTAssertNil(model.visibleIssue(key: key))
        XCTAssertFalse(model.isLoading)
    }
    @MainActor private final class PausedWire: HTTPTransport {
        var pending: CheckedContinuation<(Data, Int), Error>?
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            if request.url?.path.hasSuffix("/growth/center") == true {
                return try await withCheckedThrowingContinuation { pending = $0 }
            }
            return (Data(#"{"code":503}"#.utf8), 503)
        }
        func finish() { let continuation = pending; pending = nil; continuation?.resume(returning: (Data(#"{"code":401}"#.utf8), 401)) }
    }
}

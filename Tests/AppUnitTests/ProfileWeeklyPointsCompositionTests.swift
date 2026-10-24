import XCTest
@testable import Questify

@MainActor final class ProfileWeeklyPointsCompositionTests: XCTestCase {
    private let base = URL(string: "https://weekly.example/native")!
    private func root(_ wire: Wire, _ grants: Grants? = nil, vault: Vault? = nil) throws -> AppCompositionRoot {
        let vault = vault ?? Vault()
        let suite = "weekly-profile-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let deployment = try ReviewedAppDeployment(market: .china, baseURL: base.absoluteString,
            approvedBaseURLs: [.china: [base.absoluteString]], verifiedCapabilities: [.domesticChinaPhone],
            bundleIdentifier: "test.profile-weekly", realm: "synthetic")
        return .init(deployment: .reviewed(deployment), storage: .init(defaults: defaults, tokenStore: { _ in vault }),
            makeTransport: { wire }, profileWeeklyPointsReadApproval: { grants?.select($0) })
    }
    private func login(_ session: AppSession) async {
        session.authChannels.cancel(); await session.authChannels.loginWithPhone(phone: "10000000000", code: "123456")
        XCTAssertNotNil(session.account)
    }
    private func request() throws -> URLRequest {
        try AuthRequestBuilder.makeFormRequest(url: base.appendingPathComponent(ProfileWeeklyPointsReadRoute.path),
            fields: [:], token: "synthetic-weekly", includesBody: false)
    }
    func testDefaultFactoryShowsUnavailableAndDispatchesNoStatistics() async throws {
        let wire = Wire(), session = try root(wire).makeSession(); await login(session); wire.requests = []
        XCTAssertFalse(session.profileWeeklyPointsReader.isConfigured)
        do { _ = try await session.profileWeeklyPointsReader.weeklyPoints(); XCTFail() }
        catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testNormalSessionFactoryUsesExplicitLeaseAndLiveRevocation() async throws {
        let wire = Wire(), grants = Grants(), session = try root(wire, grants).makeSession(); await login(session)
        wire.requests = []; let reader = session.profileWeeklyPointsReader
        let value = try await reader.weeklyPoints(); XCTAssertEqual(value.weekPoints, 6)
        XCTAssertEqual(wire.requests.count, 1); XCTAssertNil(wire.requests[0].httpBody)
        let identity = reader.identity; grants.retained?.revoke(); grants.enabled = false
        XCTAssertFalse(reader.isConfigured); XCTAssertNotEqual(reader.identity, identity)
        do { _ = try await reader.weeklyPoints(); XCTFail() } catch {}
        XCTAssertEqual(wire.requests.count, 1)
        grants.retained = nil; grants.enabled = true
        XCTAssertTrue(reader.isConfigured)
        _ = try await reader.weeklyPoints(); XCTAssertEqual(wire.requests.count, 2)
    }
    func testClonesPreserveOnlyThisExactReadAndRejectMemberOverride() async throws {
        let wire = Wire(), grants = Grants(), transport = try root(wire, grants).transport()
        transport.current = { .init(epoch: 1, accountID: 81, role: "player", token: "synthetic-weekly", viewerRevision: 1) }
        let clone = transport.replacingUnderlying(wire).scopedForManualMap(ManualMapAreaSelection())
        let valid = try request(); _ = try await clone.send(valid)
        var invalid: [URLRequest] = []
        for path in ["api/user/update", "api/growth/center", "api/points/list", "api/points/result_list"] {
            var copy = valid; copy.url = base.appendingPathComponent(path); invalid.append(copy)
        }
        var copy = valid; copy.url = URL(string: valid.url!.absoluteString + "?member_id=82"); invalid.append(copy)
        copy = valid; copy.httpBody = Data(#"{"member_id":82}"#.utf8); invalid.append(copy)
        copy = valid; copy.setValue("other", forHTTPHeaderField: "Authorization"); invalid.append(copy)
        copy = valid; copy.httpMethod = "GET"; invalid.append(copy)
        for request in invalid { do { _ = try await clone.send(request); XCTFail() } catch {} }
        XCTAssertEqual(wire.requests.count, 1)
    }
    func testOldViewerTokenOwnerOrLeaseCannotReturnLateSuccessOr401() async throws {
        for change in ["viewer", "token", "owner", "revoke", "replace"] {
            for status in [200, 401] {
                let wire = Wire(), grants = Grants(), transport = try root(wire, grants).transport()
                var identity = CompositionHTTPTransport.SessionIdentity(epoch: 1, accountID: 81, role: "player", token: "synthetic-weekly", viewerRevision: 1)
                transport.current = { identity }; wire.pause = true
                let paused = expectation(description: "pending weekly read"); wire.onPaused = { paused.fulfill() }
                let task = Task { try await transport.send(request()) }; await fulfillment(of: [paused], timeout: 2)
                let lease = try XCTUnwrap(grants.retained)
                switch change {
                case "revoke": lease.revoke()
                case "replace": grants.retained = try .init(context: lease.context, expiresAt: Date().addingTimeInterval(600))
                case "token": identity = .init(epoch: 1, accountID: 81, role: "player", token: "new-token", viewerRevision: 1)
                case "owner": identity = .init(epoch: 2, accountID: 82, role: "player", token: "synthetic-weekly", viewerRevision: 2)
                default: identity = .init(epoch: 1, accountID: 81, role: "player", token: "synthetic-weekly", viewerRevision: 3)
                }
                wire.finish(status: status)
                do { _ = try await task.value; XCTFail(change) } catch { XCTAssertTrue(error is CancellationError) }
            }
        }
    }
    func testCurrentUnauthorizedReplyExpiresOnlyCurrentSession() async throws {
        let wire = Wire(), vault = Vault(), session = try root(wire, Grants(), vault: vault).makeSession()
        await login(session); wire.code = 401
        do { _ = try await session.profileWeeklyPointsReader.weeklyPoints(); XCTFail() } catch {}
        XCTAssertNil(session.account); XCTAssertNil(vault.value)
    }
    func testApprovalCannotMatchWrongOriginRoleOwnerOrExpiredTime() throws {
        let session = try PlayExperienceSession(accountID: 81, epoch: 1, namespace: "synthetic", token: "synthetic-weekly")
        let context = RuntimeDependencyContext(market: .china, baseURL: base, role: "player", session: session)
        let approval = try ProfileWeeklyPointsReadApproval(context: context, expiresAt: Date().addingTimeInterval(600))
        XCTAssertEqual(approval.endpoints.paths, [ProfileWeeklyPointsReadRoute.path])
        XCTAssertTrue(approval.matches(context)); XCTAssertFalse(approval.matches(context, now: approval.expiresAt))
        XCTAssertFalse(approval.matches(.init(market: .china, baseURL: URL(string: "https://other.example")!, role: "player", session: session)))
        XCTAssertFalse(approval.matches(.init(market: .china, baseURL: base, role: "merchant", session: session)))
        let other = try PlayExperienceSession(accountID: 82, epoch: 1, namespace: "synthetic", token: "synthetic-weekly")
        XCTAssertFalse(approval.matches(.init(market: .china, baseURL: base, role: "player", session: other)))
        approval.revoke(); XCTAssertFalse(approval.matches(context))
        XCTAssertThrowsError(try ProfileWeeklyPointsReadApproval(context: context, expiresAt: Date().addingTimeInterval(-1)))
    }
    @MainActor private final class Grants {
        var enabled = true
        var retained: ProfileWeeklyPointsReadApproval?
        func select(_ context: RuntimeDependencyContext) -> ProfileWeeklyPointsReadApproval? {
            guard enabled else { return nil }
            if retained == nil { retained = try? .init(context: context, expiresAt: Date().addingTimeInterval(600)) }
            return retained
        }
    }
    @MainActor private final class Vault: AppTokenStorage {
        var value: String?
        func read() throws -> String? { value }
        func write(_ token: String) throws { value = token }
        func clear() throws { value = nil }
    }
    @MainActor private final class Wire: HTTPTransport {
        var requests: [URLRequest] = [], code = 200, pause = false
        var onPaused: (() -> Void)?
        var pending: CheckedContinuation<(Data, Int), Error>?
        private let value = #"{"code":200,"data":{"weekPoints":6,"rankPercentage":"TOP 50%","totalUsers":10,"userRank":5}}"#
        func finish(status: Int) { pending?.resume(returning: (Data(value.utf8), status)); pending = nil }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            if request.url!.path.hasSuffix("/phone") {
                return (Data(#"{"code":200,"token":"synthetic-weekly","data":{"id":81,"role":"player"}}"#.utf8), 200)
            }
            if request.url!.path.hasSuffix("/userInfo") {
                return (Data(#"{"code":200,"appUser":{"userId":81,"role":"player"}}"#.utf8), 200)
            }
            if pause { return try await withCheckedThrowingContinuation { pending = $0; onPaused?() } }
            return (Data(value.utf8), code)
        }
    }
}

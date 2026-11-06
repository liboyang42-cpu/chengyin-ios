import XCTest
@testable import Questify

/// Synthetic normal AppSession -> dedicated composition child -> original wire.
/// No network, Keychain, deployment configuration, or legacy fixtures are changed.
@MainActor final class GrowthNormalReadTransportTests: XCTestCase {
    private let url = "https://example.test/native"
    private func setup(enabled: Bool = true, restored: Bool = false) throws -> (AppCompositionRoot, AppSession, Wire, Grants, Vault) {
        let wire = Wire(), grants = Grants(), vault = Vault()
        if restored { vault.value = "synthetic-7" }
        let suite = "growth-normal-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let deployment = try ReviewedAppDeployment(market: .china, baseURL: url, approvedBaseURLs: [.china: [url]],
            verifiedCapabilities: [.domesticChinaPhone], bundleIdentifier: "test.growth", realm: "fixture")
        let root = AppCompositionRoot(deployment: .reviewed(deployment),
            storage: .init(defaults: defaults, tokenStore: { _ in vault }), makeTransport: { wire },
            growthNormalReadApproval: { enabled ? grants.select($0) : nil })
        return (root, root.makeSession(), wire, grants, vault)
    }
    private func signIn(_ session: AppSession) async {
        session.authChannels.cancel()
        await session.authChannels.loginWithPhone(phone: "10000000000", code: "123456")
        XCTAssertNotNil(session.account)
    }
    func testNormalServiceForwardsExactlyThreeOriginalReadsWithoutAnonymousFallback() async throws {
        let (_, session, wire, _, _) = try setup(); await signIn(session); wire.requests = []
        let result = try await session.growthCenterReader.overview()
        XCTAssertEqual(result.center.value?.points, 700); XCTAssertEqual(result.progress.value?.totalCheckins, 12)
        XCTAssertEqual(result.completedTopicCount, 2); XCTAssertEqual(result.rank.issue, .notConfigured)
        XCTAssertEqual(Set(wire.requests.compactMap { $0.url?.path }), Set(GrowthNormalReadRoute.allCases.map { "/native/" + $0.rawValue }))
        XCTAssertEqual(wire.requests.count, 3)
        for request in wire.requests {
            XCTAssertNotNil(GrowthNormalReadRoute(request: request, baseURL: URL(string: url)!))
            XCTAssertEqual(request.httpBody, Data("{}".utf8))
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "synthetic-7")
        }
        for query in [GrowthBoardQuery(), .init(metric: .exp, period: .week)] {
            do { _ = try await session.growthCenterReader.leaderboard(query: query); XCTFail() }
            catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        }
        XCTAssertEqual(wire.requests.count, 3)
    }
    func testDefaultHoldMakesNoGrowthRequestEvenWithReviewedLogin() async throws {
        let (_, session, wire, _, _) = try setup(enabled: false); await signIn(session); wire.requests = []
        let result = try await session.growthCenterReader.overview()
        XCTAssertEqual(result.center.issue, .notConfigured); XCTAssertEqual(result.progress.issue, .notConfigured)
        XCTAssertEqual(result.completed.issue, .notConfigured); XCTAssertEqual(result.rank.issue, .notConfigured)
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testGenericRootDoesNotInheritGrowthChildAuthority() async throws {
        let (root, session, wire, grants, _) = try setup(); await signIn(session)
        _ = try await session.growthCenterReader.overview()
        let context = try XCTUnwrap(grants.retained?.context), generic = root.transport()
        generic.current = { .init(epoch: context.session.epoch, accountID: 7, role: context.role, token: context.session.token) }
        let before = wire.requests.count
        for route in GrowthNormalReadRoute.allCases {
            var request = try AuthRequestBuilder.makeFormRequest(url: context.baseURL.appendingPathComponent(route.rawValue), fields: [:], token: context.session.token)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = Data("{}".utf8)
            do { _ = try await generic.send(request); XCTFail() } catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        }
        XCTAssertEqual(wire.requests.count, before)
    }
    func testDedicatedChildRejectsWrongOwnerTokenPayloadAndUnrelatedRoutesBeforeWire() async throws {
        let (root, session, wire, grants, _) = try setup(); await signIn(session)
        _ = try await session.growthCenterReader.overview()
        let context = try XCTUnwrap(grants.retained?.context), generic = root.transport()
        var owner = 7
        generic.current = { .init(epoch: context.session.epoch, accountID: owner, role: context.role, token: context.session.token) }
        let child = generic.growthNormalReadTransport(approval: { _ in grants.retained })
        var original = try AuthRequestBuilder.makeFormRequest(url: context.baseURL.appendingPathComponent("api/growth/center"), fields: [:], token: context.session.token)
        original.setValue("application/json", forHTTPHeaderField: "Content-Type"); original.httpBody = Data("{}".utf8)
        let before = wire.requests.count
        for kind in ["owner", "token", "field", "anonymous", "legacy", "mission"] {
            var changed = original; owner = 7
            switch kind {
            case "owner": owner = 8
            case "token": changed.setValue("synthetic-8", forHTTPHeaderField: "Authorization")
            case "field": changed.httpBody = Data(#"{"memberId":7}"#.utf8)
            case "anonymous": changed.url = context.baseURL.appendingPathComponent("api/growth/leaderboard/anonymous")
            case "legacy": changed.url = context.baseURL.appendingPathComponent("api/growth/leaderboard")
            default: changed.url = context.baseURL.appendingPathComponent("api/growth/mission/complete")
            }
            do { _ = try await child.send(changed); XCTFail(kind) } catch { XCTAssertEqual(error as? APIError, .notConfigured) }
        }
        XCTAssertEqual(wire.requests.count, before)
    }
    func testIndependentFailureAndRetryDoNotTurnMissingDataIntoEmptySuccess() async throws {
        let (_, session, wire, _, _) = try setup(); await signIn(session)
        for failure in [(#"{"code":403}"#, 200, GrowthCenterIssue.denied),
                        (#"{"code":503}"#, 503, .unavailable),
                        (#"{"code":200,"data":{}}"#, 200, .failed)] {
            wire.center = failure.0; wire.centerStatus = failure.1
            let result = try await session.growthCenterReader.overview()
            XCTAssertEqual(result.center.issue, failure.2); XCTAssertNil(result.center.value)
            XCTAssertEqual(result.progress.value?.totalCheckins, 12); XCTAssertEqual(result.completedTopicCount, 2)
        }
        wire.center = GrowthCenterSyntheticFixtures.centerJSON; wire.centerStatus = 200
        let recovered = try await session.growthCenterReader.overview()
        XCTAssertEqual(recovered.center.value?.points, 700)
    }
    func testLeaseRevocationReplacementViewerAndAccountFenceLate401() async throws {
        for change in ["revoke", "replace", "viewer", "account"] {
            let (root, session, wire, grants, vault) = try setup(); await signIn(session)
            _ = try await session.growthCenterReader.overview()
            let oldScope = session.growthCenterReader.scope
            wire.pauseCenter = true
            let task = Task { try await session.growthCenterReader.overview() }
            while wire.pending == nil { await Task.yield() }
            if change == "revoke" { grants.retained?.revoke() }
            else if change == "replace" {
                let context = try XCTUnwrap(grants.retained?.context); grants.retained?.revoke()
                grants.retained = try GrowthNormalReadApproval(context: context, expiresAt: Date().addingTimeInterval(600))
            } else if change == "account" {
                await session.logout(); wire.account = 8; await signIn(session)
            } else {
                // The complete viewer revision is checked even when credential bytes match.
                // A dedicated child captured from this generic instance observes its revision.
                let generic = root.transport(), context = try XCTUnwrap(grants.retained?.context)
                var viewer: UInt64 = 1
                generic.current = { .init(epoch: context.session.epoch, accountID: 7, role: context.role, token: context.session.token, viewerRevision: viewer) }
                let child = generic.growthNormalReadTransport(approval: { grants.select($0) })
                var request = try AuthRequestBuilder.makeFormRequest(url: context.baseURL.appendingPathComponent("api/play/growth"), fields: [:], token: context.session.token)
                request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = Data("{}".utf8)
                wire.beforeReturn = { viewer += 1 }
                do { _ = try await child.send(request); XCTFail() } catch { XCTAssertTrue(error is CancellationError) }
                wire.beforeReturn = nil; grants.retained?.revoke()
            }
            wire.finishCenter(status: 401)
            do { _ = try await task.value; XCTFail(change) } catch { XCTAssertTrue(error is CancellationError, "\(change): \(error)") }
            XCTAssertEqual(session.account?.id, wire.account); XCTAssertEqual(vault.value, "synthetic-\(wire.account)")
            XCTAssertNotEqual(oldScope, session.growthCenterReader.scope)
        }
    }
    func testCurrent401ExpiresCurrentSessionButColdReadHasNoRestoredGrowthValue() async throws {
        let (_, session, wire, _, vault) = try setup(restored: true)
        await session.bootstrap(); XCTAssertEqual(session.account?.id, 7); wire.requests = []
        let model = GrowthCenterScreenModel<GrowthCenterOverview>(), key = GrowthCenterLoadKey(scope: session.growthCenterReader.scope)
        XCTAssertNil(model.value(key: key))
        _ = try await session.growthCenterReader.overview(); XCTAssertEqual(wire.requests.count, 3)
        wire.center = #"{"code":401}"#
        do { _ = try await session.growthCenterReader.overview(); XCTFail() } catch { XCTAssertEqual(error as? APIError, .unauthorized) }
        XCTAssertNil(session.account); XCTAssertNil(vault.value)
    }
    @MainActor private final class Grants {
        var retained: GrowthNormalReadApproval?
        func select(_ context: RuntimeDependencyContext) -> GrowthNormalReadApproval? {
            if retained == nil || !ContentDraftContextFence.matches(retained?.context, context) {
                retained?.revoke(); retained = try? .init(context: context, expiresAt: Date().addingTimeInterval(600))
            }
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
        var requests: [URLRequest] = [], account = 7
        var center = GrowthCenterSyntheticFixtures.centerJSON, centerStatus = 200
        var pauseCenter = false
        var pending: CheckedContinuation<(Data, Int), Error>?
        var beforeReturn: (() -> Void)?
        func finishCenter(status: Int) { let continuation = pending; pending = nil; continuation?.resume(returning: (Data(center.utf8), status)) }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            let path = request.url!.path
            if path.hasSuffix("/phone") { return (Data("{\"code\":200,\"token\":\"synthetic-\(account)\",\"data\":{\"id\":\(account),\"role\":\"player\"}}".utf8), 200) }
            if path.hasSuffix("/userInfo") { return (Data("{\"code\":200,\"appUser\":{\"userId\":\(account),\"role\":\"player\"}}".utf8), 200) }
            if path.hasSuffix("/growth/center") {
                if pauseCenter { return try await withCheckedThrowingContinuation { pending = $0 } }
                return (Data(center.utf8), centerStatus)
            }
            beforeReturn?()
            if path.hasSuffix("/play/growth") { return (Data(GrowthCenterSyntheticFixtures.progressJSON.utf8), 200) }
            if path.hasSuffix("/play/my-completed") { return (Data(GrowthCenterSyntheticFixtures.completedJSON.utf8), 200) }
            return (Data(#"{"code":200,"data":[]}"#.utf8), 200)
        }
    }
}

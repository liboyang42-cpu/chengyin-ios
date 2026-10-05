import XCTest
@testable import Questify

/// Real AppSession factories and the outer transport, with synthetic HTTP only.
@MainActor final class TeamReadCompositionTests: XCTestCase {
    private let base = URL(string: "https://example.test/native")!
    private func root(_ wire: Wire, _ grants: Grants, _ vault: Vault) throws -> AppCompositionRoot {
        let suite = "team-reads-" + UUID().uuidString, defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let deployment = try ReviewedAppDeployment(market: .china, baseURL: base.absoluteString,
            approvedBaseURLs: [.china: [base.absoluteString]], verifiedCapabilities: [.domesticChinaPhone],
            bundleIdentifier: "test.team-reads", realm: "synthetic")
        return .init(deployment: .reviewed(deployment), storage: .init(defaults: defaults, tokenStore: { _ in vault }),
            makeTransport: { wire }, teamReadApproval: { grants.select($0) })
    }
    private func login(_ session: AppSession) async {
        session.authChannels.cancel(); await session.authChannels.loginWithPhone(phone: "10000000000", code: "123456")
        XCTAssertNotNil(session.account)
    }
    func testNormalSessionFactoryReadsFreshMemberAndInvitationWithoutWriter() async throws {
        let wire = Wire(), session = try root(wire, Grants(), Vault()).makeSession(); await login(session); wire.requests = []
        let coordinator = session.makeTeamCoordinator(); XCTAssertFalse(coordinator.canSubmit)
        await coordinator.loadTeams(); XCTAssertEqual(coordinator.teams.map(\.id), [61])
        await coordinator.loadDetail(.id(61)); XCTAssertEqual(coordinator.detail?.members.first?.id, 7)
        XCTAssertEqual(coordinator.detail?.joined, true)
        await coordinator.loadDetail(.invitation(" invite-61 ")); XCTAssertEqual(coordinator.detail?.team.id, 61)
        XCTAssertEqual(wire.requests.compactMap { TeamReadRoute(request: $0, baseURL: base) }, [.mine, .detail(.id(61)), .detail(.invitation("invite-61"))])
        XCTAssertFalse(coordinator.canSubmit)
        await coordinator.loadCreation(ownerID: 21); XCTAssertNil(coordinator.creation); XCTAssertEqual(wire.requests.count, 3)
    }
    func testDefaultNilInnerGrantAndGuestNeverBypassOuterFence() async throws {
        let wire = Wire(), grants = Grants(); grants.enabled = false
        let composition = try root(wire, grants, Vault()), session = composition.makeSession(); await session.makeTeamCoordinator().loadTeams()
        XCTAssertTrue(wire.requests.isEmpty); await login(session); wire.requests = []
        let normal = session.makeTeamCoordinator(); XCTAssertFalse(normal.configured); await normal.loadTeams()
        let namespace = try XCTUnwrap(composition.reviewed?.storageScope.service)
        let inner = try OperationEndpointApproval(baseURL: base, namespace: namespace,
            accountID: 7, paths: ["api/team/my", "api/team/info"])
        await session.makeTeamCoordinator(readApproval: inner).loadTeams()
        XCTAssertTrue(wire.requests.isEmpty)
    }
    func testRevokedLoadedCoordinatorClearsAndDoesNotAdoptNewLease() async throws {
        let wire = Wire(), grants = Grants(), session = try root(wire, grants, Vault()).makeSession(); await login(session)
        let coordinator = session.makeTeamCoordinator(); await coordinator.loadTeams(); XCTAssertEqual(coordinator.teams.count, 1)
        let identity = session.teamViewIdentity; grants.retained?.revoke(); grants.enabled = false
        XCTAssertNotEqual(identity, session.teamViewIdentity)
        let count = wire.requests.count; await coordinator.loadTeams(); XCTAssertTrue(coordinator.teams.isEmpty)
        grants.retained = nil; grants.enabled = true; await coordinator.loadTeams(); XCTAssertEqual(wire.requests.count, count)
        let fresh = session.makeTeamCoordinator(); await fresh.loadTeams(); XCTAssertEqual(fresh.teams.count, 1)
    }
    func testLateSuccessAnd401AfterOwnerRoleABARevocationExpiryOrCancellationDoNotApply() async throws {
        for transition in ["owner", "roleABA", "sessionABA", "revoke", "reissue", "expire", "cancel"] {
            for code in [200, 401, -1] {
                let wire = Wire(), grants = Grants(), vault = Vault(), session = try root(wire, grants, vault).makeSession(); await login(session)
                let coordinator = session.makeTeamCoordinator(), paused = expectation(description: "team read suspended")
                wire.pause = true; wire.onPaused = { paused.fulfill() }
                let task = Task { await coordinator.loadDetail(.id(61)) }; await fulfillment(of: [paused], timeout: 2)
                switch transition {
                case "owner": await session.logout(); wire.account = 8; await login(session)
                case "roleABA": wire.role = "merchant"; await session.refreshOwnAccount(); wire.role = "player"; await session.refreshOwnAccount()
                case "sessionABA": await session.logout(); await login(session)
                case "revoke": grants.retained?.revoke(); grants.enabled = false
                case "reissue": grants.retained?.revoke(); grants.retained = nil; _ = session.teamViewIdentity
                case "expire": let lease = try XCTUnwrap(grants.retained); lease.expireIfNeeded(now: lease.expiresAt)
                default: task.cancel()
                }
                wire.finish(code: code); await task.value
                XCTAssertNil(coordinator.detail, transition); XCTAssertEqual(session.account?.id, wire.account)
                XCTAssertEqual(vault.value, "synthetic-\(wire.account)")
            }
        }
    }
    func testCurrent401ExpiresCurrentSession() async throws {
        let wire = Wire(), vault = Vault(), session = try root(wire, Grants(), vault).makeSession(); await login(session)
        wire.code = 401; await session.makeTeamCoordinator().loadTeams(); XCTAssertNil(session.account); XCTAssertNil(vault.value)
    }
    func testExactShapesClonesCrossScopeAndAllAdjacentMutations() async throws {
        let wire = Wire(), grants = Grants(), root = try root(wire, grants, Vault()).transport()
        root.current = { .init(epoch: 1, accountID: 7, role: "player", token: "synthetic-7", viewerRevision: 1) }
        let clone = root.scopedForManualMap(ManualMapAreaSelection()).replacingUnderlying(wire)
        for (path, body) in [("my", "{}"), ("info", "{\"teamId\":61}"), ("info", "{\"inviteCode\":\"invite-61\"}")] { _ = try await clone.send(json(path, body)) }
        let before = wire.requests.count
        var invalid = [URLRequest]()
        for path in ["create", "join", "quit", "kick", "disband", "join-mode", "apply", "withdraw", "handle", "report", "applications", "my-applications", "nearby"] { invalid.append(json(path, "{}")) }
        for body in ["{\"teamId\":0}", "{\"teamId\":true}", "{\"teamId\":61.0}", "{\"teamId\":\"61\"}", "{\"teamId\":61,\"teamId\":61}", "{\"teamId\":61,\"memberId\":7}", "{\"teamId\":61,\"inviteCode\":\"x\"}", "{\"inviteCode\":\" x \"}", "{\"inviteCode\":\"\"}"] { invalid.append(json("info", body)) }
        for url in ["https://evil.test/native/api/team/my", "https://example.test/other/api/team/my", "https://example.test/native/api/team/my?x=1", "https://example.test/native/api/team/my#x", "https://example.test/native/api/team/%6dy", "https://example.test/native/api/team/../team/my"] { var request = json("my", "{}"); request.url = URL(string: url); invalid.append(request) }
        var request = json("my", "{}"); request.httpMethod = "GET"; invalid.append(request)
        request = json("my", "{}"); request.setValue("other-token", forHTTPHeaderField: "Authorization"); invalid.append(request)
        for request in invalid { do { _ = try await clone.send(request); XCTFail("Unexpected dispatch: \(request)") } catch {} }
        for identity in [CompositionHTTPTransport.SessionIdentity(epoch: 1, accountID: 8, role: "player", token: "synthetic-7"), .init(epoch: 2, accountID: 7, role: "player", token: "synthetic-7"), .init(epoch: 1, accountID: 7, role: "merchant", token: "synthetic-7"), .init(epoch: 1, accountID: nil, role: nil, token: nil)] {
            grants.freeze = true; root.current = { identity }
            do { _ = try await clone.send(json("my", "{}")); XCTFail() } catch {}
        }
        XCTAssertEqual(wire.requests.count, before)
    }
    func testClonedTransportRejectsLateLeaseChangesAndTokenRotation() async throws {
        for transition in ["revoke", "replace", "expiry", "token", "roleABA"] {
            for code in [200, -1] {
                let wire = Wire(), grants = Grants(), root = try root(wire, grants, Vault()).transport()
                root.current = { .init(epoch: 1, accountID: 7, role: "player", token: "synthetic-7", viewerRevision: 1) }
                let clone = root.replacingUnderlying(wire).scopedForManualMap(ManualMapAreaSelection())
                wire.pause = true; let paused = expectation(description: "clone suspended"); wire.onPaused = { paused.fulfill() }
                let task = Task { try await clone.send(json("my", "{}")) }; await fulfillment(of: [paused], timeout: 2)
                let lease = try XCTUnwrap(grants.retained)
                switch transition {
                case "revoke": lease.revoke()
                case "replace": grants.retained = try .init(context: lease.context, expiresAt: Date().addingTimeInterval(600))
                case "expiry": lease.expireIfNeeded(now: lease.expiresAt)
                case "token": root.current = { .init(epoch: 1, accountID: 7, role: "player", token: "rotated", viewerRevision: 1) }
                default: root.current = { .init(epoch: 1, accountID: 7, role: "player", token: "synthetic-7", viewerRevision: 3) }
                }
                wire.finish(code: code)
                do { _ = try await task.value; XCTFail(transition) } catch { XCTAssertTrue(error is CancellationError, "\(error)") }
            }
        }
    }
    func testReadRefreshAndLogoutPreserveUnknownJournalInIsolatedStore() async throws {
        let wire = Wire(), grants = Grants(), composition = try root(wire, grants, Vault()), session = composition.makeSession()
        await login(session)
        let namespace = try XCTUnwrap(composition.reviewed?.storageScope.service)
        let account = try JSONDecoder().decode(Account.self, from: Data(#"{"id":7,"role":"player"}"#.utf8))
        let teamSession = try TeamSession(account: account, epoch: session.sessionRevision, region: "CN", storageNamespace: namespace, token: "synthetic-7")
        let journal = TeamDefaultsJournal(defaults: composition.storage.defaults)
        let record = TeamPendingRecord(operationID: UUID(), ownerKey: teamSession.ownerKey, targetKey: "team-61")
        try journal.write(record)
        let coordinator = session.makeTeamCoordinator(); await coordinator.loadDetail(.id(61)); XCTAssertEqual(coordinator.pending, record)
        XCTAssertEqual(coordinator.writeState, .unknown)
        grants.retained?.revoke(); await session.logout(); coordinator.synchronizeSession()
        XCTAssertEqual(try journal.pending(ownerKey: teamSession.ownerKey, targetKey: "team-61"), record)
    }
    private func json(_ path: String, _ body: String) -> URLRequest {
        var request = URLRequest(url: base.appendingPathComponent("api/team/" + path)); request.httpMethod = "POST"
        request.httpBody = Data(body.utf8); request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept"); request.setValue("synthetic-7", forHTTPHeaderField: "Authorization"); return request
    }
    @MainActor private final class Grants {
        var enabled = true, freeze = false; var retained: TeamReadApproval?
        func select(_ context: RuntimeDependencyContext) -> TeamReadApproval? {
            guard enabled else { return nil }
            if !freeze, retained == nil || !ContentDraftContextFence.matches(retained?.context, context) {
                retained?.revoke(); retained = try? .init(context: context, expiresAt: Date().addingTimeInterval(600))
            }
            return retained
        }
    }
    private final class Vault: AppTokenStorage { var value: String?; func read() throws -> String? { value }; func write(_ token: String) throws { value = token }; func clear() throws { value = nil } }
    private final class Wire: HTTPTransport {
        var requests: [URLRequest] = [], account = 7, role = "player", code = 200, pause = false, onPaused: (() -> Void)?
        var pending: CheckedContinuation<(Data, Int), Error>?, pendingJSON = "{}"
        func finish(code: Int) { let saved = pending; pending = nil; if code == -1 { saved?.resume(throwing: APIError.httpStatus(503)); return }; saved?.resume(returning: (Data((code == 200 ? pendingJSON : "{\"code\":\(code)}").utf8), 200)) }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request); let path = request.url!.path, json: String
            if path.hasSuffix("/phone") { json = "{\"code\":200,\"token\":\"synthetic-\(account)\",\"data\":{\"id\":\(account),\"role\":\"\(role)\"}}" }
            else if path.hasSuffix("/userInfo") { json = "{\"code\":200,\"appUser\":{\"userId\":\(account),\"role\":\"\(role)\"}}" }
            else if path.hasSuffix("/team/my") { json = "{\"code\":\(code),\"data\":[{\"id\":61,\"title\":\"Owned team\"}]}" }
            else { json = "{\"code\":\(code),\"data\":{\"team\":{\"id\":61,\"inviteCode\":\"invite-61\"},\"joined\":true,\"members\":[{\"memberId\":\(account)}]}}" }
            if path.contains("/team/"), pause { pendingJSON = json; return try await withCheckedThrowingContinuation { pending = $0; onPaused?() } }
            return (Data(json.utf8), 200)
        }
    }
}

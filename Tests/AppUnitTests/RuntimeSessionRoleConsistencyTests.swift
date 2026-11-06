import XCTest
@testable import Questify

/// Exercise the real root's login/account-refresh path, not a hand-built runtime context.
@MainActor final class RuntimeSessionRoleConsistencyTests: XCTestCase {
    func testActualLoginKeepsBothRuntimeRolesEqualToServerEffectiveRole() async throws {
        for role in ["player", "merchant", "club"] {
            let h = try Harness(role: role); defer { h.clean() }
            XCTAssertNil(h.session.currentRuntimeDependencyContext)
            await h.login()
            let context = try assertConsistent(h.session, expected: role)
            XCTAssertEqual(context.session.accountID, 7)
            XCTAssertEqual(context.session.token, "synthetic-role-token")
            XCTAssertTrue(h.wire.paths.contains { $0.hasSuffix("/phone") })
        }
    }

    func testEveryRealRoleTransitionRejectsGrantIssuedForPreviousContext() async throws {
        let roles = ["player", "merchant", "club"]
        for from in roles {
            for to in roles where to != from {
                let h = try Harness(role: from); defer { h.clean() }
                await h.login()
                let previous = try assertConsistent(h.session, expected: from)
                let grant = try WorkshopOwnedReadApproval(context: previous, expiresAt: .distantFuture)
                XCTAssertTrue(grant.matches(previous))
                h.wire.role = to
                await h.session.refreshOwnAccount()
                let current = try assertConsistent(h.session, expected: to)
                // Same account and credential: the role transition, not a new login, must fence the grant.
                XCTAssertEqual(current.session.accountID, previous.session.accountID)
                XCTAssertEqual(current.session.token, previous.session.token)
                XCTAssertNotEqual(current, previous)
                XCTAssertFalse(grant.matches(current))
                XCTAssertTrue(h.wire.paths.contains { $0.hasSuffix("/userInfo") })
                XCTAssertFalse(h.wire.paths.contains { $0.contains("/workshop/") })
            }
        }
    }

    func testMissingExplicitRoleUsesActualAccountEffectiveRoleInBothSnapshots() async throws {
        for (userType, expected) in [(1, "player"), (2, "merchant")] {
            let h = try Harness(role: "", userType: userType); defer { h.clean() }
            await h.login()
            let context = try assertConsistent(h.session, expected: expected)
            XCTAssertEqual(h.session.account?.role, "")
            XCTAssertEqual(context.session.role, h.session.account?.effectiveRole)
        }
    }

    func testLogoutRemovesRuntimeContextAndFreshLoginUsesNewRole() async throws {
        let h = try Harness(role: "merchant"); defer { h.clean() }
        await h.login()
        let previous = try assertConsistent(h.session, expected: "merchant")
        let grant = try WorkshopOwnedReadApproval(context: previous, expiresAt: .distantFuture)
        await h.session.logout()
        XCTAssertNil(h.session.currentRuntimeDependencyContext)
        h.wire.role = "club"
        await h.login()
        let current = try assertConsistent(h.session, expected: "club")
        XCTAssertFalse(grant.matches(current))
        XCTAssertGreaterThan(current.session.epoch, previous.session.epoch)
    }

    @discardableResult
    private func assertConsistent(_ session: AppSession, expected: String,
                                  file: StaticString = #filePath, line: UInt = #line) throws -> RuntimeDependencyContext {
        let account = try XCTUnwrap(session.account, file: file, line: line)
        let context = try XCTUnwrap(session.currentRuntimeDependencyContext, file: file, line: line)
        XCTAssertEqual(account.effectiveRole, expected, file: file, line: line)
        XCTAssertEqual(context.role, account.effectiveRole, file: file, line: line)
        XCTAssertEqual(context.session.role, account.effectiveRole, file: file, line: line)
        XCTAssertEqual(context.role, context.session.role, file: file, line: line)
        return context
    }

    @MainActor private final class Harness {
        let suite: String
        let wire: Wire
        let vault: Vault
        let session: AppSession
        init(role: String, userType: Int? = nil) throws {
            let suite = "runtime-role-consistency-" + UUID().uuidString
            let wire = Wire(role: role, userType: userType), vault = Vault()
            self.suite = suite; self.wire = wire; self.vault = vault
            let base = "https://example.test/runtime-role-consistency"
            let deployment = try ReviewedAppDeployment(market: .china, baseURL: base,
                approvedBaseURLs: [.china: [base]], verifiedCapabilities: [.domesticChinaPhone],
                bundleIdentifier: "test.runtime-role-consistency", realm: "synthetic")
            let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
            session = AppCompositionRoot(deployment: .reviewed(deployment),
                storage: .init(defaults: defaults, tokenStore: { _ in vault }),
                makeTransport: { wire }).makeSession()
        }
        func login() async {
            session.authChannels.cancel()
            await session.authChannels.loginWithPhone(phone: "10000000000", code: "123456")
        }
        func clean() { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
    }
    @MainActor private final class Vault: AppTokenStorage {
        var token: String?
        func read() throws -> String? { token }
        func write(_ value: String) throws { token = value }
        func clear() throws { token = nil }
    }
    @MainActor private final class Wire: HTTPTransport {
        var role: String
        let userType: Int?
        private(set) var paths: [String] = []
        init(role: String, userType: Int?) { self.role = role; self.userType = userType }
        func send(_ request: URLRequest) async throws -> (Data, Int) {
            let path = request.url?.path ?? ""; paths.append(path)
            var account: [String: Any] = ["id": 7, "userId": 7, "role": role]
            if let userType { account["userType"] = userType }
            let body: [String: Any]
            if path.hasSuffix("/phone") {
                body = ["code": 200, "token": "synthetic-role-token", "data": account]
            } else if path.hasSuffix("/userInfo") {
                body = ["code": 200, "appUser": account]
            } else if path.hasSuffix("/logout") {
                body = ["code": 200]
            } else {
                XCTFail("Unexpected request in role regression: \(path)")
                throw APIError.notConfigured
            }
            return (try JSONSerialization.data(withJSONObject: body), 200)
        }
    }
}

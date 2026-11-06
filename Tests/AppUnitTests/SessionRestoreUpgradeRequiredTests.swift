import Foundation
import XCTest
@testable import Questify

private final class RestoreUpgradeVault: AppTokenStorage {
    var value: String? = "synthetic-saved-token"
    var clears = 0
    func read() throws -> String? { value }
    func write(_ token: String) throws { value = token }
    func clear() throws { clears += 1; value = nil }
}
private final class RestoreUpgradeTransport: HTTPTransport {
    let status: Int
    var requests: [URLRequest] = []
    var deferred = false
    var pending: CheckedContinuation<(Data, Int), Error>?
    var observer: CheckedContinuation<Void, Never>?
    init(_ status: Int) { self.status = status }
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        if deferred {
            return try await withCheckedThrowingContinuation {
                pending = $0; observer?.resume(); observer = nil
            }
        }
        return (Data(), status)
    }
    func waitForRequest() async {
        if pending != nil { return }
        await withCheckedContinuation { observer = $0 }
    }
}

@MainActor final class SessionRestoreUpgradeRequiredTests: XCTestCase {
    private func root(_ transport: RestoreUpgradeTransport, _ vault: RestoreUpgradeVault)
        throws -> (AppCompositionRoot, ReviewedAppDeployment, UserDefaults) {
        let suite = "restore-upgrade-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let deployment = try ReviewedAppDeployment(market: .china,
            baseURL: "https://example.test/native", approvedBaseURLs: [.china: ["https://example.test/native"]],
            verifiedCapabilities: [.domesticChinaPhone], bundleIdentifier: "test.restore.upgrade", realm: "offline")
        let storage = AppScopedStorageFactory(defaults: defaults, tokenStore: { _ in vault })
        return (AppCompositionRoot(deployment: .reviewed(deployment), storage: storage,
                                  makeTransport: { transport }), deployment, defaults)
    }

    func testBootstrap426PreservesSavedCredentialAndOriginalUnknownRecord() async throws {
        let transport = RestoreUpgradeTransport(426), vault = RestoreUpgradeVault()
        let (root, deployment, defaults) = try root(transport, vault)
        let owner = "registration|\(deployment.storageScope.service)|CN|https://example.test/native|7"
        let original = OperationPendingRecord(ownerKey: owner, targetKey: "create|10|20")
        let journal = OperationDefaultsJournal(defaults: defaults)
        try journal.write(original)
        let session = root.makeSession()
        await session.bootstrap()
        XCTAssertNil(session.account)
        XCTAssertEqual(session.errorKey, "auth.channels.upgradeRequired")
        XCTAssertEqual(vault.value, "synthetic-saved-token")
        XCTAssertEqual(vault.clears, 0)
        XCTAssertFalse(defaults.bool(forKey: deployment.storageScope.restoreBlockedKey))
        XCTAssertEqual(try journal.pending(ownerKey: owner, targetKey: original.targetKey), original)
        XCTAssertEqual(transport.requests.count, 1)
        await session.bootstrap()
        XCTAssertEqual(transport.requests.count, 1, "No automatic retry or duplicate bootstrap")
    }

    func test401StillBlocksRestoreAndClearsCredential() async throws {
        let transport = RestoreUpgradeTransport(401), vault = RestoreUpgradeVault()
        let (root, deployment, defaults) = try root(transport, vault)
        let session = root.makeSession()
        await session.bootstrap()
        XCTAssertEqual(session.errorKey, "auth.expired")
        XCTAssertNil(vault.value)
        XCTAssertTrue(defaults.bool(forKey: deployment.storageScope.restoreBlockedKey))
        XCTAssertEqual(vault.clears, 1)
    }

    func testOtherServerFailureRemainsNetworkAndPreservesCredential() async throws {
        let transport = RestoreUpgradeTransport(503), vault = RestoreUpgradeVault()
        let (root, deployment, defaults) = try root(transport, vault)
        let session = root.makeSession()
        await session.bootstrap()
        XCTAssertEqual(session.errorKey, "auth.networkError")
        XCTAssertEqual(vault.value, "synthetic-saved-token")
        XCTAssertEqual(vault.clears, 0)
        XCTAssertFalse(defaults.bool(forKey: deployment.storageScope.restoreBlockedKey))
    }

    func testLogoutDuringRestoreCannotBeOverwrittenByLate426() async throws {
        let transport = RestoreUpgradeTransport(426), vault = RestoreUpgradeVault()
        transport.deferred = true
        let (root, deployment, defaults) = try root(transport, vault)
        let session = root.makeSession()
        let task = Task { await session.bootstrap() }
        await transport.waitForRequest()
        await session.logout()
        transport.pending?.resume(returning: (Data(), 426)); transport.pending = nil
        await task.value
        XCTAssertNil(session.account)
        XCTAssertNil(session.errorKey)
        XCTAssertNil(vault.value)
        XCTAssertTrue(defaults.bool(forKey: deployment.storageScope.restoreBlockedKey))
        XCTAssertEqual(transport.requests.count, 1)
        await root.makeSession().bootstrap()
        XCTAssertEqual(transport.requests.count, 1, "Cold restart must honor the logout tombstone")
    }
}

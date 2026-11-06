import Foundation
import XCTest
@testable import Questify

@MainActor final class WelcomeUpgradePresentationTests: XCTestCase {
    func testSignedOutUpgradeIsVisibleWithoutOpeningLogin() {
        XCTAssertEqual(WelcomeSessionPresentation.upgradeNoticeKey(errorKey: "auth.channels.upgradeRequired", accountID: nil), "auth.channels.upgradeRequired")
    }
    func testOrdinaryGuestAndErrorsKeepExistingPresentation() {
        let keys: [String?] = [nil, "auth.networkError", "auth.expired", "auth.notConfigured", "auth.storageError"]
        for key in keys {
            XCTAssertNil(WelcomeSessionPresentation.upgradeNoticeKey(errorKey: key, accountID: nil))
        }
    }
    func testRestoredAccountDoesNotShowStaleSignedOutNotice() {
        XCTAssertNil(WelcomeSessionPresentation.upgradeNoticeKey(errorKey: "auth.channels.upgradeRequired", accountID: 7))
    }
    func testRealBootstrap426FeedsWelcomeWithoutClearingSavedToken() async throws {
        let suite = "welcome-upgrade-" + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let vault = WelcomeUpgradeVault(), wire = WelcomeUpgradeWire()
        let deployment = try ReviewedAppDeployment(market: .china,
            baseURL: "https://example.test/native", approvedBaseURLs: [.china: ["https://example.test/native"]],
            verifiedCapabilities: [.domesticChinaPhone], bundleIdentifier: "test.welcome.upgrade", realm: "offline")
        let storage = AppScopedStorageFactory(defaults: defaults, tokenStore: { _ in vault })
        let root = AppCompositionRoot(deployment: .reviewed(deployment), storage: storage, makeTransport: { wire })
        let session = root.makeSession()
        await session.bootstrap()
        XCTAssertEqual(WelcomeSessionPresentation.upgradeNoticeKey(errorKey: session.errorKey, accountID: session.account?.id), "auth.channels.upgradeRequired")
        XCTAssertEqual(vault.value, "synthetic-saved-token")
        XCTAssertEqual(vault.clears, 0)
        XCTAssertFalse(defaults.bool(forKey: deployment.storageScope.restoreBlockedKey))
        XCTAssertTrue(session.restorationFinished)
        XCTAssertEqual(wire.requests.count, 1)
        await session.bootstrap()
        XCTAssertEqual(wire.requests.count, 1)
    }
}
private final class WelcomeUpgradeVault: AppTokenStorage {
    var value: String? = "synthetic-saved-token"
    var clears = 0
    func read() throws -> String? { value }
    func write(_ token: String) throws { value = token }
    func clear() throws { clears += 1; value = nil }
}
private final class WelcomeUpgradeWire: HTTPTransport {
    var requests: [URLRequest] = []
    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        return (Data(), 426)
    }
}

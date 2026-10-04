import XCTest
import Security
@testable import Questify

#if targetEnvironment(simulator)
/// Unique synthetic services and scoped temporary directories only. No production factory I/O.
@MainActor final class PlayRecoverySystemStorageTests: XCTestCase {
    private func session() throws -> PlayExperienceSession { try .init(accountID: 9001, epoch: 1, namespace: "synthetic-os-only", token: "NEVER-PERSIST-SYNTHETIC-TOKEN") }
    private func deleteSyntheticService(_ service: String) {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
            kSecAttrSynchronizable as String: false, kSecUseDataProtectionKeychain as String: true]
        let status = SecItemDelete(query as CFDictionary); XCTAssertTrue(status == errSecSuccess || status == errSecItemNotFound)
    }
    func testRealNonClassADirectoryRejectsRecoveryWithoutFilesOrKeychainWrites() async throws {
        let service = "questify.tests.play-non-class-a." + UUID().uuidString
        defer { deleteSyntheticService(service) }
        try await NonClassAStorageFixture.withDirectory { root in
            let session = try session(), key = PlayRunStorageKey.make(session: session, scope: .activity(41))
            let journal = try PlayDurableRecovery(owner: .init(session: session), key: key,
                anchors: ContentDraftSystemAnchors(service: service), ciphertexts: ContentDraftSystemCiphertexts(root: root))
            let intent = PlayCompletionIntent(review: .init(nodeID: 701, evidence: .answer("synthetic"),
                advance: nil, session: session, generation: 1, routeSessionID: nil))
            func assertNoWrites() throws {
                try NonClassAStorageFixture.assertUnchanged(root)
                let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service, kSecAttrSynchronizable as String: false,
                    kSecUseDataProtectionKeychain as String: true, kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail]
                XCTAssertEqual(SecItemCopyMatching(query as CFDictionary, nil), errSecItemNotFound,
                               "Rejected recovery must not create any synthetic-service anchor")
            }
            try assertNoWrites()
            do { _ = try await journal.read(key); XCTFail("Non-A recovery read accepted") }
            catch { XCTAssertEqual(error as? PlayExperienceError, .persistenceUnavailable) }
            try assertNoWrites()
            do { _ = try await journal.prepare(intent, key: key); XCTFail("Non-A recovery prepare accepted") }
            catch { XCTAssertEqual(error as? PlayExperienceError, .persistenceUnavailable) }
            try assertNoWrites()
            do { _ = try await journal.read(key: key); XCTFail("Non-A paused recovery read accepted") }
            catch { XCTAssertEqual(error as? PlayExperienceError, .persistenceUnavailable) }
            try assertNoWrites()
        }
    }
    func testFactoryRejectsMismatchedNamespaceAndRegionBeforeOSConstruction() throws {
        let cn = try RegionalConfiguration(market: .china, baseURL: "https://cn.example.com", approvedBaseURLs: [.china: ["https://cn.example.com"]])
        let us = try RegionalConfiguration(market: .unitedStates, baseURL: "https://us.example.com", approvedBaseURLs: [.unitedStates: ["https://us.example.com"]])
        let scope = try RegionalSessionStorageScope(configuration: cn, bundleIdentifier: "synthetic.tests", realm: "synthetic")
        let matching = try PlayExperienceSession(accountID: 9001, epoch: 1, namespace: scope.service, token: "synthetic")
        XCTAssertThrowsError(try PlayRecoveryComposition.make(session: session(), scope: .activity(41), regionalConfiguration: cn, storageScope: scope))
        XCTAssertThrowsError(try PlayRecoveryComposition.make(session: matching, scope: .activity(41), regionalConfiguration: us, storageScope: scope))
    }
}
#endif

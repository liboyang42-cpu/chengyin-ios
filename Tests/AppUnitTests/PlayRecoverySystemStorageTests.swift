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
    func testConcreteOSRelaunchCASAndNoPlaintextOrCredentialFiles() async throws {
        let service = "questify.tests.play-recovery." + UUID().uuidString
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("play-test-" + UUID().uuidString)
        defer { deleteSyntheticService(service); try? FileManager.default.removeItem(at: root) }
        let session = try session(), key = PlayRunStorageKey.make(session: session, scope: .activity(41))
        func make() throws -> PlayDurableRecovery { try .init(owner: .init(session: session), key: key, anchors: ContentDraftSystemAnchors(service: service), ciphertexts: ContentDraftSystemCiphertexts(root: root)) }
        let one = try make(), two = try make(); XCTAssertFalse(one.isSystemBacked)
        let intent = PlayCompletionIntent(review: .init(nodeID: 701, evidence: .answer("SYNTHETIC-PRIVATE-ANSWER"), advance: try .init(actionID: "synthetic-action", expectedVersion: 2), session: session, generation: 1, routeSessionID: 601))
        let initial = try await one.prepare(intent, key: key), dispatched = try await one.transition(initial, to: .dispatching, key: key)
        do { _ = try await two.transition(initial, to: .dispatching, key: key); XCTFail("Stale OS generation accepted") } catch {}
        let reopened = try make(), restored = try await reopened.read(key); XCTAssertEqual(restored, dispatched)
        for url in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            let bytes = try Data(contentsOf: url); XCTAssertNil(bytes.range(of: Data("SYNTHETIC-PRIVATE-ANSWER".utf8))); XCTAssertNil(bytes.range(of: Data(session.token.utf8)))
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            XCTAssertEqual(attributes[.posixPermissions] as? NSNumber, NSNumber(value: 0o600)); XCTAssertEqual(attributes[.protectionKey] as? String, FileProtectionType.complete.rawValue)
        }
        try await reopened.clear(dispatched, key: key); let empty = try await make().read(key); XCTAssertNil(empty)
    }
    func testMissingKeychainAfterWrittenPresenceFailsClosedWithoutReplacement() async throws {
        let service = "questify.tests.play-lost." + UUID().uuidString
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("play-lost-" + UUID().uuidString)
        defer { deleteSyntheticService(service); try? FileManager.default.removeItem(at: root) }
        let session = try session(), key = PlayRunStorageKey.make(session: session, scope: .activity(41))
        func make() throws -> PlayDurableRecovery { try .init(owner: .init(session: session), key: key, anchors: ContentDraftSystemAnchors(service: service), ciphertexts: ContentDraftSystemCiphertexts(root: root)) }
        let journal = try make(), empty = try await journal.read(key: key)
        _ = try await journal.write(.init(owner: .init(session: session), record: .init(elapsedSeconds: 10, savedAt: 100)), replacing: empty, key: key)
        deleteSyntheticService(service); let reopened = try make()
        do { _ = try await reopened.read(key: key); XCTFail("Lost Keychain state became fresh") } catch { XCTAssertEqual(error as? PlayExperienceError, .persistenceUnavailable) }
        do { _ = try await reopened.write(.init(owner: .init(session: session), record: nil, tombstone: 100), replacing: empty, key: key); XCTFail("Lost state replaced") } catch { XCTAssertEqual(error as? PlayExperienceError, .persistenceUnavailable) }
    }
    func testPartialCiphertextAndForeignRoleNeverUnlockOSPending() async throws {
        let service = "questify.tests.play-corrupt." + UUID().uuidString
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("play-corrupt-" + UUID().uuidString)
        defer { deleteSyntheticService(service); try? FileManager.default.removeItem(at: root) }
        let session = try session(), key = PlayRunStorageKey.make(session: session, scope: .activity(41))
        let anchors = ContentDraftSystemAnchors(service: service), blobs = ContentDraftSystemCiphertexts(root: root)
        let journal = try PlayDurableRecovery(owner: .init(session: session), key: key, anchors: anchors, ciphertexts: blobs)
        let value = PlayCompletionIntent(review: .init(nodeID: 701, evidence: .answer("synthetic"), advance: nil, session: session, generation: 1, routeSessionID: nil))
        _ = try await journal.prepare(value, key: key)
        let foreign = try PlayExperienceSession(accountID: session.accountID, epoch: 2, namespace: session.namespace, token: "synthetic-new-token", role: "merchant")
        let alias = try PlayDurableRecovery(owner: .init(session: foreign), key: key, anchors: anchors, ciphertexts: blobs)
        do { _ = try await alias.read(key); XCTFail("Foreign role accepted") } catch {}
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil), blob = try XCTUnwrap(files.first { !$0.lastPathComponent.hasSuffix(".presence") })
        let handle = try FileHandle(forWritingTo: blob); try handle.truncate(atOffset: 10); try handle.synchronize(); try handle.close()
        do { _ = try await journal.read(key); XCTFail("Truncated ciphertext unlocked") } catch { XCTAssertEqual(error as? PlayExperienceError, .persistenceUnavailable) }
        do { _ = try await journal.prepare(value, key: key); XCTFail("Corrupt pending overwritten") } catch { XCTAssertEqual(error as? PlayExperienceError, .persistenceUnavailable) }
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

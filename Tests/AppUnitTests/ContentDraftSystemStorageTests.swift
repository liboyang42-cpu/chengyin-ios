import XCTest
import Security
@testable import Questify

#if targetEnvironment(simulator)
/// Opt-in Apple execution only: unique synthetic service/key and temporary ciphertext directory.
/// No real account, user Keychain namespace, backend, or device lock manipulation.
@MainActor final class ContentDraftSystemStorageTests: XCTestCase {
    func testRealGenerationCASAndConditionalDelete() async throws {
        let service = "questify.tests.content-draft." + UUID().uuidString, slot = UUID().uuidString
        let store = ContentDraftSystemAnchors(service: service)
        let first = ContentDraftAnchorItem(bytes: Data("synthetic first".utf8), tag: Data(repeating: 1, count: 32))
        let second = ContentDraftAnchorItem(bytes: Data("synthetic second".utf8), tag: Data(repeating: 2, count: 32))
        let added = try await store.insert(slot: slot, item: first)
        XCTAssertTrue(added); guard added else { return }
        defer {
            let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                kSecAttrAccount as String: slot, kSecAttrSynchronizable as String: false, kSecUseDataProtectionKeychain as String: true]
            let result = SecItemDelete(query as CFDictionary)
            XCTAssertTrue(result == errSecSuccess || result == errSecItemNotFound)
        }
        let duplicate = try await store.insert(slot: slot, item: second); XCTAssertFalse(duplicate)
        let read = try await store.read(slot: slot); XCTAssertEqual(read, first) // also verifies protection attributes
        let wrong = try await store.exchange(slot: slot, matchingTag: second.tag, item: first); XCTAssertFalse(wrong)
        let changed = try await store.exchange(slot: slot, matchingTag: first.tag, item: second); XCTAssertTrue(changed)
        let stale = try await store.remove(slot: slot, matchingTag: first.tag); XCTAssertFalse(stale)
        let kept = try await store.read(slot: slot); XCTAssertEqual(kept, second)
        let removed = try await store.remove(slot: slot, matchingTag: second.tag); XCTAssertTrue(removed)
    }
    func testRealExclusiveCiphertextFileBoundedReadAndCleanup() async throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("questify-draft-test-" + UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ContentDraftSystemCiphertexts(root: root), name = UUID().uuidString
        let bytes = Data(repeating: 0xA7, count: 524_288) // synthetic ciphertext-shaped bytes only
        try await store.insert(name: name, bytes: bytes)
        do { try await store.insert(name: name, bytes: Data([0])); XCTFail("Expected exclusive-create failure") } catch {}
        let reopened = ContentDraftSystemCiphertexts(root: root)
        let restored = try await reopened.readDurably(name: name, limit: 4_194_304); XCTAssertEqual(restored, bytes)
        do { _ = try await reopened.readDurably(name: name, limit: 8_192); XCTFail("Expected bounded-read failure") } catch {}
        let attributes = try FileManager.default.attributesOfItem(atPath: root.appendingPathComponent(name).path)
        XCTAssertEqual(attributes[.posixPermissions] as? NSNumber, NSNumber(value: 0o600))
        XCTAssertEqual(attributes[.protectionKey] as? String, FileProtectionType.complete.rawValue)
        try await reopened.removeDurably(name: name)
        try await reopened.removeDurably(name: name)
    }
    func testRealPresenceMarkerIsExclusivePermanentAndEmpty() async throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("questify-draft-marker-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ContentDraftSystemCiphertexts(root: root), slot = String(repeating: "a", count: 64)
        let absent = try await store.hasPresence(slot: slot); XCTAssertFalse(absent)
        let first = try await store.createPresence(slot: slot), second = try await store.createPresence(slot: slot)
        XCTAssertTrue(first); XCTAssertFalse(second)
        let reopened = ContentDraftSystemCiphertexts(root: root)
        let present = try await reopened.hasPresence(slot: slot); XCTAssertTrue(present)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(slot + ".presence")).count, 0)
    }
    func testRealSymlinkAncestorIsRejectedWithoutTouchingTarget() async throws {
        let base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("questify-draft-links-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: base) }
        let outside = base.appendingPathComponent("outside"), link = base.appendingPathComponent("link")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside)
        let store = ContentDraftSystemCiphertexts(root: link.appendingPathComponent("journal"))
        do { _ = try await store.createPresence(slot: String(repeating: "a", count: 64)); XCTFail("Expected no-follow failure") } catch {}
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.appendingPathComponent("journal").path))
    }
    func testRealWeakExistingDirectoryIsRejectedWithoutPermissionRepair() async throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("questify-draft-mode-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
        let store = ContentDraftSystemCiphertexts(root: root)
        do { _ = try await store.createPresence(slot: String(repeating: "a", count: 64)); XCTFail("Expected owner-only directory requirement") } catch {}
        let attributes = try FileManager.default.attributesOfItem(atPath: root.path)
        XCTAssertEqual(attributes[.posixPermissions] as? NSNumber, NSNumber(value: 0o755))
    }

}
#endif

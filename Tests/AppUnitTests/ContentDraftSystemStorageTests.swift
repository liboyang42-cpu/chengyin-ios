import XCTest
import Security
import Darwin
@testable import Questify

#if targetEnvironment(simulator)
/// Opt-in Apple execution only: unique synthetic service/key and temporary ciphertext directory.
/// No real account, user Keychain namespace, backend, or device lock manipulation.
@MainActor final class ContentDraftSystemStorageTests: XCTestCase {
    func testRealNonClassADirectoryRejectsEveryFileOperationWithoutWriting() async throws {
        try await NonClassAStorageFixture.withDirectory { root in
            let store = ContentDraftSystemCiphertexts(root: root)
            let name = UUID().uuidString, slot = String(repeating: "a", count: 64)
            func rejects(_ operation: () async throws -> Void) async throws {
                do { try await operation(); XCTFail("Non-A directory accepted by Class A store") }
                catch { XCTAssertEqual(error as? ContentDraftIssue, .storageUnavailable) }
                try await NonClassAStorageFixture.assertUnchanged(root)
            }
            try await rejects { try await store.insert(name: name, bytes: Data([0xA7])) }
            try await rejects { _ = try await store.createPresence(slot: slot) }
            try await rejects { _ = try await store.hasPresence(slot: slot) }
            try await rejects { _ = try await store.readDurably(name: name, limit: 16) }
            try await rejects { try await store.removeDurably(name: name) }
        }
    }
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

/// Real, uniquely owned OS directory with a verified non-A class. Never a production bypass.
@MainActor enum NonClassAStorageFixture {
    private enum FixtureFailure: Error { case prerequisite }
    static func withDirectory(_ body: (URL) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("questify-non-class-a-" + UUID().uuidString, isDirectory: true)
        let components = root.pathComponents.filter { $0 != "/" }
        guard let leaf = components.last, root.isFileURL, root.path != "/",
              root.path == root.standardizedFileURL.path,
              !components.contains(".."), !components.contains(".") else { throw FixtureFailure.prerequisite }
        var parent = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard parent >= 0 else { throw FixtureFailure.prerequisite }
        defer { Darwin.close(parent) }
        for component in components.dropLast() {
            let next = openat(parent, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard next >= 0 else { throw FixtureFailure.prerequisite }
            Darwin.close(parent); parent = next
        }
        guard mkdirat(parent, leaf, mode_t(0o700)) == 0 else { throw FixtureFailure.prerequisite }
        defer {
            // Only the exclusively created UUID leaf is ours. Unexpected files make cleanup fail.
            XCTAssertEqual(unlinkat(parent, leaf, AT_REMOVEDIR), 0, "Non-A fixture must remain empty")
        }
        let directory = openat(parent, leaf, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directory >= 0 else { throw FixtureFailure.prerequisite }
        defer { Darwin.close(directory) }
        var info = stat()
        guard fstat(directory, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR,
              info.st_uid == geteuid(), info.st_mode & 0o777 == 0o700 else { throw FixtureFailure.prerequisite }
        // Class C is an intentionally invalid fixture for a Class A contract, never an alias for A.
        guard fcntl(directory, F_SETPROTECTIONCLASS, Int32(3)) == 0 else { throw FixtureFailure.prerequisite }
        let protection = fcntl(directory, F_GETPROTECTIONCLASS)
        print("Synthetic fail-closed fixture stage=non-class-a-directory result=\(protection)")
        guard protection == 3 else { throw FixtureFailure.prerequisite }
        try assertUnchanged(root)
        try await body(root)
        XCTAssertEqual(fcntl(directory, F_GETPROTECTIONCLASS), 3, "Production must not repair protection")
        try assertUnchanged(root)
    }
    static func assertUnchanged(_ root: URL, file: StaticString = #filePath, line: UInt = #line) throws {
        let contents = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        XCTAssertTrue(contents.isEmpty, "Rejected storage must not create ciphertext or presence files", file: file, line: line)
    }
}
#endif
